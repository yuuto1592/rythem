extends Node2D

## The gameplay loop: spawn notes as they come into view, move them with the
## conductor's clock, and turn key presses into judgements.
##
## Nothing here keeps its own idea of time. Every position and every judgement
## is derived from [member Conductor.chart_time], which is why the game stays
## in sync even if a frame takes too long.

## Emitted once the chart is over, with the same dictionary that is left in
## GameState.last_result.
signal run_finished(result: Dictionary)
## Emitted for every judgement: a tap, the head of a hold, or its tail. The hook
## for hit effects.
signal note_judged(lane: int, rank: Judge.Rank, is_tail: bool)

## Seconds of quiet after the last note before the result screen appears.
const OUTRO := 1.5

@onready var _conductor: Conductor = $Conductor
@onready var _playfield: Playfield = $Playfield
@onready var _notes_root: Node2D = $Playfield/Notes
@onready var _hud: Hud = $HudLayer/Hud

var _chart: Chart
## Notes that are on screen and not finished yet, oldest first.
var _active: Array[Note] = []
## How far into Chart.notes we have spawned.
var _spawn_index := 0
## The hold whose key is down in each lane, if any. Lane -> Note.
var _held := {}
## Chart.judgement_count(), cached: the denominator of the score.
var _total_judgements := 0

var _counts := {}
var _combo := 0
var _max_combo := 0
## Sum of Judge.WEIGHT over judged notes; the basis for score and accuracy.
var _earned := 0.0
var _judged := 0
var _autoplay := false
var _running := false

func _ready() -> void:
	for rank in Judge.RANK_NAME:
		_counts[rank] = 0

	_chart = Chart.load_from_file(GameState.chart_path)
	if _chart == null:
		# Nothing to play; the menu is the only sensible place to go.
		_leave_to(GameState.MENU_SCENE)
		return

	_autoplay = GameState.autoplay
	_total_judgements = _chart.judgement_count()
	KeyBinds.ensure_actions(_chart.lane_count)
	_playfield.configure(_chart.lane_count, _chart.scroll_time)

	_conductor.bpm = _chart.bpm
	_conductor.offset = _chart.offset
	_conductor.set_music(_load_music())
	_conductor.beat_hit.connect(_on_beat_hit)
	_conductor.finished.connect(_on_song_finished)

	_hud.set_song(_chart.title, _chart.artist)
	_hud.set_hint("%s  ·  R: retry  ·  F1: autoplay  ·  Esc: menu" % KeyBinds.lane_hint(_chart.lane_count))
	_hud.set_autoplay(_autoplay)
	_refresh_hud()

	_running = true
	_conductor.start(_chart.length() + OUTRO)

func _process(_delta: float) -> void:
	if not _running:
		return
	var now := _conductor.chart_time
	_spawn_due_notes(now)
	_advance_notes(now)
	_hud.set_progress(now / maxf(_chart.length(), 0.001))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_to_menu()
		return
	if event.is_action_pressed(&"restart"):
		get_tree().reload_current_scene()
		return
	if event.is_action_pressed(&"toggle_autoplay"):
		_autoplay = not _autoplay
		_hud.set_autoplay(_autoplay)
		return
	if not _running or _autoplay:
		return
	for lane in _chart.lane_count:
		var action := KeyBinds.lane_action(lane)
		if event.is_action_pressed(action):
			_playfield.flash(lane)
			_press_lane(lane)
			return
		if event.is_action_released(action):
			_release_lane(lane)
			return

## Spawns everything that is now within one scroll length of the judge line.
func _spawn_due_notes(now: float) -> void:
	while _spawn_index < _chart.notes.size():
		var chart_note := _chart.notes[_spawn_index]
		if chart_note.time - now > _chart.scroll_time:
			break
		var note := Note.new()
		note.setup(chart_note.time, chart_note.end_time, chart_note.lane, _playfield.lane_color(chart_note.lane))
		_notes_root.add_child(note)
		_active.append(note)
		_spawn_index += 1

## Moves live notes, retires the ones that are finished, and judges whatever
## time alone decides: missed heads, holds kept down to the end, and autoplay.
func _advance_notes(now: float) -> void:
	var index := 0
	while index < _active.size():
		var note := _active[index]
		_judge_by_time(note, now)

		if note.done:
			note.queue_free()
			_active.remove_at(index)
			continue

		# A held note's head stays on the judge line while its body runs out.
		var head_in := 0.0 if note.holding else note.time - now
		note.place(_playfield.lane_x(note.lane), _playfield.y_for(head_in), _playfield.y_for(note.end_time - now))
		index += 1

func _judge_by_time(note: Note, now: float) -> void:
	if not note.head_judged:
		var late := now - note.time
		if _autoplay and late >= 0.0:
			_judge_head(note, 0.0)
		elif late > Judge.hit_window():
			_judge_head(note, late)
	elif note.holding:
		_playfield.flash(note.lane)
		# Kept down all the way: the tail is as good as a release right on time.
		if now >= note.end_time:
			_judge_tail(note, 0.0)

## Judges the head of the note closest to the judge line in [param lane]. A
## press with no note in range is ignored rather than punished.
func _press_lane(lane: int) -> void:
	var now := _conductor.chart_time
	var target: Note = null
	var best := INF
	for note in _active:
		if note.lane != lane or note.head_judged:
			continue
		var distance := absf(now - note.time)
		if distance < best:
			best = distance
			target = note
	if target != null and best <= Judge.hit_window():
		_judge_head(target, now - target.time)

## Letting go of a hold before its end judges the tail by how early it was.
## Letting go afterwards does nothing: the tail already completed itself.
func _release_lane(lane: int) -> void:
	var note: Note = _held.get(lane)
	if note != null:
		_judge_tail(note, _conductor.chart_time - note.end_time)

func _judge_head(note: Note, error: float) -> void:
	note.head_judged = true
	var rank := Judge.rank_for(error)
	_record(rank, note.lane, false)
	if not note.is_hold():
		_finish(note)
	elif rank == Judge.Rank.MISS:
		# Missing the head drops the whole hold, tail included.
		_record(Judge.Rank.MISS, note.lane, true)
		_finish(note)
	else:
		note.holding = true
		_held[note.lane] = note

func _judge_tail(note: Note, error: float) -> void:
	_record(Judge.rank_for(error), note.lane, true)
	_finish(note)

func _finish(note: Note) -> void:
	if note.holding:
		note.holding = false
		_held.erase(note.lane)
	note.done = true
	note.visible = false

func _record(rank: Judge.Rank, lane: int, is_tail: bool) -> void:
	_counts[rank] += 1
	_judged += 1
	_earned += Judge.WEIGHT[rank]

	if rank == Judge.Rank.MISS:
		_combo = 0
		Sfx.play_miss()
	else:
		_combo += 1
		_max_combo = maxi(_max_combo, _combo)
		Sfx.play_hit()

	_hud.show_judgement(rank)
	_refresh_hud()
	note_judged.emit(lane, rank, is_tail)

func _refresh_hud() -> void:
	_hud.set_score(_score())
	_hud.set_accuracy(_accuracy())
	_hud.set_combo(_combo)

## Normalised so an all-CRITICAL run is always Judge.MAX_SCORE, whatever the
## note count.
func _score() -> int:
	if _total_judgements == 0:
		return 0
	return int(round(Judge.MAX_SCORE * _earned / float(_total_judgements)))

func _accuracy() -> float:
	return _earned / float(_judged) if _judged > 0 else 0.0

func _on_beat_hit(_beat_index: int) -> void:
	# Without music the metronome is the only tempo reference the player gets.
	if not _conductor.has_music():
		Sfx.play_tick()

func _on_song_finished() -> void:
	_running = false
	var result := _build_result()
	GameState.last_result = result
	run_finished.emit(result)
	_leave_to(GameState.RESULT_SCENE)

func _build_result() -> Dictionary:
	var accuracy := _accuracy()
	return {
		"title": _chart.title,
		"artist": _chart.artist,
		"score": _score(),
		"accuracy": accuracy,
		"grade": Judge.grade_for(accuracy),
		"max_combo": _max_combo,
		"note_count": _chart.notes.size(),
		"judgement_count": _total_judgements,
		"counts": _counts.duplicate(),
		"autoplay": _autoplay,
		"full_combo": _counts[Judge.Rank.MISS] == 0 and _judged == _total_judgements,
	}

func _load_music() -> AudioStream:
	if _chart.music_path.is_empty() or not ResourceLoader.exists(_chart.music_path):
		return null
	return ResourceLoader.load(_chart.music_path) as AudioStream

func _to_menu() -> void:
	_conductor.stop()
	_running = false
	_leave_to(GameState.MENU_SCENE)

## Scene changes only happen when this is the scene being played. Embedded in
## another scene (the tests do this) the host stays in charge of navigation.
func _leave_to(scene_path: String) -> void:
	if get_tree().current_scene == self:
		get_tree().change_scene_to_file.call_deferred(scene_path)

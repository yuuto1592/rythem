extends Node2D

## The gameplay loop: spawn notes as they come into view, move them with the
## conductor's clock, and turn key presses into judgements.
##
## Nothing here keeps its own idea of time. Every position and every judgement
## is derived from [member Conductor.chart_time], which is why the game stays
## in sync even if a frame takes too long.

## Seconds of quiet after the last note before the result screen appears.
const OUTRO := 1.5

@onready var _conductor: Conductor = $Conductor
@onready var _playfield: Playfield = $Playfield
@onready var _notes_root: Node2D = $Playfield/Notes
@onready var _hud: Hud = $HudLayer/Hud

var _chart: Chart
## Notes that are on screen and not judged yet, oldest first.
var _active: Array[Note] = []
## How far into Chart.notes we have spawned.
var _spawn_index := 0

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
		get_tree().change_scene_to_file.call_deferred(GameState.MENU_SCENE)
		return

	_autoplay = GameState.autoplay
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
		if event.is_action_pressed(KeyBinds.lane_action(lane)):
			_playfield.flash(lane)
			_hit_lane(lane)
			return

## Spawns everything that is now within one scroll length of the judge line.
func _spawn_due_notes(now: float) -> void:
	while _spawn_index < _chart.notes.size():
		var chart_note := _chart.notes[_spawn_index]
		if chart_note.time - now > _chart.scroll_time:
			break
		var note := Note.new()
		note.setup(chart_note.time, chart_note.lane, _playfield.lane_color(chart_note.lane))
		_notes_root.add_child(note)
		_active.append(note)
		_spawn_index += 1

## Moves live notes, retires the ones that have been missed, and lets autoplay
## take its free hits.
func _advance_notes(now: float) -> void:
	var index := 0
	while index < _active.size():
		var note := _active[index]
		var error := now - note.time  # Positive means the note is late.

		if _autoplay and error >= 0.0:
			_resolve(note, 0.0)
		elif error > Judge.hit_window():
			_resolve(note, error)

		if note.judged:
			note.queue_free()
			_active.remove_at(index)
		else:
			note.position = Vector2(_playfield.lane_x(note.lane), _playfield.y_for(-error))
			index += 1

## Judges the note closest to the judge line in [param lane]. A press with no
## note in range is ignored rather than punished.
func _hit_lane(lane: int) -> void:
	var now := _conductor.chart_time
	var target: Note = null
	var best := INF
	for note in _active:
		if note.lane != lane or note.judged:
			continue
		var distance := absf(now - note.time)
		if distance < best:
			best = distance
			target = note
	if target != null and best <= Judge.hit_window():
		_resolve(target, now - target.time)

func _resolve(note: Note, error: float) -> void:
	note.judged = true
	note.visible = false
	_record(Judge.rank_for(error))

func _record(rank: Judge.Rank) -> void:
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

func _refresh_hud() -> void:
	_hud.set_score(_score())
	_hud.set_accuracy(_accuracy())
	_hud.set_combo(_combo)

## Normalised so a full combo is always Judge.MAX_SCORE, whatever the note count.
func _score() -> int:
	if _chart.notes.is_empty():
		return 0
	return int(round(Judge.MAX_SCORE * _earned / float(_chart.notes.size())))

func _accuracy() -> float:
	return _earned / float(_judged) if _judged > 0 else 0.0

func _on_beat_hit(_beat_index: int) -> void:
	# Without music the metronome is the only tempo reference the player gets.
	if not _conductor.has_music():
		Sfx.play_tick()

func _on_song_finished() -> void:
	_running = false
	GameState.last_result = _build_result()
	get_tree().change_scene_to_file.call_deferred(GameState.RESULT_SCENE)

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
		"counts": _counts.duplicate(),
		"autoplay": _autoplay,
		"full_combo": _counts[Judge.Rank.MISS] == 0 and _judged == _chart.notes.size(),
	}

func _load_music() -> AudioStream:
	if _chart.music_path.is_empty() or not ResourceLoader.exists(_chart.music_path):
		return null
	return ResourceLoader.load(_chart.music_path) as AudioStream

func _to_menu() -> void:
	_conductor.stop()
	_running = false
	get_tree().change_scene_to_file.call_deferred(GameState.MENU_SCENE)

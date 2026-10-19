class_name ChartEditor
extends Control

## The chart editor. Owns the open ChartDoc, the playback clock and the side
## panel; EditorTimeline draws the chart and reports what the mouse did.
##
## Notes go in two ways: with the mouse (click a tap, drag up for a hold,
## right-click to delete), or by recording, where lane keys pressed during
## playback become notes snapped to the grid.

## Snap choices: grid steps per beat, and how they are shown.
const SNAPS := [
	[1, "1/1  beat"],
	[2, "1/2"],
	[3, "1/3  triplet"],
	[4, "1/4"],
	[6, "1/6"],
	[8, "1/8"],
]
const DEFAULT_SNAP := 3  # index of 1/4
## Where a test play's copy of the chart is written.
const TEST_CHART := "user://editor_test.json"
## Playback runs this many beats past the last note or the end of the music.
const TAIL_BEATS := 4.0
## Right-clicks this close to a note (in pixels) still hit it.
const DELETE_TOLERANCE_PX := 8.0
const HELP := """Click: tap   ·   Drag up: hold
Right click: delete
Wheel: scroll (Shift: faster)
Ctrl + wheel: zoom
Record + Play: %s add notes
Ctrl+Z / Ctrl+Y: undo / redo
Home: back to the start"""

## Folder to save into. Empty means ChartStore.writable_dir(); tests set it so
## they never write into the project.
@export var save_dir := ""

@onready var _timeline: EditorTimeline = %Timeline
@onready var _conductor: Conductor = $Conductor
@onready var _header: Label = %HeaderLabel
@onready var _title_edit: LineEdit = %TitleEdit
@onready var _artist_edit: LineEdit = %ArtistEdit
@onready var _file_edit: LineEdit = %FileEdit
@onready var _bpm_spin: SpinBox = %BpmSpin
@onready var _offset_spin: SpinBox = %OffsetSpin
@onready var _speed_spin: SpinBox = %SpeedSpin
@onready var _snap_option: OptionButton = %SnapOption
@onready var _music_button: Button = %MusicButton
@onready var _music_label: Label = %MusicLabel
@onready var _metronome_check: CheckBox = %MetronomeCheck
@onready var _play_button: Button = %PlayButton
@onready var _record_button: Button = %RecordButton
@onready var _test_button: Button = %TestButton
@onready var _test_here_button: Button = %TestHereButton
@onready var _save_button: Button = %SaveButton
@onready var _back_button: Button = %BackButton
@onready var _position_label: Label = %PositionLabel
@onready var _status_label: Label = %StatusLabel
@onready var _help_label: Label = %HelpLabel
@onready var _leave_dialog: ConfirmationDialog = %LeaveDialog
@onready var _music_dialog: FileDialog = %MusicDialog

var doc: ChartDoc
## The file the chart was opened from or last saved to; "" for a new chart.
var source_path := ""
var playing := false
var recording := false

var _recorder := NoteRecorder.new()
## Beat the playhead was at last frame, for the note sounds during playback.
var _last_played_beat := 0.0
## Set while filling the panel from the document, so it is not marked modified.
var _syncing := false

func _ready() -> void:
	for snap: Array in SNAPS:
		_snap_option.add_item(snap[1])
	_connect_ui()

	if GameState.editor_doc != null:
		_restore_session()
	else:
		open_chart(str(GameState.editor_state.get("open_path", "")))

## Loads [param path] into the editor, or starts a new chart if it is empty.
func open_chart(path: String) -> void:
	var loaded: ChartDoc = ChartDoc.load_file(path) if not path.is_empty() else null
	if not path.is_empty() and loaded == null:
		_set_status("Could not open %s. Starting a new chart." % path)
	# Set before _use_doc: the music is looked up relative to the chart's file.
	source_path = path if loaded != null else ""
	_file_edit.text = path.get_file().get_basename() if loaded != null else "new_chart"
	_use_doc(loaded if loaded != null else ChartDoc.new())
	_set_snap(DEFAULT_SNAP)
	_timeline.view_beat = 0.0
	_refresh()

func current_beat() -> float:
	if playing:
		return _conductor.chart_time / doc.seconds_per_beat()
	return _timeline.view_beat

func toggle_playback() -> void:
	if playing:
		stop_playback()
	else:
		start_playback()

func start_playback() -> void:
	# Keys go to the editor while playing, not to a field that still has focus.
	get_viewport().gui_release_focus()
	_conductor.bpm = doc.bpm
	_conductor.offset = doc.offset
	_conductor.start_at(_timeline.view_beat * doc.seconds_per_beat())
	# Just behind the start, so a note sitting on the cursor sounds too.
	_last_played_beat = _timeline.view_beat - ChartDoc.EPSILON
	playing = true
	if recording:
		doc.checkpoint()  # the whole take undoes in one step
	_refresh()

func stop_playback() -> void:
	if not playing:
		return
	var beat := current_beat()
	_conductor.stop()
	playing = false
	for note in _recorder.release_all(beat):
		_add_recorded(note)
	_timeline.view_beat = maxf(beat, 0.0)
	_refresh()

func set_recording(on: bool) -> void:
	if on and not recording and playing:
		doc.checkpoint()
	recording = on
	_record_button.set_pressed_no_signal(on)
	_refresh()

## Writes the chart to the file named in the panel. Returns the path, or "".
func save() -> String:
	var file_name := ChartStore.file_name_for(_file_edit.text)
	var dir := _save_dir()
	var target := dir.path_join(file_name + ".json")
	if target != source_path and FileAccess.file_exists(target):
		_set_status("A chart called \"%s\" already exists. Pick another file name." % file_name)
		return ""
	# The saved file may be in another folder than the one the music was
	# found from: name it relative to the new file if it sits next to it, by
	# its full path otherwise.
	if not doc.music.is_empty():
		var music_path := ChartStore.resolve_music(_chart_path(), doc.music)
		doc.music = music_path.get_file() if music_path.get_base_dir() == dir else music_path
	var path := ChartStore.save(doc, file_name, dir)
	if path.is_empty():
		_set_status("Could not save to %s." % target)
		return ""
	source_path = path
	_file_edit.text = file_name
	doc.modified = false
	_set_status("Saved to %s" % path)
	_refresh()
	return path

## Plays the chart in the game, from the top or from the cursor, then comes
## back here with everything (undo history included) as it was.
func test_play(from_cursor: bool) -> void:
	stop_playback()
	if doc.notes.is_empty():
		_set_status("Add some notes before testing.")
		return
	var file := FileAccess.open(TEST_CHART, FileAccess.WRITE)
	if file == null:
		_set_status("Could not write the test chart.")
		return
	file.store_string(doc.to_json_text(ChartStore.resolve_music(_chart_path(), doc.music)))
	file.close()
	GameState.chart_path = TEST_CHART
	GameState.play_from_time = _timeline.view_beat * doc.seconds_per_beat() if from_cursor else 0.0
	_save_session()
	_leave_to(GameState.GAME_SCENE)

func back() -> void:
	stop_playback()
	if doc.modified:
		_leave_dialog.popup_centered()
		return
	_leave()

func _leave() -> void:
	GameState.close_editor()
	_leave_to(GameState.MENU_SCENE)

func _process(_delta: float) -> void:
	if playing:
		var beat := current_beat()
		_play_note_sounds(_last_played_beat, beat)
		_last_played_beat = beat
		_timeline.view_beat = maxf(beat, 0.0)
		_timeline.queue_redraw()
		if beat > _end_beat():
			stop_playback()
	_position_label.text = _position_text(current_beat())

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null:
		return
	if playing and recording and _record_key(key):
		get_viewport().set_input_as_handled()
		return
	if not key.pressed or key.echo:
		return
	var command := key.is_command_or_control_pressed()
	if key.keycode == KEY_SPACE:
		toggle_playback()
	elif command and key.keycode == KEY_Z:
		if key.shift_pressed:
			_redo()
		else:
			_undo()
	elif command and key.keycode == KEY_Y:
		_redo()
	elif command and key.keycode == KEY_S:
		save()
	elif key.keycode == KEY_HOME:
		stop_playback()
		_timeline.view_beat = 0.0
	elif key.keycode == KEY_ESCAPE:
		back()
	else:
		return
	get_viewport().set_input_as_handled()
	_refresh()

## Lane keys while recording. Returns true if [param key] was one.
func _record_key(key: InputEventKey) -> bool:
	for lane in doc.lane_count:
		var action := KeyBinds.lane_action(lane)
		if key.is_action_pressed(action):
			_recorder.press(lane, current_beat())
			_timeline.flash(lane)
			return true
		if key.is_action_released(action):
			_add_recorded(_recorder.release(lane, current_beat()))
			return true
	return false

func _add_recorded(note: Dictionary) -> void:
	# A recorded note that collides with one already there is dropped; the
	# chart's own notes win.
	if not note.is_empty():
		doc.add_note(note.beat, note.lane, note.length, false)

func _on_place_requested(beat: float, lane: int, length: float) -> void:
	if doc.add_note(beat, lane, length):
		_set_status("")
	else:
		_set_status("That would overlap another note in this lane.")

func _on_delete_requested(beat: float, lane: int) -> void:
	var note := doc.note_at(beat, lane, DELETE_TOLERANCE_PX / _timeline.px_per_beat)
	if note != null:
		doc.remove_note(note)

func _undo() -> void:
	if not doc.undo():
		_set_status("Nothing to undo.")

func _redo() -> void:
	if not doc.redo():
		_set_status("Nothing to redo.")

func _on_music_selected(path: String) -> void:
	var file_name := ChartStore.import_music(path, _save_dir())
	if file_name.is_empty():
		_set_status("Could not copy %s." % path)
		return
	# Copied to where the chart will be saved. Until then the chart may still
	# live elsewhere (a bundled chart opened in the exported game), so name the
	# music by its full path unless it is already next to the chart.
	var copied := _save_dir().path_join(file_name)
	doc.music = file_name if _chart_path().get_base_dir() == _save_dir() else copied
	doc.mark_modified()
	_load_music()
	_set_status("Music copied to %s" % copied)

func _load_music() -> void:
	var stream := ChartStore.load_music(_chart_path(), doc.music)
	_conductor.set_music(stream)
	if stream != null:
		_music_label.text = doc.music.get_file()
		_timeline.music_beats = stream.get_length() / doc.seconds_per_beat()
	else:
		_music_label.text = "No music" if doc.music.is_empty() else "Missing: %s" % doc.music.get_file()
		_timeline.music_beats = 0.0

func _on_beat_hit(_index: int) -> void:
	if _metronome_check.button_pressed:
		Sfx.play_tick()

## One hit sound for each frame in which the playhead crossed a note.
func _play_note_sounds(from_beat: float, to_beat: float) -> void:
	for note in doc.notes:
		if note.beat > from_beat and note.beat <= to_beat:
			Sfx.play_hit()
			return

## Where the chart lives (or will), which is what its music is relative to.
func _chart_path() -> String:
	if not source_path.is_empty():
		return source_path
	return _save_dir().path_join(ChartStore.file_name_for(_file_edit.text) + ".json")

func _save_dir() -> String:
	return save_dir if not save_dir.is_empty() else ChartStore.writable_dir()

## Where playback stops by itself: a little after the last note or the end of
## the music. Recording without music runs until stopped, since a take often
## goes on past the last note.
func _end_beat() -> float:
	if recording and _timeline.music_beats <= 0.0:
		return INF
	return maxf(doc.last_beat(), _timeline.music_beats) + TAIL_BEATS

func _position_text(beat: float) -> String:
	var b := maxf(beat, 0.0)
	return "Bar %d  ·  beat %.2f  ·  %.2fs" % [floori(b / 4.0) + 1, b, b * doc.seconds_per_beat()]

func _use_doc(new_doc: ChartDoc) -> void:
	doc = new_doc
	doc.changed.connect(_refresh)
	_timeline.doc = doc
	KeyBinds.ensure_actions(doc.lane_count)
	_help_label.text = HELP % KeyBinds.lane_hint(doc.lane_count)
	_syncing = true
	_title_edit.text = doc.title
	_artist_edit.text = doc.artist
	_bpm_spin.value = doc.bpm
	_offset_spin.value = doc.offset
	_speed_spin.value = doc.scroll_time
	_syncing = false
	_load_music()

func _set_snap(index: int) -> void:
	_snap_option.select(index)
	var division: int = SNAPS[index][0]
	_timeline.division = division
	_recorder.division = division

func _save_session() -> void:
	GameState.editor_doc = doc
	GameState.editor_state = {
		"source_path": source_path,
		"file_name": _file_edit.text,
		"view_beat": _timeline.view_beat,
		"zoom": _timeline.px_per_beat,
		"snap": _snap_option.selected,
		"recording": recording,
		"metronome": _metronome_check.button_pressed,
	}

func _restore_session() -> void:
	var state := GameState.editor_state
	var was_modified := GameState.editor_doc.modified
	source_path = str(state.get("source_path", ""))
	_file_edit.text = str(state.get("file_name", "new_chart"))
	_use_doc(GameState.editor_doc)
	doc.modified = was_modified
	_timeline.view_beat = float(state.get("view_beat", 0.0))
	_timeline.px_per_beat = float(state.get("zoom", _timeline.px_per_beat))
	_set_snap(int(state.get("snap", DEFAULT_SNAP)))
	_metronome_check.button_pressed = bool(state.get("metronome", true))
	set_recording(bool(state.get("recording", false)))
	GameState.play_from_time = 0.0
	_refresh()

func _connect_ui() -> void:
	_timeline.place_requested.connect(_on_place_requested)
	_timeline.delete_requested.connect(_on_delete_requested)
	_timeline.view_moved.connect(_refresh)
	_conductor.beat_hit.connect(_on_beat_hit)

	_title_edit.text_changed.connect(func(text: String) -> void: _edit_field(func() -> void: doc.title = text))
	_artist_edit.text_changed.connect(func(text: String) -> void: _edit_field(func() -> void: doc.artist = text))
	_bpm_spin.value_changed.connect(func(value: float) -> void:
		_edit_field(func() -> void: doc.bpm = value)
		_load_music())  # the music's length in beats depends on the BPM
	_offset_spin.value_changed.connect(func(value: float) -> void: _edit_field(func() -> void: doc.offset = value))
	_speed_spin.value_changed.connect(func(value: float) -> void: _edit_field(func() -> void: doc.scroll_time = value))
	_snap_option.item_selected.connect(_set_snap)

	_music_button.pressed.connect(func() -> void: _music_dialog.popup_centered_ratio(0.7))
	_music_dialog.file_selected.connect(_on_music_selected)
	_play_button.pressed.connect(toggle_playback)
	_record_button.toggled.connect(set_recording)
	_test_button.pressed.connect(test_play.bind(false))
	_test_here_button.pressed.connect(test_play.bind(true))
	_save_button.pressed.connect(save)
	_back_button.pressed.connect(back)
	_leave_dialog.confirmed.connect(_leave)

func _edit_field(apply: Callable) -> void:
	if _syncing:
		return
	apply.call()
	doc.mark_modified()

func _refresh() -> void:
	if doc == null:
		return
	var shown := source_path.get_file() if not source_path.is_empty() else "new chart"
	_header.text = "Editing: %s%s" % [shown, "  (unsaved)" if doc.modified else ""]
	_play_button.text = "Stop  [Space]" if playing else "Play  [Space]"
	_record_button.text = "Recording: ON" if recording else "Record: off"
	_timeline.queue_redraw()

func _set_status(text: String) -> void:
	_status_label.text = text

## Scene changes only happen when the editor is the scene being run. Embedded
## in another scene (the tests do this) the host stays in charge.
func _leave_to(scene_path: String) -> void:
	if get_tree().current_scene == self:
		get_tree().change_scene_to_file.call_deferred(scene_path)

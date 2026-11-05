class_name ChartEditor
extends Control

## The chart editor app. Owns the open ChartDoc, the playback clock, the files
## and the side panel; EditorTimeline draws the chart and turns the mouse into
## requests (place, move, resize, erase...) that land here as undoable edits.
##
## It runs as its own program: the "Chart Editor" export starts on this scene
## (see run/main_scene.chart_editor in project.godot). It can also be opened
## from the Godot editor with F6. Test play switches to the game scene and
## comes back here.

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
## Playback speeds, for charting fast passages.
const SPEEDS := [1.0, 0.75, 0.5]
## Where a test play's copy of the chart is written.
const TEST_CHART := "user://editor_test.json"
## Playback runs this many beats past the last note or the end of the music.
const TAIL_BEATS := 4.0
## Right-clicks this close to a note (in pixels) still hit it.
const DELETE_TOLERANCE_PX := 8.0
const APP_NAME := "beat to light chart editor"
const HELP := """Click: tap note
Drag up or down: hold note
Drag a note: move it
Drag the end of a hold: length
Right click or drag: delete
Shift + drag: select an area
Ctrl + click: add to selection
Del: delete selected
Ctrl+C / X / V: copy, cut, paste
Arrow keys: move selected
M: mirror selected
Click the waveform: jump there
Wheel: scroll  ·  Ctrl + wheel: zoom
Space: play / stop
Record + Play: %s add notes
1-6: snap  ·  Ctrl+Z / Y: undo, redo
Drop a .json or .ogg on the window
to open it"""

## Folder the save dialog starts in for a new chart. Empty means
## ChartStore.writable_dir(); tests set it so they never write into the project.
@export var save_dir := ""

@onready var _timeline: EditorTimeline = %Timeline
@onready var _conductor: Conductor = $Conductor
@onready var _new_button: Button = %NewButton
@onready var _open_menu: MenuButton = %OpenMenu
@onready var _save_button: Button = %SaveButton
@onready var _save_as_button: Button = %SaveAsButton
@onready var _music_button: Button = %MusicButton
@onready var _play_button: Button = %PlayButton
@onready var _record_button: Button = %RecordButton
@onready var _speed_option: OptionButton = %SpeedOption
@onready var _metronome_check: CheckBox = %MetronomeCheck
@onready var _note_sound_check: CheckBox = %NoteSoundCheck
@onready var _test_button: Button = %TestButton
@onready var _test_here_button: Button = %TestHereButton
@onready var _title_edit: LineEdit = %TitleEdit
@onready var _artist_edit: LineEdit = %ArtistEdit
@onready var _bpm_spin: SpinBox = %BpmSpin
@onready var _offset_spin: SpinBox = %OffsetSpin
@onready var _scroll_spin: SpinBox = %ScrollSpin
@onready var _snap_option: OptionButton = %SnapOption
@onready var _music_label: Label = %MusicLabel
@onready var _selection_label: Label = %SelectionLabel
@onready var _mirror_button: Button = %MirrorButton
@onready var _delete_button: Button = %DeleteButton
@onready var _help_label: Label = %HelpLabel
@onready var _file_label: Label = %FileLabel
@onready var _position_label: Label = %PositionLabel
@onready var _count_label: Label = %CountLabel
@onready var _status_label: Label = %StatusLabel
@onready var _unsaved_dialog: ConfirmationDialog = %UnsavedDialog
@onready var _open_dialog: FileDialog = %OpenDialog
@onready var _save_dialog: FileDialog = %SaveDialog
@onready var _music_dialog: FileDialog = %MusicDialog

var doc: ChartDoc
## The file the chart was opened from or last saved to; "" for a new chart.
var source_path := ""
var playing := false
var recording := false

var _recorder := NoteRecorder.new()
var _waveform := Waveform.new()
## Notes copied with Ctrl+C, as {beat, lane, length} from the first one's beat.
var _clipboard: Array[Dictionary] = []
## Beat the playhead was at last frame, for the note sounds during playback.
var _last_played_beat := 0.0
## Set while filling the panel from the document, so it is not marked modified.
var _syncing := false
## True when this scene is the running program (not embedded in a test).
var _app_mode := false
## What to do once the user has answered "save changes?" (and saved, if asked).
var _pending: Callable
## Whether the current right-button sweep has taken its undo checkpoint.
var _erase_checkpointed := false

func _ready() -> void:
	for snap: Array in SNAPS:
		_snap_option.add_item(snap[1])
	for speed: float in SPEEDS:
		_speed_option.add_item("Speed %d%%" % roundi(speed * 100.0))
	_timeline.waveform = _waveform
	_unsaved_dialog.add_button("Don't save", true, "discard")
	_connect_ui()

	_app_mode = get_tree().current_scene == self
	if _app_mode:
		_set_up_window()

	if GameState.editor_doc != null:
		_restore_session()
	else:
		open_chart(_startup_path())

func _exit_tree() -> void:
	_waveform.finish()
	if _app_mode:
		# Test play needs the game's own scaling back.
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS

# --- Files ------------------------------------------------------------------

## Loads [param path] into the editor, or starts a new chart if it is empty.
## Unsaved changes are dropped; use open_file() to ask first.
func open_chart(path: String) -> void:
	stop_playback()
	var loaded: ChartDoc = ChartDoc.load_file(path) if not path.is_empty() else null
	if not path.is_empty() and loaded == null:
		_set_status("Could not open %s." % path)
	# Set before _use_doc: the music is looked up relative to the chart's file.
	source_path = path if loaded != null else ""
	_use_doc(loaded if loaded != null else ChartDoc.new())
	_set_snap(DEFAULT_SNAP)
	_timeline.view_beat = 0.0
	_timeline.clear_selection()
	if loaded != null:
		_set_status("Opened %s" % path.get_file())
	_refresh()

## Opens [param path], asking about unsaved changes first.
func open_file(path: String) -> void:
	_confirm_discard(open_chart.bind(path))

func new_chart() -> void:
	_confirm_discard(open_chart.bind(""))

## Saves to the chart's file, or asks where (a new chart, or a bundled chart in
## the exported app). Returns the path saved to, or "" if a dialog was opened
## or saving failed.
func save() -> String:
	if not source_path.is_empty() and ChartStore.is_writable(source_path) and source_path != TEST_CHART:
		return save_to(source_path)
	show_save_dialog()
	return ""

## Writes the chart to [param path]. The music is copied next to it if it is
## somewhere else. Returns the path, or "" on failure.
func save_to(path: String) -> String:
	if path.get_extension().to_lower() != "json":
		path += ".json"
	var music := ChartStore.music_for(path, source_path, doc.music)
	if not ChartStore.write_chart(doc, path, music):
		_set_status("Could not save to %s." % path)
		_pending = Callable()
		return ""
	doc.music = music
	source_path = path
	doc.modified = false
	_set_status("Saved to %s" % path)
	_refresh()
	_run_pending()
	return path

func show_save_dialog() -> void:
	var dir := _default_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	_save_dialog.current_dir = ProjectSettings.globalize_path(dir)
	_save_dialog.current_file = (source_path.get_file() if not source_path.is_empty()
			else ChartStore.file_name_for(doc.title) + ".json")
	_save_dialog.popup_centered_ratio(0.7)

func show_open_dialog() -> void:
	var dir := _default_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	_open_dialog.current_dir = ProjectSettings.globalize_path(dir)
	_open_dialog.popup_centered_ratio(0.7)

## Uses the .ogg at [param path] as the chart's music. It stays where it is
## until the chart is saved, then a copy goes next to the chart.
func load_music_file(path: String) -> void:
	if ChartStore.load_music("", path) == null:
		_set_status("Could not read %s. Music has to be an .ogg file." % path.get_file())
		return
	doc.music = path
	doc.mark_modified()
	_load_music()
	_set_status("Music: %s. It is copied next to the chart when you save." % path.get_file())

# --- Playback ---------------------------------------------------------------

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
	_conductor.speed = SPEEDS[_speed_option.selected]
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
	file.store_string(doc.to_json_text(ChartStore.resolve_music(source_path, doc.music)))
	file.close()
	GameState.chart_path = TEST_CHART
	GameState.play_from_time = _timeline.view_beat * doc.seconds_per_beat() if from_cursor else 0.0
	_save_session()
	_leave_to(GameState.GAME_SCENE)

# --- Editing the selection --------------------------------------------------

func select_all() -> void:
	_timeline.select(doc.notes)

func delete_selection() -> void:
	var count := doc.remove_notes(_timeline.selection)
	if count > 0:
		_timeline.clear_selection()
		_set_status("Deleted %d note%s." % [count, "" if count == 1 else "s"])

func copy_selection() -> bool:
	if _timeline.selection.is_empty():
		_set_status("Select some notes to copy first.")
		return false
	var first := INF
	for note in _timeline.selection:
		first = minf(first, note.beat)
	_clipboard.clear()
	for note in _timeline.selection:
		_clipboard.append({"beat": note.beat - first, "lane": note.lane, "length": note.length})
	_set_status("Copied %d note%s." % [_clipboard.size(), "" if _clipboard.size() == 1 else "s"])
	return true

func cut_selection() -> void:
	if copy_selection():
		delete_selection()

## Pastes the copied notes starting at the cursor. Notes that would land on
## others are left out. The pasted notes end up selected, ready to drag.
func paste() -> void:
	if _clipboard.is_empty():
		_set_status("Nothing copied yet.")
		return
	var at := ChartDoc.quantize(current_beat(), _timeline.division)
	var items: Array[Dictionary] = []
	for item in _clipboard:
		items.append({"beat": item.beat + at, "lane": item.lane, "length": item.length})
	var added := doc.add_notes(items)
	_timeline.select(added)
	var skipped := items.size() - added.size()
	_set_status("Pasted %d note%s.%s" % [added.size(), "" if added.size() == 1 else "s",
			" %d left out: something was in the way." % skipped if skipped > 0 else ""])

## Moves the selection [param steps] grid steps later (negative: earlier) and
## [param lanes] lanes right.
func nudge_selection(steps: int, lanes: int) -> void:
	if _timeline.selection.is_empty():
		return
	if not doc.move_notes(_timeline.selection, steps * _timeline.step_beats(), lanes):
		_set_status("Can't move there: it would overlap a note or leave the chart.")

func mirror_selection() -> void:
	if _timeline.selection.is_empty():
		_set_status("Select some notes to mirror first.")
	elif not doc.mirror_notes(_timeline.selection):
		_set_status("Can't mirror: a note would land on another.")

# --- Input ------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _waveform.poll():
		_timeline.queue_redraw()
	if playing:
		var beat := current_beat()
		if _note_sound_check.button_pressed:
			_play_note_sounds(_last_played_beat, beat)
		_last_played_beat = beat
		_timeline.view_beat = maxf(beat, 0.0)
		_timeline.queue_redraw()
		if beat > _end_beat():
			stop_playback()
	_position_label.text = _position_text(current_beat())

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _app_mode:
		_confirm_discard(get_tree().quit)

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null:
		return
	if playing and recording and _record_key(key):
		get_viewport().set_input_as_handled()
		return
	if not key.pressed:
		return
	if _shortcut(key):
		get_viewport().set_input_as_handled()
		_refresh()

## Runs the editor shortcut for [param key]. Returns false if it has none.
func _shortcut(key: InputEventKey) -> bool:
	var command := key.is_command_or_control_pressed()
	var shift := key.shift_pressed
	var code := key.keycode
	# Arrow keys repeat while held; everything else acts once per press.
	if code in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		var up := code == KEY_UP
		var vertical := code == KEY_UP or code == KEY_DOWN
		if _timeline.selection.is_empty():
			if vertical:
				var amount := _timeline.step_beats() * (4.0 if shift else 1.0)
				_timeline.view_beat = maxf(_timeline.view_beat + (amount if up else -amount), 0.0)
		elif vertical:
			nudge_selection((1 if up else -1) * (4 if shift else 1), 0)
		else:
			nudge_selection(0, 1 if code == KEY_RIGHT else -1)
		return true
	if key.echo:
		return false
	if command:
		match code:
			KEY_Z:
				if shift:
					_redo()
				else:
					_undo()
			KEY_Y:
				_redo()
			KEY_S:
				if shift:
					show_save_dialog()
				else:
					save()
			KEY_N:
				new_chart()
			KEY_O:
				show_open_dialog()
			KEY_A:
				select_all()
			KEY_C:
				copy_selection()
			KEY_X:
				cut_selection()
			KEY_V:
				paste()
			_:
				return false
		return true
	match code:
		KEY_SPACE:
			toggle_playback()
		KEY_DELETE, KEY_BACKSPACE:
			delete_selection()
		KEY_M:
			mirror_selection()
		KEY_HOME:
			_jump_to(0.0)
		KEY_END:
			_jump_to(doc.last_beat())
		KEY_ESCAPE:
			_timeline.clear_selection()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			_set_snap(code - KEY_1)
		_:
			return false
	return true

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

func _on_move_requested(notes: Array[EditNote], beats: float, lanes: int) -> void:
	if not doc.move_notes(notes, beats, lanes):
		_set_status("Can't move there: it would overlap a note or leave the chart.")

func _on_resize_requested(note: EditNote, length: float) -> void:
	if not doc.set_length(note, length):
		_set_status("Can't make it that long: it would run into the next note.")

func _on_erase_started() -> void:
	_erase_checkpointed = false

func _on_erase_requested(beat: float, lane: int) -> void:
	var note := doc.note_at(beat, lane, DELETE_TOLERANCE_PX / _timeline.px_per_beat)
	if note == null:
		return
	# One sweep is one undo step, taken only once something is actually erased.
	if not _erase_checkpointed:
		doc.checkpoint()
		_erase_checkpointed = true
	doc.remove_note(note, false)

func _on_seek_requested(beat: float) -> void:
	var was_playing := playing
	stop_playback()
	_timeline.view_beat = beat
	if was_playing:
		start_playback()
	_refresh()

func _jump_to(beat: float) -> void:
	stop_playback()
	_timeline.view_beat = maxf(beat, 0.0)

func _undo() -> void:
	if not doc.undo():
		_set_status("Nothing to undo.")

func _redo() -> void:
	if not doc.redo():
		_set_status("Nothing to redo.")

func _on_files_dropped(files: PackedStringArray) -> void:
	for path in files:
		match path.get_extension().to_lower():
			"json":
				open_file(path)
				return
			"ogg":
				load_music_file(path)
				return
	_set_status("Drop a chart (.json) or music (.ogg).")

func _on_open_menu_about_to_popup() -> void:
	var popup := _open_menu.get_popup()
	popup.clear()
	for path in ChartStore.list_charts():
		var chart := Chart.load_from_file(path)
		if chart == null:
			continue
		var label := "%s%s   (%s)" % ["[mine] " if ChartStore.is_user_chart(path) else "", chart.title, path.get_file()]
		popup.add_item(label)
		popup.set_item_metadata(popup.item_count - 1, path)
	popup.add_separator()
	popup.add_item("Browse...")
	popup.set_item_metadata(popup.item_count - 1, "")

func _on_open_menu_index_pressed(index: int) -> void:
	var path := str(_open_menu.get_popup().get_item_metadata(index))
	if path.is_empty():
		show_open_dialog()
	else:
		open_file(path)

# --- Unsaved changes --------------------------------------------------------

## Runs [param action] now if nothing is unsaved; otherwise asks whether to
## save first and runs it after the answer (unless cancelled).
func _confirm_discard(action: Callable) -> void:
	if not doc.modified:
		action.call()
		return
	_pending = action
	var shown := source_path.get_file() if not source_path.is_empty() else "the new chart"
	_unsaved_dialog.dialog_text = "Save changes to %s first?" % shown
	_unsaved_dialog.popup_centered()

func _on_unsaved_save() -> void:
	# save_to() runs the pending action once saved; with a save dialog in
	# between, that happens when a file is chosen.
	save()

func _on_unsaved_custom_action(action: StringName) -> void:
	if action == &"discard":
		_unsaved_dialog.hide()
		_run_pending()

func _run_pending() -> void:
	var action := _pending
	_pending = Callable()
	if action.is_valid():
		action.call()

# --- Music ------------------------------------------------------------------

func _load_music() -> void:
	var stream := ChartStore.load_music(source_path, doc.music)
	_conductor.set_music(stream)
	_waveform.start(stream)
	_update_music_length()
	if stream != null:
		_music_label.text = "Music: %s" % doc.music.get_file()
	else:
		_music_label.text = "No music" if doc.music.is_empty() else "Missing: %s" % doc.music.get_file()

func _update_music_length() -> void:
	var stream := _conductor.get_music()
	_timeline.music_beats = stream.get_length() / doc.seconds_per_beat() if stream != null else 0.0
	_timeline.queue_redraw()

func _on_beat_hit(_index: int) -> void:
	if _metronome_check.button_pressed:
		Sfx.play_tick()

## One hit sound for each frame in which the playhead crossed a note.
func _play_note_sounds(from_beat: float, to_beat: float) -> void:
	for note in doc.notes:
		if note.beat > from_beat and note.beat <= to_beat:
			Sfx.play_hit()
			return

# --- Window and session -----------------------------------------------------

func _set_up_window() -> void:
	var window := get_window()
	get_tree().set_auto_accept_quit(false)
	# An editor wants every pixel of a big window, not a scaled-up small one.
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	window.files_dropped.connect(_on_files_dropped)
	var default_size := Vector2i(ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height"))
	if window.size == default_size and window.mode == Window.MODE_WINDOWED:
		var screen := DisplayServer.screen_get_usable_rect(window.current_screen)
		var want := Vector2i(mini(1440, int(screen.size.x * 0.9)), mini(900, int(screen.size.y * 0.9)))
		if want.x > window.size.x and want.y > window.size.y:
			window.size = want
			window.position = screen.position + (screen.size - want) / 2

## A chart named on the command line ("chart_editor.exe mysong.json"), so
## charts can be opened with the editor from the file manager.
func _startup_path() -> String:
	if not _app_mode:
		return ""
	for arg in OS.get_cmdline_args():
		if arg.get_extension().to_lower() == "json" and FileAccess.file_exists(arg):
			return arg
	return ""

func _default_dir() -> String:
	if not source_path.is_empty() and ChartStore.is_writable(source_path) and source_path != TEST_CHART:
		return source_path.get_base_dir()
	return save_dir if not save_dir.is_empty() else ChartStore.writable_dir()

func _end_beat() -> float:
	# Recording without music runs until stopped: a take often goes on past
	# the last note.
	if recording and _timeline.music_beats <= 0.0:
		return INF
	return maxf(doc.last_beat(), _timeline.music_beats) + TAIL_BEATS

func _position_text(beat: float) -> String:
	var b := maxf(beat, 0.0)
	return "Bar %d  ·  beat %.2f  ·  %.2fs" % [floori(b / 4.0) + 1, b, b * doc.seconds_per_beat()]

func _use_doc(new_doc: ChartDoc) -> void:
	doc = new_doc
	doc.changed.connect(_on_doc_changed)
	_timeline.doc = doc
	KeyBinds.ensure_actions(doc.lane_count)
	_help_label.text = HELP % KeyBinds.lane_hint(doc.lane_count)
	_syncing = true
	_title_edit.text = doc.title
	_artist_edit.text = doc.artist
	_bpm_spin.value = doc.bpm
	_offset_spin.value = doc.offset
	_scroll_spin.value = doc.scroll_time
	_syncing = false
	_load_music()

func _on_doc_changed() -> void:
	_timeline.prune_selection()
	_refresh()

func _set_snap(index: int) -> void:
	if index < 0 or index >= SNAPS.size():
		return
	_snap_option.select(index)
	var division: int = SNAPS[index][0]
	_timeline.division = division
	_recorder.division = division
	_timeline.queue_redraw()

func _save_session() -> void:
	GameState.editor_doc = doc
	GameState.editor_state = {
		"source_path": source_path,
		"view_beat": _timeline.view_beat,
		"zoom": _timeline.px_per_beat,
		"snap": _snap_option.selected,
		"speed": _speed_option.selected,
		"recording": recording,
		"metronome": _metronome_check.button_pressed,
		"note_sounds": _note_sound_check.button_pressed,
		"clipboard": _clipboard,
	}

## Picks up where the editor left off before a test play, then hands the
## session back so GameState no longer holds it.
func _restore_session() -> void:
	var state := GameState.editor_state
	var was_modified := GameState.editor_doc.modified
	source_path = str(state.get("source_path", ""))
	_use_doc(GameState.editor_doc)
	doc.modified = was_modified
	_timeline.view_beat = float(state.get("view_beat", 0.0))
	_timeline.px_per_beat = float(state.get("zoom", _timeline.px_per_beat))
	_set_snap(int(state.get("snap", DEFAULT_SNAP)))
	_speed_option.select(int(state.get("speed", 0)))
	_metronome_check.button_pressed = bool(state.get("metronome", true))
	_note_sound_check.button_pressed = bool(state.get("note_sounds", true))
	_clipboard.assign(state.get("clipboard", []))
	set_recording(bool(state.get("recording", false)))
	var quit_requested := bool(state.get("quit_requested", false))
	GameState.clear_editor_session()
	if FileAccess.file_exists(TEST_CHART):
		DirAccess.remove_absolute(TEST_CHART)
	_refresh()
	if quit_requested:
		# The window was closed during the test play with changes unsaved.
		_confirm_discard.call_deferred(get_tree().quit)

func _connect_ui() -> void:
	_timeline.place_requested.connect(_on_place_requested)
	_timeline.move_requested.connect(_on_move_requested)
	_timeline.resize_requested.connect(_on_resize_requested)
	_timeline.erase_started.connect(_on_erase_started)
	_timeline.erase_requested.connect(_on_erase_requested)
	_timeline.seek_requested.connect(_on_seek_requested)
	_timeline.selection_changed.connect(_refresh)
	_timeline.view_moved.connect(_refresh)
	_conductor.beat_hit.connect(_on_beat_hit)

	_title_edit.text_changed.connect(func(text: String) -> void: _edit_field(func() -> void: doc.title = text))
	_artist_edit.text_changed.connect(func(text: String) -> void: _edit_field(func() -> void: doc.artist = text))
	_bpm_spin.value_changed.connect(func(value: float) -> void:
		_edit_field(func() -> void: doc.bpm = value)
		_update_music_length())  # the music's length in beats depends on the BPM
	_offset_spin.value_changed.connect(func(value: float) -> void: _edit_field(func() -> void: doc.offset = value))
	_scroll_spin.value_changed.connect(func(value: float) -> void: _edit_field(func() -> void: doc.scroll_time = value))
	_snap_option.item_selected.connect(_set_snap)

	_new_button.pressed.connect(new_chart)
	_open_menu.about_to_popup.connect(_on_open_menu_about_to_popup)
	_open_menu.get_popup().index_pressed.connect(_on_open_menu_index_pressed)
	_save_button.pressed.connect(save)
	_save_as_button.pressed.connect(show_save_dialog)
	_music_button.pressed.connect(func() -> void: _music_dialog.popup_centered_ratio(0.7))
	_play_button.pressed.connect(toggle_playback)
	_record_button.toggled.connect(set_recording)
	_test_button.pressed.connect(test_play.bind(false))
	_test_here_button.pressed.connect(test_play.bind(true))
	_mirror_button.pressed.connect(mirror_selection)
	_delete_button.pressed.connect(delete_selection)

	_open_dialog.file_selected.connect(open_file)
	_save_dialog.file_selected.connect(save_to)
	_save_dialog.canceled.connect(func() -> void: _pending = Callable())
	_music_dialog.file_selected.connect(load_music_file)
	_unsaved_dialog.confirmed.connect(_on_unsaved_save)
	_unsaved_dialog.custom_action.connect(_on_unsaved_custom_action)
	_unsaved_dialog.canceled.connect(func() -> void: _pending = Callable())

func _edit_field(apply: Callable) -> void:
	if _syncing:
		return
	apply.call()
	doc.mark_modified()

func _refresh() -> void:
	if doc == null:
		return
	var shown := source_path.get_file() if not source_path.is_empty() else "New chart"
	_file_label.text = "%s%s" % [shown, "  (unsaved)" if doc.modified else ""]
	if _app_mode:
		get_window().title = "%s%s - %s" % [shown, " *" if doc.modified else "", APP_NAME]
	_play_button.text = "Stop" if playing else "Play"
	_record_button.text = "Recording" if recording else "Record"
	var holds := doc.notes.filter(func(n: EditNote) -> bool: return n.is_hold()).size()
	_count_label.text = "%d notes (%d holds)" % [doc.notes.size(), holds]
	var selected := _timeline.selection.size()
	_selection_label.text = "%d selected" % selected if selected > 0 else "Nothing selected"
	_mirror_button.disabled = selected == 0
	_delete_button.disabled = selected == 0
	_timeline.queue_redraw()

func _set_status(text: String) -> void:
	_status_label.text = text

## Scene changes only happen when the editor is the scene being run. Embedded
## in another scene (the tests do this) the host stays in charge.
func _leave_to(scene_path: String) -> void:
	if get_tree().current_scene == self:
		get_tree().change_scene_to_file.call_deferred(scene_path)

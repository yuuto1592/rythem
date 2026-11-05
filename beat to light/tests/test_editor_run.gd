extends TestCase

## The chart editor app driven the way a person drives it: real mouse clicks
## and drags on the timeline, real key presses for the shortcuts, and a
## recording take played in real time. Saves into a throwaway user:// folder.

const EDITOR_SCENE := preload("res://scenes/editor.tscn")
const MUSIC_FIXTURE := "res://tests/fixtures/beep.ogg"
## The chart after the mouse edits and the recording take, as "beat@lane+length".
const RECORDED := ["1@0", "2@1+1", "4@3+1", "7.5@2", "8@3+1"]
## Zoomed out from the default so the test's notes fit in the headless window.
const PX_PER_BEAT := 60.0
## Generous; playback that has not reached a beat by now is stuck.
const TIMEOUT_MSEC := 10000

var _host: Node
var _editor: ChartEditor
var _timeline: EditorTimeline
var _dir := "user://test_editor_%d" % Time.get_ticks_usec()

var _saved_chart_path := ""
var _saved_play_from := 0.0
var _saved_doc: ChartDoc
var _saved_state := {}

func run(host: Node) -> void:
	_host = host
	_saved_chart_path = GameState.chart_path
	_saved_play_from = GameState.play_from_time
	_saved_doc = GameState.editor_doc
	_saved_state = GameState.editor_state.duplicate()
	GameState.clear_editor_session()

	await _placing_with_the_mouse()
	await _selecting_and_moving()
	await _changing_a_hold_s_length()
	await _box_select_and_delete()
	await _copy_paste_nudge_mirror()
	await _sweeping_with_the_eraser()
	await _clicking_the_waveform()
	await _recording_take()
	await _music_and_saving()
	await _test_play_comes_back()
	await _unsaved_changes_are_asked_about()
	await _closing_during_a_test_play()
	await _a_chart_from_elsewhere()

	_close_editor()
	_clean_up()
	GameState.chart_path = _saved_chart_path
	GameState.play_from_time = _saved_play_from
	GameState.editor_doc = _saved_doc
	GameState.editor_state = _saved_state

## Click a tap, drag a hold either way, right-click to delete, undo and redo.
func _placing_with_the_mouse() -> void:
	await _open_editor()
	check(_editor.doc.notes.is_empty(), "a new chart starts empty")

	await _click_at(1.0, 0)
	check_eq(_notes(), ["1@0"], "click places a tap on the beat")
	await _drag(2.0, 3.0, 1)
	check_eq(_notes(), ["1@0", "2@1+1"], "dragging up places a hold")
	await _drag(5.0, 4.0, 3)
	check_eq(_notes(), ["1@0", "2@1+1", "4@3+1"], "dragging down places a hold too, from the lower end")

	await _click_at(2.5, 1)
	check_eq(_notes(), ["1@0", "2@1+1", "4@3+1"], "clicking inside a hold adds nothing")
	check_eq(_timeline.selection.size(), 1, "it selects the hold instead")
	await _drag(3.75, 4.25, 3)
	check_eq(_notes(), ["1@0", "2@1+1", "4@3+1"], "a hold that would run into another is refused")
	check(_status().contains("overlap"), "and the status says why")

	await _click_at(1.0, 0, MOUSE_BUTTON_RIGHT)
	check_eq(_notes(), ["2@1+1", "4@3+1"], "right-click deletes")
	await _key(KEY_Z, true)
	check_eq(_notes(), ["1@0", "2@1+1", "4@3+1"], "Ctrl+Z brings it back")
	await _key(KEY_Y, true)
	check_eq(_notes(), ["2@1+1", "4@3+1"], "Ctrl+Y deletes it again")
	await _key(KEY_Z, true)
	check(_editor.doc.modified, "edits mark the chart unsaved")

## Click a note to select it, drag it somewhere else, try somewhere blocked.
func _selecting_and_moving() -> void:
	await _click_at(1.0, 0)
	check_eq(_timeline.selection.size(), 1, "clicking a note selects it")
	check_eq(_notes(), ["1@0", "2@1+1", "4@3+1"], "and adds nothing")
	check_eq(_label("%SelectionLabel"), "1 selected", "the panel shows the selection")

	await _drag_between(_point(1.0, 0), _point(2.0, 2))
	check_eq(_notes(), ["2@1+1", "2@2", "4@3+1"], "dragging a note moves it in time and across lanes")
	check_eq(_timeline.selection.size(), 1, "it stays selected")

	await _drag_between(_point(2.0, 2), _point(2.5, 1))
	check_eq(_notes(), ["2@1+1", "2@2", "4@3+1"], "a move onto a hold is refused")
	check(_status().contains("Can't move"), "and says why")

	await _key(KEY_Z, true)
	check_eq(_notes(), ["1@0", "2@1+1", "4@3+1"], "Ctrl+Z undoes the move")
	check(_timeline.selection.is_empty(), "the undone note is no longer selected")

## Drag the end of a hold to change its length.
func _changing_a_hold_s_length() -> void:
	await _drag_between(_point(3.0, 1), _point(4.0, 1))
	check_eq(_notes(), ["1@0", "2@1+2", "4@3+1"], "dragging a hold's end up makes it longer")
	await _drag_between(_point(4.0, 1), _point(2.5, 1))
	check_eq(_notes(), ["1@0", "2@1+0.5", "4@3+1"], "and down makes it shorter")
	await _key(KEY_Z, true)
	await _key(KEY_Z, true)
	check_eq(_notes(), ["1@0", "2@1+1", "4@3+1"], "each change undoes on its own")

## Shift+drag a box around notes, then Delete.
func _box_select_and_delete() -> void:
	await _drag_between(_point(0.5, 0), _point(3.5, 1), true)
	check_eq(_timeline.selection.size(), 2, "the box selects the notes it touches")
	check_eq(_notes(), ["1@0", "2@1+1", "4@3+1"], "and adds nothing")
	await _key(KEY_DELETE)
	check_eq(_notes(), ["4@3+1"], "Delete removes the selection")
	await _key(KEY_Z, true)
	check_eq(_notes(), ["1@0", "2@1+1", "4@3+1"], "one Ctrl+Z brings them all back")

## Copy two notes, paste them further on, nudge them with an arrow, mirror.
func _copy_paste_nudge_mirror() -> void:
	await _drag_between(_point(0.5, 0), _point(3.5, 1), true)
	await _key(KEY_C, true)
	check(_status().contains("Copied 2"), "Ctrl+C copies")
	for i in 8:
		await _wheel(true, true)  # Shift+wheel: one beat per notch
	check_near(_timeline.view_beat, 8.0, "Shift+wheel scrolls a beat at a time")

	await _key(KEY_V, true)
	check_eq(_notes(), ["1@0", "2@1+1", "4@3+1", "8@0", "9@1+1"], "Ctrl+V pastes at the cursor")
	check_eq(_timeline.selection.size(), 2, "the pasted notes are selected")
	await _key(KEY_UP)
	check_eq(_notes(), ["1@0", "2@1+1", "4@3+1", "8.25@0", "9.25@1+1"], "Up moves them one grid step later")
	await _key(KEY_RIGHT)
	check_eq(_notes(), ["1@0", "2@1+1", "4@3+1", "8.25@1", "9.25@2+1"], "Right moves them a lane over")
	await _key(KEY_LEFT)
	await _key(KEY_M)
	check_eq(_notes(), ["1@0", "2@1+1", "4@3+1", "8.25@3", "9.25@2+1"], "M mirrors them")

## Right-drag across notes deletes all of them, as one undo step.
func _sweeping_with_the_eraser() -> void:
	await _drag_between(_point(8.25, 3), _point(9.5, 2), false, MOUSE_BUTTON_RIGHT)
	check_eq(_notes(), ["1@0", "2@1+1", "4@3+1"], "a right-button sweep deletes what it passes")
	await _key(KEY_Z, true)
	check_eq(_notes().size(), 5, "one Ctrl+Z brings the sweep back")
	await _key(KEY_Y, true)
	check_eq(_notes(), ["1@0", "2@1+1", "4@3+1"], "Ctrl+Y sweeps again")

## Click the waveform to jump; drag it to scroll.
func _clicking_the_waveform() -> void:
	var view := _timeline.view_beat
	var x := _timeline.get_global_transform().origin.x + _timeline.wave_left() + EditorTimeline.WAVE_WIDTH * 0.5
	var at := Vector2(x, _point(view + 2.0, 0).y)
	await _mouse_move(at)
	await _mouse_button(at, MOUSE_BUTTON_LEFT, true)
	await _mouse_button(at, MOUSE_BUTTON_LEFT, false)
	check_near(_timeline.view_beat, view + 2.0, "clicking the waveform moves the cursor there")

	view = _timeline.view_beat
	var from := Vector2(x, _point(view + 3.0, 0).y)
	await _drag_between(from, from + Vector2(0.0, _timeline.px_per_beat * 2.0))
	check_near(_timeline.view_beat, view + 2.0, "dragging the waveform down by two beats' height scrolls two beats", 0.05)

	var anchor := _timeline.y_to_beat(_point(view + 3.0, 0).y - _timeline.get_global_transform().origin.y)
	await _wheel(true, false, true)
	check(_timeline.px_per_beat > PX_PER_BEAT, "Ctrl+wheel zooms in")
	await _wheel(false, false, true)
	check_near(_timeline.px_per_beat, PX_PER_BEAT, "and back out", 0.01)
	check_near(_timeline.y_to_beat(_point(view + 3.0, 0).y - _timeline.get_global_transform().origin.y), anchor,
			"keeping the beat under the mouse in place", 0.01)

## Record on, play from beat 4, and tap a lane key and hold another. Both come
## after beat 9, where playback (last note + 4 beats) would stop if it were
## not recording.
func _recording_take() -> void:
	await _key(KEY_HOME)
	for i in 4:
		await _wheel(true, true)
	check_near(_timeline.view_beat, 4.0, "Home, then four notches")

	await _press_button("%RecordButton")
	check(_editor.recording, "the record button turns recording on")
	await _key(KEY_SPACE)
	check(_editor.playing, "Space starts playback")
	await _wait_for_beat(7.5)
	await _lane_key(2, true)
	await _wait_for_beat(7.7)
	await _lane_key(2, false)
	await _wait_for_beat(8.0)
	await _lane_key(3, true)
	await _wait_for_beat(9.0)
	await _lane_key(3, false)
	await _wait_for_beat(9.3)
	check(_editor.playing, "still playing past the last note while recording")
	await _key(KEY_SPACE)
	check(not _editor.playing, "Space stops playback")
	check_eq(_notes(), RECORDED, "a short press records a tap, a long one a hold, both on the grid")

	await _key(KEY_Z, true)
	check_eq(_notes(), ["1@0", "2@1+1", "4@3+1"], "one Ctrl+Z undoes the whole take")
	await _key(KEY_Y, true)
	check_eq(_notes(), RECORDED, "and Ctrl+Y redoes it")
	await _press_button("%RecordButton")
	check(not _editor.recording, "the record button turns recording off")

## Load an .ogg, see its waveform, save a new chart (which asks where).
func _music_and_saving() -> void:
	var beep := ProjectSettings.globalize_path(MUSIC_FIXTURE)
	_editor.load_music_file(beep)
	check_eq(_label("%MusicLabel"), "Music: beep.ogg", "the music is loaded")
	check_near(_timeline.music_beats, 2.0, "the one-second clip is two beats at 120 BPM", 0.05)
	await _wait_until(func() -> bool: return _timeline.waveform.is_ready())
	check(_timeline.waveform.is_ready() and _timeline.waveform.loudest > 0.0, "its waveform is decoded")

	(_editor.get_node(^"%TitleEdit") as LineEdit).text_changed.emit("Editor Test")
	await _key(KEY_S, true)
	var dialog := _editor.get_node(^"%SaveDialog") as FileDialog
	check(dialog.visible, "Ctrl+S on a new chart asks where to save it")
	check_eq(dialog.current_file, "editor_test.json", "suggesting a name from the title")
	dialog.hide()

	var path := _editor.save_to(_dir.path_join("editor_test"))
	check_eq(path, _dir.path_join("editor_test.json"), ".json is added to the name")
	check(not _editor.doc.modified, "saved means not modified")
	check(FileAccess.file_exists(_dir.path_join("beep.ogg")), "the music is copied next to the chart")
	check_eq(_editor.doc.music, "beep.ogg", "and named relative to it")
	var chart := Chart.load_from_file(path)
	if chart == null:
		failures.append("the saved chart loads")
		return
	check_eq(chart.title, "Editor Test", "the title is saved")
	check_eq(chart.notes.size(), RECORDED.size(), "every note is saved")
	check(ChartStore.load_music(path, chart.music_path) != null, "the saved chart finds its music")

	await _click_at(12.0, 0)
	await _key(KEY_S, true)
	check(not dialog.visible, "once it has a file, Ctrl+S saves straight away")
	check(not _editor.doc.modified, "and it is saved")
	check_eq(Chart.load_from_file(path).notes.size(), RECORDED.size() + 1, "with the new note")
	await _key(KEY_Z, true)
	await _key(KEY_S, true)

## Test play from the cursor, then come back to the same document.
func _test_play_comes_back() -> void:
	var doc := _editor.doc
	_timeline.view_beat = 5.0
	await _press_button("%TestHereButton")
	check_eq(GameState.chart_path, ChartEditor.TEST_CHART, "the game gets the test copy")
	check_near(GameState.play_from_time, 2.5, "starting from the cursor (beat 5)")
	check(GameState.editor_doc == doc, "the document waits in GameState")
	check_eq(GameState.exit_scene(), GameState.EDITOR_SCENE, "the game will come back to the editor")
	var copy := Chart.load_from_file(ChartEditor.TEST_CHART)
	check(copy != null and copy.notes.size() == RECORDED.size(), "the test copy has every note")
	if copy != null:
		check(ChartStore.load_music(ChartEditor.TEST_CHART, copy.music_path) != null,
				"the test copy finds the music from user://")

	_close_editor()
	await _open_editor()
	check(_editor.doc == doc, "the editor comes back to the same document")
	check_near(_timeline.view_beat, 5.0, "at the same place")
	check_eq(_editor.source_path, _dir.path_join("editor_test.json"), "with the same file")
	check(doc.can_undo(), "with its undo history")
	check(GameState.editor_doc == null and GameState.editor_state.is_empty(), "the session is handed back")
	check(not FileAccess.file_exists(ChartEditor.TEST_CHART), "and the test copy is cleaned up")
	check_eq(GameState.play_from_time, 0.0, "the next run plays from the top again")

## New, open and dropping a file ask before throwing changes away.
func _unsaved_changes_are_asked_about() -> void:
	var dialog := _editor.get_node(^"%UnsavedDialog") as ConfirmationDialog
	var saved := _dir.path_join("editor_test.json")

	await _click_at(12.0, 1)
	await _key(KEY_N, true)
	check(dialog.visible, "Ctrl+N with unsaved changes asks first")
	dialog.get_cancel_button().pressed.emit()
	check(_editor.doc.modified and _editor.doc.notes.size() == RECORDED.size() + 1, "Cancel keeps everything")

	await _key(KEY_N, true)
	_dialog_button(dialog, "Don't save").pressed.emit()
	check(_editor.doc.notes.is_empty() and _editor.source_path.is_empty(), "Don't save starts the new chart")

	_editor.open_file(saved)
	check_eq(_editor.source_path, saved, "with nothing unsaved, opening needs no question")
	await _click_at(3.0, 2)
	_editor.call("_on_files_dropped", PackedStringArray([ProjectSettings.globalize_path(saved)]))
	check(dialog.visible, "dropping a chart on the window asks too")
	dialog.get_ok_button().pressed.emit()
	check(not _editor.doc.modified, "Save saves, then opens the dropped chart")
	check_eq(Chart.load_from_file(saved).notes.size(), RECORDED.size() + 1, "with the change kept in the file")

	_editor.call("_on_files_dropped", PackedStringArray([ProjectSettings.globalize_path(MUSIC_FIXTURE)]))
	check_eq(_label("%MusicLabel"), "Music: beep.ogg", "dropping an .ogg loads it as the music")

## The window closed during a test play with changes unsaved: the editor comes
## back and asks.
func _closing_during_a_test_play() -> void:
	await _click_at(6.0, 0)
	check(_editor.doc.modified, "an unsaved change")
	GameState.editor_doc = _editor.doc
	GameState.editor_state = {"source_path": _editor.source_path, "quit_requested": true}
	_close_editor()
	await _open_editor()
	var dialog := _editor.get_node(^"%UnsavedDialog") as ConfirmationDialog
	check(dialog.visible, "the editor asks about the unsaved changes before quitting")
	dialog.get_cancel_button().pressed.emit()
	check(_editor.doc.modified, "Cancel stays in the editor with the changes")

## A bundled chart saved somewhere else takes its music along.
func _a_chart_from_elsewhere() -> void:
	_editor.open_chart("res://songs/03_hold_on.json")
	var chart := Chart.load_from_file("res://songs/03_hold_on.json")
	check_eq(_editor.doc.notes.size(), chart.notes.size(), "every note of the bundled chart is there")
	check(not _editor.doc.modified, "opening is not an edit")
	_editor.load_music_file(ProjectSettings.globalize_path(MUSIC_FIXTURE))
	var path := _editor.save_to(_dir.path_join("hold_on_copy.json"))
	var copy := Chart.load_from_file(path)
	check(copy != null and copy.music_path == "beep.ogg", "the copy's music sits next to it")
	check_eq(ChartStore.is_writable("res://songs/03_hold_on.json"), OS.has_feature("editor"),
			"bundled charts are read-only in an exported app")

func _open_editor() -> void:
	_editor = EDITOR_SCENE.instantiate() as ChartEditor
	_editor.save_dir = _dir
	_host.add_child(_editor)
	_timeline = _editor.get_node(^"%Timeline")
	_timeline.px_per_beat = PX_PER_BEAT
	await _frames(2)  # let the containers lay out

func _close_editor() -> void:
	if _editor != null:
		_editor.free()
		_editor = null

func _clean_up() -> void:
	if DirAccess.dir_exists_absolute(_dir):
		for file in DirAccess.get_files_at(_dir):
			DirAccess.remove_absolute(_dir.path_join(file))
		DirAccess.remove_absolute(_dir)
	if FileAccess.file_exists(ChartEditor.TEST_CHART):
		DirAccess.remove_absolute(ChartEditor.TEST_CHART)

## The notes as "beat@lane", with "+length" for holds.
func _notes() -> Array:
	var out := []
	for note: EditNote in _editor.doc.notes:
		var text := "%s@%d" % [str(ChartDoc.json_number(note.beat)), note.lane]
		if note.is_hold():
			text += "+%s" % str(ChartDoc.json_number(note.length))
		out.append(text)
	return out

func _status() -> String:
	return _label("%StatusLabel")

func _label(unique_name: String) -> String:
	return (_editor.get_node(NodePath(unique_name)) as Label).text

func _dialog_button(dialog: AcceptDialog, text: String) -> Button:
	for button in dialog.find_children("*", "Button", true, false):
		if (button as Button).text == text:
			return button
	failures.append("no \"%s\" button" % text)
	return Button.new()

func _point(beat: float, lane: int) -> Vector2:
	return _timeline.get_global_transform() * Vector2(_timeline.lane_center_x(lane), _timeline.beat_to_y(beat))

func _click_at(beat: float, lane: int, button := MOUSE_BUTTON_LEFT) -> void:
	var at := _point(beat, lane)
	await _mouse_move(at)
	await _mouse_button(at, button, true)
	await _mouse_button(at, button, false)

func _drag(from_beat: float, to_beat: float, lane: int) -> void:
	await _drag_between(_point(from_beat, lane), _point(to_beat, lane))

## Presses at [param from], moves to [param to] in two steps and lets go.
func _drag_between(from: Vector2, to: Vector2, shift := false, button := MOUSE_BUTTON_LEFT) -> void:
	var mask := MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	await _mouse_move(from)
	await _mouse_button(from, button, true, shift)
	await _mouse_move(from.lerp(to, 0.5), mask)
	await _mouse_move(to, mask)
	await _mouse_button(to, button, false, shift)

func _wheel(up: bool, shift := false, command := false) -> void:
	var at := _point(_timeline.view_beat + 1.0, 0)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		_place(event, at)
		event.shift_pressed = shift
		event.ctrl_pressed = command
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(1)

## Mouse events arrive in window pixels, which the stretch mode scales to the
## game's resolution. (The headless window is only 64x64.)
func _place(event: InputEventMouse, at: Vector2) -> void:
	var in_window := _host.get_viewport().get_final_transform() * at
	event.position = in_window
	event.global_position = in_window

func _mouse_move(at: Vector2, mask := 0) -> void:
	var event := InputEventMouseMotion.new()
	_place(event, at)
	event.button_mask = mask
	Input.parse_input_event(event)
	await _frames(1)

func _mouse_button(at: Vector2, button: MouseButton, pressed: bool, shift := false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	_place(event, at)
	event.pressed = pressed
	event.shift_pressed = shift
	if pressed:
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	Input.parse_input_event(event)
	await _frames(1)

## Clicks a button where it is on screen, scrolling the side panel to it first
## as a person would.
func _press_button(unique_name: String) -> void:
	var button := _editor.get_node(NodePath(unique_name)) as Button
	var scroll := _editor.get_node(^"Layout/Body/Side/Scroll") as ScrollContainer
	if scroll.is_ancestor_of(button):
		scroll.ensure_control_visible(button)
		await _frames(1)
	var at := button.get_global_rect().get_center()
	await _mouse_move(at)
	await _mouse_button(at, MOUSE_BUTTON_LEFT, true)
	await _mouse_button(at, MOUSE_BUTTON_LEFT, false)

func _key(keycode: Key, command := false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.ctrl_pressed = command
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(1)

func _lane_key(lane: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KeyBinds.LANE_KEYS[lane]
	event.pressed = pressed
	Input.parse_input_event(event)
	await _frames(1)

func _wait_for_beat(beat: float) -> void:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	while _editor.current_beat() < beat and Time.get_ticks_msec() < deadline:
		await _frames(1)
	check(_editor.current_beat() >= beat, "playback reached beat %.1f" % beat)

func _wait_until(condition: Callable) -> void:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await _frames(1)

func _frames(count: int) -> void:
	for i in count:
		await _host.get_tree().process_frame

extends TestCase

## The chart editor driven the way a person drives it: real mouse clicks and
## drags on the timeline, real key presses for the shortcuts, and a recording
## take played in real time. Saves into a throwaway user:// folder.

const EDITOR_SCENE := preload("res://scenes/editor.tscn")
const MUSIC_FIXTURE := "res://tests/fixtures/beep.ogg"
## The chart after the mouse edits and the recording take, as "beat@lane+length".
const RECORDED := ["1@0", "2@1+1", "7.5@2", "8@3+1"]
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

	await _mouse_editing()
	await _recording_take()
	await _music_and_save()
	await _test_play_comes_back()
	await _leaving()
	await _opening_a_bundled_chart()
	await _music_for_a_chart_from_elsewhere()

	_close_editor()
	_clean_up()
	GameState.chart_path = _saved_chart_path
	GameState.play_from_time = _saved_play_from
	GameState.editor_doc = _saved_doc
	GameState.editor_state = _saved_state

## Click a tap, drag a hold, right-click to delete, undo and redo.
func _mouse_editing() -> void:
	GameState.open_editor("")
	await _open_editor()
	var doc: ChartDoc = _editor.doc
	check(doc.notes.is_empty(), "a new chart starts empty")

	await _click_at(1.0, 0)
	check_eq(_notes(), ["1@0"], "click places a tap on the beat")

	await _drag(2.0, 3.0, 1)
	check_eq(_notes(), ["1@0", "2@1+1"], "dragging up places a hold")

	await _click_at(2.5, 1)
	check_eq(_notes(), ["1@0", "2@1+1"], "no note inside a hold")
	check(_status().contains("overlap"), "says why the click did nothing")

	await _click_at(1.0, 0, MOUSE_BUTTON_RIGHT)
	check_eq(_notes(), ["2@1+1"], "right-click deletes")

	await _key(KEY_Z, true)
	check_eq(_notes(), ["1@0", "2@1+1"], "Ctrl+Z brings it back")
	await _key(KEY_Y, true)
	check_eq(_notes(), ["2@1+1"], "Ctrl+Y deletes it again")
	await _key(KEY_Z, true)
	check(doc.modified, "edits mark the chart unsaved")

## Record on, play from beat 4, and tap a lane key and hold another. Both come
## after beat 7, where playback (last note + 4 beats) would stop if it were
## not recording.
func _recording_take() -> void:
	for i in 4:
		await _wheel(true, true)  # Shift+wheel: one beat per notch
	check_near(_timeline.view_beat, 4.0, "Shift+wheel scrolls a beat at a time")

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

	check_eq(_notes(), RECORDED,
			"a short press records a tap, a long one a hold, both on the grid")

	await _key(KEY_Z, true)
	check_eq(_notes(), ["1@0", "2@1+1"], "one Ctrl+Z undoes the whole take")
	await _key(KEY_Y, true)
	check_eq(_notes(), RECORDED, "and Ctrl+Y redoes it")

	await _press_button("%RecordButton")
	check(not _editor.recording, "the record button turns recording off")

## Load an .ogg, name the file and save with Ctrl+S.
func _music_and_save() -> void:
	_editor.call("_on_music_selected", ProjectSettings.globalize_path(MUSIC_FIXTURE))
	check(FileAccess.file_exists(_dir.path_join("beep.ogg")), "the music is copied next to the chart")
	check_eq(_editor.doc.music, "beep.ogg", "and named relative to it")
	check_near(_timeline.music_beats, 2.0, "the one-second clip is two beats at 120 BPM", 0.05)

	(_editor.get_node(^"%TitleEdit") as LineEdit).text = "Editor Test"
	(_editor.get_node(^"%TitleEdit") as LineEdit).text_changed.emit("Editor Test")
	(_editor.get_node(^"%FileEdit") as LineEdit).text = "Editor Test!"
	await _key(KEY_S, true)

	var path := _dir.path_join("editor_test.json")
	check(FileAccess.file_exists(path), "Ctrl+S saves under a safe file name")
	check(not _editor.doc.modified, "saved means not modified")
	var chart := Chart.load_from_file(path)
	if chart == null:
		failures.append("the saved chart loads")
		return
	check_eq(chart.title, "Editor Test", "the title is saved")
	check_eq(chart.notes.size(), RECORDED.size(), "every note is saved")
	if chart.notes.size() == RECORDED.size():
		check_near(chart.notes[3].time, 4.0, "beat 8 at 120 BPM is 4s")
		check_near(chart.notes[3].end_time, 4.5, "and its hold ends at beat 9")
	check(ChartStore.load_music(path, chart.music_path) != null, "the saved chart finds its music")

## Test play from the cursor, then come back to the same document.
func _test_play_comes_back() -> void:
	var doc: ChartDoc = _editor.doc
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
	check_eq((_editor.get_node(^"%FileEdit") as LineEdit).text, "editor_test", "with the same file name")
	check(doc.can_undo(), "with its undo history")
	check_eq(GameState.play_from_time, 0.0, "the next run plays from the top again")

## Esc leaves at once when saved and asks first when not. A file that is
## somebody else's is not overwritten.
func _leaving() -> void:
	await _click_at(8.0, 0)
	check(_editor.doc.modified, "a new edit is unsaved")
	await _key(KEY_ESCAPE)
	var dialog := _editor.get_node(^"%LeaveDialog") as ConfirmationDialog
	check(dialog.visible, "Esc with unsaved changes asks first")
	check(GameState.editor_doc != null, "and does not leave yet")
	dialog.get_ok_button().pressed.emit()
	check(GameState.editor_doc == null, "leaving forgets the session")

	_close_editor()
	GameState.open_editor("")
	await _open_editor()
	await _click_at(0.0, 0)
	(_editor.get_node(^"%FileEdit") as LineEdit).text = "editor_test"
	check_eq(_editor.save(), "", "a new chart does not overwrite another chart's file")
	check(_status().contains("already exists"), "and says why")
	var other := Chart.load_from_file(_dir.path_join("editor_test.json"))
	check(other != null and other.notes.size() == RECORDED.size(), "the other chart is untouched")

## Edit on a chart from song select opens it with every note.
func _opening_a_bundled_chart() -> void:
	_close_editor()
	var path := "res://songs/03_hold_on.json"
	GameState.open_editor(path)
	await _open_editor()
	var chart := Chart.load_from_file(path)
	check_eq(_editor.doc.notes.size(), chart.notes.size(), "every note of %s is there" % path)
	check_eq(_editor.doc.title, chart.title, "with its title")
	check_eq(_editor.source_path, path, "and saves back to the same file")
	check(not _editor.doc.modified, "opening is not an edit")
	await _key(KEY_ESCAPE)
	check(GameState.editor_doc == null and GameState.editor_state.is_empty(),
			"Esc without changes leaves at once")

## A bundled chart edited in the exported game saves to user://, not next to
## the original. Music loaded for it is copied there and must still be found,
## before and after saving.
func _music_for_a_chart_from_elsewhere() -> void:
	_close_editor()
	GameState.open_editor("res://songs/03_hold_on.json")
	await _open_editor()
	_editor.call("_on_music_selected", ProjectSettings.globalize_path(MUSIC_FIXTURE))
	check_eq((_editor.get_node(^"%MusicLabel") as Label).text, "beep.ogg", "the copied music is found")
	check(_timeline.music_beats > 0.0, "and its length is known")

	(_editor.get_node(^"%FileEdit") as LineEdit).text = "hold_on_copy"
	var path := _editor.save()
	check_eq(path, _dir.path_join("hold_on_copy.json"), "saved to the writable folder")
	var chart := Chart.load_from_file(path)
	if chart == null:
		failures.append("the copy loads")
		return
	check_eq(chart.music_path, "beep.ogg", "the music is named relative to the copy, next to it")
	check(ChartStore.load_music(path, chart.music_path) != null, "and the copy finds it")

func _open_editor() -> void:
	_editor = EDITOR_SCENE.instantiate() as ChartEditor
	_editor.save_dir = _dir
	_host.add_child(_editor)
	_timeline = _editor.get_node(^"%Timeline")
	await _frames(2)  # let the containers lay out

func _close_editor() -> void:
	if _editor != null:
		_editor.free()
		_editor = null

func _clean_up() -> void:
	for file in ["editor_test.json", "hold_on_copy.json", "beep.ogg"]:
		if FileAccess.file_exists(_dir.path_join(file)):
			DirAccess.remove_absolute(_dir.path_join(file))
	if FileAccess.file_exists(ChartEditor.TEST_CHART):
		DirAccess.remove_absolute(ChartEditor.TEST_CHART)
	if DirAccess.dir_exists_absolute(_dir):
		DirAccess.remove_absolute(_dir)

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
	return (_editor.get_node(^"%StatusLabel") as Label).text

func _point(beat: float, lane: int) -> Vector2:
	return _timeline.get_global_transform() * Vector2(_timeline.lane_center_x(lane), _timeline.beat_to_y(beat))

func _click_at(beat: float, lane: int, button := MOUSE_BUTTON_LEFT) -> void:
	var at := _point(beat, lane)
	await _mouse_move(at)
	await _mouse_button(at, button, true)
	await _mouse_button(at, button, false)

func _drag(from_beat: float, to_beat: float, lane: int) -> void:
	var from := _point(from_beat, lane)
	var to := _point(to_beat, lane)
	await _mouse_move(from)
	await _mouse_button(from, MOUSE_BUTTON_LEFT, true)
	await _mouse_move(from.lerp(to, 0.5), MOUSE_BUTTON_MASK_LEFT)
	await _mouse_move(to, MOUSE_BUTTON_MASK_LEFT)
	await _mouse_button(to, MOUSE_BUTTON_LEFT, false)

func _wheel(up: bool, shift := false) -> void:
	var at := _point(_timeline.view_beat + 1.0, 0)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	_place(event, at)
	event.shift_pressed = shift
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(1)
	var release := event.duplicate() as InputEventMouseButton
	release.pressed = false
	Input.parse_input_event(release)
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

func _mouse_button(at: Vector2, button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	_place(event, at)
	event.pressed = pressed
	if pressed:
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	Input.parse_input_event(event)
	await _frames(1)

## Clicks a button in the side panel where it is on screen, scrolling the
## panel to it first as a person would.
func _press_button(unique_name: String) -> void:
	var button := _editor.get_node(NodePath(unique_name)) as Button
	(_editor.get_node(^"Layout/Side/Scroll") as ScrollContainer).ensure_control_visible(button)
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

func _frames(count: int) -> void:
	for i in count:
		await _host.get_tree().process_frame

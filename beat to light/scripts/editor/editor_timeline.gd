class_name EditorTimeline
extends Control

## The editor's chart view: bar numbers, the song's waveform, then the lanes,
## with time running up the screen as in play. The line near the bottom is the
## cursor; playback starts there, and the chart scrolls past it while playing.
##
## The mouse works on the chart directly:
##   empty lane       click: tap note; drag up or down: hold note
##   note             click: select; drag: move (every selected note)
##   end of a hold    drag: change its length
##   Shift + drag     select everything in a box (Ctrl adds to the selection)
##   right button     delete what is under it; drag to delete along the way
##   waveform/ruler   click: jump there; drag: scroll (as does the middle button)
## The timeline keeps the selection and shows what a drag would do; the editor
## makes the actual changes, so they can be undone.

signal place_requested(beat: float, lane: int, length: float)
signal move_requested(notes: Array[EditNote], beats: float, lanes: int)
signal resize_requested(note: EditNote, length: float)
## A right-button drag began; erase_requested follows for each spot it passes.
signal erase_started
signal erase_requested(beat: float, lane: int)
signal seek_requested(beat: float)
signal selection_changed
## The user scrolled or zoomed.
signal view_moved

const LANE_WIDTH := 96.0
const RULER_WIDTH := 56.0
const WAVE_WIDTH := 120.0
const WAVE_GAP := 14.0
## Distance from the bottom edge to the cursor line.
const CURSOR_FROM_BOTTOM := 96.0
const NOTE_HEIGHT := 18.0
const HOLD_WIDTH := 56.0
## How close (in pixels) to the end of a hold grabs the end instead of the body.
const END_GRAB := 7.0
## A press that moves less than this is a click, not a drag.
const DRAG_THRESHOLD := 4.0
const MIN_PX_PER_BEAT := 30.0
const MAX_PX_PER_BEAT := 480.0
const FLASH_TIME := 0.12

const WAVE_COLOR := Color(0.45, 0.7, 1.0, 0.55)
const SELECT_COLOR := Color(1, 1, 1)
const BLOCKED_COLOR := Color(1, 0.3, 0.3, 0.6)

enum Drag { NONE, CREATE, MOVE, RESIZE, BOX, ERASE, SEEK, PAN }

var doc: ChartDoc
## Grid steps per beat; positions snap to these.
var division := 4
## The beat sitting on the cursor line.
var view_beat := 0.0
var px_per_beat := 120.0
## Where the music ends, in beats, drawn as a marker. 0 when there is no music.
var music_beats := 0.0
## The song's waveform; drawn when it has been decoded.
var waveform: Waveform
## Selected notes. Moves, deletes and copies work on these.
var selection: Array[EditNote] = []

var _drag := Drag.NONE
var _press_pos := Vector2.ZERO
var _dragged := false
var _hover := Vector2(-1, -1)
var _press_lane := -1
var _press_beat := 0.0
var _grabbed: EditNote
var _create_end := 0.0
var _move_beats := 0.0
var _move_lanes := 0
var _resize_length := 0.0
var _box_additive := false
var _pan_from := 0.0
var _last_erase := Vector2.ZERO
var _flash := {}  # lane -> seconds left

func _ready() -> void:
	# Keys go to the editor, never to the timeline: with no control focused,
	# the arrow keys reach the editor instead of moving focus around.
	focus_mode = Control.FOCUS_NONE
	clip_contents = true

func lane_count() -> int:
	return doc.lane_count if doc != null else 4

# --- Geometry ---------------------------------------------------------------

func cursor_y() -> float:
	return size.y - CURSOR_FROM_BOTTOM

func beat_to_y(beat: float) -> float:
	return cursor_y() - (beat - view_beat) * px_per_beat

func y_to_beat(y: float) -> float:
	return view_beat + (cursor_y() - y) / px_per_beat

## Left edge of the whole drawing (ruler, waveform and lanes), centred.
func content_left() -> float:
	return maxf((size.x - (RULER_WIDTH + WAVE_WIDTH + WAVE_GAP + lane_count() * LANE_WIDTH)) * 0.5, 8.0)

func wave_left() -> float:
	return content_left() + RULER_WIDTH

func lanes_left() -> float:
	return wave_left() + WAVE_WIDTH + WAVE_GAP

func lane_center_x(lane: int) -> float:
	return lanes_left() + (lane + 0.5) * LANE_WIDTH

## The lane under [param x], or -1 outside the lanes.
func x_to_lane(x: float) -> int:
	var lane := _lane_index(x)
	return lane if lane >= 0 and lane < lane_count() else -1

## True over the ruler and the waveform, where a click moves the cursor.
func in_seek_area(x: float) -> bool:
	return x >= content_left() and x < lanes_left() - WAVE_GAP * 0.5

## The grid position nearest to [param y], never before the start of the chart.
func snapped_beat_at(y: float) -> float:
	return maxf(ChartDoc.quantize(y_to_beat(y), division), 0.0)

func step_beats() -> float:
	return 1.0 / maxi(division, 1)

## The note under [param pos] and which part: {note, end} where end is true on
## the end of a hold. Empty when there is no note there.
func hit_test(pos: Vector2) -> Dictionary:
	var lane := x_to_lane(pos.x)
	if lane < 0 or doc == null:
		return {}
	var body_hit: EditNote = null
	for note in doc.notes:
		if note.lane != lane:
			continue
		var head_y := beat_to_y(note.beat)
		if note.is_hold():
			var end_y := beat_to_y(note.end_beat())
			if absf(pos.y - end_y) <= END_GRAB:
				return {"note": note, "end": true}
			if pos.y >= end_y and pos.y <= head_y:
				body_hit = note
		if absf(pos.y - head_y) <= NOTE_HEIGHT * 0.5 + 2.0:
			return {"note": note, "end": false}
	if body_hit != null:
		return {"note": body_hit, "end": false}
	return {}

# --- Selection --------------------------------------------------------------

func select(notes: Array[EditNote]) -> void:
	selection = notes.duplicate()
	selection_changed.emit()
	queue_redraw()

func clear_selection() -> void:
	if selection.is_empty():
		return
	selection.clear()
	selection_changed.emit()
	queue_redraw()

func is_selected(note: EditNote) -> bool:
	return selection.has(note)

## Drops selected notes that are no longer in the chart (after an undo).
func prune_selection() -> void:
	if doc == null:
		return
	var kept := selection.filter(func(n: EditNote) -> bool: return doc.notes.has(n))
	if kept.size() != selection.size():
		selection.assign(kept)
		selection_changed.emit()

## Lights a lane up briefly (a key press while recording).
func flash(lane: int) -> void:
	_flash[lane] = FLASH_TIME
	queue_redraw()

# --- Input ------------------------------------------------------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _drag == Drag.NONE:
		_hover = Vector2(-1, -1)
		queue_redraw()

func _process(delta: float) -> void:
	if _flash.is_empty():
		return
	for lane in _flash.keys():
		_flash[lane] -= delta
		if _flash[lane] <= 0.0:
			_flash.erase(lane)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		_on_motion(motion)
		return
	var button := event as InputEventMouseButton
	if button != null:
		_on_button(button)

func _on_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press_left(event)
			else:
				_release_left(event.position)
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_drag = Drag.ERASE
				_last_erase = event.position
				erase_started.emit()
				_erase_at(event.position)
			elif _drag == Drag.ERASE:
				_drag = Drag.NONE
		MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_begin(Drag.PAN, event.position)
			elif _drag == Drag.PAN:
				_drag = Drag.NONE
				view_moved.emit()
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_wheel(event)
		_:
			return
	accept_event()
	queue_redraw()

func _press_left(event: InputEventMouseButton) -> void:
	# A click on the chart takes the keyboard away from any text field.
	get_viewport().gui_release_focus()
	var pos := event.position
	if in_seek_area(pos.x):
		_begin(Drag.SEEK, pos)
		return
	var lane := x_to_lane(pos.x)
	if lane < 0:
		return
	var toggle := event.is_command_or_control_pressed()
	if event.shift_pressed:
		_begin(Drag.BOX, pos)
		_box_additive = toggle
		return
	var hit := hit_test(pos)
	if hit.is_empty():
		clear_selection()
		_begin(Drag.CREATE, pos)
		_press_lane = lane
		_press_beat = snapped_beat_at(pos.y)
		_create_end = _press_beat
		return
	var note: EditNote = hit.note
	if toggle:
		if is_selected(note):
			selection.erase(note)
			selection_changed.emit()
			return
		selection.append(note)
		selection_changed.emit()
	elif not is_selected(note):
		var only: Array[EditNote] = [note]
		select(only)
	_grabbed = note
	_press_lane = lane
	if hit.end:
		_begin(Drag.RESIZE, pos)
		_resize_length = note.length
	else:
		_begin(Drag.MOVE, pos)
		_move_beats = 0.0
		_move_lanes = 0

func _begin(kind: Drag, pos: Vector2) -> void:
	_drag = kind
	_press_pos = pos
	_dragged = false
	_pan_from = view_beat

func _release_left(pos: Vector2) -> void:
	var kind := _drag
	_drag = Drag.NONE
	match kind:
		Drag.CREATE:
			var start := minf(_press_beat, _create_end)
			place_requested.emit(start, _press_lane, absf(_create_end - _press_beat))
		Drag.MOVE:
			if _dragged and (not is_zero_approx(_move_beats) or _move_lanes != 0):
				move_requested.emit(selection.duplicate(), _move_beats, _move_lanes)
		Drag.RESIZE:
			if _dragged and not is_equal_approx(_resize_length, _grabbed.length):
				resize_requested.emit(_grabbed, _resize_length)
		Drag.BOX:
			var found := _box_notes()
			if _box_additive:
				for note in found:
					if not is_selected(note):
						selection.append(note)
				selection_changed.emit()
			else:
				select(found)
		Drag.SEEK:
			seek_requested.emit(snapped_beat_at(pos.y))
		Drag.PAN:
			view_moved.emit()

func _on_motion(event: InputEventMouseMotion) -> void:
	_hover = event.position
	var pos := event.position
	if _drag != Drag.NONE and _press_pos.distance_to(pos) >= DRAG_THRESHOLD:
		_dragged = true
	match _drag:
		Drag.CREATE:
			_create_end = snapped_beat_at(pos.y)
		Drag.MOVE:
			_move_beats = ChartDoc.quantize(y_to_beat(pos.y) - y_to_beat(_press_pos.y), division)
			_move_lanes = _lane_index(pos.x) - _press_lane
		Drag.RESIZE:
			_resize_length = maxf(snapped_beat_at(pos.y) - _grabbed.beat, 0.0)
		Drag.ERASE:
			_erase_along(_last_erase, pos)
			_last_erase = pos
		Drag.SEEK, Drag.PAN:
			if _dragged:
				_drag = Drag.PAN
				view_beat = maxf(_pan_from + (pos.y - _press_pos.y) / px_per_beat, 0.0)
	_update_cursor_shape(pos)
	queue_redraw()

func _wheel(event: InputEventMouseButton) -> void:
	var up := event.button_index == MOUSE_BUTTON_WHEEL_UP
	if event.is_command_or_control_pressed():
		# Zoom around the beat under the mouse, so it stays put on screen.
		var anchor := y_to_beat(event.position.y)
		px_per_beat = clampf(px_per_beat * (1.15 if up else 1.0 / 1.15), MIN_PX_PER_BEAT, MAX_PX_PER_BEAT)
		view_beat = maxf(anchor - (cursor_y() - event.position.y) / px_per_beat, 0.0)
	else:
		var amount := step_beats() * (4.0 if event.shift_pressed else 1.0)
		view_beat = maxf(view_beat + (amount if up else -amount), 0.0)
	view_moved.emit()

func _erase_at(pos: Vector2) -> void:
	var lane := x_to_lane(pos.x)
	if lane >= 0:
		erase_requested.emit(y_to_beat(pos.y), lane)

## Erases at points no further apart than half a note, so a quick sweep does
## not skip anything.
func _erase_along(from: Vector2, to: Vector2) -> void:
	var steps := maxi(ceili(from.distance_to(to) / (NOTE_HEIGHT * 0.5)), 1)
	for i in range(1, steps + 1):
		_erase_at(from.lerp(to, float(i) / steps))

func _update_cursor_shape(pos: Vector2) -> void:
	var shape := Control.CURSOR_ARROW
	if _drag == Drag.PAN:
		shape = Control.CURSOR_DRAG
	elif _drag == Drag.MOVE:
		shape = Control.CURSOR_MOVE
	elif _drag == Drag.RESIZE:
		shape = Control.CURSOR_VSIZE
	elif in_seek_area(pos.x):
		shape = Control.CURSOR_POINTING_HAND
	else:
		var hit := hit_test(pos)
		if not hit.is_empty():
			shape = Control.CURSOR_VSIZE if hit.end else Control.CURSOR_MOVE
		elif x_to_lane(pos.x) >= 0:
			shape = Control.CURSOR_CROSS
	mouse_default_cursor_shape = shape

func _box_notes() -> Array[EditNote]:
	if doc == null:
		var none: Array[EditNote] = []
		return none
	var a := _press_pos
	var b := _hover
	var from_lane := clampi(_lane_index(minf(a.x, b.x)), 0, lane_count() - 1)
	var to_lane := clampi(_lane_index(maxf(a.x, b.x)), 0, lane_count() - 1)
	return doc.notes_in(y_to_beat(maxf(a.y, b.y)), y_to_beat(minf(a.y, b.y)), from_lane, to_lane)

func _lane_index(x: float) -> int:
	return floori((x - lanes_left()) / LANE_WIDTH)

## Where the current move or resize would put the selection, for the preview.
func _pending_targets() -> Array[Dictionary]:
	if _drag == Drag.MOVE and _dragged:
		return ChartDoc.shifted(selection, _move_beats, _move_lanes)
	var targets: Array[Dictionary] = []
	if _drag == Drag.RESIZE and _dragged:
		targets.append({"beat": _grabbed.beat, "lane": _grabbed.lane, "length": _resize_length})
	return targets

# --- Drawing ----------------------------------------------------------------

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var left := lanes_left()
	var width := lane_count() * LANE_WIDTH
	var wave_x := wave_left()

	draw_rect(Rect2(wave_x, 0.0, WAVE_WIDTH, size.y), Color(1, 1, 1, 0.03))
	for lane in lane_count():
		var x := left + lane * LANE_WIDTH
		draw_rect(Rect2(x, 0.0, LANE_WIDTH, size.y), Color(1, 1, 1, 0.035 if lane % 2 == 0 else 0.06))
		if _flash.has(lane):
			var glow := _lane_color(lane)
			glow.a = 0.3 * _flash[lane] / FLASH_TIME
			draw_rect(Rect2(x, 0.0, LANE_WIDTH, size.y), glow)

	_draw_waveform(wave_x)

	# Grid: bar lines (every 4 beats) strongest, then beats, then subdivisions.
	# Beat lines run through the waveform too, to line notes up with the sound.
	var first := floori(maxf(y_to_beat(size.y), 0.0) * division)
	var last := ceili(y_to_beat(0.0) * division)
	for k in range(first, last + 1):
		var y := beat_to_y(float(k) / division)
		if k % (4 * division) == 0:
			draw_line(Vector2(wave_x, y), Vector2(left + width, y), Color(1, 1, 1, 0.45), 2.0)
			draw_string(font, Vector2(content_left(), y + 5.0), "bar %d" % (k / (4 * division) + 1),
					HORIZONTAL_ALIGNMENT_LEFT, RULER_WIDTH - 6.0, 13, Color(1, 1, 1, 0.6))
		elif k % division == 0:
			draw_line(Vector2(wave_x, y), Vector2(left + width, y), Color(1, 1, 1, 0.2), 1.0)
		else:
			draw_line(Vector2(left, y), Vector2(left + width, y), Color(1, 1, 1, 0.07), 1.0)

	if music_beats > 0.0:
		var y_end := beat_to_y(music_beats)
		draw_line(Vector2(wave_x, y_end), Vector2(left + width, y_end), Color("ffa94d"), 2.0)
		draw_string(font, Vector2(left + width + 8.0, y_end + 5.0), "music ends",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("ffa94d"))

	var pending := _pending_targets()
	var moving := not pending.is_empty()
	if doc != null:
		var top := y_to_beat(0.0)
		var bottom := y_to_beat(size.y)
		for note in doc.notes:
			if note.end_beat() < bottom or note.beat > top:
				continue
			var faded := moving and (is_selected(note) or note == _grabbed)
			_draw_note(note.beat, note.lane, note.length, 0.3 if faded else 1.0, is_selected(note))

	if moving:
		var movers: Array[EditNote] = selection
		if _drag == Drag.RESIZE:
			movers = [_grabbed]
		var ok := doc.can_relocate(movers, pending)
		for t in pending:
			_draw_note(t.beat, t.lane, t.length, 0.8, false, not ok)
	elif _drag == Drag.CREATE:
		var start := minf(_press_beat, _create_end)
		var ok := doc == null or doc.can_place(start, _press_lane, absf(_create_end - _press_beat))
		_draw_note(start, _press_lane, absf(_create_end - _press_beat), 0.55, false, not ok)
	elif _drag == Drag.NONE and _hover.x >= 0.0:
		var lane := x_to_lane(_hover.x)
		if lane >= 0 and hit_test(_hover).is_empty():
			_draw_note(snapped_beat_at(_hover.y), lane, 0.0, 0.3, false)

	if _drag == Drag.BOX:
		var box := Rect2(_press_pos, Vector2.ZERO).expand(_hover)
		draw_rect(box, Color(1, 1, 1, 0.08))
		draw_rect(box, Color(1, 1, 1, 0.6), false, 1.0)

	var cy := cursor_y()
	draw_line(Vector2(wave_x, cy), Vector2(left + width + 12.0, cy), Color(1, 1, 1, 0.9), 3.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(wave_x - 10.0, cy - 7.0), Vector2(wave_x, cy), Vector2(wave_x - 10.0, cy + 7.0)]),
		Color(1, 1, 1, 0.9))

func _draw_waveform(x: float) -> void:
	if waveform == null or not waveform.is_ready() or waveform.loudest <= 0.0 or doc == null:
		return
	var spb := doc.seconds_per_beat()
	var mid := x + WAVE_WIDTH * 0.5
	var scale := (WAVE_WIDTH * 0.5 - 4.0) / waveform.loudest
	var row := 2.0
	var y := 0.0
	while y < size.y:
		# Song time = chart time + offset; the row covers y .. y + row.
		var t_top := y_to_beat(y) * spb + doc.offset
		var t_bottom := y_to_beat(y + row) * spb + doc.offset
		if t_top >= 0.0:
			var half := waveform.peak_between(maxf(t_bottom, 0.0), t_top) * scale
			if half > 0.5:
				draw_rect(Rect2(mid - half, y, half * 2.0, row), WAVE_COLOR)
		y += row

func _draw_note(beat: float, lane: int, length: float, alpha: float, selected: bool, blocked := false) -> void:
	var color := BLOCKED_COLOR if blocked else _lane_color(lane)
	color.a = alpha if not blocked else BLOCKED_COLOR.a
	var x := lane_center_x(lane)
	var y := beat_to_y(beat)
	if length > 0.0:
		var y_end := beat_to_y(beat + length)
		var body := color
		body.a = color.a * 0.55
		draw_rect(Rect2(x - HOLD_WIDTH * 0.5, y_end, HOLD_WIDTH, y - y_end), body)
		draw_rect(Rect2(x - LANE_WIDTH * 0.42, y_end - 3.0, LANE_WIDTH * 0.84, 6.0), color)
		if selected:
			draw_rect(Rect2(x - HOLD_WIDTH * 0.5, y_end, HOLD_WIDTH, y - y_end), SELECT_COLOR, false, 2.0)
	var head := Rect2(x - LANE_WIDTH * 0.42, y - NOTE_HEIGHT * 0.5, LANE_WIDTH * 0.84, NOTE_HEIGHT)
	draw_rect(head, color)
	if selected:
		draw_rect(head.grow(3.0), SELECT_COLOR, false, 3.0)
	else:
		draw_rect(head, Color(1, 1, 1, color.a * 0.6), false, 1.5)

func _lane_color(lane: int) -> Color:
	return Playfield.LANE_COLORS[lane % Playfield.LANE_COLORS.size()]

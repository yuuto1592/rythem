class_name EditorTimeline
extends Control

## The editor's chart view: lanes left to right, time running up the screen as
## in play. The line near the bottom is the cursor; playback starts there, and
## the chart scrolls past it while playing.
##
## The timeline only draws and reports what the mouse did. The editor decides
## what that means for the chart.

signal place_requested(beat: float, lane: int, length: float)
signal delete_requested(beat: float, lane: int)
## The user scrolled or zoomed.
signal view_moved

const LANE_WIDTH := 96.0
## Distance from the bottom edge to the cursor line.
const CURSOR_FROM_BOTTOM := 96.0
const NOTE_HEIGHT := 18.0
const HOLD_WIDTH := 56.0
const MIN_PX_PER_BEAT := 30.0
const MAX_PX_PER_BEAT := 480.0
const FLASH_TIME := 0.12

var doc: ChartDoc
## Grid steps per beat; positions snap to these.
var division := 4
## The beat sitting on the cursor line.
var view_beat := 0.0
var px_per_beat := 120.0
## Where the music ends, in beats, drawn as a marker. 0 when there is no music.
var music_beats := 0.0

var _hover_lane := -1
var _hover_beat := 0.0
var _drag_lane := -1
var _drag_start := 0.0
var _drag_end := 0.0
var _flash := {}  # lane -> seconds left

func _ready() -> void:
	focus_mode = Control.FOCUS_CLICK
	clip_contents = true

func lane_count() -> int:
	return doc.lane_count if doc != null else 4

func cursor_y() -> float:
	return size.y - CURSOR_FROM_BOTTOM

func beat_to_y(beat: float) -> float:
	return cursor_y() - (beat - view_beat) * px_per_beat

func y_to_beat(y: float) -> float:
	return view_beat + (cursor_y() - y) / px_per_beat

func lanes_left() -> float:
	return (size.x - lane_count() * LANE_WIDTH) * 0.5

func lane_center_x(lane: int) -> float:
	return lanes_left() + (lane + 0.5) * LANE_WIDTH

## The lane under [param x], or -1 outside the lanes.
func x_to_lane(x: float) -> int:
	var lane := floori((x - lanes_left()) / LANE_WIDTH)
	return lane if lane >= 0 and lane < lane_count() else -1

## The grid position nearest to [param y], never before the start of the chart.
func snapped_beat_at(y: float) -> float:
	return maxf(ChartDoc.quantize(y_to_beat(y), division), 0.0)

func step_beats() -> float:
	return 1.0 / maxi(division, 1)

## Lights a lane up briefly (a key press while recording).
func flash(lane: int) -> void:
	_flash[lane] = FLASH_TIME
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
		_hover_lane = x_to_lane(motion.position.x)
		_hover_beat = snapped_beat_at(motion.position.y)
		if _drag_lane >= 0:
			_drag_end = maxf(_hover_beat, _drag_start)
		queue_redraw()
		return
	var button := event as InputEventMouseButton
	if button != null:
		_on_mouse_button(button)

func _on_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				var lane := x_to_lane(event.position.x)
				if lane >= 0:
					_drag_lane = lane
					_drag_start = snapped_beat_at(event.position.y)
					_drag_end = _drag_start
					accept_event()
			elif _drag_lane >= 0:
				var lane := _drag_lane
				_drag_lane = -1
				# Dragging up stretches a hold; a click without a drag is a tap.
				place_requested.emit(_drag_start, lane, maxf(_drag_end - _drag_start, 0.0))
				accept_event()
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				var lane := x_to_lane(event.position.x)
				if lane >= 0:
					delete_requested.emit(y_to_beat(event.position.y), lane)
					accept_event()
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				var up := event.button_index == MOUSE_BUTTON_WHEEL_UP
				if event.is_command_or_control_pressed():
					px_per_beat = clampf(px_per_beat * (1.15 if up else 1.0 / 1.15), MIN_PX_PER_BEAT, MAX_PX_PER_BEAT)
				else:
					var amount := step_beats() * (4.0 if event.shift_pressed else 1.0)
					view_beat = maxf(view_beat + (amount if up else -amount), 0.0)
				view_moved.emit()
				accept_event()
	queue_redraw()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var left := lanes_left()
	var width := lane_count() * LANE_WIDTH

	for lane in lane_count():
		var x := left + lane * LANE_WIDTH
		draw_rect(Rect2(x, 0.0, LANE_WIDTH, size.y), Color(1, 1, 1, 0.035 if lane % 2 == 0 else 0.06))
		if _flash.has(lane):
			var glow := _lane_color(lane)
			glow.a = 0.3 * _flash[lane] / FLASH_TIME
			draw_rect(Rect2(x, 0.0, LANE_WIDTH, size.y), glow)

	# Grid: bar lines (every 4 beats) strongest, then beats, then subdivisions.
	var first := floori(maxf(y_to_beat(size.y), 0.0) * division)
	var last := ceili(y_to_beat(0.0) * division)
	for k in range(first, last + 1):
		var y := beat_to_y(float(k) / division)
		if k % (4 * division) == 0:
			draw_line(Vector2(left, y), Vector2(left + width, y), Color(1, 1, 1, 0.45), 2.0)
			draw_string(font, Vector2(left - 64.0, y + 5.0), "bar %d" % (k / (4 * division) + 1),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.55))
		elif k % division == 0:
			draw_line(Vector2(left, y), Vector2(left + width, y), Color(1, 1, 1, 0.2), 1.0)
		else:
			draw_line(Vector2(left, y), Vector2(left + width, y), Color(1, 1, 1, 0.07), 1.0)

	if music_beats > 0.0:
		var y_end := beat_to_y(music_beats)
		draw_line(Vector2(left, y_end), Vector2(left + width, y_end), Color("ffa94d"), 2.0)
		draw_string(font, Vector2(left + width + 8.0, y_end + 5.0), "music ends",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("ffa94d"))

	if doc != null:
		var top := y_to_beat(0.0)
		var bottom := y_to_beat(size.y)
		for note in doc.notes:
			if note.end_beat() >= bottom and note.beat <= top:
				_draw_note(note.beat, note.lane, note.length, 1.0)

	if _drag_lane >= 0:
		_draw_note(_drag_start, _drag_lane, _drag_end - _drag_start, 0.55)
	elif _hover_lane >= 0:
		_draw_note(_hover_beat, _hover_lane, 0.0, 0.3)

	var cy := cursor_y()
	draw_line(Vector2(left - 12.0, cy), Vector2(left + width + 12.0, cy), Color(1, 1, 1, 0.9), 3.0)

func _draw_note(beat: float, lane: int, length: float, alpha: float) -> void:
	var color := _lane_color(lane)
	color.a = alpha
	var x := lane_center_x(lane)
	var y := beat_to_y(beat)
	if length > 0.0:
		var y_end := beat_to_y(beat + length)
		var body := color
		body.a = alpha * 0.55
		draw_rect(Rect2(x - HOLD_WIDTH * 0.5, y_end, HOLD_WIDTH, y - y_end), body)
		draw_rect(Rect2(x - LANE_WIDTH * 0.42, y_end - 3.0, LANE_WIDTH * 0.84, 6.0), color)
	var head := Rect2(x - LANE_WIDTH * 0.42, y - NOTE_HEIGHT * 0.5, LANE_WIDTH * 0.84, NOTE_HEIGHT)
	draw_rect(head, color)
	draw_rect(head, Color(1, 1, 1, alpha * 0.6), false, 1.5)

func _lane_color(lane: int) -> Color:
	return Playfield.LANE_COLORS[lane % Playfield.LANE_COLORS.size()]

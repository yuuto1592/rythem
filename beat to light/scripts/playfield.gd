class_name Playfield
extends Node2D

## Draws the lanes and owns the playfield geometry: every "where on screen
## does this go?" question is answered here, so the rest of the game only
## deals in lanes and seconds.
##
## The node's own origin is the horizontal centre of the playfield, so lane
## positions are symmetrical around x = 0.

const LANE_WIDTH := 112.0
## Distance from the top of the viewport down to the judge line.
const JUDGE_Y := 560.0
const JUDGE_LINE_THICKNESS := 5.0
## How long a lane stays lit after a key press, in seconds.
const FLASH_TIME := 0.12

const LANE_COLORS := [
	Color("ff7ab6"),
	Color("7ad7ff"),
	Color("ffd97a"),
	Color("9bff7a"),
	Color("c89bff"),
	Color("7affd1"),
]

var lane_count := 4
var scroll_time := 1.0

var _flash: Array[float] = []

func _ready() -> void:
	configure(lane_count, scroll_time)

func configure(p_lane_count: int, p_scroll_time: float) -> void:
	lane_count = maxi(p_lane_count, 1)
	scroll_time = maxf(p_scroll_time, 0.1)
	_flash.resize(lane_count)
	_flash.fill(0.0)
	queue_redraw()

func lane_color(lane: int) -> Color:
	return LANE_COLORS[lane % LANE_COLORS.size()]

func width() -> float:
	return lane_count * LANE_WIDTH

func lane_x(lane: int) -> float:
	return -width() * 0.5 + (lane + 0.5) * LANE_WIDTH

## Vertical position of a note that is [param seconds_until] away from being hit.
## At 0 it sits on the judge line; at [member scroll_time] it is at the top edge.
func y_for(seconds_until: float) -> float:
	return JUDGE_Y - (seconds_until / scroll_time) * JUDGE_Y

## Lights up a lane to acknowledge a key press.
func flash(lane: int) -> void:
	if lane >= 0 and lane < _flash.size():
		_flash[lane] = FLASH_TIME
		queue_redraw()

func _process(delta: float) -> void:
	var lit := false
	for i in _flash.size():
		if _flash[i] > 0.0:
			_flash[i] = maxf(_flash[i] - delta, 0.0)
			lit = true
	if lit:
		queue_redraw()

func _draw() -> void:
	var left := -width() * 0.5
	var bottom := JUDGE_Y + 60.0

	for lane in lane_count:
		var x := left + lane * LANE_WIDTH
		var base := Color(1, 1, 1, 0.04 if lane % 2 == 0 else 0.07)
		draw_rect(Rect2(x, 0.0, LANE_WIDTH, bottom), base)

		var strength := _flash[lane] / FLASH_TIME if lane < _flash.size() else 0.0
		if strength > 0.0:
			var glow := lane_color(lane)
			glow.a = 0.28 * strength
			draw_rect(Rect2(x, 0.0, LANE_WIDTH, JUDGE_Y), glow)

		# Receptor: where the note has to be when you press the key.
		var receptor := Rect2(x + 8.0, JUDGE_Y - Note.HEIGHT * 0.5, LANE_WIDTH - 16.0, Note.HEIGHT)
		draw_rect(receptor, Color(1, 1, 1, 0.08 + 0.35 * strength))
		draw_rect(receptor, lane_color(lane), false, 2.0)

	for lane in lane_count + 1:
		var x := left + lane * LANE_WIDTH
		draw_line(Vector2(x, 0.0), Vector2(x, bottom), Color(1, 1, 1, 0.12), 1.0)

	draw_line(
		Vector2(left, JUDGE_Y),
		Vector2(left + width(), JUDGE_Y),
		Color(1, 1, 1, 0.75),
		JUDGE_LINE_THICKNESS
	)

class_name Note
extends Node2D

## A note on its way down a lane. Drawn in code so there is no art to manage;
## swap [method _draw] for a Sprite2D once you have graphics.

const WIDTH := 94.0
const HEIGHT := 24.0

## Chart time, in seconds, when this note should be hit.
var time := 0.0
var lane := 0
var judged := false

var _color := Color.WHITE

func setup(p_time: float, p_lane: int, p_color: Color) -> void:
	time = p_time
	lane = p_lane
	_color = p_color

func _draw() -> void:
	var rect := Rect2(-WIDTH * 0.5, -HEIGHT * 0.5, WIDTH, HEIGHT)
	draw_rect(rect, _color)
	draw_rect(rect.grow(1.0), _color.lightened(0.45), false, 2.0)

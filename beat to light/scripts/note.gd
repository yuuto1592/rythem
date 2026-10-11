class_name Note
extends Node2D

## A note on its way down a lane. Drawn in code so there is no art to manage;
## swap [method _draw] for a Sprite2D once you have graphics.
##
## A hold note is a head plus a body that reaches up to its tail. The game
## moves the head and tells the note where the tail is with [method place].

const WIDTH := 94.0
const HEIGHT := 24.0
## Narrower than the head, so the head still reads as the thing to hit.
const BODY_WIDTH := 60.0

## Chart time, in seconds, when this note should be hit.
var time := 0.0
## When a hold may be let go. Equal to [member time] for a tap.
var end_time := 0.0
var lane := 0
## The head (or the whole tap) has been judged.
var head_judged := false
## The head of a hold was hit and its key is still down.
var holding := false
## What the head of a hold earned. It is only scored if the hold is kept to the end.
var head_rank := Judge.Rank.MISS
## Every judgement this note produces is in; it can be removed.
var done := false

var _color := Color.WHITE
## Tail position relative to the head, in pixels. Negative is up the screen.
var _tail_offset := 0.0

func setup(p_time: float, p_end_time: float, p_lane: int, p_color: Color) -> void:
	time = p_time
	end_time = maxf(p_end_time, p_time)
	lane = p_lane
	_color = p_color

func is_hold() -> bool:
	return end_time > time

## Puts the head at ([param x], [param head_y]) and, for a hold, stretches the
## body up to [param tail_y].
func place(x: float, head_y: float, tail_y: float) -> void:
	position = Vector2(x, head_y)
	if is_hold():
		_tail_offset = minf(tail_y - head_y, 0.0)
		queue_redraw()

func _draw() -> void:
	if is_hold():
		var body := _color
		body.a = 0.85 if holding else 0.5
		draw_rect(Rect2(-BODY_WIDTH * 0.5, _tail_offset, BODY_WIDTH, -_tail_offset), body)
		var tail := Rect2(-WIDTH * 0.5, _tail_offset - HEIGHT * 0.25, WIDTH, HEIGHT * 0.5)
		draw_rect(tail, _color.lightened(0.2))

	var head := Rect2(-WIDTH * 0.5, -HEIGHT * 0.5, WIDTH, HEIGHT)
	draw_rect(head, _color.lightened(0.35) if holding else _color)
	draw_rect(head.grow(1.0), _color.lightened(0.45), false, 2.0)

class_name ChartNote
extends RefCounted

## One playable note in a [Chart].

enum Kind {
	TAP, ## A single press on the note's lane.
	HOLD, ## Press at [member time] and keep the key down until [member end_time].
}

## When the note should be hit, in seconds from the start of the chart.
var time := 0.0
## When a HOLD may be let go. Equal to [member time] for a TAP.
var end_time := 0.0
## Zero-based lane index.
var lane := 0
## Derived from the length: anything that lasts is a HOLD.
var kind := Kind.TAP

func _init(p_time := 0.0, p_lane := 0, p_end_time := 0.0) -> void:
	time = p_time
	lane = p_lane
	end_time = maxf(p_end_time, p_time)
	kind = Kind.HOLD if end_time > time else Kind.TAP

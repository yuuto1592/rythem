class_name ChartNote
extends RefCounted

## One playable note in a [Chart].

enum Kind {
	TAP, ## A single press on the note's lane.
}

## When the note should be hit, in seconds from the start of the chart.
var time := 0.0
## Zero-based lane index.
var lane := 0
## Reserved so hold/slide notes can be added without changing the loader.
var kind := Kind.TAP

func _init(p_time := 0.0, p_lane := 0, p_kind := Kind.TAP) -> void:
	time = p_time
	lane = p_lane
	kind = p_kind

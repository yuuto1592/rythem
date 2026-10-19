class_name EditNote
extends RefCounted

## A note in the chart editor. Positions are in beats, not seconds, so notes
## keep their place in the music when the BPM changes.

var beat := 0.0
var lane := 0
## 0 for a tap; how many beats a hold lasts otherwise.
var length := 0.0

func _init(p_beat := 0.0, p_lane := 0, p_length := 0.0) -> void:
	beat = p_beat
	lane = p_lane
	length = maxf(p_length, 0.0)

func is_hold() -> bool:
	return length > 0.0

func end_beat() -> float:
	return beat + length

## True if this note and one at [param other_beat]..[param other_end] in the
## same lane would collide: two notes on one beat, or a note inside a hold.
func overlaps(other_beat: float, other_end: float) -> bool:
	return other_beat <= end_beat() + ChartDoc.EPSILON and beat <= other_end + ChartDoc.EPSILON

func to_dict() -> Dictionary:
	var data := {"beat": ChartDoc.json_number(beat), "lane": lane}
	if is_hold():
		data["length"] = ChartDoc.json_number(length)
	return data

func duplicate_note() -> EditNote:
	return EditNote.new(beat, lane, length)

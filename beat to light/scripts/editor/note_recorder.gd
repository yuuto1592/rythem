class_name NoteRecorder
extends RefCounted

## Turns key presses during playback into notes. A press becomes a tap; a key
## held for at least HOLD_MIN_BEATS becomes a hold. Both ends snap to the grid,
## which also absorbs the player being a little early or late.

## Shorter presses are taps. Half a beat keeps quick double taps from turning
## into tiny holds.
const HOLD_MIN_BEATS := 0.5

## Grid steps per beat, as in ChartDoc.quantize.
var division := 4

var _down := {}  # lane -> beat the key went down

func press(lane: int, beat: float) -> void:
	_down[lane] = beat

## Returns the recorded note as {beat, lane, length}, or {} if [param lane]
## was not down.
func release(lane: int, beat: float) -> Dictionary:
	if not _down.has(lane):
		return {}
	var start: float = _down[lane]
	_down.erase(lane)
	var at := ChartDoc.quantize(start, division)
	var length := 0.0
	if beat - start >= HOLD_MIN_BEATS:
		# A hold is at least one grid step long, however it rounds.
		length = maxf(ChartDoc.quantize(beat, division) - at, 1.0 / division)
	return {"beat": at, "lane": lane, "length": ChartDoc.tidy(length)}

## Releases every key still down (playback stopped mid-hold), as release() does.
func release_all(beat: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for lane in _down.keys():
		out.append(release(lane, beat))
	return out

func is_down(lane: int) -> bool:
	return _down.has(lane)

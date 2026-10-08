extends PlayTest

## Plays the fixture by sending real key events, so the InputMap actions
## registered by KeyBinds and the game's _unhandled_input are exercised the
## way a player would exercise them.
##
## A press lands on the first frame at or after the note's time, so it can be
## up to one frame late. That is why this asserts "no misses, nothing worse
## than GREAT" rather than all PERFECT: it must not flake on a slow machine.

var _notes: Array[ChartNote] = []
var _next := 0

func run(host: Node) -> void:
	_notes = expected_notes()
	start_game(host, false)
	await play_to_end(host, _press_due_notes)
	if result.is_empty():
		return

	var note_count := _notes.size()
	check_eq(_next, note_count, "every note was pressed")
	check_eq(result["counts"][Judge.Rank.MISS], 0, "no misses")
	check_eq(result["counts"][Judge.Rank.GOOD], 0, "nothing worse than GREAT")
	check_eq(result["max_combo"], note_count, "max combo")
	check_eq(result["full_combo"], true, "full combo")
	check_eq(result["autoplay"], false, "not flagged as autoplay")

func _press_due_notes() -> void:
	while _next < _notes.size() and _notes[_next].time <= conductor.chart_time:
		_tap(_notes[_next].lane)
		_next += 1

func _tap(lane: int) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = KeyBinds.LANE_KEYS[lane]
		event.pressed = pressed
		Input.parse_input_event(event)

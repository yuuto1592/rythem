class_name PlayTest
extends TestCase

## Shared plumbing for tests that play game.tscn for real. The game runs on
## the wall clock, so these take as long as the fixture chart plus the outro.

const GAME_SCENE := preload("res://scenes/game.tscn")
## Shortened from the in-game default so the suite stays quick.
const LEAD_IN := 0.2
## Generous; a run that has not finished by now is stuck.
const TIMEOUT_MSEC := 15000

var game: Node
var conductor: Conductor
var result := {}
var beats_heard := 0
## Every judgement in the order it happened: {lane, rank, at}, where [code]at[/code]
## is the chart time it was made.
var judgements: Array[Dictionary] = []

var _finished := false
var _saved_chart_path := ""
var _saved_autoplay := false
## Key events waiting for their chart time: {time, lane, pressed}, by time.
var _key_schedule: Array[Dictionary] = []

## The chart this test plays. Override to use another fixture.
func fixture() -> String:
	return "res://tests/fixtures/smoke.json"

func expected_chart() -> Chart:
	return Chart.load_from_file(fixture())

## Adds the game to [param host] and returns once it is running.
func start_game(host: Node, autoplay: bool) -> void:
	_saved_chart_path = GameState.chart_path
	_saved_autoplay = GameState.autoplay
	GameState.chart_path = fixture()
	GameState.autoplay = autoplay

	game = GAME_SCENE.instantiate()
	conductor = game.get_node(^"Conductor")
	conductor.lead_in = LEAD_IN
	conductor.beat_hit.connect(_on_beat_hit)
	game.note_judged.connect(_on_note_judged)
	game.run_finished.connect(_on_run_finished)
	host.add_child(game)

## Queues a real key event for [param lane], sent on the first frame at or
## after chart time [param time]. Call before [method play_to_end].
func schedule_key(time: float, lane: int, pressed: bool) -> void:
	_key_schedule.append({"time": time, "lane": lane, "pressed": pressed})
	_key_schedule.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)

## Steps frames until the run ends, sending scheduled keys as they come due.
## Records a failure instead of hanging if the run never ends.
func play_to_end(host: Node) -> void:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	while not _finished and Time.get_ticks_msec() < deadline:
		_send_due_keys()
		await host.get_tree().process_frame
	check(_finished, "run finished within %ds" % (TIMEOUT_MSEC / 1000))
	check(_key_schedule.is_empty(), "every scheduled key was sent")

	game.queue_free()
	GameState.chart_path = _saved_chart_path
	GameState.autoplay = _saved_autoplay

func _send_due_keys() -> void:
	while not _key_schedule.is_empty() and _key_schedule[0].time <= conductor.chart_time:
		var key: Dictionary = _key_schedule.pop_front()
		var event := InputEventKey.new()
		event.physical_keycode = KeyBinds.LANE_KEYS[key.lane]
		event.pressed = key.pressed
		Input.parse_input_event(event)

func _on_beat_hit(_index: int) -> void:
	beats_heard += 1

func _on_note_judged(lane: int, rank: Judge.Rank) -> void:
	judgements.append({"lane": lane, "rank": rank, "at": conductor.chart_time})

func _on_run_finished(p_result: Dictionary) -> void:
	_finished = true
	result = p_result

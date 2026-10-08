class_name PlayTest
extends TestCase

## Shared plumbing for tests that play game.tscn for real. The game runs on
## the wall clock, so these take as long as the fixture chart plus the outro.

const GAME_SCENE := preload("res://scenes/game.tscn")
const FIXTURE := "res://tests/fixtures/smoke.json"
## Shortened from the in-game default so the suite stays quick.
const LEAD_IN := 0.2
## Generous; a run that has not finished by now is stuck.
const TIMEOUT_MSEC := 15000

var game: Node
var conductor: Conductor
var result := {}
var beats_heard := 0

var _finished := false
var _saved_chart_path := ""
var _saved_autoplay := false

## Adds the game to [param host] and returns once it is running.
func start_game(host: Node, autoplay: bool) -> void:
	_saved_chart_path = GameState.chart_path
	_saved_autoplay = GameState.autoplay
	GameState.chart_path = FIXTURE
	GameState.autoplay = autoplay

	game = GAME_SCENE.instantiate()
	conductor = game.get_node(^"Conductor")
	conductor.lead_in = LEAD_IN
	conductor.beat_hit.connect(_on_beat_hit)
	game.run_finished.connect(_on_run_finished)
	host.add_child(game)

## Steps frames until the run ends, calling [param each_frame] (if given) once
## per frame. Records a failure instead of hanging if the run never ends.
func play_to_end(host: Node, each_frame := Callable()) -> void:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	while not _finished and Time.get_ticks_msec() < deadline:
		if each_frame.is_valid():
			each_frame.call()
		await host.get_tree().process_frame
	check(_finished, "run finished within %ds" % (TIMEOUT_MSEC / 1000))

	game.queue_free()
	GameState.chart_path = _saved_chart_path
	GameState.autoplay = _saved_autoplay

func expected_notes() -> Array[ChartNote]:
	return Chart.load_from_file(FIXTURE).notes

func _on_beat_hit(_index: int) -> void:
	beats_heard += 1

func _on_run_finished(p_result: Dictionary) -> void:
	_finished = true
	result = p_result

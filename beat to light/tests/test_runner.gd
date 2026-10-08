extends Node

## Runs every test and exits with 0 when all pass, 1 otherwise, so a CI job
## can use the exit code directly. See "Testing" in the README.

## Pure logic. Each test_* method gets a fresh instance.
const UNIT_TESTS: Array[GDScript] = [
	preload("res://tests/test_judge.gd"),
	preload("res://tests/test_chart.gd"),
	preload("res://tests/test_playfield.gd"),
	preload("res://tests/test_conductor.gd"),
]

## Play the real game scene against a fixture chart, in real time. Slower;
## each takes a few seconds.
const PLAY_TESTS: Array[GDScript] = [
	preload("res://tests/test_autoplay_run.gd"),
	preload("res://tests/test_input_run.gd"),
]

## Longer than the longest sound effect in sfx.gd.
const QUIT_DELAY := 0.3

var _passed := 0
var _failed := 0

func _ready() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	var started := Time.get_ticks_msec()

	for script in UNIT_TESTS:
		for method in _test_methods(script):
			var case: TestCase = script.new()
			case.call(method)
			_report("%s.%s" % [_name_of(script), method], case.failures)

	for script in PLAY_TESTS:
		var case: TestCase = script.new()
		await case.run(self)
		_report(_name_of(script), case.failures)

	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	print("")
	print("%d passed, %d failed (%.1fs)" % [_passed, _failed, seconds])

	# Let the last hit sound finish. Quitting mid-sound leaves its playback in
	# the audio server and Godot prints a (harmless) leak warning at exit.
	await get_tree().create_timer(QUIT_DELAY).timeout
	get_tree().quit(1 if _failed > 0 else 0)

func _report(label: String, failures: PackedStringArray) -> void:
	if failures.is_empty():
		_passed += 1
		print("  PASS  %s" % label)
		return
	_failed += 1
	print("  FAIL  %s" % label)
	for failure in failures:
		print("        - %s" % failure)

func _test_methods(script: GDScript) -> PackedStringArray:
	var names: PackedStringArray = []
	for method in script.get_script_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_"):
			names.append(method_name)
	return names

func _name_of(script: GDScript) -> String:
	return script.resource_path.get_file().get_basename()

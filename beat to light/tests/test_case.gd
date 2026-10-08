class_name TestCase
extends RefCounted

## Base class for the tests in res://tests/. Kept deliberately small so the
## suite needs no plugin: subclass it, write methods whose names start with
## test_, and add the script to test_runner.gd.
##
## GDScript has no exceptions, so a failed check records a message and the
## test carries on. One test can report several failures.

var failures: PackedStringArray = []

## Override in tests that need the scene tree (they run after the unit tests
## and are awaited). Unit tests leave this alone and use test_* methods.
func run(_host: Node) -> void:
	pass

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s\n        expected: %s\n        actual:   %s" % [message, expected, actual])

func check_near(actual: float, expected: float, message: String, tolerance := 0.0001) -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s\n        expected: %f (±%f)\n        actual:   %f" % [message, expected, tolerance, actual])

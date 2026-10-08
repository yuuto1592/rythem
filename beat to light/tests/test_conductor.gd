extends TestCase

func test_seconds_per_beat() -> void:
	var conductor := Conductor.new()
	conductor.bpm = 120.0
	check_near(conductor.seconds_per_beat(), 0.5, "120 BPM")
	conductor.bpm = 90.0
	check_near(conductor.seconds_per_beat(), 60.0 / 90.0, "90 BPM")
	conductor.free()

func test_zero_bpm_does_not_divide_by_zero() -> void:
	var conductor := Conductor.new()
	conductor.bpm = 0.0
	check(is_finite(conductor.seconds_per_beat()), "finite")
	conductor.free()

func test_no_music_means_clock_mode() -> void:
	# Outside the tree there is no Music child, so the system clock is used.
	var conductor := Conductor.new()
	check(not conductor.has_music(), "no music without a stream")
	conductor.free()

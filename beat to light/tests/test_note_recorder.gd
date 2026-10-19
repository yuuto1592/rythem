extends TestCase

func test_short_press_is_a_snapped_tap() -> void:
	var rec := NoteRecorder.new()
	rec.division = 4
	rec.press(1, 3.93)
	var note := rec.release(1, 4.05)
	check_near(note.beat, 4.0, "snapped to the nearest sixteenth")
	check_eq(note.lane, 1, "lane")
	check_near(note.length, 0.0, "a tap")

func test_long_press_is_a_hold() -> void:
	var rec := NoteRecorder.new()
	rec.division = 4
	rec.press(2, 8.02)
	var note := rec.release(2, 9.97)
	check_near(note.beat, 8.0, "start snapped")
	check_near(note.length, 2.0, "end snapped")

func test_hold_is_at_least_one_step() -> void:
	var rec := NoteRecorder.new()
	rec.division = 2
	rec.press(0, 1.9)  # snaps to 2.0
	var note := rec.release(0, 2.45)  # held 0.55 beats, but the end also snaps to 2.5
	check_near(note.length, 0.5, "one grid step")

func test_release_without_press_records_nothing() -> void:
	var rec := NoteRecorder.new()
	check(rec.release(3, 1.0).is_empty(), "nothing")

func test_keys_are_tracked_per_lane() -> void:
	var rec := NoteRecorder.new()
	rec.press(0, 1.0)
	rec.press(3, 1.0)
	check(rec.is_down(0) and rec.is_down(3), "both down")
	var notes := rec.release_all(1.1)
	check_eq(notes.size(), 2, "both released when playback stops")
	check(not rec.is_down(0), "nothing left down")

extends TestCase

const BUNDLED_DIR := "res://songs"

func test_beats_become_seconds() -> void:
	var chart := Chart.from_dict({"bpm": 120, "notes": [{"beat": 4, "lane": 0}]})
	check_near(chart.notes[0].time, 2.0, "beat 4 at 120 BPM")

func test_time_overrides_beat() -> void:
	var chart := Chart.from_dict({"bpm": 120, "notes": [{"beat": 4, "time": 0.75, "lane": 0}]})
	check_near(chart.notes[0].time, 0.75, "explicit time wins")

func test_notes_are_sorted() -> void:
	var chart := Chart.from_dict({"notes": [
		{"beat": 8, "lane": 0},
		{"beat": 2, "lane": 1},
		{"beat": 5, "lane": 2},
	]})
	check_eq(chart.notes.map(func(n: ChartNote) -> int: return n.lane), [1, 2, 0], "lanes in time order")

func test_out_of_range_lanes_are_clamped() -> void:
	var chart := Chart.from_dict({"lane_count": 4, "notes": [
		{"beat": 1, "lane": 9},
		{"beat": 2, "lane": -3},
	]})
	check_eq(chart.notes[0].lane, 3, "lane above range")
	check_eq(chart.notes[1].lane, 0, "lane below range")

func test_junk_note_entries_are_skipped() -> void:
	var chart := Chart.from_dict({"notes": [{"beat": 1, "lane": 0}, "oops", 42, null]})
	check_eq(chart.notes.size(), 1, "only the real note survives")

func test_defaults_and_guards() -> void:
	var chart := Chart.from_dict({})
	check_eq(chart.title, "Untitled", "title")
	check_eq(chart.lane_count, 4, "lane_count")
	check_near(chart.bpm, Chart.DEFAULT_BPM, "bpm")
	check_eq(chart.notes.size(), 0, "no notes")
	check_near(chart.length(), 0.0, "length of an empty chart")

	var silly := Chart.from_dict({"bpm": 0, "lane_count": 0, "scroll_time": 0})
	check(silly.bpm >= 1.0, "bpm floored")
	check(silly.lane_count >= 1, "lane_count floored")
	check(silly.scroll_time >= 0.1, "scroll_time floored")

func test_length_is_last_note_time() -> void:
	var chart := Chart.from_dict({"bpm": 60, "notes": [{"beat": 1, "lane": 0}, {"beat": 7, "lane": 0}]})
	check_near(chart.length(), 7.0, "length")

func test_bundled_charts_are_valid() -> void:
	# Every chart that ships in songs/ must load and make sense.
	var paths := GameState.list_charts()
	check(not paths.is_empty(), "songs/ contains charts")
	for path in paths:
		var chart := Chart.load_from_file(path)
		if chart == null:
			check(false, "%s failed to load" % path)
			continue
		check(not chart.notes.is_empty(), "%s has notes" % path)
		var previous := -INF
		for note in chart.notes:
			check(note.lane >= 0 and note.lane < chart.lane_count, "%s: lane %d in range" % [path, note.lane])
			check(note.time >= previous, "%s: sorted at %.3fs" % [path, note.time])
			previous = note.time
		# A first note earlier than one scroll length would appear already
		# part-way down the screen.
		check(chart.notes[0].time >= chart.scroll_time,
				"%s: first note leaves room to scroll in" % path)

class_name Chart
extends RefCounted

## A song's note data, loaded from a JSON file in res://songs/.
##
## Times in the file are written in beats so that charts stay readable and
## stay correct if you change the BPM. [method load_from_file] converts them
## to seconds once, up front.

const DEFAULT_BPM := 120.0
const DEFAULT_SCROLL_TIME := 1.0

var title := "Untitled"
var artist := ""
var bpm := DEFAULT_BPM
## Seconds to add to every note. Use it to line a chart up with its audio.
var offset := 0.0
var lane_count := 4
## How long a note is visible before it reaches the judge line. Lower is faster.
var scroll_time := DEFAULT_SCROLL_TIME
## Path to an audio file, or "" to play without music (a metronome is used instead).
var music_path := ""
## Sorted by [member ChartNote.time], ascending.
var notes: Array[ChartNote] = []

## Seconds from chart start to the last note.
func length() -> float:
	return notes[-1].time if not notes.is_empty() else 0.0

func seconds_per_beat() -> float:
	return 60.0 / maxf(bpm, 1.0)

## Returns the parsed chart, or null if the file is missing or malformed.
static func load_from_file(path: String) -> Chart:
	if not FileAccess.file_exists(path):
		push_error("Chart not found: %s" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Chart is not a JSON object: %s" % path)
		return null
	return from_dict(parsed as Dictionary)

static func from_dict(data: Dictionary) -> Chart:
	var chart := Chart.new()
	chart.title = str(data.get("title", chart.title))
	chart.artist = str(data.get("artist", chart.artist))
	chart.bpm = maxf(float(data.get("bpm", chart.bpm)), 1.0)
	chart.offset = float(data.get("offset", chart.offset))
	chart.lane_count = maxi(int(data.get("lane_count", chart.lane_count)), 1)
	chart.scroll_time = maxf(float(data.get("scroll_time", chart.scroll_time)), 0.1)
	chart.music_path = str(data.get("music", chart.music_path))

	var spb := chart.seconds_per_beat()
	for entry: Variant in data.get("notes", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var note: Dictionary = entry
		var lane := clampi(int(note.get("lane", 0)), 0, chart.lane_count - 1)
		# "time" (seconds) wins over "beat" so one-off notes can be placed by hand.
		var time := float(note["time"]) if note.has("time") else float(note.get("beat", 0.0)) * spb
		chart.notes.append(ChartNote.new(time, lane))

	chart.notes.sort_custom(func(a: ChartNote, b: ChartNote) -> bool: return a.time < b.time)
	return chart

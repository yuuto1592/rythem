class_name ChartDoc
extends RefCounted

## The chart editor's document: a chart that can be changed, undone and saved.
##
## Chart is built for playing and keeps everything in seconds. Here positions
## stay in beats, so changing the BPM moves every note with the tempo. Notes in
## one lane never collide: no two notes on the same beat, and nothing inside a
## hold (the key is still down, so it could not be hit).

## Beats closer than this are the same beat. Snapped positions are exact
## fractions, so this only absorbs floating-point noise.
const EPSILON := 0.0001
## How many undo steps are kept.
const UNDO_LIMIT := 200

signal changed

var title := "New chart"
var artist := ""
var bpm := 120.0
var offset := 0.0
var lane_count := 4
var scroll_time := 1.1
## The chart's music: a file name next to the chart, or a res:// path.
var music := ""
## Sorted by beat, then lane.
var notes: Array[EditNote] = []
## True when there are changes that have not been saved.
var modified := false

var _undo: Array[Array] = []
var _redo: Array[Array] = []

static func from_chart(chart: Chart) -> ChartDoc:
	var doc := ChartDoc.new()
	doc.title = chart.title
	doc.artist = chart.artist
	doc.bpm = chart.bpm
	doc.offset = chart.offset
	doc.lane_count = chart.lane_count
	doc.scroll_time = chart.scroll_time
	doc.music = chart.music_path
	var spb := chart.seconds_per_beat()
	for note in chart.notes:
		doc.notes.append(EditNote.new(tidy(note.time / spb), note.lane, tidy((note.end_time - note.time) / spb)))
	doc._sort()
	return doc

static func load_file(path: String) -> ChartDoc:
	var chart := Chart.load_from_file(path)
	return from_chart(chart) if chart != null else null

## Rounds [param beat] to the nearest step of a grid with [param division]
## steps per beat (4 = sixteenth notes in 4/4, 3 = triplets).
static func quantize(beat: float, division: int) -> float:
	var steps := maxi(division, 1)
	return tidy(roundf(beat * steps) / steps)

## Trims floating-point noise so saved charts read cleanly ("2.5", not "2.4999999").
static func tidy(value: float) -> float:
	return roundf(value * 1_000_000.0) / 1_000_000.0

## A number as it should appear in a saved chart: whole numbers as integers
## ("4", like the bundled charts), everything else tidied.
static func json_number(value: float) -> Variant:
	var v := tidy(value)
	return int(v) if is_equal_approx(v, roundf(v)) else v

func seconds_per_beat() -> float:
	return 60.0 / maxf(bpm, 1.0)

## The beat at which the last note ends; 0 for an empty chart.
func last_beat() -> float:
	var last := 0.0
	for note in notes:
		last = maxf(last, note.end_beat())
	return last

## Whether a note could go at [param beat] in [param lane] without colliding.
## Notes in [param ignore] are left out of the check (the notes being moved).
func can_place(beat: float, lane: int, length := 0.0, ignore: Array[EditNote] = []) -> bool:
	if lane < 0 or lane >= lane_count or beat < -EPSILON:
		return false
	for note in notes:
		if note.lane == lane and note.overlaps(beat, beat + maxf(length, 0.0)) and not ignore.has(note):
			return false
	return true

## Whether every note in [param moving] can go where [param targets] says
## ({beat, lane, length} each, in the same order) at once: inside the chart,
## clear of the notes that stay put, and clear of each other.
func can_relocate(moving: Array[EditNote], targets: Array[Dictionary]) -> bool:
	for i in targets.size():
		var t := targets[i]
		if not can_place(t.beat, t.lane, t.length, moving):
			return false
		for j in i:
			var other := targets[j]
			if other.lane == t.lane and t.beat <= other.beat + other.length + EPSILON \
					and other.beat <= t.beat + t.length + EPSILON:
				return false
	return true

## Where [param moving] would land shifted by [param beats] and [param lanes].
static func shifted(moving: Array[EditNote], beats: float, lanes: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for note in moving:
		out.append({"beat": tidy(note.beat + beats), "lane": note.lane + lanes, "length": note.length})
	return out

## Moves [param moving] as one block. All or nothing, one undo step. The notes
## stay the same objects, so a selection holding them stays valid.
func move_notes(moving: Array[EditNote], beats: float, lanes: int) -> bool:
	return _relocate(moving, shifted(moving, beats, lanes))

## Flips [param moving] left to right (lane 0 <-> the last lane).
func mirror_notes(moving: Array[EditNote]) -> bool:
	var targets: Array[Dictionary] = []
	for note in moving:
		targets.append({"beat": note.beat, "lane": lane_count - 1 - note.lane, "length": note.length})
	return _relocate(moving, targets)

## Makes [param note] a hold of [param length] beats, or a tap with 0.
func set_length(note: EditNote, length: float) -> bool:
	var one: Array[EditNote] = [note]
	var target: Array[Dictionary] = [{"beat": note.beat, "lane": note.lane, "length": tidy(maxf(length, 0.0))}]
	return _relocate(one, target)

## Adds a note if it fits. With [param undoable] false the caller has already
## taken a checkpoint (a recording take is undone as one step).
func add_note(beat: float, lane: int, length := 0.0, undoable := true) -> bool:
	beat = tidy(beat)
	length = tidy(maxf(length, 0.0))
	if not can_place(beat, lane, length):
		return false
	if undoable:
		checkpoint()
	notes.append(EditNote.new(beat, lane, length))
	_sort()
	_touch()
	return true

## The note in [param lane] at [param beat], counting the whole body of a hold.
## [param tolerance] (in beats) makes small notes easier to hit with the mouse.
func note_at(beat: float, lane: int, tolerance := 0.0) -> EditNote:
	for note in notes:
		if note.lane == lane and beat >= note.beat - tolerance and beat <= note.end_beat() + tolerance:
			return note
	return null

func remove_note(note: EditNote, undoable := true) -> bool:
	if not notes.has(note):
		return false
	if undoable:
		checkpoint()
	notes.erase(note)
	_touch()
	return true

## Removes every note in [param doomed] as one undo step. Returns how many went.
func remove_notes(doomed: Array[EditNote]) -> int:
	var present := doomed.filter(func(n: EditNote) -> bool: return notes.has(n))
	if present.is_empty():
		return 0
	checkpoint()
	for note in present:
		notes.erase(note)
	_touch()
	return present.size()

## Adds notes given as {beat, lane, length} (a paste) as one undo step. Notes
## that would collide are skipped. Returns the notes that were added.
func add_notes(items: Array[Dictionary]) -> Array[EditNote]:
	var added: Array[EditNote] = []
	var took_checkpoint := false
	for item in items:
		var beat := tidy(float(item.beat))
		var length := tidy(maxf(float(item.get("length", 0.0)), 0.0))
		if not can_place(beat, int(item.lane), length):
			continue
		if not took_checkpoint:
			checkpoint()
			took_checkpoint = true
		var note := EditNote.new(beat, int(item.lane), length)
		notes.append(note)
		added.append(note)
	if not added.is_empty():
		_sort()
		_touch()
	return added

## Notes with any part between [param from_beat] and [param to_beat] in lanes
## [param from_lane] to [param to_lane] (inclusive): what a selection box covers.
func notes_in(from_beat: float, to_beat: float, from_lane: int, to_lane: int) -> Array[EditNote]:
	var out: Array[EditNote] = []
	for note in notes:
		if note.lane >= from_lane and note.lane <= to_lane \
				and note.beat <= to_beat + EPSILON and note.end_beat() >= from_beat - EPSILON:
			out.append(note)
	return out

## Saves the current notes so the next change can be undone.
func checkpoint() -> void:
	_undo.append(_snapshot())
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()
	_redo.clear()

func can_undo() -> bool:
	return not _undo.is_empty()

func can_redo() -> bool:
	return not _redo.is_empty()

func undo() -> bool:
	if _undo.is_empty():
		return false
	_redo.append(_snapshot())
	_restore(_undo.pop_back())
	return true

func redo() -> bool:
	if _redo.is_empty():
		return false
	_undo.append(_snapshot())
	_restore(_redo.pop_back())
	return true

## Marks the document as changed, for edits outside the notes (title, BPM...).
func mark_modified() -> void:
	_touch()

func to_dict() -> Dictionary:
	return {
		"title": title,
		"artist": artist,
		"bpm": json_number(bpm),
		"offset": json_number(offset),
		"lane_count": lane_count,
		"scroll_time": json_number(scroll_time),
		"music": music,
		"notes": notes.map(func(n: EditNote) -> Dictionary: return n.to_dict()),
	}

## The chart as JSON in the same layout as the bundled charts: one note per
## line, so diffs of hand-edited and editor-made charts stay readable.
## [param music_path], when given, replaces the music field (a copy written
## somewhere else has to point at the music by its full path).
func to_json_text(music_path := "") -> String:
	var data := to_dict()
	if not music_path.is_empty():
		data["music"] = music_path
	var lines: PackedStringArray = ["{"]
	for key in ["title", "artist", "bpm", "offset", "lane_count", "scroll_time", "music"]:
		lines.append("  %s: %s," % [JSON.stringify(key), JSON.stringify(data[key])])
	lines.append("  \"notes\": [")
	var rows: PackedStringArray = []
	for note: Dictionary in data["notes"]:
		rows.append("    " + JSON.stringify(note, "", false))
	if not rows.is_empty():
		lines.append(",\n".join(rows))
	lines.append("  ]")
	lines.append("}")
	return "\n".join(lines) + "\n"

func _relocate(moving: Array[EditNote], targets: Array[Dictionary]) -> bool:
	if moving.is_empty() or not can_relocate(moving, targets):
		return false
	var unchanged := true
	for i in moving.size():
		var n := moving[i]
		var t := targets[i]
		if not (is_equal_approx(n.beat, t.beat) and n.lane == t.lane and is_equal_approx(n.length, t.length)):
			unchanged = false
	if unchanged:
		return true
	checkpoint()
	for i in moving.size():
		moving[i].beat = tidy(targets[i].beat)
		moving[i].lane = targets[i].lane
		moving[i].length = tidy(targets[i].length)
	_sort()
	_touch()
	return true

func _snapshot() -> Array[EditNote]:
	var copy: Array[EditNote] = []
	for note in notes:
		copy.append(note.duplicate_note())
	return copy

func _restore(snapshot: Array[EditNote]) -> void:
	notes = snapshot
	_touch()

func _sort() -> void:
	notes.sort_custom(func(a: EditNote, b: EditNote) -> bool:
		return a.beat < b.beat - EPSILON or (absf(a.beat - b.beat) <= EPSILON and a.lane < b.lane))

func _touch() -> void:
	modified = true
	changed.emit()

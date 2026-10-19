extends TestCase

func _doc() -> ChartDoc:
	var doc := ChartDoc.new()
	doc.bpm = 120.0
	return doc

func test_add_tap_and_hold() -> void:
	var doc := _doc()
	check(doc.add_note(2.0, 1), "tap added")
	check(doc.add_note(4.0, 2, 2.0), "hold added")
	check_eq(doc.notes.size(), 2, "two notes")
	check(doc.notes[1].is_hold(), "second is a hold")
	check(doc.modified, "marked modified")

func test_notes_stay_sorted() -> void:
	var doc := _doc()
	doc.add_note(8.0, 0)
	doc.add_note(2.0, 3)
	doc.add_note(2.0, 1)
	check_eq(doc.notes.map(func(n: EditNote) -> String: return "%d@%d" % [int(n.beat), n.lane]),
			["2@1", "2@3", "8@0"], "by beat, then lane")

func test_collisions_in_one_lane_are_refused() -> void:
	var doc := _doc()
	doc.add_note(4.0, 0, 2.0)  # hold 4..6
	check(not doc.add_note(4.0, 0), "tap on the hold's head")
	check(not doc.add_note(5.0, 0), "tap inside the hold")
	check(not doc.add_note(6.0, 0), "tap on the hold's end")
	check(not doc.add_note(3.0, 0, 1.5), "hold running into the hold")
	check(doc.add_note(6.25, 0), "tap just after the hold")
	check(doc.add_note(5.0, 1), "same beat, other lane")
	check(not doc.add_note(1.0, 4), "lane out of range")
	check(not doc.add_note(-1.0, 0), "negative beat")
	check_eq(doc.notes.size(), 3, "only the valid notes")

func test_note_at_covers_a_hold_body() -> void:
	var doc := _doc()
	doc.add_note(4.0, 2, 2.0)
	check(doc.note_at(5.5, 2) != null, "inside the body")
	check(doc.note_at(5.5, 1) == null, "other lane")
	check(doc.note_at(3.9, 2) == null, "before the head")
	check(doc.note_at(3.9, 2, 0.2) != null, "within the tolerance")

func test_undo_and_redo() -> void:
	var doc := _doc()
	doc.add_note(1.0, 0)
	doc.add_note(2.0, 0)
	doc.remove_note(doc.notes[0])
	check_eq(doc.notes.size(), 1, "after remove")
	check(doc.undo(), "undo remove")
	check_eq(doc.notes.size(), 2, "remove undone")
	check(doc.undo(), "undo second add")
	check_eq(doc.notes.size(), 1, "second add undone")
	check(doc.redo(), "redo")
	check_eq(doc.notes.size(), 2, "redone")
	doc.add_note(3.0, 0)
	check(not doc.can_redo(), "a new edit clears redo")

func test_one_checkpoint_undoes_a_whole_take() -> void:
	var doc := _doc()
	doc.checkpoint()
	for beat in [1.0, 2.0, 3.0]:
		doc.add_note(beat, 0, 0.0, false)
	doc.undo()
	check_eq(doc.notes.size(), 0, "the whole take is gone in one undo")

func test_quantize() -> void:
	check_near(ChartDoc.quantize(2.13, 4), 2.25, "nearest sixteenth (up)")
	check_near(ChartDoc.quantize(2.10, 4), 2.0, "nearest sixteenth (down)")
	check_near(ChartDoc.quantize(1.30, 3), 1.333333, "triplets", 0.000001)
	check_near(ChartDoc.quantize(5.6, 1), 6.0, "whole beats")

func test_save_and_reload_round_trip() -> void:
	var doc := _doc()
	doc.title = "Round Trip"
	doc.bpm = 150.0
	doc.offset = 0.125
	doc.music = "song.ogg"
	doc.add_note(4.0, 0)
	doc.add_note(4.5, 2, 1.5)
	doc.add_note(1.0 / 3.0, 3)
	var parsed: Variant = JSON.parse_string(doc.to_json_text())
	check_eq(typeof(parsed), TYPE_DICTIONARY, "saved text is a JSON object")
	var back := ChartDoc.from_chart(Chart.from_dict(parsed))
	check_eq(back.title, "Round Trip", "title")
	check_near(back.bpm, 150.0, "bpm")
	check_near(back.offset, 0.125, "offset")
	check_eq(back.music, "song.ogg", "music")
	check_eq(back.notes.size(), 3, "notes")
	for i in back.notes.size():
		check_near(back.notes[i].beat, doc.notes[i].beat, "note %d beat" % i, 0.00001)
		check_near(back.notes[i].length, doc.notes[i].length, "note %d length" % i, 0.00001)
		check_eq(back.notes[i].lane, doc.notes[i].lane, "note %d lane" % i)

func test_saved_text_matches_the_bundled_layout() -> void:
	var doc := _doc()
	doc.add_note(4.0, 0)
	doc.add_note(6.0, 1, 2.0)
	var text := doc.to_json_text()
	check(text.contains("    {\"beat\":4,\"lane\":0}"), "one tap per line, whole beats as integers")
	check(text.contains("{\"beat\":6,\"lane\":1,\"length\":2}"), "hold with its length")

func test_bundled_charts_survive_a_round_trip() -> void:
	# Opening a chart in the editor and saving it must not move a single note.
	for path in ChartStore.list_charts_in(ChartStore.BUNDLED_DIR):
		var original := Chart.load_from_file(path)
		var resaved := Chart.from_dict(JSON.parse_string(ChartDoc.from_chart(original).to_json_text()))
		check_eq(resaved.notes.size(), original.notes.size(), "%s: note count" % path)
		for i in mini(resaved.notes.size(), original.notes.size()):
			check_near(resaved.notes[i].time, original.notes[i].time, "%s: note %d time" % [path, i], 0.00001)
			check_near(resaved.notes[i].end_time, original.notes[i].end_time, "%s: note %d end" % [path, i], 0.00001)

func test_bpm_change_keeps_notes_on_their_beats() -> void:
	var doc := _doc()
	doc.add_note(4.0, 0, 2.0)
	doc.bpm = 60.0
	var chart := Chart.from_dict(JSON.parse_string(doc.to_json_text()))
	check_near(chart.notes[0].time, 4.0, "beat 4 is 4s at 60 BPM")
	check_near(chart.notes[0].end_time, 6.0, "and the hold ends at 6s")

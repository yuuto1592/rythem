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

func _layout(doc: ChartDoc) -> Array:
	return doc.notes.map(func(n: EditNote) -> String:
		return "%s@%d%s" % [str(ChartDoc.json_number(n.beat)), n.lane,
				"+%s" % str(ChartDoc.json_number(n.length)) if n.is_hold() else ""])

func test_move_notes_as_a_block() -> void:
	var doc := _doc()
	doc.add_note(1.0, 0)
	doc.add_note(2.0, 1, 1.0)
	doc.add_note(4.0, 3)
	var block: Array[EditNote] = [doc.notes[0], doc.notes[1]]
	check(doc.move_notes(block, 1.0, 1), "moved")
	check_eq(_layout(doc), ["2@1", "3@2+1", "4@3"], "both notes moved one beat later and one lane right")
	check(block[0].lane == 1 and block[1].lane == 2, "the same note objects moved (a selection stays valid)")
	check(not doc.move_notes(block, 1.0, 1), "a block that would land on a note is refused")
	check(not doc.move_notes(block, 0.0, 2), "a block that would leave the lanes is refused")
	check(not doc.move_notes(block, -3.0, 0), "a block that would go before the start is refused")
	check_eq(_layout(doc), ["2@1", "3@2+1", "4@3"], "refused moves change nothing")
	check(doc.undo(), "one undo")
	check_eq(_layout(doc), ["1@0", "2@1+1", "4@3"], "undoes the whole move")

func test_notes_can_move_through_their_own_old_places() -> void:
	var doc := _doc()
	doc.add_note(1.0, 0)
	doc.add_note(1.25, 0)
	var both: Array[EditNote] = [doc.notes[0], doc.notes[1]]
	check(doc.move_notes(both, 0.25, 0), "a run of notes shifts along itself")
	check_eq(_layout(doc), ["1.25@0", "1.5@0"], "both shifted")

func test_mirror_and_resize() -> void:
	var doc := _doc()
	doc.add_note(1.0, 0)
	doc.add_note(2.0, 1, 1.0)
	doc.add_note(2.0, 3)
	var pair: Array[EditNote] = [doc.notes[0], doc.notes[1]]
	check(doc.mirror_notes(pair), "mirrored")
	check_eq(_layout(doc), ["1@3", "2@2+1", "2@3"], "lane 0 <-> 3, 1 <-> 2")
	var hold := doc.notes[1]
	check(doc.set_length(hold, 2.5), "longer hold")
	check_near(hold.length, 2.5, "new length")
	check(doc.set_length(hold, 0.0), "a hold can become a tap")
	check(not hold.is_hold(), "now a tap")
	var tap := doc.notes[0]
	check(not doc.set_length(tap, 1.0), "a hold that would run into the next note is refused")
	var blocked: Array[EditNote] = [doc.notes[2]]
	doc.add_note(2.0, 0)
	check(not doc.mirror_notes(blocked), "mirroring onto a note is refused")

func test_delete_and_paste_are_one_step_each() -> void:
	var doc := _doc()
	doc.add_note(1.0, 0)
	doc.add_note(2.0, 1)
	doc.add_note(3.0, 2)
	var two: Array[EditNote] = [doc.notes[0], doc.notes[2]]
	check_eq(doc.remove_notes(two), 2, "two deleted")
	check_eq(_layout(doc), ["2@1"], "the other stays")
	doc.undo()
	check_eq(doc.notes.size(), 3, "one undo brings both back")

	var items: Array[Dictionary] = [
		{"beat": 5.0, "lane": 0, "length": 0.0},
		{"beat": 6.0, "lane": 1, "length": 1.0},
		{"beat": 2.0, "lane": 1, "length": 0.0},  # lands on 2@1
	]
	var added := doc.add_notes(items)
	check_eq(added.size(), 2, "the note in the way is left out")
	check_eq(_layout(doc), ["1@0", "2@1", "3@2", "5@0", "6@1+1"], "pasted")
	doc.undo()
	check_eq(doc.notes.size(), 3, "one undo removes the whole paste")

func test_notes_in_a_box() -> void:
	var doc := _doc()
	doc.add_note(1.0, 0)
	doc.add_note(2.0, 1, 2.0)  # 2..4
	doc.add_note(3.0, 2)
	doc.add_note(6.0, 1)
	var found := doc.notes_in(3.5, 6.5, 1, 1)
	check_eq(found.size(), 2, "a hold reaching into the box counts, and so does a note inside it")
	check_eq(doc.notes_in(0.0, 10.0, 3, 3).size(), 0, "an empty lane")

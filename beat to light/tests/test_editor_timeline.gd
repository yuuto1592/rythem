extends TestCase

## The timeline's screen geometry: which beat and lane a point is, and back.

func _timeline() -> EditorTimeline:
	var timeline := EditorTimeline.new()
	timeline.doc = ChartDoc.new()
	timeline.size = Vector2(800.0, 600.0)
	timeline.view_beat = 4.0
	timeline.px_per_beat = 100.0
	return timeline

func test_beats_and_heights_convert_both_ways() -> void:
	var t := _timeline()
	check_near(t.beat_to_y(4.0), t.cursor_y(), "the view beat sits on the cursor line")
	check_near(t.beat_to_y(5.0), t.cursor_y() - 100.0, "later beats are higher up")
	for beat in [0.0, 3.25, 4.0, 7.5]:
		check_near(t.y_to_beat(t.beat_to_y(beat)), beat, "round trip at beat %s" % beat)
	t.free()

func test_ruler_waveform_and_lanes_sit_side_by_side() -> void:
	var t := _timeline()
	var width := EditorTimeline.RULER_WIDTH + EditorTimeline.WAVE_WIDTH + EditorTimeline.WAVE_GAP \
			+ 4 * EditorTimeline.LANE_WIDTH
	check_near(t.content_left(), (800.0 - width) * 0.5, "the whole drawing is centred")
	check_near(t.wave_left(), t.content_left() + EditorTimeline.RULER_WIDTH, "waveform after the ruler")
	check(t.lanes_left() > t.wave_left() + EditorTimeline.WAVE_WIDTH, "lanes after the waveform")
	for lane in 4:
		check_eq(t.x_to_lane(t.lane_center_x(lane)), lane, "lane %d's centre is lane %d" % [lane, lane])
	check_eq(t.x_to_lane(t.lanes_left() - 1.0), -1, "left of the lanes is no lane")
	check_eq(t.x_to_lane(t.lanes_left() + 4 * EditorTimeline.LANE_WIDTH + 1.0), -1, "right of the lanes is no lane")
	check(t.in_seek_area(t.wave_left() + 10.0), "the waveform moves the cursor")
	check(t.in_seek_area(t.content_left() + 5.0), "so does the ruler")
	check(not t.in_seek_area(t.lane_center_x(0)), "the lanes do not")
	t.free()

func test_hit_test_finds_heads_bodies_and_ends() -> void:
	var t := _timeline()
	t.doc.add_note(5.0, 1)
	t.doc.add_note(6.0, 2, 2.0)  # 6..8
	var tap := t.hit_test(Vector2(t.lane_center_x(1), t.beat_to_y(5.0) + 3.0))
	check(not tap.is_empty() and tap.note.beat == 5.0 and not tap.end, "a tap's head")
	var body := t.hit_test(Vector2(t.lane_center_x(2), t.beat_to_y(7.0)))
	check(not body.is_empty() and body.note.beat == 6.0 and not body.end, "a hold's body")
	var end := t.hit_test(Vector2(t.lane_center_x(2), t.beat_to_y(8.0) - 2.0))
	check(not end.is_empty() and end.end, "a hold's end")
	check(t.hit_test(Vector2(t.lane_center_x(1), t.beat_to_y(5.5))).is_empty(), "empty space")
	check(t.hit_test(Vector2(t.lane_center_x(3), t.beat_to_y(5.0))).is_empty(), "another lane")
	t.free()

func test_snapping_follows_the_grid() -> void:
	var t := _timeline()
	t.division = 4
	check_near(t.snapped_beat_at(t.beat_to_y(5.1)), 5.0, "snaps down to the nearest 1/4")
	check_near(t.snapped_beat_at(t.beat_to_y(5.2)), 5.25, "snaps up to the nearest 1/4")
	t.division = 3
	check_near(t.snapped_beat_at(t.beat_to_y(5.3)), 5.333333, "triplets", 0.00001)
	check_near(t.snapped_beat_at(t.beat_to_y(-2.0)), 0.0, "never before the start")
	check_near(t.step_beats(), 1.0 / 3.0, "one step is one grid division")
	t.free()

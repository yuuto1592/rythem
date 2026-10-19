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

func test_lanes_are_centred() -> void:
	var t := _timeline()
	var width := 4 * EditorTimeline.LANE_WIDTH
	check_near(t.lanes_left(), (800.0 - width) * 0.5, "lanes are centred")
	for lane in 4:
		check_eq(t.x_to_lane(t.lane_center_x(lane)), lane, "lane %d's centre is lane %d" % [lane, lane])
	check_eq(t.x_to_lane(t.lanes_left() - 1.0), -1, "left of the lanes is no lane")
	check_eq(t.x_to_lane(t.lanes_left() + width + 1.0), -1, "right of the lanes is no lane")
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

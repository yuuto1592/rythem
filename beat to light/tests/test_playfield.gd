extends TestCase

var _field: Playfield

func _init() -> void:
	_field = Playfield.new()
	_field.configure(4, 1.0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_field):
		_field.free()

func test_lanes_are_symmetric_around_the_origin() -> void:
	check_near(_field.lane_x(0), -_field.lane_x(3), "outer lanes")
	check_near(_field.lane_x(1), -_field.lane_x(2), "inner lanes")

func test_lanes_are_one_lane_width_apart() -> void:
	for lane in 3:
		check_near(_field.lane_x(lane + 1) - _field.lane_x(lane), Playfield.LANE_WIDTH, "lane %d -> %d" % [lane, lane + 1])

func test_due_note_sits_on_the_judge_line() -> void:
	check_near(_field.y_for(0.0), Playfield.JUDGE_Y, "0s away")

func test_note_one_scroll_away_is_at_the_top() -> void:
	check_near(_field.y_for(_field.scroll_time), 0.0, "scroll_time away")

func test_notes_move_down_as_time_passes() -> void:
	check(_field.y_for(0.8) < _field.y_for(0.4), "further away is higher up")
	check(_field.y_for(-0.1) > Playfield.JUDGE_Y, "a late note is below the line")

func test_scroll_time_scales_speed() -> void:
	var slow := Playfield.new()
	slow.configure(4, 2.0)
	check_near(slow.y_for(1.0), Playfield.JUDGE_Y * 0.5, "half way at half the scroll time")
	slow.free()

func test_lane_colors_wrap() -> void:
	var count := Playfield.LANE_COLORS.size()
	check_eq(_field.lane_color(count), _field.lane_color(0), "wraps around")

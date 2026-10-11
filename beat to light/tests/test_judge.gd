extends TestCase

const ORDER := [
	Judge.Rank.CRITICAL,
	Judge.Rank.PERFECT,
	Judge.Rank.GREAT,
	Judge.Rank.GOOD,
	Judge.Rank.MISS,
]

func test_exact_hit_is_critical() -> void:
	check_eq(Judge.rank_for(0.0), Judge.Rank.CRITICAL, "zero error")

func test_critical_is_25ms_either_way() -> void:
	check_eq(Judge.rank_for(0.025), Judge.Rank.CRITICAL, "25ms late")
	check_eq(Judge.rank_for(-0.025), Judge.Rank.CRITICAL, "25ms early")
	check_eq(Judge.rank_for(0.026), Judge.Rank.PERFECT, "26ms late")
	check_eq(Judge.rank_for(-0.026), Judge.Rank.PERFECT, "26ms early")

func test_windows_and_weights_match_the_spec() -> void:
	# The agreed table. Changing the feel should be a deliberate edit here too.
	var spec := [
		[Judge.Rank.CRITICAL, 0.025, 1.0],
		[Judge.Rank.PERFECT, 0.040, 0.95],
		[Judge.Rank.GREAT, 0.080, 0.5],
		[Judge.Rank.GOOD, 0.150, 0.2],
	]
	for row: Array in spec:
		var name: String = Judge.RANK_NAME[row[0]]
		check_near(Judge.WINDOW[row[0]], row[1], "%s window" % name)
		check_near(Judge.WEIGHT[row[0]], row[2], "%s weight" % name)
	check_near(Judge.WEIGHT[Judge.Rank.MISS], 0.0, "MISS weight")
	check_near(Judge.INNER_CRITICAL_WINDOW, 0.016, "inner CRITICAL window")

func test_perfect_great_and_good_edges() -> void:
	check_eq(Judge.rank_for(0.040), Judge.Rank.PERFECT, "40ms")
	check_eq(Judge.rank_for(-0.041), Judge.Rank.GREAT, "41ms early")
	check_eq(Judge.rank_for(0.080), Judge.Rank.GREAT, "80ms")
	check_eq(Judge.rank_for(-0.081), Judge.Rank.GOOD, "81ms early")
	check_eq(Judge.rank_for(0.150), Judge.Rank.GOOD, "150ms")
	check_eq(Judge.rank_for(-0.151), Judge.Rank.MISS, "151ms early")

func test_inner_critical_is_16ms_inside_critical() -> void:
	for error in [0.0, 0.016, -0.016]:
		check(Judge.is_inner_critical(error), "%.3fs is inner" % error)
		check_eq(Judge.rank_for(error), Judge.Rank.CRITICAL, "%.3fs still shows as CRITICAL" % error)
	for error in [0.017, -0.017, 0.025]:
		check(not Judge.is_inner_critical(error), "%.3fs is not inner" % error)
		check_eq(Judge.rank_for(error), Judge.Rank.CRITICAL, "%.3fs is plain CRITICAL" % error)

func test_inner_critical_is_not_a_rank() -> void:
	# Hidden: no name, color or row of its own anywhere ranks are listed.
	check_eq(Judge.Rank.size(), 5, "five visible ranks")
	check_eq(Judge.RANK_NAME.size(), 5, "five names on screen")

func test_window_edges_are_inclusive() -> void:
	for rank in [Judge.Rank.CRITICAL, Judge.Rank.PERFECT, Judge.Rank.GREAT, Judge.Rank.GOOD]:
		check_eq(Judge.rank_for(Judge.WINDOW[rank]), rank, "%s edge" % Judge.RANK_NAME[rank])

func test_just_past_each_edge_drops_a_rank() -> void:
	var nudge := 0.001
	for i in ORDER.size() - 1:
		var rank: Judge.Rank = ORDER[i]
		check_eq(Judge.rank_for(Judge.WINDOW[rank] + nudge), ORDER[i + 1], "past %s" % Judge.RANK_NAME[rank])

func test_early_and_late_are_judged_the_same() -> void:
	for error in [0.01, 0.035, 0.07, 0.12, 0.3]:
		check_eq(Judge.rank_for(-error), Judge.rank_for(error), "±%.3fs" % error)

func test_windows_widen_and_weights_fall_with_rank() -> void:
	# Guards against an edit that puts the tuning table out of order.
	for i in ORDER.size() - 1:
		var better: Judge.Rank = ORDER[i]
		var worse: Judge.Rank = ORDER[i + 1]
		var names := "%s vs %s" % [Judge.RANK_NAME[better], Judge.RANK_NAME[worse]]
		check(Judge.WEIGHT[better] > Judge.WEIGHT[worse], "weight " + names)
		if Judge.WINDOW.has(worse):
			check(Judge.WINDOW[better] < Judge.WINDOW[worse], "window " + names)

func test_only_critical_earns_full_value() -> void:
	check_eq(Judge.WEIGHT[Judge.Rank.CRITICAL], 1.0, "CRITICAL weight")
	check(Judge.WEIGHT[Judge.Rank.PERFECT] < 1.0, "PERFECT is worth less than CRITICAL")

func test_hit_window_is_the_widest_window() -> void:
	check_eq(Judge.hit_window(), Judge.WINDOW[Judge.Rank.GOOD], "hit_window()")

func test_every_rank_has_a_name_weight_and_color() -> void:
	for rank in Judge.Rank.values():
		check(Judge.RANK_NAME.has(rank), "name for rank %d" % rank)
		check(Judge.WEIGHT.has(rank), "weight for rank %d" % rank)
		check(Judge.RANK_COLOR.has(rank), "color for rank %d" % rank)

func test_grades() -> void:
	check_eq(Judge.grade_for(1.0), "S", "100%")
	check_eq(Judge.grade_for(0.98), "S", "S boundary")
	check_eq(Judge.grade_for(0.979), "A", "just under S")
	check_eq(Judge.grade_for(0.5), "D", "50%")
	check_eq(Judge.grade_for(0.0), "D", "0%")

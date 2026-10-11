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

extends TestCase

func test_exact_hit_is_perfect() -> void:
	check_eq(Judge.rank_for(0.0), Judge.Rank.PERFECT, "zero error")

func test_window_edges_are_inclusive() -> void:
	check_eq(Judge.rank_for(Judge.WINDOW[Judge.Rank.PERFECT]), Judge.Rank.PERFECT, "PERFECT edge")
	check_eq(Judge.rank_for(Judge.WINDOW[Judge.Rank.GREAT]), Judge.Rank.GREAT, "GREAT edge")
	check_eq(Judge.rank_for(Judge.WINDOW[Judge.Rank.GOOD]), Judge.Rank.GOOD, "GOOD edge")

func test_just_past_each_edge_drops_a_rank() -> void:
	var nudge := 0.001
	check_eq(Judge.rank_for(Judge.WINDOW[Judge.Rank.PERFECT] + nudge), Judge.Rank.GREAT, "past PERFECT")
	check_eq(Judge.rank_for(Judge.WINDOW[Judge.Rank.GREAT] + nudge), Judge.Rank.GOOD, "past GREAT")
	check_eq(Judge.rank_for(Judge.WINDOW[Judge.Rank.GOOD] + nudge), Judge.Rank.MISS, "past GOOD")

func test_early_and_late_are_judged_the_same() -> void:
	for error in [0.02, 0.07, 0.12, 0.3]:
		check_eq(Judge.rank_for(-error), Judge.rank_for(error), "±%.2fs" % error)

func test_windows_widen_and_weights_fall_with_rank() -> void:
	# Guards against an edit that puts the tuning table out of order.
	check(Judge.WINDOW[Judge.Rank.PERFECT] < Judge.WINDOW[Judge.Rank.GREAT], "PERFECT < GREAT window")
	check(Judge.WINDOW[Judge.Rank.GREAT] < Judge.WINDOW[Judge.Rank.GOOD], "GREAT < GOOD window")
	check(Judge.WEIGHT[Judge.Rank.PERFECT] > Judge.WEIGHT[Judge.Rank.GREAT], "PERFECT > GREAT weight")
	check(Judge.WEIGHT[Judge.Rank.GREAT] > Judge.WEIGHT[Judge.Rank.GOOD], "GREAT > GOOD weight")
	check(Judge.WEIGHT[Judge.Rank.GOOD] > Judge.WEIGHT[Judge.Rank.MISS], "GOOD > MISS weight")

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

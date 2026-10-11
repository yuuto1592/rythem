extends PlayTest

## Autoplay is deterministic (every head is hit and every hold kept down with
## zero error), so this can demand an exact perfect score. It covers spawning,
## scrolling, judging taps and holds, scoring and the end-of-chart handoff.

func run(host: Node) -> void:
	var chart := expected_chart()
	var total := chart.notes.size()
	check(chart.notes.any(func(n: ChartNote) -> bool: return n.kind == ChartNote.Kind.HOLD),
			"fixture includes holds")

	start_game(host, true)
	await play_to_end(host)
	if result.is_empty():
		return

	check_eq(result["note_count"], total, "note count")
	check_eq(result["counts"][Judge.Rank.CRITICAL], total, "all CRITICAL")
	check_eq(result["counts"][Judge.Rank.MISS], 0, "no misses")
	check_eq(result["max_combo"], total, "max combo")
	check_eq(result["score"], Judge.MAX_SCORE, "score")
	check_eq(result["grade"], "S", "grade")
	check_eq(result["full_combo"], true, "full combo")
	check_eq(result["autoplay"], true, "flagged as autoplay")
	check_eq(GameState.last_result, result, "result handed to GameState")
	check_eq(judgements.size(), total, "one judgement per note, holds included")
	# Without music the conductor runs the metronome, so beats must be ticking.
	check(beats_heard >= 5, "conductor emitted beats (got %d)" % beats_heard)

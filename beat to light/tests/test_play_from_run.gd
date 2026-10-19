extends PlayTest

## "Test from here": starting partway through drops the notes before the start
## point and scores the rest as a whole chart.

func run(host: Node) -> void:
	var chart := expected_chart()
	var spb := chart.seconds_per_beat()
	var from := 5.0 * spb  # beat 5 of the smoke chart
	var expected := chart.notes.filter(func(n: ChartNote) -> bool: return n.time >= from - 0.001).size()
	check(expected > 0 and expected < chart.notes.size(), "fixture has notes on both sides of beat 5")

	GameState.play_from_time = from
	start_game(host, true)
	await play_to_end(host)
	if result.is_empty():
		return

	check_eq(result["note_count"], expected, "only the notes from beat 5 on")
	check_eq(result["counts"][Judge.Rank.CRITICAL], expected, "all of them judged")
	check_eq(result["score"], Judge.MAX_SCORE, "scored as a whole chart")
	check(not judgements.is_empty() and judgements[0].at >= from - 0.01,
			"the first judgement is at or after the start point")

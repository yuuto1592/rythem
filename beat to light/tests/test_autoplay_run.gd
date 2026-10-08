extends PlayTest

## Autoplay is deterministic (every note is resolved with zero error), so this
## can demand an exact perfect score. It covers spawning, scrolling, judging,
## scoring and the end-of-chart handoff.

func run(host: Node) -> void:
	start_game(host, true)
	await play_to_end(host)
	if result.is_empty():
		return

	var note_count := expected_notes().size()
	check_eq(result["note_count"], note_count, "note count")
	check_eq(result["counts"][Judge.Rank.PERFECT], note_count, "all PERFECT")
	check_eq(result["counts"][Judge.Rank.MISS], 0, "no misses")
	check_eq(result["max_combo"], note_count, "max combo")
	check_eq(result["score"], Judge.MAX_SCORE, "score")
	check_eq(result["grade"], "S", "grade")
	check_eq(result["full_combo"], true, "full combo")
	check_eq(result["autoplay"], true, "flagged as autoplay")
	check_eq(GameState.last_result, result, "result handed to GameState")
	# Without music the conductor runs the metronome, so beats must be ticking.
	check(beats_heard >= 5, "conductor emitted beats (got %d)" % beats_heard)

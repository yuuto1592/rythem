extends PlayTest

## Plays the fixture by sending real key presses and releases, so the InputMap
## actions registered by KeyBinds and the game's _unhandled_input are exercised
## the way a player would exercise them. Holds are kept down past their end.
##
## A key lands on the first frame at or after its time, so a head can be up to
## a frame late. That is why heads are only required to be GREAT or better
## rather than CRITICAL: the test must not flake on a slow machine.

func run(host: Node) -> void:
	var chart := expected_chart()
	for note in chart.notes:
		schedule_key(note.time, note.lane, true)
		var release := note.end_time + 0.05 if note.kind == ChartNote.Kind.HOLD else note.time + 0.01
		schedule_key(release, note.lane, false)

	start_game(host, false)
	await play_to_end(host)
	if result.is_empty():
		return

	var total := chart.judgement_count()
	check_eq(result["counts"][Judge.Rank.MISS], 0, "no misses")
	check_eq(result["counts"][Judge.Rank.GOOD], 0, "nothing worse than GREAT")
	check_eq(result["max_combo"], total, "max combo")
	check_eq(result["full_combo"], true, "full combo")
	check_eq(result["autoplay"], false, "not flagged as autoplay")
	for j in judgements:
		if j.is_tail:
			check_eq(j.rank, Judge.Rank.CRITICAL, "lane %d: a hold kept down to the end ends CRITICAL" % j.lane)

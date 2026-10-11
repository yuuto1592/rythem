extends PlayTest

## The hold-note rules a player meets, played with real key events. One hold
## per lane in fixtures/holds.json:
##   lane 0: let go far too early     -> tail MISS
##   lane 1: never pressed            -> head MISS and tail MISS
##   lane 2: kept down past the end   -> tail CRITICAL; the late release adds nothing
##   lane 3: let go a little early    -> tail graded by how early, not missed

## Early enough to drop out of CRITICAL even if the key arrives a few frames
## late, and well inside the GOOD window.
const SLIGHTLY_EARLY := 0.10

func fixture() -> String:
	return "res://tests/fixtures/holds.json"

func run(host: Node) -> void:
	var hold := {}
	for note in expected_chart().notes:
		hold[note.lane] = note

	schedule_key(hold[0].time, 0, true)
	schedule_key(hold[0].time + 0.5 * (hold[0].end_time - hold[0].time), 0, false)
	schedule_key(hold[2].time, 2, true)
	schedule_key(hold[2].end_time + 0.2, 2, false)
	schedule_key(hold[3].time, 3, true)
	schedule_key(hold[3].end_time - SLIGHTLY_EARLY, 3, false)

	start_game(host, false)
	await play_to_end(host)
	if result.is_empty():
		return

	var lane0 := ranks_in_lane(0)
	check_eq(lane0.size(), 2, "lane 0: head and tail judged")
	if lane0.size() == 2:
		check(lane0[0] != Judge.Rank.MISS, "lane 0: head hit")
		check_eq(lane0[1], Judge.Rank.MISS, "lane 0: released halfway is a MISS")

	var lane1 := ranks_in_lane(1)
	check_eq(lane1.size(), 2, "lane 1: head and tail judged")
	check(lane1.all(func(rank: Judge.Rank) -> bool: return rank == Judge.Rank.MISS),
			"lane 1: an untouched hold misses head and tail")

	var lane2 := ranks_in_lane(2)
	check_eq(lane2.size(), 2, "lane 2: releasing after the end adds no judgement")
	if lane2.size() == 2:
		check(lane2[0] != Judge.Rank.MISS, "lane 2: head hit")
		check_eq(lane2[1], Judge.Rank.CRITICAL, "lane 2: held past the end is CRITICAL")

	var lane3 := ranks_in_lane(3)
	check_eq(lane3.size(), 2, "lane 3: head and tail judged")
	if lane3.size() == 2:
		check(lane3[0] != Judge.Rank.MISS, "lane 3: head hit")
		check(lane3[1] in [Judge.Rank.PERFECT, Judge.Rank.GREAT, Judge.Rank.GOOD],
				"lane 3: released %dms early is graded, not missed or CRITICAL (got %s)"
				% [int(SLIGHTLY_EARLY * 1000), Judge.RANK_NAME[lane3[1]]])

	check_eq(result["counts"][Judge.Rank.MISS], 3, "three misses in total")
	check_eq(result["full_combo"], false, "no full combo")

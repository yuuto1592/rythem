extends PlayTest

## The hold-note rules a player meets, played with real key events. A hold is
## judged once: the head sets the rank, which stands only if the key stays down
## to the end. One hold per lane in fixtures/holds.json:
##   lane 0: let go halfway                  -> MISS, judged when let go
##   lane 1: never pressed                   -> MISS
##   lane 2: kept down past the end          -> the head's rank, judged at the end;
##                                              the late release adds nothing
##   lane 3: let go just before the end      -> still the head's rank (grace period)

## Inside Judge.HOLD_RELEASE_GRACE even if the key arrives a few frames late.
const JUST_BEFORE_END := 0.05
## How long lane 2 stays down after its end: long enough to tell "judged at the
## end" from "judged when finally let go".
const KEPT_PAST_END := 0.2

func fixture() -> String:
	return "res://tests/fixtures/holds.json"

func run(host: Node) -> void:
	var hold := {}
	for note in expected_chart().notes:
		hold[note.lane] = note
	var halfway: float = hold[0].time + 0.5 * (hold[0].end_time - hold[0].time)

	schedule_key(hold[0].time, 0, true)
	schedule_key(halfway, 0, false)
	schedule_key(hold[2].time, 2, true)
	schedule_key(hold[2].end_time + KEPT_PAST_END, 2, false)
	schedule_key(hold[3].time, 3, true)
	schedule_key(hold[3].end_time - JUST_BEFORE_END, 3, false)

	start_game(host, false)
	await play_to_end(host)
	if result.is_empty():
		return

	check_eq(judgements.size(), 4, "one judgement per hold")
	var by_lane := {}
	for j in judgements:
		check(not by_lane.has(j.lane), "lane %d judged only once" % j.lane)
		by_lane[j.lane] = j
	if by_lane.size() != 4:
		return

	check_eq(by_lane[0].rank, Judge.Rank.MISS, "lane 0: let go halfway is a MISS")
	check(by_lane[0].at < hold[0].end_time, "lane 0: judged when let go, not at the end")

	check_eq(by_lane[1].rank, Judge.Rank.MISS, "lane 1: never pressed is a MISS")

	check(by_lane[2].rank != Judge.Rank.MISS, "lane 2: held past the end keeps the head's rank")
	check(by_lane[2].at >= hold[2].end_time, "lane 2: judged at the end, not when pressed")
	check(by_lane[2].at < hold[2].end_time + KEPT_PAST_END,
			"lane 2: judged at the end, without waiting for the key to come up")

	check(by_lane[3].rank != Judge.Rank.MISS,
			"lane 3: let go %dms before the end still counts as held" % int(JUST_BEFORE_END * 1000))

	check_eq(result["counts"][Judge.Rank.MISS], 2, "two misses in total")
	check_eq(result["full_combo"], false, "no full combo")

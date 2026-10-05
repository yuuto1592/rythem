class_name Judge
extends RefCounted

## Timing windows and scoring weights. Tune the game's feel from here.

enum Rank { PERFECT, GREAT, GOOD, MISS }

## Largest timing error, in seconds, that still earns each rank.
## Anything worse than GOOD is a miss.
const WINDOW := {
	Rank.PERFECT: 0.045,
	Rank.GREAT: 0.090,
	Rank.GOOD: 0.150,
}

## How much of a note's value each rank is worth.
const WEIGHT := {
	Rank.PERFECT: 1.0,
	Rank.GREAT: 0.7,
	Rank.GOOD: 0.4,
	Rank.MISS: 0.0,
}

const RANK_NAME := {
	Rank.PERFECT: "PERFECT",
	Rank.GREAT: "GREAT",
	Rank.GOOD: "GOOD",
	Rank.MISS: "MISS",
}

const RANK_COLOR := {
	Rank.PERFECT: Color("ffe66d"),
	Rank.GREAT: Color("6dd3ff"),
	Rank.GOOD: Color("8ee97f"),
	Rank.MISS: Color("ff6b6b"),
}

## A full-score run is worth this much, no matter how many notes it has.
const MAX_SCORE := 1_000_000

## Rank boundaries for the result screen, best first.
const GRADES := [
	["S", 0.98],
	["A", 0.93],
	["B", 0.85],
	["C", 0.70],
	["D", 0.0],
]

## Widest window a press can land in and still hit a note.
static func hit_window() -> float:
	return WINDOW[Rank.GOOD]

## [param error] is seconds late (positive) or early (negative).
static func rank_for(error: float) -> Rank:
	var distance := absf(error)
	if distance <= WINDOW[Rank.PERFECT]:
		return Rank.PERFECT
	if distance <= WINDOW[Rank.GREAT]:
		return Rank.GREAT
	if distance <= WINDOW[Rank.GOOD]:
		return Rank.GOOD
	return Rank.MISS

static func grade_for(accuracy: float) -> String:
	for grade: Array in GRADES:
		if accuracy >= float(grade[1]):
			return str(grade[0])
	return "D"

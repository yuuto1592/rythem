# beat to light

A 4-lane falling-note rhythm game in Godot 4. This is a playable base, not a
finished game: the timing, scoring, chart format and scene flow all work, and
each piece is small enough to replace.

Open `project.godot` in Godot 4 and press F5.

## Controls

| Key | Action |
| --- | --- |
| `D` `F` `J` `K` | Lanes 1–4 |
| `R` | Restart the chart |
| `F1` | Toggle autoplay |
| `Esc` | Back to song select (quit from the menu) |

Lane keys are physical key positions, so they stay under the same fingers on a
non-QWERTY layout. Change them in `scripts/key_binds.gd`.

## What is in here

```
scenes/
  main_menu.tscn    song select; lists every chart in songs/
  game.tscn         the playfield, the conductor and the HUD
  result.tscn       score, grade and judgement breakdown
scripts/
  conductor.gd      the clock: "when is now?" in song time
  chart.gd          loads a JSON chart; beats -> seconds
  chart_note.gd     one note (time, lane, kind)
  judge.gd          timing windows, scoring weights, grades
  game.gd           the gameplay loop
  playfield.gd      lane geometry and lane drawing
  note.gd           a single falling note
  hud.gd            in-game readouts
  main_menu.gd / result.gd
  game_state.gd     autoload: what survives a scene change
  sfx.gd            autoload: hit/miss/metronome blips, synthesised at startup
  key_binds.gd      key layout, registered into the InputMap at runtime
songs/
  01_warm_up.json    "Warm Up" — 32 quarter notes, 100 BPM
  02_first_light.json "First Light" — 124 notes, 120 BPM
tests/
  run_tests.sh       headless test entry point (see Testing)
  test_runner.tscn   the scene that runs every test
  test_*.gd          the tests themselves
  fixtures/          charts used only by tests
```

## How timing works

Everything derives from `Conductor.chart_time`. Nothing accumulates its own
delta, so a dropped frame cannot make the notes drift away from the music.

- With a song loaded, the conductor reads the audio playback position and
  corrects it with `AudioServer.get_time_since_last_mix()` and the output
  latency, which is what keeps the visuals matched to what you hear.
- With no song, it runs on the system clock and `Sfx.play_tick()` gives the
  player a metronome instead. Both bundled charts work this way, so the project
  is playable before you have any audio.

A note's screen position is just its distance from now:
`Playfield.y_for(note.time - chart_time)`. A note `scroll_time` seconds away
sits at the top of the screen; at 0 it is on the judge line.

## Writing a chart

Drop a JSON file in `songs/` and it shows up in song select. Song select is
sorted by file name, which is what the number prefixes are for.

```json
{
  "title": "First Light",
  "artist": "tutorial chart",
  "bpm": 120,
  "offset": 0.0,
  "lane_count": 4,
  "scroll_time": 1.1,
  "music": "",
  "notes": [
    {"beat": 4, "lane": 0},
    {"beat": 4.5, "lane": 2}
  ]
}
```

- `beat` is counted from the start of the chart; `0.5` is an eighth note at 4/4.
  A note can use `"time"` in seconds instead if you would rather place it by hand.
- `lane` is zero-based, left to right.
- Two notes on the same beat in different lanes make a jump. Nothing special is
  needed for chords.
- `scroll_time` is how long a note is visible before it has to be hit. Lower is
  faster and harder.
- `offset` shifts every note later, in seconds. Use it to line a chart up with
  its audio.

## Adding music

Put an `.ogg` next to the chart, point the chart's `"music"` field at it
(`"res://songs/mysong.ogg"`), and the conductor switches to the audio clock on
its own. If the notes feel consistently early or late against the track, nudge
`offset` rather than moving the notes.

Exported builds need `*.json` added to **Project > Export > Resources >
Filters to export non-resource files**, otherwise `songs/` ships empty.

## Tuning the feel

`scripts/judge.gd` holds all of it in one place: the timing windows (how late a
press can be and still count), what each rank is worth, the grade cut-offs and
the maximum score. The score is normalised, so a full combo is always
`MAX_SCORE` no matter how many notes a chart has.

## Testing

The tests need nothing but Godot itself: no plugin, no addon. They run
headless, so they work on a server or in CI as well as on your machine.

### What you need

- **Godot 4.x.** The suite is verified on 4.3 stable. Download it from
  <https://godotengine.org/download/archive/>. The standard build is enough; the
  .NET build is not needed.
- **bash**, for `run_tests.sh` (macOS, Linux, Git Bash or WSL on Windows). On
  plain Windows, run the commands it wraps directly; see below.

There is no audio device on a headless machine. Godot falls back to a dummy
audio driver, the game still runs, and the tests do not depend on hearing
anything.

### Running the tests

From the project folder:

```sh
tests/run_tests.sh                                   # `godot` on your PATH
GODOT=~/bin/Godot_v4.3-stable_linux.x86_64 tests/run_tests.sh
```

Without bash (PowerShell or cmd), run the two steps yourself from the project
folder:

```sh
godot --headless --editor --quit --path .            # first time only
godot --headless --path . res://tests/test_runner.tscn
```

From the editor: open `tests/test_runner.tscn` and press **F6** (Run Current
Scene). Results appear in the Output panel.

A passing run looks like this and exits with code 0. Any failure exits with 1
and prints what was expected next to what happened:

```
  PASS  test_judge.test_exact_hit_is_perfect
  ...
  PASS  test_autoplay_run
  PASS  test_input_run

28 passed, 0 failed (5.9s)
```

> **First run on a fresh checkout.** Godot only learns the global class names
> (`Chart`, `Judge`, `Conductor`, ...) when it imports the project, and
> `.godot/` is not committed. Without that step every script fails with
> `Identifier "Chart" not declared`. `run_tests.sh` imports automatically when
> `.godot/` is missing. If you add a new `class_name` and see that error, run
> the import line above again.

> **Time limit.** A script with a syntax error does not make Godot exit; it
> sits on an empty scene forever. `run_tests.sh` therefore stops the run after
> 90 seconds, exits with 124 and says so. Look for `SCRIPT ERROR` in the output
> to find the broken file. Raise the limit with `TEST_TIMEOUT=300` if the suite
> ever legitimately needs longer. (On macOS this needs `gtimeout` from
> `brew install coreutils`; without it the run is not capped.)

### Continuous integration

`.github/workflows/tests.yml` (at the repository root, not in this folder) runs
the same `run_tests.sh` on GitHub's servers:

- **When:** every push to `main`, every pull request, and on demand from the
  Actions tab (**Run workflow**).
- **Where to look:** the checks section at the bottom of a pull request, the
  ✓/✗ next to each commit, and the **Actions** tab for full logs.
- **Godot is cached.** The first run downloads Godot (about 50 MB) and saves
  it; later runs restore it in seconds and skip the download. The log shows
  which happened: the "Download Godot (cache miss only)" step is skipped on a
  cache hit.
- A pull request can use the cache from its own earlier runs and from `main`.
  Until `main` has run once, each new pull request downloads Godot on its
  first run. GitHub deletes caches that go unused for 7 days; the next run
  then downloads again and re-caches.
- **Changing the Godot version:** edit `GODOT_VERSION` at the top of the
  workflow (a release tag such as `4.4-stable`). The cache is keyed on it, so
  the new version is downloaded once and cached from then on.
- A newer push to the same branch cancels the run it makes obsolete, and the
  job is capped at 10 minutes as a backstop, so a stuck run cannot use up
  Actions minutes.

### What is covered

| File | What it checks |
| --- | --- |
| `test_judge.gd` | Window edges, early = late, rank ordering, grades. Catches a tuning edit that breaks the table, e.g. a GREAT window narrower than PERFECT. |
| `test_chart.gd` | Beats to seconds, sorting, lane clamping, junk entries, defaults. **Also loads every chart in `songs/`**, so a broken chart fails the suite. |
| `test_playfield.gd` | Lane positions and the time-to-screen mapping. |
| `test_conductor.gd` | Beat length and the clock-mode fallback. |
| `test_autoplay_run.gd` | Plays `game.tscn` for real with autoplay: spawning, scrolling, judging, scoring, the result handoff and the metronome. Expects an exact perfect score. |
| `test_input_run.gd` | Plays it again by **sending real key events**, which exercises the key bindings and the input handling that autoplay bypasses. |

The two play tests run on the wall clock against
`tests/fixtures/smoke.json` (5 notes, about 3 seconds each). A synthesised
press can land up to one frame late, so the input test accepts PERFECT or
GREAT rather than demanding PERFECT. That keeps it from failing on a slow
machine while still catching a broken input path.

The play tests put the game scene inside the test runner instead of switching
to it. `game.gd` emits `run_finished(result)` and only changes scene when it is
the scene being played, which is what makes that possible.

### Adding a test

Unit test: create `tests/test_something.gd`, extend `TestCase`, write methods
whose names start with `test_`, and add the script to `UNIT_TESTS` in
`test_runner.gd`. Each method gets a fresh instance.

```gdscript
extends TestCase

func test_quarter_note_at_60_bpm() -> void:
	var chart := Chart.from_dict({"bpm": 60, "notes": [{"beat": 1, "lane": 0}]})
	check_near(chart.notes[0].time, 1.0, "one beat is one second")
```

Available checks: `check(condition, message)`, `check_eq(actual, expected,
message)` and `check_near(actual, expected, message, tolerance)`. GDScript has
no exceptions, so a failed check records the message and the test continues.

Test that needs the running game: extend `PlayTest` instead, override
`run(host)`, and add it to `PLAY_TESTS`. `test_input_run.gd` is the example to
copy.

### What the tests cannot tell you

Headless means nothing is drawn and nothing is heard. Check these by hand
after changing the playfield, the HUD or the timing code:

- [ ] The lanes, notes and judge line look right at the window size you ship.
- [ ] HUD text fits and does not overlap the playfield.
- [ ] With a real song, notes land on the beat you hear. If they are
      consistently early or late, adjust the chart's `offset`.
- [ ] Hit and miss sounds play, and the metronome plays when there is no music.

### Exporting

`tests/` ships in exported builds unless you exclude it. Add `tests/*` to
**Project > Export > Resources > Filters to exclude files/folders**.

## Where to go next

- **Hold notes.** `ChartNote.Kind` already exists with only `TAP` in it; the
  loader will pass a `kind` through untouched. The work is in `game.gd`
  (judging a release) and `note.gd` (drawing a tail).
- **Hit effects.** `Playfield.flash()` is the hook — it already fires on every
  key press.
- **Real graphics.** `note.gd` and `playfield.gd` draw everything in code;
  swap `_draw()` for sprites.
- **Per-note offset calibration.** The conductor's `offset` is global; a
  calibration screen that measures the player's own latency would set it.

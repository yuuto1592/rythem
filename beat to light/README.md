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

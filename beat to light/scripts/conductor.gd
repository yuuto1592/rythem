class_name Conductor
extends Node

## The single source of truth for "when is now?".
##
## Everything that needs the song position asks the conductor instead of
## accumulating its own delta, so the notes never drift away from the music.
## With an audio stream assigned to the child [AudioStreamPlayer] the audio
## clock wins; without one the conductor runs on the system clock, which is
## what lets a chart be played before you have a song for it.

signal beat_hit(beat_index: int)
signal finished

## Beats per minute the chart was written against.
@export var bpm := 120.0
## Silence before chart time 0, so the first notes have room to scroll in.
@export var lead_in := 2.5
## Added to every note time; raise it if the chart feels early against the audio.
@export var offset := 0.0

var playing := false
## Raw audio position in seconds. Negative during the lead-in.
var song_time := 0.0
## [member song_time] with [member offset] applied. Notes are judged against this.
var chart_time := 0.0

var _music: AudioStreamPlayer
var _start_usec := 0
var _music_started := false
var _last_beat := -1
var _end_time := INF

func _ready() -> void:
	_music = get_node_or_null(^"Music") as AudioStreamPlayer
	set_process(false)

func seconds_per_beat() -> float:
	return 60.0 / maxf(bpm, 1.0)

## True when a song is loaded, i.e. when the audio clock drives playback.
func has_music() -> bool:
	return _music != null and _music.stream != null

func set_music(stream: AudioStream) -> void:
	if _music != null:
		_music.stream = stream

## Runs until [param end_time] (chart seconds), then emits [signal finished].
func start(end_time := INF) -> void:
	_end_time = end_time
	_last_beat = -1
	_music_started = false
	song_time = -lead_in
	chart_time = song_time - offset
	_start_usec = Time.get_ticks_usec()
	playing = true
	set_process(true)

func stop() -> void:
	playing = false
	set_process(false)
	if _music != null and _music.playing:
		_music.stop()

func _process(_delta: float) -> void:
	song_time = float(Time.get_ticks_usec() - _start_usec) / 1_000_000.0 - lead_in

	if has_music():
		if not _music_started and song_time >= 0.0:
			_music.play(song_time)
			_music_started = true
		if _music_started and _music.playing:
			var position := _music.get_playback_position()
			if position > 0.0:
				# Compensate for the audio buffer so the visuals match what we hear.
				song_time = position + AudioServer.get_time_since_last_mix() \
						- AudioServer.get_output_latency()

	chart_time = song_time - offset
	_emit_due_beats()

	if chart_time >= _end_time:
		stop()
		finished.emit()

func _emit_due_beats() -> void:
	var current := floori(chart_time / seconds_per_beat())
	while _last_beat < current:
		_last_beat += 1
		if _last_beat >= 0:
			beat_hit.emit(_last_beat)

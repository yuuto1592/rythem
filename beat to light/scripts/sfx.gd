extends Node

## Autoload. Synthesises its own blips at startup so the game makes a noise
## without shipping any audio files. Replace the generated streams with real
## samples when you have them — the play_* API stays the same.

const SAMPLE_RATE := 44100
## Number of players kept around, i.e. how many blips can overlap.
const VOICES := 8

var _hit: AudioStreamWAV
var _miss: AudioStreamWAV
var _tick: AudioStreamWAV
var _click: AudioStreamWAV

var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0

func _ready() -> void:
	_hit = _make_blip(1320.0, 0.06, 0.30)
	_miss = _make_blip(170.0, 0.14, 0.26)
	_tick = _make_blip(880.0, 0.04, 0.12)
	_click = _make_blip(620.0, 0.05, 0.18)
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_voices.append(player)

func play_hit() -> void:
	_play(_hit)

func play_miss() -> void:
	_play(_miss)

## Metronome beat, used while a chart has no music of its own.
func play_tick() -> void:
	_play(_tick)

func play_ui() -> void:
	_play(_click)

func _play(stream: AudioStream) -> void:
	if _voices.is_empty():
		return
	var player := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	player.stream = stream
	player.play()

## A sine blip with an exponential decay — short enough to read as percussive.
func _make_blip(frequency: float, length: float, volume: float) -> AudioStreamWAV:
	var frames := int(SAMPLE_RATE * length)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var decay := maxf(length * 0.25, 0.001)
	for i in frames:
		var t := float(i) / float(SAMPLE_RATE)
		var sample := sin(TAU * frequency * t) * exp(-t / decay) * volume
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream

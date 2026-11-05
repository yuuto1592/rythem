class_name Waveform
extends RefCounted

## How loud a song is over time, for drawing next to the chart so notes can be
## lined up with what is heard. Decoding a whole song takes a moment, so
## start() does it on a thread; poll() each frame until it returns true.

## One peak per this many seconds of music.
const BUCKET_SECONDS := 0.01

## The loudest sample in each bucket, 0..1.
var peaks := PackedFloat32Array()
## Seconds each entry of [member peaks] covers.
var bucket_seconds := BUCKET_SECONDS
## The loudest peak in the song, for scaling the drawing; 0 until ready.
var loudest := 0.0

var _thread: Thread

## Decodes [param stream] now, on this thread. Returns {peaks, bucket_seconds}.
static func compute(stream: AudioStream, seconds := BUCKET_SECONDS) -> Dictionary:
	var out := PackedFloat32Array()
	var length := stream.get_length()
	var playback := stream.instantiate_playback()
	if playback == null or length <= 0.0:
		return {"peaks": out, "bucket_seconds": seconds}
	var rate := AudioServer.get_mix_rate()
	var chunk := maxi(int(rate * seconds), 1)
	# A looping stream never stops playing; one pass is all we want.
	var limit := int(rate * (length + 1.0))
	var total := 0
	playback.start(0.0)
	while playback.is_playing() and total < limit:
		var frames := playback.mix_audio(1.0, chunk)
		if frames.is_empty():
			break
		var peak := 0.0
		for frame in frames:
			peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		out.append(peak)
		total += frames.size()
	playback.stop()
	# Measure what a bucket really covers rather than trusting the mix rate.
	var actual := seconds
	if total > 0:
		actual = chunk * minf(length, float(total) / rate) / total
	return {"peaks": out, "bucket_seconds": actual}

## Starts decoding [param stream] in the background, dropping any earlier song.
func start(stream: AudioStream) -> void:
	finish()
	peaks = PackedFloat32Array()
	loudest = 0.0
	if stream == null:
		return
	_thread = Thread.new()
	_thread.start(_decode.bind(stream))

## True once, on the frame the background decoding has finished.
func poll() -> bool:
	if _thread == null or _thread.is_alive():
		return false
	_take(_thread.wait_to_finish())
	_thread = null
	return true

## Waits for any decoding still running. Call before the waveform goes away.
func finish() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null

func is_ready() -> bool:
	return _thread == null and not peaks.is_empty()

## The loudest peak between song times [param from_time] and [param to_time].
func peak_between(from_time: float, to_time: float) -> float:
	if peaks.is_empty():
		return 0.0
	var first := maxi(floori(from_time / bucket_seconds), 0)
	var last := mini(ceili(to_time / bucket_seconds), peaks.size() - 1)
	var peak := 0.0
	for i in range(first, last + 1):
		peak = maxf(peak, peaks[i])
	return peak

func _decode(stream: AudioStream) -> Dictionary:
	return compute(stream)

func _take(result: Dictionary) -> void:
	peaks = result.peaks
	bucket_seconds = result.bucket_seconds
	loudest = 0.0
	for p in peaks:
		loudest = maxf(loudest, p)

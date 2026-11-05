extends TestCase

## The waveform drawn next to the chart: decoded from the music, and lined up
## with time. The fixture is half a second of silence, then half a second of
## tone.

const FIXTURE := "res://tests/fixtures/silence_then_beep.ogg"

func _stream() -> AudioStream:
	return AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(FIXTURE))

func test_peaks_follow_the_sound() -> void:
	var wave := Waveform.new()
	wave._take(Waveform.compute(_stream()))
	check_near(wave.bucket_seconds, Waveform.BUCKET_SECONDS, "one peak per 10ms", 0.001)
	check_near(wave.peaks.size() * wave.bucket_seconds, 1.0, "covers the whole second", 0.03)
	check(wave.peak_between(0.0, 0.45) < 0.02, "silent first half (got %f)" % wave.peak_between(0.0, 0.45))
	# ffmpeg's tone is an eighth of full scale.
	check(wave.peak_between(0.55, 0.95) > 0.1, "loud second half (got %f)" % wave.peak_between(0.55, 0.95))
	check(wave.loudest >= wave.peak_between(0.55, 0.95), "loudest is the loudest")
	check_eq(wave.peak_between(5.0, 6.0), 0.0, "past the end is silent")

func test_no_music_no_waveform() -> void:
	var wave := Waveform.new()
	wave.start(null)
	check(not wave.poll(), "nothing to wait for")
	check(not wave.is_ready(), "nothing to draw")
	check_eq(wave.peak_between(0.0, 1.0), 0.0, "silent")

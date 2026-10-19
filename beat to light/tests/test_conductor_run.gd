extends TestCase

## Conductor.start_at, on the real clock: playback starts where it is told and
## the metronome picks up at the next beat rather than replaying earlier ones.

var _beats: Array[int] = []

func run(host: Node) -> void:
	var conductor := Conductor.new()
	conductor.bpm = 120.0  # half a second per beat
	host.add_child(conductor)
	conductor.beat_hit.connect(func(index: int) -> void: _beats.append(index))

	conductor.start_at(10.1)
	# Beat 21 is at 10.5s, 0.4s in.
	await host.get_tree().create_timer(0.6).timeout
	check(conductor.chart_time >= 10.6 and conductor.chart_time < 11.2,
			"started at 10.1s and ran about 0.6s (at %.3f)" % conductor.chart_time)
	check(not _beats.is_empty() and _beats[0] == 21, "first beat is 21, the next after 10.1s (got %s)" % [_beats])
	check(not _beats.has(20), "beats before the start are not replayed")

	conductor.stop()
	_beats.clear()
	conductor.start_at(5.0)
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	check(not _beats.is_empty() and _beats[0] == 10, "starting exactly on a beat plays that beat (got %s)" % [_beats])
	conductor.queue_free()

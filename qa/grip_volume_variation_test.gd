extends SceneTree
## Perceptual regression: quieter catches, varied textures, no channel stealing.
## Uses the imported streams, so the same assertions work against an exported PCK.
const Sound = preload("res://scripts/audio.gd")
const CLIP_NAMES: Array[String] = ["grip_1", "grip_2", "grip_3", "grip_4", "grip_5", "grip_6"]

var checks: int = 0
var failures: Array[String] = []
var sound: Node

func _initialize() -> void:
	call_deferred("_run")

func verify(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures.append(detail)
		print("FAIL ", detail)

func grip_player() -> AudioStreamPlayer:
	return sound.get("_grip_touch") as AudioStreamPlayer

func begin_audio() -> void:
	sound.reset_ascent()
	sound.set_muted(false)
	sound.set_climbing_state(80.0, true, false)

func identify(stream: AudioStream) -> String:
	for clip: String in CLIP_NAMES:
		if sound._clips.get(clip) == stream:
			return clip
	return ""

func decode(stream: AudioStreamWAV) -> Dictionary:
	var samples: PackedFloat32Array = PackedFloat32Array()
	var rate: int = stream.mix_rate
	if stream.format == AudioStreamWAV.FORMAT_16_BITS:
		var channels: int = 2 if stream.stereo else 1
		var count: int = stream.data.size() / (2 * channels)
		samples.resize(count)
		for frame in range(count):
			var value: float = float(stream.data.decode_s16(frame * channels * 2)) / 32768.0
			if channels == 2:
				value = (value + float(stream.data.decode_s16(frame * channels * 2 + 2)) / 32768.0) * 0.5
			samples[frame] = value
	else:
		# Exporters may compress WAV imports. Decode actual playback rather than
		# silently skipping the acoustic checks when source WAVs are unavailable.
		var playback: AudioStreamPlayback = stream.instantiate_playback()
		if playback == null or not playback.has_method("mix_audio"):
			return {}
		rate = int(AudioServer.get_mix_rate())
		playback.start()
		var frames: PackedVector2Array = playback.mix_audio(1.0, ceili(stream.get_length() * rate))
		playback.stop()
		samples.resize(frames.size())
		for frame in range(frames.size()):
			samples[frame] = (frames[frame].x + frames[frame].y) * 0.5
	return {"samples": samples, "rate": rate}

func measure(samples: PackedFloat32Array, rate: int) -> Dictionary:
	var energy: float = 0.0
	var late_energy: float = 0.0
	var body_energy: float = 0.0
	var body_difference: float = 0.0
	var center: float = 0.0
	var peak: float = 0.0
	var dc: float = 0.0
	var previous: float = 0.0
	for frame in range(samples.size()):
		var value: float = samples[frame]
		var squared: float = value * value
		var t: float = float(frame) / float(rate)
		energy += squared
		dc += value
		peak = maxf(peak, absf(value))
		center += t * squared
		if t >= 0.15:
			late_energy += squared
		else:
			body_energy += squared
			body_difference += pow(value - previous, 2.0)
		previous = value
	var duration: float = float(samples.size()) / rate
	return {"duration": duration, "peak": peak,
		"rms": sqrt(energy / maxi(1, samples.size())),
		"dc": dc / maxi(1, samples.size()),
		"body_rms": sqrt(body_energy / maxf(1.0, minf(0.15, duration) * rate)),
		"tail_rms": sqrt(late_energy / maxf(1.0, (duration - 0.15) * rate)),
		"tail_share": late_energy / maxf(energy, 0.000001),
		"center": center / maxf(energy, 0.000001),
		# First-difference energy is a simple reproducible brightness/roughness
		# measure. It distinguishes contact textures without assuming a synth's
		# filter constants, exact FFT bins, or a particular waveform generator.
		"roughness": body_difference / maxf(body_energy, 0.000001)}

func check_imported_textures() -> void:
	var hashes: Dictionary = {}
	var reports: Array[Dictionary] = []
	for clip: String in CLIP_NAMES:
		var stream: AudioStreamWAV = sound._clips.get(clip) as AudioStreamWAV
		verify(stream != null and not stream.data.is_empty(), clip + " imports as a nonempty playable stream")
		if stream == null or stream.data.is_empty():
			continue
		hashes[hash(stream.data)] = true
		var decoded: Dictionary = decode(stream)
		verify(not decoded.is_empty() and not decoded.get("samples", PackedFloat32Array()).is_empty(), clip + " waveform can be inspected in source or release")
		if decoded.is_empty() or decoded.samples.is_empty():
			continue
		var report: Dictionary = measure(decoded.samples, int(decoded.rate))
		reports.append(report)
		verify(report.duration >= 0.20 and report.duration <= 0.85, clip + " remains a short contact, pressure and grit gesture")
		verify(report.peak <= 0.551 and report.peak >= 0.10, clip + " has a restrained peak with audible material")
		verify(report.body_rms > 0.005 and report.tail_rms > 0.00015 and report.tail_rms < report.body_rms, clip + " keeps a quiet grain tail below the initial grasp")
		verify(absf(report.dc) < 0.01, clip + " has no material DC offset")
		print("GRIP_VARIATION_WAVEFORM ", clip, " ", JSON.stringify(report))
	verify(hashes.size() == 6, "Six catches use six different sample payloads")
	if reports.size() != 6:
		return
	var shortest: float = INF
	var longest: float = 0.0
	var darkest: float = INF
	var brightest: float = 0.0
	var least_tail: float = INF
	var most_tail: float = 0.0
	for report: Dictionary in reports:
		shortest = minf(shortest, report.duration)
		longest = maxf(longest, report.duration)
		darkest = minf(darkest, report.roughness)
		brightest = maxf(brightest, report.roughness)
		least_tail = minf(least_tail, report.tail_share)
		most_tail = maxf(most_tail, report.tail_share)
	verify(longest - shortest >= 0.10, "Library includes clearly shorter and longer settling gestures")
	verify(brightest / maxf(darkest, 0.000001) >= 1.25, "Contact bodies differ in texture beyond random noise seeds")
	verify(most_tail - least_tail >= 0.01, "Library varies the amount of loose grit after the grasp")
	print("GRIP_VARIATION_SPREAD duration=", longest - shortest, " roughness_ratio=", brightest / maxf(darkest, 0.000001), " tail_share=", most_tail - least_tail)

func check_levels_and_phrases() -> void:
	for kind: String in ["normal", "wet", "small"]:
		begin_audio()
		sound._grip_rng.seed = 59318
		sound._grip_bag.clear()
		sound._last_grip_sample = -1
		var previous: String = ""
		var phrase: Dictionary = {}
		var lowest_gain: float = INF
		var highest_gain: float = -INF
		var lowest_pitch: float = INF
		var highest_pitch: float = 0.0
		var total_gain: float = 0.0
		for attempt in range(48):
			sound.play_grip(kind)
			var player: AudioStreamPlayer = grip_player()
			var clip: String = identify(player.stream)
			verify(player.playing and not clip.is_empty(), kind + " contact plays an imported grip sample")
			verify(clip != previous, kind + " sequence avoids adjacent repetition, including bag boundaries")
			phrase[clip] = true
			previous = clip
			if attempt % 6 == 5:
				verify(phrase.size() == 6, kind + " six-contact phrase includes every texture")
				phrase.clear()
			lowest_gain = minf(lowest_gain, player.volume_db)
			highest_gain = maxf(highest_gain, player.volume_db)
			total_gain += player.volume_db
			lowest_pitch = minf(lowest_pitch, player.pitch_scale)
			highest_pitch = maxf(highest_pitch, player.pitch_scale)
		var mean_gain: float = total_gain / 48.0
		verify(mean_gain <= (-10.5 if kind == "normal" else -12.0), kind + " average catch is quieter than the old mix by at least 4 dB")
		verify(highest_gain <= (-10.1 if kind == "normal" else -11.5) and lowest_gain >= -14.0, kind + " random gains remain within the softer mix")
		verify(highest_gain - lowest_gain >= 0.6 and highest_gain - lowest_gain <= 2.0, kind + " catches have modest loudness variation")
		verify(highest_pitch - lowest_pitch >= 0.035 and lowest_pitch >= 0.88 and highest_pitch <= 1.15, kind + " pitch variation is audible but remains natural")
		print("GRIP_VARIATION_PLAYBACK ", kind, " mean_db=", mean_gain, " gain_range=", Vector2(lowest_gain, highest_gain), " pitch_range=", Vector2(lowest_pitch, highest_pitch))

func check_channel_lifecycle() -> void:
	begin_audio()
	sound.play_recovery()
	sound.play_exertion(2.5, 2.815, 1.6)
	var voice: AudioStreamPlayer = sound._voice
	var recovery: AudioStreamPlayer = sound._recovery
	var voice_stream: AudioStream = voice.stream
	var recovery_stream: AudioStream = recovery.stream
	verify(voice.playing and recovery.playing, "Independent exertion and rest fixtures are audible")
	sound.play_grip()
	verify(grip_player() != voice and grip_player() != recovery and voice.playing and recovery.playing and voice.stream == voice_stream and recovery.stream == recovery_stream, "Grip textures leave voice and recovery playback running")
	sound.stop_grip()
	verify(not grip_player().playing and voice.playing and recovery.playing, "Stopping grip leaves other feedback channels intact")
	for stop: String in ["mute", "inactive", "reset", "summit"]:
		begin_audio()
		sound.play_grip()
		verify(grip_player().playing, stop + " fixture has a contact tail")
		match stop:
			"mute": sound.set_muted(true)
			"inactive": sound.set_climbing_state(80.0, false, false)
			"reset": sound.reset_ascent()
			"summit":
				# The completed final catch may finish naturally under summit music.
				sound.play_summit()
				sound.stop_grip()
		verify(not grip_player().playing, stop + " cancels a contact tail when requested")
		var old_stream: AudioStream = grip_player().stream
		sound.play_grip()
		verify(not grip_player().playing and grip_player().stream == old_stream, stop + " suppresses new catches")
		sound.set_muted(false)
		sound.set_climbing_state(80.0, true, false)
		sound._process(2.0)
		verify(not grip_player().playing, stop + " never queues a suppressed contact for replay")

func _run() -> void:
	verify("--qa-capture" in OS.get_cmdline_user_args(), "Run in isolated --qa-capture mode")
	if not failures.is_empty():
		quit(1)
		return
	sound = Sound.new()
	root.add_child(sound)
	sound.set_process(false)
	sound.start_ambience()
	verify(grip_player() != null, "Audio exposes the dedicated grip channel")
	if grip_player() != null:
		check_imported_textures()
		check_levels_and_phrases()
		check_channel_lifecycle()
	sound.shutdown()
	for child: Node in sound.get_children():
		if child is AudioStreamPlayer:
			verify(not child.playing and child.stream == null, child.name + " releases playback and stream on shutdown")
	sound.queue_free()
	await create_timer(0.1).timeout
	print("GRIP_VOLUME_VARIATION_RESULT checks=", checks, " failures=", failures.size())
	for failure: String in failures:
		print("FAILED: ", failure)
	quit(0 if failures.is_empty() else 1)

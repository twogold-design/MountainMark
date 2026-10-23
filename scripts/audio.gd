extends Node
## Original, locally synthesized soundscape. Never writes runtime data.

var _wind: AudioStreamPlayer
var _air: AudioStreamPlayer
var _breath: AudioStreamPlayer
var _voice: AudioStreamPlayer
var _recovery: AudioStreamPlayer
var _grip_touch: AudioStreamPlayer
var _music: AudioStreamPlayer
var _route_bed: AudioStreamPlayer
var _route_theme: int = 0
var _wind_strength: float = 0.0
var _wind_smoothed: float = 0.0
var _grip_duck: float = 0.0
var _theme_streams: Array[AudioStreamWAV] = []
var _effects: Array[AudioStreamPlayer] = []
var _clips: Dictionary = {}
var _effect_index: int = 0
var _altitude: float = 0.0
var _muted: bool = false
var _started: bool = false
var _summit: bool = false
var _breath_timer: float = 9.0
var _grip_count: int = 0
const FAR_REACH_RATIO: float = 0.72
const FATIGUE_ENTER: float = 35.0
const FATIGUE_EXIT: float = 42.0
var _climbing_active: bool = false
var _resting: bool = false
var _stamina: float = 100.0
var _fatigued: bool = false
var _voice_clip: String = ""
var _voice_lock: float = 0.0
var _exertion_cooldown: float = 0.0
var _voice_rng: RandomNumberGenerator = RandomNumberGenerator.new()
const GRIP_CLIPS: Array[String] = ["grip_1", "grip_2", "grip_3", "grip_4", "grip_5", "grip_6"]
var _grip_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _grip_bag: Array[int] = []
var _last_grip_sample: int = -1

func _ready() -> void:
	_voice_rng.randomize()
	_grip_rng.randomize()
	var clip_names: Array[String] = ["wind", "air", "breath", "grip", "chalk", "fall", "checkpoint", "summit", "effort_1", "effort_2", "pant", "recovery"]
	clip_names.append_array(GRIP_CLIPS)
	for clip_name: String in clip_names:
		var stream: AudioStreamWAV = load("res://assets/audio/" + clip_name + ".wav") as AudioStreamWAV
		if stream != null:
			if clip_name == "wind" or clip_name == "air":
				stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
				stream.loop_begin = 0
				stream.loop_end = int(stream.data.size() / 2)
			_clips[clip_name] = stream
	_wind = _make_player("Wind", -18.0)
	_air = _make_player("DistantAir", -23.0)
	_breath = _make_player("Breathing", -16.0)
	_voice = _make_player("ClimberVoice", -11.0)
	_recovery = _make_player("RestReward", -13.0)
	_grip_touch = _make_player("GripContact", -11.0)
	_music = _make_player("SummitMusic", -12.0)
	_route_bed = _make_player("RouteNature", -28.0)
	for theme in range(3):
		_theme_streams.append(_make_nature_loop(theme))
	set_route_theme(_route_theme)
	for idx: int in range(5):
		_effects.append(_make_player("Touch%d" % idx, -9.0))

func _make_player(label: String, gain: float) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = label
	player.volume_db = gain
	add_child(player)
	return player

func _process(delta: float) -> void:
	if not _started:
		return
	_grip_duck = maxf(0.0, _grip_duck - delta)
	_voice_lock = maxf(0.0, _voice_lock - delta)
	_exertion_cooldown = maxf(0.0, _exertion_cooldown - delta)
	_wind_smoothed = move_toward(_wind_smoothed, _wind_strength, delta * 1.8)
	var theme_gain: float = [-2.5, -5.0, 0.0][_route_theme]
	var wind_gain: float = -21.0 + _altitude * 3.0 + theme_gain + _wind_smoothed * 7.0
	var duck_db: float = 5.0 if _grip_duck > 0.0 else 0.0
	wind_gain -= duck_db
	var air_gain: float = -27.0 + _altitude * 4.0 - duck_db
	var bed_gain: float = [-27.0, -23.0, -29.0][_route_theme] - duck_db
	_route_bed.volume_db = lerpf(_route_bed.volume_db, -80.0 if _muted else bed_gain - (9.0 if _summit else 0.0), minf(delta * 3.0, 1.0))
	_wind.pitch_scale = lerpf(_wind.pitch_scale, [0.86, 0.75, 1.05][_route_theme] + _wind_smoothed * 0.16, minf(delta * 1.5, 1.0))
	if _summit:
		wind_gain -= 5.0
		air_gain -= 10.0
	_wind.volume_db = lerpf(_wind.volume_db, -80.0 if _muted else wind_gain, minf(delta * 2.0, 1.0))
	_air.volume_db = lerpf(_air.volume_db, -80.0 if _muted else air_gain, minf(delta, 1.0))
	if not _climbing_active or _resting or _summit or _muted:
		return
	_breath_timer -= delta
	if _breath_timer <= 0.0 and not _voice.playing and not _breath.playing and _voice_lock <= 0.0:
		if _fatigued:
			var urgency: float = 1.0 - clampf(_stamina / FATIGUE_ENTER, 0.0, 1.0)
			_voice.pitch_scale = lerpf(0.96, 1.10, urgency) * _voice_rng.randf_range(0.98, 1.02)
			_voice_clip = "pant"
			_play_on(_voice, "pant", lerpf(-15.0, -9.5, urgency))
			_breath_timer = lerpf(3.5, 1.9, urgency) + _voice_rng.randf_range(-0.12, 0.12)
			_grip_duck = maxf(_grip_duck, 0.7)
		else:
			_breath_timer = _voice_rng.randf_range(10.0, 17.0)
			if _grip_count > 0:
				_play_on(_breath, "breath", -19.0)
				_grip_count = 0

func set_climbing_state(stamina: float, active: bool, resting: bool) -> void:
	_stamina = clampf(stamina, 0.0, 100.0)
	_climbing_active = active
	_resting = resting and active
	if not active or _resting:
		_fatigued = false
		_breath_timer = 9.0
		_stop_voice()
		if not active:
			_recovery.stop()
			# Let the last catch finish underneath the summit music, even when a
			# long frame resolves contact and summit arrival in the same update.
			if not _summit:
				stop_grip()
		return
	var was_fatigued: bool = _fatigued
	if _stamina < FATIGUE_ENTER:
		_fatigued = true
	elif _stamina >= FATIGUE_EXIT:
		_fatigued = false
	if _fatigued and not was_fatigued:
		_breath.stop()
		_breath_timer = minf(_breath_timer, 0.25)
	elif was_fatigued and not _fatigued:
		if _voice_clip == "pant":
			_voice.stop()
		_breath_timer = 9.0

func _stop_voice() -> void:
	_breath.stop()
	_voice.stop()
	_voice_clip = ""
	_voice_lock = 0.0
	_exertion_cooldown = 0.0

func play_exertion(distance: float, reach_limit: float, move_duration: float) -> void:
	if not _started or not _climbing_active or _resting or _summit or _muted or _exertion_cooldown > 0.0:
		return
	var reach_ratio: float = maxf(0.0, distance) / maxf(0.01, reach_limit)
	if reach_ratio < FAR_REACH_RATIO:
		return
	var intensity: float = clampf(inverse_lerp(FAR_REACH_RATIO, 1.0, reach_ratio), 0.0, 1.0)
	_breath.stop()
	_voice.stop()
	_voice_clip = "effort_%d" % _voice_rng.randi_range(1, 2)
	_voice.pitch_scale = _voice_rng.randf_range(0.96, 1.04)
	_play_on(_voice, _voice_clip, lerpf(-13.0, -8.5, intensity))
	_exertion_cooldown = 0.85
	_voice_lock = maxf(0.85, move_duration * 0.55)
	_breath_timer = maxf(_breath_timer, _voice_lock + 0.25)
	_grip_duck = maxf(_grip_duck, 0.65)

func play_recovery(checkpoint: bool = false) -> void:
	if not _started or not _climbing_active or _summit or _muted:
		return
	_stop_voice()
	_grip_count = 0
	_play_on(_recovery, "checkpoint" if checkpoint else "recovery", -14.0 if checkpoint else -12.5)
	_grip_duck = maxf(_grip_duck, 1.1)

func _play_on(player: AudioStreamPlayer, clip: String, gain: float) -> void:
	if _muted or not _clips.has(clip):
		return
	player.volume_db = gain
	player.stream = _clips[clip] as AudioStream
	player.play()

func _effect(clip: String, gain: float, varied: bool = false) -> void:
	if _effects.is_empty():
		return
	var player: AudioStreamPlayer = _effects[_effect_index % _effects.size()]
	_effect_index += 1
	player.pitch_scale = randf_range(0.91, 1.1) if varied else 1.0
	_play_on(player, clip, gain)

func start_ambience() -> void:
	if _started:
		return
	_started = true
	_wind.stream = _clips.get("wind") as AudioStream
	_air.stream = _clips.get("air") as AudioStream
	_wind.volume_db = -80.0
	_air.volume_db = -80.0
	_wind.play()
	_air.play()
	_route_bed.play()

func set_route_theme(index: int) -> void:
	_route_theme = clampi(index, 0, 2)
	if _route_bed == null:
		return
	_route_bed.stop()
	_route_bed.stream = _theme_streams[_route_theme]
	_air.pitch_scale = [1.12, 0.74, 0.93][_route_theme]
	_music.pitch_scale = [1.0, 0.94, 1.06][_route_theme]
	if _started:
		_route_bed.play()

func set_wind_strength(value: float) -> void:
	# Caller can supply forecast strength before the balance penalty peaks.
	_wind_strength = clampf(value, 0.0, 1.0)

func _make_nature_loop(theme: int) -> AudioStreamWAV:
	# Original deterministic synthesis; no downloads or runtime file writes.
	# Forest: soft foliage and spaced bird calls. Canyon: a filtered water bed.
	# Summit route: distant tonal air, with the main wind voice carrying gusts.
	const RATE: int = 22050
	const SECONDS: int = 8
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(RATE * SECONDS * 2)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 82731 + theme * 103
	var low: float = 0.0
	var slow: float = 0.0
	for sample_index in range(RATE * SECONDS):
		var t: float = float(sample_index) / float(RATE)
		var white: float = rng.randf_range(-1.0, 1.0)
		low = lerpf(low, white, 0.085)
		slow = lerpf(slow, white, 0.006)
		var value: float = 0.0
		if theme == 0:
			value = low * (0.18 + sin(TAU * t / 8.0) * 0.045)
			for call_start in [1.2, 4.6, 5.05]:
				var ct: float = t - float(call_start)
				if ct >= 0.0 and ct < 0.22:
					var envelope: float = pow(sin(PI * ct / 0.22), 2.0)
					value += sin(TAU * (2050.0 * ct + 1600.0 * ct * ct)) * envelope * 0.10
		elif theme == 1:
			value = low * 0.62 + slow * 0.18 + white * 0.035
			value *= 0.82 + 0.18 * sin(TAU * t / 4.0)
		else:
			value = slow * 0.48 + low * 0.12
			value += sin(TAU * 146.0 * t) * 0.009 + sin(TAU * 219.0 * t) * 0.006
		# Short seam fade avoids noise discontinuities at loop boundaries.
		value *= minf(1.0, minf(t, float(SECONDS) - t) / 0.055)
		bytes.encode_s16(sample_index * 2, int(clampf(value, -1.0, 1.0) * 32767.0))
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = RATE * SECONDS
	return stream

func set_altitude(progress: float) -> void:
	_altitude = clampf(progress, 0.0, 1.0)

func play_grip(kind: String = "normal") -> void:
	if not _started or _muted or not _climbing_active or _summit:
		return
	if _grip_bag.is_empty():
		for index in range(GRIP_CLIPS.size()):
			_grip_bag.append(index)
		for index in range(_grip_bag.size() - 1, 0, -1):
			var other: int = _grip_rng.randi_range(0, index)
			var saved: int = _grip_bag[index]
			_grip_bag[index] = _grip_bag[other]
			_grip_bag[other] = saved
		if _grip_bag.back() == _last_grip_sample:
			var saved: int = _grip_bag[0]
			_grip_bag[0] = _grip_bag[-1]
			_grip_bag[-1] = saved
	var sample_index: int = _grip_bag.back()
	if not _clips.has(GRIP_CLIPS[sample_index]):
		return
	_grip_bag.pop_back()
	_last_grip_sample = sample_index
	var surface_pitch: float = 1.06 if kind == "small" else (0.94 if kind == "wet" else 1.0)
	_grip_touch.pitch_scale = surface_pitch * _grip_rng.randf_range(0.96, 1.04)
	var gain: float = (-12.5 if kind in ["wet", "small"] else -11.0) + _grip_rng.randf_range(-0.8, 0.8)
	_play_on(_grip_touch, GRIP_CLIPS[sample_index], gain)
	_grip_duck = maxf(_grip_duck, 0.36)
	_grip_count += 1

func stop_grip() -> void:
	_grip_touch.stop()

func play_chalk() -> void:
	_effect("chalk", -10.0, true)

func play_fall() -> void:
	set_climbing_state(_stamina, false, false)
	_effect("fall", -10.0)

func play_checkpoint() -> void:
	_effect("checkpoint", -15.0)

func play_summit() -> void:
	_summit = true
	set_climbing_state(_stamina, false, false)
	_play_on(_music, "summit", -10.0)

func set_muted(muted: bool) -> void:
	_muted = muted
	if muted:
		_wind.volume_db = -80.0
		_air.volume_db = -80.0
		_route_bed.volume_db = -80.0
		_stop_voice()
		stop_grip()
		_breath_timer = maxf(_breath_timer, 2.0)
		_recovery.stop()
		_music.stop()
		for player: AudioStreamPlayer in _effects:
			player.stop()

func _exit_tree() -> void:
	shutdown()

func shutdown() -> void:
	_started = false
	_climbing_active = false
	# Looping streams retain their playback; explicitly release before shutdown.
	for child: Node in get_children():
		if child is AudioStreamPlayer:
			var player: AudioStreamPlayer = child as AudioStreamPlayer
			player.stop()
			player.stream = null
	_effects.clear()
	_clips.clear()
	_theme_streams.clear()

func reset_ascent() -> void:
	stop_grip()
	set_climbing_state(100.0, false, false)
	_summit = false
	_wind_strength = 0.0
	_wind_smoothed = 0.0
	_grip_duck = 0.0
	_grip_count = 0
	_breath_timer = 9.0
	_music.stop()
	_breath.stop()


extends Node
## Original, locally synthesized soundscape. Never writes runtime data.

var _wind: AudioStreamPlayer
var _air: AudioStreamPlayer
var _breath: AudioStreamPlayer
var _music: AudioStreamPlayer
var _effects: Array[AudioStreamPlayer] = []
var _clips: Dictionary = {}
var _effect_index: int = 0
var _altitude: float = 0.0
var _muted: bool = false
var _started: bool = false
var _summit: bool = false
var _breath_timer: float = 9.0
var _grip_count: int = 0

func _ready() -> void:
	for clip_name: String in ["wind", "air", "breath", "grip", "chalk", "fall", "checkpoint", "summit"]:
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
	_music = _make_player("SummitMusic", -12.0)
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
	var wind_gain: float = -19.0 + _altitude * 4.0
	var air_gain: float = -25.0 + _altitude * 5.0
	if _summit:
		wind_gain -= 5.0
		air_gain -= 10.0
	_wind.volume_db = lerpf(_wind.volume_db, -80.0 if _muted else wind_gain, minf(delta * 2.0, 1.0))
	_air.volume_db = lerpf(_air.volume_db, -80.0 if _muted else air_gain, minf(delta, 1.0))
	_breath_timer -= delta
	if _breath_timer <= 0.0 and not _summit:
		_breath_timer = randf_range(10.0, 17.0)
		if _grip_count > 0:
			_play_on(_breath, "breath", -17.0)
			_grip_count = 0

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

func set_altitude(progress: float) -> void:
	_altitude = clampf(progress, 0.0, 1.0)

func play_grip() -> void:
	_grip_count += 1
	_effect("grip", -8.0, true)

func play_chalk() -> void:
	_effect("chalk", -10.0, true)

func play_fall() -> void:
	_effect("fall", -10.0)

func play_checkpoint() -> void:
	_effect("checkpoint", -15.0)

func play_summit() -> void:
	_summit = true
	_breath.stop()
	_play_on(_music, "summit", -10.0)

func set_muted(muted: bool) -> void:
	_muted = muted
	if muted:
		_wind.volume_db = -80.0
		_air.volume_db = -80.0
		_breath.stop()
		_music.stop()
		for player: AudioStreamPlayer in _effects:
			player.stop()

func _exit_tree() -> void:
	shutdown()

func shutdown() -> void:
	_started = false
	# Looping streams retain their playback; explicitly release before shutdown.
	for child: Node in get_children():
		if child is AudioStreamPlayer:
			var player: AudioStreamPlayer = child as AudioStreamPlayer
			player.stop()
			player.stream = null
	_effects.clear()
	_clips.clear()

func reset_ascent() -> void:
	_summit = false
	_grip_count = 0
	_breath_timer = 9.0
	_music.stop()
	_breath.stop()


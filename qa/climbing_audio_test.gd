extends SceneTree
## Player feedback regression: real audio players, real climb events, isolated saves.

class RecordingAudio extends "res://scripts/audio.gd":
	var events: Array[Dictionary] = []
	func _play_on(player: AudioStreamPlayer, clip: String, gain: float) -> void:
		super._play_on(player, clip, gain)
		if not _muted and _clips.has(clip) and player.playing:
			events.append({"clip": clip, "voice": player == get("_voice"), "gain": gain})

var checks: int = 0
var failures: Array[String] = []
var game: Node3D
var audio: Node
var player_path: String
var player_exists: bool
var player_bytes: PackedByteArray

func _initialize() -> void:
	call_deferred("_run")

func verify(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		print("FAIL ", message)

func voice_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in audio.events:
		if bool(event.voice):
			result.append(event)
	return result

func voice() -> AudioStreamPlayer:
	return audio.get("_voice") as AudioStreamPlayer

func played(clip: String) -> bool:
	for event: Dictionary in audio.events:
		if str(event.clip) == clip:
			return true
	return false

func reset_audio(stamina: float = 100.0, resting: bool = false) -> void:
	audio.reset_ascent()
	audio.set_muted(false)
	audio.set_climbing_state(stamina, true, resting)
	audio.events.clear()

func breathing_for(stamina: float, seconds: float) -> int:
	reset_audio(stamina)
	for step in range(ceili(seconds / 0.1)):
		# Advance game time without waiting for the sound card's real-time playback.
		# Finishing the prior clip allows measuring the scheduler, not clip overlap.
		voice().stop()
		audio._process(0.1)
	return voice_events().size()

func check_audio_contract() -> void:
	reset_audio()
	audio._process(30.0)
	verify(voice_events().is_empty(), "Healthy climbing does not randomly play tired breathing")
	audio.play_exertion(1.0, 2.815, 1.6)
	verify(voice_events().is_empty(), "A nearby hold does not trigger a far-reach effort voice")
	audio.play_exertion(2.30, 2.815, 1.6)
	verify(voice_events().size() == 1 and voice().playing, "A far reachable hold plays one effort voice")
	var effort_stream: AudioStream = voice().stream
	audio.set_climbing_state(12.0, true, false)
	audio._process(0.1)
	verify(voice_events().size() == 1 and voice().stream == effort_stream, "Fatigue cannot interrupt the active exertion voice")
	var moderate_count: int = breathing_for(31.0, 30.0)
	var exhausted_count: int = breathing_for(10.0, 30.0)
	verify(moderate_count >= 3, "Low stamina produces recurring breathing")
	verify(exhausted_count > moderate_count, "Lower stamina produces more frequent breathing")
	reset_audio(31.0)
	for step in range(60):
		voice().stop()
		audio._process(0.1)
	verify(not voice_events().is_empty(), "Crossing the tired threshold starts panting")
	audio.events.clear()
	audio.set_climbing_state(38.0, true, false)
	for step in range(60):
		voice().stop()
		audio._process(0.1)
	verify(not voice_events().is_empty(), "Small stamina fluctuations do not repeatedly switch breathing off")
	audio.set_climbing_state(45.0, true, false)
	verify(not voice().playing, "Recovered stamina stops the tired voice promptly")
	audio.events.clear()
	audio._process(10.0)
	verify(voice_events().is_empty(), "Recovered stamina does not restart panting")
	reset_audio(10.0)
	audio.play_exertion(2.3, 2.815, 1.6)
	audio.set_climbing_state(10.0, true, true)
	verify(not voice().playing, "Resting on a platform immediately releases the urgent voice")
	audio.events.clear()
	audio._process(10.0)
	verify(voice_events().is_empty(), "A platform suppresses tired panting while stamina recovers")
	audio.play_recovery(false)
	verify(not audio.events.is_empty(), "A rest landing has audible positive feedback")
	for inactive in [false, true]:
		reset_audio(10.0)
		audio.play_exertion(2.3, 2.815, 1.6)
		if inactive:
			audio.set_muted(true)
		else:
			audio.set_climbing_state(10.0, false, false)
		verify(not voice().playing, "Mute/inactive state releases active exertion")
		audio.events.clear()
		audio._process(10.0)
		audio.play_exertion(2.3, 2.815, 1.6)
		audio.play_recovery()
		verify(voice_events().is_empty(), "Mute/inactive state cannot leak a pending vocal cue")
	reset_audio(10.0)
	audio.play_exertion(2.3, 2.815, 1.6)
	audio.play_summit()
	verify(not voice().playing, "Summit releases the climbing voice")
	audio.events.clear()
	audio._process(10.0)
	verify(voice_events().is_empty(), "Summit does not resume low-stamina panting")
	reset_audio(10.0)
	audio.play_exertion(2.3, 2.815, 1.6)
	audio.reset_ascent()
	verify(not voice().playing, "A new ascent cannot retain the previous voice")
	print("AUDIO_CADENCE moderate=", moderate_count, " exhausted=", exhausted_count)

func freeze_game() -> void:
	game.set_process(false)
	game.climber.set_process(false)
	game.world.set_process(false)
	audio.set_process(false)

func begin_game() -> void:
	game.mode = "menu"
	game.route_index = 0
	game.play_style = "journey"
	game.save_data = {}
	game.start_climb(false)
	freeze_game()
	game._process(0.0)
	audio.events.clear()

func tick(dt: float, axis: float = 0.0) -> void:
	game.clock_time += dt
	game._tick_control(dt, axis)
	game.climber._process(dt)
	game._process(0.0)
	audio._process(dt)

func start_move(id: int, hand: int) -> bool:
	game.select_support(int(game._hold(id).get("support", -1)))
	var stance: float = game.balance_target_for_hold(id, hand)
	for step in range(200):
		if absf(game.balance - stance) < 0.025:
			break
		tick(0.01, clampf((stance - game.balance) * 14.0, -1.0, 1.0))
	game._update_reachable()
	game._update_camera(1.0)
	game.attempt_hold(id, hand)
	if not game.grip_active:
		return false
	for step in range(440):
		tick(0.01, clampf((game.balance_target - game.balance) * 14.0, -1.0, 1.0))
		if game.grip_active:
			var aim: Dictionary = game.get_drag_aim_info()
			game.set_grip_drag(Vector2(aim.drag_anchor) - (Vector2(aim.target_screen) - Vector2(aim.origin_screen)) / game.DRAG_AMPLIFICATION)
		if game.grip_ready() and game.grip_quality() >= 0.90:
			game._release_grip(hand)
			return game.climber.moving
	return false

func stop_case(label: String) -> void:
	begin_game()
	game.current_rest = false
	game.climber.stamina = 20.0
	game._process(0.0)
	audio.play_exertion(2.3, 2.815, 1.6)
	verify(voice().playing, label + " precondition: a voice is playing")
	match label:
		"pause": game.toggle_pause()
		"help": game.toggle_help()
		"fall": game._on_fell("qa feedback lifecycle")
		"menu": game.return_menu()
		"mute": game.toggle_audio()
	game._process(0.0)
	verify(not voice().playing, label + " stops the voice through the real game control")
	audio.events.clear()
	audio._process(8.0)
	verify(voice_events().is_empty(), label + " does not resume panting in the background")
	if label == "help":
		game.toggle_help()
	if label == "mute":
		game.toggle_audio()

func check_game_integration() -> void:
	begin_game()
	var target: int = int(game.reachable[0])
	var hand: int = game.recommended_hand(target)
	verify(start_move(target, hand), "Actual grip preparation and release starts a route move")
	verify(voice_events().is_empty(), "Effort voice waits for planted feet instead of playing at button release")
	var final_info: Dictionary = game.hold_reach_info(target, hand)
	var is_far: bool = float(final_info.distance) / float(final_info.max_distance) >= 0.72
	while game.climber.moving:
		tick(0.01)
	verify(voice_events().size() == (1 if is_far else 0), "Real movement emits exactly one distance-appropriate effort cue")
	verify(game.climber.current_hold_id == target, "Feedback preserves completion of the climb")
	# Continue the authored route until a platform, using actual grip timing and stamina.
	for route_step in range(12):
		if game.current_rest:
			break
		game._update_reachable()
		target = int(game.reachable[0])
		hand = game.recommended_hand(target)
		verify(start_move(target, hand), "Route step toward first rest platform")
		audio.events.clear()
		while game.climber.moving:
			tick(0.01)
	verify(game.current_rest and game.climber.current_hold_id > 0, "Actual route arrival reaches a rest platform")
	verify(game.rest_feedback_time > 0.0, "Platform arrival activates visible positive feedback")
	var landing_events: int = audio.events.size()
	verify(played("recovery"), "Ordinary platform arrival emits its positive recovery sound")
	var before: float = game.climber.stamina
	for frame in range(60):
		game._process(1.0 / 60.0)
		audio._process(1.0 / 60.0)
	verify(game.climber.stamina > before, "Rest feedback accompanies real stamina recovery")
	verify(audio.events.size() == landing_events, "Standing on a platform does not repeat the landing cue every frame")
	verify(audio._recovery.playing, "Frame-by-frame resting state does not truncate positive recovery audio")
	# Reach the authored shortcut rather than manufacturing a long move fixture.
	var covered_far: bool = false
	for route_step in range(16):
		game._update_reachable()
		if game.reachable.is_empty():
			break
		target = int(game.reachable[0])
		for candidate: int in game.reachable:
			if str(game._hold(candidate).branch) == "shortcut":
				target = candidate
		hand = game.recommended_hand(target)
		var moved: bool = start_move(target, hand)
		verify(moved, "Real route preparation toward the long shortcut")
		if not moved:
			break
		var reach: Dictionary = game.hold_reach_info(target, hand)
		var far: bool = float(reach.distance) / float(reach.max_distance) >= 0.72
		audio.events.clear()
		while game.climber.moving:
			tick(0.01)
		if far:
			verify(voice_events().size() == 1, "Authored far reach plays exactly one exertion cue during its action")
			covered_far = true
			break
		if game.current_rest:
			game._process(2.0)
	verify(covered_far, "Real integration includes an authored far hold, not only short normal moves")
	# Event boundaries verify priority and duplicate suppression independently of routing.
	for checkpoint_feedback in [false, true]:
		begin_game()
		var feedback_id: int = -1
		for hold: Dictionary in game.world.holds:
			if int(hold.id) <= 0 or int(hold.id) >= game.world.holds.size() - 1:
				continue
			if bool(hold.rest) and ((checkpoint_feedback and bool(hold.checkpoint)) or (not checkpoint_feedback and not str(hold.collectible).is_empty())):
				feedback_id = int(hold.id)
				break
		verify(feedback_id >= 0, "Authored route contains the positive-feedback priority fixture")
		if feedback_id < 0:
			continue
		# A chapter banner is separate from the rest-versus-discovery priority under test.
		game.chapter = 4
		game._on_reached(feedback_id)
		verify(game.rest_feedback_time > 0.0, "Checkpoint/discovery keeps its independent positive grip-meter feedback")
		verify(game.toast.contains("安全锚点" if checkpoint_feedback else "发现山路记录"), "Rest encouragement preserves checkpoint/discovery message priority")
		verify(played("checkpoint" if checkpoint_feedback else "recovery"), "Checkpoint/discovery selects one appropriate landing sound")
		var event_count: int = audio.events.size()
		game._on_reached(feedback_id)
		verify(audio.events.size() == event_count, "Duplicate arrival notification does not replay platform feedback")
	for label in ["pause", "help", "fall", "menu", "mute"]:
		stop_case(label)

func _run() -> void:
	verify("--qa-capture" in OS.get_cmdline_user_args(), "Run with --qa-capture so no player progress is saved")
	if not failures.is_empty():
		quit(1)
		return
	player_path = ProjectSettings.globalize_path("res://.runtime/save.json")
	player_exists = FileAccess.file_exists(player_path)
	if player_exists:
		player_bytes = FileAccess.get_file_as_bytes(player_path)
	var packed: PackedScene = load("res://scenes/main.tscn")
	game = packed.instantiate()
	root.add_child(game)
	game.sound.shutdown()
	game.sound.free()
	audio = RecordingAudio.new()
	game.add_child(audio)
	game.sound = audio
	audio.start_ambience()
	freeze_game()
	var has_feedback: bool = false
	for property: Dictionary in game.get_property_list():
		if str(property.name) == "rest_feedback_time":
			has_feedback = true
	verify(has_feedback, "Main scene exposes the completed rest-feedback integration")
	if not has_feedback:
		quit(1)
		return
	check_audio_contract()
	check_game_integration()
	var unchanged: bool = FileAccess.file_exists(player_path) == player_exists
	if player_exists:
		unchanged = unchanged and FileAccess.get_file_as_bytes(player_path) == player_bytes
	verify(unchanged, "Player save remains byte-for-byte unchanged")
	audio.shutdown()
	verify(not voice().playing and voice().stream == null, "Shutdown releases the voice stream")
	game.queue_free()
	await create_timer(0.1).timeout
	print("CLIMBING_AUDIO_RESULT checks=", checks, " failures=", failures.size())
	for failure: String in failures:
		print("FAILED: ", failure)
	quit(0 if failures.is_empty() else 1)

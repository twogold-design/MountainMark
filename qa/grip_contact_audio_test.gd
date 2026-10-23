extends SceneTree
## Contact-driven rock sounds: rendered palms, real controllers, and isolated saves.
const Actor = preload("res://scripts/climber.gd")
const START := Vector3(0.0, 2.5, 0.45)
const MOTIONS := [Vector3(0.45, 1.2, 0.0), Vector3(1.65, 0.6, 0.0), Vector3(0.3, 2.1, 0.0)]

class RecordingAudio extends "res://scripts/audio.gd":
	var events: Array[Dictionary] = []
	func _play_on(player: AudioStreamPlayer, clip: String, gain: float) -> void:
		super._play_on(player, clip, gain)
		if not _muted and _clips.has(clip) and player.playing:
			events.append({"clip": clip, "touch": player == get("_grip_touch"), "gain": gain})

var checks: int = 0
var failures: Array[String] = []
var actor: Node3D
var actor_events: Array[Dictionary] = []
var game: Node3D
var audio: Node
var contact_times: Dictionary = {}
var player_saves: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func verify(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures.append(detail)
		print("FAIL ", detail)

func _on_contact(id: int, hand: int, kind: String) -> void:
	actor_events.append({"type": "contact", "id": id, "hand": hand, "kind": kind,
		"time": actor._move_time, "p": actor._move_time / actor._move_duration,
		"error": actor._gloves[hand].position.distance_to(actor._new_hands[hand])})

func _on_arrival(id: int) -> void:
	actor_events.append({"type": "arrival", "id": id})

func begin_actor(delta: Vector3, hand: int, searching: bool, kind: String = "normal") -> bool:
	actor.setup({"id": 0, "position": START})
	actor.climbing = true
	actor.set_support_foot(1 - hand)
	actor_events.clear()
	if not actor.climb_to({"id": 1, "position": START + delta, "kind": kind}, hand, 4.0):
		return false
	# Both animation paths are intentional fixtures; sampling odds is tested elsewhere.
	actor._searching_move = searching
	return true

func check_actor_contacts() -> void:
	for fps in [30, 60, 120]:
		for motion in range(MOTIONS.size()):
			for hand in range(2):
				for searching in [false, true]:
					var kind: String = ["normal", "traverse", "small"][motion]
					var label: String = "%dfps / motion%d / hand%d / searching%s" % [fps, motion, hand, str(searching)]
					verify(begin_actor(MOTIONS[motion], hand, searching, kind), label + " starts")
					actor._process(0.20 * actor._move_duration / float(actor._step_count))
					verify(actor_events.is_empty(), label + " has no contact before foot placement")
					while actor.moving:
						actor._process(1.0 / float(fps))
					verify(actor_events.size() == 2, label + " emits one contact and one arrival")
					if actor_events.size() < 2:
						continue
					var contact: Dictionary = actor_events[0]
					verify(contact.type == "contact" and actor_events[1].type == "arrival", label + " contact precedes arrival")
					if contact.type != "contact":
						continue
					verify(int(contact.id) == 1 and int(contact.hand) == hand and str(contact.kind) == kind, label + " preserves hold, hand and rock kind")
					verify(float(contact.p) >= 0.5 and float(contact.p) <= 1.025, label + " waits until the movement's second half")
					verify(float(contact.error) <= 0.0121, label + " occurs within 12mm of rendered target contact")
					var timing_key: String = "%d_%d_%s" % [motion, hand, str(searching)]
					if contact_times.has(timing_key):
						verify(absf(float(contact_times[timing_key]) - float(contact.time)) <= 1.0 / 30.0 + 0.002, label + " stays within one frame across render rates")
					else:
						contact_times[timing_key] = float(contact.time)
					actor._process(1.0)
					verify(actor_events.size() == 2, label + " never repeats after arrival")
	verify(begin_actor(MOTIONS[0], 0, false, "wet"), "Large-step contact fixture starts")
	actor._process(actor._move_duration + 0.001)
	verify(actor_events.size() == 2 and actor_events[0].type == "contact" and actor_events[1].type == "arrival", "A slow frame still emits contact before arrival")
	if not actor_events.is_empty() and actor_events[0].has("error"):
		verify(float(actor_events[0].error) <= 0.0121, "Final-frame fallback uses the actual rendered palm")
	verify(begin_actor(MOTIONS[1], 1, true), "Cancellation fixture starts")
	actor._process(actor._move_duration * 0.3)
	actor.recover()
	actor_events.clear()
	actor._process(4.0)
	verify(actor_events.is_empty() and not actor.moving, "Recover cancels an unfinished contact without a delayed event")
	actor.stamina = 0.1
	verify(not actor.climb_to({"id": 1, "position": START + MOTIONS[0]}, 0, 8.0), "Insufficient stamina rejects an attempted move")
	actor._process(1.0)
	verify(actor_events.is_empty(), "A failed move produces no contact event")

func touch_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in audio.events:
		if bool(event.touch):
			result.append(event)
	return result

func touch_player() -> AudioStreamPlayer:
	return audio.get("_grip_touch") as AudioStreamPlayer

func begin_audio() -> void:
	audio.reset_ascent()
	audio.set_muted(false)
	audio.set_climbing_state(80.0, true, false)
	audio.events.clear()

func pcm_energy(stream: AudioStreamWAV, start: float, finish: float) -> float:
	var bytes_per_sample: int = 2 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1
	var samples: int = stream.data.size() / bytes_per_sample
	var from: int = clampi(int(float(samples) * start), 0, samples)
	var to: int = clampi(int(float(samples) * finish), from, samples)
	var energy: float = 0.0
	for sample in range(from, to):
		var value: float = float(stream.data.decode_s16(sample * 2)) / 32768.0 if bytes_per_sample == 2 else (float(stream.data[sample]) - 128.0) / 128.0
		energy += value * value
	return sqrt(energy / float(maxi(1, to - from)))

func source_pcm(clip: String) -> AudioStreamWAV:
	# WAV imports may use QOA; inspect the source waveform when the repository is
	# available. A release pack can legitimately contain only its imported stream.
	var path: String = "res://assets/audio/" + clip + ".wav"
	if not FileAccess.file_exists(path):
		return null
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var result := AudioStreamWAV.new()
	var bits: int = 0
	var offset: int = 12
	while offset + 8 <= bytes.size():
		var name: String = bytes.slice(offset, offset + 4).get_string_from_ascii()
		var size: int = bytes.decode_u32(offset + 4)
		var end: int = offset + 8 + size
		if end > bytes.size():
			return null
		if name == "fmt " and size >= 16:
			if bytes.decode_u16(offset + 8) != 1:
				return null
			result.stereo = bytes.decode_u16(offset + 10) == 2
			result.mix_rate = bytes.decode_u32(offset + 12)
			bits = bytes.decode_u16(offset + 22)
		elif name == "data":
			result.data = bytes.slice(offset + 8, end)
		offset = end + size % 2
	if bits not in [8, 16] or result.data.is_empty():
		return null
	result.format = AudioStreamWAV.FORMAT_16_BITS if bits == 16 else AudioStreamWAV.FORMAT_8_BITS
	return result

func check_samples_and_shuffle() -> void:
	begin_audio()
	var unique_data: Dictionary = {}
	for sample in range(1, 7):
		var clip: String = "grip_%d" % sample
		var stream: AudioStreamWAV = audio._clips.get(clip) as AudioStreamWAV
		verify(stream != null, clip + " imports as a playable WAV")
		if stream == null:
			continue
		verify(stream.get_length() >= 0.20 and stream.get_length() <= 1.0 and not stream.data.is_empty(), clip + " is a short nonempty contact clip")
		unique_data[hash(stream.data)] = true
		var waveform: AudioStreamWAV = stream
		if waveform.format != AudioStreamWAV.FORMAT_16_BITS and waveform.format != AudioStreamWAV.FORMAT_8_BITS:
			waveform = source_pcm(clip)
		if waveform != null:
			var body: float = pcm_energy(waveform, 0.0, 0.4)
			var tail: float = pcm_energy(waveform, 0.55, 0.9)
			verify(body > 0.005, clip + " has an audible initial touch and friction")
			verify(tail > 0.0002 and tail < body, clip + " retains a quieter non-silent granular tail")
			print("GRIP_WAVEFORM ", clip, " body_rms=", snappedf(body, 0.0001), " tail_rms=", snappedf(tail, 0.0001))
		else:
			print("GRIP_COMPRESSED_SAMPLE ", clip, " format=", stream.format, "; source waveform excluded from release pack")
	verify(unique_data.size() == 6, "All six contact samples have different audio data")
	audio._grip_rng.seed = 98121
	var seen: Dictionary = {}
	var previous: String = ""
	for attempt in range(48):
		audio.play_grip(["normal", "traverse", "small", "wet"][attempt % 4])
		var played: Array[Dictionary] = touch_events()
		verify(played.size() == attempt + 1, "Each contact starts one sample on its dedicated player")
		if played.is_empty():
			continue
		var clip: String = str(played.back().clip)
		verify(clip.begins_with("grip_") and clip != previous, "The shuffled contact library never repeats an adjacent sample")
		seen[clip] = true
		previous = clip
		if attempt % 6 == 5:
			verify(seen.size() == 6, "Each six-touch phrase uses the whole sample library")
			seen.clear()
	# A rock contact has its own lifetime; it must not steal exertion or rest voices.
	begin_audio()
	audio.play_recovery()
	audio.play_exertion(2.5, 2.815, 1.6)
	var voice_stream: AudioStream = audio._voice.stream
	var recovery_stream: AudioStream = audio._recovery.stream
	verify(audio._voice.playing and audio._recovery.playing, "Independent voice-channel fixture is audible")
	audio.play_grip("wet")
	verify(audio._voice.playing and audio._voice.stream == voice_stream and audio._recovery.playing and audio._recovery.stream == recovery_stream, "Rock contact leaves voice and recovery playback running")
	audio.stop_grip()
	verify(not touch_player().playing and audio._voice.playing and audio._recovery.playing, "Stopping contact clears only the contact channel")
	for gate in ["mute", "inactive", "reset"]:
		begin_audio()
		audio.play_grip()
		verify(touch_player().playing, gate + " fixture begins with a contact sample")
		match gate:
			"mute": audio.set_muted(true)
			"inactive": audio.set_climbing_state(80.0, false, false)
			"reset": audio.reset_ascent()
		verify(not touch_player().playing, gate + " stops the current contact tail")
		audio.events.clear()
		audio.play_grip()
		verify(touch_events().is_empty(), gate + " prevents a new contact sample")
		audio.set_muted(false)
		audio.set_climbing_state(80.0, true, false)
		audio._process(2.0)
		verify(touch_events().is_empty(), gate + " does not replay a suppressed contact on return")

func freeze() -> void:
	game.set_process(false)
	game.climber.set_process(false)
	game.world.set_process(false)
	audio.set_process(false)

func begin_game() -> void:
	game.mode = "menu"
	game.route_index = 0
	game.play_style = "journey"
	game.save_data = {}
	game.help_open = false
	game.muted = false
	audio.set_muted(false)
	game.start_climb(false)
	freeze()
	game._process(0.0)
	audio.events.clear()

func tick(dt: float, axis: float = 0.0) -> void:
	game.clock_time += dt
	game._tick_control(dt, axis)
	game.climber._process(dt)
	game._process(0.0)
	audio._process(dt)

func start_real_move(id: int, hand: int) -> bool:
	game.select_support(int(game._hold(id).get("support", -1)))
	var stance: float = game.balance_target_for_hold(id, hand)
	for step in range(200):
		if absf(game.balance - stance) < 0.025:
			break
		tick(0.01, clampf((stance - game.balance) * 14.0, -1.0, 1.0))
	game._update_reachable()
	game.attempt_hold(id, hand)
	if not game.grip_active:
		return false
	for step in range(440):
		tick(0.01, clampf((game.balance_target - game.balance) * 14.0, -1.0, 1.0))
		var power_error: float = absf(game.grip_power - game.grip_target) / game.grip_window
		var weight_error: float = absf(game.balance - game.balance_target) / game.balance_window
		if game.grip_ready() and 1.0 - power_error * 0.55 - weight_error * 0.45 >= 0.90:
			game._release_grip(hand)
			return game.climber.moving
	return false

func check_real_game() -> void:
	begin_game()
	var id: int = int(game.reachable[0])
	verify(start_real_move(id, 1), "Real grip preparation and release starts a movement")
	verify(touch_events().is_empty(), "Button release never plays the future rock contact")
	tick(0.2 * game.climber._move_duration)
	verify(touch_events().is_empty(), "Feet and early reaching remain free of a premature touch sound")
	while game.climber.moving:
		tick(1.0 / 60.0)
	verify(touch_events().size() == 1 and game.climber.current_hold_id == id, "Real rendered hand contact plays exactly one grip sample")
	for frame in range(20):
		tick(1.0 / 60.0)
	verify(touch_events().size() == 1, "No timer repeats the contact after reaching the hold")
	for stop in ["pause", "help", "mute", "fall", "menu"]:
		begin_game()
		audio.play_grip()
		verify(touch_player().playing, stop + " lifecycle fixture has an audible contact tail")
		match stop:
			"pause": game.toggle_pause()
			"help": game.toggle_help()
			"mute": game.toggle_audio()
			"fall": game._on_fell("QA tail cleanup")
			"menu": game.return_menu()
		verify(not touch_player().playing, stop + " stops the existing contact tail through the real game control")
	# The final reachable hold must make its contact before the summit transition.
	begin_game()
	var last_id: int = game.world.holds.size() - 1
	var before_id: int = -1
	for hold: Dictionary in game.world.holds:
		if last_id in hold.links:
			before_id = int(hold.id)
	verify(before_id >= 0, "Authored summit has a preceding hold")
	if before_id >= 0:
		game.climber.setup(game._hold(before_id))
		game.climber.climbing = true
		game.current_rest = bool(game._hold(before_id).rest)
		game._update_reachable()
		verify(start_real_move(last_id, game.recommended_hand(last_id)), "Real final grip starts from the authored penultimate hold")
		while game.climber.moving:
			tick(1.0 / 60.0)
		verify(touch_events().size() == 1 and game.mode == "summit", "Final rock contact is heard before summit feedback takes over")
		verify(touch_player().playing, "Summit transition preserves the final contact's short natural tail")
	# Suppress the contact at the exact event boundary, then restore without replay.
	for gate in ["pause", "help", "mute"]:
		begin_game()
		id = int(game.reachable[0])
		verify(start_real_move(id, 1), gate + " fixture has an unfinished real move")
		match gate:
			"pause": game.toggle_pause()
			"help": game.toggle_help()
			"mute": game.toggle_audio()
		# Direct advancement intentionally samples event delivery despite suspended processing.
		game.climber._process(game.climber._move_duration)
		verify(touch_events().is_empty(), gate + " does not play a contact delivered while hidden or muted")
		match gate:
			"pause": game.toggle_pause()
			"help": game.toggle_help()
			"mute": game.toggle_audio()
		game._process(0.0)
		audio._process(3.0)
		verify(touch_events().is_empty(), gate + " never queues the suppressed contact for resuming")
	for cancellation in ["recover", "fall", "menu"]:
		begin_game()
		id = int(game.reachable[0])
		verify(start_real_move(id, 1), cancellation + " cancellation fixture starts")
		tick(game.climber._move_duration * 0.25)
		match cancellation:
			"recover": game.climber.recover()
			"fall":
				game._on_fell("QA contact cancellation")
				game.fall_time = 0.7
				game.retry_after_fall()
			"menu": game.return_menu()
		game._process(0.0)
		game.climber._process(4.0)
		audio._process(4.0)
		verify(touch_events().is_empty(), cancellation + " discards the old move without late contact audio")
	# An immediate premature release fails before a reaching action can begin.
	begin_game()
	id = int(game.reachable[0])
	game.attempt_hold(id, 1)
	game._release_grip(1)
	tick(1.0)
	verify(not game.climber.moving and touch_events().is_empty(), "Failed grip timing cannot produce a successful rock contact sound")

func _run() -> void:
	verify("--qa-capture" in OS.get_cmdline_user_args(), "Test requires isolated --qa-capture mode")
	if not failures.is_empty():
		quit(1)
		return
	for path in ["res://.runtime/save.json", "res://build/.runtime/save.json"]:
		player_saves[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	actor = Actor.new()
	root.add_child(actor)
	actor.set_process(false)
	verify(actor.has_signal("hand_contact"), "Actor exposes the completed physical hand-contact event")
	if not actor.has_signal("hand_contact"):
		quit(1)
		return
	actor.hand_contact.connect(_on_contact)
	actor.reached_hold.connect(_on_arrival)
	check_actor_contacts()
	var packed: PackedScene = load("res://scenes/main.tscn")
	game = packed.instantiate()
	root.add_child(game)
	game.sound.shutdown()
	game.sound.free()
	audio = RecordingAudio.new()
	game.add_child(audio)
	game.sound = audio
	audio.start_ambience()
	freeze()
	verify(touch_player() != null and audio.has_method("stop_grip"), "Audio exposes the dedicated contact channel and cancellation")
	if touch_player() == null or not audio.has_method("stop_grip"):
		quit(1)
		return
	check_samples_and_shuffle()
	check_real_game()
	for path: String in player_saves:
		var bytes: Variant = player_saves[path]
		verify((not FileAccess.file_exists(path)) if bytes == null else (FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path) == bytes), path + " is unchanged")
	audio.shutdown()
	verify(not touch_player().playing and touch_player().stream == null, "Shutdown releases the contact stream")
	game.queue_free()
	actor.queue_free()
	await create_timer(0.1).timeout
	print("GRIP_CONTACT_AUDIO_RESULT checks=", checks, " failures=", failures.size())
	for failure: String in failures:
		print("FAILED: ", failure)
	quit(0 if failures.is_empty() else 1)

extends SceneTree
## Expedition regression: real grip timing, real stamina, environment time, isolated saves.
const ROUTES = preload("res://scripts/routes.gd")
var game: Node3D
var target_quality: float = 0.9
var checks: int = 0
var failures: Array[String] = []
var player_bytes: PackedByteArray
var player_exists: bool
var player_path: String
var saved_environment: String

func _initialize() -> void:
	call_deferred("_run")

func verify(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		print("FAIL ", message)

func graph_check(data: Dictionary, label: String) -> void:
	var holds: Array = data.holds
	var seen: Dictionary = {0: true}
	var todo: Array[int] = [0]
	while not todo.is_empty():
		var id: int = todo.pop_back()
		var links: Array = holds[id].links
		verify(not links.is_empty() or id == holds.size() - 1, label + " no dead end %d" % id)
		for next: int in links:
			verify(next >= 0 and next < holds.size(), label + " valid edge")
			if next < 0 or next >= holds.size():
				continue
			verify(Vector3(holds[id].position).distance_to(holds[next].position) <= 3.05, label + " edge reach %d to %d" % [id, next])
			verify(Vector3(holds[next].position).y > Vector3(holds[id].position).y, label + " forward progress")
			if not seen.has(next):
				seen[next] = true
				todo.append(next)
	verify(seen.size() == holds.size(), label + " all holds reachable")
	for branch in ["safe", "shortcut"]:
		var current: int = 0
		for i in range(holds.size()):
			if current == holds.size() - 1:
				break
			var links: Array = holds[current].links
			if links.is_empty():
				break
			var next: int = links[0]
			for candidate: int in links:
				if str(holds[candidate].branch) == branch:
					next = candidate
			current = next
		verify(current == holds.size() - 1, label + " complete " + branch + " path")

func freeze() -> void:
	game.set_process(false)
	game.climber.set_process(false)
	game.sound.set_process(false)
	game.world.set_process(false)

func begin(route: int, style: String = "journey", challenge: int = 0) -> void:
	game.mode = "menu"
	game.route_index = route
	game.play_style = style
	game.challenge_index = challenge
	game.start_climb(false)
	freeze()
	verify(game.mode == "playing", "Start %d %s %d" % [route, style, challenge])

func tick(dt: float, axis: float = 0.0) -> void:
	# Same environment rules as main._process, then the real controller and actor.
	game.clock_time += dt
	if game.mode == "playing":
		game.elapsed += dt
		game.chalk_protection = maxf(0.0, game.chalk_protection - dt)
		game.wind_strength = game.world.get_wind_strength()
		var kind: String = str(game._hold(game.climber.current_hold_id).get("kind", "normal"))
		game.climber.terrain_drain = 0.7 if kind == "small" else (1.1 if kind == "wet" and game.chalk_protection <= 0.0 else 0.0)
		if game.current_rest and not game.climber.moving and not game.grip_active:
			game.climber.rest(dt)
		game._tick_control(dt, axis)
		game.climber._process(dt)
		game.world.update_atmosphere(game.highest / game.route_height, dt)

func controller_axis() -> float:
	return clampf((game.balance_target - game.balance) * 14.0, -1.0, 1.0)

func prepare(id: int, hand: int) -> bool:
	game._update_camera(1.0)
	game.attempt_hold(id, hand)
	if not game.grip_active:
		return false
	for step in range(440):
		tick(0.01, controller_axis())
		if game.grip_active:
			var aim: Dictionary = game.get_drag_aim_info()
			game.set_grip_drag(Vector2(aim.drag_anchor) - (Vector2(aim.target_screen) - Vector2(aim.origin_screen)) / game.DRAG_AMPLIFICATION)
		if game.mode != "playing" or not game.grip_active:
			return false
		var quality: float = game.grip_quality()
		if game.grip_ready() and quality >= target_quality:
			return true
	return false

func move(id: int, hand: int) -> bool:
	game.select_support(int(game._hold(id).get("support", -1)))
	# Read the line and shift with real A/D input before spending grip-preparation time.
	# Weight now starts neutral after each move and changes actual shoulder reach.
	var stance: float = game.balance_target_for_hold(id, hand)
	for align_step in range(200):
		if absf(game.balance - stance) < 0.025:
			break
		tick(0.01, clampf((stance - game.balance) * 14.0, -1.0, 1.0))
	game._update_reachable()
	# Observe the real gust cycle before starting a wind-exposed move.
	if str(game._hold(id).kind) == "wind":
		for wait_step in range(1800):
			if game.world.get_wind_strength() < 0.40:
				break
			tick(0.01)
	if not prepare(id, hand):
		return false
	game._release_grip(hand)
	if not game.climber.moving:
		return false
	for step in range(450):
		tick(0.01)
		if not game.climber.moving:
			break
	game._update_reachable()
	return game.climber.current_hold_id == id

func full_ascent(branch: String) -> bool:
	var min_stamina: float = 100.0
	var minimum_quality: float = 1.0
	for step in range(250):
		if game.mode == "summit":
			print("ASCENT ", game.active_route.name, " ", game.play_style, " ", branch, " moves=", game.climber.total_moves, " time=", snappedf(game.elapsed, 0.1), " min_stamina=", snappedf(min_stamina, 0.1), " chalk=", game.chalk_used, " min_quality=", snappedf(minimum_quality, 0.01))
			return true
		if game.current_rest:
			for rest_step in range(200):
				if game.climber.stamina >= 99.0:
					break
				tick(0.05)
		game._update_reachable()
		if game.reachable.is_empty():
			print("NO_REACH ", game.climber.current_hold_id)
			return false
		var id: int = game.reachable[0]
		for candidate: int in game.reachable:
			if str(game._hold(candidate).branch) == branch:
				id = candidate
		if game.climber.stamina < 30.0 or (str(game._hold(id).kind) == "wet" and game.chalk_protection <= 0.0):
			game.use_chalk()
		var dx: float = Vector3(game._hold(id).position).x - game.climber.get_reach_origin().x
		var hand: int = (1 if dx > 0 else 0) if absf(dx) > 0.55 else (1 - game.last_hand)
		if game.climber.stamina < game.hold_effort(id, hand, 0.0) + 3.0 and game.chalk_charges > 0:
			for cooldown_step in range(700):
				if game.climber._chalk_cooldown <= 0.0 or game.mode != "playing":
					break
				tick(0.01)
			game.use_chalk()
		if not move(id, hand):
			print("MOVE_FAILURE route=", game.route_index, " branch=", branch, " from=", game.climber.current_hold_id, " to=", id, " stamina=", game.climber.stamina, " time=", game.elapsed, " mode=", game.mode, " slips=", game.slip_streak, " chalk=", game.chalk_charges, " reason=", game.toast)
			return false
		min_stamina = minf(min_stamina, game.climber.stamina)
		minimum_quality = minf(minimum_quality, game.last_quality)
	return false

func progress_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for key in ["version", "route", "checkpoint", "elapsed", "falls", "moves", "chalk_used", "run_collections", "in_progress"]:
		result[key] = game.save_data.get(key)
	return result.duplicate(true)

func _run() -> void:
	verify("--qa-capture" in OS.get_cmdline_user_args(), "Must run with --qa-capture")
	if not failures.is_empty():
		quit(1)
		return
	for route in range(3):
		for style in ["journey", "extreme"]:
			graph_check(ROUTES.build(route, style), "%d %s" % [route, style])
		graph_check(ROUTES.build(0, "challenge", route), "challenge %d" % route)
	player_path = ProjectSettings.globalize_path("res://.runtime/save.json")
	player_exists = FileAccess.file_exists(player_path)
	if player_exists:
		player_bytes = FileAccess.get_file_as_bytes(player_path)
	saved_environment = OS.get_environment("MOUNTAINMARK_DATA_DIR")
	OS.set_environment("MOUNTAINMARK_DATA_DIR", ProjectSettings.globalize_path("res://qa/expedition-v3-data"))
	var packed: PackedScene = load("res://scenes/main.tscn")
	game = packed.instantiate()
	root.add_child(game)
	freeze()
	game._save_path = ProjectSettings.globalize_path("res://qa/expedition-v3-save.json")
	game.save_data = {}
	verify(game.route_unlocked(0) and not game.route_unlocked(1) and not game.route_unlocked(2), "Fresh route unlock gating")
	verify(not game.extreme_unlocked(), "Fresh extreme locked")
	game.route_index = 1
	game.start_climb(false)
	verify(game.mode == "menu" and not game.climber.climbing, "Locked mountain cannot start")
	game.route_index = 0
	game.play_style = "extreme"
	game.start_climb(false)
	verify(game.mode == "menu" and not game.climber.climbing, "Locked extreme cannot start")
	game.play_style = "journey"
	for route in range(3):
		begin(route)
		var ok: bool = full_ascent("safe")
		verify(ok and game.falls == 0, "Real safe ascent route %d" % route)
		verify(game.save_data.get("records", {}).has("%s_journey" % ROUTES.IDS[route]), "Journey record route %d" % route)
		if not ok:
			game.save_data["completed_routes"] = {"0":true, "1":true, "2":true}
		verify(game.extreme_unlocked(), "Extreme unlock after route %d" % route)
		if route < 2:
			verify(game.route_unlocked(route + 1), "Next route unlock")
	for route in range(3):
		begin(route)
		verify(full_ascent("shortcut") and game.falls == 0, "Real shortcut ascent route %d" % route)
	verify(game.save_data.get("collections", {}).size() == 18, "All safe and shortcut collectibles")
	verify(game.save_data.get("badges", {}).has("山路熟客"), "Both branches award explorer badge")
	begin(0)
	# Preserve a live journey while challenges and extreme sessions update independent records.
	game.elapsed = 42.0
	game._save_progress()
	var live_journey: Dictionary = progress_snapshot()
	for challenge in range(3):
		begin(0, "challenge", challenge)
		if challenge == 1:
			verify(not game.use_chalk(), "Traverse challenge disallows chalk")
		verify(full_ascent("main") and game.falls == 0, "Real challenge complete %d" % challenge)
		verify(game.save_data.get("records", {}).has("challenge_%d" % challenge), "Challenge record %d" % challenge)
		verify(progress_snapshot() == live_journey, "Challenge cannot overwrite active journey %d" % challenge)
	for route in range(3):
		begin(route, "extreme")
		verify(game.chalk_charges == 2, "Extreme has two chalk charges")
		verify(full_ascent("safe"), "Real extreme safe ascent %d" % route)
		verify(progress_snapshot() == live_journey, "Extreme cannot overwrite journey")
		verify(game.save_data.get("records", {}).has("%s_extreme" % ROUTES.IDS[route]), "Extreme independent record")
	begin(2, "extreme")
	verify(full_ascent("shortcut"), "Real summit extreme shortcut ascent")
	verify(progress_snapshot() == live_journey, "Extreme shortcut cannot overwrite journey")
	target_quality = 0.65
	for style in ["journey", "extreme"]:
		begin(2, style)
		verify(full_ascent("shortcut"), "Cloud shortcut allows 0.65 quality " + style)
	target_quality = 0.9
	# Observation, pause and challenge retry follow their real input/state paths.
	begin(0)
	var origin: Vector3 = game.climber.get_reach_origin()
	var key_event: InputEventKey = InputEventKey.new()
	key_event.pressed = true
	key_event.keycode = KEY_W
	game._unhandled_input(key_event)
	verify(not game.climber.moving and not game.grip_active and game.climber.get_reach_origin().is_equal_approx(origin), "W observes without automatic climbing")
	verify(game.preview_id in game.reachable, "W highlights a legal next hold")
	game.attempt_hold(game.reachable[0], 1)
	verify(game.grip_active, "Grip active before pause")
	var paused_elapsed: float = game.elapsed
	var paused_stamina: float = game.climber.stamina
	key_event.keycode = KEY_ESCAPE
	game._unhandled_input(key_event)
	verify(game.mode == "paused" and not game.grip_active, "Esc cancels grip and pauses")
	game._process(2.0)
	game._release_grip(1)
	verify(game.elapsed == paused_elapsed and game.climber.stamina == paused_stamina and not game.climber.moving, "Pause freezes elapsed and rejects stale release")
	verify(game.climber.process_mode == Node.PROCESS_MODE_DISABLED, "Pause disables actor motion")
	game._unhandled_input(key_event)
	verify(game.mode == "playing" and game.climber.process_mode == Node.PROCESS_MODE_INHERIT, "Esc resumes the current climb")
	freeze()
	begin(0, "challenge", 2)
	verify(move(game.reachable[0], 1), "Challenge moves before fall")
	game._on_fell("主动返回")
	verify(game.mode == "fallen", "Challenge shows fall feedback")
	game.fall_time = 0.7
	game.retry_after_fall()
	freeze()
	verify(game.mode == "playing" and game.play_style == "challenge" and game.challenge_index == 2, "Retry preserves selected short challenge")
	verify(game.climber.current_hold_id == 0 and game.climber.total_moves == 0 and game.falls == 0 and game.world.holds.size() == 11, "Challenge retry restarts only short course")
	# Actual foot gating, then a successful retry with the correct selected foot.
	begin(0, "challenge", 1)
	var target: int = game.reachable[0]
	var required: int = int(game._hold(target).support)
	verify(required >= 0, "Traverse requires a support foot")
	game.select_support(1 - required)
	game.attempt_hold(target, 1)
	game._release_grip(1)
	verify(game.slip_streak == 1 and not game.climber.moving and game._last_grip_failure.contains("支撑脚"), "Wrong support rejected with specific feedback")
	tick(0.36)
	verify(move(target, 1), "Correct support allows traverse")
	# Cost and idle drain use identical position/hand/quality for before-after comparison.
	begin(0, "challenge", 2)
	target = game.reachable[0]
	game.chalk_protection = 0.0
	var wet_cost: float = game.hold_effort(target, 1, 1.0)
	verify(game.use_chalk(), "Wet challenge chalk usable")
	verify(is_equal_approx(wet_cost - game.hold_effort(target, 1, 1.0), 4.0), "Chalk removes wet grip surcharge")
	verify(move(target, 1), "Reach wet hold")
	game.chalk_protection = 0.0
	game._process(0.0)
	verify(is_equal_approx(game.climber.terrain_drain, 1.1), "Main applies wet idle drain")
	game.chalk_protection = 10.0
	game._process(0.0)
	verify(is_zero_approx(game.climber.terrain_drain), "Chalk prevents wet idle drain")
	# Main's environmental and wind gating with controlled sample values.
	game._hold(game.climber.current_hold_id)["kind"] = "small"
	game._process(0.0)
	verify(is_equal_approx(game.climber.terrain_drain, 0.7), "Main applies small hold idle drain")
	var before: float = game.climber.stamina
	game.climber._process(1.0)
	verify(is_equal_approx(before - game.climber.stamina, 1.08), "Small hold drains total 1.08 per second")
	game._update_reachable()
	target = game.reachable[0]
	game._hold(target)["kind"] = "wind"
	game.select_support(-1)
	game.attempt_hold(target, 0)
	game.wind_strength = 0.0
	for i in range(400):
		game._tick_control(0.01, controller_axis())
		if game.grip_ready():
			break
	verify(game.grip_ready(), "Calm wind allows valid grip")
	game.wind_strength = 0.9
	verify(not game.grip_ready(), "Strong gust blocks release")
	game._release_grip(0)
	verify(game._last_grip_failure.contains("阵风"), "Wind failure explains waiting")
	# Legacy checkpoint numbers must never be interpreted as the new layout.
	game.save_data = {"checkpoint": 38, "elapsed": 73.0, "falls": 2, "moves": 12, "summits": 1, "in_progress": true}
	game.start_climb(true)
	freeze()
	verify(game.route_index == 0 and game.climber.current_hold_id == 0, "Legacy checkpoint safely migrates to base")
	verify(game.elapsed == 73.0 and game.falls == 2 and game.climber.total_moves == 12, "Legacy time and counters preserved")
	verify(game.route_unlocked(1) and game.extreme_unlocked(), "Legacy summit keeps unlocks")
	verify(not game.route_unlocked(2), "Legacy summit does not unlock final route")
	var unchanged: bool = FileAccess.file_exists(player_path) == player_exists
	if player_exists:
		unchanged = unchanged and FileAccess.get_file_as_bytes(player_path) == player_bytes
	verify(unchanged, "Player save untouched byte-for-byte")
	game.sound.shutdown()
	game.queue_free()
	await create_timer(0.3).timeout
	OS.set_environment("MOUNTAINMARK_DATA_DIR", saved_environment)
	print("EXPEDITION_V3_RESULT checks=", checks, " failures=", failures.size())
	for failure: String in failures:
		print("FAILED: ", failure)
	quit(0 if failures.is_empty() else 1)

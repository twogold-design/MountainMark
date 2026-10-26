extends SceneTree
## Screen-space drag input, real hand endpoints and complete climbing journeys.
var game: Node3D
var view: SubViewport
var checks: int = 0
var failures: Array[String] = []
var player_saves: Dictionary = {}
var contacts: Array[Dictionary] = []
var arrivals: Array[int] = []
var repository: String

func _initialize() -> void:
	call_deferred("run")

func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL ", label)

func freeze() -> void:
	game.set_process(false)
	game.climber.set_process(false)
	game.sound.set_process(false)
	game.world.set_process(false)

func begin(route: int = 0, style: String = "journey", challenge: int = 0) -> void:
	game.mode = "menu"
	game.route_index = route
	game.play_style = style
	game.challenge_index = challenge
	game.start_climb(false)
	freeze()
	game._camera_ready = false
	game._update_camera(1.0)
	contacts.clear()
	arrivals.clear()

func axis_to(target: float) -> float:
	return clampf((target - float(game.balance)) * 14.0, -1.0, 1.0)

func tick(dt: float, axis: float = 0.0) -> void:
	game.clock_time += dt
	if game.mode != "playing":
		return
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
	game._update_camera(dt)
	game._sync_ui_visibility()

func align(id: int, hand: int) -> void:
	var stance: float = game.balance_target_for_hold(id, hand)
	for _step in range(200):
		if absf(game.balance - stance) < 0.01:
			break
		tick(0.01, axis_to(stance))
	game._update_reachable()

func move_mouse(point: Vector2, held: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = (MOUSE_BUTTON_MASK_LEFT if game.grip_hand == 0 else MOUSE_BUTTON_MASK_RIGHT) if held else 0
	view.push_input(event, true)

func mouse_button(point: Vector2, pressed: bool, hand: int = 1) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT if hand == 0 else MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	event.position = point
	event.global_position = point
	event.button_mask = (MOUSE_BUTTON_MASK_LEFT if hand == 0 else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
	view.push_input(event, true)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = code
	event.physical_keycode = code
	view.push_input(event, true)
	event.pressed = false
	view.push_input(event, true)

func passive(control: Control) -> bool:
	if control.mouse_filter != Control.MOUSE_FILTER_IGNORE or control.focus_mode != Control.FOCUS_NONE:
		return false
	return control.find_children("*", "BaseButton", true, false).is_empty()

func fixture(dx: float = 0.25, dy: float = 1.2, hand: int = 1) -> void:
	game.mode = "playing"
	game.help_open = false
	game._reset_controls()
	game.world.holds[0].links = [1]
	game.world.holds[1].position = Vector3(game.world.holds[0].position) + Vector3(dx, dy, 0.0)
	game.world.holds[1].support = -1
	game.world.holds[1].kind = "normal"
	game.world.holds[1].rest = false
	game.world.holds[1].checkpoint = false
	game.climber.setup(game.world.holds[0])
	game.climber.climbing = true
	game.current_rest = false
	game.climber.set_process(false)
	game.select_support(1 - hand)
	align(1, hand)
	game._camera_ready = false
	game._update_camera(1.0)
	game._sync_ui_visibility()
	contacts.clear()
	arrivals.clear()

func start_input(hand: int = 1) -> bool:
	var at: Vector2 = game.camera.unproject_position(game._hold(1).position)
	move_mouse(at)
	mouse_button(at, true, hand)
	return game.grip_active and game.grip_id == 1 and game.grip_hand == hand

func cursor_for(point: Vector3) -> Vector2:
	var info: Dictionary = game.get_drag_aim_info()
	var screen: Vector2 = game.camera.unproject_position(point)
	return Vector2(info.drag_anchor) - (screen - Vector2(info.origin_screen)) / float(game.DRAG_AMPLIFICATION)

func ideal_cursor() -> Vector2:
	var info: Dictionary = game.get_drag_aim_info()
	return Vector2(info.drag_anchor) - (Vector2(info.target_screen) - Vector2(info.origin_screen)) / float(game.DRAG_AMPLIFICATION)

func settle_aim(cursor: Vector2, seconds: float = 0.25, via_input: bool = true) -> void:
	if via_input:
		move_mouse(cursor, true)
	else:
		game.set_grip_drag(cursor)
	for _step in range(ceili(seconds / 0.01)):
		tick(0.01, axis_to(game.balance_target))

func _on_contact(id: int, hand: int, kind: String) -> void:
	contacts.append({"id": id, "hand": hand, "kind": kind, "palm": game.climber._gloves[hand].global_position})

func _on_arrival(id: int) -> void:
	arrivals.append(id)

func finish_motion() -> void:
	for _step in range(900):
		if not game.climber.moving and not game.climber.miss_reaching:
			return
		tick(1.0 / 120.0)

func check_real_input() -> void:
	fixture()
	verify(start_input(), "A real viewport click selects the target and begins a right-hand drag")
	var info: Dictionary = game.get_drag_aim_info()
	var keys_ok: bool = true
	for name: String in ["predicted", "target", "origin", "origin_screen", "target_screen", "predicted_screen", "drag_anchor", "drag_cursor", "power", "required_power", "angle_error", "miss_distance", "tolerance", "accurate"]:
		keys_ok = keys_ok and info.has(name)
	verify(keys_ok, "Aim feedback exposes the real world and logical viewport geometry")
	var start_power: float = game.grip_power
	var initial_prediction: Vector3 = info.predicted
	for _step in range(100):
		tick(0.01, axis_to(game.balance_target))
	info = game.get_drag_aim_info()
	verify(is_equal_approx(game.grip_power, start_power) and Vector3(info.predicted).distance_to(initial_prediction) < 0.03 and not bool(info.accurate) and not game.grip_ready(), "Waiting with the pointer still neither builds strength nor corrects a missed aim")
	var cursor: Vector2 = ideal_cursor()
	settle_aim(cursor)
	info = game.get_drag_aim_info()
	verify(game.grip_power > 0.0 and bool(info.accurate) and game.grip_ready(), "A backward mouse drag supplies the direction and force for the actual target")
	var shot: Vector3 = info.predicted
	mouse_button(cursor, false)
	verify(not game.grip_active and game.climber.moving, "A real mouse release commits the prepared drag")
	finish_motion()
	verify(game.climber.current_hold_id == 1 and game.climber.total_moves == 1 and contacts.size() == 1 and arrivals.size() == 1, "The viewport click-motion-release path completes exactly one real grab")
	verify(not contacts.is_empty() and Vector3(contacts[0].palm).distance_to(shot) < 0.018, "The rendered successful palm touches the predicted point")
	fixture()
	verify(start_input(), "Immediate release fixture starts through real viewport input")
	cursor = ideal_cursor()
	move_mouse(cursor, true)
	verify(is_zero_approx(game.grip_time) and game.grip_ready(), "An accurate drag can be ready immediately without waiting for a timed charge")
	mouse_button(cursor, false)
	finish_motion()
	verify(game.climber.current_hold_id == 1 and game.climber.total_moves == 1 and contacts.size() == 1, "An immediate accurate click-drag-release completes one grab")

func check_force_and_direction() -> void:
	fixture()
	verify(start_input(), "Force and direction fixture starts through viewport input")
	var info: Dictionary = game.get_drag_aim_info()
	var anchor: Vector2 = info.drag_anchor
	var pull: Vector2 = anchor - ideal_cursor()
	for factor: float in [0.45, 1.0, 1.50]:
		settle_aim(anchor - pull * factor)
		info = game.get_drag_aim_info()
		verify(bool(info.accurate) == is_equal_approx(factor, 1.0), "Pull length %.2f produces its actual undershoot, hit or overshoot" % factor)
		if not is_equal_approx(factor, 1.0):
			verify(float(info.miss_distance) > float(info.tolerance), "An incorrect force %.2f stays outside the rock tolerance" % factor)
	settle_aim(anchor - pull)
	var aligned_power: float = game.grip_power
	var aligned_quality: float = game.grip_quality()
	settle_aim(anchor - pull.rotated(0.70))
	info = game.get_drag_aim_info()
	verify(float(info.angle_error) > 0.60 and float(info.miss_distance) > float(info.tolerance) and not game.grip_ready(), "A clearly wrong direction independently sends the real predicted endpoint past the rock")
	settle_aim(anchor)
	verify(game.grip_power < aligned_power * 0.1 and not game.grip_ready(), "Dragging back toward the click anchor removes force immediately")
	settle_aim(anchor - pull)
	var target: Vector3 = game.get_drag_aim_info().target
	var tolerance: float = game.get_drag_aim_info().tolerance
	settle_aim(cursor_for(target + Vector3(tolerance * 0.45, 0.0, 0.0)))
	info = game.get_drag_aim_info()
	verify(bool(info.accurate) and game.grip_ready() and game.grip_quality() < aligned_quality - 0.025 and game.grip_quality() > 0.0, "A small real landing error inside tolerance reduces quality without an automatic center snap")
	var shot: Vector3 = info.predicted
	var offset: float = shot.distance_to(target)
	var cursor: Vector2 = info.drag_cursor
	mouse_button(cursor, false)
	finish_motion()
	verify(contacts.size() == 1 and Vector3(contacts[0].palm).distance_to(shot) < 0.018 and Vector3(contacts[0].palm).distance_to(target) > offset * 0.55, "An accepted off-center grab preserves the rendered off-center contact")

func check_miss_motion() -> void:
	fixture()
	verify(start_input(), "Miss fixture starts through viewport input")
	var info: Dictionary = game.get_drag_aim_info()
	var target: Vector3 = info.target
	var miss_point: Vector3 = target + Vector3(maxf(float(info.tolerance) * 6.0, 0.85), 0.0, 0.0)
	var cursor: Vector2 = cursor_for(miss_point)
	settle_aim(cursor)
	info = game.get_drag_aim_info()
	var predicted: Vector3 = info.predicted
	var old_hold: int = game.climber.current_hold_id
	var body_start: Vector3 = game.climber.get_body_position()
	var feet_start: Array[Vector3] = [game.climber.get_foot_position(0), game.climber.get_foot_position(1)]
	var original_moves: int = game.climber.total_moves
	var original_slips: int = game.slip_streak
	mouse_button(cursor, false)
	verify(game.climber.miss_reaching and not game.climber.moving and game.climber.current_hold_id == old_hold, "A missed release reaches toward the actual miss without beginning a climbing step")
	var closest: float = INF
	var max_palm_step: float = 0.0
	var foot_drift: float = 0.0
	var last_palm: Vector3 = game.climber._gloves[1].global_position
	var stayed: bool = true
	game.attempt_hold(1, 1)
	verify(not game.grip_active, "An unfinished miss cannot start a second overlapping drag")
	for _step in range(240):
		tick(1.0 / 120.0)
		var palm: Vector3 = game.climber._gloves[1].global_position
		# A safe miss keeps the original support and obeys real arm length.
		# Only a successful climb advances the body to the full target point.
		var shoulder: Vector3 = game.climber.get_shoulder_position(1)
		var endpoint: Vector3 = shoulder + (predicted - shoulder).limit_length(float(game.climber.ARM_REACH))
		closest = minf(closest, palm.distance_to(endpoint))
		for foot in range(2):
			foot_drift = maxf(foot_drift, game.climber.get_foot_position(foot).distance_to(feet_start[foot]))
		max_palm_step = maxf(max_palm_step, palm.distance_to(last_palm))
		last_palm = palm
		stayed = stayed and game.climber.current_hold_id == old_hold
		if not game.climber.miss_reaching:
			break
	verify(closest < 0.025, "The rendered miss reaches the physically limited endpoint along the actual predicted error direction")
	verify(foot_drift < 0.025, "A safe exploratory miss preserves both actual foot contacts")
	verify(max_palm_step < 0.11, "The exploratory miss has no hand teleport between 120fps frames")
	verify(stayed and game.climber.total_moves == original_moves and contacts.is_empty() and arrivals.is_empty(), "A miss neither changes holds or move counts nor emits a grip contact or arrival")
	verify(game.slip_streak == original_slips + 1 and not game.climber.miss_reaching and game.climber.get_body_position().distance_to(body_start) < 0.06, "The failed reach returns to the same support position and records one mistake")
	for _step in range(60):
		tick(1.0 / 120.0)
	verify(game.slip_streak == original_slips + 1 and contacts.is_empty(), "The completed miss produces no delayed grab sound signal or repeated failure")

func check_camera_cancel_and_interface() -> void:
	fixture()
	verify(start_input(), "Camera and cancellation fixture starts")
	settle_aim(ideal_cursor())
	var camera_transform: Transform3D = game.camera.global_transform
	game.camera_yaw = 0.6
	game.camera_pitch = 0.2
	for _step in range(25):
		tick(0.01, axis_to(game.balance_target))
	verify(game.camera.global_transform.is_equal_approx(camera_transform), "The original camera transform stays fixed throughout a drag")
	var power: float = game.grip_power
	var predicted: Vector3 = game.get_drag_aim_info().predicted
	key(KEY_QUOTELEFT)
	verify(not game.ui_visible and not game.hud.is_visible_in_tree() and game.control_hints.is_visible_in_tree() and game.grip_controls.is_visible_in_tree(), "The simplified interface retains operating hints and the real drag control component")
	verify(passive(game.grip_controls) and passive(game.control_hints) and is_equal_approx(game.grip_power, power) and Vector3(game.get_drag_aim_info().predicted).is_equal_approx(predicted), "Persistent drag feedback consumes no input and toggling the interface does not alter the shot")
	key(KEY_ESCAPE)
	game._sync_ui_visibility()
	verify(game.mode == "paused" and not game.grip_active and not game.grip_controls.is_visible_in_tree(), "Escape discards the active drag before pausing")
	mouse_button(Vector2.ZERO, false)
	key(KEY_ESCAPE)
	game._sync_ui_visibility()
	verify(game.mode == "playing" and not game.climber.moving and not game.climber.miss_reaching, "A release after pause cannot commit a stale trajectory")
	freeze()
	fixture()
	verify(start_input(), "Focus cancellation fixture starts")
	settle_aim(ideal_cursor())
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	mouse_button(Vector2.ZERO, false)
	verify(not game.grip_active and not game.climber.moving and not game.climber.miss_reaching, "Losing application focus cancels a pulled shot safely")
	if not game.ui_visible:
		key(KEY_QUOTELEFT)
	game.camera_yaw = 0.0
	game.camera_pitch = 0.0

func check_resolutions_and_edges() -> void:
	for size: Vector2i in [Vector2i(960, 720), Vector2i(1280, 720), Vector2i(1440, 900), Vector2i(1920, 1080)]:
		view.size = size
		fixture()
		if game.ui_visible:
			key(KEY_QUOTELEFT)
		verify(start_input(), "A target click uses logical coordinates at resolution %s" % str(size))
		var cursor: Vector2 = ideal_cursor()
		settle_aim(cursor)
		var info: Dictionary = game.get_drag_aim_info()
		verify(Rect2(Vector2.ZERO, Vector2(size)).has_point(cursor) and bool(info.accurate) and game.grip_ready(), "A normal camera exposes a complete in-window target drag at resolution %s" % str(size))
		game._cancel_grip()
		game._sync_ui_visibility()
	view.size = Vector2i(1440, 900)
	for edge: Vector2 in [Vector2(42.0, 400.0), Vector2(1398.0, 400.0), Vector2(720.0, 42.0), Vector2(720.0, 858.0)]:
		fixture()
		var target: Vector3 = game._hold(1).position
		var depth: float = -game.camera.to_local(target).z
		var at_screen: Vector3 = game.camera.project_position(edge, depth)
		game.camera.global_position += target - at_screen
		game._camera_ready = true
		verify(start_input(), "The real click can select a projected target near screen edge %s" % str(edge))
		var cursor: Vector2 = ideal_cursor()
		settle_aim(cursor)
		var info: Dictionary = game.get_drag_aim_info()
		verify(bool(info.accurate) and Vector3(info.predicted).is_finite() and game.grip_ready(), "A held drag near edge %s preserves finite, accurate world mapping even if the cursor crosses a window edge" % str(edge))
		game._cancel_grip()
		game._sync_ui_visibility()
	if not game.ui_visible:
		key(KEY_QUOTELEFT)

func legal_move(id: int, hand: int) -> bool:
	game.select_support(int(game._hold(id).get("support", -1)))
	align(id, hand)
	if str(game._hold(id).kind) == "wind":
		for _wait in range(1800):
			if game.world.get_wind_strength() < 0.40:
				break
			tick(0.01)
	game._update_camera(1.0)
	game.attempt_hold(id, hand)
	if not game.grip_active:
		return false
	for _step in range(440):
		game.set_grip_drag(ideal_cursor())
		tick(0.01, axis_to(game.balance_target))
		if game.mode != "playing" or not game.grip_active:
			return false
		if game.grip_ready() and game.grip_quality() >= 0.90:
			break
	if not game.grip_ready():
		return false
	game._release_grip(hand)
	if not game.climber.moving:
		return false
	finish_motion()
	game._update_reachable()
	return game.climber.current_hold_id == id

func ascent(branch: String) -> bool:
	var minimum: float = 100.0
	for _step in range(250):
		if game.mode == "summit":
			print("DRAG_ASCENT route=", game.route_index, " style=", game.play_style, " challenge=", game.challenge_index, " branch=", branch, " moves=", game.climber.total_moves, " min_stamina=", snappedf(minimum, 0.1), " elapsed=", snappedf(game.elapsed, 0.1), " falls=", game.falls)
			return game.falls == 0
		if game.current_rest:
			for _rest in range(200):
				if game.climber.stamina >= 99.0:
					break
				tick(0.05)
		game._update_reachable()
		if game.reachable.is_empty():
			return false
		var id: int = game.reachable[0]
		for candidate: int in game.reachable:
			if str(game._hold(candidate).branch) == branch:
				id = candidate
		if game.climber.stamina < 30.0 or (str(game._hold(id).kind) == "wet" and game.chalk_protection <= 0.0):
			game.use_chalk()
		var dx: float = Vector3(game._hold(id).position).x - game.climber.get_reach_origin().x
		var hand: int = (1 if dx > 0 else 0) if absf(dx) > 0.55 else 1 - game.last_hand
		if game.climber.stamina < game.hold_effort(id, hand, 0.0) + 3.0 and game.chalk_charges > 0:
			for _cooldown in range(700):
				if game.climber._chalk_cooldown <= 0.0 or game.mode != "playing":
					break
				tick(0.01)
			game.use_chalk()
		if not legal_move(id, hand):
			print("DRAG_ASCENT_FAILURE route=", game.route_index, " style=", game.play_style, " challenge=", game.challenge_index, " branch=", branch, " from=", game.climber.current_hold_id, " to=", id, " stamina=", game.climber.stamina, " reason=", game.toast, " mode=", game.mode)
			return false
		minimum = minf(minimum, game.climber.stamina)
	return false

func check_expeditions() -> void:
	for route in range(3):
		for style: String in ["journey", "extreme"]:
			for branch: String in ["safe", "shortcut"]:
				begin(route, style)
				verify(ascent(branch), "Complete drag ascent route=%d style=%s branch=%s" % [route, style, branch])
	for challenge in range(3):
		begin(0, "challenge", challenge)
		verify(ascent("main"), "Complete drag challenge %d" % challenge)
		verify(game.save_data.get("records", {}).has("challenge_%d" % challenge), "Drag challenge %d awards its completion record" % challenge)

func run() -> void:
	var script_path: String = get_script().resource_path
	if script_path.begins_with("res://"):
		script_path = ProjectSettings.globalize_path(script_path)
	repository = script_path.get_base_dir().get_base_dir()
	var isolated: String = OS.get_environment("MOUNTAINMARK_DATA_DIR").replace("\\", "/").simplify_path()
	var safe_root: String = repository.path_join(".runtime").replace("\\", "/").simplify_path() + "/"
	if "--qa-capture" not in OS.get_cmdline_user_args() or not isolated.begins_with(safe_root):
		push_error("Use -- --qa-capture and an isolated checkout .runtime data directory")
		quit(2)
		return
	for suffix: String in [".runtime/save.json", "build/.runtime/save.json"]:
		var path: String = repository.path_join(suffix)
		player_saves[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	view = SubViewport.new()
	view.size = Vector2i(1440, 900)
	view.handle_input_locally = true
	root.add_child(view)
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	view.add_child(game)
	game.save_data = {"completed_routes": {"0": true, "1": true, "2": true}}
	game.sound.set_muted(true)
	freeze()
	verify(game.has_method("set_grip_drag") and game.has_method("get_drag_aim_info") and game.climber.has_method("miss_grip"), "Drag controls expose actual aiming and an independent failed reach")
	if not game.has_method("set_grip_drag") or not game.has_method("get_drag_aim_info") or not game.climber.has_method("miss_grip"):
		quit(1)
		return
	game.climber.hand_contact.connect(_on_contact)
	game.climber.reached_hold.connect(_on_arrival)
	await process_frame
	begin()
	check_real_input()
	check_force_and_direction()
	check_miss_motion()
	check_camera_cancel_and_interface()
	check_resolutions_and_edges()
	check_expeditions()
	for path: String in player_saves:
		var bytes: Variant = player_saves[path]
		verify((not FileAccess.file_exists(path)) if bytes == null else (FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path) == bytes), path + " remains byte-for-byte unchanged")
	verify(not FileAccess.file_exists(isolated.path_join("save.json")), "Capture mode does not write the isolated test save either")
	game.sound.shutdown()
	game.queue_free()
	await process_frame
	print("DRAG_GRIP_RESULT checks=", checks, " failures=", failures.size())
	for failure: String in failures:
		print("FAILED: ", failure)
	quit(0 if failures.is_empty() else 1)

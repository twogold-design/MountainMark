extends SceneTree
## Core input, failure and resource regression for direct mouse-pull aiming.
var game: Node3D
var test_view: SubViewport
var checks: int = 0
var failures: Array[String] = []
var player_saves: Dictionary = {}
var mouse_position: Vector2 = Vector2.ZERO

func _initialize() -> void:
	call_deferred("run")

func verify(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures.append(label)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	game._unhandled_input(event)

func mouse_at(point: Vector2) -> void:
	mouse_position = point
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	if game.grip_active:
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if game.grip_hand == 0 else MOUSE_BUTTON_MASK_RIGHT
	test_view.push_input(event, true)
	game._update_hover()

func mouse(pressed: bool, hand: int = 0) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT if hand == 0 else MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	event.position = mouse_position
	event.global_position = mouse_position
	event.button_mask = (MOUSE_BUTTON_MASK_LEFT if hand == 0 else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
	test_view.push_input(event, true)

func reset_run() -> void:
	game.start_climb(false)
	game.set_process(false)
	game.climber.set_process(false)
	game._update_reachable()
	game._update_camera(1.0)

func next_id() -> int:
	game._update_reachable()
	game.choose_next()
	return int(game.preview_id)

func control_axis() -> float:
	var difference: float = float(game.balance_target) - float(game.balance)
	return signf(difference) if absf(difference) > 0.012 else 0.0

func drag(factor: float = 1.0, angle: float = 0.0) -> void:
	if not game.grip_active:
		return
	var aim: Dictionary = game.get_drag_aim_info()
	var pull: Vector2 = (Vector2(aim.target_screen) - Vector2(aim.origin_screen)) / float(game.DRAG_AMPLIFICATION)
	game.set_grip_drag(Vector2(aim.drag_anchor) - pull.rotated(angle) * factor)

func prepare_release(id: int, hand: int) -> bool:
	var foot: int = int(game._hold(id).get("support", -1))
	if foot >= 0:
		game.select_support(foot)
	game._update_camera(1.0)
	game.attempt_hold(id, hand)
	if not game.grip_active:
		return false
	for tick in range(440):
		game._tick_control(0.01, control_axis())
		drag()
		if game.grip_ready():
			return true
	return false

func finish_failed_reach() -> void:
	for _frame in range(120):
		if game.mode != "playing" or (not game.climber.miss_reaching and game._slip_cooldown <= 0.0):
			break
		game._tick_control(0.01, 0.0)
		game.climber._process(0.01)

func legal_move(id: int, hand: int) -> bool:
	if not prepare_release(id, hand):
		return false
	game._release_grip(hand)
	if not game.climber.moving:
		return false
	for step in range(250):
		game.climber._process(0.01)
		if not game.climber.moving:
			break
	game._update_reachable()
	return game.climber.current_hold_id == id

func run() -> void:
	if "--qa-capture" not in OS.get_cmdline_user_args() or OS.get_environment("MOUNTAINMARK_DATA_DIR").is_empty():
		push_error("Run with -- --qa-capture and isolated MOUNTAINMARK_DATA_DIR")
		quit(2)
		return
	var script_path: String = get_script().resource_path
	if script_path.begins_with("res://"):
		script_path = ProjectSettings.globalize_path(script_path)
	var repository: String = script_path.get_base_dir().get_base_dir()
	for suffix: String in [".runtime/save.json", "build/.runtime/save.json"]:
		var path: String = repository.path_join(suffix)
		player_saves[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	test_view = SubViewport.new()
	test_view.size = Vector2i(1440, 900)
	test_view.handle_input_locally = true
	root.add_child(test_view)
	var packed := load("res://scenes/main.tscn") as PackedScene
	game = packed.instantiate() as Node3D
	test_view.add_child(game)
	game.save_data = {}
	game.sound.set_muted(true)
	await process_frame
	reset_run()
	var start: Vector3 = game.climber.get_reach_origin()
	var initial_id: int = game.climber.current_hold_id
	for i in range(100):
		key(KEY_W)
	verify(game.preview_id >= 0 and not game.grip_active and not game.climber.moving and game.climber.current_hold_id == initial_id and game.climber.get_reach_origin().is_equal_approx(start), "100 W presses preview only, never move")
	var target: int = next_id()
	game._camera_ready = false
	game._update_camera(1.0)
	mouse_at(game.camera.unproject_position(game._hold(target).position))
	mouse(true)
	verify(game.grip_active and not game.climber.moving, "mouse press begins grip preparation without movement")
	mouse(false)
	verify(not game.grip_active and not game.climber.moving and not game.climber.miss_reaching and game.climber.current_hold_id == initial_id and game.slip_streak == 0, "a click without pulling cancels without moving or counting a mistake")
	reset_run()
	target = next_id()
	game.attempt_hold(target, 0)
	for _sample in range(100):
		game._tick_control(0.01, 0.0)
	verify(game.grip_active and is_zero_approx(game.grip_power) and not game.grip_ready(), "Holding the pointer still never accumulates force or aims automatically")
	reset_run()
	target = next_id()
	game.attempt_hold(target, 0)
	var bad_balance_ready: bool = false
	for tick in range(440):
		var away: float = -1.0 if game.balance_target >= 0.0 else 1.0
		game._tick_control(0.01, away)
		drag()
		if game.grip_power_ready() and absf(game.balance - game.balance_target) > game.balance_window:
			bad_balance_ready = true
			break
	var stamina_before: float = game.climber.stamina
	game._release_grip(0)
	verify(bad_balance_ready and not game.climber.moving and game.slip_streak == 1 and game.climber.stamina < stamina_before, "an accurate drag with wrong body balance fails and spends stamina")
	reset_run()
	target = next_id()
	game.attempt_hold(target, 0)
	# Isolate pull length from balance; real A/D movement is exercised below.
	game.balance = game.balance_target
	game.climber.set_lean(game.balance)
	game._refresh_grip_geometry()
	game._tick_control(0.05, 0.0)
	drag(0.4)
	var insufficient: bool = absf(game.balance - game.balance_target) <= game.balance_window and not game.grip_power_ready()
	game._release_grip(0)
	verify(insufficient and not game.climber.moving and game.slip_streak == 1 and "拉得太短" in game._last_grip_failure, "a short pull with correct body balance misses and explains insufficient reach")
	reset_run()
	target = next_id()
	var aimed: bool = prepare_release(target, 0)
	drag(1.0, 0.70)
	var off_target: bool = not game.grip_ready() and float(game.get_drag_aim_info().miss_distance) > float(game.get_drag_aim_info().tolerance)
	game._release_grip(0)
	verify(aimed and off_target and not game.climber.moving and game.slip_streak == 1 and "方向偏" in game._last_grip_failure, "direction error independently produces a real missed landing and specific feedback")
	reset_run()
	target = next_id()
	verify(legal_move(target, 0), "A/D balance correction plus a correct drag completes a left-hand move")
	target = next_id()
	verify(legal_move(target, 1), "second move accepts the right hand and updates position")
	verify(game.climber.total_moves == 2 and game.slip_streak == 0, "two successful grips count exactly two moves and clear mistakes")
	reset_run()
	target = next_id()
	game.attempt_hold(target, 0)
	for tick in range(710):
		game._tick_control(0.01, 0.0)
	verify(not game.grip_active and not game.climber.moving and game.slip_streak == 1, "holding longer than seven seconds fails once")
	reset_run()
	target = next_id()
	var pause_ready: bool = prepare_release(target, 0)
	key(KEY_ESCAPE)
	var paused_origin: Vector3 = game.climber.get_reach_origin()
	verify(pause_ready and game.mode == "paused" and not game.grip_active, "Escape cancels a prepared grip before pausing")
	mouse(false)
	key(KEY_ESCAPE)
	mouse(false)
	verify(game.mode == "playing" and not game.climber.moving and game.climber.get_reach_origin().is_equal_approx(paused_origin) and game.slip_streak == 0, "release during or after pause cannot apply stale grip")
	reset_run()
	target = next_id()
	game.attempt_hold(target, 0)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	verify(not game.grip_active and not game.climber.moving, "focus loss cancels held input")
	if game.mode == "paused":
		game.toggle_pause()
	reset_run()
	verify(legal_move(next_id(), 0), "leave anchor before repeated-failure recovery test")
	var departed: int = game.climber.current_hold_id
	for i in range(3):
		target = next_id()
		prepare_release(target, 1)
		drag(1.0, 0.70)
		game._release_grip(1)
		finish_failed_reach()
	verify(game.mode == "fallen", "third mistake waits for explicit retry")
	game.fall_time = 0.7
	game.retry_after_fall()
	verify(departed != game.checkpoint and game.climber.current_hold_id == game.checkpoint and game.falls == 1 and game.slip_streak == 0, "three consecutive mistakes return to anchor and count one fall")
	reset_run()
	game.current_rest = false
	game.climber.stamina = 30.0
	var chalk_start: int = game.chalk_charges
	for i in range(3):
		game.climber._chalk_cooldown = 0.0
		game.use_chalk()
	verify(chalk_start == 3 and game.chalk_charges == 0, "only three chalk charges are available")
	var after_chalk: float = game.climber.stamina
	game.climber._chalk_cooldown = 0.0
	game.use_chalk()
	verify(game.chalk_charges == 0 and is_equal_approx(game.climber.stamina, after_chalk), "fourth chalk use does not restore stamina")
	var anchor: Dictionary = {}
	for hold: Dictionary in game.world.holds:
		if bool(hold.checkpoint) and int(hold.id) > 0:
			anchor = hold
			break
	game.climber.setup(anchor)
	game.climber.climbing = true
	game._on_reached(int(anchor.id))
	verify(game.chalk_charges == 3, "reaching a safety anchor replenishes chalk")
	reset_run()
	target = next_id()
	game._grip_hand_history = 0
	var repeated_cost: float = game.hold_effort(target, 0, 1.0)
	game._grip_hand_history = 1
	var alternate_cost: float = game.hold_effort(target, 0, 1.0)
	verify(repeated_cost > alternate_cost, "repeating the same hand costs more than alternating")
	game._grip_hand_history = -1
	var delta_x: float = game._hold(target).position.x - game.climber.get_reach_origin().x
	var natural_hand: int = 1 if delta_x > 0.0 else 0
	verify(game.hold_effort(target, 1 - natural_hand, 1.0) > game.hold_effort(target, natural_hand, 1.0), "cross-body reach costs more than the natural-side hand")
	# Keep hand, terrain, support and body fixed, varying only the same point's
	# distance. The initial reachable set can legitimately contain just one point.
	var authored_position: Vector3 = game._hold(target).position
	var fixed_origin: Vector3 = game.climber.get_reach_origin()
	game._hold(target).position = fixed_origin + Vector3(0.3, 1.15, 0.0)
	var near_effort: float = game.hold_effort(target, 1, 1.0)
	game._hold(target).position = fixed_origin + Vector3(0.3, 1.6, 0.0)
	var far_effort: float = game.hold_effort(target, 1, 1.0)
	game._hold(target).position = authored_position
	verify(far_effort > near_effort, "increasing the same hold's distance with the same hand and terrain consumes more stamina")
	verify(game.hold_effort(target, 1, 0.2) > game.hold_effort(target, 1, 1.0), "less stable movement quality consumes more stamina")
	reset_run()
	var route_ok: bool = true
	var route_steps: int = 0
	var minimum_stamina: float = 100.0
	for step in range(100):
		if game.mode == "summit":
			break
		if game.current_rest:
			game.climber.rest(5.0)
		target = next_id()
		if target < 0 or not legal_move(target, step % 2):
			route_ok = false
			print("ROUTE_FAILURE at=", game.climber.current_hold_id, " target=", target, " stamina=", game.climber.stamina, " balance=", game.balance, " grip=", game.grip_power)
			break
		route_steps += 1
		minimum_stamina = minf(minimum_stamina, game.climber.stamina)
	verify(route_ok and game.mode == "summit" and game.falls == 0 and route_steps > 20 and game.climber.total_moves == route_steps, "complete route is reachable using drag aim, alternating hands and rest ledges")
	print("ROUTE_METRICS moves=", route_steps, " minimum_stamina=", minimum_stamina, " falls=", game.falls)
	for path: String in player_saves:
		var bytes: Variant = player_saves[path]
		verify((not FileAccess.file_exists(path)) if bytes == null else (FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path) == bytes), path + " remains untouched")
	game.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.3).timeout
	print("CONTROL_V2_RESULT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)





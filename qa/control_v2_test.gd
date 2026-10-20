extends SceneTree
## Deterministic gameplay regression. Inputs follow the same grip/balance API as UI.
const TEST_SAVE := "res://qa/control-v2-save.json"
var game: Node3D
var test_view: SubViewport
var checks: int = 0
var failures: Array[String] = []
var player_path: String
var player_existed: bool
var player_bytes: PackedByteArray

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
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	test_view.push_input(event, true)
	game._update_hover()

func mouse(pressed: bool, hand: int = 0) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT if hand == 0 else MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	game._unhandled_input(event)

func reset_run() -> void:
	game.start_climb(false)
	game.set_process(false)
	game.climber.set_process(false)
	game._update_reachable()

func next_id() -> int:
	game._update_reachable()
	game.choose_next()
	return int(game.preview_id)

func control_axis() -> float:
	var difference: float = float(game.balance_target) - float(game.balance)
	return signf(difference) if absf(difference) > 0.012 else 0.0

func prepare_release(id: int, hand: int) -> bool:
	game.attempt_hold(id, hand)
	if not game.grip_active:
		return false
	for tick in range(440):
		game._tick_control(0.01, control_axis())
		if game.grip_ready():
			return true
	return false

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
	test_view = SubViewport.new()
	test_view.size = Vector2i(1440, 900)
	test_view.handle_input_locally = true
	root.add_child(test_view)
	var packed := load("res://scenes/main.tscn") as PackedScene
	game = packed.instantiate() as Node3D
	test_view.add_child(game)
	game._save_path = ProjectSettings.globalize_path(TEST_SAVE)
	game.save_data = {}
	game.sound.set_muted(true)
	player_path = game._data_path("save.json")
	player_existed = FileAccess.file_exists(player_path)
	if player_existed:
		player_bytes = FileAccess.get_file_as_bytes(player_path)
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
	verify(not game.grip_active and not game.climber.moving and game.climber.current_hold_id == initial_id and game.slip_streak == 1, "instant click cannot climb and counts one timing failure")
	verify(is_equal_approx(game._grip_power_at(0.0), 0.0) and is_equal_approx(game._grip_power_at(1.1), 1.0) and is_equal_approx(game._grip_power_at(2.2), 0.0), "grip pulse follows specified 2.2 second cycle")
	reset_run()
	target = next_id()
	game.attempt_hold(target, 0)
	var bad_balance_ready: bool = false
	for tick in range(440):
		var away: float = -1.0 if game.balance_target >= 0.0 else 1.0
		game._tick_control(0.01, away)
		if absf(game.grip_power - game.grip_target) <= game.grip_window and absf(game.balance - game.balance_target) > game.balance_window:
			bad_balance_ready = true
			break
	var stamina_before: float = game.climber.stamina
	game._release_grip(0)
	verify(bad_balance_ready and not game.climber.moving and game.slip_streak == 1 and game.climber.stamina < stamina_before, "correct pulse with wrong body balance fails and spends stamina")
	reset_run()
	target = next_id()
	game.attempt_hold(target, 0)
	var bad_timing_ready: bool = false
	for tick in range(440):
		game._tick_control(0.01, control_axis())
		if absf(game.balance - game.balance_target) <= game.balance_window and absf(game.grip_power - game.grip_target) > game.grip_window:
			bad_timing_ready = true
			break
	game._release_grip(0)
	verify(bad_timing_ready and not game.climber.moving and game.slip_streak == 1, "correct body balance outside pulse window fails")
	reset_run()
	target = next_id()
	verify(legal_move(target, 0), "A/D balance correction plus timed release completes a left-hand move")
	target = next_id()
	verify(legal_move(target, 1), "second move accepts the right hand and updates position")
	verify(game.climber.total_moves == 2 and game.slip_streak == 0, "two successful grips count exactly two moves and clear mistakes")
	reset_run()
	target = next_id()
	game.attempt_hold(target, 0)
	for tick in range(460):
		game._tick_control(0.01, 0.0)
	verify(not game.grip_active and not game.climber.moving and game.slip_streak == 1, "holding longer than 4.5 seconds fails once")
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
		game.attempt_hold(target, 1)
		game._release_grip(1)
		game._tick_control(0.36, 0.0)
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
	var near_id: int = -1
	var far_id: int = -1
	var near_distance: float = INF
	var far_distance: float = -INF
	for id: int in game.reachable:
		var distance: float = game.climber.get_reach_origin().distance_to(game._hold(id).position)
		if distance < near_distance:
			near_distance = distance
			near_id = id
		if distance > far_distance:
			far_distance = distance
			far_id = id
	verify(far_distance > near_distance and game.hold_effort(far_id, 1, 1.0) > game.hold_effort(near_id, 1, 1.0), "farther reaches consume more stamina")
	verify(game.hold_effort(target, 1, 0.2) > game.hold_effort(target, 1, 1.0), "less precise release consumes more stamina")
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
	verify(route_ok and game.mode == "summit" and game.falls == 0 and route_steps > 20 and game.climber.total_moves == route_steps, "complete route is reachable using only legal timed grips, alternating hands and rest ledges")
	print("ROUTE_METRICS moves=", route_steps, " minimum_stamina=", minimum_stamina, " falls=", game.falls)
	var unchanged: bool = FileAccess.file_exists(player_path) == player_existed
	if player_existed:
		unchanged = unchanged and FileAccess.get_file_as_bytes(player_path) == player_bytes
	verify(unchanged, "player save remains byte-for-byte untouched")
	game.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.3).timeout
	print("CONTROL_V2_RESULT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)





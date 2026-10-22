extends SceneTree
## Geometry regression. Run with -- --qa-capture and an isolated data directory.
## The synthetic edge stays in the real route graph and under the 3.05m edge limit.
var game: Node3D
var test_view: SubViewport
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func verify(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures.append(label)

func lean(value: float) -> void:
	game.balance = value
	game.climber.set_lean(value)
	game._refresh_grip_geometry()
	game._update_reachable()

func edge(dx: float = 0.9, dy: float = 2.17, support: int = -1) -> void:
	game.mode = "playing"
	game._reset_controls()
	game.world.holds[0].links = [1]
	game.world.holds[1].position = Vector3(game.world.holds[0].position) + Vector3(dx, dy, 0.0)
	game.world.holds[1].support = support
	game.world.holds[1].kind = "normal"
	game.climber.setup(game.world.holds[0])
	game.climber.climbing = true
	game.climber.set_process(false)
	game.current_rest = false
	game._update_reachable()

func actual_shoulders_match() -> bool:
	for hand in range(2):
		var side: float = -1.0 if hand == 0 else 1.0
		var actual: Vector3 = game.climber._torso.transform * Vector3(side * 0.225, 0.22, -0.02)
		var info: Dictionary = game.hold_reach_info(1, hand)
		if not actual.is_equal_approx(info.shoulder):
			return false
	return game.climber.get_body_position().is_equal_approx(game.climber._torso.position)

func make_pulse_ready() -> void:
	game.grip_time = 1.0
	game.grip_power = game.grip_target

func run() -> void:
	var isolated: String = ProjectSettings.globalize_path("res://.runtime/reach-geometry-data")
	if "--qa-capture" not in OS.get_cmdline_user_args() or OS.get_environment("MOUNTAINMARK_DATA_DIR").simplify_path() != isolated.simplify_path():
		push_error("Use -- --qa-capture and MOUNTAINMARK_DATA_DIR=" + isolated)
		quit(2)
		return
	test_view = SubViewport.new()
	test_view.size = Vector2i(1440, 900)
	root.add_child(test_view)
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	test_view.add_child(game)
	game.set_process(false)
	game.sound.set_muted(true)
	await process_frame

	# Both directions and both crossed hands must gain real reach from the right shift.
	for side in [-1, 1]:
		var hand: int = 0 if side > 0 else 1
		edge(0.1 + float(side) * 0.8)
		lean(-float(side) * 0.9)
		var far: Dictionary = game.hold_reach_info(1, hand)
		var far_cost: float = game.hold_effort(1, hand, 1.0)
		var outside: bool = 1 in game.readable and 1 not in game.reachable
		lean(float(side) * 0.9)
		var near: Dictionary = game.hold_reach_info(1, hand)
		verify(outside and 1 in game.readable and 1 in game.reachable and not far.reachable and near.reachable, "side %d: weight shift changes a readable edge from out of reach to reachable" % side)
		verify(near.distance < far.distance and game.hold_effort(1, hand, 1.0) < far_cost, "side %d: the same hand moves closer and spends less stamina" % side)
		verify(game.recommended_hand(1) == (1 if side > 0 else 0), "side %d: natural-side hand is recommended" % side)
		verify(actual_shoulders_match(), "side %d: rendered torso and reach calculation share the actual shoulders immediately" % side)
		var hint: String = game.balance_hint_for_hold(1)
		var target: float = game.balance_target_for_hold(1, hand)
		var shoulder: Vector3 = near.shoulder
		var camera_start: Transform3D = game.camera.transform
		var invariant: bool = true
		for angles: Vector2 in [Vector2(-0.68, -0.22), Vector2(0.68, 0.22), Vector2.ZERO]:
			game.camera_yaw = angles.x
			game.camera_pitch = angles.y
			game._camera_ready = false
			game._update_camera(1.0)
			var rotated: Dictionary = game.hold_reach_info(1, hand)
			invariant = invariant and game.balance_hint_for_hold(1) == hint and is_equal_approx(game.balance_target_for_hold(1, hand), target) and is_equal_approx(float(rotated.distance), float(near.distance)) and Vector3(rotated.shoulder).is_equal_approx(shoulder)
		verify(invariant and not game.camera.transform.is_equal_approx(camera_start), "side %d: rotating the real camera preserves direction hint, target balance and distance" % side)

	# The selected support foot shifts the same body used for geometry and gates release.
	edge(0.65, 1.5, 0)
	game.select_support(1)
	lean(0.3)
	var wrong_support: Dictionary = game.hold_reach_info(1, 1)
	var wrong_shoulder: Vector3 = wrong_support.shoulder
	game.select_support(0)
	var correct_support: Dictionary = game.hold_reach_info(1, 1)
	verify(not wrong_support.support_ok and correct_support.support_ok and correct_support.max_distance > wrong_support.max_distance and wrong_shoulder.x > Vector3(correct_support.shoulder).x, "support foot changes actual shoulder position and grants its reach allowance only when correct")
	verify(actual_shoulders_match(), "changing support foot updates rendered shoulders without a frame of lag")
	game.attempt_hold(1, 1)
	lean(game.balance_target)
	make_pulse_ready()
	game.select_support(1)
	verify(game.grip_reach_ready() and not game.grip_ready(), "a reachable hand and good timing cannot bypass the required support foot")
	game.select_support(0)
	lean(game.balance_target)
	make_pulse_ready()
	verify(game.grip_ready(), "correct foot, real reach, balance and timing jointly allow the grip")

	# Isolate reach gating from the two numeric bars so a wide UI window cannot bypass it.
	edge()
	lean(-0.9)
	game.attempt_hold(1, 0)
	make_pulse_ready()
	game.balance_window = 2.0
	verify(game.grip_active and not game.grip_reach_ready() and not game.grip_ready(), "green timing and balance bars cannot approve a hand that physically cannot reach")
	var origin: Vector3 = game.climber.get_reach_origin()
	game._release_grip(0)
	verify(not game.climber.moving and game.climber.get_reach_origin().is_equal_approx(origin) and game.slip_streak == 1 and game._last_grip_failure.contains("够不到"), "releasing out of reach fails once and never starts a move")

	# Exercise live input, rather than only setting the geometry query's lean argument.
	edge()
	lean(-0.9)
	var before_input: float = game.hold_reach_info(1, 0).distance
	game._tick_control(0.8, 1.0)
	verify(game.balance > 0.0 and game.hold_reach_info(1, 0).distance < before_input and actual_shoulders_match(), "A/D input updates distance and visible shoulders during route reading")
	game.attempt_hold(1, 0)
	lean(game.balance_target)
	make_pulse_ready()
	verify(game.grip_ready(), "moving onto the proper side makes the formerly unreachable crossed-hand grip ready")
	var stamina: float = game.climber.stamina
	game._release_grip(0)
	verify(game.climber.moving and game.climber.stamina < stamina, "the legal adjusted grip starts an actual climb and spends stamina")
	for frame in range(500):
		if not game.climber.moving:
			break
		game.climber._process(0.01)
	verify(game.climber.current_hold_id == 1 and actual_shoulders_match(), "adjusted reach completes at the target with consistent rendered geometry")

	edge()
	lean(0.9)
	game.attempt_hold(1, 0)
	var paused_body: Vector3 = game.climber.get_body_position()
	game.toggle_pause()
	game._release_grip(0)
	game.toggle_pause()
	game.climber.set_process(false)
	verify(not game.grip_active and not game.climber.moving and game.climber.get_body_position().is_equal_approx(paused_body) and actual_shoulders_match(), "pause cancels the prepared grip and preserves a coherent body pose")
	game.select_support(1)
	game._on_fell()
	game.fall_time = 0.7
	game.retry_after_fall()
	game.climber.set_process(false)
	verify(game.mode == "playing" and is_zero_approx(game.balance) and is_zero_approx(game.climber._lean) and game.selected_support == -1 and game.climber.current_hold_id == game.checkpoint and actual_shoulders_match(), "retry clears stale lean and support and restores the checkpoint's actual pose")
	verify(not FileAccess.file_exists(isolated.path_join("save.json")), "capture mode never writes a save, including during fall recovery")

	game.queue_free()
	await process_frame
	await process_frame
	print("REACH_GEOMETRY_RESULT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

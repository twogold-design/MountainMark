extends "drag_grip_test.gd"
## Fixed imperfect mouse traces measure assistance; these are scripted samples,
## not a measurement of real players. Shared motion/viewport helpers stay here.
const PROFILES := [
	{"label": "near_normal", "offset": Vector2(0.25, 1.10), "kind": "normal", "foot": -1, "hand": 1},
	{"label": "far_normal", "offset": Vector2(0.75, 1.70), "kind": "normal", "foot": 1, "hand": 1},
	{"label": "small", "offset": Vector2(-0.35, 1.35), "kind": "small", "foot": 0, "hand": 0}
]
const SIZES := [Vector2i(960, 720), Vector2i(1280, 720), Vector2i(1920, 1080)]
const VIEWS := [Vector2(-0.50, -0.15), Vector2.ZERO, Vector2(0.50, 0.15)]
const IMPERFECT_TRACES := [
	Vector4(0.85, -12.0, -3.0, 2.0), Vector4(0.90, -8.0, 2.0, -2.0),
	Vector4(1.10, 8.0, -2.0, 3.0), Vector4(1.15, 12.0, 3.0, -2.0),
	Vector4(0.85, 12.0, -3.0, 1.0), Vector4(1.15, -12.0, 1.0, 3.0),
	Vector4(0.90, 8.0, 0.0, -3.0), Vector4(1.10, -8.0, 3.0, 0.0)
]
var sample_stats: Dictionary = {}

func prepare_profile(profile: Dictionary, size: Vector2i = Vector2i(1280, 720), angles: Vector2 = Vector2.ZERO) -> bool:
	view.size = size
	game.mode = "playing"
	game.help_open = false
	game._reset_controls()
	game.world.holds[0].links = [1]
	game.world.holds[1].position = Vector3(game.world.holds[0].position) + Vector3(profile.offset.x, profile.offset.y, 0.0)
	game.world.holds[1].support = int(profile.foot)
	game.world.holds[1].kind = str(profile.kind)
	game.world.holds[1].rest = bool(profile.get("rest", false))
	game.world.holds[1].checkpoint = false
	game.climber.setup(game.world.holds[0])
	game.climber.climbing = true
	game.current_rest = false
	game.camera_yaw = angles.x
	game.camera_pitch = angles.y
	game._update_reachable()
	game._camera_ready = false
	game._update_camera(1.0)
	game._sync_ui_visibility()
	contacts.clear()
	arrivals.clear()
	if not start_input(int(profile.hand)):
		return false
	# Isolate aiming tolerance after the real no-A/D settling behavior. No drag
	# adjustment or force is supplied while the body establishes its stance.
	for _step in range(240):
		tick(0.01, 0.0)
		if absf(game.balance - game.balance_target) < 0.018:
			break
	return game.grip_active and absf(game.balance - game.balance_target) <= game.balance_window

func trace_cursor(trace: Vector4) -> Vector2:
	var aim: Dictionary = game.get_drag_aim_info()
	var pull: Vector2 = (Vector2(aim.target_screen) - Vector2(aim.origin_screen)) / float(game.DRAG_AMPLIFICATION)
	return Vector2(aim.drag_anchor) - pull.rotated(deg_to_rad(trace.y)) * trace.x + Vector2(trace.z, trace.w)

func check_imperfect_inputs() -> void:
	var samples: int = 0
	var raw_hits: int = 0
	var actual_hits: int = 0
	var assistance_seen: int = 0
	var corrections_safe: bool = true
	var tolerance_preserved: bool = true
	for profile: Dictionary in PROFILES:
		var label: String = profile.label
		sample_stats[label] = {"samples": 0, "raw_hits": 0, "hits": 0}
		for size: Vector2i in SIZES:
			for angles: Vector2 in VIEWS:
				for trace: Vector4 in IMPERFECT_TRACES:
					var prepared: bool = prepare_profile(profile, size, angles)
					if not prepared:
						verify(false, "Sample cannot establish its real stance: %s %s %s" % [label, str(size), str(angles)])
						continue
					move_mouse(trace_cursor(trace), true)
					tick(0.01, 0.0)
					var aim: Dictionary = game.get_drag_aim_info()
					var raw_error: float = Vector3(aim.raw_predicted).distance_to(Vector3(aim.target))
					var corrected_error: float = Vector3(aim.predicted).distance_to(Vector3(aim.target))
					var raw_hit: bool = raw_error <= float(aim.tolerance)
					var actual_hit: bool = game.grip_ready()
					samples += 1
					raw_hits += int(raw_hit)
					actual_hits += int(actual_hit)
					assistance_seen += int(bool(aim.assisted))
					sample_stats[label].samples += 1
					sample_stats[label].raw_hits += int(raw_hit)
					sample_stats[label].hits += int(actual_hit)
					corrections_safe = corrections_safe and corrected_error <= raw_error + 0.0001 and float(aim.assist_strength) >= 0.0 and float(aim.assist_strength) <= 1.0
					tolerance_preserved = tolerance_preserved and is_equal_approx(float(aim.tolerance), 0.11 if str(profile.kind) == "small" else 0.18)
					if actual_hit:
						corrections_safe = corrections_safe and corrected_error <= float(aim.tolerance) and game.grip_quality() > 0.0
					game._cancel_grip()
	verify(samples == 216, "All 216 predefined imperfect input traces were sampled")
	verify(actual_hits >= ceili(float(samples) * 0.80), "At least 80 percent of the fixed imperfect traces can actually release")
	verify(actual_hits - raw_hits >= ceili(float(samples) * 0.25), "Assistance improves this fixed trace set by at least 25 percentage points")
	verify(assistance_seen > samples / 2 and corrections_safe, "Continuous target attraction reduces real error without leaving the original rock tolerance")
	verify(tolerance_preserved, "The raw small and ordinary rock tolerances remain 0.11m and 0.18m")
	for label: String in sample_stats:
		var stats: Dictionary = sample_stats[label]
		verify(int(stats.hits) >= ceili(float(stats.samples) * 2.0 / 3.0), label + " remains usable across its view and resolution samples")
		print("DRAG_ASSIST_SAMPLES profile=", label, " total=", stats.samples, " raw_hits=", stats.raw_hits, " assisted_hits=", stats.hits)
	print("DRAG_ASSIST_SAMPLES total=", samples, " raw_hits=", raw_hits, " assisted_hits=", actual_hits, " traces=force0.85-1.15/angle8-12deg/jitter2-3px")

func check_pose_and_override() -> void:
	verify(prepare_profile(PROFILES[1]), "Automatic stance fixture starts on a real required-foot hold")
	verify(game.selected_support == 1 and game.climber.support_foot == 1 and game.balance > 0.30, "Clicking the hold selects its required foot and really shifts body balance without A/D")
	var actual_shoulder: Vector3 = game.climber._torso.transform * Vector3(0.225, 0.22, -0.02)
	var shoulder: Vector3 = game.climber.get_shoulder_position(1)
	verify(actual_shoulder.is_equal_approx(shoulder), "Automatic stance uses the rendered shoulder in real reach calculations")
	var before_balance: float = game.balance
	var before_shoulder: Vector3 = shoulder
	for _step in range(35):
		tick(0.01, -1.0)
	verify(game.balance < before_balance - 0.20 and game.climber.get_shoulder_position(1).x < before_shoulder.x - 0.05, "Manual A input overrides automatic settling and visibly moves the real shoulder left")
	verify(prepare_profile(PROFILES[2]), "Manual support fixture starts")
	move_mouse(ideal_cursor(), true)
	key(KEY_E)
	for _step in range(15):
		tick(0.01, 0.0)
	verify(game.selected_support == 1 and game.climber.support_foot == 1 and not game.grip_ready(), "Manual E can replace automatic support and the wrong foot still blocks a release")
	key(KEY_Q)
	for _step in range(100):
		tick(0.01, 0.0)
	move_mouse(ideal_cursor(), true)
	verify(game.selected_support == 0 and game.climber.support_foot == 0 and game.grip_ready(), "Q restores the matching real support and permits the adjusted shot")

func check_clear_errors_and_cancellation() -> void:
	for trace: Vector4 in [Vector4(0.45, 0.0, 0.0, 0.0), Vector4(1.50, 0.0, 0.0, 0.0), Vector4(1.0, 38.0, 0.0, 0.0), Vector4(1.0, 180.0, 0.0, 0.0)]:
		verify(prepare_profile(PROFILES[1]), "An intentional error fixture starts")
		var cursor: Vector2 = trace_cursor(trace)
		move_mouse(cursor, true)
		var aim: Dictionary = game.get_drag_aim_info()
		verify(not game.grip_ready() and Vector3(aim.predicted).distance_to(Vector3(aim.target)) > float(aim.tolerance), "Clearly wrong force/direction remains a real miss: %s" % str(trace))
		var stamina: float = game.climber.stamina
		mouse_button(cursor, false, 1)
		verify(game.slip_streak == 1 and not game.climber.moving and is_equal_approx(stamina - float(game.climber.stamina), 6.0), "A clear mistake records one failure and costs six stamina")
		finish_motion()
	for pixels: float in [0.0, 4.0]:
		verify(prepare_profile(PROFILES[0]), "A light-click cancellation fixture starts")
		var anchor: Vector2 = game.get_drag_aim_info().drag_anchor
		var cursor: Vector2 = anchor + Vector2(pixels, 0.0)
		move_mouse(cursor, true)
		var stamina: float = game.climber.stamina
		mouse_button(cursor, false, 1)
		verify(not game.grip_active and game.slip_streak == 0 and is_equal_approx(game.climber.stamina, stamina) and not game.climber.moving and not game.climber.miss_reaching and contacts.is_empty(), "A %.0fpx near-click cancels without a shot or an extra stamina/mistake penalty" % pixels)
	verify(prepare_profile(PROFILES[0]), "Seven-second hanging fixture starts")
	while game.grip_active and game.grip_time < 6.85:
		tick(0.01, 0.0)
	verify(game.grip_active and is_zero_approx(game.grip_power) and not game.grip_ready(), "A stationary pointer remains uncharged through 6.85 seconds")
	while game.grip_active and game.grip_time < 7.1:
		tick(0.01, 0.0)
	verify(not game.grip_active and game.slip_streak == 1 and "悬挂太久" in game._last_grip_failure, "Seven seconds still ends an unsupported hanging preparation exactly once")

func check_continuity_and_contact() -> void:
	verify(prepare_profile(PROFILES[1]), "Continuous attraction fixture starts")
	var anchor: Vector2 = game.get_drag_aim_info().drag_anchor
	var pull: Vector2 = anchor - ideal_cursor()
	var last: Vector3 = Vector3.INF
	var maximum_step: float = 0.0
	for angle_step in range(-164, 165):
		move_mouse(anchor - pull.rotated(deg_to_rad(float(angle_step) * 0.25)), true)
		var point: Vector3 = game.get_drag_aim_info().predicted
		if last.is_finite():
			maximum_step = maxf(maximum_step, point.distance_to(last))
		last = point
	verify(maximum_step < 0.07, "A quarter-degree input sweep has no hard jump at the angular assistance boundary")
	last = Vector3.INF
	maximum_step = 0.0
	for power_step in range(90, 311):
		move_mouse(anchor - pull * (float(power_step) * 0.005), true)
		var point: Vector3 = game.get_drag_aim_info().predicted
		if last.is_finite():
			maximum_step = maxf(maximum_step, point.distance_to(last))
		last = point
	verify(maximum_step < 0.09, "A half-percent force sweep has no hard jump at the strength assistance boundary")
	verify(prepare_profile(PROFILES[0]), "An imperfect assisted-contact fixture starts")
	var cursor: Vector2 = trace_cursor(Vector4(1.10, 8.0, 2.0, -2.0))
	move_mouse(cursor, true)
	var aim: Dictionary = game.get_drag_aim_info()
	var predicted: Vector3 = aim.predicted
	verify(bool(aim.assisted) and game.grip_ready(), "A modestly imperfect viewport drag becomes an assisted real shot")
	mouse_button(cursor, false, 1)
	finish_motion()
	verify(game.climber.current_hold_id == 1 and contacts.size() == 1 and Vector3(contacts[0].palm).distance_to(predicted) < 0.018, "The actual hand lands at the corrected prediction once instead of a cosmetic marker")
	for kind: String in ["normal", "small", "wet", "rest"]:
		var profile: Dictionary = PROFILES[0].duplicate(true)
		profile.kind = "normal" if kind == "rest" else kind
		profile.rest = kind == "rest"
		verify(prepare_profile(profile), kind + " tolerance fixture starts")
		var expected: float = {"normal": 0.18, "small": 0.11, "wet": 0.14, "rest": 0.22}[kind]
		verify(is_equal_approx(float(game.get_drag_aim_info().tolerance), expected), kind + " preserves its original physical contact tolerance")

func run() -> void:
	var script_path: String = get_script().resource_path
	if script_path.begins_with("res://"):
		script_path = ProjectSettings.globalize_path(script_path)
	repository = script_path.get_base_dir().get_base_dir()
	var isolated: String = OS.get_environment("MOUNTAINMARK_DATA_DIR").replace("\\", "/").simplify_path()
	if "--qa-capture" not in OS.get_cmdline_user_args() or not isolated.begins_with(repository.path_join(".runtime").replace("\\", "/").simplify_path() + "/"):
		push_error("Run in an isolated checkout .runtime directory with --qa-capture")
		quit(2)
		return
	for suffix: String in [".runtime/save.json", "build/.runtime/save.json"]:
		var path: String = repository.path_join(suffix)
		player_saves[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	view = SubViewport.new()
	view.size = Vector2i(1280, 720)
	view.handle_input_locally = true
	root.add_child(view)
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	view.add_child(game)
	game.save_data = {"completed_routes": {"0": true, "1": true, "2": true}}
	game.sound.set_muted(true)
	freeze()
	game.climber.hand_contact.connect(_on_contact)
	game.climber.reached_hold.connect(_on_arrival)
	await process_frame
	begin()
	game.toggle_ui()
	verify(prepare_profile(PROFILES[0]), "Assisted drag fixture starts through the real viewport")
	var aim: Dictionary = game.get_drag_aim_info()
	var fields: bool = true
	for name: String in ["raw_predicted", "raw_predicted_screen", "assisted", "assist_strength", "assist_angle", "assist_power_ratio"]:
		fields = fields and aim.has(name)
	verify(fields, "Assistance exposes its raw endpoint and continuous correction values")
	if not fields:
		game.sound.shutdown()
		quit(1)
		return
	check_imperfect_inputs()
	check_pose_and_override()
	check_clear_errors_and_cancellation()
	check_continuity_and_contact()
	for path: String in player_saves:
		var bytes: Variant = player_saves[path]
		verify((not FileAccess.file_exists(path)) if bytes == null else (FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path) == bytes), path + " remains unchanged")
	game.sound.shutdown()
	game.queue_free()
	await process_frame
	print("DRAG_ASSIST_RESULT checks=", checks, " failures=", failures.size())
	for failure: String in failures:
		print("FAILED: ", failure)
	quit(0 if failures.is_empty() else 1)

extends Node3D
## Three mountains, branching journeys, challenges and a persistent expedition journal.
const Routes = preload("res://scripts/routes.gd")
const ROUTE_NAMES := ["松风岩脊", "回声峡谷", "云上孤峰"]
const WorldScript = preload("res://scripts/world.gd")
const ClimberScript = preload("res://scripts/climber.gd")
const AudioScript = preload("res://scripts/audio.gd")
const HudScript = preload("res://scripts/hud.gd")
const REACH: float = 3.05
const HEIGHT: float = 72.0
var CHAPTERS: Array[String] = ["起攀 · 松风岩脚", "第一段 · 风蚀石阶", "第二段 · 云间横渡", "第三段 · 天光之脊", "终点 · 群山之上"]
var world: Node3D
var climber: Node3D
var sound: Node
var camera: Camera3D
var hud: Control
var mode: String = "menu"
var elapsed: float = 0.0
var falls: int = 0
var highest: float = 0.0
var hovered_id: int = -1
var reachable: Array = []
var readable: Array[int] = []
var current_rest: bool = true
var rest_feedback_time: float = 0.0
var rest_feedback_stamina: float = 100.0
var _move_voice_distance: float = 0.0
var _move_voice_limit: float = 1.0
var checkpoint: int = 0
var last_hand: int = 0
var toast: String = ""
var toast_sub: String = ""
var toast_time: float = 0.0
var summit_time: float = 0.0
var clock_time: float = 0.0
var muted: bool = false
var help_open: bool = false
var save_data: Dictionary = {}
var visited: Dictionary = {}
var chapter: int = 0
var _camera_ready: bool = false
var camera_yaw: float = 0.0
var camera_pitch: float = 0.0
var camera_reading: bool = false
var camera_orbiting: bool = false
var _auto_test: bool = false
var _auto_timer: float = 0.0
var _qa_idle: float = 0.0
var _save_path: String
var route_index: int = 0
var route_height: float = 72.0
var play_style: String = "journey"
var challenge_index: int = 0
var selected_support: int = -1
var chalk_protection: float = 0.0
var wind_strength: float = 0.0
var result_title: String = ""
var result_detail: String = ""
var earned_badges: Array[String] = []
var postcard_path: String = ""
var outfit_index: int = 0
var active_route: Dictionary = {}
var run_collections: Array[String] = []
var precise_streak: int = 0
var best_precise_streak: int = 0
var chalk_used: int = 0
var _summit_buttons_ready: bool = false
var _last_grip_failure: String = ""
var fall_time: float = 0.0
var fall_reason: String = ""
var fall_title: String = "这一步，没能抓稳。"
var grip_active: bool = false
var grip_id: int = -1
var grip_hand: int = 0
var grip_time: float = 0.0
var grip_power: float = 0.0
var grip_target: float = 0.62
var grip_window: float = 0.16
var balance: float = 0.0
var balance_target: float = 0.0
var balance_window: float = 0.30
var chalk_charges: int = 3
var slip_streak: int = 0
var preview_id: int = -1
var last_quality: float = 0.0
var _grip_hand_history: int = -1
var _slip_cooldown: float = 0.0

func _ready() -> void:
	Engine.max_fps = 90
	_save_path = _data_path("save.json")
	_load_save()
	world = WorldScript.new()
	add_child(world)
	active_route = Routes.build(0)
	world.build_world(active_route)
	climber = ClimberScript.new()
	add_child(climber)
	climber.setup(world.holds[0])
	outfit_index = clampi(int(save_data.get("outfit", 0)), 0, 2)
	climber.set_outfit(outfit_index)
	climber.reached_hold.connect(_on_reached)
	climber.fell.connect(_on_fell)
	climber.effort_started.connect(_on_effort_started)
	sound = AudioScript.new()
	add_child(sound)
	sound.start_ambience()
	camera = Camera3D.new()
	camera.fov = 53.0
	camera.near = 0.1
	camera.far = 1200.0
	add_child(camera)
	camera.current = true
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	hud = HudScript.new()
	hud.game = self
	layer.add_child(hud)
	_update_reachable()
	_auto_test = "--qa-route" in OS.get_cmdline_user_args()
	if _auto_test:
		start_climb(false)
		print("QA_START holds=", world.holds.size())
	if "--qa-summit" in OS.get_cmdline_user_args():
		start_climb(false)
		climber.setup(world.holds[-1])
		_on_reached(int(world.holds[-1].id))
	if "--qa-midpoint" in OS.get_cmdline_user_args():
		start_climb(false)
		var midpoint: Dictionary = world.holds[world.holds.size() / 2]
		climber.setup(midpoint)
		climber.climbing = true
		_on_reached(int(midpoint.id))
		_update_reachable()
	get_tree().auto_accept_quit = false

func _data_path(filename: String) -> String:
	var base: String = ProjectSettings.globalize_path("res://.runtime")
	if OS.has_feature("standalone") and not OS.has_feature("editor"):
		base = OS.get_executable_path().get_base_dir().path_join(".runtime")
	if OS.has_environment("MOUNTAINMARK_DATA_DIR"):
		base = OS.get_environment("MOUNTAINMARK_DATA_DIR")
	DirAccess.make_dir_recursive_absolute(base)
	return base.path_join(filename)

func _load_save() -> void:
	if FileAccess.file_exists(_save_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_save_path))
		if parsed is Dictionary:
			save_data = parsed

func _write_save() -> void:
	if "--qa-capture" in OS.get_cmdline_user_args() or _auto_test or "--qa-summit" in OS.get_cmdline_user_args() or "--qa-midpoint" in OS.get_cmdline_user_args():
		return
	var file: FileAccess = FileAccess.open(_save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data, "\t"))

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		camera_orbiting = false
		if grip_active:
			_cancel_grip()
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()

func _process(delta: float) -> void:
	clock_time += delta
	toast_time = maxf(0.0, toast_time - delta)
	if mode == "playing":
		rest_feedback_time = maxf(0.0, rest_feedback_time - delta)
		elapsed += delta
		chalk_protection = maxf(0.0, chalk_protection - delta)
		wind_strength = world.get_wind_strength()
		sound.set_wind_strength(wind_strength)
		var terrain: String = str(_hold(climber.current_hold_id).get("kind", "normal"))
		climber.terrain_drain = 0.7 if terrain == "small" else (1.1 if terrain == "wet" and chalk_protection <= 0.0 else 0.0)
		if current_rest and not climber.moving and not grip_active:
			climber.rest(delta)
		var lean: float = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		if _auto_test:
			var aim: int = grip_id if grip_active else next_hold_id()
			if aim >= 0:
				var stance: float = balance_target if grip_active else balance_target_for_hold(aim, recommended_hand(aim))
				lean = clampf((stance - balance) * 8.0, -1.0, 1.0)
		_update_read_line_camera(delta)
		_tick_control(delta, lean)
		_update_reachable()
		_update_hover()
		if _auto_test:
			_run_qa(delta)
	elif mode == "fallen":
		fall_time += delta
	elif mode == "summit":
		summit_time += delta
		if summit_time >= 4.0 and not _summit_buttons_ready:
			_summit_buttons_ready = true
			hud.refresh_buttons()
		if _auto_test and summit_time > 3.0:
			print("QA_SUCCESS summit reached; moves=", climber.total_moves, "; falls=", falls, "; checkpoints=", checkpoint)
			_auto_test = false
			quit_game()
	var altitude: float = clampf((climber.get_reach_origin().y - 1.0) / route_height, 0.0, 1.0)
	world.update_atmosphere(altitude, delta if mode in ["playing", "menu", "summit"] else 0.0)
	sound.set_altitude(altitude)
	_sync_climbing_audio()
	if climber.has_method("set_support_feedback_visible"):
		climber.set_support_feedback_visible(mode == "playing" and not help_open)
	_update_camera(delta)
	hud.queue_redraw()

func _sync_climbing_audio() -> void:
	sound.set_climbing_state(climber.stamina, mode == "playing" and climber.climbing and not help_open, current_rest and not climber.moving and not grip_active)

func _on_effort_started() -> void:
	_sync_climbing_audio()
	sound.play_exertion(_move_voice_distance, _move_voice_limit, climber._move_duration)

func _update_camera(delta: float) -> void:
	var body: Vector3 = climber.get_body_position()
	var target: Vector3 = body + Vector3(1.10, 0.9, -0.4)
	var desired: Vector3 = body + Vector3(4.5, 1.4, 8.0)
	if mode == "menu":
		target = Vector3(-2.6, 7.0, 0.0)
		desired = Vector3(9.0 + sin(clock_time * 0.07) * 0.8, 10.0, 22.0)
	elif mode == "summit":
		var progress: float = smoothstep(0.0, 9.0, summit_time)
		var summit: Vector3 = world.get_summit_position()
		target = body.lerp(summit + Vector3(0.0, 1.0, 0.0), progress * 0.7)
		desired = body + Vector3(lerpf(1.0, 12.0, progress), lerpf(1.5, 6.0, progress), lerpf(9.0, 20.0, progress))
	else:
		var view_angle: float = camera_yaw if mode == "playing" else 0.0
		var view_basis: Basis = Basis(Vector3.UP, view_angle) * Basis(Vector3.RIGHT, camera_pitch if mode == "playing" else 0.0)
		target = body + view_basis * Vector3(1.10, 0.9, -0.4)
		desired = body + view_basis * Vector3(4.5, 1.4, 8.0)
		if current_rest and not grip_active:
			desired += Vector3(0.3, 0.4, 0.6)
		desired += Vector3(sin(clock_time * 0.75) * 0.022, sin(clock_time * 1.15) * 0.025, 0.0)
	if not _camera_ready:
		camera.position = desired
		_camera_ready = true
	else:
		camera.position = camera.position.lerp(desired, 1.0 - exp(-delta * 3.5))
	if camera.position.distance_to(target) > 0.1:
		camera.look_at(target, Vector3.UP)

func _update_read_line_camera(delta: float) -> void:
	if mode != "playing" or grip_active or climber.moving:
		camera_orbiting = false
		camera_reading = false
		return
	var orbit_axis: float = float(Input.is_physical_key_pressed(KEY_X)) - float(Input.is_physical_key_pressed(KEY_Z))
	if absf(orbit_axis) > 0.01:
		camera_yaw = clampf(camera_yaw + orbit_axis * delta * 0.90, -0.68, 0.68)
		camera_reading = true
	else:
		camera_reading = camera_orbiting or absf(camera_yaw) > 0.015 or absf(camera_pitch) > 0.015

func start_climb(resume: bool = false) -> void:
	if resume:
		route_index = clampi(int(save_data.get("route", 0)), 0, 2)
		play_style = "journey"
	elif play_style != "challenge" and not route_unlocked(route_index):
		show_toast("山路尚未开启", "先完成上一条路线，或进入岩段挑战练习。", 4.0)
		return
	if play_style == "extreme" and not extreme_unlocked():
		show_toast("先认识这座山", "完成本路线的登山旅程后，开启极限登顶。", 4.0)
		return
	_build_selected_world()
	sound.reset_ascent()
	_reset_controls()
	mode = "playing"
	help_open = false
	climber.process_mode = Node.PROCESS_MODE_INHERIT
	var start_id: int = 0
	elapsed = 0.0
	falls = 0
	highest = 0.0
	checkpoint = 0
	chapter = 0
	precise_streak = 0
	best_precise_streak = 0
	chalk_used = 0
	postcard_path = ""
	run_collections.clear()
	earned_badges.clear()
	camera_yaw = 0.0
	camera_pitch = 0.0
	camera_reading = false
	camera_orbiting = false
	visited.clear()
	if resume:
		# Old versions have a different hold layout: safely resume at base.
		start_id = int(save_data.get("checkpoint", 0)) if int(save_data.get("version", 0)) >= 3 else 0
		elapsed = float(save_data.get("elapsed", 0.0))
		falls = int(save_data.get("falls", 0))
		chalk_used = int(save_data.get("chalk_used", 0))
		for item in save_data.get("run_collections", []):
			run_collections.append(str(item))
		if start_id < 0 or start_id >= world.holds.size() or not bool(_hold(start_id).checkpoint):
			start_id = 0
	var hold: Dictionary = _hold(start_id)
	climber.setup(hold)
	climber.set_outfit(outfit_index)
	climber.total_moves = int(save_data.get("moves", 0)) if resume else 0
	climber.climbing = true
	checkpoint = start_id
	current_rest = bool(hold.rest)
	_sync_climbing_audio()
	highest = float(hold.position.y)
	chapter = mini(4, int(highest / route_height * 4.0))
	_camera_ready = false
	_update_reachable()
	hud.refresh_buttons()
	show_toast(str(active_route.name), challenge_goal_text() if play_style == "challenge" else "W 标记目标 · 中键 / Z X 读线。Q/E 选支撑脚 → A/D 移重心 → 按住鼠标，双绿区就绪后松开。", 7.0)
	if resume and int(save_data.get("version", 0)) < 3:
		show_toast("旧旅程已保留，山路已更新", "旧版锚点布局已变化，本次从营地出发；原登顶成绩仍在。", 8.0)

func _hold(id: int) -> Dictionary:
	for hold: Dictionary in world.holds:
		if int(hold.id) == id:
			return hold
	return world.holds[0]

func _update_reachable() -> void:
	reachable.clear()
	readable.clear()
	var origin: Vector3 = climber.get_reach_origin()
	var links: Array = _hold(climber.current_hold_id).get("links", [])
	for id: int in links:
		if origin.distance_to(Vector3(_hold(id).position)) > REACH:
			continue
		readable.append(id)
		if bool(hold_reach_info(id, 0).reachable) or bool(hold_reach_info(id, 1).reachable):
			reachable.append(id)
	world.set_hold_feedback(reachable, grip_id if grip_active else (hovered_id if hovered_id >= 0 else preview_id), climber.current_hold_id)

func _update_hover() -> void:
	hovered_id = -1
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var best: float = 44.0
	for id: int in readable:
		var p: Vector3 = _hold(id).position
		if camera.is_position_behind(p):
			continue
		var distance: float = camera.unproject_position(p).distance_to(mouse)
		if distance < best:
			best = distance
			hovered_id = id

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			var fullscreen: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
			return
		if event.keycode == KEY_M:
			toggle_audio()
			return
		if event.keycode == KEY_ESCAPE:
			if help_open:
				help_open = false
				hud.refresh_buttons()
			elif mode == "journal":
				close_journal()
			elif mode == "playing" or mode == "paused":
				toggle_pause()
			return
		if mode == "menu" and event.keycode == KEY_ENTER:
			start_climb(false)
			return
		if mode == "fallen" and event.keycode == KEY_ENTER:
			retry_after_fall()
			return
		if mode != "playing":
			return
		match event.keycode:
			KEY_W, KEY_UP:
				choose_next()
			KEY_SPACE:
				use_chalk()
			KEY_R:
				_on_fell("主动返回")
			KEY_Q:
				select_support(0)
			KEY_E:
				select_support(1)
	if event is InputEventMouseMotion and camera_orbiting and mode == "playing" and not climber.moving and not grip_active:
		camera_yaw = clampf(camera_yaw - event.relative.x * 0.0045, -0.68, 0.68)
		camera_pitch = clampf(camera_pitch + event.relative.y * 0.0035, -0.28, 0.22)
		camera_reading = true
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		camera_orbiting = event.pressed and mode == "playing" and not grip_active and not climber.moving
		if camera_orbiting:
			camera_reading = true
		return
	if event is InputEventMouseButton and mode == "playing":
		if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT:
			return
		var hand: int = 0 if event.button_index == MOUSE_BUTTON_LEFT else 1
		if not event.pressed:
			_release_grip(hand)
		elif not grip_active and not climber.moving and not camera_orbiting:
			_update_hover()
			if hovered_id >= 0:
				attempt_hold(hovered_id, hand)
			else:
				show_toast("先选一处落手点", "对准发光岩点，按住左键或右键。W 只观察路线，不会自动攀爬。", 2.5)

func next_hold_id() -> int:
	var origin: Vector3 = climber.get_reach_origin()
	var best_score: float = INF
	var best_id: int = -1
	for id: int in readable:
		var hold: Dictionary = _hold(id)
		if not bool(hold_reach_info(id).can_adjust):
			continue
		var p: Vector3 = hold.position
		if p.y < origin.y:
			continue
		var score: float = origin.distance_to(p) + absf(p.x - origin.x) * 0.25
		if bool(hold.rest):
			score -= 0.45
		if score < best_score:
			best_score = score
			best_id = id
	return best_id

func choose_next() -> void:
	# Observation is deliberately separate from committing a climbing move.
	if mode != "playing" or climber.moving or grip_active:
		return
	preview_id = next_hold_id()
	show_toast("观察，不等于迈步", "已标记上行岩点。中键拖拽或 Z / X 调整读线视角；按住鼠标后再用 A / D 稳住重心。", 3.0)

func balance_hint_for_hold(id: int) -> String:
	if id < 0:
		return ""
	var info: Dictionary = hold_reach_info(id, grip_hand if grip_active and grip_id == id else -1)
	var direction: float = float(info.target_balance) - balance
	var instruction: String = "重心已到位"
	if absf(direction) > 0.08:
		instruction = "A 向岩壁左侧移重心" if direction < 0.0 else "D 向岩壁右侧移重心"
	return ("左手" if int(info.hand) == 0 else "右手") + " · " + instruction

func balance_target_for_hold(id: int, hand: int) -> float:
	# Align the chosen shoulder with the hold on the wall's horizontal axis.
	var x: float = float(_hold(id).position.x)
	var low: float = -0.90
	var high: float = 0.90
	for _iteration in range(12):
		var middle: float = (low + high) * 0.5
		if climber.get_shoulder_position(hand, middle).x < x:
			low = middle
		else:
			high = middle
	return (low + high) * 0.5

func recommended_hand(id: int) -> int:
	var target: Vector3 = Vector3(_hold(id).position) + Vector3(0.0, 0.0, 0.025)
	var best_hand: int = 0
	var best_score: float = INF
	for hand: int in range(2):
		var stance: float = balance_target_for_hold(id, hand)
		var distance: float = climber.get_shoulder_position(hand, stance).distance_to(target)
		var score: float = distance + absf(stance) * 0.04 + (0.10 if hand == _grip_hand_history else 0.0)
		if score < best_score:
			best_score = score
			best_hand = hand
	return best_hand

func hold_reach_info(id: int, hand: int = -1, lean_value: float = 2.0) -> Dictionary:
	var chosen: int = recommended_hand(id) if hand < 0 else clampi(hand, 0, 1)
	var weight: float = balance if lean_value > 1.0 else clampf(lean_value, -1.0, 1.0)
	var hold: Dictionary = _hold(id)
	var target: Vector3 = Vector3(hold.position) + Vector3(0.0, 0.0, 0.025)
	var shoulder: Vector3 = climber.get_shoulder_position(chosen, weight)
	var stance: float = balance_target_for_hold(id, chosen)
	var distance: float = shoulder.distance_to(target)
	var required: int = int(hold.get("support", -1))
	var supported: bool = required < 0 or selected_support == required
	# One route edge includes several <=0.4m foot placements and a final arm reach.
	var push_bonus: float = 0.05 if required >= 0 and supported else 0.0
	var maximum: float = ClimberScript.ARM_REACH + ClimberScript.STEP_REACH + push_bonus
	var best_distance: float = climber.get_shoulder_position(chosen, stance).distance_to(target)
	return {"hand": chosen, "shoulder": shoulder, "target": target,
		"distance": distance, "max_distance": maximum, "target_balance": stance,
		"reachable": distance <= maximum, "can_adjust": best_distance <= maximum,
		"support_ok": supported}

func grip_reach_ready() -> bool:
	return grip_active and bool(hold_reach_info(grip_id, grip_hand).reachable)

func _refresh_grip_geometry() -> void:
	if not grip_active:
		return
	var hold: Dictionary = _hold(grip_id)
	var info: Dictionary = hold_reach_info(grip_id, grip_hand)
	var altitude: float = clampf(float(hold.position.y) / route_height, 0.0, 1.0)
	var long_reach: float = clampf((float(info.distance) - 1.9) / 1.0, 0.0, 1.0)
	balance_target = float(info.target_balance)
	balance_window = lerpf(0.30, 0.20, altitude) - long_reach * 0.025

func attempt_hold(id: int, hand: int = 0) -> void:
	if mode != "playing" or climber.moving or grip_active or _slip_cooldown > 0.0 or id not in readable:
		return
	if not bool(hold_reach_info(id, hand).can_adjust):
		show_toast("这只手还够不到", "换一只手，或先用 Q / E 选好支撑脚，再用 A / D 移重心。", 3.0)
		return
	camera_orbiting = false
	grip_id = id
	grip_hand = clampi(hand, 0, 1)
	grip_time = 0.0
	grip_power = 0.0
	preview_id = -1
	var hold: Dictionary = _hold(id)
	var span: Vector3 = Vector3(hold.position) - climber.get_reach_origin()
	var altitude: float = clampf(float(hold.position.y) / route_height, 0.0, 1.0)
	var long_reach: float = clampf((span.length() - 1.4) / 1.6, 0.0, 1.0)
	grip_target = 0.57 + long_reach * 0.13 + float(id % 3) * 0.035
	grip_window = lerpf(0.16, 0.10, altitude) - long_reach * 0.015
	if climber.stamina < hold_effort(id, grip_hand, 0.0):
		grip_id = -1
		show_toast("这一步需要更多握力", "选择更近的岩点，或空格使用镁粉。金色岩点可以休息。", 3.0)
		return
	grip_active = true
	_refresh_grip_geometry()
	toast_time = 0.0
	var foot: int = int(hold.get("support", -1))
	if foot >= 0 and selected_support != foot:
		show_toast("先让脚站稳", "这一步需要" + ("左脚支撑（Q）" if foot == 0 else "右脚支撑（E）") + "，再稳住重心出手。", 3.0)

func _grip_power_at(seconds: float) -> float:
	return 0.5 - 0.5 * cos(seconds * TAU / 2.2)

func _tick_control(delta: float, axis: float) -> void:
	_slip_cooldown = maxf(0.0, _slip_cooldown - delta)
	if climber.moving:
		return
	var target_windy: bool = grip_active and str(_hold(grip_id).get("kind", "")) == "wind"
	var wind: float = sin(clock_time * 1.3) * (0.04 + (wind_strength * 0.55 if target_windy else 0.0))
	balance = clampf(balance + (axis * 1.25 + (wind if grip_active else 0.0)) * delta, -1.0, 1.0)
	climber.set_lean(balance)
	_refresh_grip_geometry()
	if not grip_active:
		return
	grip_time += delta
	grip_power = _grip_power_at(grip_time)
	climber.stamina = maxf(0.0, climber.stamina - delta * 1.6)
	if grip_time >= 4.5:
		_fail_grip("悬挂太久，手指滑开了")
	elif climber.stamina <= 0.0:
		_on_fell()

func grip_ready() -> bool:
	if not grip_active:
		return false
	var foot: int = int(_hold(grip_id).get("support", -1))
	var supported: bool = foot < 0 or foot == selected_support
	var wind_ok: bool = str(_hold(grip_id).get("kind", "")) != "wind" or wind_strength < 0.72
	return supported and wind_ok and grip_reach_ready() and grip_time >= 0.2 and grip_time < 4.5 and absf(grip_power - grip_target) <= grip_window and absf(balance - balance_target) <= balance_window

func hold_effort(id: int, hand: int, quality: float) -> float:
	var span: Vector3 = Vector3(_hold(id).position) - climber.get_reach_origin()
	var info: Dictionary = hold_reach_info(id, hand)
	var cross_body: bool = (hand == 0 and span.x > 0.55) or (hand == 1 and span.x < -0.55)
	var repeat_cost: float = 1.5 if hand == _grip_hand_history else 0.0
	var kind: String = str(_hold(id).get("kind", "normal"))
	var terrain_cost: float = 0.3 if kind == "small" else (4.0 if kind == "wet" and chalk_protection <= 0.0 else 0.0)
	# Authored step cost is the baseline; actual shoulder motion adds or saves effort.
	var neutral_distance: float = climber.get_shoulder_position(hand, 0.0).distance_to(Vector3(info.target))
	var extension: float = maxf(0.0, span.length() + float(info.distance) - neutral_distance)
	var alignment: float = 1.0 - clampf(absf(balance - float(info.target_balance)) / 0.60, 0.0, 1.0)
	var leg_assist: float = alignment * 0.45 if bool(info.support_ok) else 0.0
	return terrain_cost + 4.0 + extension * 2.2 + (2.5 if cross_body else 0.0) + repeat_cost + (1.0 - clampf(quality, 0.0, 1.0)) * 3.0 - leg_assist

func _release_grip(hand: int) -> void:
	if mode != "playing" or not grip_active or hand != grip_hand:
		return
	if not grip_ready():
		var foot: int = int(_hold(grip_id).get("support", -1))
		if foot >= 0 and selected_support != foot:
			_fail_grip("支撑脚没有选稳：Q 左脚 / E 右脚")
			return
		if str(_hold(grip_id).get("kind", "")) == "wind" and wind_strength >= 0.72:
			_fail_grip("阵风正强，先等待飘带落下再出手")
			return
		if not grip_reach_ready():
			_fail_grip("身体还没移到位，手还够不到岩点")
			return
		_fail_grip("重心没有稳住" if absf(balance - balance_target) > balance_window else "松手时机不对")
		return
	var power_error: float = absf(grip_power - grip_target) / grip_window
	var weight_error: float = absf(balance - balance_target) / balance_window
	last_quality = clampf(1.0 - power_error * 0.55 - weight_error * 0.45, 0.0, 1.0)
	var id: int = grip_id
	var effort: float = hold_effort(id, hand, last_quality)
	var reach_info: Dictionary = hold_reach_info(id, hand)
	_cancel_grip()
	climber.set_support_foot(selected_support)
	if climber.climb_to(_hold(id), hand, effort):
		precise_streak = precise_streak + 1 if last_quality >= 0.65 else 0
		best_precise_streak = maxi(best_precise_streak, precise_streak)
		current_rest = false
		rest_feedback_time = 0.0
		_move_voice_distance = float(reach_info.distance)
		_move_voice_limit = float(reach_info.max_distance)
		_sync_climbing_audio()
		last_hand = hand
		_grip_hand_history = hand
		slip_streak = 0
		sound.play_grip()
		show_toast("稳稳抓住" if last_quality > 0.65 else "抓住了，再稳一点", "本次握力消耗 %.1f · 远点、跨手和连续同手更费力。" % effort, 1.7)
	else:
		show_toast("握力不足以拉起身体", "空格使用镁粉，或 R 返回安全锚点。", 2.5)

func _cancel_grip() -> void:
	grip_active = false
	grip_id = -1
	grip_time = 0.0
	grip_power = 0.0

func _fail_grip(reason: String) -> void:
	_last_grip_failure = reason
	precise_streak = 0
	_cancel_grip()
	slip_streak += 1
	last_quality = 0.0
	_slip_cooldown = 0.35
	climber.stamina = maxf(0.0, climber.stamina - 11.0)
	if slip_streak >= 3 or climber.stamina <= 0.0:
		_on_fell()
	else:
		sound.play_fall()
		show_toast(reason, "失手 %d/3 · 握力 -11。按住鼠标，用 A/D 对准重心绿区，再看蓄力松手。" % slip_streak, 4.0)

func use_chalk() -> bool:
	if mode != "playing" or grip_active or climber.moving:
		return false
	if play_style == "challenge" and challenge_index == 1:
		show_toast("横渡练习 · 无镁粉", "选好支撑脚，在中间岩台恢复握力。", 3.0)
		return false
	if chalk_charges <= 0:
		show_toast("镁粉用完了", "到达安全锚点可以补满；极限模式每段仅两次。", 2.8)
		return false
	if climber.chalk():
		chalk_charges -= 1
		chalk_used += 1
		chalk_protection = 18.0
		sound.play_chalk()
		show_toast("拍掉湿气，重新抓握", "握力 +10 · 防湿 18 秒 · 剩余 %d 次；锚点补满。" % chalk_charges, 2.3)
		return true
	show_toast("先让手指缓一缓", "镁粉需要 7 秒后才能再次使用。", 2.0)
	return false

func _reset_controls() -> void:
	_cancel_grip()
	balance = 0.0
	balance_target = 0.0
	chalk_charges = chalk_capacity()
	chalk_protection = 0.0
	selected_support = -1
	climber.set_support_foot(-1)
	climber.set_lean(0.0)
	climber.terrain_drain = 0.0
	slip_streak = 0
	preview_id = -1
	last_quality = 0.0
	_grip_hand_history = -1
	_slip_cooldown = 0.0
	rest_feedback_time = 0.0
	_move_voice_distance = 0.0

func _on_reached(id: int) -> void:
	var hold: Dictionary = _hold(id)
	balance = 0.0
	climber.set_lean(0.0)
	current_rest = bool(hold.rest)
	_sync_climbing_audio()
	# Keep recovery feedback in the grip meter, even if a discovery replaces the toast.
	if current_rest and id > 0 and id < world.holds.size() - 1 and not visited.has(id):
		rest_feedback_time = 4.0
		rest_feedback_stamina = climber.stamina
		sound.play_recovery(bool(hold.checkpoint))
	highest = maxf(highest, float(hold.position.y))
	if bool(hold.checkpoint):
		chalk_charges = chalk_capacity()
		checkpoint = id
		if _auto_test:
			print("QA_ANCHOR ", id, " y=", hold.position.y)
		climber.checkpoint_position = hold.position
		climber.checkpoint_hold_id = id
		if not visited.has(id):
			show_toast("安全锚点 · 已抵达", "留在这里喘口气，握力会自动恢复。" + ("进度已保存。" if play_style == "journey" else "绳索已固定。"), 4.5)
		_save_progress()
	elif current_rest and not visited.has(id):
		show_toast("踩稳了，歇一口气", "这一段完成了。放松双肩，握力正在恢复。", 3.2)
	visited[id] = true
	var found: String = str(hold.get("collectible", ""))
	if not found.is_empty() and found not in run_collections:
		run_collections.append(found)
		world.mark_collectible_collected(found)
		var collections: Dictionary = save_data.get("collections", {})
		collections[found] = true
		save_data["collections"] = collections
		_write_save()
		show_toast("发现山路记录", "已收进登山日志。探索另一条分支，可以补全这座山的足迹。", 4.0)
	var next_chapter: int = mini(4, int(highest / route_height * 4.0))
	if next_chapter > chapter:
		chapter = next_chapter
		if chapter < 4:
			show_toast(CHAPTERS[chapter], terrain_hint(), 5.0)
	if id == world.holds.size() - 1:
		_finish()

func _on_fell(reason: String = "") -> void:
	if mode != "playing":
		return
	falls += 1
	fall_time = 0.0
	fall_title = "先退一步，再向上。" if reason == "主动返回" else "这一步，没能抓稳。"
	if reason == "主动返回":
		fall_reason = "沿安全绳返回，给双手一点喘息的时间。"
	elif slip_streak >= 3:
		fall_reason = "连续三次失手，安全绳接住了你。" + _last_grip_failure
	else:
		fall_reason = "握力耗尽，安全绳接住了你。小抓点不宜久留，可改走有岩台的绕行。"
	_cancel_grip()
	mode = "fallen"
	rest_feedback_time = 0.0
	toast_time = 0.0
	climber.process_mode = Node.PROCESS_MODE_DISABLED
	sound.play_fall()
	_save_progress()
	hud.refresh_buttons()

func retry_after_fall() -> void:
	# A short guard stops the release/click that caused the fall from dismissing it.
	if mode != "fallen" or fall_time < 0.6:
		return
	if play_style == "challenge":
		start_climb(false)
		return
	_reset_controls()
	climber.recover()
	climber.climbing = true
	climber.process_mode = Node.PROCESS_MODE_INHERIT
	current_rest = true
	mode = "playing"
	_sync_climbing_audio()
	_camera_ready = false
	_update_reachable()
	hud.refresh_buttons()
	show_toast("重新站稳，再向上。", "已回到山脚营地。先稳住重心，再把握松手时机。" if checkpoint == 0 else "已回到最近的安全锚点，之前的攀登进度仍然保留。", 4.0)

func _save_progress() -> void:
	if play_style != "journey":
		return
	save_data["version"] = 3
	save_data["route"] = route_index
	save_data["checkpoint"] = checkpoint
	save_data["elapsed"] = elapsed
	save_data["falls"] = falls
	save_data["moves"] = climber.total_moves
	save_data["chalk_used"] = chalk_used
	save_data["run_collections"] = run_collections.duplicate()
	save_data["in_progress"] = true
	_write_save()

func _finish() -> void:
	if mode == "summit":
		return
	_cancel_grip()
	rest_feedback_time = 0.0
	mode = "summit"
	summit_time = 0.0
	_summit_buttons_ready = false
	climber.celebrate(world.get_summit_position())
	sound.play_summit()
	toast_time = 0.0
	var success: bool = true
	if play_style == "challenge":
		success = best_precise_streak >= 5 if challenge_index == 0 else (chalk_used == 0 if challenge_index == 1 else falls == 0)
	result_title = ("岩段挑战完成" if success else "抵达终点，再精进一点") if play_style == "challenge" else ["松风为你停留。", "回声终于有了回答。", "你站在了云海之上。"][route_index]
	result_detail = "%s · %s · 跌落 %d 次 · %d 次抓握" % [active_route.name, time_string(elapsed), falls, climber.total_moves]
	if play_style == "challenge" and not success:
		result_detail = "本次连续精准 %d / 5；完成整段并连续五次精准抓握即可获得纪念章。" % best_precise_streak
	var key: String = "challenge_%d" % challenge_index if play_style == "challenge" else "%s_%s" % [Routes.IDS[route_index], play_style]
	var records: Dictionary = save_data.get("records", {})
	var record: Dictionary = records.get(key, {})
	if success:
		record["completions"] = int(record.get("completions", 0)) + 1
		if float(record.get("best", 0.0)) <= 0.0 or elapsed < float(record.best):
			record["best"] = elapsed
		record["first_date"] = record.get("first_date", Time.get_date_string_from_system())
		record["last_date"] = Time.get_date_string_from_system()
		records[key] = record
		save_data["records"] = records
		_add_badge("岩段练习生" if play_style == "challenge" else "群山之上")
		if falls == 0:
			_add_badge("稳如磐石")
		if chalk_charges > 0:
			_add_badge("留有余力")
		if play_style != "challenge":
			var completed: Dictionary = save_data.get("completed_routes", {})
			completed[str(route_index)] = true
			save_data["completed_routes"] = completed
			if route_index == 2:
				_add_badge("云海来客")
			if play_style == "extreme":
				_add_badge("孤峰行者")
			var count: int = 0
			for collected in save_data.get("collections", {}):
				if str(collected).begins_with(str(Routes.IDS[route_index])):
					count += 1
			if count >= 6:
				_add_badge("山路熟客")
			elif count > 0:
				_add_badge("另辟蹊径")
			save_data["summits"] = int(save_data.get("summits", 0)) + 1
			var best: float = float(save_data.get("best_time", 0.0))
			if elapsed < best or best <= 0.0:
				save_data["best_time"] = elapsed
			if falls == 0:
				save_data["clean_ascent"] = true
	if play_style == "journey":
		save_data["in_progress"] = false
	_write_save()
	_save_postcard_record()
	hud.refresh_buttons()

func toggle_pause() -> void:
	if mode == "playing":
		_cancel_grip()
		mode = "paused"
		climber.process_mode = Node.PROCESS_MODE_DISABLED
	elif mode == "paused":
		mode = "playing"
		climber.process_mode = Node.PROCESS_MODE_INHERIT
	_sync_climbing_audio()
	hud.refresh_buttons()

func return_menu() -> void:
	_reset_controls()
	sound.reset_ascent()
	if mode == "playing" or mode == "paused" or mode == "fallen":
		_save_progress()
	mode = "menu"
	help_open = false
	climber.process_mode = Node.PROCESS_MODE_INHERIT
	climber.setup(world.holds[0])
	climber.climbing = false
	climber.summit_mode = false
	hud.refresh_buttons()

func toggle_audio() -> void:
	muted = not muted
	sound.set_muted(muted)
	hud.refresh_buttons()

func toggle_help() -> void:
	help_open = not help_open
	_sync_climbing_audio()
	hud.refresh_buttons()

func quit_game() -> void:
	if mode == "quitting":
		return
	if mode == "playing" or mode == "paused" or mode == "fallen":
		_save_progress()
	mode = "quitting"
	climber.climbing = false
	sound.shutdown()
	await get_tree().create_timer(0.3).timeout
	get_tree().quit()

func show_toast(title: String, subtitle: String, seconds: float = 3.5) -> void:
	toast = title
	toast_sub = subtitle
	toast_time = seconds

func time_string(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds) / 60, int(seconds) % 60]

func _run_qa(delta: float) -> void:
	_auto_timer += delta
	if _auto_timer > 420.0:
		push_error("QA_TIMEOUT at hold %d, reachable %s" % [climber.current_hold_id, str(reachable)])
		get_tree().quit(2)
	if climber.moving:
		_qa_idle = 0.0
		return
	if grip_active:
		if grip_ready():
			_release_grip(grip_hand)
		return
	_qa_idle += delta
	if current_rest and climber.stamina < 96.0:
		return
	if _qa_idle > 0.18:
		if climber.stamina < 24.0:
			use_chalk()
		var id: int = next_hold_id()
		if id >= 0:
			select_support(int(_hold(id).get("support", -1)))
			if str(_hold(id).get("kind", "")) == "wind" and wind_strength > 0.40:
				return
			var hand: int = recommended_hand(id)
			attempt_hold(id, hand)
		_qa_idle = 0.0




func route_info() -> Dictionary:
	return Routes.info(route_index)

func route_unlocked(index: int) -> bool:
	if index == 0:
		return true
	var completed: Dictionary = save_data.get("completed_routes", {})
	return bool(completed.get(str(index - 1), false)) or (index == 1 and int(save_data.get("summits", 0)) > 0)

func extreme_unlocked() -> bool:
	return bool(save_data.get("completed_routes", {}).get(str(route_index), false)) or (route_index == 0 and int(save_data.get("summits", 0)) > 0)

func _build_selected_world() -> void:
	if is_instance_valid(world):
		remove_child(world)
		world.free()
	active_route = Routes.build(route_index, play_style, challenge_index)
	CHAPTERS.assign([
		["起攀 · 松风营地", "林间 · 晨光岩台", "分岔 · 旧路足迹", "山脊 · 松涛渐远", "终点 · 松风岩脊"],
		["起攀 · 峡谷入口", "横渡 · 两壁回声", "湿壁 · 飞瀑水汽", "出谷 · 天光渐近", "终点 · 回声峡谷"],
		["起攀 · 雪岭营地", "岩阶 · 寒风初起", "山脊 · 阵风间隙", "云上 · 最后的攀登", "终点 · 云上孤峰"]
	][route_index])
	if play_style == "challenge":
		CHAPTERS.assign([str(active_route.name), "观察 · 选择落点", "练习 · 调整姿态", "稳住 · 最后几步", "完成 · 岩段挑战"])
	route_height = float(active_route.height)
	world = WorldScript.new()
	add_child(world)
	world.build_world(active_route)
	for found in save_data.get("collections", {}):
		world.mark_collectible_collected(str(found))
	wind_strength = 0.0
	sound.set_route_theme((1 if challenge_index > 0 else 0) if play_style == "challenge" else route_index)
	sound.set_wind_strength(0.0)
	climber.setup(world.holds[0])
	climber.set_outfit(outfit_index)
	_camera_ready = false

func select_route(index: int) -> void:
	if mode != "menu":
		return
	route_index = clampi(index, 0, 2)
	_build_selected_world()
	hud.refresh_buttons()

func select_style(style: String) -> void:
	if mode != "menu" or style not in ["journey", "challenge", "extreme"]:
		return
	play_style = style
	_build_selected_world()
	hud.refresh_buttons()

func select_challenge(index: int) -> void:
	if mode != "menu":
		return
	challenge_index = clampi(index, 0, 2)
	_build_selected_world()
	hud.refresh_buttons()

func continue_journey() -> void:
	start_climb(true)

func select_support(index: int) -> void:
	if climber.moving:
		return
	selected_support = clampi(index, -1, 1)
	climber.set_support_foot(selected_support)
	_refresh_grip_geometry()
	_update_reachable()

func chalk_capacity() -> int:
	return 2 if play_style == "extreme" else 3

func challenge_goal_text() -> String:
	if play_style == "challenge":
		return ["连续 5 次精准抓握并抵达终点 · 当前最佳 %d/5" % best_precise_streak, "不使用镁粉完成横渡 · Q 左支撑 / E 右支撑", "零跌落通过湿壁 · 镁粉防湿 18 秒"][challenge_index]
	if play_style == "extreme":
		return "极限登顶 · 每段 2 次镁粉 · 仅半山锚点 · 本地独立纪录"
	return "观察分岔 · 绕行可休息 · 捷径需连攀"

func terrain_hint() -> String:
	var id: int = grip_id if grip_active else hovered_id
	if id < 0:
		id = climber.current_hold_id
	var hold: Dictionary = _hold(id)
	var foot: int = int(hold.get("support", -1))
	if foot >= 0:
		return "横渡 · 先按 " + ("Q 选左脚支撑" if foot == 0 else "E 选右脚支撑") + "，再移重心、伸手"
	match str(hold.get("kind", "normal")):
		"wet":
			return "湿壁 · 镁粉保护剩余 %.0f 秒" % chalk_protection if chalk_protection > 0.0 else "湿壁 · 握力消耗增加；空格镁粉可防湿 18 秒"
		"small":
			return "小抓点 · 悬停更费握力，提前看好下一步"
		"wind":
			return "阵风正强 · 贴壁等待，飘带垂下再出手" if wind_strength >= 0.72 else "风势减弱 · 稳住重心，趁间隙攀登"
	if current_rest and reachable.size() > 1:
		return "前方分岔 · 左侧绕行有休息点，右侧捷径连续发力"
	return "岩台可以恢复握力；观察下一段，再决定走法" if current_rest else "交替用手、选择近点，让握力留得更久"

func _add_badge(badge: String) -> void:
	if badge not in earned_badges:
		earned_badges.append(badge)
	var badges: Dictionary = save_data.get("badges", {})
	badges[badge] = Time.get_date_string_from_system()
	save_data["badges"] = badges

func open_journal() -> void:
	if mode != "menu":
		return
	mode = "journal"
	hud.refresh_buttons()

func close_journal() -> void:
	mode = "menu"
	hud.refresh_buttons()

func cycle_outfit() -> void:
	var unlocked: int = 1
	if int(save_data.get("summits", 0)) > 0 or save_data.get("collections", {}).size() >= 2:
		unlocked = 2
	if save_data.get("completed_routes", {}).size() >= 3 or save_data.get("collections", {}).size() >= 6:
		unlocked = 3
	outfit_index = (outfit_index + 1) % unlocked
	climber.set_outfit(outfit_index)
	save_data["outfit"] = outfit_index
	_write_save()
	show_toast(["落日橙", "松林绿", "冰川蓝"][outfit_index], "收集 2 / 6 份山路记录，可解锁更多服装与背包配色。", 4.0)
	hud.refresh_buttons()

func journal_lines() -> Array[String]:
	var lines: Array[String] = ["登山日志  /  你的每一步，都留下山痕", ""]
	var records: Dictionary = save_data.get("records", {})
	for i in range(3):
		lines.append(ROUTE_NAMES[i] + (" · 已开启" if route_unlocked(i) else " · 完成前一座山后开启"))
		for style: String in ["journey", "extreme"]:
			var record: Dictionary = records.get("%s_%s" % [Routes.IDS[i], style], {})
			var label: String = "旅程" if style == "journey" else "极限"
			lines.append("  %s：%s" % [label, "尚未登顶" if record.is_empty() else "登顶 %d 次 · 最佳 %s · 首登 %s" % [record.completions, time_string(float(record.best)), record.first_date]])
		var count: int = 0
		for item in save_data.get("collections", {}):
			if str(item).begins_with(str(Routes.IDS[i])):
				count += 1
		lines.append("  山路记录 %d / 6 · 绕行与捷径各有三处足迹" % count)
		lines.append("")
	for i in range(3):
		var record: Dictionary = records.get("challenge_%d" % i, {})
		lines.append("挑战 · %s：%s" % [Routes.CHALLENGES[i], "等待挑战" if record.is_empty() else "完成 %d 次 · 最佳 %s" % [record.completions, time_string(float(record.best))]])
	lines.append("")
	lines.append("纪念章：" + ("尚未获得" if save_data.get("badges", {}).is_empty() else "、".join(save_data.get("badges", {}).keys())))
	lines.append("配色：收集 2 份记录解锁松林绿，6 份记录解锁冰川蓝。")
	lines.append("纪念卡：每次完成都会保留文字记录；结算页可保存带风景的图片。")
	for item in save_data.get("collections", {}):
		var pieces: PackedStringArray = str(item).split("_")
		if pieces.size() == 3:
			var r: int = Routes.IDS.find(pieces[0])
			if r >= 0:
				lines.append("拾得 · %s 第%d段 · %s" % [ROUTE_NAMES[r], int(pieces[1]) + 1, "岩台上的旧登山笔记：慢一点，山会等你。" if pieces[2] == "safe" else "捷径石堆旁的刻痕：稳住下一步，再看远方。"])
	return lines

func _save_postcard_record() -> void:
	if _auto_test or "--qa-capture" in OS.get_cmdline_user_args():
		return
	var folder: String = _data_path("postcards")
	DirAccess.make_dir_recursive_absolute(folder)
	var filename: String = "%s_%s_%d.txt" % [str(active_route.id), play_style, Time.get_unix_time_from_system()]
	var file := FileAccess.open(folder.path_join(filename), FileAccess.WRITE)
	if file:
		file.store_string("山痕 · 登顶纪念\n" + result_title + "\n" + result_detail + "\n" + Time.get_datetime_string_from_system() + "\n纪念章：" + "、".join(earned_badges) + "\n走过的分支：" + "、".join(run_collections))

func export_postcard() -> void:
	if mode != "summit":
		return
	await RenderingServer.frame_post_draw
	var folder: String = _data_path("postcards")
	DirAccess.make_dir_recursive_absolute(folder)
	var filename: String = "%s_%s_%d.png" % [str(active_route.id), play_style, Time.get_unix_time_from_system()]
	var target: String = folder.path_join(filename)
	var error: Error = get_viewport().get_texture().get_image().save_png(target)
	if error == OK:
		postcard_path = target
		hud.refresh_buttons()

func open_postcards() -> void:
	var folder: String = _data_path("postcards")
	DirAccess.make_dir_recursive_absolute(folder)
	OS.shell_open(folder)


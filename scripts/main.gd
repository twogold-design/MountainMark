extends Node3D
## Mountain Mark: a complete single-route climbing journey.
const WorldScript = preload("res://scripts/world.gd")
const ClimberScript = preload("res://scripts/climber.gd")
const AudioScript = preload("res://scripts/audio.gd")
const HudScript = preload("res://scripts/hud.gd")
const REACH: float = 3.05
const HEIGHT: float = 72.0
const CHAPTERS: Array[String] = ["起攀 · 松风岩脚", "第一段 · 风蚀石阶", "第二段 · 云间横渡", "第三段 · 天光之脊", "终点 · 群山之上"]
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
var current_rest: bool = true
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
var _auto_test: bool = false
var _auto_timer: float = 0.0
var _qa_idle: float = 0.0
var _save_path: String
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
	world.build_world()
	climber = ClimberScript.new()
	add_child(climber)
	climber.setup(world.holds[0])
	climber.reached_hold.connect(_on_reached)
	climber.fell.connect(_on_fell)
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
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and grip_active:
		_cancel_grip()
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()

func _process(delta: float) -> void:
	clock_time += delta
	toast_time = maxf(0.0, toast_time - delta)
	if mode == "playing":
		elapsed += delta
		if current_rest and not climber.moving and not grip_active:
			climber.rest(delta)
		var lean: float = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		if _auto_test and grip_active:
			lean = clampf((balance_target - balance) * 8.0, -1.0, 1.0)
		_tick_control(delta, lean)
		_update_reachable()
		_update_hover()
		if _auto_test:
			_run_qa(delta)
	elif mode == "fallen":
		fall_time += delta
	elif mode == "summit":
		summit_time += delta
		if _auto_test and summit_time > 3.0:
			print("QA_SUCCESS summit reached; moves=", climber.total_moves, "; falls=", falls, "; checkpoints=", checkpoint)
			_auto_test = false
			quit_game()
	var altitude: float = clampf((climber.get_reach_origin().y - 1.0) / HEIGHT, 0.0, 1.0)
	world.update_atmosphere(altitude, delta)
	sound.set_altitude(altitude)
	_update_camera(delta)
	hud.queue_redraw()

func _update_camera(delta: float) -> void:
	var body: Vector3 = climber.get_body_position()
	var target: Vector3 = body + Vector3(1.45, 1.0, -0.4)
	var desired: Vector3 = body + Vector3(6.0, 1.5, 10.0)
	if mode == "menu":
		target = Vector3(-2.6, 7.0, 0.0)
		desired = Vector3(9.0 + sin(clock_time * 0.07) * 0.8, 10.0, 22.0)
	elif mode == "summit":
		var progress: float = smoothstep(0.0, 9.0, summit_time)
		var summit: Vector3 = world.get_summit_position()
		target = body.lerp(summit + Vector3(0.0, 1.0, 0.0), progress * 0.7)
		desired = body + Vector3(lerpf(1.0, 12.0, progress), lerpf(1.5, 6.0, progress), lerpf(9.0, 20.0, progress))
	else:
		desired += Vector3(sin(clock_time * 0.75) * 0.022, sin(clock_time * 1.15) * 0.025, 0.0)
	if not _camera_ready:
		camera.position = desired
		_camera_ready = true
	else:
		camera.position = camera.position.lerp(desired, 1.0 - exp(-delta * 3.5))
	if camera.position.distance_to(target) > 0.1:
		camera.look_at(target, Vector3.UP)

func start_climb(resume: bool = false) -> void:
	sound.reset_ascent()
	_reset_controls()
	mode = "playing"
	help_open = false
	climber.process_mode = Node.PROCESS_MODE_INHERIT
	climber.summit_mode = false
	var start_id: int = 0
	elapsed = 0.0
	falls = 0
	highest = 0.0
	checkpoint = 0
	chapter = 0
	visited.clear()
	if resume:
		start_id = int(save_data.get("checkpoint", 0))
		elapsed = float(save_data.get("elapsed", 0.0))
		falls = int(save_data.get("falls", 0))
		if start_id >= world.holds.size():
			start_id = 0
	var hold: Dictionary = _hold(start_id)
	climber.setup(hold)
	climber.total_moves = int(save_data.get("moves", 0)) if resume else 0
	climber.climbing = true
	checkpoint = start_id
	climber.checkpoint_hold_id = start_id
	climber.checkpoint_position = hold.position
	current_rest = bool(hold.rest)
	highest = float(hold.position.y)
	chapter = mini(4, int(highest / 18.0))
	_camera_ready = false
	_update_reachable()
	hud.refresh_buttons()
	show_toast("每一次向上，都算数。", "按住岩点 → A/D 稳住重心 → 两条绿区同时满足时松手。", 9.0)

func _hold(id: int) -> Dictionary:
	for hold: Dictionary in world.holds:
		if int(hold.id) == id:
			return hold
	return world.holds[0]

func _update_reachable() -> void:
	reachable.clear()
	var origin: Vector3 = climber.get_reach_origin()
	for hold: Dictionary in world.holds:
		var p: Vector3 = hold.position
		if int(hold.id) == climber.current_hold_id:
			continue
		if origin.distance_to(p) <= REACH and p.y > origin.y - 0.8:
			reachable.append(int(hold.id))
	world.set_hold_feedback(reachable, grip_id if grip_active else (hovered_id if hovered_id >= 0 else preview_id), climber.current_hold_id)

func _update_hover() -> void:
	hovered_id = -1
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var best: float = 44.0
	for id: int in reachable:
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
	if event is InputEventMouseButton and mode == "playing":
		if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT:
			return
		var hand: int = 0 if event.button_index == MOUSE_BUTTON_LEFT else 1
		if not event.pressed:
			_release_grip(hand)
		elif not grip_active and not climber.moving:
			_update_hover()
			if hovered_id >= 0:
				attempt_hold(hovered_id, hand)
			else:
				show_toast("先选一处落手点", "对准发光岩点，按住左键或右键。W 只观察路线，不会自动攀爬。", 2.5)

func next_hold_id() -> int:
	var origin: Vector3 = climber.get_reach_origin()
	var best_score: float = INF
	var best_id: int = -1
	for id: int in reachable:
		var hold: Dictionary = _hold(id)
		var p: Vector3 = hold.position
		if p.y < origin.y + 0.45:
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
	show_toast("观察，不等于迈步", "已标记较近的上行岩点。需要亲自按住鼠标，配合 A/D 和松手时机。", 3.0)

func attempt_hold(id: int, hand: int = 0) -> void:
	if mode != "playing" or climber.moving or grip_active or _slip_cooldown > 0.0 or id not in reachable:
		return
	grip_id = id
	grip_hand = clampi(hand, 0, 1)
	grip_time = 0.0
	grip_power = 0.0
	preview_id = -1
	var hold: Dictionary = _hold(id)
	var span: Vector3 = Vector3(hold.position) - climber.get_reach_origin()
	var altitude: float = clampf(float(hold.position.y) / HEIGHT, 0.0, 1.0)
	var long_reach: float = clampf((span.length() - 1.4) / 1.6, 0.0, 1.0)
	grip_target = 0.57 + long_reach * 0.13 + float(id % 3) * 0.035
	grip_window = lerpf(0.16, 0.10, altitude) - long_reach * 0.015
	balance_target = clampf(span.x * 0.48 + (-0.24 if grip_hand == 0 else 0.24) + sin(float(hold.position.y) * 0.21) * 0.16, -0.80, 0.80)
	balance_window = lerpf(0.30, 0.20, altitude) - long_reach * 0.025
	if climber.stamina < hold_effort(id, grip_hand, 0.0):
		grip_id = -1
		show_toast("这一步需要更多握力", "选择更近的岩点，或空格使用镁粉。金色岩点可以休息。", 3.0)
		return
	grip_active = true
	toast_time = 0.0

func _grip_power_at(seconds: float) -> float:
	return 0.5 - 0.5 * cos(seconds * TAU / 2.2)

func _tick_control(delta: float, axis: float) -> void:
	_slip_cooldown = maxf(0.0, _slip_cooldown - delta)
	if climber.moving:
		return
	var wind: float = sin(clock_time * 1.3 + float(climber.current_hold_id)) * (0.025 + highest / HEIGHT * 0.08)
	balance = clampf(balance + (axis * 1.25 + (wind if grip_active else 0.0)) * delta, -1.0, 1.0)
	climber.set_lean(balance)
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
	return grip_active and grip_time >= 0.2 and grip_time < 4.5 and absf(grip_power - grip_target) <= grip_window and absf(balance - balance_target) <= balance_window

func hold_effort(id: int, hand: int, quality: float) -> float:
	var span: Vector3 = Vector3(_hold(id).position) - climber.get_reach_origin()
	var cross_body: bool = (hand == 0 and span.x > 0.55) or (hand == 1 and span.x < -0.55)
	var repeat_cost: float = 1.5 if hand == _grip_hand_history else 0.0
	return 4.0 + span.length() * 2.2 + (2.5 if cross_body else 0.0) + repeat_cost + (1.0 - clampf(quality, 0.0, 1.0)) * 3.0

func _release_grip(hand: int) -> void:
	if mode != "playing" or not grip_active or hand != grip_hand:
		return
	if not grip_ready():
		_fail_grip("重心没有稳住" if absf(balance - balance_target) > balance_window else "松手时机不对")
		return
	var power_error: float = absf(grip_power - grip_target) / grip_window
	var weight_error: float = absf(balance - balance_target) / balance_window
	last_quality = clampf(1.0 - power_error * 0.55 - weight_error * 0.45, 0.0, 1.0)
	var id: int = grip_id
	var effort: float = hold_effort(id, hand, last_quality)
	_cancel_grip()
	if climber.climb_to(_hold(id), hand, effort):
		current_rest = false
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
	if chalk_charges <= 0:
		show_toast("镁粉用完了", "本段只有三次补粉。到达安全锚点可以补满。", 2.8)
		return false
	if climber.chalk():
		chalk_charges -= 1
		sound.play_chalk()
		show_toast("拍掉湿气，重新抓握", "握力 +10 · 剩余镁粉 %d/3；到安全锚点补满。" % chalk_charges, 2.3)
		return true
	show_toast("先让手指缓一缓", "镁粉需要 7 秒后才能再次使用。", 2.0)
	return false

func _reset_controls() -> void:
	_cancel_grip()
	balance = 0.0
	balance_target = 0.0
	chalk_charges = 3
	slip_streak = 0
	preview_id = -1
	last_quality = 0.0
	_grip_hand_history = -1
	_slip_cooldown = 0.0

func _on_reached(id: int) -> void:
	var hold: Dictionary = _hold(id)
	current_rest = bool(hold.rest)
	highest = maxf(highest, float(hold.position.y))
	if bool(hold.checkpoint):
		chalk_charges = 3
		checkpoint = id
		if _auto_test:
			print("QA_ANCHOR ", id, " y=", hold.position.y)
		climber.checkpoint_position = hold.position
		climber.checkpoint_hold_id = id
		if not visited.has(id):
			sound.play_checkpoint()
			show_toast("安全锚点 · 已抵达", "留在这里喘口气，握力会自动恢复。进度已保存。", 4.5)
		_save_progress()
	elif current_rest and not visited.has(id):
		show_toast("找到了休息点", "放松双肩。停留即可恢复握力。", 3.2)
	visited[id] = true
	var next_chapter: int = mini(4, int(highest / 18.0))
	if next_chapter > chapter:
		chapter = next_chapter
		if chapter < 4:
			show_toast(CHAPTERS[chapter], ["", "风从岩缝穿过。脚下的路，已经很远。", "云层沉到身后。只听见自己的呼吸。", "最后一段。光就在山脊的另一侧。"][chapter], 5.0)
	if highest >= HEIGHT - 0.3:
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
		fall_reason = "连续三次失手，安全绳接住了你。"
	else:
		fall_reason = "握力耗尽，安全绳接住了你。"
	_cancel_grip()
	mode = "fallen"
	toast_time = 0.0
	climber.process_mode = Node.PROCESS_MODE_DISABLED
	sound.play_fall()
	_save_progress()
	hud.refresh_buttons()

func retry_after_fall() -> void:
	# A short guard stops the release/click that caused the fall from dismissing it.
	if mode != "fallen" or fall_time < 0.6:
		return
	_reset_controls()
	climber.recover()
	climber.climbing = true
	climber.process_mode = Node.PROCESS_MODE_INHERIT
	current_rest = true
	mode = "playing"
	_camera_ready = false
	_update_reachable()
	hud.refresh_buttons()
	show_toast("重新站稳，再向上。", "已回到山脚营地。先稳住重心，再把握松手时机。" if checkpoint == 0 else "已回到最近的安全锚点，之前的攀登进度仍然保留。", 4.0)

func _save_progress() -> void:
	save_data["checkpoint"] = checkpoint
	save_data["elapsed"] = elapsed
	save_data["falls"] = falls
	save_data["moves"] = climber.total_moves
	save_data["in_progress"] = true
	_write_save()

func _finish() -> void:
	if mode == "summit":
		return
	_cancel_grip()
	mode = "summit"
	summit_time = 0.0
	climber.celebrate(world.get_summit_position())
	sound.play_summit()
	toast_time = 0.0
	save_data["summits"] = int(save_data.get("summits", 0)) + 1
	save_data["in_progress"] = false
	var best: float = float(save_data.get("best_time", 0.0))
	if elapsed < best or best <= 0.0:
		save_data["best_time"] = elapsed
	if falls == 0:
		save_data["clean_ascent"] = true
	_write_save()
	hud.refresh_buttons()

func toggle_pause() -> void:
	if mode == "playing":
		_cancel_grip()
		mode = "paused"
		climber.process_mode = Node.PROCESS_MODE_DISABLED
	elif mode == "paused":
		mode = "playing"
		climber.process_mode = Node.PROCESS_MODE_INHERIT
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
			var hand: int = 0 if Vector3(_hold(id).position).x < climber.get_reach_origin().x else 1
			attempt_hold(id, hand)
		_qa_idle = 0.0




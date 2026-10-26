extends SceneTree
## Global immersion shortcut, actual viewport input, and read-only player saves.
var game: Node3D
var test_view: SubViewport
var checks: int = 0
var failures: Array[String] = []
var player_saves: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func verify(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures.append(label)

func key_event(physical: int, logical: int = 0, character: int = 0) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = physical
	event.keycode = logical
	event.unicode = character
	event.pressed = true
	return event

func push(event: InputEventKey) -> void:
	test_view.push_input(event, true)

func tap(physical: int = KEY_QUOTELEFT, logical: int = KEY_QUOTELEFT, character: int = 96) -> void:
	var event: InputEventKey = key_event(physical, logical, character)
	push(event)
	var release: InputEventKey = event.duplicate()
	release.pressed = false
	push(release)

func set_visible_ui(value: bool) -> void:
	if bool(game.ui_visible) != value:
		tap()

func all_rings_hidden() -> bool:
	for ring: Node3D in game.world._rings:
		if ring.is_visible_in_tree():
			return false
	return true

func ring_visibility() -> Array[bool]:
	var result: Array[bool] = []
	for ring: Node3D in game.world._rings:
		result.append(ring.is_visible_in_tree())
	return result

func hidden_hold_materials() -> bool:
	for i in range(game.world.holds.size()):
		var material: StandardMaterial3D = game.world._materials[i]
		if not material.albedo_color.is_equal_approx(game.world._hold_color(game.world.holds[i])) or not is_equal_approx(material.emission_energy_multiplier, 0.08):
			return false
	return true

func current_hold_materials() -> bool:
	var selected: int = game.grip_id if game.grip_active else (game.hovered_id if game.hovered_id >= 0 else game.preview_id)
	for i in range(game.world.holds.size()):
		var material: StandardMaterial3D = game.world._materials[i]
		var color: Color = Color("8fcdba") if i == game.climber.current_hold_id else (Color("fff5cc") if i == selected else game.world._hold_color(game.world.holds[i]))
		var emission: float = 0.5 if i == selected else (0.20 if i in game.reachable else 0.08)
		if not material.albedo_color.is_equal_approx(color) or not is_equal_approx(material.emission_energy_multiplier, emission):
			return false
	return true

func all_buttons_hidden() -> bool:
	for button: Button in game.hud.buttons:
		if button.is_visible_in_tree():
			return false
	return true

func persistent_hints_visible() -> bool:
	return game.control_hints.is_visible_in_tree()

func passive_hints() -> bool:
	return passive_control(game.control_hints)

func passive_control(layer: Control) -> bool:
	if layer.mouse_filter != Control.MOUSE_FILTER_IGNORE or layer.focus_mode != Control.FOCUS_NONE:
		return false
	for control: Control in layer.find_children("*", "Control", true, false):
		if control is BaseButton or control.focus_mode != Control.FOCUS_NONE or control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			return false
	return true

func hints_match_mode(mode: String, help: bool) -> bool:
	var lines: Array[String] = game.control_hints.get_hint_lines()
	if game.control_hints._lines != lines:
		return false
	var text: String = " ".join(lines)
	if "·" not in text:
		return false
	if help:
		return "Esc" in text and ("关闭" in text or "返回" in text)
	match mode:
		"playing":
			if not (("左键" in text and "右键" in text) or "左/右键" in text or "点住岩点" in text):
				return false
			if "回拉" not in text and "向后拉" not in text:
				return false
			for required: String in ["Q", "E", "A", "D", "W", "中键", "Z", "X", "空格", "R", "Esc"]:
				if required not in text:
					return false
			return true
		"paused": return "Esc" in text and "继续" in text
		"fallen": return "Enter" in text and ("重试" in text or "再试" in text)
		"menu": return "Enter" in text and ("开始" in text or "攀登" in text)
		"journal": return "Esc" in text and "返回" in text
		"summit": return "界面" in text or "恢复" in text
	return false

func state_snapshot() -> Dictionary:
	return {"mode": game.mode, "help": game.help_open, "grip": game.grip_active,
		"grip_id": game.grip_id, "grip_time": game.grip_time, "grip_power": game.grip_power,
		"balance": game.balance, "support": game.selected_support, "stamina": game.climber.stamina,
		"moving": game.climber.moving, "move_time": game.climber._move_time,
		"hold": game.climber.current_hold_id, "muted": game.muted,
		"climbing": game.climber.climbing, "actor_process": game.climber.process_mode,
		"readable": game.readable.duplicate(), "reachable": game.reachable.duplicate()}

func input_contract() -> void:
	set_visible_ui(true)
	var button: Button = game.hud.buttons[0]
	button.grab_focus()
	verify(test_view.gui_get_focus_owner() == button, "A menu button owns GUI focus before the global shortcut")
	tap(KEY_QUOTELEFT, KEY_B, 0xB7)
	verify(not game.ui_visible and persistent_hints_visible(), "The physical top-left key hides the main interface once and retains operating hints despite GUI focus")
	verify(test_view.gui_get_focus_owner() == null, "Hiding the interface releases its button focus")
	tap()
	verify(game.ui_visible and not persistent_hints_visible(), "One further physical key press restores the main interface and removes the duplicate hint layer")
	for code: int in [0xB7, 96]:
		tap(0, 0, code)
		verify(not game.ui_visible, "Unicode %d is accepted when no physical code is supplied" % code)
		tap()
	tap(0, KEY_QUOTELEFT, 0)
	verify(not game.ui_visible, "Logical quote-left is a fallback when the physical code is absent")
	tap()
	var shifted: InputEventKey = key_event(KEY_QUOTELEFT, KEY_QUOTELEFT, 126)
	shifted.shift_pressed = true
	push(shifted)
	verify(not game.ui_visible, "Shift with the same physical key remains a usable immersion shortcut")
	tap()
	for kind: String in ["echo", "release", "ctrl", "alt", "meta", "other physical"]:
		var event: InputEventKey = key_event(KEY_QUOTELEFT, KEY_QUOTELEFT, 0xB7)
		match kind:
			"echo": event.echo = true
			"release": event.pressed = false
			"ctrl": event.ctrl_pressed = true
			"alt": event.alt_pressed = true
			"meta": event.meta_pressed = true
			"other physical": event.physical_keycode = KEY_A
		push(event)
		verify(game.ui_visible, kind + " does not accidentally toggle the interface")
	# A hidden button must neither receive mouse input nor regain focus with Tab.
	var start_button: Button
	for candidate: Button in game.hud.buttons:
		if candidate.text.begins_with("开始攀登"):
			start_button = candidate
	verify(start_button != null, "The actual menu start button is available for the hidden click regression")
	if start_button != null:
		var click_at: Vector2 = start_button.get_global_rect().get_center()
		set_visible_ui(false)
		for pressed: bool in [true, false]:
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = pressed
			click.position = click_at
			click.global_position = click_at
			test_view.push_input(click, true)
		verify(game.mode == "menu", "Clicking the former menu button position cannot activate a hidden button")
		tap(KEY_TAB, KEY_TAB, 9)
		verify(test_view.gui_get_focus_owner() == null, "Tab cannot focus an interface hidden by the global shortcut")
	set_visible_ui(true)

func overlay_contract() -> void:
	for mode: String in ["menu", "journal", "playing", "paused", "fallen", "summit"]:
		for help: bool in [false, true]:
			game.mode = mode
			game.help_open = help
			game.summit_time = 4.1
			game.hud.refresh_buttons()
			game._sync_ui_visibility()
			var snapshot: Dictionary = state_snapshot()
			var button_count: int = game.hud.buttons.size()
			tap()
			verify(not game.ui_visible and not game.hud.is_visible_in_tree() and all_buttons_hidden() and persistent_hints_visible(), "%s / help=%s: main HUD and buttons hide while operating hints remain visible" % [mode, str(help)])
			verify(hints_match_mode(mode, help), "%s / help=%s: persistent hints describe the current controls and interface restoration" % [mode, str(help)])
			verify(state_snapshot() == snapshot, "%s / help=%s: hiding preserves gameplay and overlay state" % [mode, str(help)])
			verify(not game.grip_controls.is_visible_in_tree(), "%s / help=%s: inactive grip feedback does not leave a panel behind" % [mode, str(help)])
			game.hud.refresh_buttons()
			verify(all_buttons_hidden() and persistent_hints_visible(), "%s / help=%s: rebuilt main buttons remain hidden and operating hints remain visible" % [mode, str(help)])
			tap()
			verify(game.ui_visible and game.hud.is_visible_in_tree() and not persistent_hints_visible() and game.hud.buttons.size() == button_count and state_snapshot() == snapshot, "%s / help=%s: restoration keeps the same screen and gameplay state without duplicate hints" % [mode, str(help)])
	game.help_open = false

func begin_climb() -> void:
	game.mode = "menu"
	game.help_open = false
	game.start_climb(false)
	game.set_process(false)
	game.climber.set_process(false)
	game._update_reachable()
	game._update_camera(1.0)
	game._sync_ui_visibility()

func aim_at_grip() -> void:
	if not game.grip_active:
		return
	var aim: Dictionary = game.get_drag_aim_info()
	game.set_grip_drag(Vector2(aim.drag_anchor) - (Vector2(aim.target_screen) - Vector2(aim.origin_screen)) / float(game.DRAG_AMPLIFICATION))

func world_feedback_contract() -> void:
	begin_climb()
	game.select_support(0)
	game._process(0.0)
	var rings: Array[bool] = ring_visibility()
	var readable: Array = game.readable.duplicate()
	var reachable: Array = game.reachable.duplicate()
	verify(true in rings and game.climber._support_marker.is_visible_in_tree(), "Visible climbing begins with real reachable rings and the selected support marker")
	tap()
	game._process(0.0)
	game._update_reachable()
	game.climber._update_pose()
	verify(all_rings_hidden() and not game.climber._support_marker.is_visible_in_tree() and persistent_hints_visible(), "Frame updates keep feedback rings hidden and operating hints visible")
	verify(hidden_hold_materials(), "Hidden holds use their natural material color and baseline 0.08 emission")
	verify(game.readable == readable and game.reachable == reachable, "Hiding feedback preserves the selectable and reachable hold sets")
	tap()
	verify(ring_visibility() == rings and game.climber._support_marker.is_visible_in_tree(), "Restoring UI immediately restores the same hold rings and selected support marker")
	verify(current_hold_materials(), "Restoring UI reapplies current used and reachable material feedback")

func rebuilt_world_contract() -> void:
	set_visible_ui(false)
	var previous_world: int = game.world.get_instance_id()
	var previous_save: Dictionary = game.save_data.duplicate(true)
	game.save_data["completed_routes"] = {"0": true, "1": true}
	game.mode = "menu"
	game.select_route(1)
	game.start_climb(false)
	game.climber.set_process(false)
	game.select_support(1)
	verify(game.world.get_instance_id() != previous_world and game.route_index == 1 and game.mode == "playing", "Starting a different unlocked route rebuilds the real world")
	verify(not game.ui_visible and not game.hud.is_visible_in_tree() and all_buttons_hidden() and all_rings_hidden() and not game.climber._support_marker.is_visible_in_tree() and hidden_hold_materials() and persistent_hints_visible(), "A newly built route immediately inherits hidden HUD and markers with visible operating hints")
	game._process(0.0)
	verify(not game.hud.is_visible_in_tree() and all_rings_hidden() and not game.climber._support_marker.is_visible_in_tree() and hidden_hold_materials() and persistent_hints_visible(), "The rebuilt world's first frame retains operating hints and keeps other interface feedback hidden")
	tap()
	verify(game.hud.is_visible_in_tree() and not persistent_hints_visible() and true in ring_visibility() and game.climber._support_marker.is_visible_in_tree() and current_hold_materials(), "The shortcut restores current feedback correctly after the route rebuild")
	game.save_data = previous_save
	game.mode = "menu"
	game.select_route(0)

func controls_contract() -> void:
	begin_climb()
	var id: int = game.next_hold_id()
	verify(id >= 0, "A real first-route hold is selectable for the hidden gameplay regression")
	if id < 0:
		return
	var hand: int = game.recommended_hand(id)
	var foot: int = int(game._hold(id).get("support", -1))
	game.select_support(foot if foot >= 0 else 1 - hand)
	game.attempt_hold(id, hand)
	game._tick_control(0.1, 0.0)
	verify(game.grip_active, "Real grip preparation starts before hiding UI")
	game._sync_ui_visibility()
	verify(game.grip_controls.is_visible_in_tree() and passive_control(game.grip_controls), "Full HUD shows one passive grip component for active preparation")
	var component_id: int = game.grip_controls.get_instance_id()
	var snapshot: Dictionary = state_snapshot()
	tap()
	verify(not game.ui_visible and persistent_hints_visible() and passive_hints() and state_snapshot() == snapshot, "Hiding during grip preparation retains passive hints and preserves pressure, timing, balance, support and stamina")
	verify(game.grip_controls.is_visible_in_tree(), "Simplified interface retains the real power and balance component")
	tap()
	verify(game.ui_visible and game.grip_controls.is_visible_in_tree() and game.grip_controls.get_instance_id() == component_id and state_snapshot() == snapshot, "Restoring full HUD retains the same grip component and gameplay state")
	tap()
	var start_time: float = game.grip_time
	var start_power: float = game.grip_power
	var visible_during_preparation: bool = true
	for _tick in range(440):
		var axis: float = clampf((float(game.balance_target) - float(game.balance)) * 14.0, -1.0, 1.0)
		game._tick_control(0.01, axis)
		aim_at_grip()
		game._sync_ui_visibility()
		visible_during_preparation = visible_during_preparation and game.grip_controls.is_visible_in_tree()
		if game.grip_ready():
			break
	verify(visible_during_preparation and game.grip_time > start_time and not is_equal_approx(game.grip_power, start_power), "Live drag power and aim update while the simplified grip component stays visible")
	verify(game.grip_ready(), "Actual drag aim and weight-shift controls prepare a legal grip with the main HUD hidden")
	game._release_grip(hand)
	game._sync_ui_visibility()
	verify(not game.grip_controls.is_visible_in_tree(), "Releasing a prepared grip removes its component before climbing")
	verify(game.climber.moving and not game.ui_visible, "A prepared grip starts climbing with all UI hidden")
	game.climber._process(game.climber._move_duration * 0.2)
	snapshot = state_snapshot()
	tap()
	tap()
	verify(state_snapshot() == snapshot, "Toggling UI during movement does not restart, cancel or advance the climbing motion")
	while game.climber.moving:
		game.climber._process(1.0 / 60.0)
	verify(game.climber.current_hold_id == id and game.climber.total_moves == 1 and not game.ui_visible, "The real hidden climbing action lands once on its chosen hold")
	game.hovered_id = -1
	game.preview_id = game.next_hold_id()
	game._update_reachable()
	verify(hidden_hold_materials(), "Advancing and selecting a new hold while hidden preserves natural rock colors and baseline emission")
	tap()
	verify(current_hold_materials() and game.world._materials[id].albedo_color.is_equal_approx(Color("8fcdba")) and not game.world._materials[0].albedo_color.is_equal_approx(Color("8fcdba")), "Restoration uses the new selected, reachable and used holds rather than cached pre-move feedback")
	tap()
	tap(KEY_ESCAPE, KEY_ESCAPE)
	game._sync_ui_visibility()
	verify(game.mode == "paused" and not game.ui_visible and all_buttons_hidden() and persistent_hints_visible() and hints_match_mode("paused", false), "Escape still pauses while passive hints explain how to continue")
	tap(KEY_ESCAPE, KEY_ESCAPE)
	verify(game.mode == "playing" and not game.ui_visible, "Escape resumes hidden gameplay")
	game._on_fell("主动返回")
	game.fall_time = 0.7
	game._process(0.0)
	verify(game.mode == "fallen" and all_buttons_hidden() and persistent_hints_visible() and hints_match_mode("fallen", false), "The hidden fall screen retains retry and interface hints")
	tap(KEY_ENTER, KEY_ENTER)
	verify(game.mode == "playing" and not game.ui_visible and not game.climber.moving, "Enter retries after a fall without forcing interface visibility")
	tap()
	verify(game.hud.is_visible_in_tree() and not persistent_hints_visible(), "The same shortcut restores the interface after a hidden retry without duplicate hints")

func grip_cancellation_contract() -> void:
	begin_climb()
	set_visible_ui(false)
	var id: int = game.next_hold_id()
	var hand: int = game.recommended_hand(id)
	game.attempt_hold(id, hand)
	aim_at_grip()
	game._sync_ui_visibility()
	verify(game.grip_active and game.grip_controls.is_visible_in_tree(), "A fresh hidden grip displays its independent component")
	var snapshot: Dictionary = state_snapshot()
	game.toggle_help()
	game._sync_ui_visibility()
	verify(game.help_open and not game.grip_controls.is_visible_in_tree() and not game.grip_active and not game.climber.moving and not game.climber.miss_reaching and game.climber.current_hold_id == snapshot.hold, "Opening help cancels an active drag and hides its component without committing a shot")
	game.toggle_help()
	game._sync_ui_visibility()
	game._release_grip(hand)
	verify(not game.grip_active and not game.grip_controls.is_visible_in_tree() and not game.climber.moving and not game.climber.miss_reaching, "Closing help and releasing cannot restore or commit the stale drag")
	game.attempt_hold(id, hand)
	aim_at_grip()
	game._cancel_grip()
	game._sync_ui_visibility()
	verify(not game.grip_active and not game.grip_controls.is_visible_in_tree(), "Cancelling a hidden grip clears the component")
	game.attempt_hold(id, hand)
	game._sync_ui_visibility()
	verify(game.grip_controls.is_visible_in_tree(), "The component can appear again for another grip")
	tap(KEY_ESCAPE, KEY_ESCAPE)
	game._sync_ui_visibility()
	verify(game.mode == "paused" and not game.grip_active and not game.grip_controls.is_visible_in_tree(), "Pausing cancels preparation and leaves no stale grip component")
	tap(KEY_ESCAPE, KEY_ESCAPE)
	game._sync_ui_visibility()
	verify(game.mode == "playing" and not game.grip_controls.is_visible_in_tree(), "Resuming without a grip keeps its component hidden")
	set_visible_ui(true)

func run() -> void:
	var isolated: String = OS.get_environment("MOUNTAINMARK_DATA_DIR")
	# The QA file remains outside the exported pack. res:// points at build when
	# running a PCK, so derive the actual checkout from this script's own path.
	var script_path: String = get_script().resource_path
	if script_path.begins_with("res://"):
		script_path = ProjectSettings.globalize_path(script_path)
	var repository: String = script_path.get_base_dir().get_base_dir()
	var workspace_runtime: String = repository.path_join(".runtime")
	var safe_data: bool = isolated.replace("\\", "/").simplify_path().begins_with(workspace_runtime.replace("\\", "/").simplify_path() + "/")
	verify("--qa-capture" in OS.get_cmdline_user_args() and safe_data, "The check uses isolated runtime data and --qa-capture")
	if not failures.is_empty():
		quit(2)
		return
	for suffix: String in [".runtime/save.json", "build/.runtime/save.json"]:
		var path: String = repository.path_join(suffix)
		player_saves[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	test_view = SubViewport.new()
	test_view.size = Vector2i(1440, 900)
	test_view.handle_input_locally = true
	root.add_child(test_view)
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	test_view.add_child(game)
	game.set_process(false)
	game.climber.set_process(false)
	game.sound.set_muted(true)
	await process_frame
	verify(game.has_method("toggle_ui") and game.has_method("_sync_ui_visibility"), "The game exposes the global UI visibility control")
	if not game.has_method("toggle_ui") or not game.has_method("_sync_ui_visibility"):
		quit(1)
		return
	verify(game.ui_visible and game.hud.is_visible_in_tree(), "Interface is enabled when the game starts")
	verify(game.control_hints != null and game.control_hints.has_method("get_hint_lines"), "An independent control hint layer is available")
	verify(passive_hints() and not persistent_hints_visible(), "The control hint layer has no mouse handling, focus or active buttons and starts hidden")
	verify(game.grip_controls != null and passive_control(game.grip_controls) and not game.grip_controls.is_visible_in_tree(), "The independent grip component starts hidden and cannot consume mouse or focus")
	input_contract()
	overlay_contract()
	world_feedback_contract()
	rebuilt_world_contract()
	controls_contract()
	grip_cancellation_contract()
	for path: String in player_saves:
		var bytes: Variant = player_saves[path]
		verify((not FileAccess.file_exists(path)) if bytes == null else (FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path) == bytes), path + " remains unchanged")
	game.sound.shutdown()
	game.queue_free()
	await process_frame
	print("UI_TOGGLE_RESULT checks=", checks, " failures=", failures.size())
	for failure: String in failures:
		print("FAILED: ", failure)
	quit(0 if failures.is_empty() else 1)

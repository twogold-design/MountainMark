extends SceneTree
## Render actual target picking, direct mouse-pull aim and both interface modes.
## Run through an isolated data directory and --qa-capture; never writes player saves.
const SIZE := Vector2i(1280, 900)
var game: Node3D
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	print("PASS " if condition else "FAIL ", label)
	if not condition:
		failures += 1

func capture(label: String, save: bool = true) -> Image:
	game._sync_ui_visibility()
	game.hud.queue_redraw()
	game.control_hints.refresh()
	game.grip_controls.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var frame: Image = root.get_texture().get_image()
	frame.convert(Image.FORMAT_RGBA8)
	if save:
		var path: String = "res://qa/ui-toggle-" + label + ".png"
		check(frame.save_png(path) == OK, "save " + path)
	return frame

func changed_pixels(first: Image, second: Image) -> int:
	var a: PackedByteArray = first.get_data()
	var b: PackedByteArray = second.get_data()
	var changed: int = 0
	for i in range(0, a.size(), 4):
		if a[i] != b[i] or a[i + 1] != b[i + 1] or a[i + 2] != b[i + 2]:
			changed += 1
	return changed

func max_channel_error(first: Image, second: Image) -> int:
	var a: PackedByteArray = first.get_data()
	var b: PackedByteArray = second.get_data()
	var error: int = 0
	for i in range(a.size()):
		error = maxi(error, absi(int(a[i]) - int(b[i])))
	return error

func ready_pixels(frame: Image, center: Vector2) -> int:
	var count: int = 0
	var area: Rect2i = Rect2i(Vector2i(center) - Vector2i(9, 9), Vector2i(19, 19)).intersection(Rect2i(Vector2i.ZERO, frame.get_size()))
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var color: Color = frame.get_pixel(x, y)
			if color.g > 0.65 and color.g > color.r * 1.12 and color.b > color.r * 1.04:
				count += 1
	return count

func move_mouse(point: Vector2, hand: int) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if hand == 0 else MOUSE_BUTTON_MASK_RIGHT
	root.push_input(event, true)

func mouse_button(point: Vector2, pressed: bool, hand: int) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT if hand == 0 else MOUSE_BUTTON_RIGHT
	event.position = point
	event.global_position = point
	event.pressed = pressed
	event.button_mask = (MOUSE_BUTTON_MASK_LEFT if hand == 0 else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
	root.push_input(event, true)

func run() -> void:
	if "--qa-capture" not in OS.get_cmdline_user_args():
		quit(2)
		return
	OS.set_environment("MOUNTAINMARK_DATA_DIR", ProjectSettings.globalize_path("res://.runtime/ui-toggle-preview-data"))
	root.size = SIZE
	root.content_scale_size = SIZE
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.climber.set_process(false)
	game.hud.set_process(false)
	game.sound.set_process(false)
	game.save_data = {}
	game.play_style = "challenge"
	game.challenge_index = 1
	game.start_climb(false)
	game.climber.set_process(false)
	var id: int = int(game.readable[0])
	var hand: int = game.recommended_hand(id)
	var support: int = int(game._hold(id).get("support", -1))
	game.select_support(-1)
	game.balance = 0.0
	game.climber.set_lean(game.balance)
	game._camera_ready = false
	game._update_camera(1.0)
	game._update_reachable()
	game.toast_time = 0.0
	game.hud.refresh_buttons()
	game._sync_ui_visibility()
	# Water/cloud shaders also animate through TIME, outside main._process.
	# Freeze engine time before the first image, so restored pixels are comparable.
	Engine.time_scale = 0.0
	await process_frame
	await RenderingServer.frame_post_draw
	# Pick a real visible rock with the production mouse-button path. The pull
	# then travels through _input before the GUI, as it does during actual play.
	var point: Vector2 = game.camera.unproject_position(Vector3(game._hold(id).position))
	move_mouse(point, hand)
	mouse_button(point, true, hand)
	check(game.grip_active and game.grip_id == id, "mouse button selects the actual target rock")
	check(support < 0 or game.selected_support == support, "clicking automatically chooses the required support foot")
	for step in range(20):
		game._tick_control(0.1, 0.0)
	check(absf(game.balance - game.balance_target) < 0.03, "body settles without any A/D input")
	var start_aim: Dictionary = game.get_drag_aim_info().duplicate()
	var anchor: Vector2 = start_aim.drag_anchor
	var ideal: Vector2 = anchor - (Vector2(start_aim.target_screen) - Vector2(start_aim.origin_screen)) / float(game.DRAG_AMPLIFICATION)
	var assisted_cursor: Vector2 = anchor + (ideal - anchor).rotated(deg_to_rad(12.0))
	move_mouse(assisted_cursor, hand)
	var hit_aim: Dictionary = game.get_drag_aim_info().duplicate()
	check(bool(hit_aim.assisted) and bool(hit_aim.accurate) and game.grip_ready(), "12-degree imperfect mouse pull is helped into a valid contact")
	check(float(hit_aim.raw_miss_distance) > float(hit_aim.tolerance), "unassisted landing would have missed the original rock boundary")
	check(float(hit_aim.miss_distance) < float(hit_aim.tolerance), "corrected predicted contact lies inside the true rock boundary")
	check(Vector3(hit_aim.predicted).distance_to(Vector3(hit_aim.target)) > 0.001, "assistance preserves a real off-centre contact without hard-locking")
	# The normal frame loop refreshes assistance after input. Reproduce that
	# refresh explicitly while the preview's simulation clock is frozen.
	game._update_reachable()
	game._sync_ui_visibility()
	var fixed_camera: Transform3D = game.camera.transform
	var fixed_body: Transform3D = game.climber._torso.transform
	check(game.ui_visible and game.hud.visible, "interface starts visible")
	check(not game.control_hints.visible, "immersive control hints stay hidden with full HUD")
	check(game.grip_active, "visible sample includes active grip feedback")
	check(game.grip_controls.visible, "full HUD includes independent live grip controls")
	check(game.climber._support_marker.visible, "visible sample includes support marker")
	var visible: Image = await capture("visible")
	var baseline: Image = await capture("baseline", false)
	var baseline_changes: int = changed_pixels(visible, baseline)
	var baseline_error: int = max_channel_error(visible, baseline)
	check(baseline_changes < 100 and baseline_error <= 1, "consecutive unchanged frames establish tiny render-noise baseline")
	game.toggle_ui()
	check(not game.ui_visible and not game.hud.visible, "HUD completely hidden")
	check(game.control_hints.visible, "essential controls remain visible in immersive mode")
	check(game.grip_controls.visible, "drag trajectory and force panel remain visible in immersive mode")
	check(game.grip_controls.mouse_filter == Control.MOUSE_FILTER_IGNORE, "live grip controls allow gameplay pointer input")
	check(game.control_hints.mouse_filter == Control.MOUSE_FILTER_IGNORE, "essential hints allow gameplay pointer input")
	check(not game.climber._support_marker.visible, "support marker hidden")
	var rings_hidden: bool = true
	for ring: MeshInstance3D in game.world._rings:
		rings_hidden = rings_hidden and not ring.visible
	check(rings_hidden, "all 3D hold assistance rings hidden")
	check(game.camera.transform == fixed_camera and game.climber._torso.transform == fixed_body, "hiding preserves camera and body")
	var hidden: Image = await capture("hidden")
	check(hidden.save_png("res://qa/ui-toggle-drag-hit.png") == OK, "save hit prediction")
	check(hidden.save_png("res://qa/ui-toggle-drag-assisted.png") == OK, "save imperfect pull with transparent assistance")
	check(ready_pixels(hidden, Vector2(hit_aim.predicted_screen)) > 5, "releasable assisted contact displays actual ready-green pixels")
	var settled_balance: float = game.balance
	game.balance = -0.7 if game.balance_target >= 0.0 else 0.7
	game.climber.set_lean(game.balance)
	game._refresh_grip_geometry()
	var unsteady_start: Dictionary = game.get_drag_aim_info().duplicate()
	var unsteady_cursor: Vector2 = anchor - (Vector2(unsteady_start.target_screen) - Vector2(unsteady_start.origin_screen)) / float(game.DRAG_AMPLIFICATION)
	move_mouse(unsteady_cursor, hand)
	var unsteady_aim: Dictionary = game.get_drag_aim_info().duplicate()
	check(bool(unsteady_aim.accurate) and not game.grip_ready(), "accurate aim remains unreleasable while the body is unsettled")
	var unsteady_frame: Image = await capture("drag-body-finding")
	check(ready_pixels(unsteady_frame, Vector2(unsteady_aim.predicted_screen)) == 0, "unsettled body leaves no ready-green pixels on the predicted contact")
	game.balance = settled_balance
	game.climber.set_lean(game.balance)
	game._refresh_grip_geometry()
	move_mouse(assisted_cursor, hand)
	check(game.grip_ready(), "settled body restores the assisted release feedback")
	var short_cursor: Vector2 = anchor + (ideal - anchor) * 0.55
	move_mouse(short_cursor, hand)
	var short_aim: Dictionary = game.get_drag_aim_info().duplicate()
	check(not bool(short_aim.accurate) and float(short_aim.power) < float(short_aim.required_power), "short pull gives insufficient reach instead of an automatic hit")
	check(float(short_aim.miss_distance) > float(short_aim.tolerance), "short pull leaves a measurable landing error")
	var short_frame: Image = await capture("drag-short")
	check(changed_pixels(hidden, short_frame) > 300, "short pull visibly updates force, line and predicted landing")
	var angle_cursor: Vector2 = anchor + (ideal - anchor).rotated(deg_to_rad(35.0))
	move_mouse(angle_cursor, hand)
	var angle_aim: Dictionary = game.get_drag_aim_info().duplicate()
	check(not bool(angle_aim.accurate) and float(angle_aim.angle_error) > deg_to_rad(30.0), "35-degree pull still misses despite the assistance")
	check(absf(float(angle_aim.power) - float(hit_aim.power)) < 0.0001, "directional miss occurs at the same force as the hit")
	var angle_frame: Image = await capture("drag-angle")
	check(angle_frame.save_png("res://qa/ui-toggle-drag-miss.png") == OK, "save obvious directional error that still misses")
	check(changed_pixels(hidden, angle_frame) > 300, "angle change visibly moves the predicted landing away from the rock")
	move_mouse(assisted_cursor, hand)
	check(game.grip_ready(), "returning to an approximate pull restores the assisted hit")
	game.toggle_ui()
	check(game.ui_visible and game.hud.visible, "HUD restored")
	check(not game.control_hints.visible, "immersive control hints hide when full HUD is restored")
	check(game.climber._support_marker.visible, "support marker restored")
	var restored: Image = await capture("restored")
	var hidden_changes: int = changed_pixels(visible, hidden)
	var restored_changes: int = changed_pixels(visible, restored)
	var restored_error: int = max_channel_error(visible, restored)
	check(hidden_changes > SIZE.x * SIZE.y / 20, "hiding removes interface pixels")
	# Compatibility's transparent water can differ by one 8-bit channel unit at
	# a few pixels despite a frozen clock. Reject any larger or widespread change.
	check(restored_changes < 100 and restored_error <= 1, "restored frame matches within 1/255 on fewer than 0.01% pixels")
	mouse_button(assisted_cursor, false, hand)
	check(not game.grip_active and game.climber.moving, "actual mouse release commits the displayed hit")
	game.climber._process(game.climber._move_duration)
	game.toast_time = 0.0
	game.toggle_help()
	await capture("help")
	check(not game.grip_controls.visible, "grip controls hide when preparation ends and help opens")
	game.toggle_ui()
	check(not game.hud.visible, "help overlay hidden with entire HUD")
	check(game.control_hints.visible, "essential controls remain visible over hidden help")
	await capture("help-hidden")
	game.toggle_ui()
	game.toggle_help()
	game.return_menu()
	game.climber.set_process(false)
	game._update_camera(1.0)
	await capture("menu")
	game.toggle_ui()
	check(not game.hud.visible, "menu buttons and panels hidden with entire HUD")
	check(game.control_hints.visible, "essential controls remain visible over hidden menu")
	await capture("menu-hidden")
	game.toggle_ui()
	print("UI_TOGGLE_PREVIEW baseline_changed_pixels=", baseline_changes, " baseline_max_channel_error=", baseline_error, " visible_to_hidden_pixels=", hidden_changes, " restored_changed_pixels=", restored_changes, " restored_max_channel_error=", restored_error, " failures=", failures)
	var report: FileAccess = FileAccess.open("res://.runtime/ui-toggle-preview-data/comparison.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"size": [SIZE.x, SIZE.y], "baseline_changed_pixels": baseline_changes, "baseline_max_channel_error": baseline_error, "visible_to_hidden_pixels": hidden_changes, "restored_changed_pixels": restored_changes, "restored_max_channel_error": restored_error, "assisted_raw_error_m": hit_aim.raw_miss_distance, "assisted_corrected_error_m": hit_aim.miss_distance, "assisted_degrees": rad_to_deg(float(hit_aim.angle_error)), "assist_strength": hit_aim.assist_strength, "tolerance_m": hit_aim.tolerance, "short_error_m": short_aim.miss_distance, "angle_error_m": angle_aim.miss_distance, "drag_angle_degrees": rad_to_deg(float(angle_aim.angle_error)), "failures": failures}, "\t"))
	game.sound.shutdown()
	game.queue_free()
	await create_timer(0.3, true, false, true).timeout
	quit(0 if failures == 0 else 1)

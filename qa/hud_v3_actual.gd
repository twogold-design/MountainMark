extends SceneTree
## Captures the actual game, with isolated QA state and no player save writes.
var game: Node3D
func _initialize() -> void:
	call_deferred("run")
func capture(label: String) -> void:
	game.toast_time = 0.0
	game.hud.refresh_buttons()
	game._sync_ui_visibility()
	game.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://qa/hud-v3-actual-" + label + ".png")
	print("CAPTURE ", label)
func aim_current_grip() -> void:
	game.climber.set_lean(game.balance)
	game._refresh_grip_geometry()
	var aim: Dictionary = game.get_drag_aim_info()
	game.set_grip_drag(Vector2(aim.drag_anchor) - (Vector2(aim.target_screen) - Vector2(aim.origin_screen)) / float(game.DRAG_AMPLIFICATION))
func position_at(hold: Dictionary) -> void:
	game.climber.setup(hold)
	game.climber.set_process(false)
	game.current_rest = bool(hold.rest)
	game._update_reachable()
	game.hovered_id = -1
	game._camera_ready = false
	game._update_camera(1.0)
	game.world.update_atmosphere(float(hold.position.y) / game.route_height, 1.0)
func run() -> void:
	OS.set_environment("MOUNTAINMARK_DATA_DIR", ProjectSettings.globalize_path("res://.runtime/qa-hud-v3"))
	root.size = Vector2i(1280, 900)
	root.content_scale_size = Vector2i(1280, 900)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._save_path = ProjectSettings.globalize_path("res://qa/hud-v3-save.json")
	game.set_process(false)
	game.climber.set_process(false)
	game.save_data = {}
	game._update_camera(1.0)
	await capture("menu")
	game.save_data = {"completed_routes": {"0":true,"1":true,"2":true}, "summits":3}
	game.select_route(1)
	game.select_style("journey")
	await capture("canyon-menu")
	game.select_style("journey")
	game.select_route(0)
	game.start_climb(false)
	for hold: Dictionary in game.world.holds:
		if hold.links.size() > 1:
			position_at(hold)
			break
	assert(game.reachable.size() > 1)
	await capture("fork")
	for hold: Dictionary in game.world.holds:
		if not str(hold.get("collectible", "")).is_empty():
			position_at(game._hold(int(hold.id) - 1))
			game.hovered_id = int(hold.id)
			break
	await capture("collection")
	game.return_menu()
	game.select_route(1)
	game.select_style("journey")
	game.start_climb(false)
	position_at(game.world.holds[0])
	game.attempt_hold(1, 0)
	game.balance = game.balance_target
	game.grip_time = 0.6
	aim_current_grip()
	assert(not game.grip_ready())
	await capture("support")
	game.select_support(int(game._hold(1).support))
	game.balance = game.balance_target
	aim_current_grip()
	assert(game.grip_ready())
	await capture("support-ready")
	game._on_fell("qa")
	game.fall_time = 1.0
	await capture("canyon-fallen")
	game.return_menu()
	game.select_style("extreme")
	game.select_route(2)
	game.start_climb(false)
	assert(game.chalk_capacity() == 2)
	for hold: Dictionary in game.world.holds:
		if str(hold.kind) == "wind":
			position_at(game._hold(int(hold.id) - 1))
			game.attempt_hold(int(hold.id), 1)
			break
	game.wind_strength = 0.91
	game.balance = game.balance_target
	game.grip_time = 0.6
	aim_current_grip()
	await capture("wind")
	game.toggle_pause()
	await capture("extreme-paused")
	game.toggle_pause()
	game._on_fell("qa")
	game.fall_time = 1.0
	await capture("fallen")
	game.return_menu()
	game.save_data["badges"] = {"群山之上":"2026-10-20","稳如磐石":"2026-10-20","留有余力":"2026-10-20","另辟蹊径":"2026-10-20","山路熟客":"2026-10-20","云海来客":"2026-10-20","孤峰行者":"2026-10-20","岩段练习生":"2026-10-20"}
	game.open_journal()
	await capture("journal")
	game.hud.journal_page = 1
	await capture("journal-page2")
	game.close_journal()
	game.select_style("journey")
	game.select_route(2)
	game.start_climb(false)
	position_at(game.world.holds[-1])
	game.elapsed = 821.0
	game.climber.total_moves = 56
	game._on_reached(int(game.world.holds[-1].id))
	game.summit_time = 7.0
	game.climber._process(7.0)
	game.run_collections.assign(["summit_1_safe", "summit_3_shortcut", "summit_4_safe"])
	game.elapsed = 821.0
	game.result_detail = "云上孤峰 · 13:41 · 跌落 0 次 · 56 次抓握 · 穿越阵风，走过更远的山路"
	game._camera_ready = false
	game._update_camera(1.0)
	await capture("summit")
	await game.export_postcard()
	assert(FileAccess.file_exists(game.postcard_path))
	assert(str(game.postcard_path).replace("\\", "/").begins_with(ProjectSettings.globalize_path("res://.runtime/qa-hud-v3").replace("\\", "/")))
	await capture("postcard-saved")
	game.queue_free()
	await process_frame
	print("HUD_V3_ACTUAL_PASS")
	quit()

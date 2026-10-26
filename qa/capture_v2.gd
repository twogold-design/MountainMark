extends SceneTree
var game: Node3D
func _initialize() -> void:
	call_deferred("run")
func capture_file(path: String) -> void:
	game._sync_ui_visibility()
	game.hud.queue_redraw()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func aim_current_grip() -> void:
	game._refresh_grip_geometry()
	var aim: Dictionary = game.get_drag_aim_info()
	game.set_grip_drag(Vector2(aim.drag_anchor) - (Vector2(aim.target_screen) - Vector2(aim.origin_screen)) / float(game.DRAG_AMPLIFICATION))
func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game._save_path = ProjectSettings.globalize_path("res://qa/capture-v2-save.json")
	game.start_climb(false)
	await create_timer(0.5).timeout
	game.set_process(false)
	game.climber.set_process(false)
	game.attempt_hold(game.next_hold_id(), 1)
	game.balance = game.balance_target
	game.grip_time = 0.6
	game.climber.set_lean(game.balance)
	aim_current_grip()
	game.climber._process(0.1)
	await capture_file("res://qa/control-v2-ready.png")
	game.balance = -1.0 if game.balance_target > 0 else 1.0
	game.climber.set_lean(game.balance)
	aim_current_grip()
	game.climber._process(0.1)
	await capture_file("res://qa/control-v2-balance.png")
	game.balance = game.balance_target
	game.climber.set_lean(game.balance)
	aim_current_grip()
	game._release_grip(game.grip_hand)
	game.climber._process(game.climber._move_duration * 0.45)
	game.toast_time = 0.0
	await capture_file("res://qa/control-v2-leg-motion.png")
	game._cancel_grip()
	game.mode = "menu"
	game.help_open = true
	game.hud.refresh_buttons()
	await capture_file("res://qa/control-v2-help.png")
	game.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("CONTROL_V2_VISUAL_OK")
	quit()

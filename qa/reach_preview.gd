extends SceneTree
## Render the shipped HUD and procedural poses with isolated, non-writing QA state.
var game: Node3D

func _initialize() -> void:
	call_deferred("run")

func capture(label: String, close: bool = false) -> void:
	game.toast_time = 0.0
	game.hud.refresh_buttons()
	game.hud.queue_redraw()
	if not close:
		game._camera_ready = false
		game._update_camera(1.0)
	if close:
		var body: Vector3 = game.climber.get_body_position()
		game.camera.position = body + Vector3(1.7, 0.1, 4.3)
		game.camera.look_at(body + Vector3(0.0, -0.15, 0.0))
	await process_frame
	await RenderingServer.frame_post_draw
	var path: String = "res://qa/reach-v032-" + label + ".png"
	var error: Error = root.get_texture().get_image().save_png(path)
	assert(error == OK)
	print("REACH_CAPTURE ", path)

func run() -> void:
	if "--qa-capture" not in OS.get_cmdline_user_args():
		quit(1)
		return
	OS.set_environment("MOUNTAINMARK_DATA_DIR", ProjectSettings.globalize_path("res://.runtime/reach-preview-data"))
	root.size = Vector2i(1280, 900)
	root.content_scale_size = Vector2i(1280, 900)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.climber.set_process(false)
	game.save_data = {"completed_routes":{"0":true}}
	game.route_index = 1
	game.play_style = "journey"
	game.start_climb(false)
	game._update_camera(1.0)
	game.choose_next()
	game.camera_reading = true
	game.select_support(0)
	await capture("left-support")
	game.select_support(1)
	await capture("right-support")
	var id: int = int(game.readable[0])
	game.select_support(int(game._hold(id).get("support", -1)))
	var hand: int = game.recommended_hand(id)
	game.attempt_hold(id, hand)
	game.balance = game.balance_target
	game.climber.set_lean(game.balance)
	game._refresh_grip_geometry()
	game.grip_time = 1.0
	game.grip_power = game.grip_target
	await capture("ready")
	game._cancel_grip()
	for style: int in range(3):
		game.climber.setup({"id": 0, "position": Vector3(0.0, 2.5, 0.45)})
		game.climber.climbing = true
		game.climber.set_process(false)
		game.select_support(0 if style != 1 else 1)
		var point: Vector3 = [Vector3(0.15, 3.5, 0.45), Vector3(-1.1, 2.85, 0.45), Vector3(0.20, 4.6, 0.45)][style]
		game.climber.climb_to({"id": id, "position": point}, 0 if style == 1 else 1, 0.0)
		game.climber._process(game.climber._move_duration * 0.38)
		await capture(["front", "side", "high-step"][style], true)
	game.sound.shutdown()
	game.queue_free()
	await create_timer(0.3).timeout
	quit()

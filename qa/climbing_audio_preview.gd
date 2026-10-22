extends SceneTree
## Capture the actual recovery HUD alongside a collectible toast, without touching saves.
var game: Node3D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if "--qa-capture" not in OS.get_cmdline_user_args():
		quit(1)
		return
	OS.set_environment("MOUNTAINMARK_DATA_DIR", ProjectSettings.globalize_path("res://.runtime/climbing-audio-preview-data"))
	root.size = Vector2i(1280, 900)
	root.content_scale_size = Vector2i(1280, 900)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.climber.set_process(false)
	game.sound.set_process(false)
	game.save_data = {}
	game.start_climb(false)
	var fixture: Dictionary = {}
	for hold: Dictionary in game.world.holds:
		if bool(hold.rest) and not bool(hold.checkpoint) and not str(hold.get("collectible", "")).is_empty():
			fixture = hold
			break
	assert(not fixture.is_empty(), "The real route must contain a rest ledge with a discovery.")
	game.climber.setup(fixture)
	game.climber.climbing = true
	game.climber.stamina = 30.0
	game.climber.set_process(false)
	game.chapter = mini(4, int(float(fixture.position.y) / game.route_height * 4.0))
	game._on_reached(int(fixture.id))
	game._process(0.6)
	assert(is_equal_approx(game.climber.stamina, 43.8))
	assert(game.rest_feedback_time > 0.0)
	assert(game.toast == "发现山路记录")
	game._camera_ready = false
	game._update_camera(1.0)
	game.hud.refresh_buttons()
	game.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var target: String = "res://qa/climbing-audio-rest.png"
	assert(root.get_texture().get_image().save_png(target) == OK)
	print("CLIMBING_AUDIO_PREVIEW hold=", fixture.id, " stamina=", game.climber.stamina, " toast=", game.toast, " output=", target)
	game.sound.shutdown()
	game.queue_free()
	await process_frame
	quit()

extends SceneTree
var game: Node3D
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	assert("--qa-capture" in OS.get_cmdline_user_args())
	assert(ProjectSettings.get_setting("application/config/version") == "0.3.1")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.save_data = {}
	await create_timer(0.6).timeout
	var cliff: MeshInstance3D = game.world.get_node("ContinuousRockFace")
	assert(cliff.mesh.surface_get_array_len(0) > 8000)
	assert(cliff.material_override is ShaderMaterial)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("M:/NewGames/MountainMark/qa/art-v031-menu.png")
	game.start_climb(false)
	await create_timer(0.6).timeout
	game.toast_time = 0.0
	var before: Vector3 = game.climber.get_body_position()
	game.choose_next()
	await create_timer(0.2).timeout
	assert(before.is_equal_approx(game.climber.get_body_position()))
	game.toast_time = 0.0
	game.hud.queue_redraw()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("M:/NewGames/MountainMark/qa/art-v031-gameplay.png")
	print("ART_PACK_RENDER_PASS version=0.3.1 smooth_cliff_vertices=", cliff.mesh.surface_get_array_len(0) if is_instance_valid(cliff) else "rebuilt", " W_observation_only=true")
	game.quit_game()

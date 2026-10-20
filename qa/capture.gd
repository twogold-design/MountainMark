extends SceneTree
var game: Node3D
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://qa/01-title.png")
	game.start_climb(false)
	await create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://qa/02-climbing.png")
	var mid: Dictionary = game.world.holds[36]
	game.climber.setup(mid)
	game.climber.climbing = true
	game._on_reached(int(mid.id))
	game._update_reachable()
	await create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://qa/03-midpoint.png")
	game.climber.setup(game.world.holds[-1])
	game._on_reached(int(game.world.holds[-1].id))
	await create_timer(9.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://qa/04-summit.png")
	print("VISUAL_CAPTURE_OK")
	game.queue_free()
	await process_frame
	quit()

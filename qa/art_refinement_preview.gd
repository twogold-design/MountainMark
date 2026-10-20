extends SceneTree
var game: Node3D
func _initialize() -> void:
	call_deferred("run")
func step(seconds: float) -> void:
	for i in range(int(seconds * 60.0)):
		game.climber._process(1.0 / 60.0)
		game._process(1.0 / 60.0)
func snap(file: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://qa/" + file)
func run() -> void:
	assert("--qa-capture" in OS.get_cmdline_user_args())
	for index in range(6):
		game = load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		game._save_path = "res://.runtime/scenery-camera-save.json"
		game.save_data = {"completed_routes": {"0": true, "1": true, "2": true}}
		game.route_index = mini(index, 2)
		game.play_style = "journey" if index < 3 else "challenge"
		game.challenge_index = maxi(0, index - 3)
		game.start_climb(false)
		var expected: Dictionary = load("res://scripts/routes.gd").build(game.route_index, game.play_style, game.challenge_index)
		assert(game.world.holds == expected.holds)
		assert(is_equal_approx(game.world.get_summit_position().y, game.route_height + 2.0))
		game.set_process(false)
		game.climber.set_process(false)
		game.sound.set_muted(true)
		game.hud.hide()
		var prefix: String = str(game.active_route.id) + ("-challenge%d" % (index - 3) if index >= 3 else "")
		game._update_camera(1.0)
		await snap("art-v031-%s-base.png" % prefix)
		var selected: Dictionary = game.world.holds[1]
		for hold in game.world.holds:
			if float(hold.position.y) >= game.route_height * 0.57 and not bool(hold.rest) and str(hold.branch) != "shortcut":
				selected = hold
				break
		game.climber.setup(selected)
		game.climber.climbing = true
		game._on_reached(int(selected.id))
		game._camera_ready = false
		game.toast_time = 0.0
		step(0.5)
		await create_timer(0.3).timeout
		await snap("art-v031-%s-climb.png" % prefix)
		var stamp: int = Time.get_ticks_usec()
		for frame in range(45):
			await process_frame
		var milliseconds: float = float(Time.get_ticks_usec() - stamp) / 1000.0 / 45.0
		print("ART_RENDER ", prefix, " frame_ms=", snappedf(milliseconds, 0.1), " primitives=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), " calls=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		game.climber.setup(game.world.holds[-1])
		game.climber.climbing = true
		game.best_precise_streak = 5
		game._on_reached(int(game.world.holds[-1].id))
		assert(game.mode == "summit")
		step(3.5)
		await snap("art-v031-%s-summit-close.png" % prefix)
		step(6.5)
		await snap("art-v031-%s-summit.png" % prefix)
		var floor: Vector3 = game.world.get_summit_position()
		print("ART_CAMERA_OK ", prefix, " floor=", floor, " feet=", game.climber._feet, " camera=", game.camera.position)
		for foot in game.climber._feet:
			assert(absf(foot.y - floor.y - 0.06) < 0.005)
			assert(absf(foot.z - floor.z) < 0.005)
		game.queue_free()
		await process_frame
	quit()

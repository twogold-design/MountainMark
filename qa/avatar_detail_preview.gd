extends SceneTree
const ACTOR = preload("res://scripts/climber.gd")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	root.size = Vector2i(1440, 900)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var stage := Control.new()
	root.add_child(stage)
	for index in range(3):
		var box := SubViewportContainer.new()
		box.position = Vector2(index * 480, 0)
		box.size = Vector2(480, 900)
		stage.add_child(box)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(480, 900)
		viewport.own_world_3d = true
		viewport.msaa_3d = Viewport.MSAA_4X
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		box.add_child(viewport)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color("253845")
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color("c6d9e4")
		env.environment.ambient_light_energy = 0.55
		viewport.add_child(env)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-35, -35, 0)
		light.light_energy = 1.7
		viewport.add_child(light)
		var actor: Node3D = ACTOR.new()
		viewport.add_child(actor)
		actor.set_process(false)
		actor.setup({"id": 0, "position": Vector3(0, 2.5, 0.45)})
		actor.set_outfit(index)
		var body: Vector3 = actor.get_body_position()
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 1.30 if not OS.get_cmdline_user_args().has("full") else 2.70
		var angles: Array[Vector3] = [Vector3(0.8, 0.2, 4.0), Vector3(3.5, 0.15, 2.0), Vector3(-1.2, 0.25, -4.0)]
		camera.position = body + angles[index]
		viewport.add_child(camera)
		camera.look_at(body + Vector3(0, -0.12, 0), Vector3.UP)
		camera.current = true
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var tag := "after"
	if OS.get_cmdline_user_args().size() > 0:
		tag = OS.get_cmdline_user_args()[0]
	var result: Error = root.get_texture().get_image().save_png("res://qa/avatar-detail-" + tag + ".png")
	print("AVATAR DETAIL CAPTURE ", tag, " status=", result)
	quit(result)

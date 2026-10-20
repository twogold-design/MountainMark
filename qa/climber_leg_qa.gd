extends SceneTree

const ACTOR = preload("res://scripts/climber.gd")
var cases: Array[Node3D] = []
var checks: int = 0
var max_upper_error: float = 0.0
var max_lower_error: float = 0.0

func _initialize() -> void:
	call_deferred("_run")

func _check_legs(actor: Node3D) -> void:
	for i in range(2):
		var side: float = -1.0 if i == 0 else 1.0
		var hip: Vector3 = actor._torso.transform * Vector3(side * 0.13, -0.29, 0)
		var knee: Vector3 = actor._knees[i].position
		var ankle: Vector3 = actor._boots[i].position - Vector3(0, -0.015, -0.045)
		var upper_error: float = absf(hip.distance_to(knee) - 0.43)
		var lower_error: float = absf(knee.distance_to(ankle) - 0.44)
		max_upper_error = maxf(max_upper_error, upper_error)
		max_lower_error = maxf(max_lower_error, lower_error)
		assert(upper_error < 0.0002, "Thigh length changed")
		assert(lower_error < 0.0002, "Shin length changed")
		var axis: Vector3 = (ankle - hip).normalized()
		var bend: Vector3 = knee - hip - axis * (knee - hip).dot(axis)
		assert(bend.z <= 0.0001, "Knee bent away from rock")
		assert(absf(actor._boots[i].rotation.y) < 0.06, "Toe turned outward")
		checks += 1

func _run() -> void:
	root.size = Vector2i(1600, 1000)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var stage: Control = Control.new()
	root.add_child(stage)
	for index in range(4):
		var box: SubViewportContainer = SubViewportContainer.new()
		box.position = Vector2(float(index % 2) * 800.0, float(index / 2) * 500.0)
		box.size = Vector2(800, 500)
		stage.add_child(box)
		var viewport: SubViewport = SubViewport.new()
		viewport.size = Vector2i(800, 500)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		box.add_child(viewport)
		var env_node: WorldEnvironment = WorldEnvironment.new()
		var environment: Environment = Environment.new()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color("182c3c")
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color("c6d9e4")
		environment.ambient_light_energy = 0.65
		env_node.environment = environment
		viewport.add_child(env_node)
		var light: DirectionalLight3D = DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-35, -30, 0)
		light.light_energy = 1.4
		viewport.add_child(light)
		var actor: Node3D = ACTOR.new()
		viewport.add_child(actor)
		actor.set_process(false)
		actor.setup({"id": 0, "position": Vector3(0, 2.5, 0.45)})
		actor.climbing = true
		cases.append(actor)
		if index == 1 or index == 2:
			var target_x: float = -0.45 if index == 1 else 0.45
			assert(actor.climb_to({"id": 1, "position": Vector3(target_x, 3.8, 0.45)}, index - 1, 7.5))
			assert(is_equal_approx(actor.stamina, 92.5))
			var freeze_time: float = actor._move_duration * (0.41 if index == 1 else 0.68)
			while actor._move_time < freeze_time:
				actor._process(0.008)
				_check_legs(actor)
		elif index == 3:
			actor.celebrate(Vector3(0, 3.5, -0.8))
			for frame in range(240):
				actor._process(0.016)
				_check_legs(actor)
		_check_legs(actor)
		var body: Vector3 = actor.get_body_position()
		var wall: MeshInstance3D = MeshInstance3D.new()
		var wall_mesh: BoxMesh = BoxMesh.new()
		wall_mesh.size = Vector3(3.5, 3.2, 0.08)
		wall.mesh = wall_mesh
		var stone: StandardMaterial3D = StandardMaterial3D.new()
		stone.albedo_color = Color("8c7861")
		wall.material_override = stone
		wall.position = Vector3(body.x, body.y - 0.2, 0.05)
		if index == 3:
			wall_mesh.size = Vector3(3.5, 0.08, 3.0)
			wall.position = Vector3(0, 3.5, -0.8)
		viewport.add_child(wall)
		var camera: Camera3D = Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 2.55
		camera.position = body + Vector3(4.3, 0.35, 2.1)
		viewport.add_child(camera)
		camera.look_at(body + Vector3(0, -0.10, 0), Vector3.UP)
		camera.current = true
		var label: Label = Label.new()
		label.text = ["IDLE / knees toward wall", "LEFT REACH / plant then push", "RIGHT REACH / support foot", "SUMMIT / feet on platform"][index]
		label.position = box.position + Vector2(20, 18)
		label.add_theme_font_size_override("font_size", 22)
		stage.add_child(label)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var result: Error = root.get_texture().get_image().save_png("res://qa/climber-leg-sideviews.png")
	assert(result == OK)
	# Exercise full left/right moves, support-foot dwell, lean, stamina gating and restart.
	var actor: Node3D = cases[0]
	for hand in range(2):
		actor.setup({"id": 0, "position": Vector3(0, 2.5, 0.45)})
		actor.climbing = true
		assert(actor.climb_to({"id": 1, "position": Vector3(0.6, 3.8, 0.45)}, hand, 9.0))
		var planted: Vector3 = actor._feet[1 - hand]
		actor._process(0.12 * actor._move_duration / float(actor._step_count))
		assert(actor._feet[1 - hand].is_equal_approx(planted))
		assert(actor.get_body_position().is_equal_approx(actor._old_body + Vector3(0, 0, sin(0.12 * PI) * 0.025)))
		while actor.moving:
			actor._process(0.008)
			_check_legs(actor)
		actor.set_lean(-1.0 if hand == 0 else 1.0)
		for frame in range(90):
			actor._process(0.016)
			_check_legs(actor)
		actor.stamina = 2.0
		assert(not actor.climb_to({"id": 2, "position": Vector3(0, 4.8, 0.45)}, 0, 3.0))
		actor.recover()
		assert(actor.climbing and not actor.moving and not actor.summit_mode)
		assert(actor.chalk())
		actor.setup({"id": 0, "position": Vector3(0, 2.5, 0.45)})
		assert(actor._chalk_cooldown == 0.0 and actor.total_moves == 0)
	print("LEG QA PASS checks=", checks, " max thigh error=", max_upper_error, " max shin error=", max_lower_error)
	print("Side views saved to qa/climber-leg-sideviews.png")
	quit()


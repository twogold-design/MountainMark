extends SceneTree
func _initialize() -> void:
	var world_script = load("res://scripts/world.gd")
	var world = world_script.new()
	root.add_child(world)
	world.build_world()
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(4.0, 9.0, 17.0)
	camera.look_at_from_position(Vector3(4.0, 9.0, 17.0), Vector3(0.0, 8.0, 0.0))
	camera.fov = 65.0
	camera.current = true
	world.set_hold_feedback([1, 2], 2, 0)
	await create_timer(1.5).timeout
	root.get_texture().get_image().save_png("res://qa/world-preview.png")
	print("WORLD_OK: ", world.holds.size(), " holds; ", world.holds[-1].position)
	for i in range(1, world.holds.size()):
		assert(world.holds[i].position.y >= world.holds[i - 1].position.y)
	quit()


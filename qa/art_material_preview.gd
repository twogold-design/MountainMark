extends SceneTree
const Materials = preload("res://scripts/terrain_materials.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(0, 2, 9)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -25, 0)
	scene.add_child(light)
	for i in range(4):
		var object := MeshInstance3D.new()
		object.mesh = SphereMesh.new() if i < 2 else QuadMesh.new()
		object.position.x = float(i) * 2.0 - 3.0
		object.scale = Vector3.ONE * 1.7
		object.material_override = [Materials.rock(Color("a18c70")), Materials.snow(), Materials.water(), Materials.cloud()][i]
		scene.add_child(object)
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://qa/art-material-preview.png")
	print("MATERIALS_RENDER_OK")
	scene.queue_free()
	await process_frame
	quit()

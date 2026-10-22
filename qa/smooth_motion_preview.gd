extends SceneTree
## Deterministic rendered animation samples. Writes only QA artifacts and isolated runtime files.
const SIZE: Vector2i = Vector2i(480, 480)
const FRAME_COUNT: int = 49
const CLIMBER = preload("res://scripts/climber.gd")
var stage: Node3D
var actor: Node3D
var camera: Camera3D
var title: Label
var stamp: Label
var output_dir: String = "res://.runtime/smooth-motion-frames"
var contact: Image

func _initialize() -> void:
	call_deferred("run")

func material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.95
	return result

func mesh(shape: Mesh, color: Color, at: Vector3) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.mesh = shape
	result.material_override = material(color)
	result.position = at
	stage.add_child(result)
	return result

func hold(at: Vector3, target: bool) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.115 if target else 0.095
	sphere.height = sphere.radius * 2.0
	var item := mesh(sphere, Color("edc47c") if target else Color("557a84"), at)
	item.scale = Vector3(1.0, 0.65, 0.5)

func build_stage() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("182732")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c8dfed")
	environment.environment.ambient_light_energy = 0.65
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-32.0, -25.0, 0.0)
	light.light_energy = 1.5
	stage.add_child(light)
	var wall := BoxMesh.new()
	wall.size = Vector3(8.0, 8.0, 0.1)
	mesh(wall, Color("40525b"), Vector3(0.0, 3.0, 0.25))
	for y in range(5):
		var ledge := BoxMesh.new()
		ledge.size = Vector3(7.0, 0.012, 0.006)
		mesh(ledge, Color("50636a"), Vector3(0.0, float(y), 0.307))
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.7
	stage.add_child(camera)
	camera.position = Vector3(2.8, 3.05, 9.0)
	camera.look_at(Vector3(-0.25, 2.62, 0.55))
	camera.current = true
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var bar := ColorRect.new()
	bar.color = Color(0.035, 0.065, 0.085, 0.90)
	bar.size = Vector2(SIZE.x, 61.0)
	layer.add_child(bar)
	title = Label.new()
	title.position = Vector2(18.0, 8.0)
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", Color("f1c675"))
	layer.add_child(title)
	stamp = Label.new()
	stamp.position = Vector2(18.0, 35.0)
	stamp.add_theme_font_size_override("font_size", 14)
	layer.add_child(stamp)

func seed_for_search() -> int:
	var rng := RandomNumberGenerator.new()
	for value in range(1000):
		rng.seed = value
		if rng.randf() < CLIMBER.SEARCH_CHANCE:
			return value
	return 1

func run() -> void:
	if "--qa-capture" not in OS.get_cmdline_user_args():
		quit(1)
		return
	OS.set_environment("MOUNTAINMARK_DATA_DIR", ProjectSettings.globalize_path("res://.runtime/smooth-preview-data"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	root.size = SIZE
	root.content_scale_size = SIZE
	build_stage()
	contact = Image.create(SIZE.x * 6, SIZE.y * 4, false, Image.FORMAT_RGB8)
	var labels: Array[String] = ["FRONT / continuous reach", "SIDE / weight transfer", "HIGH STEP / knee fold", "SEARCH / occasional variation"]
	var slugs: Array[String] = ["front", "side", "high-step", "search"]
	var targets: Array[Vector3] = [Vector3(0.15, 3.5, 0.45), Vector3(-1.1, 2.85, 0.45), Vector3(0.20, 4.6, 0.45), Vector3(0.15, 3.5, 0.45)]
	var selected_frames: Array[int] = [0, 10, 20, 29, 39, 48]
	for style in range(4):
		actor = CLIMBER.new()
		stage.add_child(actor)
		actor.set_process(false)
		actor.setup({"id": 0, "position": Vector3(0.0, 2.5, 0.45)})
		actor.climbing = true
		actor.set_support_foot(1 if style == 1 else 0)
		if style == 3:
			actor.total_moves = 1
			actor._motion_rng.seed = seed_for_search()
		var hand: int = 0 if style == 1 else 1
		assert(actor.climb_to({"id": 1, "position": targets[style]}, hand, 0.0))
		assert(actor._searching_move == (style == 3))
		title.text = labels[style]
		camera.size = 5.4 if style == 2 else 3.9
		var focus_y: float = 2.75 if style == 2 else 2.28
		camera.position = Vector3(2.8, focus_y + 0.35, 9.0)
		camera.look_at(Vector3(-0.25, focus_y, 0.55))
		hold(Vector3(0.0, 2.5, 0.45), false)
		hold(targets[style], true)
		var duration: float = actor._move_duration
		for frame in range(FRAME_COUNT):
			var fraction: float = float(frame) / float(FRAME_COUNT - 1)
			if frame > 0:
				actor._process(duration / float(FRAME_COUNT - 1))
			else:
				actor._update_pose()
			stamp.text = "%.2f s / %.0f%%   |   Actual Godot pose" % [duration * fraction, fraction * 100.0]
			await process_frame
			await RenderingServer.frame_post_draw
			var capture: Image = root.get_texture().get_image()
			capture.convert(Image.FORMAT_RGB8)
			var path: String = "%s/%s-%03d.png" % [output_dir, slugs[style], frame]
			assert(capture.save_png(path) == OK)
			var column: int = selected_frames.find(frame)
			if column >= 0:
				contact.blit_rect(capture, Rect2i(Vector2i.ZERO, SIZE), Vector2i(column * SIZE.x, style * SIZE.y))
		print("SMOOTH_PREVIEW ", slugs[style], " duration=", duration, " search=", actor._searching_move)
		actor.queue_free()
		# Remove hold meshes; the wall and grid remain.
		for child in stage.get_children():
			if child is MeshInstance3D and child.mesh is SphereMesh:
				child.queue_free()
		await process_frame
	assert(contact.save_png("res://qa/smooth-motion-contact.png") == OK)
	print("SMOOTH_PREVIEW contact=res://qa/smooth-motion-contact.png frames=", output_dir)
	quit()

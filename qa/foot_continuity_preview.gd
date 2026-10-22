extends SceneTree
## Render the actual boots through one complete reach, then hold the landing.
## The contact sheet uses six timeline samples; the GIF is assembled from frames.
const SIZE := Vector2i(420, 500)
const MOTION_FRAMES: int = 61
const LANDING_FRAMES: int = 9
const START := Vector3(0.0, 2.5, 0.45)
const Actor = preload("res://scripts/climber.gd")
var stage: Node3D
var actor: Node3D
var camera: Camera3D
var marks: Node3D
var title: Label
var stamp: Label
var contact: Image
var output_dir: String = "res://.runtime/foot-continuity-frames"
var reports: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.95
	return result

func mesh(shape: Mesh, color: Color, at: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.mesh = shape
	result.material_override = material(color)
	result.position = at
	(stage if parent == null else parent).add_child(result)
	return result

func hold(at: Vector3, goal: bool) -> void:
	var shape := SphereMesh.new()
	shape.radius = 0.10 if goal else 0.075
	shape.height = shape.radius * 2.0
	var item := mesh(shape, Color("edc47c") if goal else Color("6d9ea7"), at, marks)
	item.scale = Vector3(1.0, 0.60, 0.45)

func build_stage() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("182732")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("cee1ed")
	environment.environment.ambient_light_energy = 0.75
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-32.0, -25.0, 0.0)
	light.light_energy = 1.5
	stage.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-22.0, 155.0, 0.0)
	fill.light_energy = 0.7
	stage.add_child(fill)
	var rock := BoxMesh.new()
	rock.size = Vector3(7.0, 7.0, 0.10)
	mesh(rock, Color("40525b"), Vector3(0.0, 3.0, 0.25))
	for y in range(6):
		var line := BoxMesh.new()
		line.size = Vector3(6.0, 0.012, 0.005)
		mesh(line, Color("50636a"), Vector3(0.0, float(y), 0.306))
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	camera.current = true
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var bar := ColorRect.new()
	bar.color = Color(0.035, 0.065, 0.085, 0.93)
	bar.size = Vector2(SIZE.x, 61.0)
	layer.add_child(bar)
	title = Label.new()
	title.position = Vector2(12.0, 8.0)
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", Color("f1c675"))
	layer.add_child(title)
	stamp = Label.new()
	stamp.position = Vector2(12.0, 35.0)
	stamp.add_theme_font_size_override("font_size", 13)
	layer.add_child(stamp)

func vector_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func run() -> void:
	if "--qa-capture" not in OS.get_cmdline_user_args():
		quit(2)
		return
	OS.set_environment("MOUNTAINMARK_DATA_DIR", ProjectSettings.globalize_path("res://.runtime/foot-preview-data"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	root.size = SIZE
	root.content_scale_size = SIZE
	build_stage()
	contact = Image.create(SIZE.x * 6, SIZE.y * 6, false, Image.FORMAT_RGB8)
	var selected: Array[int] = [0, 12, 24, 36, 48, 60]
	var slugs: Array[String] = ["front", "side-left", "side-right", "high-step", "drop-left", "drop-right"]
	var labels: Array[String] = ["FRONT / plant and push", "LEFT TRAVERSE / transfer", "RIGHT TRAVERSE / transfer", "HIGH STEP / one lift", "LEFT DROP KNEE / pivot", "RIGHT DROP KNEE / pivot"]
	var targets: Array[Vector3] = [Vector3(0.15, 3.70, 0.45), Vector3(-1.1, 2.85, 0.45), Vector3(1.1, 2.85, 0.45), Vector3(0.20, 4.60, 0.45), Vector3(-0.90, 3.45, 0.45), Vector3(0.90, 3.45, 0.45)]
	var hands: Array[int] = [1, 0, 1, 1, 0, 1]
	var supports: Array[int] = [0, 1, 0, 0, 0, 1]
	for style in range(slugs.size()):
		actor = Actor.new()
		stage.add_child(actor)
		actor.set_process(false)
		actor.setup({"id": 0, "position": START})
		actor.climbing = true
		actor.set_support_foot(supports[style])
		actor.set_lean((-0.90 if hands[style] == 0 else 0.90) if style >= 4 else 0.0)
		assert(actor.climb_to({"id": 1, "position": targets[style]}, hands[style], 0.0))
		assert(actor._motion == (["front", "side", "side", "high_step", "drop_knee", "drop_knee"][style]))
		title.text = labels[style]
		marks = Node3D.new()
		stage.add_child(marks)
		hold(START, false)
		hold(targets[style], true)
		var focus := Vector3((targets[style].x + 0.1) * 0.45, 2.80 if style == 3 else 2.30, 0.65)
		camera.size = 5.1 if style == 3 else 4.1
		camera.position = focus + Vector3(1.8 if hands[style] == 0 else -1.8, 0.20, 9.0)
		camera.look_at(focus)
		var duration: float = actor._move_duration
		var frame_count: int = MOTION_FRAMES + LANDING_FRAMES
		var samples: Array[Dictionary] = []
		for frame in range(frame_count):
			var elapsed: float = float(frame) * duration / float(MOTION_FRAMES - 1)
			if frame > 0:
				actor._process(duration / float(MOTION_FRAMES - 1))
			else:
				actor._update_pose()
			stamp.text = "%.2f s / %.0f%% | actual Godot boots" % [elapsed, minf(100.0, elapsed / duration * 100.0)]
			samples.append({"time": elapsed, "left": vector_array(actor._boots[0].position), "right": vector_array(actor._boots[1].position), "left_target": vector_array(actor._feet[0]), "right_target": vector_array(actor._feet[1]), "moving": actor.moving})
			await process_frame
			await RenderingServer.frame_post_draw
			var capture: Image = root.get_texture().get_image()
			capture.convert(Image.FORMAT_RGB8)
			assert(capture.save_png("%s/%s-%03d.png" % [output_dir, slugs[style], frame]) == OK)
			var column: int = selected.find(frame)
			if column >= 0:
				contact.blit_rect(capture, Rect2i(Vector2i.ZERO, SIZE), Vector2i(column * SIZE.x, style * SIZE.y))
		reports.append({"slug": slugs[style], "duration": duration, "frames": frame_count, "frame_interval": duration / float(MOTION_FRAMES - 1), "samples": samples})
		print("FOOT_PREVIEW ", slugs[style], " duration=", duration)
		actor.queue_free()
		marks.queue_free()
		await process_frame
	assert(contact.save_png("res://qa/foot-continuity-contact.png") == OK)
	var report := FileAccess.open(output_dir + "/frames.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(reports, "\t"))
	print("FOOT_PREVIEW contact=res://qa/foot-continuity-contact.png frames=", output_dir)
	quit()

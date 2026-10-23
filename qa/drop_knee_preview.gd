extends SceneTree
## Actual Godot rendering: mirrored drop knees and a high-step comparison.
## Two views per action, deterministic time sampling, isolated QA artifacts.
const SIZE := Vector2i(360, 400)
const FRAME_COUNT: int = 37
const START := Vector3(0.0, 2.5, 0.45)
const Actor = preload("res://scripts/climber.gd")
var stage: Node3D
var actor: Node3D
var camera: Camera3D
var wall: MeshInstance3D
var marks: Node3D
var title: Label
var stamp: Label
var contact: Image
var output_dir: String = "res://.runtime/drop-knee-frames"
var frame_reports: Array[Dictionary] = []

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
	shape.radius = 0.105 if goal else 0.085
	shape.height = shape.radius * 2.0
	var item := mesh(shape, Color("edc47c") if goal else Color("6d9ea7"), at, marks)
	item.scale = Vector3(1.0, 0.70, 0.50)

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
	rock.size = Vector3(6.0, 6.0, 0.10)
	wall = mesh(rock, Color("40525b"), Vector3(0.0, 3.0, 0.25))
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
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("f1c675"))
	layer.add_child(title)
	stamp = Label.new()
	stamp.position = Vector2(12.0, 35.0)
	stamp.add_theme_font_size_override("font_size", 12)
	layer.add_child(stamp)

func run() -> void:
	if "--qa-capture" not in OS.get_cmdline_user_args():
		quit(2)
		return
	OS.set_environment("MOUNTAINMARK_DATA_DIR", ProjectSettings.globalize_path("res://.runtime/drop-preview-data"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	root.size = SIZE
	root.content_scale_size = SIZE
	build_stage()
	contact = Image.create(SIZE.x * 6, SIZE.y * 6, false, Image.FORMAT_RGB8)
	var selected: Array[int] = [0, 7, 14, 21, 28, 36]
	for style in range(6):
		var from_front: bool = style >= 3
		var action: int = style % 3
		var hand: int = 0 if action == 0 else 1
		var side: float = -1.0 if hand == 0 else 1.0
		var high: bool = action == 2
		var delta := Vector3(side * 0.90, 0.95, 0.0) if not high else Vector3(0.20, 2.10, 0.0)
		var target: Vector3 = START + delta
		var slug: String = ("left-drop" if action == 0 else ("right-drop" if action == 1 else "high-step")) + ("-front" if from_front else "-back")
		actor = Actor.new()
		stage.add_child(actor)
		actor.set_process(false)
		actor.setup({"id": 0, "position": START})
		actor.climbing = true
		actor.set_support_foot(1 - hand if high else hand)
		actor.set_lean(0.0 if high else side * 0.90)
		assert(actor.climb_to({"id": 1, "position": target}, hand, 0.0))
		assert(actor._motion == ("high_step" if high else "drop_knee"))
		title.text = ("HIGH STEP" if high else ("LEFT DROP KNEE" if hand == 0 else "RIGHT DROP KNEE")) + (" / front" if from_front else " / back")
		wall.visible = not from_front
		marks = Node3D.new()
		stage.add_child(marks)
		hold(START, false)
		hold(target, true)
		var focus := Vector3(0.10 if high else side * 0.30, 2.95 if high else 2.40, 0.65)
		camera.size = 5.3 if high else 4.3
		camera.position = focus + Vector3(side * (1.2 if from_front else -1.2), 0.25, -8.0 if from_front else 8.0)
		camera.look_at(focus)
		var duration: float = actor._move_duration
		frame_reports.append({"slug": slug, "duration": duration, "frames": FRAME_COUNT})
		for frame in range(FRAME_COUNT):
			var fraction: float = float(frame) / float(FRAME_COUNT - 1)
			if frame > 0:
				actor._process(duration / float(FRAME_COUNT - 1))
			else:
				actor._update_pose()
			stamp.text = "%.2f s / %.0f%% | actual Godot pose" % [duration * fraction, fraction * 100.0]
			await process_frame
			await RenderingServer.frame_post_draw
			var capture: Image = root.get_texture().get_image()
			capture.convert(Image.FORMAT_RGB8)
			assert(capture.save_png("%s/%s-%03d.png" % [output_dir, slug, frame]) == OK)
			var column: int = selected.find(frame)
			if column >= 0:
				contact.blit_rect(capture, Rect2i(Vector2i.ZERO, SIZE), Vector2i(column * SIZE.x, style * SIZE.y))
		print("DROP_PREVIEW ", slug, " duration=", duration)
		actor.queue_free()
		marks.queue_free()
		await process_frame
	assert(contact.save_png("res://qa/drop-knee-contact.png") == OK)
	var report := FileAccess.open(output_dir + "/frames.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(frame_reports, "\t"))
	print("DROP_PREVIEW contact=res://qa/drop-knee-contact.png frames=", output_dir)
	quit()

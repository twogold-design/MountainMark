extends Node3D
## Original alpine tower built from local procedural meshes.
var holds: Array[Dictionary] = []
var _rings: Array[MeshInstance3D] = []
var _materials: Array[StandardMaterial3D] = []
var _clouds: Array[Node3D] = []
var _flags: Array[MeshInstance3D] = []
var _rng := RandomNumberGenerator.new()
var _environment: Environment
var _elapsed: float = 0.0
var _built: bool = false
var _grass_material: StandardMaterial3D
var _pole_material: StandardMaterial3D

func build_world() -> void:
	if _built:
		return
	_built = true
	_rng.seed = 738194
	_grass_material = _material(Color("72794c"))
	_grass_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_pole_material = _material(Color("343b3b"))
	_build_light()
	_build_backdrop()
	_build_cliff()
	_build_route()
	_build_summit()
	_build_camp()

func _material(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.96
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	return mat

func _build_light() -> void:
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("25516a")
	sky_mat.sky_horizon_color = Color("d2d8cb")
	sky_mat.ground_bottom_color = Color("304b4f")
	sky_mat.ground_horizon_color = Color("c1cbbd")
	sky_mat.sky_curve = 0.16
	sky_mat.sun_angle_max = 18.0
	sky_mat.sun_curve = 0.10
	sky.sky_material = sky_mat
	_environment.sky = sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color("bbd2d4")
	_environment.ambient_light_energy = 0.43
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_environment.fog_enabled = true
	_environment.fog_light_color = Color("a5bcbc")
	_environment.fog_light_energy = 0.65
	_environment.fog_density = 0.0017
	var world_env := WorldEnvironment.new()
	world_env.environment = _environment
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34.0, -32.0, 0.0)
	sun.light_color = Color("fff0dd")
	sun.light_energy = 0.79
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110.0
	sun.shadow_bias = 0.05
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18.0, 142.0, 0.0)
	fill.light_color = Color("8fb8ce")
	fill.light_energy = 0.20
	add_child(fill)

func _build_cliff() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: int = 48
	var columns: int = 12
	var grid: Array = []
	for iy in range(rows + 1):
		var row: Array[Vector3] = []
		var yy: float = -4.0 + float(iy) * 78.0 / float(rows)
		var half_width: float = 7.2 + sin(yy * 0.11) * 0.7 + cos(yy * 0.27) * 0.4
		for ix in range(columns + 1):
			var xx: float = (float(ix) / float(columns) * 2.0 - 1.0) * half_width
			var y_offset: float = _rng.randf_range(-0.33, 0.33) if iy > 0 and iy < rows else 0.0
			var zz: float = _rng.randf_range(-0.31, -0.03)
			if ix == 0 or ix == columns:
				zz -= 1.2
			row.append(Vector3(xx + _rng.randf_range(-0.22, 0.22), yy + y_offset, zz))
		grid.append(row)
	for iy in range(rows):
		for ix in range(columns):
			var a: Vector3 = grid[iy][ix]
			var b: Vector3 = grid[iy][ix + 1]
			var c: Vector3 = grid[iy + 1][ix]
			var d: Vector3 = grid[iy + 1][ix + 1]
			var hue: Color = Color("8d7b67").lerp(Color("b29c80"), _rng.randf_range(0.0, 0.8))
			if iy % 9 <= 1:
				hue = hue.darkened(0.12)
			_triangle(surface, a, b, c, hue)
			_triangle(surface, b, d, c, hue.lightened(_rng.randf_range(-0.08, 0.08)))
	var cliff := MeshInstance3D.new()
	cliff.mesh = surface.commit()
	var vertex_material := _material(Color.WHITE)
	vertex_material.vertex_color_use_as_albedo = true
	vertex_material.vertex_color_is_srgb = true
	cliff.material_override = vertex_material
	add_child(cliff)
	for side in [-1.0, 1.0]:
		for i in range(9):
			var yy: float = float(i) * 8.5
			var xx: float = side * (7.1 + sin(yy * 0.11) * 0.55)
			var buttress := _rock(Vector3(xx, yy, -3.1), Vector3(3.1, 6.6, 3.7), Color("94735c"))
			buttress.rotation_degrees.z = side * _rng.randf_range(2.0, 9.0)
	var seam_mat := _material(Color("795e4b"))
	for i in range(62):
		var yy: float = _rng.randf_range(-1.0, 72.5)
		var xx: float = _rng.randf_range(-6.3, 6.3)
		var seam := _box(Vector3(xx, yy, 0.008), Vector3(_rng.randf_range(0.35, 1.8), 0.018, 0.012), seam_mat)
		seam.rotation.z = _rng.randf_range(-0.55, 0.55)
	for i in range(34):
		var yy: float = _rng.randf_range(2.0, 70.0)
		var side: float = -1.0 if i % 2 == 0 else 1.0
		_rock(Vector3(side * _rng.randf_range(4.2, 6.8), yy, -0.3), Vector3(_rng.randf_range(0.3, 0.9), 0.65, 0.30), Color("b49370"))

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var normal: Vector3 = (b - a).cross(c - a).normalized()
	# SurfaceTool colors need explicit linear conversion in Compatibility rendering.
	surface.set_color(color.srgb_to_linear())
	surface.set_normal(normal)
	surface.add_vertex(a)
	surface.add_vertex(c)
	surface.add_vertex(b)

func _build_route() -> void:
	var count: int = 57
	for i in range(count):
		var yy: float = 1.0 + float(i) * 71.0 / float(count - 1)
		var xx: float = sin(float(i) * 0.29) * 2.0 + sin(float(i) * 0.71) * 0.45
		if i == 0:
			xx = 0.0
		var checkpoint: bool = i == 0 or i == 14 or i == 28 or i == 42 or i == 56
		var is_rest: bool = i % 7 == 0
		_add_hold(Vector3(xx, yy, 0.45), is_rest, checkpoint)
		if is_rest:
			_make_ledge(Vector3(xx, yy - 1.7, 0.0), checkpoint)
		if i % 4 == 2 and i < count - 2:
			_add_hold(Vector3(xx + (0.95 if i % 8 == 2 else -0.95), yy + 0.12, 0.45), false, false)

func _add_hold(pos: Vector3, rest_hold: bool, checkpoint: bool) -> void:
	var idx: int = holds.size()
	holds.append({"id": idx, "position": pos, "rest": rest_hold, "checkpoint": checkpoint})
	var color: Color = Color("f5c16c") if rest_hold else Color("e7ddc7")
	var mat := _material(color, 0.13)
	var grip := MeshInstance3D.new()
	var grip_mesh := SphereMesh.new()
	grip_mesh.radial_segments = 7
	grip_mesh.rings = 3
	grip_mesh.radius = 1.0
	grip_mesh.height = 2.0
	grip.mesh = grip_mesh
	grip.position = pos
	grip.scale = Vector3(0.24, 0.12, 0.16) if rest_hold else Vector3(0.18, 0.10, 0.14)
	grip.rotation.z = _rng.randf_range(-0.25, 0.25)
	grip.material_override = mat
	add_child(grip)
	_materials.append(mat)
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.28
	ring_mesh.outer_radius = 0.31
	ring_mesh.rings = 24
	ring_mesh.ring_segments = 6
	ring.mesh = ring_mesh
	ring.rotation.x = PI / 2.0
	ring.position = pos + Vector3(0.0, 0.0, 0.04)
	ring.material_override = _material(Color("e8f1d4"), 0.65)
	ring.visible = false
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	_rings.append(ring)
	var chalk := _box(pos + Vector3(0.0, -0.18, -0.36), Vector3(0.12, 0.052, 0.018), _material(Color("e9d8b5")))
	chalk.rotation.z = -0.15
	if checkpoint:
		var bolt := _box(pos + Vector3(0.48, -0.20, -0.16), Vector3(0.065, 0.18, 0.08), _pole_material)
		bolt.rotation.z = 0.10
		_flag(pos + Vector3(0.85, -1.62, 0.4), 0.65, Color("e29a4d"))

func _make_ledge(pos: Vector3, large: bool) -> void:
	var width: float = 2.2 if large else 1.2
	var ledge := _rock(pos + Vector3(0.0, -0.11, -0.12), Vector3(width, 0.25, 0.62), Color("977757"))
	ledge.rotation.z = -0.025
	_box(pos + Vector3(0.0, 0.06, 0.05), Vector3(width * 1.5, 0.08, 0.68), _grass_material)
	for k in range(5 if large else 2):
		_grass(pos + Vector3(_rng.randf_range(-width * 0.7, width * 0.7), 0.10, _rng.randf_range(0.05, 0.3)), _rng.randf_range(0.16, 0.32))

func _build_backdrop() -> void:
	for layer in range(4):
		var zz: float = -45.0 - float(layer) * 48.0
		var base_color: Color = Color("38525c").lerp(Color("94a9b3"), float(layer) / 4.3)
		for i in range(10):
			var xx: float = -180.0 + float(i) * 40.0 + _rng.randf_range(-12.0, 12.0)
			var height: float = _rng.randf_range(59.0, 94.0) + float(layer) * 10.0
			var base_y: float = -35.0 - float(layer) * 2.0
			_mountain(Vector3(xx, base_y, zz), Vector3(_rng.randf_range(32.0, 48.0), height, 26.0), base_color, layer >= 2)
	for side in [-1.0, 1.0]:
		for i in range(5):
			var depth: float = -20.0 - float(i) * 13.0
			var horizontal: float = side * (24.0 + float(i) * 15.0)
			_mountain(Vector3(horizontal, -32.0, depth), Vector3(15.0 + float(i) * 3.0, 55.0 + float(i % 3) * 12.0, 15.0), Color("3d5961").lightened(float(i) * 0.035), false)
	var ground := _box(Vector3(0.0, -34.5, -10.0), Vector3(220.0, 1.0, 180.0), _material(Color("4c655a")))
	ground.rotation.z = -0.02
	var cloud_mat := _material(Color(0.78, 0.84, 0.82, 0.20))
	cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cloud_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in range(17):
		var cloud := Node3D.new()
		cloud.position = Vector3(_rng.randf_range(-95.0, 95.0), _rng.randf_range(-6.0, 35.0), _rng.randf_range(-120.0, -32.0))
		add_child(cloud)
		for k in range(3):
			var puff := MeshInstance3D.new()
			var puff_mesh := SphereMesh.new()
			puff_mesh.radial_segments = 12
			puff_mesh.rings = 6
			puff.mesh = puff_mesh
			puff.material_override = cloud_mat
			puff.position = Vector3(float(k - 1) * 8.0, 0.0, float(k % 2) * 2.0)
			puff.scale = Vector3(25.0, 2.1, 8.0)
			puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cloud.add_child(puff)
		_clouds.append(cloud)

func _mountain(pos: Vector3, dimensions: Vector3, color: Color, snow: bool) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var apex := Vector3(dimensions.x * 0.11, dimensions.y, -dimensions.z * 0.2)
	var points: Array[Vector3] = [Vector3(-dimensions.x, 0, dimensions.z), Vector3(dimensions.x * 0.18, dimensions.y * 0.30, dimensions.z), Vector3(dimensions.x, 0, dimensions.z * 0.5), Vector3(dimensions.x * 0.7, 0, -dimensions.z), Vector3(-dimensions.x, 0, -dimensions.z)]
	for i in range(points.size()):
		var a: Vector3 = points[i]
		var b: Vector3 = points[(i + 1) % points.size()]
		var face_color: Color = color.lightened(float(i % 3) * 0.065)
		_triangle(surface, a, b, apex, face_color)
		if snow:
			var snow_offset: Vector3 = (b - a).cross(apex - a).normalized() * 0.20
			_triangle(surface, a.lerp(apex, 0.77) + snow_offset, b.lerp(apex, 0.80) + snow_offset, apex + snow_offset, Color("bccbd0").lerp(face_color, 0.35))
	var instance := MeshInstance3D.new()
	instance.mesh = surface.commit()
	var mat := _material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.material_override = mat
	instance.position = pos
	add_child(instance)

func _build_summit() -> void:
	_rock(Vector3(0.0, 73.0, -5.4), Vector3(7.6, 1.1, 5.0), Color("bb9975"))
	_box(Vector3(0.0, 73.85, -3.0), Vector3(11.8, 0.20, 8.0), _grass_material)
	for i in range(22):
		_grass(Vector3(_rng.randf_range(-5.0, 5.0), 73.98, _rng.randf_range(-6.0, -0.6)), _rng.randf_range(0.2, 0.5))
	_flag(Vector3(1.8, 74.0, -0.8), 3.0, Color("e8a74f"))
	for i in range(5):
		var size: float = 0.50 - float(i) * 0.075
		_rock(Vector3(-1.9, 74.05 + float(i) * 0.18, -1.2), Vector3(size, 0.14, size * 0.8), Color("d1b593"))

func _build_camp() -> void:
	_rock(Vector3(0.0, -18.0, -6.0), Vector3(13.0, 18.0, 12.0), Color("667163"))
	_rock(Vector3(0.0, -1.3, 1.0), Vector3(6.5, 0.6, 4.0), Color("797561"))
	var tent_surface := SurfaceTool.new()
	tent_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_triangle(tent_surface, Vector3(-1.1, 0, 0), Vector3(1.1, 0, 0), Vector3(0, 1.35, 0), Color.WHITE)
	_triangle(tent_surface, Vector3(-1.1, 0, 0), Vector3(0, 1.35, 0), Vector3(-1.1, 0, -1.9), Color.WHITE)
	_triangle(tent_surface, Vector3(-1.1, 0, -1.9), Vector3(0, 1.35, 0), Vector3(0, 1.35, -1.9), Color.WHITE)
	_triangle(tent_surface, Vector3(0, 1.35, 0), Vector3(1.1, 0, 0), Vector3(1.1, 0, -1.9), Color.WHITE)
	_triangle(tent_surface, Vector3(0, 1.35, 0), Vector3(1.1, 0, -1.9), Vector3(0, 1.35, -1.9), Color.WHITE)
	var tent := MeshInstance3D.new()
	tent.mesh = tent_surface.commit()
	var tent_mat := _material(Color("d88a4a"))
	tent_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	tent.material_override = tent_mat
	tent.position = Vector3(-3.1, -0.75, 2.1)
	add_child(tent)
	for i in range(12):
		_grass(Vector3(_rng.randf_range(-5.0, 5.0), -0.70, _rng.randf_range(0.8, 3.0)), 0.3)

func _box(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	instance.mesh = box
	instance.position = pos
	instance.material_override = mat
	add_child(instance)
	return instance

func _rock(pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertices: Array = []
	var radii: Array[float] = [0.60, 1.0, 0.91, 0.51]
	var heights: Array[float] = [-1.0, -0.44, 0.44, 1.0]
	var segments: int = 7
	for ring in range(4):
		var row: Array[Vector3] = []
		for i in range(segments):
			var angle: float = float(i) * TAU / float(segments)
			row.append(Vector3(cos(angle) * radii[ring], heights[ring], -sin(angle) * radii[ring]))
		vertices.append(row)
	for ring in range(3):
		for i in range(segments):
			var n: int = (i + 1) % segments
			var a: Vector3 = vertices[ring][i]
			var b: Vector3 = vertices[ring][n]
			var c: Vector3 = vertices[ring + 1][i]
			var d: Vector3 = vertices[ring + 1][n]
			_triangle(surface, a, b, c, color)
			_triangle(surface, b, d, c, color)
	for i in range(segments):
		_triangle(surface, vertices[3][i], vertices[3][(i + 1) % segments], Vector3(0, 1, 0), color)
	var instance := MeshInstance3D.new()
	instance.mesh = surface.commit()
	instance.position = pos
	instance.scale = size
	var mat := _material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	instance.material_override = mat
	add_child(instance)
	return instance
func _grass(pos: Vector3, size: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(4):
		var angle: float = float(i) * PI / 4.0
		var span := Vector3(cos(angle), 0.0, sin(angle)) * size * 0.55
		_triangle(surface, -span, span, Vector3(size * 0.25, size * _rng.randf_range(0.8, 1.4), 0.0), Color.WHITE)
	var instance := MeshInstance3D.new()
	instance.mesh = surface.commit()
	instance.position = pos
	instance.material_override = _grass_material
	add_child(instance)

func _flag(pos: Vector3, height: float, color: Color) -> void:
	_box(pos + Vector3(0.0, height * 0.5, 0.0), Vector3(0.035, height, 0.035), _pole_material)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_triangle(surface, Vector3.ZERO, Vector3(height * 0.56, -height * 0.12, 0.05), Vector3(0.0, -height * 0.29, 0.0), Color.WHITE)
	var flag := MeshInstance3D.new()
	flag.mesh = surface.commit()
	var mat := _material(color)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	flag.material_override = mat
	flag.position = pos + Vector3(0.0, height * 0.96, 0.0)
	add_child(flag)
	_flags.append(flag)

func set_hold_feedback(reachable_ids: Array, selected_id: int, used_id: int) -> void:
	for i in range(holds.size()):
		var reachable: bool = reachable_ids.has(i)
		var selected: bool = i == selected_id
		var used: bool = i == used_id
		_rings[i].visible = reachable or selected
		_rings[i].scale = Vector3.ONE * (1.25 if selected else 1.0)
		var base_color: Color = Color("f5c16c") if bool(holds[i]["rest"]) else Color("e7ddc7")
		_materials[i].albedo_color = Color("8fcdba") if used else (Color("fff5cc") if selected else base_color)
		_materials[i].emission_energy_multiplier = 0.5 if selected else (0.20 if reachable else 0.08)

func update_atmosphere(progress: float, delta: float) -> void:
	_elapsed += delta
	for i in range(_clouds.size()):
		_clouds[i].position.x += delta * (0.13 + float(i % 3) * 0.025)
		if _clouds[i].position.x > 145.0:
			_clouds[i].position.x = -145.0
	for i in range(_flags.size()):
		_flags[i].rotation.y = sin(_elapsed * 3.2 + float(i)) * 0.16
		_flags[i].rotation.z = sin(_elapsed * 4.0 + float(i)) * 0.025
	_environment.fog_density = lerpf(0.0017, 0.0011, clampf(progress, 0.0, 1.0))

func get_summit_position() -> Vector3:
	return Vector3(0.0, 74.0, -0.8)







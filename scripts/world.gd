extends Node3D
const TerrainMaterials = preload("res://scripts/terrain_materials.gd")
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
var route_id: String = "ridge"
var _route_height: float = 72.0
var _route: Dictionary = {}
var _water_strands: Array[MeshInstance3D] = []
var _wind_ribbons: Array[MeshInstance3D] = []
var _birds: Array[Node3D] = []
var _collectibles: Dictionary = {}
var _rock_color: Color = Color("8d7b67")
var _rock_highlight: Color = Color("b29c80")
var _snow_material: Material

func build_world(route: Dictionary = {}) -> void:
	if _built:
		return
	_built = true
	_route = route
	set_theme(str(route.get("id", "ridge")))
	_route_height = float(route.get("height", 72.0))
	_rng.seed = 738194
	_grass_material = _material(Color("72794c"))
	if route_id == "canyon":
		_grass_material = _material(Color("49775d"))
		_rock_color = Color("4f6867")
		_rock_highlight = Color("7e9690")
	elif route_id == "summit":
		_grass_material = _material(Color("d5e3e4"))
		_rock_color = Color("677785")
		_rock_highlight = Color("a9b5bd")
	_grass_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_snow_material = TerrainMaterials.snow()
	_pole_material = _material(Color("343b3b"))
	_build_light()
	_build_backdrop()
	_build_cliff()
	_build_route()
	_build_summit()
	_build_camp()
	_build_theme_scenery()

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
	if route_id == "ridge":
		sky_mat.sky_top_color = Color("438199")
		sky_mat.sky_horizon_color = Color("e7d5b0")
	elif route_id == "canyon":
		sky_mat.sky_top_color = Color("3b6873")
		sky_mat.sky_horizon_color = Color("a2c6bc")
	else:
		sky_mat.sky_top_color = Color("264d7d")
		sky_mat.sky_horizon_color = Color("e1d9db")
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
	if route_id == "canyon":
		_environment.fog_light_color = Color("87b2ac")
		_environment.ambient_light_color = Color("aad4cc")
		_environment.ambient_light_energy = 0.52
	elif route_id == "summit":
		_environment.fog_light_color = Color("bdcddd")
		_environment.ambient_light_color = Color("bccfe3")
	var world_env := WorldEnvironment.new()
	world_env.environment = _environment
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34.0, -32.0, 0.0)
	sun.light_color = Color("fff0dd")
	sun.light_energy = 0.79
	if route_id == "ridge":
		sun.rotation_degrees = Vector3(-24.0, -38.0, 0.0)
		sun.light_color = Color("ffe0ab")
	elif route_id == "canyon":
		sun.rotation_degrees = Vector3(-58.0, -20.0, 0.0)
		sun.light_color = Color("dcefdc")
		sun.light_energy = 0.66
	else:
		sun.light_color = Color("fff2ee")
		sun.light_energy = 0.93
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
	# A continuous eroded height field shares vertices and normals across the face.
	var rows: int = int(ceil((_route_height + 6.0) / 0.48))
	var columns: int = 52
	var vertices := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	var erosion := FastNoiseLite.new()
	erosion.seed = 36181
	erosion.frequency = 0.43
	erosion.fractal_octaves = 4
	for iy in range(rows + 1):
		var yy: float = -4.0 + float(iy) * (_route_height + 6.0) / float(rows)
		var half_width: float = 7.2 + sin(yy * 0.11) * 0.7 + cos(yy * 0.27) * 0.4
		for ix in range(columns + 1):
			var fraction: float = float(ix) / float(columns)
			var xx: float = (fraction * 2.0 - 1.0) * half_width
			var wave: float = sin(yy * 0.71 + xx * 0.31) * 0.10
			var grooves: float = pow(absf(sin(xx * 1.1 + sin(yy * 0.13) * 0.65)), 8.0) * 0.12
			var zz: float = -0.23 + erosion.get_noise_2d(xx, yy) * 0.25 + wave - grooves
			zz -= pow(absf(fraction * 2.0 - 1.0), 10.0) * 1.6
			vertices.append(Vector3(xx, yy, minf(zz, 0.06)))
			uv.append(Vector2(xx, yy) * 0.25)
	for iy in range(rows):
		for ix in range(columns):
			var a: int = iy * (columns + 1) + ix
			var b: int = a + 1
			var c: int = a + columns + 1
			indices.append_array(PackedInt32Array([a, c, b, b, c, c + 1]))
	var cliff := MeshInstance3D.new()
	cliff.name = "ContinuousRockFace"
	cliff.mesh = _smooth_mesh(vertices, indices, uv)
	cliff.material_override = TerrainMaterials.rock(_rock_color.lerp(_rock_highlight, 0.25), route_id)
	add_child(cliff)
	for side in [-1.0, 1.0]:
		for i in range(int(ceil(_route_height / 8.5))):
			var yy: float = float(i) * 8.5
			var xx: float = side * (7.1 + sin(yy * 0.11) * 0.55)
			var buttress := _rock(Vector3(xx, yy, -3.1), Vector3(3.1, 6.6, 3.7), _rock_color.darkened(0.1))
			buttress.rotation_degrees.z = side * _rng.randf_range(2.0, 9.0)
	for i in range(maxi(6, int(_route_height * 0.47))):
		var yy: float = _rng.randf_range(2.0, _route_height - 2.0)
		var side: float = -1.0 if i % 2 == 0 else 1.0
		_rock(Vector3(side * _rng.randf_range(4.2, 6.8), yy, -0.3), Vector3(_rng.randf_range(0.3, 0.9), 0.65, 0.30), _rock_highlight)

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var normal: Vector3 = (b - a).cross(c - a).normalized()
	# SurfaceTool colors need explicit linear conversion in Compatibility rendering.
	surface.set_color(color.srgb_to_linear())
	surface.set_normal(normal)
	surface.add_vertex(a)
	surface.add_vertex(c)
	surface.add_vertex(b)

func _build_route() -> void:
	var supplied: Array = _route.get("holds", [])
	if not supplied.is_empty():
		for hold in supplied:
			var pos: Vector3 = hold["position"]
			_add_hold(pos, bool(hold.get("rest", false)), bool(hold.get("checkpoint", false)), hold)
			if bool(hold.get("rest", false)):
				_make_ledge(pos - Vector3(0.0, 1.7, 0.45), bool(hold.get("checkpoint", false)))
		return
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

func _add_hold(pos: Vector3, rest_hold: bool, checkpoint: bool, data: Dictionary = {}) -> void:
	var idx: int = holds.size()
	holds.append(data.duplicate(true) if not data.is_empty() else {"id": idx, "position": pos, "rest": rest_hold, "checkpoint": checkpoint})
	var color: Color = _hold_color(holds[-1])
	var mat := _material(color, 0.13)
	var grip := MeshInstance3D.new()
	var grip_mesh := SphereMesh.new()
	grip_mesh.radial_segments = 24
	grip_mesh.rings = 12
	grip_mesh.radius = 1.0
	grip_mesh.height = 2.0
	grip.mesh = grip_mesh
	grip.position = pos
	grip.scale = Vector3(0.24, 0.12, 0.16) if rest_hold else Vector3(0.18, 0.10, 0.14)
	if str(data.get("kind", "normal")) == "small":
		grip.scale = Vector3(0.14, 0.065, 0.13)
	if str(data.get("kind", "normal")) == "wet":
		mat.roughness = 0.15
		mat.metallic = 0.15
		var patch := _rock(pos - Vector3(0.0, 0.06, 0.51), Vector3(0.45, 0.65, 0.06), _rock_color.darkened(0.22))
		patch.rotation.z = _rng.randf_range(-0.3, 0.3)
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
	if not str(data.get("collectible", "")).is_empty():
		_make_collectible(pos, str(data["collectible"]))
	if str(data.get("branch", "main")) == "shortcut":
		var mark := _box(pos + Vector3(0.28, -0.1, -0.36), Vector3(0.04, 0.11, 0.02), _material(Color("cd9470")))
		mark.rotation.z = -0.45
	if str(data.get("kind", "normal")) == "wind":
		_make_wind_ribbon(pos + Vector3(0.5, -0.1, -0.15), 0.5)

func _make_ledge(pos: Vector3, large: bool) -> void:
	var width: float = 2.2 if large else 1.2
	var ledge := _rock(pos + Vector3(0.0, -0.23, -0.12), Vector3(width, 0.25, 0.62), _rock_color)
	ledge.rotation.z = -0.025
	var turf := _rock(pos + Vector3(0.0, 0.06, 0.05), Vector3(width * 0.75, 0.04, 0.34), _grass_material.albedo_color)
	turf.material_override = _snow_material if route_id == "summit" else TerrainMaterials.ground(_grass_material.albedo_color)
	if route_id != "summit":
		for k in range(5 if large else 2):
			_grass(pos + Vector3(_rng.randf_range(-width * 0.7, width * 0.7), 0.10, _rng.randf_range(0.05, 0.3)), _rng.randf_range(0.16, 0.32))
	if large:
		_cairn(pos + Vector3(-width * 0.6, 0.1, 0.1), 0.38)
		if route_id == "ridge":
			_pine(pos + Vector3(width * 0.7, 0.1, -0.12), 1.0)
		elif route_id == "canyon":
			_fern(pos + Vector3(width * 0.7, 0.1, -0.1), 0.65)

func _build_backdrop() -> void:
	for layer in range(4):
		var zz: float = -45.0 - float(layer) * 48.0
		var base_color: Color = Color("38525c").lerp(Color("94a9b3"), float(layer) / 4.3)
		if route_id == "canyon":
			base_color = Color("234e4c").lerp(Color("8db4a8"), float(layer) / 4.3)
		elif route_id == "summit":
			base_color = Color("4f6680").lerp(Color("b6c5d4"), float(layer) / 4.3)
		for i in range(10):
			var xx: float = -180.0 + float(i) * 40.0 + _rng.randf_range(-12.0, 12.0)
			var height: float = _rng.randf_range(59.0, 94.0) + float(layer) * 10.0 + maxf(0.0, _route_height - 72.0) * 0.5
			var base_y: float = -35.0 - float(layer) * 2.0
			_mountain(Vector3(xx, base_y, zz), Vector3(_rng.randf_range(32.0, 48.0), height, 26.0), base_color, route_id == "summit" or (route_id == "ridge" and layer >= 2))
	for side in [-1.0, 1.0]:
		for i in range(5):
			var depth: float = -20.0 - float(i) * 13.0
			var horizontal: float = side * (24.0 + float(i) * 15.0)
			_mountain(Vector3(horizontal, -32.0, depth), Vector3(15.0 + float(i) * 3.0, 55.0 + float(i % 3) * 12.0, 15.0), Color("3d5961").lightened(float(i) * 0.035), false)
	var ground := _box(Vector3(0.0, -34.5, -10.0), Vector3(220.0, 1.0, 180.0), _material(Color("4c655a")))
	ground.rotation.z = -0.02
	for i in range(17):
		var center := Vector3(_rng.randf_range(-95.0, 95.0), _rng.randf_range(-6.0, 35.0), _rng.randf_range(-120.0, -32.0))
		for k in range(3):
			_cloud_puff(center + Vector3(float(k - 1) * 10.0, float(k % 2), float(k) * 0.7), Vector2(38.0, 10.0))

func _mountain(pos: Vector3, dimensions: Vector3, color: Color, snow: bool) -> void:
	var cols: int = 36
	var rows: int = 28
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	var relief := FastNoiseLite.new()
	relief.seed = int(absf(pos.x * 317.0 + pos.z * 119.0)) + 840
	relief.frequency = 0.90
	relief.fractal_octaves = 4
	for iz in range(rows + 1):
		var zz: float = float(iz) / float(rows) * 2.0 - 1.0
		for ix in range(cols + 1):
			var xx: float = float(ix) / float(cols) * 2.0 - 1.0
			var edge: float = pow(maxf(0.0, (1.0 - xx * xx) * (1.0 - zz * zz)), 0.70)
			var main_peak: float = exp(-((xx - 0.11) * (xx - 0.11) * 3.2 + (zz + 0.10) * (zz + 0.10) * 2.5))
			var side_peak: float = exp(-((xx + 0.50) * (xx + 0.50) * 6.0 + (zz - 0.20) * (zz - 0.20) * 4.0))
			var shoulder: float = exp(-((xx - 0.57) * (xx - 0.57) * 7.0 + (zz + 0.32) * (zz + 0.32) * 4.5))
			var ridges: float = relief.get_noise_2d(xx * 2.8, zz * 2.8)
			var h: float = edge * (0.16 + main_peak * 0.65 + side_peak * 0.28 + shoulder * 0.30 + ridges * 0.07)
			vertices.append(Vector3(xx * dimensions.x, h * dimensions.y, zz * dimensions.z))
			uv.append(Vector2(xx, zz))
			var snow_amount: float = smoothstep(0.54 + ridges * 0.12, 0.72 + ridges * 0.12, h) if snow else 0.0
			colors.append(color.lerp(Color("dde5e8"), snow_amount * 0.92).srgb_to_linear())
	for iz in range(rows):
		for ix in range(cols):
			var a: int = iz * (cols + 1) + ix
			var c: int = a + cols + 1
			indices.append_array(PackedInt32Array([a, a + 1, c, a + 1, c + 1, c]))
	var instance := MeshInstance3D.new()
	instance.mesh = _smooth_mesh(vertices, indices, uv, colors)
	instance.material_override = TerrainMaterials.rock(Color.WHITE, "distant")
	instance.position = pos
	add_child(instance)

func _build_summit() -> void:
	var top: float = _route_height + 2.0
	_rock(Vector3(0.0, top - 1.3, -5.4), Vector3(7.6, 1.1, 5.0), _rock_highlight)
	var turf := _rock(Vector3(0.0, top - 0.15, -3.0), Vector3(6.4, 0.15, 4.7), Color("d8e7e8") if route_id == "summit" else (Color("597f66") if route_id == "canyon" else Color("81865b")))
	turf.material_override = _snow_material if route_id == "summit" else TerrainMaterials.ground(_grass_material.albedo_color)
	if route_id != "summit":
		for i in range(22):
			_grass(Vector3(_rng.randf_range(-5.0, 5.0), top - 0.02, _rng.randf_range(-6.0, -0.6)), _rng.randf_range(0.2, 0.5))
	_flag(Vector3(1.8, top, -0.8), 3.0, Color("e8a74f"))
	_cairn(Vector3(-1.9, top + 0.05, -1.2), 0.9)
	_box(Vector3(-3.1, top + 0.12, -2.1), Vector3(0.5, 0.24, 0.35), _material(Color("aa7452")))
	_box(Vector3(-3.1, top + 0.25, -2.1), Vector3(0.55, 0.025, 0.39), _pole_material)
	if route_id == "ridge":
		_pine(Vector3(-4.0, top, -4.3), 3.8)
		_pine(Vector3(4.0, top, -5.5), 2.8)
		_bench(Vector3(-3.3, top, -3.0))
	elif route_id == "canyon":
		_fern(Vector3(-4.2, top, -3.0), 1.1)
		_fern(Vector3(3.6, top, -4.0), 1.0)
		_waterfall(Vector3(5.6, top - 0.15, 0.85), 1.7, minf(12.0, _route_height * 0.6))
	else:
		for i in range(9):
			_rock(Vector3(_rng.randf_range(-5.0, 5.0), top + 0.12, _rng.randf_range(-7.0, -3.0)), Vector3(1.4, 0.25, 0.7), Color("e2eceb"))
		_make_wind_ribbon(Vector3(-2.1, top + 0.7, -1.4), 2.0)


func _build_camp() -> void:
	_rock(Vector3(0.0, -19.0, -6.0), Vector3(13.0, 18.0, 12.0), Color("667163"))
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
	var tent_mat := _material(Color("c16c50") if route_id == "summit" else (Color("ad8260") if route_id == "canyon" else Color("d88a4a")))
	tent_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	tent.material_override = tent_mat
	tent.position = Vector3(-3.1, -0.75, 2.1)
	add_child(tent)
	if route_id != "summit":
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
	# Rounded eroded blocks retain broad shelves and a stone silhouette.
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var uv := PackedVector2Array()
	var segments: int = 28
	var rings: int = 16
	var phase: float = _rng.randf() * TAU
	for ring in range(rings + 1):
		var v: float = float(ring) / float(rings)
		var latitude: float = v * PI - PI * 0.5
		var yy: float = clampf(signf(sin(latitude)) * pow(absf(sin(latitude)), 0.56) * 1.20, -1.0, 1.0)
		var radius: float = pow(maxf(0.0, cos(latitude)), 0.40)
		for i in range(segments):
			var angle: float = float(i) * TAU / float(segments)
			var xx: float = signf(cos(angle)) * pow(absf(cos(angle)), 0.62)
			var zz: float = signf(sin(angle)) * pow(absf(sin(angle)), 0.62)
			var erosion: float = 0.95 + sin(angle * 3.0 + phase + yy * 0.7) * 0.035 + cos(angle * 5.0 - yy * 1.8 + phase) * 0.025
			vertices.append(Vector3(xx * radius * erosion + yy * 0.035, yy, -zz * radius * erosion))
			uv.append(Vector2(float(i) / float(segments), v))
	for ring in range(rings):
		for i in range(segments):
			var a: int = ring * segments + i
			var c: int = a + segments
			var b: int = ring * segments + (i + 1) % segments
			var d: int = b + segments
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	var instance := MeshInstance3D.new()
	instance.mesh = _smooth_mesh(vertices, indices, uv)
	instance.position = pos
	instance.scale = size
	instance.material_override = TerrainMaterials.snow(color) if color.r > 0.78 and color.g > 0.83 else TerrainMaterials.rock(color, route_id)
	add_child(instance)
	return instance

func _smooth_mesh(vertices: PackedVector3Array, indices: PackedInt32Array, uv: PackedVector2Array, colors: PackedColorArray = PackedColorArray()) -> ArrayMesh:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for i in range(0, indices.size(), 3):
		var a: int = indices[i]
		var b: int = indices[i + 1]
		var c: int = indices[i + 2]
		var normal: Vector3 = (vertices[c] - vertices[a]).cross(vertices[b] - vertices[a])
		normals[a] += normal
		normals[b] += normal
		normals[c] += normal
	for i in range(normals.size()):
		normals[i] = normals[i].normalized()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	if not colors.is_empty():
		arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _grass(pos: Vector3, size: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(13):
		var angle: float = _rng.randf() * TAU
		var lean := Vector3(cos(angle), 0.0, sin(angle)) * size * _rng.randf_range(0.18, 0.45)
		var side := Vector3(-sin(angle), 0.0, cos(angle)) * size * 0.024
		var height: float = size * _rng.randf_range(0.65, 1.45)
		var base := Vector3(_rng.randf_range(-0.09, 0.09), 0.0, _rng.randf_range(-0.09, 0.09)) * size
		for j in range(3):
			var t0: float = float(j) / 3.0
			var t1: float = float(j + 1) / 3.0
			var a: Vector3 = base + lean * t0 * t0 + Vector3.UP * height * t0
			var b: Vector3 = base + lean * t1 * t1 + Vector3.UP * height * t1
			_triangle(surface, a - side * (1.0 - t0), a + side * (1.0 - t0), b - side * (1.0 - t1), Color.WHITE)
			_triangle(surface, a + side * (1.0 - t0), b + side * (1.0 - t1), b - side * (1.0 - t1), Color.WHITE)
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
		var base_color: Color = _hold_color(holds[i])
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
	for i in range(_water_strands.size()):
		var strand: MeshInstance3D = _water_strands[i]
		strand.position.y = float(strand.get_meta("top")) - fmod(_elapsed * (2.5 + float(i % 4) * 0.45) + float(i) * 1.33, float(strand.get_meta("fall")))
	for i in range(_wind_ribbons.size()):
		_wind_ribbons[i].rotation.y = sin(_elapsed * 2.6 + float(i)) * (0.18 + get_wind_strength() * 0.55)
		_wind_ribbons[i].rotation.z = sin(_elapsed * 4.2 + float(i)) * 0.11
	for i in range(_birds.size()):
		var phase: float = _elapsed * 0.12 + float(i) * 1.8
		_birds[i].position = Vector3(sin(phase) * 24.0, _route_height * 0.65 + sin(phase * 1.7) * 6.0, -20.0 + cos(phase) * 12.0)
		_birds[i].rotation.y = -phase
	var base_fog: float = 0.0026 if route_id == "canyon" else 0.0017
	_environment.fog_density = lerpf(base_fog, 0.0010, clampf(progress, 0.0, 1.0))

func get_summit_position() -> Vector3:
	return Vector3(0.0, _route_height + 2.0, -0.8)







func set_theme(theme: String) -> void:
	if theme in ["canyon", "echo", "echo_canyon"]:
		route_id = "canyon"
	elif theme in ["summit", "cloud", "cloud_peak", "peak"]:
		route_id = "summit"
	else:
		route_id = "ridge"

func get_wind_strength() -> float:
	return clampf(0.5 + sin(_elapsed * 0.72) * 0.34 + sin(_elapsed * 0.23 + 0.8) * 0.16, 0.0, 1.0)

func _hold_color(data: Dictionary) -> Color:
	if bool(data.get("rest", false)):
		return Color("f5c16c")
	match str(data.get("kind", "normal")):
		"wet": return Color("9fdedc")
		"small": return Color("d8b6a3")
		"wind": return Color("dde5f1")
		"traverse": return Color("d5ddab")
	return Color("e7ddc7")

func _build_theme_scenery() -> void:
	# Near-wall details stay on the shoulders, preserving the readable climbing corridor.
	_signpost(Vector3(3.7, -0.65, 1.0))
	_bench(Vector3(2.7, -0.7, 2.5))
	_camp_props()
	match route_id:
		"ridge":
			_build_pine_ridge()
		"canyon":
			_build_echo_canyon()
		"summit":
			_build_cloud_peak()
	_build_birds()

func _build_pine_ridge() -> void:
	for side in [-1.0, 1.0]:
		for i in range(11):
			var pos := Vector3(side * (8.2 + _rng.randf_range(0.0, 5.0)), -1.4 + float(i) * 0.22, -2.0 - float(i) * 2.8)
			_rock(pos - Vector3(0.0, 1.1, 0.0), Vector3(3.8, 1.2, 3.4), Color("66725a"))
			_pine(pos, _rng.randf_range(3.0, 6.0))
		for i in range(maxi(1, int(_route_height / 12.0))):
			var yy: float = 6.0 + float(i) * (_route_height - 8.0) / float(maxi(1, int(_route_height / 12.0)))
			var pos := Vector3(side * _rng.randf_range(5.8, 7.0), yy, -0.7)
			_rock(pos - Vector3(0.0, 0.1, 0.2), Vector3(1.4, 0.24, 0.8), _rock_color)
			_pine(pos + Vector3(0.0, 0.1, 0.0), _rng.randf_range(1.3, 2.2))
			for k in range(3):
				_grass(pos + Vector3(float(k) * 0.25 - 0.3, 0.1, 0.1), 0.25)
	for i in range(maxi(5, int(_route_height * 0.33))):
		var y: float = _rng.randf_range(2.0, _route_height - 2.0)
		var side: float = -1.0 if i % 2 == 0 else 1.0
		_rock(Vector3(side * _rng.randf_range(3.8, 6.0), y, -0.10), Vector3(0.6, 0.22, 0.09), Color("818353"))
	for i in range(4):
		_pine(Vector3(-5.8 + float(i) * 3.8, -1.0, -7.0), 2.8 + float(i % 2))

func _build_echo_canyon() -> void:
	for side in [-1.0, 1.0]:
		for i in range(6):
			var yy: float = float(i) * _route_height / 6.0 - 7.0
			var pos := Vector3(side * (12.0 + float(i % 2) * 1.5), yy, -8.0)
			_rock(pos, Vector3(5.8, 10.0, 7.0), Color("3e6260").lightened(float(i % 3) * 0.035))
			_fern(pos + Vector3(-side * 2.7, 8.0, 6.6), 1.5)
		_waterfall(Vector3(side * 6.25, _route_height * (0.65 if side < 0.0 else 0.84), 0.85), 1.0 if side < 0.0 else 1.5, _route_height * 0.57)
	# A continuous river ribbon follows the valley, without rectangular tile joins.
	var river_vertices := PackedVector3Array()
	var river_uv := PackedVector2Array()
	var river_indices := PackedInt32Array()
	for i in range(81):
		var distance: float = float(i) * 1.6
		var xx: float = 17.0 + sin(distance * 0.045) * 7.5
		for side in [0.0, 1.0]:
			river_vertices.append(Vector3(xx + (side - 0.5) * 7.0, -8.0 - distance * 0.018, -distance))
			river_uv.append(Vector2(side, distance * 0.03))
		if i < 80:
			var a: int = i * 2
			river_indices.append_array(PackedInt32Array([a, a + 2, a + 1, a + 1, a + 2, a + 3]))
	var river := MeshInstance3D.new()
	river.mesh = _smooth_mesh(river_vertices, river_indices, river_uv)
	river.material_override = TerrainMaterials.water()
	river.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(river)
	for i in range(11):
		var distance: float = float(i) * 12.0
		var xx: float = 17.0 + sin(distance * 0.045) * 7.5
		_rock(Vector3(xx - 5.2, -8.8 - distance * 0.018, -distance), Vector3(4.2, 1.0, 7.0), Color("406458"))
	for i in range(maxi(8, int(_route_height * 0.42))):
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var pos := Vector3(side * _rng.randf_range(3.7, 6.9), _rng.randf_range(1.0, _route_height - 3.0), 0.03)
		var moss := _rock(pos, Vector3(_rng.randf_range(0.35, 0.8), _rng.randf_range(0.18, 0.6), 0.06), Color("527d67"))
		moss.rotation.z = _rng.randf_range(-0.6, 0.6)
		if i % 4 == 0:
			_fern(pos + Vector3(0.0, 0.15, 0.10), 0.6)
	for i in range(12):
		var hanging := _box(Vector3(5.7 + sin(float(i)) * 0.5, _route_height * 0.45 - float(i) * 0.48, 0.08), Vector3(0.045, 0.55, 0.04), _grass_material)
		hanging.rotation.z = sin(float(i)) * 0.3

func _build_cloud_peak() -> void:
	for side in [-1.0, 1.0]:
		for i in range(12):
			var yy: float = float(i) * _route_height / 12.0
			var pos := Vector3(side * (5.6 + sin(float(i)) * 0.7), yy, -0.2)
			_rock(pos, Vector3(1.5, 0.32, 0.55), Color("e1e9e9"))
			_rock(pos - Vector3(0.0, 0.65, 0.0), Vector3(0.25, 0.85, 0.18), Color("b8d4df"))
			if i % 3 == 1:
				_make_wind_ribbon(pos + Vector3(0.0, 0.4, 0.0), 1.2)
	for i in range(8):
		var side: float = -1.0 if i % 2 == 0 else 1.0
		_mountain(Vector3(side * (15.0 + float(i) * 7.0), -12.0, -14.0 - float(i) * 8.0), Vector3(7.0, 35.0 + float(i) * 4.0, 8.0), Color("8294a6"), true)
	# Soft noise-edged cloud banks have no visible polygon outlines.
	for i in range(25):
		var center := Vector3(_rng.randf_range(-125.0, 125.0), _route_height * 0.72 + _rng.randf_range(-6.0, 6.0), _rng.randf_range(-140.0, -20.0))
		_cloud_puff(center, Vector2(_rng.randf_range(40.0, 62.0), _rng.randf_range(10.0, 17.0)))
	_rock(Vector3(0.0, -0.68, 1.0), Vector3(5.6, 0.10, 3.2), Color("d8e7e8"))
	for i in range(4):
		_make_wind_ribbon(Vector3(-5.5 + float(i) * 3.6, 0.1, 0.4), 1.3)

func _pine(pos: Vector3, height: float) -> void:
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = height * 0.009
	trunk_mesh.bottom_radius = height * 0.035
	trunk_mesh.height = height * 0.94
	trunk_mesh.radial_segments = 12
	trunk.mesh = trunk_mesh
	trunk.position = pos + Vector3(0.0, height * 0.47, 0.0)
	trunk.material_override = TerrainMaterials.rock(Color("685743"), "bark")
	add_child(trunk)
	# All branches and individual needle fans share one surface and material.
	var foliage := SurfaceTool.new()
	foliage.begin(Mesh.PRIMITIVE_TRIANGLES)
	for level in range(8):
		var fraction: float = float(level) / 8.0
		var origin := Vector3(0.0, height * (0.22 + fraction * 0.73), 0.0)
		for branch in range(7):
			var angle: float = float(branch) * TAU / 7.0 + float(level) * 1.73 + _rng.randf_range(-0.22, 0.22)
			var direction := Vector3(cos(angle), 0.0, sin(angle))
			var side := Vector3(-sin(angle), 0.0, cos(angle))
			var length: float = height * (0.29 * (1.0 - fraction) + 0.025) * _rng.randf_range(0.75, 1.14)
			var tip: Vector3 = origin + direction * length + Vector3.UP * height * 0.035
			var shade := Color("244837").lerp(Color("608467"), fraction * 0.65 + _rng.randf() * 0.20)
			_triangle(foliage, origin - side * height * 0.008, origin + side * height * 0.008, tip, shade.darkened(0.13))
			for spray in range(9):
				var t: float = (float(spray) + 1.0) / 10.0
				var base: Vector3 = origin.lerp(tip, t) - Vector3.UP * sin(t * PI) * height * 0.04
				for hand in [-1.0, 1.0]:
					var end: Vector3 = base + side * hand * length * (1.0 - t) * 0.42 + direction * length * 0.15 + Vector3.UP * height * 0.018
					var axis: Vector3 = (end - base).normalized()
					var cross_axis: Vector3 = Vector3(-axis.z, 0.1, axis.x).normalized()
					for needle in range(5):
						var center: Vector3 = base.lerp(end, float(needle) / 5.0)
						var needle_size: float = height * 0.028 * (1.0 - t * 0.40)
						for needle_side in [-1.0, 1.0]:
							var needle_tip: Vector3 = center + cross_axis * needle_side * needle_size + axis * needle_size * 0.65 + Vector3.UP * needle_size * 0.40
							_triangle(foliage, center - axis * needle_size * 0.14, center + axis * needle_size * 0.23, needle_tip, shade)
	var crown := MeshInstance3D.new()
	crown.mesh = foliage.commit()
	crown.position = pos
	var mat := _material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	crown.material_override = mat
	add_child(crown)

func _fern(pos: Vector3, size: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(8):
		var angle: float = float(i) * TAU / 8.0 + _rng.randf_range(-0.12, 0.12)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-sin(angle), 0.0, cos(angle))
		for j in range(10):
			var t: float = (float(j) + 1.0) / 11.0
			var center: Vector3 = direction * size * 0.72 * t + Vector3.UP * size * (sin(t * PI * 0.9) * 0.34 + t * 0.12)
			var next_t: float = t + 0.09
			var next: Vector3 = direction * size * 0.72 * next_t + Vector3.UP * size * (sin(next_t * PI * 0.9) * 0.34 + next_t * 0.12)
			_triangle(surface, center - side * size * 0.006, center + side * size * 0.006, next, Color.WHITE)
			for hand in [-1.0, 1.0]:
				var leaflet_length: float = size * sin(t * PI) * 0.17
				var tip: Vector3 = center + side * hand * leaflet_length + direction * size * 0.07 + Vector3.UP * size * 0.025
				var mid: Vector3 = center.lerp(tip, 0.45)
				_triangle(surface, center, mid - direction * size * 0.024, tip, Color.WHITE)
				_triangle(surface, center, tip, mid + direction * size * 0.024, Color.WHITE)
	var fern := MeshInstance3D.new()
	fern.mesh = surface.commit()
	fern.position = pos
	fern.material_override = _grass_material
	add_child(fern)

func _cairn(pos: Vector3, size: float) -> void:
	for i in range(5):
		var radius: float = size * (0.55 - float(i) * 0.082)
		_rock(pos + Vector3(sin(float(i)) * 0.03, float(i) * size * 0.21, 0.0), Vector3(radius, size * 0.12, radius * 0.83), _rock_highlight.lightened(0.1))

func _bench(pos: Vector3) -> void:
	var wood := _material(Color("78634b"))
	_box(pos + Vector3(0.0, 0.40, 0.0), Vector3(1.5, 0.10, 0.45), wood)
	for side in [-1.0, 1.0]:
		_box(pos + Vector3(side * 0.55, 0.20, 0.0), Vector3(0.10, 0.40, 0.38), wood)

func _signpost(pos: Vector3) -> void:
	var wood := _material(Color("806448"))
	_box(pos + Vector3(0.0, 0.65, 0.0), Vector3(0.09, 1.30, 0.09), wood)
	_box(pos + Vector3(0.0, 1.12, 0.0), Vector3(0.95, 0.27, 0.07), wood)
	var stripe := _material(Color("eed2a0"), 0.08)
	_box(pos + Vector3(-0.22, 1.12, 0.045), Vector3(0.3, 0.035, 0.02), stripe)
	var arrow := _box(pos + Vector3(-0.31, 1.16, 0.045), Vector3(0.035, 0.15, 0.02), stripe)
	arrow.rotation.z = -0.65

func _camp_props() -> void:
	var cloth := _material(Color("526e6a"))
	_box(Vector3(-1.7, -0.45, 2.0), Vector3(0.38, 0.52, 0.26), cloth)
	_box(Vector3(-1.7, -0.17, 2.0), Vector3(0.42, 0.08, 0.28), _pole_material)
	_box(Vector3(2.2, -0.22, 2.6), Vector3(0.15, 0.23, 0.15), _material(Color("c4d5ca")))
	var rope_mat := _material(Color("cb995a"))
	for i in range(3):
		var ring := MeshInstance3D.new()
		var mesh := TorusMesh.new()
		mesh.inner_radius = 0.20 + float(i) * 0.04
		mesh.outer_radius = 0.24 + float(i) * 0.04
		mesh.rings = 16
		mesh.ring_segments = 5
		ring.mesh = mesh
		ring.material_override = rope_mat
		ring.position = Vector3(-1.0, -0.65 + float(i) * 0.03, 2.3)
		add_child(ring)
	for i in range(8):
		var angle: float = float(i) * TAU / 8.0
		_rock(Vector3(0.8 + cos(angle) * 0.45, -0.65, 2.6 + sin(angle) * 0.45), Vector3(0.13, 0.12, 0.15), Color("7c7c70"))
	for i in range(3):
		var log_mesh := _box(Vector3(0.8, -0.61 + float(i) * 0.03, 2.6), Vector3(0.62, 0.09, 0.10), _material(Color("59483c")))
		log_mesh.rotation.y = float(i) * 1.2
	# A quiet lantern makes the camp feel occupied without affecting route readability.
	_box(Vector3(-2.05, -0.30, 2.7), Vector3(0.15, 0.24, 0.15), _material(Color("ffd78c"), 0.8))

func _waterfall(top: Vector3, width: float, fall: float) -> void:
	var vertices := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	var rows: int = maxi(12, int(fall * 2.0))
	var columns: int = 8
	for j in range(rows + 1):
		var t: float = float(j) / float(rows)
		var drift: float = sin(t * 6.0) * width * 0.06
		var spread: float = 0.85 + sin(t * PI) * 0.08 + t * 0.20
		for i in range(columns + 1):
			var u: float = float(i) / float(columns)
			vertices.append(Vector3((u - 0.5) * width * spread + drift, -t * fall, sin(u * PI) * 0.10 + sin(t * 8.0 + u * 4.0) * 0.035))
			uv.append(Vector2(u, t))
	for j in range(rows):
		for i in range(columns):
			var a: int = j * (columns + 1) + i
			var c: int = a + columns + 1
			indices.append_array(PackedInt32Array([a, a + 1, c, a + 1, c + 1, c]))
	var curtain := MeshInstance3D.new()
	curtain.mesh = _smooth_mesh(vertices, indices, uv)
	curtain.position = top
	curtain.material_override = TerrainMaterials.water()
	curtain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(curtain)
	for i in range(18):
		var strand := MeshInstance3D.new()
		var strand_mesh := QuadMesh.new()
		strand_mesh.size = Vector2(_rng.randf_range(0.045, 0.10), _rng.randf_range(0.7, 1.8))
		strand.mesh = strand_mesh
		strand.material_override = TerrainMaterials.water()
		strand.position = top + Vector3(_rng.randf_range(-width * 0.40, width * 0.40), -float(i) * fall / 18.0, 0.18)
		strand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		strand.set_meta("top", top.y - 1.0)
		strand.set_meta("fall", maxf(1.0, fall - 2.0))
		add_child(strand)
		_water_strands.append(strand)
	_cloud_puff(top - Vector3(0.0, fall - 0.35, -0.4), Vector2(width * 3.0, 1.6))

func _make_wind_ribbon(pos: Vector3, size: float) -> void:
	_box(pos + Vector3(0.0, size * 0.26, 0.0), Vector3(0.025, size * 0.52, 0.025), _pole_material)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_triangle(surface, Vector3.ZERO, Vector3(size * 0.68, -size * 0.02, 0.03), Vector3(size * 0.6, -size * 0.12, 0.03), Color.WHITE)
	_triangle(surface, Vector3.ZERO, Vector3(size * 0.6, -size * 0.12, 0.03), Vector3(0.0, -size * 0.09, 0.0), Color.WHITE)
	var ribbon := MeshInstance3D.new()
	ribbon.mesh = surface.commit()
	var mat := _material(Color("d7a574"))
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ribbon.material_override = mat
	ribbon.position = pos + Vector3(0.0, size * 0.5, 0.0)
	add_child(ribbon)
	_wind_ribbons.append(ribbon)

func _make_collectible(pos: Vector3, key: String) -> void:
	var book := _box(pos + Vector3(-0.42, -0.30, -0.12), Vector3(0.24, 0.30, 0.07), _material(Color("b18f59"), 0.2))
	book.rotation.z = -0.10
	_collectibles[key] = book
	var band := _box(book.position + Vector3(0.0, 0.0, 0.045), Vector3(0.05, 0.24, 0.02), _material(Color("f1dfad"), 0.25))
	band.rotation.z = -0.10
	book.set_meta("band", band)

func mark_collectible_collected(key: String) -> void:
	if not _collectibles.has(key):
		return
	var book: MeshInstance3D = _collectibles[key]
	book.visible = false
	var band: MeshInstance3D = book.get_meta("band")
	band.visible = false

func _build_birds() -> void:
	for i in range(3):
		var bird := Node3D.new()
		add_child(bird)
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_triangle(surface, Vector3(-0.9, 0.10, 0.0), Vector3(0.0, 0.0, 0.2), Vector3(0.0, 0.0, -0.15), Color.WHITE)
		_triangle(surface, Vector3(0.0, 0.0, -0.15), Vector3(0.0, 0.0, 0.2), Vector3(0.9, 0.10, 0.0), Color.WHITE)
		var wings := MeshInstance3D.new()
		wings.mesh = surface.commit()
		var mat := _material(Color("344852"))
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		wings.material_override = mat
		bird.add_child(wings)
		_birds.append(bird)

func _cloud_puff(pos: Vector3, size: Vector2) -> void:
	var puff := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = size
	puff.mesh = mesh
	puff.material_override = TerrainMaterials.cloud()
	puff.position = pos
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(puff)
	_clouds.append(puff)


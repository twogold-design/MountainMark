extends RefCounted
## Shared, seamless procedural surface assets; no runtime filesystem writes.
const STONE = preload("res://assets/shaders/stone.gdshader")
const SNOW = preload("res://assets/shaders/snow.gdshader")
const WATER = preload("res://assets/shaders/water.gdshader")
const CLOUD = preload("res://assets/shaders/cloud.gdshader")
static var _noise: NoiseTexture2D
static var _rock_cache: Dictionary = {}
static var _snow_cache: Dictionary = {}
static var _water: ShaderMaterial
static var _cloud: ShaderMaterial

static func noise_texture() -> NoiseTexture2D:
	if _noise == null:
		var noise := FastNoiseLite.new()
		noise.seed = 725831
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.026
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = 5
		noise.fractal_gain = 0.48
		_noise = NoiseTexture2D.new()
		_noise.width = 512
		_noise.height = 512
		_noise.seamless = true
		_noise.generate_mipmaps = true
		_noise.noise = noise
	return _noise

static func rock(base: Color, variant: String = "ridge") -> ShaderMaterial:
	var key: String = base.to_html() + variant
	if not _rock_cache.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = STONE
		mat.set_shader_parameter("stone_noise", noise_texture())
		mat.set_shader_parameter("base_color", base.srgb_to_linear())
		mat.set_shader_parameter("detail_strength", 0.15 if variant == "distant" else 1.0)
		mat.set_shader_parameter("dampness", 0.72 if variant == "canyon" else 0.0)
		mat.set_shader_parameter("frost", 0.4 if variant == "summit" else 0.0)
		_rock_cache[key] = mat
	return _rock_cache[key]

static func snow(base: Color = Color("d8e7e8")) -> ShaderMaterial:
	var key: String = base.to_html()
	if not _snow_cache.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = SNOW
		mat.set_shader_parameter("stone_noise", noise_texture())
		mat.set_shader_parameter("base_color", base.srgb_to_linear())
		_snow_cache[key] = mat
	return _snow_cache[key]

static func water() -> ShaderMaterial:
	if _water == null:
		_water = ShaderMaterial.new()
		_water.shader = WATER
		_water.set_shader_parameter("stone_noise", noise_texture())
	return _water

static func cloud() -> ShaderMaterial:
	if _cloud == null:
		_cloud = ShaderMaterial.new()
		_cloud.shader = CLOUD
		_cloud.set_shader_parameter("stone_noise", noise_texture())
	return _cloud
static func ground(base: Color) -> ShaderMaterial:
	var key: String = base.to_html() + "ground"
	if not _rock_cache.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://assets/shaders/ground.gdshader")
		mat.set_shader_parameter("stone_noise", noise_texture())
		mat.set_shader_parameter("base_color", base.srgb_to_linear())
		_rock_cache[key] = mat
	return _rock_cache[key]

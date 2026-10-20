shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D stone_noise : repeat_enable, filter_linear_mipmap;
uniform vec4 base_color : source_color = vec4(0.55, 0.5, 0.43, 1.0);
uniform float detail_strength = 1.0;
uniform float dampness = 0.0;
uniform float frost = 0.0;
varying vec3 stone_position;
varying vec3 stone_normal;

void vertex() {
	stone_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	stone_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
float stone_sample(vec3 p, vec3 weights, float scale) {
	return texture(stone_noise, p.yz * scale).r * weights.x
		+ texture(stone_noise, p.xz * scale + vec2(0.31, 0.17)).r * weights.y
		+ texture(stone_noise, p.xy * scale + vec2(0.13, 0.47)).r * weights.z;
}
void fragment() {
	vec3 n = normalize(stone_normal);
	vec3 weights = pow(abs(n), vec3(4.0));
	weights /= max(dot(weights, vec3(1.0)), 0.001);
	float broad = stone_sample(stone_position, weights, 0.025);
	float middle = stone_sample(stone_position, weights, 0.28);
	float grain = stone_sample(stone_position, weights, 2.8);
	float strata = sin(stone_position.y * 3.8 + broad * 12.0 + stone_position.x * 0.18);
	float vein = 1.0 - smoothstep(0.018, 0.055, abs(middle - 0.49));
	float tone = 0.91 + broad * 0.18 + (middle - 0.5) * 0.14 * detail_strength;
	tone += (grain - 0.5) * 0.055 * detail_strength + strata * 0.016 * detail_strength;
	tone -= vein * 0.018 * detail_strength;
	vec3 stone = base_color.rgb * COLOR.rgb * tone;
	float weathering = smoothstep(0.48, 0.76, broad) * smoothstep(-0.1, 0.7, n.y);
	stone = mix(stone, stone * vec3(0.80, 0.91, 0.78), weathering * dampness * 0.45);
	stone = mix(stone, vec3(0.69, 0.77, 0.80), frost * weathering * 0.35);
	ALBEDO = stone;
	ROUGHNESS = clamp(0.93 - dampness * 0.28 + (grain - 0.5) * 0.08, 0.52, 1.0);
	SPECULAR = 0.26 + dampness * 0.12;
	// Derivative surface gradient adds fine relief without exposing mesh triangles.
	float relief = (grain * 0.0015 + middle * 0.004) * detail_strength;
	vec3 dx = dFdx(stone_position);
	vec3 dy = dFdy(stone_position);
	vec3 r1 = cross(dy, n);
	vec3 r2 = cross(n, dx);
	float det = dot(dx, r1);
	vec3 gradient = sign(det) * (dFdx(relief) * r1 + dFdy(relief) * r2) / max(abs(det), 0.0001);
	vec3 bumped = normalize(n - gradient);
	NORMAL = normalize((VIEW_MATRIX * vec4(bumped, 0.0)).xyz);
}

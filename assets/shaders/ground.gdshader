shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D stone_noise : repeat_enable, filter_linear_mipmap;
uniform vec4 base_color : source_color;
varying vec3 ground_position;
void vertex() {
	ground_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float moss = texture(stone_noise, ground_position.xz * 0.12).r;
	float earth = texture(stone_noise, ground_position.xz * 0.8).r;
	ALBEDO = base_color.rgb * (0.85 + moss * 0.25 + (earth - 0.5) * 0.09);
	ROUGHNESS = 0.98;
	SPECULAR = 0.15;
}

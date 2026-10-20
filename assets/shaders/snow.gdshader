shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D stone_noise : repeat_enable, filter_linear_mipmap;
uniform vec4 base_color : source_color = vec4(0.85, 0.91, 0.92, 1.0);
varying vec3 snow_position;
void vertex() {
	snow_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float drift = texture(stone_noise, snow_position.xz * 0.12).r;
	float grain = texture(stone_noise, snow_position.xz * 4.0).r;
	float ripple = sin(snow_position.x * 3.0 + drift * 7.0 + snow_position.z * 1.2);
	ALBEDO = base_color.rgb * (0.93 + drift * 0.08 + ripple * 0.009 + (grain - 0.5) * 0.028);
	ROUGHNESS = 0.84 + grain * 0.1;
	SPECULAR = 0.27;
}

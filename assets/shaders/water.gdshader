shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform sampler2D stone_noise : repeat_enable, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.20, 0.38, 0.40, 0.58);
void fragment() {
	vec2 flow = vec2(UV.x * 1.7, UV.y * 0.8 + TIME * 0.20);
	float water = texture(stone_noise, flow).r;
	float streak = texture(stone_noise, vec2(UV.x * 4.2, UV.y * 0.18 + TIME * 0.13)).r;
	float edge = smoothstep(0.0, 0.13, UV.x) * smoothstep(0.0, 0.13, 1.0 - UV.x);
	float foam = smoothstep(0.52, 0.74, streak) * 0.42;
	ALBEDO = mix(tint.rgb, vec3(0.62, 0.74, 0.73), foam) * (0.90 + water * 0.18);
	ROUGHNESS = 0.30;
	SPECULAR = 0.65;
	ALPHA = edge * (tint.a + (water - 0.5) * 0.20);
}

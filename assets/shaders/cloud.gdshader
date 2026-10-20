shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
uniform sampler2D stone_noise : repeat_enable, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.82, 0.88, 0.89, 0.24);
void vertex() {
	// Preserve scale while facing the camera, eliminating polygon-disc silhouettes.
	mat4 face = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	face[0].xyz *= length(MODEL_MATRIX[0].xyz);
	face[1].xyz *= length(MODEL_MATRIX[1].xyz);
	face[2].xyz *= length(MODEL_MATRIX[2].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * face;
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float noise = texture(stone_noise, UV * 0.65 + vec2(TIME * 0.002, 0.17)).r;
	float edge = 1.0 - smoothstep(0.18, 1.0, dot(p, p) + (noise - 0.5) * 0.42);
	ALBEDO = tint.rgb;
	ALPHA = edge * (0.52 + noise * 0.48) * tint.a;
}

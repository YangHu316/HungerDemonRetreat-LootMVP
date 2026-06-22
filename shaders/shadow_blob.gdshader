shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// §5.5 ShadowBlob: 中心黑 α=0.5 渐隐到边缘 α=0
void fragment() {
	vec2 uv = UV - vec2(0.5);
	float d = length(uv) * 2.0; // 0 中心 → 1 边缘
	float a = clamp(1.0 - d, 0.0, 1.0);
	a = a * a; // smooth falloff
	ALBEDO = vec3(0.0, 0.0, 0.0);
	ALPHA = 0.5 * a;
}

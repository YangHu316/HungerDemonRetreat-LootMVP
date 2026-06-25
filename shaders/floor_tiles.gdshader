shader_type spatial;
render_mode cull_back;

// .tres 用的参数名(2026-06 修对齐 — 之前 shader 用 tile_color_*/roughness_value
// 与 .tres 里的 color_*/roughness_val 不匹配 → 全程吃默认深色 → 地板看着发黑)
uniform vec3 color_a : source_color = vec3(0.23, 0.24, 0.27);
uniform vec3 color_b : source_color = vec3(0.18, 0.19, 0.22);
uniform vec3 grout_color : source_color = vec3(0.08, 0.08, 0.10);
uniform vec2 tile_size = vec2(1.0, 1.0);
uniform float grout_width = 0.04;
uniform float roughness_val = 0.7;
uniform float metallic_val = 0.0;
uniform vec2 uv_scale = vec2(1.0, 1.0);

void fragment() {
	vec2 scaled_uv = UV * uv_scale;
	vec2 cell_uv = fract(scaled_uv / tile_size);
	vec2 cell_id = floor(scaled_uv / tile_size);

	vec2 fw = fwidth(cell_uv) * 1.5;

	float grout_x = smoothstep(grout_width - fw.x, grout_width + fw.x, cell_uv.x) *
					smoothstep(grout_width - fw.x, grout_width + fw.x, 1.0 - cell_uv.x);
	float grout_y = smoothstep(grout_width - fw.y, grout_width + fw.y, cell_uv.y) *
					smoothstep(grout_width - fw.y, grout_width + fw.y, 1.0 - cell_uv.y);

	float in_tile = grout_x * grout_y;
	float in_grout = 1.0 - in_tile;

	float checker = mod(cell_id.x + cell_id.y, 2.0);
	vec3 tile = mix(color_a, color_b, checker);

	ALBEDO = mix(tile, grout_color, in_grout);
	ROUGHNESS = roughness_val;
	METALLIC = metallic_val;
}

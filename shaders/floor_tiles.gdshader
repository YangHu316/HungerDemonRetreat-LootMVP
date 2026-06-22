shader_type spatial;
render_mode cull_back;

uniform vec3 tile_color_a : source_color = vec3(0.16, 0.18, 0.21);
uniform vec3 tile_color_b : source_color = vec3(0.20, 0.22, 0.25);
uniform vec3 grout_color  : source_color = vec3(0.08, 0.08, 0.10);
uniform float tile_size = 1.0;
uniform float grout_width = 0.04;
uniform float roughness_value = 0.85;

void fragment() {
    vec2 cell_uv = fract(UV / tile_size);
    vec2 cell_id = floor(UV / tile_size);

    vec2 fw = fwidth(cell_uv) * 1.5;

    float grout_x = smoothstep(grout_width - fw.x, grout_width + fw.x, cell_uv.x) *
                    smoothstep(grout_width - fw.x, grout_width + fw.x, 1.0 - cell_uv.x);
    float grout_y = smoothstep(grout_width - fw.y, grout_width + fw.y, cell_uv.y) *
                    smoothstep(grout_width - fw.y, grout_width + fw.y, 1.0 - cell_uv.y);

    float in_tile = grout_x * grout_y;
    float in_grout = 1.0 - in_tile;

    float checker = mod(cell_id.x + cell_id.y, 2.0);
    vec3 tile = mix(tile_color_a, tile_color_b, checker);

    ALBEDO = mix(tile, grout_color, in_grout);
    ROUGHNESS = roughness_value;
}

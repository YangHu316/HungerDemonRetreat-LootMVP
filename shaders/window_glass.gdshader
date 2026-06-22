shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;
uniform vec4 tint : source_color = vec4(0.55, 0.75, 0.95, 0.35);
uniform float fresnel_strength : hint_range(0.0, 2.0) = 0.6;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.05;
void fragment() {
    float fresnel = pow(1.0 - dot(NORMAL, VIEW), 2.0) * fresnel_strength;
    ALBEDO = tint.rgb;
    ALPHA = clamp(tint.a + fresnel, 0.1, 0.85);
    METALLIC = 0.6;
    ROUGHNESS = roughness_value;
    EMISSION = vec3(0.05, 0.07, 0.10);
}

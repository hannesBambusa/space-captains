// Soft fill for flat annulus/disc meshes on the play plane (UV.x = 0 inner
// edge .. 1 outer edge). Used for the build zone while placing.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 zone_color : source_color = vec4(1.0, 0.6, 0.25, 1.0);
uniform float fill = 0.012;
uniform float edge = 0.05;
uniform float inner_edge = 0.0;

void fragment() {
	float u = UV.x;
	float outer_glow = smoothstep(0.97, 1.0, u);
	float inner_glow = (1.0 - smoothstep(0.0, 0.03, u)) * inner_edge;
	ALBEDO = zone_color.rgb * (fill + (outer_glow + inner_glow) * edge);
}

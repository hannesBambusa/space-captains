// Screen-space progress bar on a 1x1 QuadMesh: stays a fixed pixel size and
// faces the camera at any zoom, drawn over everything. offset_px lifts it
// above the node's origin.
shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec2 size_px = vec2(64.0, 7.0);
uniform vec2 offset_px = vec2(0.0, 30.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 fill_color : source_color = vec4(1.0, 0.58, 0.22, 1.0);
uniform vec4 back_color : source_color = vec4(0.03, 0.05, 0.08, 0.85);
uniform vec4 border_color : source_color = vec4(0.75, 0.82, 0.9, 0.7);

void vertex() {
	vec4 c = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0));
	vec2 px = VERTEX.xy * size_px + offset_px;
	// The projection may flip clip-space Y; keep +Y = up on screen.
	px.y *= sign(PROJECTION_MATRIX[1][1]);
	c.xy += px / VIEWPORT_SIZE * 2.0 * c.w;
	POSITION = c;
}

void fragment() {
	vec2 p = UV * size_px;
	float border = 1.0 - step(1.0, p.x) * step(1.0, p.y) * step(p.x, size_px.x - 1.0) * step(p.y, size_px.y - 1.0);
	float inner_u = clamp((p.x - 2.0) / max(size_px.x - 4.0, 1.0), 0.0, 1.0);
	float inside = step(2.0, p.y) * step(p.y, size_px.y - 2.0) * step(2.0, p.x) * step(p.x, size_px.x - 2.0);
	vec4 col = back_color;
	if (inside > 0.5 && inner_u <= progress) {
		col = fill_color;
	}
	if (border > 0.5) {
		col = border_color;
	}
	ALBEDO = col.rgb;
	ALPHA = col.a;
}

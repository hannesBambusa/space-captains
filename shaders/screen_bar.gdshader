// Screen-space progress bar on a 1x1 QuadMesh: stays a fixed pixel size and
// faces the camera at any zoom, drawn over everything. offset_px lifts it
// above the node's origin. The bar is snapped to whole pixels, so its 1 px
// border does not shimmer while the structure drifts with the station.
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
	// The projection may flip clip-space Y; keep +Y = up on screen.
	float flip = sign(PROJECTION_MATRIX[1][1]);
	vec2 center_px = (c.xy / c.w * 0.5 + 0.5) * VIEWPORT_SIZE;
	vec2 corner_px = floor(center_px + vec2(offset_px.x, offset_px.y * flip) - size_px * 0.5 + 0.5);
	vec2 px = corner_px + (VERTEX.xy * vec2(1.0, flip) + 0.5) * size_px;
	c.xy = (px / VIEWPORT_SIZE * 2.0 - 1.0) * c.w;
	POSITION = c;
}

void fragment() {
	vec2 p = floor(UV * size_px);
	vec2 inner = size_px - 1.0;
	bool border = p.x < 1.0 || p.y < 1.0 || p.x >= inner.x || p.y >= inner.y;
	bool inside = p.x >= 2.0 && p.y >= 2.0 && p.x < size_px.x - 2.0 && p.y < size_px.y - 2.0;
	float fill_px = floor((size_px.x - 4.0) * progress + 0.5);
	vec4 col = back_color;
	if (inside && p.x - 2.0 < fill_px) {
		float edge = step(fill_px - 1.0, p.x - 2.0);
		col = vec4(mix(fill_color.rgb, vec3(1.0, 0.95, 0.85), edge * 0.7), fill_color.a);
	}
	if (border) {
		col = border_color;
	}
	ALBEDO = col.rgb;
	ALPHA = col.a;
}

// Short welding beam on a 1x1 QuadMesh: the node's local Y (scaled to the
// beam length) runs from the weld tip (y = -0.5) to the work point (y = +0.5).
// The vertex stage turns the quad to face the camera and keeps it at least
// min_px wide; a beam forced wider than its real width dims to match, so it
// never shimmers as a sub-pixel line at RTS zoom.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 beam_color : source_color = vec4(1.0, 0.75, 0.45, 1.0);
uniform float width = 0.12;
uniform float min_px = 1.5;
uniform float energy = 3.0;
// 0..1, flicker and on/off, driven from the script.
instance uniform float strength = 1.0;

varying float v_side;
varying float v_along;
varying float v_dim;

void vertex() {
	vec3 a = (MODEL_MATRIX * vec4(0.0, -0.5, 0.0, 1.0)).xyz;
	vec3 b = (MODEL_MATRIX * vec4(0.0, 0.5, 0.0, 1.0)).xyz;
	vec3 p = mix(a, b, VERTEX.y + 0.5);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = cam - p;
	float dist = max(length(to_cam), 0.01);
	float world_per_px = 2.0 * dist / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float w = max(width, min_px * world_per_px);
	vec3 dir = b - a;
	vec3 side = cross(dir, to_cam);
	side = length(side) > 1e-5 ? normalize(side) : vec3(1.0, 0.0, 0.0);
	p += side * VERTEX.x * w;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p, 1.0);
	v_side = VERTEX.x * 2.0;
	v_along = VERTEX.y + 0.5;
	v_dim = width / w;
}

void fragment() {
	float core = exp(-v_side * v_side * 5.0);
	// Soft ends.
	float ends = smoothstep(0.0, 0.08, v_along) * smoothstep(1.0, 0.9, v_along);
	vec3 hot = mix(beam_color.rgb, vec3(1.0, 0.97, 0.9), core * core);
	ALBEDO = hot * core * ends * energy * v_dim * strength;
}

// Warp hop light trail (WarpTrail): a 1x1 QuadMesh rebuilt in the vertex
// stage as a thin ribbon from the node's origin (the head) back along
// trail_axis for trail_len metres, turned round its axis to face the camera.
// The width is held between min_px and max_px on screen so the line stays
// thin and readable at every zoom; a width forced wider than its world size
// dims to match. Additive, HDR core so the glow picks it up. All per-ship
// values are instance uniforms: one shared material for every trail.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

instance uniform vec3 trail_axis = vec3(0.0, 0.0, 1.0);
instance uniform float trail_len = 400.0;
instance uniform float trail_alpha = 1.0;
instance uniform vec4 trail_tint : source_color = vec4(0.373, 0.816, 0.886, 1.0);
instance uniform float trail_width = 2.0;

// Core width on screen, pixels (the halo is halo x wider).
uniform float min_px = 1.2;
uniform float max_px = 2.6;
uniform float halo = 3.5;
// Head cap ahead of the origin, in core widths.
uniform float cap = 3.0;
uniform float energy = 3.2;

varying float v_t;
varying float v_x;
varying float v_dim;
varying float v_cap;

void vertex() {
	vec3 head = MODEL_MATRIX[3].xyz;
	vec3 axis = normalize(trail_axis);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float t = 0.5 - VERTEX.y;
	float dist = max(length(cam - head), 0.01);
	// Metres per pixel at this distance (abs: the projection can flip Y).
	float wpp = 2.0 * dist / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
	float w = clamp(trail_width, min_px * wpp, max_px * wpp);
	float cap_len = w * cap;
	float along = mix(-cap_len, trail_len, t);
	vec3 p = head + axis * along;
	vec3 side = cross(axis, cam - p);
	float sl = length(side);
	side = sl > 1e-4 ? side / sl : INV_VIEW_MATRIX[0].xyz;
	p += side * VERTEX.x * 2.0 * w * halo;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p, 1.0);
	v_t = along / max(trail_len, 0.01);
	v_x = VERTEX.x * 2.0;
	v_cap = along / max(cap_len, 0.01);
	v_dim = max(trail_width / w, 0.45);
}

void fragment() {
	float t = clamp(v_t, 0.0, 1.0);
	// Narrows toward the tail.
	float taper = mix(1.0, 0.35, t);
	float x = v_x * halo / taper;
	float core = exp(-x * x * 2.2);
	float glow = exp(-v_x * v_x * 4.0 / taper) * 0.07;
	// Bright near the head, a long soft taper to nothing at the tail.
	float body = pow(1.0 - t, 1.8);
	float hot = exp(-t * 28.0);
	// Rounded head: fades out over the cap ahead of the origin.
	float front = v_cap < 0.0 ? smoothstep(-1.0, 0.0, v_cap) : 1.0;
	vec3 white = mix(trail_tint.rgb, vec3(1.0), 0.82);
	vec3 c = white * core * (body * 0.9 + hot * 1.6) + trail_tint.rgb * glow * (body + hot);
	ALBEDO = clamp(c * energy * trail_alpha * front * v_dim, vec3(0.0), vec3(7.0));
}

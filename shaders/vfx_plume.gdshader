// Engine plume (EnginePlume) on a 1x1 QuadMesh: a thin hot exhaust cone
// that runs from the nozzle (node origin) along the node's +Z, turned about
// that axis to face the camera. Length and brightness come from thrust
// (instance uniforms). Width and length never drop under a few pixels, so a
// burning drive still reads as a short bright tick at system zoom; forced
// bigger it dims to match. Additive, soft, no depth write.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

instance uniform vec4 pl_tint : source_color = vec4(0.55, 0.75, 1.0, 1.0);
instance uniform float pl_len = 10.0;
instance uniform float pl_width = 1.5;
instance uniform float pl_alpha = 1.0;

uniform float min_width_px = 1.6;
uniform float min_len_px = 5.0;
uniform float energy = 2.2;

varying vec2 v_uv;
varying float v_dim;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 axis = normalize(MODEL_MATRIX[2].xyz);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float dist = max(length(cam - origin), 0.01);
	float wpp = 2.0 * dist / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
	vec3 v = (cam - origin) / dist;
	vec3 side = cross(axis, v);
	float sl = length(side);
	side = sl > 1e-3 ? side / sl : INV_VIEW_MATRIX[0].xyz;
	float w = max(pl_width, min_width_px * wpp);
	float len = max(pl_len, min_len_px * wpp);
	float t = VERTEX.y + 0.5;
	vec3 p = origin + axis * (t * len) + side * VERTEX.x * w;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p, 1.0);
	v_uv = vec2(VERTEX.x * 2.0, t);
	v_dim = clamp((pl_width / w) * (pl_len / len), 0.18, 1.0);
}

void fragment() {
	float t = v_uv.y;
	// The cone narrows toward the tail; the core is hotter near the nozzle.
	float half_w = mix(0.75, 0.22, t);
	float r = abs(v_uv.x) / half_w;
	float body = exp(-r * r * 3.0) * (1.0 - smoothstep(0.85, 1.0, r));
	float along = pow(1.0 - t, 1.6) * smoothstep(0.0, 0.05, t + 0.02);
	float core = exp(-r * r * 14.0) * pow(1.0 - t, 4.0);
	vec3 c = pl_tint.rgb * body * along + vec3(1.0, 0.97, 0.92) * core * 1.4;
	ALBEDO = c * energy * pl_alpha * v_dim;
}

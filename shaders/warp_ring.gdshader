// Thin warp ring (WarpFx shock ring, WarpVisuals drive charge ring) on a 1x1
// QuadMesh, laid in the plane across ring_normal (camera-facing when the
// normal is zero). The radius never drops under min_px on screen (scaled by
// ring_grow, so an expanding ring still grows at far zoom); the line stays
// at least ~1.5 px wide. Additive, soft against geometry. Instance uniforms.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

instance uniform vec4 ring_tint : source_color = vec4(0.62, 0.85, 1.0, 1.0);
instance uniform vec3 ring_normal = vec3(0.0);
instance uniform float ring_radius = 30.0;
instance uniform float ring_alpha = 1.0;
instance uniform float ring_grow = 1.0;
// Line width as a fraction of the radius.
instance uniform float ring_width = 0.05;

uniform float min_px = 24.0;
// The floor shrinks to far_min x min_px between these camera distances (system zoom).
uniform vec2 far_band = vec2(4000.0, 30000.0);
uniform float far_min = 0.45;
// How far a ring with a normal turns toward the camera (never seen edge-on).
uniform float face_cam = 0.9;
uniform float energy = 1.3;
uniform float fade_dist = 5.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec2 v_uv;
varying float v_dim;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float dist = max(length(cam - center), 0.01);
	// Metres per pixel at this distance (abs: the projection can flip Y).
	float wpp = 2.0 * dist / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
	float floor_px = min_px * mix(1.0, far_min, smoothstep(far_band.x, far_band.y, dist));
	float s = ring_radius;
	float s2 = max(s, floor_px * wpp * ring_grow);
	vec3 u = INV_VIEW_MATRIX[0].xyz;
	vec3 w = INV_VIEW_MATRIX[1].xyz;
	if (dot(ring_normal, ring_normal) > 1e-6) {
		vec3 v = normalize(cam - center);
		vec3 n = normalize(ring_normal);
		// The ring is the same either way round: tip it toward the camera.
		n *= dot(n, v) < 0.0 ? -1.0 : 1.0;
		n = normalize(n + v * face_cam);
		vec3 a = abs(n.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
		u = normalize(cross(n, a));
		w = cross(n, u);
	}
	vec3 p = center + (u * VERTEX.x + w * VERTEX.y) * 2.0 * s2;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p, 1.0);
	v_uv = VERTEX.xy * 2.0;
	v_dim = mix(min(s / s2, 1.0), 1.0, 0.5);
}

// 0..1: fades where the ring meets geometry; empty sky counts as far away.
float soft_depth(vec2 uv, float frag_z, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	if (d <= 1e-7) {
		return 1.0;
	}
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	float soft = clamp((-v.z / v.w + frag_z) / fade_dist, 0.0, 1.0);
	return soft >= 0.0 ? soft : 1.0;
}

void fragment() {
	float d = length(v_uv);
	float hw = max(ring_width, fwidth(d) * 1.5);
	float r = 1.0 - hw * 1.5;
	float x = (d - r) / hw;
	float line = exp(-x * x * 1.6);
	// A faint fill inside the ring, brighter toward its edge.
	float fill = smoothstep(0.6, r, d) * step(d, r) * 0.025;
	vec3 c = mix(ring_tint.rgb, vec3(1.0), 0.45) * line + ring_tint.rgb * fill;
	ALBEDO = clamp(c * energy * ring_alpha * v_dim * soft_depth(SCREEN_UV, VERTEX.z, INV_PROJECTION_MATRIX), vec3(0.0), vec3(7.0));
}

// Warp flash (WarpFx): a camera-facing glow on a 1x1 QuadMesh with a
// white-hot centre, a soft tinted halo and a faint horizontal (screen)
// streak. The radius is held between min_px and max_px on screen; a flash
// forced bigger than its world size dims to match. Drawn pulled toward the
// camera so the hull it sits on does not cut it. Per-flash values are
// instance uniforms.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

instance uniform vec4 fx_tint : source_color = vec4(0.62, 0.85, 1.0, 1.0);
instance uniform float fx_radius = 20.0;
instance uniform float fx_alpha = 1.0;

uniform float min_px = 34.0;
// The floor shrinks to far_min x min_px between these camera distances (system zoom).
uniform vec2 far_band = vec2(4000.0, 30000.0);
uniform float far_min = 0.45;
uniform float max_px = 220.0;
uniform float energy = 4.0;
uniform float max_out = 8.0;
uniform float streak = 0.6;

varying vec2 v_uv;
varying float v_dim;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float dist = max(length(cam - center), 0.01);
	// Metres per pixel at this distance (abs: the projection can flip Y).
	float wpp = 2.0 * dist / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
	float floor_px = min_px * mix(1.0, far_min, smoothstep(far_band.x, far_band.y, dist));
	float s = fx_radius;
	float s2 = clamp(s, floor_px * wpp, max(max_px * wpp, floor_px * wpp));
	// The quad is 3x wide for the streak.
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 p = center + (right * VERTEX.x * 3.0 + up * VERTEX.y) * 2.0 * s2;
	// Pull toward the camera a little so the hull does not cut it in half.
	p += normalize(cam - center) * min(s2 * 0.5, dist * 0.5);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p, 1.0);
	v_uv = vec2(VERTEX.x * 3.0, VERTEX.y) * 2.0;
	v_dim = mix(min(s / s2, 1.0), 1.0, 0.35);
}

void fragment() {
	float r2 = dot(v_uv, v_uv);
	float halo = exp(-r2 * 9.0);
	float hot = exp(-r2 * 60.0);
	float line = exp(-v_uv.y * v_uv.y * 1600.0) * exp(-abs(v_uv.x) * 2.2) * streak;
	float edge = 1.0 - smoothstep(0.75, 1.0, abs(v_uv.y));
	vec3 soft_white = mix(fx_tint.rgb, vec3(1.0), 0.5);
	vec3 c = soft_white * halo * 0.45 + vec3(1.0) * hot * 1.6 + soft_white * line;
	ALBEDO = clamp(c * edge * energy * fx_alpha * v_dim, vec3(0.0), vec3(max_out));
}

// Pooled flash quads (FlashPool: muzzle flashes, hit glints, explosion
// cores) drawn by one MultiMesh. Instance transform: origin = flash point,
// basis scale = radius. INSTANCE_CUSTOM.xyz = world direction times the
// stretch length (a muzzle flash runs forward along it), .w = white-core
// share. COLOR = HDR tint, alpha = fade. Camera-facing; never smaller than
// min_px on screen, dimmed to its real size when forced bigger (down to
// dim_floor so far fights still twinkle). Additive, no depth write.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float min_px = 2.0;
uniform float dim_floor = 0.12;

varying vec4 v_color;
varying vec2 v_pos;
varying float v_len;
varying float v_rad;
varying float v_dim;
varying float v_core;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float dist = max(length(cam - center), 0.01);
	float wpp = 2.0 * dist / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
	float s2 = max(s, min_px * wpp);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	float L = length(INSTANCE_CUSTOM.xyz);
	float ls = 0.0;
	if (L > 1e-4) {
		vec3 v = (cam - center) / dist;
		vec3 a = INSTANCE_CUSTOM.xyz / L;
		vec3 ap = a - v * dot(a, v);
		float apl = length(ap);
		if (apl > 1e-3) {
			up = ap / apl;
			right = normalize(cross(up, v));
			ls = max(L * apl, 0.0) * (s2 / s);
		}
	}
	float along = mix(-s2, ls + s2, VERTEX.y + 0.5);
	float across = VERTEX.x * 2.0 * s2;
	vec3 p = center + right * across + up * along;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p, 1.0);
	v_pos = vec2(across, along);
	v_len = ls;
	v_rad = s2;
	v_dim = max((s / s2) * (s / s2), dim_floor);
	v_core = INSTANCE_CUSTOM.w;
	v_color = COLOR;
}

void fragment() {
	// A teardrop: round at the origin, tapering along the stretch.
	float t = v_len > 0.0 ? clamp(v_pos.y / v_len, 0.0, 1.0) : 0.0;
	float w = v_rad * mix(1.0, 0.28, t);
	float dy = v_pos.y < 0.0 ? v_pos.y : max(v_pos.y - v_len, 0.0);
	vec2 r = vec2(v_pos.x / w, dy / v_rad);
	float r2 = dot(r, r);
	float a = exp(-r2 * 4.0) * (1.0 - smoothstep(0.6, 1.0, r2)) * mix(1.0, 0.55, t);
	vec3 c = v_color.rgb;
	c = mix(c, vec3(max(max(c.r, c.g), c.b)), exp(-r2 * 14.0) * v_core);
	ALBEDO = c * a * v_color.a * v_dim;
}

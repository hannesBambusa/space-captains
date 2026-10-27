// Ship shield bubble ripple (ShieldRipple) on a sphere: a bright spot where
// the round struck, a ring running out from it over the bubble and a faint
// rim, all fading over the ripple's life. Only drawn for a moment after a
// hit; invisible otherwise. Instance uniforms (one material, pooled meshes).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

instance uniform vec4 sh_tint : source_color = vec4(0.45, 0.8, 1.0, 1.0);
// Hit direction from the bubble centre (unit, world axes).
instance uniform vec3 sh_hit = vec3(0.0, 0.0, 1.0);
// 0 at the hit, 1 at the end of the ripple.
instance uniform float sh_k = 0.0;
instance uniform float sh_alpha = 1.0;

uniform float energy = 1.2;

varying vec3 v_dir;

void vertex() {
	v_dir = normalize(VERTEX);
}

void fragment() {
	float c = clamp(dot(v_dir, normalize(sh_hit)), -1.0, 1.0);
	float ang = acos(c);
	float k = sh_k;
	float front = mix(0.05, 1.9, sqrt(k));
	float ring = exp(-pow((ang - front) / mix(0.08, 0.3, k), 2.0));
	float spot = exp(-ang * ang * 22.0) * pow(1.0 - k, 3.0);
	// Hex-ish cell shimmer along the ring.
	float cells = 0.75 + 0.25 * sin(v_dir.x * 41.0) * sin(v_dir.y * 37.0) * sin(v_dir.z * 43.0);
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 3.0) * 0.2;
	float fade = pow(1.0 - k, 1.6);
	float a = (ring * cells * 0.9 + spot * 2.2 + rim * (1.0 - smoothstep(0.0, 2.5, abs(ang - front)))) * fade * sh_alpha;
	vec3 col = mix(sh_tint.rgb, vec3(1.0), spot * 0.6);
	ALBEDO = col * a * energy;
}

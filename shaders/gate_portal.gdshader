// Jump gate portal: swirling energy disc in the local XY plane (a QuadMesh,
// facing +Z = the ring axis). Additive, both faces. UV radius 1 = disc edge.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 portal_color : source_color = vec3(0.35, 0.75, 1.0);
uniform vec3 core_color : source_color = vec3(0.75, 0.55, 1.0);
uniform float intensity = 2.2;
uniform float swirl_speed = 0.35;
uniform float pulse = 1.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += vnoise(p) * a;
		p = p * 2.03 + vec2(4.1, 1.3);
		a *= 0.5;
	}
	return s / 0.96875;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float a = atan(p.y, p.x);
	float t = TIME * swirl_speed;
	// Log-spiral coordinates make the noise swirl into the centre.
	float spiral = a / 6.2831853 * 3.0 + log(max(r, 0.02)) * 1.2 - t;
	float n1 = fbm(vec2(cos(spiral * 6.2831853), sin(spiral * 6.2831853)) * 1.6 + vec2(r * 3.0 - t * 2.0, t));
	float n2 = fbm(vec2(spiral * 4.0, r * 5.0 - t * 3.0));
	float arms = pow(0.5 + 0.5 * sin(spiral * 6.2831853 * 2.0 + n2 * 4.0), 3.0);
	float edge = smoothstep(0.7, 0.97, r) * smoothstep(1.0, 0.96, r);
	float body = (0.25 + 0.75 * n1) * (0.35 + 0.65 * arms) * smoothstep(1.0, 0.85, r);
	float core = exp(-r * r * 9.0);
	vec3 col = portal_color * body + core_color * core * 0.9 + portal_color * edge * 1.6;
	ALBEDO = col * intensity * pulse;
}

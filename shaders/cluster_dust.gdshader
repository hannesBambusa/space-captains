// Far view of an asteroid cluster: a flat disc of lit dust in the local XZ
// plane, centred on the cluster. Gaussian radial profile broken up by
// clumps, forward scattering toward the star, optional self-glow (crystal
// clusters). Fades out near the camera, where the real asteroids take over.
// [amount] thins it as the cluster is mined (1 = full, 0 = gone).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 star_position = vec3(0.0);
uniform vec3 star_color : source_color = vec3(1.0);
uniform vec3 dust_color : source_color = vec3(0.62, 0.55, 0.48);
uniform vec3 glow_color : source_color = vec3(0.3, 0.85, 1.0);
uniform float glow_strength = 0.0;
uniform float intensity = 0.16;
uniform float cluster_radius = 1000.0;
uniform float amount = 1.0;
uniform float seed = 1.0;
uniform float near_fade_start = 1800.0;
uniform float near_fade_end = 5000.0;

varying vec3 local_pos;
varying vec3 world_pos;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), u.x),
				mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), u.x), u.y),
			mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), u.x),
				mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}

float fbm(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += vnoise(p) * a;
		p = p * 2.07 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s / 0.9375;
}

void vertex() {
	local_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = local_pos.xz / cluster_radius;
	float u = length(p);
	vec3 q = vec3(local_pos.xz / 420.0, seed);
	float clumps = fbm(q);
	float wisps = vnoise(vec3(local_pos.xz / 1500.0, seed + 5.0));
	float profile = exp(-u * u * 2.6);
	float density = profile * (0.3 + 0.95 * clumps) * (0.7 + 0.6 * wisps);
	density *= smoothstep(1.5, 1.05, u + 0.25 * (clumps - 0.5));

	vec3 l = normalize(star_position - world_pos);
	vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);
	float fwd = pow(clamp(-dot(v, l), 0.0, 1.0), 5.0);
	float back = 0.5 + 0.5 * dot(v, l);
	float phase = 0.55 + 0.35 * back + 1.6 * fwd;

	float d = distance(CAMERA_POSITION_WORLD, world_pos);
	float fade = smoothstep(near_fade_start, near_fade_end, d);
	vec3 col = dust_color * star_color * phase * intensity * density;
	col += glow_color * glow_strength * density * (0.6 + 0.6 * clumps);
	ALBEDO = col * fade * clamp(amount, 0.0, 1.0);
}

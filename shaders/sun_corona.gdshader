// Sun corona: a camera-facing additive quad round the sun sphere (Star.build).
// From the inside out: a bright chromosphere rim hugging the disc;
// prominences, flickering arcs and tongues of plasma standing off the limb;
// streamers, rays that drift outward and slowly turn; and the wide soft
// glow. All in the star's colour, whiter near the disc.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 corona_color : source_color = vec3(1.0, 0.86, 0.66);
uniform vec3 outer_color : source_color = vec3(1.0, 0.56, 0.34);
uniform float intensity : hint_range(0.0, 50.0) = 2.0;
// Sun sphere radius as a fraction of the quad half-size.
uniform float core_fraction : hint_range(0.01, 0.9) = 0.14;
uniform float ray_strength : hint_range(0.0, 1.0) = 0.12;
uniform float falloff : hint_range(0.5, 6.0) = 2.6;
uniform float seed = 0.0;
uniform float flow_speed : hint_range(0.0, 4.0) = 1.0;
// How bright the prominences on the limb are (0 = none).
uniform float prominence : hint_range(0.0, 4.0) = 1.0;

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

// Noise on a circle (angle a, wrapped seamlessly) and a second coordinate.
float ring_noise(float a, float y, float freq) {
	vec2 c = vec2(cos(a), sin(a)) * freq;
	return vnoise(c + vec2(y, seed)) * 0.6 + vnoise(c * 2.1 + vec2(-y * 1.3, seed * 1.7)) * 0.4;
}

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	float t = TIME * flow_speed;
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	// Distance off the limb, in sun radii (0 at the disc's edge).
	float h = max(r - core_fraction, 0.0) / core_fraction;
	// 0 at the edge, 1 at the quad's edge.
	float x = max(r - core_fraction, 0.0) / (1.0 - core_fraction);

	// Wide glow and the streamers drifting outward.
	float glow = pow(core_fraction / max(r, core_fraction), falloff);
	float wide = exp(-x * 3.5) * 0.35;
	float rays = ring_noise(a + t * 0.004, h * 1.2 - t * 0.05, 3.0) * 0.55 + ring_noise(a - t * 0.003, h * 0.6 - t * 0.03, 9.0) * 0.45;
	rays = pow(rays, 1.6) * 1.6;
	float shaped = (glow + wide) * (1.0 - ray_strength + ray_strength * 2.0 * rays * smoothstep(0.0, 0.25, x));

	// Chromosphere: a thin, bright, rippling rim right on the edge.
	float rim_noise = ring_noise(a, t * 0.2, 14.0);
	float rim = exp(-h * mix(28.0, 16.0, rim_noise)) * step(core_fraction, r);

	// Prominences: tongues of plasma standing off the limb where the noise
	// along the edge peaks; they rise, flicker and fade.
	float site = ring_noise(a, t * 0.015, 2.6);
	float tall = smoothstep(0.58, 0.8, site) * 0.55;
	float tongue = ring_noise(a * 1.0, h * 5.0 - t * 0.25, 22.0);
	float prom = smoothstep(tall, 0.0, h) * smoothstep(0.35, 0.75, tongue) * step(0.001, tall);
	prom *= 0.75 + 0.25 * sin(t * 1.7 + a * 5.0 + seed);

	float edge_fade = smoothstep(1.0, 0.55, r);
	vec3 col = mix(corona_color, outer_color, smoothstep(0.0, 0.6, x));
	vec3 total = col * shaped * intensity;
	total += corona_color * rim * intensity * 3.0;
	total += mix(outer_color, corona_color, 0.35) * prom * intensity * 2.2 * prominence;
	ALBEDO = total * edge_fade;
}

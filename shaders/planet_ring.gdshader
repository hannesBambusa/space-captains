// Planetary ring: flat annulus in the local XZ plane, node scaled by the planet
// radius (so inner/outer are in planet radii). Banded, semi-transparent, lit
// from the star on either face, with forward scattering and the planet's shadow
// (ray toward the star tested against the planet sphere).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 star_position = vec3(0.0);
uniform vec3 star_color : source_color = vec3(1.0);
uniform vec3 ring_color : source_color = vec3(0.82, 0.74, 0.62);
uniform vec3 ring_color_b : source_color = vec3(0.55, 0.47, 0.40);
uniform float inner = 1.3;
uniform float outer = 2.1;
uniform float opacity : hint_range(0.0, 1.0) = 0.85;
uniform float brightness : hint_range(0.0, 4.0) = 1.15;
uniform float seed = 3.0;

varying vec3 local_pos;
varying vec3 world_pos;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	float u = f * f * (3.0 - 2.0 * f);
	return mix(hash11(i + seed), hash11(i + 1.0 + seed), u);
}

void vertex() {
	local_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float r = length(local_pos.xz);
	float x = (r - inner) / (outer - inner);
	if (x < 0.0 || x > 1.0) {
		discard;
	}
	// Bands: several noise octaves along the radius, plus named gaps.
	float b = noise1(x * 18.0) * 0.45 + noise1(x * 55.0) * 0.3 + noise1(x * 160.0) * 0.25;
	float density = smoothstep(0.18, 0.75, b);
	density *= smoothstep(0.0, 0.06, x) * smoothstep(1.0, 0.9, x);
	float cassini = smoothstep(0.012, 0.0, abs(x - 0.62));
	float encke = smoothstep(0.006, 0.0, abs(x - 0.88));
	density *= (1.0 - cassini * 0.92) * (1.0 - encke * 0.8);
	// Inner C-ring is fainter, the B-ring densest.
	density *= mix(0.45, 1.0, smoothstep(0.1, 0.3, x)) * mix(1.0, 0.75, smoothstep(0.62, 0.7, x));
	vec3 col = mix(ring_color_b, ring_color, noise1(x * 31.0 + 7.0));

	vec3 n = normalize(MODEL_MATRIX[1].xyz);
	vec3 l = normalize(star_position - world_pos);
	vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);
	float lit_face = abs(dot(n, l));
	bool same_side = dot(n, l) * dot(n, v) > 0.0;
	// Lit face reflects; the unlit face only shows light scattered through thin areas.
	float face = same_side ? 0.35 + 0.65 * lit_face : (0.25 + 0.5 * (1.0 - density)) * lit_face;
	float fwd = pow(clamp(-dot(v, l), 0.0, 1.0), 6.0) * (1.0 - density) * 1.5;

	// Planet shadow.
	vec3 c = MODEL_MATRIX[3].xyz;
	float pr = length(MODEL_MATRIX[0].xyz);
	vec3 oc = world_pos - c;
	float bq = dot(oc, l);
	float cq = dot(oc, oc) - pr * pr;
	float h = bq * bq - cq;
	float shadow = 1.0;
	if (h > 0.0 && -bq - sqrt(h) > 0.0) {
		float miss = sqrt(max(dot(oc, oc) - bq * bq, 0.0)) / pr;
		shadow = smoothstep(0.97, 1.0, miss);
	}

	ALBEDO = col * star_color * brightness * (face + fwd) * (0.06 + 0.94 * shadow);
	ALPHA = clamp(density * opacity, 0.0, 1.0);
}

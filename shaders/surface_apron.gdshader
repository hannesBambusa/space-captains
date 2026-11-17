// Graded ground of a planet outpost (SurfaceDressing): the apron under a
// building (a disc: UV.x = distance from the centre as a share of the
// radius) and the track from the landing pad to a building (a strip:
// UV.x = across, UV.y = metres along). Compacted, darker ground with slab
// seams, stains and drifted dust, fading raggedly into the terrain at its
// edge. UV2 = zone metres, for noise that runs on across the pieces.
shader_type spatial;
render_mode blend_mix, depth_draw_never, diffuse_burley, specular_schlick_ggx;

uniform vec3 base : source_color = vec3(0.2);
uniform bool track = false;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = UV2;
	float big = fbm(p * 0.05);
	float fine = vnoise(p * 1.3);
	// 0 at the middle, 1 at the edge.
	float edge = track ? abs(UV.x - 0.5) * 2.0 : UV.x;
	float ragged = edge + (big - 0.5) * (track ? 0.5 : 0.14);
	float alpha = 1.0 - smoothstep(track ? 0.55 : 0.86, track ? 1.0 : 1.0, ragged);
	vec3 c = base * mix(0.82, 1.12, big) * mix(0.93, 1.05, fine);
	float rough = 0.9;
	if (track) {
		// Two packed ruts and a paler crown.
		float rut = smoothstep(0.12, 0.0, abs(abs(UV.x - 0.5) - 0.22));
		c *= mix(1.0, 0.86, rut);
		c *= mix(1.0, 1.08, smoothstep(0.1, 0.0, abs(UV.x - 0.5)));
	} else {
		// Slabs: seams every 9 m, each slab a slightly different grey.
		vec2 cell = p / 9.0;
		vec2 f = abs(fract(cell) - 0.5);
		float seam = smoothstep(0.455, 0.49, max(f.x, f.y));
		float slab = hash12(floor(cell));
		float paved = 1.0 - smoothstep(0.78, 0.86, ragged);
		c *= mix(1.0, mix(0.9, 1.08, slab), paved);
		c *= mix(1.0, 0.5, seam * paved);
		c *= mix(1.0, 1.7, paved);
		// Oil and scorch stains.
		float stain = smoothstep(0.62, 0.8, fbm(p * 0.11 + 31.0));
		c *= mix(1.0, 0.7, stain * paved);
		rough = mix(0.9, 0.7, paved);
	}
	// Dust blown in from the edge.
	c = mix(c, c * 1.25 + 0.02, smoothstep(0.45, 0.95, ragged) * 0.5);
	ALBEDO = c;
	ROUGHNESS = rough;
	ALPHA = alpha * (track ? 0.62 : 0.97);
}

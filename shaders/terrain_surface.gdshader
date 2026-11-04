// Ground of a planet outpost's landing zone (SurfaceTerrain). Colours by
// planet type (terrain_type: PlanetDef.Type) from height, slope and world
// noise: rocky (grey-brown rock, darker cliffs, dust), ocean (green-grey
// shore rock, wet sand low), desert (warm sand, ripples, darker rock on
// steep ground), ice (blue-white snow, bare blue ice and dark rock on
// slopes, cracks), lava (black basalt, glowing cracks low and in seams),
// gas giant (the cloud deck: soft bands in the planet's tint, swirls, light
// glow from below).
// Detail fades with camera distance.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform int terrain_type = 0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float amp = 60.0;

varying vec3 v_world;
varying float v_slope;

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
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_slope = 1.0 - clamp(NORMAL.y, 0.0, 1.0);
}

void fragment() {
	vec2 p = v_world.xz;
	float big = fbm(p * 0.0015);
	float mid = fbm(p * 0.012);
	float fine = vnoise(p * 0.25);
	float h = v_world.y / max(amp, 1.0);
	float steep = smoothstep(0.18, 0.45, v_slope);
	vec3 c = vec3(0.4);
	float rough = 0.9;
	vec3 glow = vec3(0.0);
	if (terrain_type == 1) {
		// Ocean world shore.
		vec3 sand = mix(vec3(0.42, 0.40, 0.33), vec3(0.52, 0.49, 0.40), mid);
		vec3 rock = mix(vec3(0.20, 0.23, 0.21), vec3(0.30, 0.33, 0.29), big);
		c = mix(sand, rock, smoothstep(0.1, 0.5, h + 0.2 * mid) * 0.7 + steep * 0.5);
		c *= mix(0.75, 1.0, smoothstep(-0.1, 0.1, h));
	} else if (terrain_type == 2) {
		// Desert.
		vec3 sand = mix(vec3(0.62, 0.42, 0.24), vec3(0.74, 0.55, 0.33), big);
		float ripple = sin(dot(p, vec2(0.31, 0.12)) + mid * 6.0) * 0.5 + 0.5;
		sand *= mix(0.92, 1.06, ripple);
		vec3 rock = vec3(0.36, 0.24, 0.16) * mix(0.8, 1.1, mid);
		c = mix(sand, rock, steep);
		rough = 0.95;
	} else if (terrain_type == 3) {
		// Ice.
		vec3 snow = mix(vec3(0.78, 0.84, 0.90), vec3(0.92, 0.95, 0.98), mid);
		vec3 ice = vec3(0.45, 0.62, 0.78) * mix(0.85, 1.1, big);
		vec3 rock = vec3(0.18, 0.20, 0.24);
		c = mix(snow, ice, smoothstep(0.1, 0.3, v_slope) + 0.25 * smoothstep(0.55, 0.75, big));
		c = mix(c, rock, smoothstep(0.42, 0.6, v_slope));
		float crack = 1.0 - smoothstep(0.0, 0.03, abs(fbm(p * 0.006 + 3.0) - 0.5));
		c *= 1.0 - 0.35 * crack;
		rough = mix(0.6, 0.25, smoothstep(0.1, 0.3, v_slope));
	} else if (terrain_type == 4) {
		// Lava field.
		vec3 basalt = mix(vec3(0.06, 0.055, 0.055), vec3(0.14, 0.12, 0.11), mid);
		c = basalt * mix(0.8, 1.15, fine);
		float seam = 1.0 - smoothstep(0.0, 0.012, abs(fbm(p * 0.0025 + 7.0) - 0.5));
		seam *= smoothstep(0.35, 0.6, big);
		float low = 1.0 - smoothstep(-0.55, -0.35, h);
		float hot = max(seam, low);
		glow = vec3(1.0, 0.3, 0.05) * hot * (1.0 + 0.6 * fine);
		c = mix(c, vec3(0.2, 0.05, 0.02), hot * 0.5);
		rough = 0.85;
	} else if (terrain_type == 5) {
		// Gas giant cloud deck.
		float swirl = fbm(p * 0.0012 + vec2(fbm(p * 0.0005), fbm(p * 0.0005 + 5.0)) * 3.0);
		float band = sin(p.y * 0.009 + swirl * 7.0) * 0.5 + 0.5;
		float band2 = sin(p.y * 0.023 + swirl * 11.0 + 1.3) * 0.5 + 0.5;
		vec3 light_c = vec3(0.90, 0.76, 0.56);
		vec3 deep_c = vec3(0.48, 0.28, 0.16);
		c = mix(deep_c, light_c, smoothstep(0.2, 0.8, band) * 0.75 + band2 * 0.25) * mix(0.82, 1.1, mid);
		c = mix(c, vec3(0.98, 0.95, 0.9), smoothstep(0.55, 0.8, swirl) * 0.35);
		glow = c * 0.06;
		rough = 1.0;
	} else {
		// Rocky.
		vec3 dust = mix(vec3(0.27, 0.22, 0.18), vec3(0.36, 0.30, 0.24), big);
		vec3 rock = mix(vec3(0.13, 0.12, 0.11), vec3(0.21, 0.19, 0.17), mid);
		c = mix(dust, rock, steep * 0.85 + 0.15 * smoothstep(0.5, 0.8, mid));
		c *= mix(0.88, 1.08, fine);
	}
	// Small stones and pits, close up only.
	float near = 1.0 - smoothstep(200.0, 900.0, length(v_world - (INV_VIEW_MATRIX[3].xyz)));
	c *= mix(1.0, mix(0.85, 1.08, vnoise(p * 1.4)), near);
	ALBEDO = c * tint;
	ROUGHNESS = rough;
	EMISSION = glow;
}

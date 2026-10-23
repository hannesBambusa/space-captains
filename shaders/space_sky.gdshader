// Procedural deep-space sky: layered stars, hero stars, nebula band, galactic dust.
// No TIME use, so the radiance map is only rebuilt when a uniform changes.
// The smooth parts (nebula, dust, haze) render in the quarter-res pass and the
// star density field in the half-res pass; only the stars run per full-res pixel.
shader_type sky;
render_mode use_debanding, use_quarter_res_pass, use_half_res_pass;

group_uniforms base;
uniform vec3 base_color_a : source_color = vec3(0.004, 0.005, 0.014);
uniform vec3 base_color_b : source_color = vec3(0.010, 0.005, 0.020);
uniform float base_intensity : hint_range(0.0, 4.0) = 1.0;

group_uniforms stars;
uniform float star_intensity : hint_range(0.0, 8.0) = 1.0;
uniform float star_density : hint_range(0.0, 2.0) = 1.0;
uniform vec3 star_color_hot : source_color = vec3(0.62, 0.74, 1.0);
uniform vec3 star_color_white : source_color = vec3(0.95, 0.96, 1.0);
uniform vec3 star_color_warm : source_color = vec3(1.0, 0.80, 0.52);
uniform float hero_star_intensity : hint_range(0.0, 40.0) = 7.0;
uniform float hero_star_density : hint_range(0.0, 1.0) = 0.22;

group_uniforms nebula;
uniform vec3 band_normal = vec3(0.80, 0.25, -0.50);
uniform float band_width : hint_range(0.02, 1.0) = 0.30;
uniform vec3 nebula_teal : source_color = vec3(0.05, 0.42, 0.48);
uniform vec3 nebula_magenta : source_color = vec3(0.55, 0.08, 0.42);
uniform vec3 nebula_violet : source_color = vec3(0.22, 0.10, 0.55);
uniform vec3 nebula_orange : source_color = vec3(0.85, 0.36, 0.10);
uniform float nebula_intensity : hint_range(0.0, 4.0) = 0.42;
uniform float nebula_scale : hint_range(0.3, 8.0) = 1.7;
uniform float nebula_coverage : hint_range(0.0, 1.0) = 0.40;

group_uniforms dust;
uniform vec3 galaxy_glow_color : source_color = vec3(0.55, 0.50, 0.62);
uniform float galaxy_glow_intensity : hint_range(0.0, 2.0) = 0.05;
uniform float dust_darkening : hint_range(0.0, 1.0) = 0.75;
uniform float dust_scale : hint_range(1.0, 20.0) = 5.0;

group_uniforms radiance;
// Only affect the radiance cubemap (ambient light and reflections), not the visible sky.
uniform float radiance_boost : hint_range(0.0, 20.0) = 3.0;
uniform vec3 radiance_fill : source_color = vec3(0.020, 0.024, 0.040);
uniform float radiance_sun : hint_range(0.0, 50.0) = 3.0;

group_uniforms misc;
uniform float noise_seed = 7.31;

vec3 hash33(vec3 p3) {
	p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yxx) * p3.zyx);
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = hash13(i);
	float b = hash13(i + vec3(1.0, 0.0, 0.0));
	float c = hash13(i + vec3(0.0, 1.0, 0.0));
	float d = hash13(i + vec3(1.0, 1.0, 0.0));
	float e = hash13(i + vec3(0.0, 0.0, 1.0));
	float f1 = hash13(i + vec3(1.0, 0.0, 1.0));
	float g = hash13(i + vec3(0.0, 1.0, 1.0));
	float h = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(a, b, u.x), mix(c, d, u.x), u.y),
			mix(mix(e, f1, u.x), mix(g, h, u.x), u.y), u.z);
}

// Rotated octaves hide the value-noise lattice.
const mat3 OCT_ROT = mat3(
		vec3(0.00, 0.80, 0.60),
		vec3(-0.80, 0.36, -0.48),
		vec3(-0.60, -0.48, 0.64));

float fbm(vec3 p, int octaves) {
	float sum = 0.0;
	float amp = 0.5;
	float norm = 0.0;
	for (int i = 0; i < octaves; i++) {
		sum += vnoise(p) * amp;
		norm += amp;
		p = OCT_ROT * p * 2.03 + vec3(1.7, 9.2, 3.1);
		amp *= 0.5;
	}
	return sum / norm;
}

// One star layer. Stars live in a thin spherical shell of 3D cells so they are
// spread evenly over the sphere with no cube-face seams. A 2x2x2 cell lookup is
// enough because shell half-thickness + star reach stays below half a cell.
vec3 star_layer(vec3 dir, float scale, float prob, float size_rad, float bright,
		float px, float seed, float reach) {
	vec3 p = dir * scale;
	vec3 base = floor(p - 0.5);
	vec3 col = vec3(0.0);
	float sigma = max(size_rad, px * 0.75);
	float energy = (size_rad * size_rad) / (sigma * sigma);
	for (int i = 0; i < 8; i++) {
		vec3 c = base + vec3(float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1));
		vec3 h = hash33(c + seed);
		if (h.x > prob) {
			continue;
		}
		vec3 s = c + hash33(c * 1.37 + seed + 17.13);
		if (abs(length(s) - scale) > 0.5 - reach) {
			continue;
		}
		float d = length(dir - normalize(s));
		// Many faint stars, few bright ones.
		float b = bright * (0.08 + 0.92 * pow(h.y, 6.0));
		float t = h.z;
		vec3 tint = t < 0.55 ? mix(star_color_warm, star_color_white, t / 0.55)
				: mix(star_color_white, star_color_hot, (t - 0.55) / 0.45);
		col += tint * b * energy * exp(-(d * d) / (sigma * sigma));
	}
	return col;
}

vec3 hero_stars(vec3 dir, float px, float seed) {
	float scale = 11.0;
	vec3 p = dir * scale;
	vec3 base = floor(p - 0.5);
	vec3 col = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		vec3 c = base + vec3(float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1));
		vec3 h = hash33(c + seed);
		if (h.x > hero_star_density) {
			continue;
		}
		vec3 s = c + hash33(c * 2.11 + seed + 5.7);
		if (abs(length(s) - scale) > 0.12) {
			continue;
		}
		float d = length(dir - normalize(s));
		float core_sigma = max(0.0011, px * 0.9);
		float core = exp(-(d * d) / (core_sigma * core_sigma));
		float halo_r = 0.010;
		float halo = 1.0 / (1.0 + pow(d / (halo_r * 0.18), 2.0));
		halo *= smoothstep(halo_r * 3.0, 0.0, d);
		vec3 tint = h.z < 0.5 ? mix(star_color_warm, star_color_white, h.z * 2.0)
				: mix(star_color_white, star_color_hot, (h.z - 0.5) * 2.0);
		float b = hero_star_intensity * (0.35 + 0.65 * h.y);
		col += tint * b * (core + halo * 0.05);
	}
	return col;
}

// Smooth background: base gradient, galactic haze and nebula. Returns rgb and
// the dust absorption (multiplies stars) in alpha.
vec4 background(vec3 dir, vec3 seedv) {
	vec3 n = normalize(band_normal);
	float warp = fbm(dir * 1.3 + seedv, 3) - 0.5;
	float lat = dot(dir, n) + warp * 0.32;
	float band = exp(-pow(lat / band_width, 2.0));
	float band_core = exp(-pow(lat / (band_width * 0.38), 2.0));

	float g = fbm(dir * 0.8 + seedv * 2.0, 3);
	vec3 col = mix(base_color_a, base_color_b, g) * base_intensity * (0.7 + 0.6 * band);

	vec3 q = dir * nebula_scale + seedv;
	vec3 w = vec3(fbm(q + vec3(3.1, 0.0, 1.2), 4), fbm(q + vec3(7.4, 2.2, 5.5), 4), fbm(q + vec3(1.9, 8.3, 2.7), 4));
	float neb = fbm(q * 1.4 + w * 1.6, 5);
	float neb_mask = smoothstep(nebula_coverage, nebula_coverage + 0.28, neb) * band;
	float hue_a = fbm(q * 0.7 + 11.0, 3);
	float hue_b = w.x;
	vec3 neb_col = mix(nebula_teal, nebula_violet, smoothstep(0.35, 0.65, hue_a));
	neb_col = mix(neb_col, nebula_magenta, smoothstep(0.50, 0.75, hue_b) * 0.8);
	float hot = smoothstep(0.66, 0.84, neb) * smoothstep(0.55, 0.75, w.z);
	neb_col = mix(neb_col, nebula_orange, hot * 0.7);
	float neb_bright = neb_mask * (0.35 + 0.9 * smoothstep(0.5, 0.85, neb));

	float dust = fbm(dir * dust_scale + seedv * 3.0 + w * 0.8, 5);
	float lanes = smoothstep(0.42, 0.62, dust) * band_core;
	float absorb = 1.0 - dust_darkening * lanes;

	float haze = band_core * (0.55 + 0.45 * fbm(dir * 3.0 + seedv, 4));
	col += galaxy_glow_color * galaxy_glow_intensity * haze * absorb;
	col += neb_col * nebula_intensity * neb_bright * mix(1.0, absorb, 0.6);
	return vec4(col, absorb);
}

// Star density from the galactic band and a large-scale cluster field.
float star_density_at(vec3 dir, vec3 seedv) {
	vec3 n = normalize(band_normal);
	float warp = fbm(dir * 1.3 + seedv, 3) - 0.5;
	float band = exp(-pow((dot(dir, n) + warp * 0.32) / band_width, 2.0));
	float cluster = smoothstep(0.3, 0.75, fbm(dir * 2.4 + seedv * 5.0, 3));
	return star_density * (0.55 + 0.9 * band + 0.6 * cluster);
}

vec3 stars_at(vec3 dir, float px, float dens, float absorb, bool hero) {
	vec3 stars = vec3(0.0);
	stars += star_layer(dir, 150.0, clamp(0.55 * dens, 0.0, 1.0), 0.00035, 0.30, px, 1.0, 0.22);
	stars += star_layer(dir, 95.0, clamp(0.35 * dens, 0.0, 1.0), 0.00045, 0.75, px, 2.0, 0.16);
	stars += star_layer(dir, 48.0, clamp(0.28 * dens, 0.0, 1.0), 0.00060, 1.60, px, 3.0, 0.12);
	stars *= star_intensity * absorb;
	if (hero) {
		stars += hero_stars(dir, px, 4.0) * mix(1.0, absorb, 0.5);
	}
	return stars;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 seedv = vec3(noise_seed, noise_seed * 1.7, noise_seed * 0.3);

	if (AT_CUBEMAP_PASS) {
		vec4 bg = background(dir, seedv);
		vec3 col = bg.rgb + stars_at(dir, 0.004, star_density_at(dir, seedv), bg.a, false);
		col = col * radiance_boost + radiance_fill;
		if (LIGHT0_ENABLED) {
			float sd = max(dot(dir, LIGHT0_DIRECTION), 0.0);
			col += LIGHT0_COLOR * (pow(sd, 400.0) * radiance_sun + pow(sd, 12.0) * 0.08);
		}
		COLOR = col;
	} else if (AT_QUARTER_RES_PASS) {
		vec4 bg = background(dir, seedv);
		COLOR = bg.rgb;
		ALPHA = bg.a;
	} else if (AT_HALF_RES_PASS) {
		COLOR = vec3(star_density_at(dir, seedv) * 0.25);
		ALPHA = 1.0;
	} else {
		float px = clamp(length(fwidth(dir)), 0.0003, 0.0018);
		vec4 bg = QUARTER_RES_COLOR;
		float dens = HALF_RES_COLOR.r * 4.0;
		COLOR = bg.rgb + stars_at(dir, px, dens, bg.a, true);
	}
}

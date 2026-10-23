// Procedural planet surface. One shader, six looks picked by planet_type:
//   0 ROCKY (cratered), 1 OCEAN (continents, clouds, city lights), 2 DESERT,
//   3 ICE (cracked), 4 LAVA (emissive cracks), 5 GAS_GIANT (banded flow).
// Lit manually. With use_star_position the light direction is computed per
// fragment toward star_position, so the terminator always faces the star
// wherever the planet is on its orbit. Otherwise sun_direction is used
// (sector.tscn prototype). Defaults reproduce the sector's earthlike look.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

uniform int planet_type = 1;
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0); // world space, toward the sun
uniform bool use_star_position = false;
uniform vec3 star_position = vec3(0.0);
uniform vec3 star_color : source_color = vec3(1.0);
uniform bool use_anim_time = false;
uniform float anim_time = 0.0;
uniform float seed = 1.0;
uniform float sun_intensity : hint_range(0.0, 4.0) = 1.25;
uniform float night_ambient : hint_range(0.0, 0.2) = 0.006;
uniform vec3 tint : source_color = vec3(1.0);
// World-space relief for the screen-space bump, as a fraction of the radius.
uniform float bump_strength : hint_range(0.0, 0.2) = 0.0;

group_uniforms surface;
uniform float continent_scale : hint_range(0.2, 10.0) = 2.2;
uniform float sea_level : hint_range(0.0, 1.0) = 0.52;
uniform vec3 ocean_deep : source_color = vec3(0.010, 0.040, 0.110);
uniform vec3 ocean_shallow : source_color = vec3(0.030, 0.150, 0.230);
uniform vec3 land_low : source_color = vec3(0.16, 0.20, 0.10);
uniform vec3 land_mid : source_color = vec3(0.36, 0.28, 0.17);
uniform vec3 land_high : source_color = vec3(0.55, 0.50, 0.45);
uniform vec3 ice_color : source_color = vec3(0.85, 0.90, 0.95);
uniform float ice_latitude : hint_range(0.0, 1.2) = 0.82;
uniform float band_strength : hint_range(0.0, 1.0) = 0.15;
uniform float ocean_specular : hint_range(0.0, 4.0) = 0.6;

group_uniforms palette;
// Generic palette for the non-ocean types (dark to light, plus an accent).
uniform vec3 pal_a : source_color = vec3(0.10, 0.09, 0.08);
uniform vec3 pal_b : source_color = vec3(0.30, 0.27, 0.24);
uniform vec3 pal_c : source_color = vec3(0.52, 0.48, 0.43);
uniform vec3 pal_d : source_color = vec3(0.75, 0.70, 0.62);
uniform vec3 pal_accent : source_color = vec3(1.0, 0.45, 0.12);
uniform float emission_strength : hint_range(0.0, 20.0) = 0.0;
uniform float flow_speed = 0.02;
uniform float crater_amount : hint_range(0.0, 1.0) = 0.0;

group_uniforms clouds;
uniform float cloud_amount : hint_range(0.0, 1.0) = 0.55;
uniform float cloud_scale : hint_range(0.5, 12.0) = 3.5;
uniform vec3 cloud_color : source_color = vec3(0.92, 0.94, 0.98);
uniform float cloud_speed = 0.004;

group_uniforms night;
uniform vec3 city_color : source_color = vec3(1.0, 0.62, 0.28);
uniform float city_intensity : hint_range(0.0, 4.0) = 0.22;
uniform vec3 terminator_color : source_color = vec3(1.0, 0.45, 0.25);
uniform float terminator_strength : hint_range(0.0, 1.0) = 0.6;
uniform vec3 rim_color : source_color = vec3(0.35, 0.65, 1.0);
uniform float rim_intensity : hint_range(0.0, 4.0) = 0.7;

group_uniforms rings;
// Shadow of the planet's own ring system (gas giants). Radii in body radii.
uniform float ring_shadow : hint_range(0.0, 1.0) = 0.0;
uniform float ring_inner = 1.3;
uniform float ring_outer = 2.1;

varying vec3 local_pos;
varying vec3 world_pos;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 hash33(vec3 p3) {
	p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yxx) * p3.zyx);
}

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), u.x),
				mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), u.x), u.y),
			mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), u.x),
				mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}

const mat3 OCT_ROT = mat3(vec3(0.00, 0.80, 0.60), vec3(-0.80, 0.36, -0.48), vec3(-0.60, -0.48, 0.64));

float fbm(vec3 p, int octaves) {
	float sum = 0.0;
	float amp = 0.5;
	float norm = 0.0;
	for (int i = 0; i < octaves; i++) {
		sum += vnoise(p) * amp;
		norm += amp;
		p = OCT_ROT * p * 2.02 + vec3(3.1, 1.7, 8.3);
		amp *= 0.5;
	}
	return sum / norm;
}

// Ridged noise: thin bright lines where the noise crosses 0.5.
float ridges(vec3 p, int octaves) {
	float sum = 0.0;
	float amp = 0.5;
	float norm = 0.0;
	for (int i = 0; i < octaves; i++) {
		float r = 1.0 - abs(vnoise(p) * 2.0 - 1.0);
		sum += r * r * amp;
		norm += amp;
		p = OCT_ROT * p * 2.13 + vec3(5.3, 2.9, 1.1);
		amp *= 0.5;
	}
	return sum / norm;
}

// Crater field: returns (height, rim) from a 3D cell layer on the unit sphere.
vec2 craters(vec3 p, float scale, float s) {
	vec3 q = p * scale;
	vec3 b = floor(q);
	float h = 0.0;
	float rim = 0.0;
	for (int i = 0; i < 27; i++) {
		vec3 o = vec3(float(i % 3), float((i / 3) % 3), float(i / 9)) - 1.0;
		vec3 c = b + o;
		vec3 r = hash33(c + s);
		if (r.z > 0.55) {
			continue;
		}
		vec3 fp = c + 0.2 + r * 0.6;
		float rad = 0.18 + 0.32 * r.x * r.x;
		float d = length(q - fp) / rad;
		if (d < 1.4) {
			float bowl = 1.0 - smoothstep(0.0, 1.0, d);
			float lip = exp(-pow((d - 1.0) * 4.0, 2.0));
			h += -bowl * bowl * 0.8 + lip * 0.35;
			rim = max(rim, lip);
		}
	}
	return vec2(h, rim);
}

// One gas giant band sample with the zonal winds applied as rotation offsets.
vec3 gas_sample(vec3 p, float shear) {
	float wind = sin(p.y * 14.0 + seed) * 0.6 + sin(p.y * 31.0) * 0.4;
	float ang = shear * wind;
	vec3 fp = vec3(p.x * cos(ang) - p.z * sin(ang), p.y, p.x * sin(ang) + p.z * cos(ang));
	vec3 q = fp * vec3(2.0, 9.0, 2.0) + seed;
	float turb = fbm(q, 5);
	float swirl = fbm(fp * 6.0 + turb * 2.5 + seed, 4);
	float y = p.y + (turb - 0.5) * 0.09 + (swirl - 0.5) * 0.03;
	float b1 = sin(y * 23.0 + seed) * 0.5 + 0.5;
	float b2 = sin(y * 57.0 + seed * 2.0) * 0.5 + 0.5;
	float b3 = sin(y * 9.0 + seed * 3.0) * 0.5 + 0.5;
	vec3 c = mix(pal_a, pal_b, b3);
	c = mix(c, pal_c, smoothstep(0.3, 0.8, b1) * 0.8);
	c = mix(c, pal_d, smoothstep(0.65, 0.95, b2) * 0.55);
	return c * (0.88 + 0.24 * swirl);
}

void vertex() {
	local_pos = normalize(VERTEX);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Screen-space bump from a scalar height field (world metres).
vec3 bump_normal(vec3 n, float h_world) {
	vec3 dpdx = dFdx(world_pos);
	vec3 dpdy = dFdy(world_pos);
	float dhdx = dFdx(h_world);
	float dhdy = dFdy(h_world);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
	return normalize(abs(det) * n - grad);
}

void fragment() {
	float t = use_anim_time ? anim_time : TIME;
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 l = use_star_position ? normalize(star_position - world_pos) : normalize(sun_direction);
	vec3 p = local_pos;
	vec3 sp = p * continent_scale + vec3(seed * 7.1, seed * 3.3, seed * 1.9);
	float lat = abs(p.y);
	float body_radius = length(MODEL_MATRIX[0].xyz);

	vec3 albedo = vec3(0.5);
	vec3 emission = vec3(0.0);
	float height = 0.0;       // 0..1 relief for bump
	float spec_mask = 0.0;
	float spec_power = 48.0;
	float land = 1.0;
	float elev = 0.0;
	float soft_terminator = 0.0;
	float cl = 0.0;
	float city_mask = 0.0;

	// Clouds rotate slowly around the planet's axis.
	float ca = t * cloud_speed;
	vec3 cp = vec3(p.x * cos(ca) - p.z * sin(ca), p.y, p.x * sin(ca) + p.z * cos(ca));

	if (planet_type == 1) {
		// OCEAN / earthlike.
		vec3 w = vec3(fbm(sp + 4.0, 3), fbm(sp + 9.0, 3), fbm(sp + 13.0, 3));
		float h = fbm(sp + w * 1.2, 7);
		float bands = sin(p.y * 9.0 + fbm(sp * 0.7, 3) * 4.0) * 0.5 + 0.5;
		land = smoothstep(sea_level, sea_level + 0.012, h);
		float depth = clamp((sea_level - h) / max(sea_level, 0.001), 0.0, 1.0);
		vec3 ocean = mix(ocean_shallow, ocean_deep, smoothstep(0.0, 0.25, depth));
		elev = clamp((h - sea_level) / max(1.0 - sea_level, 0.001), 0.0, 1.0);
		vec3 ground = mix(land_low, land_mid, smoothstep(0.02, 0.22, elev + (fbm(sp * 4.0, 3) - 0.5) * 0.2));
		ground = mix(ground, land_high, smoothstep(0.25, 0.5, elev));
		ground = mix(ground, land_mid * 1.15, smoothstep(0.35, 0.0, lat) * 0.45);
		albedo = mix(ocean, ground, land);
		albedo *= 1.0 - band_strength + band_strength * 2.0 * bands;
		float ice = smoothstep(ice_latitude - 0.06, ice_latitude + 0.02, lat + (h - 0.5) * 0.25);
		albedo = mix(albedo, ice_color, ice);
		height = elev * land;
		spec_mask = (1.0 - land) * (1.0 - ice);
		float city_region = smoothstep(0.5, 0.7, fbm(sp * 3.0 + 7.0, 3));
		city_mask = smoothstep(0.66, 0.82, fbm(sp * 26.0 + 2.0, 3)) * city_region * land * (1.0 - ice) * smoothstep(0.6, 0.1, elev);
	} else if (planet_type == 0) {
		// ROCKY: grey-brown regolith, maria, craters.
		float h = fbm(sp, 6);
		float maria = smoothstep(0.52, 0.42, fbm(sp * 0.6 + 3.0, 4));
		vec2 c1 = craters(p, 7.0, seed);
		vec2 c2 = craters(p, 19.0, seed + 11.0);
		vec2 c3 = craters(p, 47.0, seed + 23.0);
		float cr = (c1.x + c2.x * 0.6 + c3.x * 0.35) * crater_amount;
		height = h * 0.6 + cr * 0.25;
		albedo = mix(pal_b, pal_c, smoothstep(0.35, 0.65, h));
		albedo = mix(albedo, pal_a, maria * 0.7);
		albedo = mix(albedo, pal_d, clamp((c1.y + c2.y * 0.7) * crater_amount * 0.5, 0.0, 1.0));
		albedo *= 0.85 + 0.3 * fbm(sp * 9.0, 3);
	} else if (planet_type == 2) {
		// DESERT: dune seas, dark rocky plateaus, canyons, small polar caps.
		vec3 w = vec3(fbm(sp + 2.0, 3), fbm(sp + 6.0, 3), fbm(sp + 12.0, 3));
		float h = fbm(sp + w * 1.4, 6);
		float plateau = smoothstep(0.54, 0.6, h);
		float canyon = smoothstep(0.82, 0.97, ridges(sp * 1.6 + w, 4)) * (1.0 - plateau);
		float dune_phase = dot(p, normalize(vec3(0.4, 0.2, 1.0))) * 40.0 * continent_scale + fbm(sp * 3.0, 3) * 18.0;
		// Fade the dune ripples out before they alias at distance.
		float dune_aa = 1.0 - smoothstep(0.4, 1.2, fwidth(dune_phase));
		float dunes = 0.5 + (sin(dune_phase) * 0.5) * dune_aa;
		float lat_band = sin(p.y * 7.0 + w.x * 3.0) * 0.5 + 0.5;
		albedo = mix(pal_c, pal_d, lat_band * 0.6 + dunes * 0.15);
		albedo = mix(albedo, pal_b, plateau * 0.8);
		albedo = mix(albedo, pal_a, canyon * 0.8);
		albedo *= 0.9 + 0.2 * fbm(sp * 8.0, 3);
		float cap = smoothstep(ice_latitude - 0.03, ice_latitude + 0.02, lat + (h - 0.5) * 0.2);
		albedo = mix(albedo, ice_color, cap);
		height = h * 0.5 + plateau * 0.4 - canyon * 0.5 + dunes * 0.04;
	} else if (planet_type == 3) {
		// ICE: bright shell, blue-grey older terrain, dark crack lines.
		vec3 w = vec3(fbm(sp + 1.0, 3), fbm(sp + 5.0, 3), fbm(sp + 8.0, 3));
		float h = fbm(sp + w, 5);
		float cracks = smoothstep(0.7, 0.88, ridges(sp * 1.2 + w * 0.8, 4));
		float fine = smoothstep(0.76, 0.92, ridges(sp * 4.5 + w * 2.0, 3));
		albedo = mix(pal_c, pal_d, smoothstep(0.38, 0.62, h));
		albedo = mix(albedo, pal_b, smoothstep(0.6, 0.72, fbm(sp * 0.7 + 4.0, 4)) * 0.6);
		albedo = mix(albedo, pal_a, clamp(cracks * 0.8 + fine * 0.4, 0.0, 1.0));
		// Reddish-brown deposits along the big fractures (Europa-like lineae).
		albedo = mix(albedo, pal_accent, cracks * smoothstep(0.45, 0.7, fbm(sp * 2.0 + 9.0, 3)) * 0.45);
		height = h * 0.4 - cracks * 0.35;
		spec_mask = 0.35 * (1.0 - cracks);
		spec_power = 24.0;
	} else if (planet_type == 4) {
		// LAVA: dark basalt crust, glowing cracks and lava seas.
		vec3 w = vec3(fbm(sp + 3.0, 3), fbm(sp + 7.0, 3), fbm(sp + 11.0, 3));
		float h = fbm(sp + w * 1.3, 6);
		float seas = smoothstep(0.35, 0.30, h);
		float crack = smoothstep(0.78, 0.95, ridges(sp * 1.4 + w * 1.5, 5));
		float fine = smoothstep(0.86, 0.97, ridges(sp * 5.0 + w * 3.0, 3)) * 0.6;
		float hot = clamp(max(seas, max(crack, fine)), 0.0, 1.0);
		float pulse = 0.85 + 0.15 * sin(t * 0.8 + fbm(sp * 2.0, 2) * 12.0);
		albedo = mix(pal_a, pal_b, smoothstep(0.4, 0.75, h));
		albedo *= 0.8 + 0.4 * fbm(sp * 10.0, 3);
		albedo = mix(albedo, pal_a * 0.6, hot);
		vec3 glow = mix(pal_accent, vec3(1.0, 0.62, 0.22), seas * 0.4 + crack * 0.1);
		emission = glow * hot * emission_strength * pulse;
		height = h * 0.6 - hot * 0.3;
	} else {
		// GAS_GIANT: latitude bands with differential (zonal) flow. Two flow
		// phases cross-fade so the shear never winds up over long sim times.
		float phase = t * flow_speed;
		float f1 = fract(phase);
		float f2 = fract(phase + 0.5);
		float wgt = abs(1.0 - 2.0 * f1);
		vec3 g1 = gas_sample(p, (f1 - 0.5) * 1.6);
		vec3 g2 = gas_sample(p, (f2 - 0.5) * 1.6);
		albedo = mix(g1, g2, wgt);
		// Great storm, carried along by the slow overall rotation only.
		vec3 sc = normalize(vec3(0.75, -0.32, 0.55));
		vec3 dvec = p - sc;
		float storm_d = length(dvec * vec3(1.0, 2.1, 1.0)) / 0.16;
		float storm_n = fbm(p * 14.0 + seed, 3);
		float storm = exp(-storm_d * storm_d * 1.3) * (0.75 + 0.5 * storm_n);
		float storm_ring = exp(-pow((storm_d - 0.85) * 3.0, 2.0));
		albedo = mix(albedo, pal_accent, clamp(storm, 0.0, 1.0) * 0.85);
		albedo = mix(albedo, pal_d, storm_ring * 0.4);
		// Polar haze.
		albedo = mix(albedo, pal_b * 0.8, smoothstep(0.75, 0.97, lat) * 0.7);
		soft_terminator = 1.0;
	}

	albedo *= tint;

	// Clouds (ocean thick, desert/ice thin, configured by cloud_amount).
	if (cloud_amount > 0.0) {
		vec3 cq = cp * cloud_scale + vec3(seed * 2.3);
		// Warped base shapes, eroded by fine detail so the edges stay crisp up close.
		vec3 cw = vec3(fbm(cq * 0.6 + 21.0, 3), fbm(cq * 0.6 + 34.0, 3), fbm(cq * 0.6 + 47.0, 3)) - 0.5;
		float base = fbm(cq + cw * 2.2, 6);
		float detail = fbm(cq * 6.0 + cw * 3.0 + 7.0, 3);
		float c = base - (detail - 0.5) * 0.16;
		cl = smoothstep(1.0 - cloud_amount, 1.0 - cloud_amount + 0.2, c) * cloud_amount * 1.4;
		cl = clamp(cl, 0.0, 1.0);
	}

	vec3 nb = n;
	if (bump_strength > 0.0) {
		nb = bump_normal(n, height * bump_strength * body_radius);
	}

	float ndl_geo = dot(n, l);
	float ndl = dot(nb, l);
	float diffuse = soft_terminator > 0.5
			? smoothstep(-0.12, 0.6, ndl_geo) * (0.55 + 0.45 * clamp(ndl_geo, 0.0, 1.0))
			: clamp(ndl * 1.05 + 0.03, 0.0, 1.0) * smoothstep(-0.08, 0.05, ndl_geo);
	float term = smoothstep(-0.05, 0.18, ndl_geo) * smoothstep(0.42, 0.0, ndl_geo);
	vec3 light_col = mix(vec3(1.0), terminator_color, term * terminator_strength) * sun_intensity * star_color;

	// Ring shadow: march toward the star and test the equatorial ring plane.
	if (ring_shadow > 0.0) {
		vec3 c = MODEL_MATRIX[3].xyz;
		vec3 rn = normalize(MODEL_MATRIX[1].xyz);
		float denom = dot(l, rn);
		if (abs(denom) > 0.001) {
			float tt = dot(c - world_pos, rn) / denom;
			if (tt > 0.0) {
				float rr = length(world_pos + l * tt - c) / body_radius;
				float in_ring = smoothstep(ring_inner, ring_inner + 0.05, rr) * smoothstep(ring_outer, ring_outer - 0.08, rr);
				float bands = 0.55 + 0.45 * sin(rr * 61.0) * sin(rr * 23.0 + 1.0);
				light_col *= 1.0 - in_ring * ring_shadow * bands;
			}
		}
	}

	vec3 surface = albedo * (1.0 - cl);
	vec3 col = surface * diffuse * light_col;
	// Specular glint (oceans, ice).
	vec3 r = reflect(-l, nb);
	float spec = pow(max(dot(r, v), 0.0), spec_power) * spec_mask * (1.0 - cl) * ocean_specular;
	col += vec3(1.0, 0.92, 0.8) * star_color * spec * smoothstep(0.0, 0.2, ndl_geo);
	col += cloud_color * cl * clamp(ndl_geo * 1.05 + 0.03, 0.0, 1.0) * light_col;

	// Night side: city lights, lava glow stays visible everywhere.
	float night = smoothstep(0.05, -0.15, ndl_geo);
	col += city_color * city_mask * night * city_intensity * (1.0 - cl * 0.8);
	col += albedo * night_ambient;
	col += emission * (1.0 - cl * 0.7) * mix(0.75, 1.25, night);

	// Thin atmosphere scatter at the rim of the disc.
	float mu = clamp(dot(n, v), 0.0, 1.0);
	float rim = pow(1.0 - mu, 3.0);
	col += rim_color * rim * rim_intensity * smoothstep(-0.25, 0.4, ndl_geo);

	ALBEDO = col;
}

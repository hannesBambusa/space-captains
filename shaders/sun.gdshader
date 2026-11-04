// Sun surface: a burning plasma sphere in the star's colour (Star.build).
// Layers, all in object space on the unit sphere, slowly turning with
// differential rotation (the equator runs ahead of the poles):
//  - plasma: domain-warped fbm, the big churning flows;
//  - granulation: Worley cells, bright tops and dark lanes between them,
//    drifting and boiling;
//  - filaments: ridged noise, thin white-hot streaks;
//  - sunspots: rare dark umbrae with a lighter penumbra;
//  - faculae: bright patches that show near the limb;
//  - limb darkening.
// The result is a heat value run through a colour ramp: a dark, saturated
// version of the star's colour, the colour itself, then white-hot. Values
// go well above 1.0 so the glow pass blooms the hot parts.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

uniform vec3 star_color : source_color = vec3(1.0, 0.76, 0.3);
uniform float intensity : hint_range(0.0, 100.0) = 3.6;
// Offsets every pattern, so two stars never look alike.
uniform float seed = 0.0;
// Speed of every motion (1 = normal).
uniform float flow_speed : hint_range(0.0, 4.0) = 1.0;
// How many and how big the sunspots are (0 = none).
uniform float spots : hint_range(0.0, 1.0) = 0.5;

varying vec3 local_pos;

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

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
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.02 + vec3(1.7, 9.2, 4.1);
		a *= 0.5;
	}
	return v;
}

// Worley: distances to the nearest and second nearest feature point.
vec2 worley(vec3 p, float t) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 o = hash33(i + g);
				// Feature points wander: the cells boil.
				o = 0.5 + 0.42 * sin(t + 6.2831 * o);
				vec3 r = g + o - f;
				float d = dot(r, r);
				if (d < d1) {
					d2 = d1;
					d1 = d;
				} else if (d < d2) {
					d2 = d;
				}
			}
		}
	}
	return vec2(sqrt(d1), sqrt(d2));
}

vec3 rotate_y(vec3 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}

void vertex() {
	local_pos = normalize(VERTEX);
}

void fragment() {
	float t = TIME * flow_speed;
	vec3 n = normalize(local_pos);
	// Differential rotation: the equator turns faster than the poles.
	n = rotate_y(n, t * 0.01 * (1.0 - 0.4 * n.y * n.y));
	vec3 s = vec3(seed * 1.37, seed * 0.71, seed * 2.13);

	// Big churning flows: fbm warped by fbm.
	vec3 q = n * 2.6 + s;
	vec3 warp = vec3(fbm(q + vec3(0.0, 0.0, t * 0.018)), fbm(q + vec3(5.2, 1.3, -t * 0.015)), fbm(q + vec3(9.7, 4.4, t * 0.012)));
	vec3 p = n * 5.0 + warp * 1.8 + s;
	float plasma = fbm(p + vec3(t * 0.02, -t * 0.015, 0.0));

	// Granulation: rounded cell tops, soft dark lanes between them. The
	// sample point is warped by small-scale noise so no cell is a polygon,
	// and the lanes fade in and out so the grid never reads as a grid.
	vec3 gp = n * 30.0 + warp * 2.2 + s;
	gp += (vec3(vnoise(gp * 0.9 + t * 0.1), vnoise(gp * 0.9 + 7.3), vnoise(gp * 0.9 - 3.1)) - 0.5) * 1.1;
	vec2 w = worley(gp, t * 0.35);
	float lane = 1.0 - smoothstep(0.0, 0.42, w.y - w.x);
	float dome = 1.0 - smoothstep(0.0, 0.9, w.x);
	float cells = clamp(1.0 - lane * mix(0.35, 0.8, vnoise(n * 6.0 + s + t * 0.05)) + dome * 0.15, 0.0, 1.1);
	vec3 fp = n * 85.0 + warp * 3.0 + s * 2.0;
	fp += (vec3(vnoise(fp * 0.8), vnoise(fp * 0.8 + 4.2), vnoise(fp * 0.8 - 6.6)) - 0.5) * 1.2;
	vec2 w2 = worley(fp, t * 0.6);
	float fine_cells = 1.0 - (1.0 - smoothstep(0.0, 0.45, w2.y - w2.x)) * 0.5;

	// Thin white-hot filaments along the flows.
	float ridge = 1.0 - abs(fbm(p * 1.7 + vec3(-t * 0.03, t * 0.02, 0.0)) * 2.0 - 1.0);
	float filament = pow(ridge, 7.0);

	// Sunspots: rare dark umbrae, a lighter ring of penumbra round each.
	float spot_n = fbm(n * 4.2 + s * 0.53 + vec3(0.0, t * 0.002, 0.0));
	float th = mix(0.8, 0.58, spots);
	float umbra = smoothstep(th + 0.035, th + 0.06, spot_n);
	float penumbra = smoothstep(th, th + 0.035, spot_n) - umbra;
	// Penumbra fibrils radiate from the spot.
	penumbra *= 0.75 + 0.25 * vnoise(n * 160.0 + s);

	float mu = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float limb = pow(mu, 0.55);
	// Faculae: bright patches that only stand out near the limb.
	float faculae = smoothstep(0.55, 0.72, fbm(n * 7.5 + s + 3.0)) * pow(1.0 - mu, 1.5);

	float heat = 0.18 + 0.62 * plasma;
	heat *= mix(0.7, 1.0, cells) * mix(0.9, 1.0, fine_cells);
	heat += filament * 0.38;
	heat *= 1.0 - penumbra * 0.42 - umbra * 0.82;
	heat = heat * (0.42 + 0.58 * limb) + faculae * 0.35;
	heat = clamp(heat, 0.0, 1.2);

	// Colour ramp: deep (dark, saturated), the star's colour, white-hot.
	vec3 base = star_color;
	vec3 deep = base * base * 0.32;
	vec3 hot = mix(base, vec3(1.0), 0.7);
	vec3 col = heat < 0.55 ? mix(deep, base, heat / 0.55) : mix(base, hot, clamp((heat - 0.55) / 0.5, 0.0, 1.0));
	// The edge burns a little redder or deeper, like a real limb.
	col = mix(col, deep * 1.6, (1.0 - limb) * 0.35);
	// Most of the disc stays under the bloom threshold so its detail reads;
	// only the hottest cells and filaments push past it.
	ALBEDO = col * intensity * (0.3 + 0.7 * heat + 1.2 * pow(max(heat - 0.75, 0.0), 2.0));
}

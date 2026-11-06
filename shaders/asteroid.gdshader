// Asteroid material for MultiMesh belts and clusters. Carries the glb's PBR inputs (copied
// from its StandardMaterial3D at load time) and tumbles each instance in the
// vertex stage so thousands of asteroids spin for free.
// Surface detail (procedural, in the rock's own space in metres, so it turns
// with the rock and has no UV seams): a height field of craters (cellular
// bowls with raised rims), broad lumps and fine grain lights the surface
// as bump detail (derivative bump mapping) and drives the albedo: dark
// crater floors, bright rims, mottled patches, dust in the hollows, and a
// rougher, duller look there. It fades out with distance (before the
// mesh LOD) so far rocks do not shimmer. Ore surfaces (metallic) and glowing
// crystal get less of it.
// INSTANCE_CUSTOM: x = axis azimuth (0..1), y = axis z (0..1), z = spin rad/s, w = phase/tint seed.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_albedo_texture = false;
uniform bool use_vertex_color = false;

uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D metallic_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 metallic_channel = vec4(0.0, 0.0, 1.0, 0.0);
uniform bool use_metallic_texture = false;

uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D roughness_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 roughness_channel = vec4(0.0, 1.0, 0.0, 0.0);
uniform bool use_roughness_texture = false;
uniform float specular : hint_range(0.0, 1.0) = 0.5;

uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal_texture = false;
uniform float normal_scale : hint_range(-4.0, 4.0) = 1.0;

uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 1.0;
uniform sampler2D emission_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool use_emission_texture = false;

// Per MultiMeshInstance3D: lets each belt push crystal glow harder.
instance uniform float emission_boost = 1.0;
// Per MultiMeshInstance3D distance LOD: asteroids shrink to nothing between
// lod_fade_start and lod_fade_end (camera distance, metres). 0 = off.
instance uniform float lod_fade_start = 0.0;
instance uniform float lod_fade_end = 0.0;
// Per MultiMeshInstance3D cluster thinning: instances whose seed
// (INSTANCE_CUSTOM.w) is below thin_level shrink away (0 = all shown).
instance uniform float thin_level = 0.0;
// Per MultiMeshInstance3D size floor: far rocks grow so their radius never
// drops under this many screen pixels (0 = off), so a far cluster reads as
// small lit rocks instead of vanishing.
instance uniform float min_px = 0.0;
// Slight per-instance brightness variation so repeated meshes read as different rocks.
uniform float tint_variation : hint_range(0.0, 0.5) = 0.18;

// Surface detail (see the header).
uniform float detail_strength : hint_range(0.0, 2.0) = 1.0;
// Crater cells per metre, and how deep a crater is in metres per metre of cell.
uniform float crater_freq = 0.07;
uniform float crater_depth = 0.8;
// Bump strength of the height field.
uniform float bump_strength = 1.6;
// Camera distance where the detail starts and ends fading out, metres.
uniform vec2 detail_fade = vec2(900.0, 2200.0);

// Ore in the rock (set per variant by AsteroidBelt): 0 none, 1 veins (iron),
// 2 blobs (titanium). Soft-edged, in the rock's own space, with its own
// colour, metal and gloss, and a faint sheen.
uniform int ore_mode = 0;
uniform vec3 ore_color : source_color = vec3(0.62, 0.26, 0.08);
uniform float ore_metallic = 0.75;
uniform float ore_roughness = 0.45;
// Veins or blobs per metre.
uniform float ore_freq = 0.09;

varying float v_tint;
// Rock-local position in metres (before the tumble) and a per-rock seed.
varying vec3 v_obj;
varying float v_seed;
varying float v_dist;

mat3 axis_angle(vec3 axis, float a) {
	float s = sin(a);
	float c = cos(a);
	float t = 1.0 - c;
	return mat3(
			vec3(t * axis.x * axis.x + c, t * axis.x * axis.y + s * axis.z, t * axis.x * axis.z - s * axis.y),
			vec3(t * axis.x * axis.y - s * axis.z, t * axis.y * axis.y + c, t * axis.y * axis.z + s * axis.x),
			vec3(t * axis.x * axis.z + s * axis.y, t * axis.y * axis.z - s * axis.x, t * axis.z * axis.z + c));
}

void vertex() {
	float az = INSTANCE_CUSTOM.x * 6.2831853;
	float z = INSTANCE_CUSTOM.y * 2.0 - 1.0;
	float rxy = sqrt(max(1.0 - z * z, 0.0));
	vec3 axis = vec3(rxy * cos(az), z, rxy * sin(az));
	mat3 rot = axis_angle(axis, TIME * INSTANCE_CUSTOM.z + INSTANCE_CUSTOM.w * 6.2831853);
	float lod = 1.0;
	if (lod_fade_end > 0.0) {
		float d = distance(MODEL_MATRIX[3].xyz, INV_VIEW_MATRIX[3].xyz);
		lod = 1.0 - smoothstep(lod_fade_start, lod_fade_end, d);
	}
	if (thin_level > 0.0) {
		lod *= smoothstep(thin_level, thin_level + 0.04, INSTANCE_CUSTOM.w);
	}
	float scale_m = length(MODEL_MATRIX[0].xyz);
	v_obj = VERTEX * scale_m + vec3(INSTANCE_CUSTOM.w * 173.0, INSTANCE_CUSTOM.w * 91.0, INSTANCE_CUSTOM.w * 57.0);
	v_seed = INSTANCE_CUSTOM.w;
	v_dist = distance(MODEL_MATRIX[3].xyz, INV_VIEW_MATRIX[3].xyz);
	if (min_px > 0.0) {
		float world_per_px = 2.0 * v_dist / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
		lod *= max(1.0, min_px * world_per_px / max(scale_m, 0.01));
	}
	VERTEX = rot * VERTEX * lod;
	NORMAL = rot * NORMAL;
	TANGENT = rot * TANGENT;
	BINORMAL = rot * BINORMAL;
	v_tint = 1.0 + (fract(INSTANCE_CUSTOM.w * 13.37) * 2.0 - 1.0) * tint_variation;
}

// --- Detail noise -------------------------------------------------------------

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

float fbm(vec3 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < oct; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 4.1);
		a *= 0.5;
	}
	return v;
}

// Craters: x = height (bowl down, rim up), y = 0..1 inside a crater (floor mask).
vec2 craters(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float h = 0.0;
	float inside = 0.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 o = hash33(i + g);
				// Not every cell holds a crater; sizes vary.
				float r = mix(0.18, 0.5, o.x) * step(0.35, o.y);
				if (r <= 0.0) {
					continue;
				}
				float d = length(g + o - f) / r;
				if (d < 1.4) {
					float bowl = d < 1.0 ? (d * d - 1.0) : 0.0;
					float rim = exp(-pow((d - 1.0) * 4.0, 2.0)) * 0.35;
					h += (bowl + rim) * r;
					inside = max(inside, 1.0 - smoothstep(0.7, 1.0, d));
				}
			}
		}
	}
	return vec2(h, inside);
}

void fragment() {
	vec4 alb = albedo_color;
	if (use_albedo_texture) {
		alb *= texture(albedo_texture, UV);
	}
	if (use_vertex_color) {
		alb *= COLOR;
	}
	// Surface detail, faded out with distance and on ore and crystal surfaces.
	float glow_surface = step(0.01, dot(emission_color, vec3(1.0)));
	float rockiness = (1.0 - 0.55 * metallic) * (1.0 - 0.8 * glow_surface);
	float k = detail_strength * rockiness * (1.0 - smoothstep(detail_fade.x, detail_fade.y, v_dist));
	float dust = 0.0;
	float rough_add = 0.0;
	float ore = 0.0;
	if (ore_mode > 0) {
		vec3 q = v_obj * ore_freq;
		// A wobble so veins wander instead of following the noise grid.
		q += vec3(fbm(q * 2.1 + 5.0, 2), fbm(q * 2.1 + 11.0, 2), fbm(q * 2.1 + 17.0, 2)) * 0.6;
		if (ore_mode == 1) {
			float n = vnoise(q) * 2.0 - 1.0;
			float n2 = vnoise(q * 2.3 + 3.0) * 2.0 - 1.0;
			ore = max(1.0 - smoothstep(0.05, 0.12, abs(n)), 0.7 * (1.0 - smoothstep(0.04, 0.09, abs(n2))));
		} else {
			float b = fbm(q, 3);
			ore = smoothstep(0.56, 0.62, b);
		}
		ore *= 1.0 - smoothstep(detail_fade.y, detail_fade.y * 1.6, v_dist) * 0.5;
	}
	if (k > 0.001) {
		vec3 p = v_obj;
		vec2 cr = craters(p * crater_freq);
		vec2 cr2 = craters(p * crater_freq * 3.1 + 7.0);
		float lumps = fbm(p * 0.045, 3);
		float grain = fbm(p * 0.9, 3);
		float height = (cr.x * crater_depth / crater_freq + cr2.x * crater_depth * 0.45 / (crater_freq * 3.1)) * 0.6
				+ (lumps - 0.5) * 6.0 + (grain - 0.5) * 0.25
				// Ore stands a little proud of the rock, its edges catch the light.
				+ ore * 0.5;
		// Derivative bump: the height field tilts the view-space normal.
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		float dhdx = dFdx(height);
		float dhdy = dFdy(height);
		vec3 n = normalize(NORMAL);
		vec3 r1 = cross(dpdy, n);
		vec3 r2 = cross(n, dpdx);
		float det = dot(dpdx, r1);
		vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
		// Steep jumps across a pixel (far or grazing) would alias: cap them.
		float gl = length(grad);
		grad *= gl > abs(det) * 2.5 ? abs(det) * 2.5 / gl : 1.0;
		NORMAL = normalize(mix(n, normalize(abs(det) * n - grad * bump_strength), k));
		// Albedo: mottled patches, dark crater floors, bright rims, fine speckle.
		float patches = fbm(p * 0.12 + 3.3, 4);
		float speck = vnoise(p * 4.0);
		float rim = clamp(cr.x * 6.0, 0.0, 1.0) * (1.0 - cr.y);
		float shade = mix(0.72, 1.22, patches) * (1.0 - 0.32 * cr.y - 0.18 * cr2.y) * (1.0 + 0.35 * rim) * mix(0.9, 1.1, speck);
		dust = clamp(cr.y * 0.6 + cr2.y * 0.3, 0.0, 1.0);
		alb.rgb = mix(alb.rgb, alb.rgb * shade, k);
		// Pale regolith settles in the hollows.
		alb.rgb = mix(alb.rgb, mix(alb.rgb, vec3(dot(alb.rgb, vec3(0.333)) * 1.25), 0.5), dust * 0.4 * k);
		rough_add = (dust * 0.08 - rim * 0.06) * k;
	}
	if (ore > 0.0) {
		// Crystalline grain and darker seams inside the ore, and dust in the craters over it.
		float glint = vnoise(v_obj * 2.5) * 0.25 + 0.85;
		float seam = mix(0.65, 1.15, fbm(v_obj * 0.6 + 21.0, 3));
		alb.rgb = mix(alb.rgb, ore_color * glint * seam * (1.0 - 0.35 * dust), ore);
	}
	ALBEDO = alb.rgb * v_tint;

	float m = metallic;
	if (use_metallic_texture) {
		m *= dot(texture(metallic_texture, UV), metallic_channel);
	}
	METALLIC = mix(m, ore_metallic, ore);

	float r = roughness;
	if (use_roughness_texture) {
		r *= dot(texture(roughness_texture, UV), roughness_channel);
	}
	ROUGHNESS = clamp(mix(r + rough_add, ore_roughness, ore), 0.0, 1.0);
	SPECULAR = specular;

	if (use_normal_texture) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}

	vec3 e = emission_color * emission_energy;
	if (use_emission_texture) {
		e *= texture(emission_texture, UV).rgb;
	}
	// A faint ore sheen, so veins read in the shade too.
	e += ore_color * ore * 0.06;
	EMISSION = e * emission_boost;
}

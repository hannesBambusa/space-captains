// Station shield bubble (StationShield): mostly transparent, a faint fresnel
// rim, a subtle hex lattice projected from above (the camera looks down),
// expanding ripples at up to six recent impacts, flicker when low, cells
// that grow in when raising and break up when collapsing. One mesh (a unit
// sphere scaled by the node), one material, additive.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 shield_color : source_color = vec3(0.32, 0.72, 1.0);
uniform vec3 low_color : source_color = vec3(1.0, 0.45, 0.3);
// HP share 0..1.
uniform float charge = 1.0;
uniform float radius = 400.0;
uniform float sim_time = 0.0;
// 0 = whole, 1 = no cells left (raise / collapse animation).
uniform float dissolve = 0.0;
uniform float collapsing = 0.0;
uniform float flicker = 0.0;
// Camera fade, set by the script.
uniform float view_fade = 1.0;
// Hex cell size on the plane, m.
uniform float hex_size = 26.0;
uniform float base_alpha = 0.0006;
uniform float rim_alpha = 0.3;
uniform float rim_power = 6.0;
uniform float hex_alpha = 0.06;
uniform float ripple_alpha = 0.9;
uniform float ripple_time = 1.3;
// xyz = point on the unit sphere, w = sim time of the hit.
uniform vec4 impacts[6];

varying vec3 v_unit;
varying vec3 v_normal;

void vertex() {
	v_unit = VERTEX;
	// The node scales a unit sphere unevenly (flattened bubble): build the
	// true normal (inverse-transpose of the scale) instead of the scaled one.
	mat3 m = mat3(MODEL_MATRIX);
	vec3 sc = vec3(length(m[0]), length(m[1]), length(m[2]));
	vec3 wn = m * (VERTEX / (sc * sc));
	v_normal = normalize(mat3(VIEW_MATRIX) * normalize(wn));
}

float hex_dist(vec2 p) {
	p = abs(p);
	return max(dot(p, vec2(0.5, 0.8660254)), p.x);
}

// Distance to the cell border (0 on the border, 0.5 in the middle) and the cell id.
vec3 hex_cell(vec2 uv) {
	const vec2 r = vec2(1.0, 1.7320508);
	const vec2 h = r * 0.5;
	vec2 a = mod(uv, r) - h;
	vec2 b = mod(uv - h, r) - h;
	vec2 gv = dot(a, a) < dot(b, b) ? a : b;
	vec2 id = uv - gv;
	return vec3(0.5 - hex_dist(gv), id);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec3 n = normalize(v_unit);
	float facing = abs(dot(normalize(v_normal), normalize(VIEW)));
	float rim = pow(1.0 - facing, rim_power);
	float front = FRONT_FACING ? 1.0 : 0.2;

	vec2 uv = v_unit.xz * radius / hex_size;
	vec3 hc = hex_cell(uv);
	float line = 1.0 - smoothstep(0.0, 0.06, hc.x);
	float cell_rand = hash12(hc.yz);

	// Ripples: a ring running out from each hit and a hot core.
	float ripple = 0.0;
	for (int i = 0; i < 6; i++) {
		vec4 imp = impacts[i];
		float age = (sim_time - imp.w) / ripple_time;
		if (age < 0.0 || age > 1.0) {
			continue;
		}
		float ang = acos(clamp(dot(n, normalize(imp.xyz)), -1.0, 1.0));
		float ring_r = age * 0.32;
		float ring = exp(-pow((ang - ring_r) / 0.022, 2.0)) * (1.0 - age);
		float core = exp(-ang * ang / 0.0009) * pow(1.0 - age, 2.0) * 1.6;
		ripple += ring + core;
	}

	// Raising / collapsing: cells drop out by their own random threshold.
	float cell_on = step(dissolve, cell_rand * 0.98 + 0.01);
	float edge_glow = 0.0;
	if (dissolve > 0.001) {
		float d = cell_rand - dissolve;
		edge_glow = (1.0 - smoothstep(0.0, 0.08, abs(d))) * (collapsing > 0.5 ? 2.5 : 1.2);
	}

	float k = clamp(charge, 0.0, 1.0);
	float strength = mix(0.55, 1.0, k);
	float a = base_alpha + rim * rim_alpha + line * hex_alpha * (0.08 + rim * 2.0) + ripple * ripple_alpha * (0.4 + line * 0.6);
	a = a * strength * cell_on + edge_glow * (0.006 + line * 0.1) * (0.3 + rim);

	// Low HP: a nervous flicker of whole bands.
	float flick = 1.0 - flicker * 0.55 * step(0.55, fract(sin(floor(sim_time * 18.0) * 12.9898 + floor(v_unit.y * 6.0)) * 43758.5453));
	a *= flick * front * view_fade;

	vec3 col = mix(low_color, shield_color, smoothstep(0.1, 0.45, k));
	col = mix(col, vec3(0.85, 0.95, 1.0), clamp(ripple * 0.5, 0.0, 0.6));
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}

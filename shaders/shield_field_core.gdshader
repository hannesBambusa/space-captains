// Shield Generator field core (ShieldFieldCore): the small force-field orb
// held in the emitter cradle. Same language as the station bubble
// (station_shield.gdshader): additive, unshaded, a fresnel rim, a hex
// lattice, flicker when low, cells that break up when collapsing. On top:
// the lattice slowly turns and drifts, energy bands run up and down the orb,
// a few cells sparkle, a faint inner glow and a brief flash on bubble hits.
// The lattice is unwrapped from the top pole (the RTS camera looks down), so
// the cells stay even where the camera sees them. One mesh (a sphere of
// radius [radius]), one material, mostly transparent in the middle.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 field_color : source_color = vec3(0.32, 0.72, 1.0);
uniform vec3 low_color : source_color = vec3(1.0, 0.45, 0.3);
// Bubble HP share 0..1.
uniform float charge = 1.0;
// 0 = off, 1 = fully on (raise / collapse / down sputter).
uniform float fade = 1.0;
uniform float flicker = 0.0;
// 0 = whole, 1 = no cells left.
uniform float dissolve = 0.0;
uniform float collapsing = 0.0;
// 0..1, a bubble hit just landed.
uniform float hit_flash = 0.0;
uniform float sim_time = 0.0;
uniform float radius = 4.0;
// Hex cell size on the unwrapped surface, m.
uniform float hex_size = 1.15;
uniform float base_alpha = 0.02;
uniform float rim_alpha = 0.6;
uniform float rim_power = 2.2;
uniform float hex_alpha = 0.32;
uniform float band_alpha = 0.3;
uniform float inner_alpha = 0.05;
uniform float spin_speed = 0.06;

varying vec3 v_unit;

void vertex() {
	v_unit = VERTEX / radius;
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
	float facing = abs(dot(NORMAL, VIEW));
	float rim = pow(1.0 - facing, rim_power);
	float front = FRONT_FACING ? 1.0 : 0.35;

	// Azimuthal unwrap from the top pole, turning slowly.
	float ang = atan(n.z, n.x) + sim_time * spin_speed;
	float polar = acos(clamp(n.y, -1.0, 1.0));
	vec2 p = vec2(cos(ang), sin(ang)) * polar * radius / hex_size;
	vec3 hc = hex_cell(p + vec2(0.0, sim_time * 0.05));
	float line = 1.0 - smoothstep(0.0, 0.07, hc.x);
	float cell_rand = hash12(hc.yz);

	// Energy bands: one set flowing up, a fainter one flowing down.
	float up_band = pow(0.5 + 0.5 * sin(n.y * 9.0 - sim_time * 2.2), 12.0);
	float down_band = pow(0.5 + 0.5 * sin(n.y * 6.0 + sim_time * 1.4 + 1.7), 16.0) * 0.6;
	float bands = up_band + down_band;
	// Containment line on the equator.
	float equator = exp(-pow(n.y / 0.035, 2.0)) * 0.6;

	// A few cells light up for a moment.
	float tick = floor(sim_time * 1.5 + cell_rand * 7.0);
	float sparkle = step(0.93, hash12(hc.yz + tick)) * (0.5 + 0.5 * sin(sim_time * 6.0 + cell_rand * 30.0));

	// Collapsing / raising: cells drop out by their own random threshold.
	float cell_on = step(dissolve, cell_rand * 0.98 + 0.01);
	float edge_glow = 0.0;
	if (dissolve > 0.001) {
		float d = cell_rand - dissolve;
		edge_glow = (1.0 - smoothstep(0.0, 0.1, abs(d))) * (collapsing > 0.5 ? 1.6 : 0.8);
	}

	float k = clamp(charge, 0.0, 1.0);
	float strength = mix(0.45, 1.0, k);
	float a = base_alpha
		+ rim * rim_alpha
		+ line * hex_alpha * (0.25 + rim * 1.5)
		+ bands * band_alpha * (0.3 + line * 0.7)
		+ equator * rim
		+ sparkle * 0.18 * (0.4 + line)
		+ pow(facing, 4.0) * inner_alpha * (FRONT_FACING ? 0.0 : 1.0);
	a = a * strength * cell_on + edge_glow * (0.03 + line * 0.25);
	a += hit_flash * (0.08 + rim * 0.5 + line * 0.35);

	// Low HP: a nervous flicker of whole bands.
	float flick = 1.0 - flicker * 0.6 * step(0.5, fract(sin(floor(sim_time * 18.0) * 12.9898 + floor(n.y * 5.0)) * 43758.5453));
	a *= flick * front * fade;

	vec3 col = mix(low_color, field_color, smoothstep(0.1, 0.45, k));
	col = mix(col, vec3(0.85, 0.95, 1.0), clamp(hit_flash * 0.6 + sparkle * 0.25, 0.0, 0.7));
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}

// Shield Generator field rings (ShieldFieldCore): a flat quad on the
// field core's equator. A dashed containment ring hugs the orb and pulse
// rings run out from it and fade, faster while the bubble recharges. Seen
// from above (the RTS camera), so the quad lies flat. Additive, unshaded.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 field_color : source_color = vec3(0.32, 0.72, 1.0);
uniform vec3 low_color : source_color = vec3(1.0, 0.45, 0.3);
uniform float charge = 1.0;
uniform float fade = 1.0;
uniform float flicker = 0.0;
uniform float hit_flash = 0.0;
uniform float sim_time = 0.0;
// Half the quad's side, m (the quad spans -outer..outer).
uniform float outer = 9.0;
// Where the pulses start (the orb's equator), m.
uniform float inner = 4.0;
// Pulses per sim second.
uniform float pulse_rate = 0.45;
uniform float ring_alpha = 0.35;
uniform float pulse_alpha = 0.3;
uniform float width = 0.12;
uniform int dashes = 24;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * outer;
	float r = length(p);
	float ang = atan(p.y, p.x);

	// Dashed containment ring, turning slowly the other way to the orb.
	float dash_t = fract((ang / 6.2831853 + sim_time * 0.015) * float(dashes));
	float dash = smoothstep(0.0, 0.08, dash_t) * (1.0 - smoothstep(0.62, 0.7, dash_t));
	float ring = exp(-pow((r - inner * 1.06) / width, 2.0)) * (0.35 + 0.65 * dash);

	// Pulses: three at a time, running out and thinning.
	float pulses = 0.0;
	for (int i = 0; i < 3; i++) {
		float ph = fract(sim_time * pulse_rate + float(i) / 3.0);
		float pr = mix(inner * 1.02, outer * 0.95, ph);
		float w = mix(width * 1.5, width * 4.0, ph);
		pulses += exp(-pow((r - pr) / w, 2.0)) * pow(1.0 - ph, 1.8);
	}

	float k = clamp(charge, 0.0, 1.0);
	float strength = mix(0.4, 1.0, k);
	float a = (ring * ring_alpha + pulses * pulse_alpha) * strength;
	a += hit_flash * ring * 0.6;
	float flick = 1.0 - flicker * 0.6 * step(0.5, fract(sin(floor(sim_time * 18.0) * 12.9898) * 43758.5453));
	a *= flick * fade * (1.0 - smoothstep(outer * 0.9, outer, r));

	vec3 col = mix(low_color, field_color, smoothstep(0.1, 0.45, k));
	col = mix(col, vec3(0.85, 0.95, 1.0), clamp(hit_flash * 0.5, 0.0, 0.6));
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}

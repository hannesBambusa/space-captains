// Defence zone disc (DefenseZone): a faint translucent fill, a soft glow
// toward the edge, a thin constant-pixel rim, and two faint dashed inner
// rings. Drawn on a flat quad centred on the zone (VERTEX.xz = local metres).
// alert > 0 tints it toward the alert colour and pulses (raiders inside).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 zone_color : source_color = vec4(0.4, 0.85, 1.0, 1.0);
uniform vec4 alert_color : source_color = vec4(1.0, 0.35, 0.25, 1.0);
uniform float radius = 1500.0;
uniform float fill = 0.006;
uniform float glow = 0.018;
uniform float rim = 0.4;
uniform float rim_px = 1.8;
// 0..1: selected zones are brighter.
uniform float highlight = 0.0;
// 0..1: raiders inside.
uniform float alert = 0.0;
uniform float time_s = 0.0;

varying vec2 v_pos;

void vertex() {
	v_pos = VERTEX.xz;
}

void fragment() {
	float r = length(v_pos);
	float u = r / max(radius, 1.0);
	float px = max(fwidth(r), 1e-3);
	float inside = 1.0 - smoothstep(radius - px, radius + px, r);
	float edge = 1.0 - smoothstep(rim_px * 0.5, rim_px * 0.5 + 1.0, abs(r - radius) / px);
	// Dashed inner rings at a third and two thirds.
	float ang = atan(v_pos.y, v_pos.x);
	float dash = step(0.5, fract(ang * 18.0 / 6.2831853));
	float inner = 0.0;
	for (int i = 1; i <= 2; i++) {
		float rr = radius * float(i) / 3.0;
		inner += (1.0 - smoothstep(0.5, 1.5, abs(r - rr) / px)) * dash;
	}
	float pulse = 0.65 + 0.35 * sin(time_s * 4.0);
	vec3 col = mix(zone_color.rgb, alert_color.rgb, alert * pulse);
	float k = 1.0 + highlight * 1.2;
	float a = inside * (fill + glow * u * u * u) + edge * rim + inside * inner * 0.07;
	ALBEDO = col * a * k;
}

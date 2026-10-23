// Sun corona: camera-facing additive quad around the sun sphere.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 corona_color : source_color = vec3(1.0, 0.86, 0.66);
uniform vec3 outer_color : source_color = vec3(1.0, 0.56, 0.34);
uniform float intensity : hint_range(0.0, 50.0) = 2.0;
// Sun sphere radius as a fraction of the quad half-size.
uniform float core_fraction : hint_range(0.01, 0.9) = 0.14;
uniform float ray_strength : hint_range(0.0, 1.0) = 0.12;
uniform float falloff : hint_range(0.5, 6.0) = 2.6;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	float u = f * f * (3.0 - 2.0 * f);
	return mix(hash11(i), hash11(i + 1.0), u);
}

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float rays = noise1(a * 7.0 / 6.2831 * 9.0 + TIME * 0.02) * 0.6 + noise1(a * 23.0 / 6.2831 * 4.0 - TIME * 0.015) * 0.4;
	float x = max(r - core_fraction, 0.0) / (1.0 - core_fraction);
	float glow = pow(core_fraction / max(r, core_fraction), falloff);
	float wide = exp(-x * 3.5) * 0.35;
	float shaped = (glow + wide) * (1.0 - ray_strength + ray_strength * 2.0 * rays * smoothstep(0.0, 0.25, x));
	shaped *= smoothstep(1.0, 0.55, r);
	vec3 col = mix(corona_color, outer_color, smoothstep(0.0, 0.6, x));
	ALBEDO = col * shaped * intensity;
}

// Sun core: emissive sphere with limb darkening and slow granulation.
// Values well above 1.0 so the glow pass blooms it.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

uniform vec3 core_color : source_color = vec3(1.0, 0.93, 0.80);
uniform vec3 limb_color : source_color = vec3(1.0, 0.55, 0.22);
uniform float intensity : hint_range(0.0, 100.0) = 14.0;
uniform float granulation : hint_range(0.0, 1.0) = 0.12;

varying vec3 local_pos;

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

void vertex() {
	local_pos = normalize(VERTEX);
}

void fragment() {
	float mu = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float limb = pow(mu, 0.45);
	float g = vnoise(local_pos * 18.0 + vec3(TIME * 0.05)) * 0.6 + vnoise(local_pos * 45.0 - vec3(TIME * 0.03)) * 0.4;
	vec3 col = mix(limb_color, core_color, limb);
	col *= 1.0 - granulation + granulation * 2.0 * g;
	ALBEDO = col * intensity * (0.55 + 0.45 * limb);
}

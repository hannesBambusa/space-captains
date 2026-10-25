// Body of construction_build / construction_build_double (see there).
#include "res://shaders/construction_common.gdshaderinc"

// 0..1: the surface's own emission (lights switching on at completion).
uniform float lights_on = 0.0;
// 0..1: fresh-metal tint just below the build line.
uniform float fresh = 1.0;
uniform float fresh_length = 4.0;
uniform vec4 fresh_color : source_color = vec4(0.72, 0.84, 0.98, 1.0);
// 0..1: completion flash: a band sweeping up (pulse_y) and the silhouette edges.
uniform float pulse = 0.0;
uniform float pulse_y = -10000.0;
uniform float pulse_width = 3.0;
uniform vec4 pulse_color : source_color = vec4(0.5, 0.85, 1.0, 1.0);

// The original material.
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform bool use_normal = false;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_scale = 1.0;
uniform sampler2D metallic_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 metallic_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform float metallic = 0.0;
uniform sampler2D roughness_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 roughness_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform float roughness = 1.0;
uniform float specular = 0.5;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);

varying vec3 v_site;

void vertex() {
	v_site = (to_site * vec4(VERTEX, 1.0)).xyz;
	UV = UV * uv1_scale.xy + uv1_offset.xy;
}

void fragment() {
	float d = cut_at(v_site) - v_site.y;
	vec2 fd = front_dist(d, v_site);
	if (d < 0.0) {
		discard;
	}
	float seam = max(exp(-fd.x / seam_width), exp(-fd.y / 3.0) * 0.6);
	float core = max(exp(-fd.x / (seam_width * 0.2)), exp(-fd.y / 1.2));
	float f = fresh * exp(-d / fresh_length);

	vec4 alb = albedo_color * texture(albedo_tex, UV);
	ALBEDO = mix(alb.rgb, fresh_color.rgb, f * 0.15);
	METALLIC = dot(texture(metallic_tex, UV), metallic_channel) * metallic;
	ROUGHNESS = mix(dot(texture(roughness_tex, UV), roughness_channel) * roughness, 0.35, f * 0.4);
	SPECULAR = specular;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = emission_color.rgb * emission_energy * lights_on
			+ seam_color.rgb * seam * 1.6
			+ vec3(1.0, 0.9, 0.75) * core * 3.0
			+ fresh_color.rgb * f * 0.04
			+ pulse_color.rgb * pulse * (exp(-abs(v_site.y - pulse_y) / pulse_width) * (0.25 + fres * 0.8) + fres * 0.2);
}

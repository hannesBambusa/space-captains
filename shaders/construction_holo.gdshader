// Under-construction look, blueprint pass (next_pass of construction_build).
// Above the build line: an additive cyan hologram of the finished surface:
// fresnel edge glow and a faint building-space grid with anti-aliased lines
// (fwidth based, about 1.2 px wide, faded out where the grid gets too dense
// to read, and only along the axes that run across the face, so faces lying
// on a grid plane never shimmer). Additive and no depth writes: the result
// does not depend on draw order, so nothing pops while the camera moves.
// A warm glow just above the line leads the welding seam.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

#include "res://shaders/construction_common.gdshaderinc"

uniform vec4 holo_color : source_color = vec4(0.35, 0.8, 1.0, 1.0);
uniform float grid_size = 3.0;
// 0..1 overall strength (fades in when the site opens).
uniform float intensity = 1.0;
// Projection sweep: a bright band rising over the blueprint, building-space
// height (far away = off).
uniform float scan_y = -10000.0;
uniform float scan_width = 2.0;

varying vec3 v_site;
varying vec3 v_site_n;

void vertex() {
	v_site = (to_site * vec4(VERTEX, 1.0)).xyz;
	v_site_n = normalize(mat3(to_site) * NORMAL);
}

float grid_axis(float q, float fw, float across) {
	float g = abs(fract(q - 0.5) - 0.5) / max(fw, 1e-4);
	float line = 1.0 - smoothstep(0.35, 1.25, g);
	float dense = 1.0 - smoothstep(0.08, 0.3, fw);
	return line * dense * across;
}

void fragment() {
	// Derivatives before the discard.
	vec3 q = v_site / grid_size;
	vec3 fw = fwidth(q);
	float sw = max(scan_width, fwidth(v_site.y) * 2.0);
	float d = v_site.y - cut_at(v_site);
	vec2 fd = front_dist(d, v_site);
	if (d <= 0.0) {
		discard;
	}
	vec3 n = abs(normalize(v_site_n));
	// A face shows the grid lines of the axes that run across it.
	vec3 across = 1.0 - smoothstep(0.55, 0.9, n);
	float line = max(max(grid_axis(q.x, fw.x, across.x), grid_axis(q.y, fw.y, across.y)), grid_axis(q.z, fw.z, across.z));
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.5);
	float scan = exp(-abs(v_site.y - scan_y) / sw);
	float lead = max(exp(-fd.x / (seam_width * 1.3)), exp(-fd.y / 3.0) * 0.5);
	vec3 c = holo_color.rgb * (0.02 + fres * 0.36 + line * 0.24 + scan * 0.45);
	c += seam_color.rgb * lead * 0.7;
	ALBEDO = c * intensity;
}

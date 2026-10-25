// Hologram look of arriving hostile bases (DenArrivalSite, ScavengerDen
// warp-in). Below the line (world y = fill_y) the hull is solid and lit;
// above it only a faint holographic grid shows the shape. A bright seam
// marks the line. Grid lines are anti-aliased (fwidth), fade out where they
// get too dense, and only run across a face (never along a face lying on a
// grid plane), so they do not shimmer. Buildings use construction_build /
// construction_holo instead.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back;

uniform float fill_y = 0.0;
uniform float grid_size = 3.0;
uniform vec4 hull_color : source_color = vec4(0.5, 0.52, 0.56, 1.0);
uniform vec4 seam_color : source_color = vec4(1.0, 0.58, 0.22, 1.0);
uniform vec4 holo_color : source_color = vec4(0.45, 0.75, 1.0, 1.0);

varying vec3 v_world;
varying vec3 v_wn;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

float grid_axis(float q, float fw, float across) {
	float g = abs(fract(q - 0.5) - 0.5) / max(fw, 1e-4);
	return (1.0 - smoothstep(0.35, 1.25, g)) * (1.0 - smoothstep(0.08, 0.3, fw)) * across;
}

void fragment() {
	vec3 q = v_world / grid_size;
	vec3 fw = fwidth(q);
	vec3 across = 1.0 - smoothstep(0.55, 0.9, abs(normalize(v_wn)));
	float line = max(max(grid_axis(q.x, fw.x, across.x), grid_axis(q.y, fw.y, across.y)), grid_axis(q.z, fw.z, across.z));
	float sw = max(0.9, fwidth(v_world.y) * 2.0);
	float built = step(v_world.y, fill_y);
	float seam = exp(-abs(v_world.y - fill_y) / sw);
	ALBEDO = mix(holo_color.rgb * 0.15, hull_color.rgb, built);
	METALLIC = 0.35;
	ROUGHNESS = 0.6;
	EMISSION = holo_color.rgb * line * (1.0 - built) * 1.2
			+ seam_color.rgb * line * built * 0.3
			+ seam_color.rgb * seam * 3.0;
	ALPHA = max(mix(0.06 + line * 0.55, 0.95, built), seam);
}

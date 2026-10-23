// Under-construction look for buildings. Below the build line (world y =
// fill_y) the hull is solid and lit; above it only a faint holographic grid
// shows the finished shape. A bright seam marks the build line.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled;

uniform float fill_y = 0.0;
uniform float grid_size = 3.0;
uniform vec4 hull_color : source_color = vec4(0.5, 0.52, 0.56, 1.0);
uniform vec4 seam_color : source_color = vec4(1.0, 0.58, 0.22, 1.0);
uniform vec4 holo_color : source_color = vec4(0.45, 0.75, 1.0, 1.0);

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 q = v_world / grid_size;
	vec3 g = abs(fract(q - 0.5) - 0.5) / max(fwidth(q), vec3(1e-4));
	float line = 1.0 - clamp(min(min(g.x, g.y), g.z), 0.0, 1.0);
	float built = step(v_world.y, fill_y);
	float seam = 1.0 - smoothstep(0.0, 0.9, abs(v_world.y - fill_y));
	ALBEDO = mix(holo_color.rgb * 0.15, hull_color.rgb, built);
	METALLIC = 0.35;
	ROUGHNESS = 0.6;
	EMISSION = holo_color.rgb * line * (1.0 - built) * 1.2
			+ seam_color.rgb * line * built * 0.5
			+ seam_color.rgb * seam * 3.0;
	ALPHA = max(mix(0.06 + line * 0.55, 0.95, built), seam);
}

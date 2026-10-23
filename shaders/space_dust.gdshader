// Faint dust motes near the play plane. Camera-facing quads that drift slowly
// and wrap inside a box that follows the camera focus, fading out with camera
// distance so they never read as noise when zoomed out.
// INSTANCE_CUSTOM: xyz = drift velocity (m/s), w = brightness 0..1.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 dust_color : source_color = vec3(0.55, 0.62, 0.78);
uniform float intensity : hint_range(0.0, 4.0) = 0.6;
uniform float mote_size = 0.7;            // world size in metres
uniform float min_pixel_angle = 0.0016;   // keeps far motes ~1.5 px wide
uniform vec3 focus = vec3(0.0);           // box centre, set each frame by space_dust.gd
uniform vec3 box_size = vec3(1000.0, 90.0, 1000.0);
uniform float fade_near = 12.0;
uniform float fade_start = 260.0;
uniform float fade_end = 900.0;

varying float v_alpha;

void vertex() {
	vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	center += INSTANCE_CUSTOM.xyz * TIME;
	vec3 box_min = focus - box_size * 0.5;
	center = box_min + mod(center - box_min, box_size);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float dist = length(center - cam);
	float size = max(mote_size, dist * min_pixel_angle);
	float size_fade = (mote_size * mote_size) / (size * size);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = center + (right * VERTEX.x + up * VERTEX.y) * size;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	float fade = smoothstep(fade_near, fade_near * 3.0, dist) * (1.0 - smoothstep(fade_start, fade_end, dist));
	v_alpha = fade * INSTANCE_CUSTOM.w * mix(1.0, size_fade, 0.6);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = dot(p, p);
	float m = exp(-d * 4.0) * (1.0 - smoothstep(0.7, 1.0, d));
	ALBEDO = dust_color * intensity * m * v_alpha;
}

// Mid/far view of individual asteroids: one camera-facing dot per asteroid,
// at the same position as the detailed mesh. Invisible near the camera (the
// meshes draw there), fades in as the meshes shrink away, then keeps a
// pixel-size floor with energy falloff so far belts read as sparkling bands.
// Instance transform = translation only (belt-local).
// INSTANCE_CUSTOM: x = radius (m), y = albedo 0..1, z = ore kind (0 rock,1 iron,2 titanium,3 crystal), w = seed.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 star_position = vec3(0.0);
uniform vec3 star_color : source_color = vec3(1.0);
uniform float intensity = 1.0;
uniform float min_px = 1.6;
uniform float near_start = 2600.0;
uniform float near_end = 3600.0;
// Minimum brightness factor for sub-pixel asteroids.
uniform float energy_floor = 0.02;
uniform float crystal_glow = 1.0;

varying vec3 v_color;
varying float v_alpha;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float dist = length(center - cam);
	float world_per_px = 2.0 * dist / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float true_size = INSTANCE_CUSTOM.x * 1.6;
	float size = max(true_size, world_per_px * min_px);
	float energy = max((true_size * true_size) / (size * size), energy_floor);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = center + (right * VERTEX.x + up * VERTEX.y) * size;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);

	vec3 l = normalize(star_position - center);
	vec3 v = normalize(cam - center);
	// Rocks are brightest seen from the star's side (full phase).
	float phase = 0.15 + 0.85 * pow(0.5 + 0.5 * dot(v, l), 1.5);
	float kind = INSTANCE_CUSTOM.z;
	vec3 base = vec3(0.62, 0.58, 0.54);
	vec3 glow = vec3(0.0);
	if (kind > 0.5 && kind < 1.5) {
		base = vec3(0.78, 0.48, 0.32);
	} else if (kind > 1.5 && kind < 2.5) {
		base = vec3(0.75, 0.82, 0.92);
	} else if (kind > 2.5) {
		base = vec3(0.45, 0.85, 1.0);
		glow = vec3(0.25, 0.8, 1.0) * crystal_glow;
	}
	float twinkle = 0.8 + 0.4 * sin(TIME * (0.6 + INSTANCE_CUSTOM.w * 1.7) + INSTANCE_CUSTOM.w * 40.0);
	v_color = (base * star_color * phase * INSTANCE_CUSTOM.y + glow) * intensity * twinkle;
	v_alpha = energy * smoothstep(near_start, near_end, dist);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = dot(p, p);
	float m = exp(-d * 3.5) * (1.0 - smoothstep(0.75, 1.0, d));
	ALBEDO = v_color * m * v_alpha;
}

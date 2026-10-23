// Atmosphere shell: slightly larger sphere drawn additively around a planet.
// Lit from sun_direction, or per fragment toward star_position.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0); // world space, points toward the sun
// When set, the light direction is computed per fragment toward star_position.
uniform bool use_star_position = false;
uniform vec3 star_position = vec3(0.0);
uniform vec3 atmosphere_color : source_color = vec3(0.30, 0.62, 1.0);
uniform vec3 sunset_color : source_color = vec3(1.0, 0.45, 0.20);
uniform float intensity : hint_range(0.0, 10.0) = 1.6;
// Planet radius / shell radius. The halo peaks at the planet limb.
uniform float inner_ratio : hint_range(0.5, 0.999) = 0.966;
uniform float rim_power : hint_range(0.5, 12.0) = 4.0;
uniform float sunset_strength : hint_range(0.0, 1.0) = 0.8;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 l = use_star_position ? normalize(star_position - world_pos) : normalize(sun_direction);
	float mu = clamp(dot(n, v), 0.0, 1.0);
	float limb_mu = sqrt(max(1.0 - inner_ratio * inner_ratio, 0.0));
	// Rise from the shell silhouette to the planet limb, then fade inward over the disc.
	float outer = smoothstep(0.0, limb_mu, mu);
	float inner = pow(1.0 - clamp((mu - limb_mu) / (1.0 - limb_mu), 0.0, 1.0), rim_power);
	float shape = mu < limb_mu ? outer * outer : inner;
	float ndl = dot(n, l);
	float lit = smoothstep(-0.22, 0.35, ndl);
	// Backlit rim when looking toward the sun past the planet.
	float forward = pow(max(dot(-v, l), 0.0), 8.0) * 0.5 * smoothstep(-0.4, 0.0, ndl);
	float sunset = smoothstep(-0.18, 0.0, ndl) * smoothstep(0.3, 0.02, ndl);
	vec3 col = mix(atmosphere_color, sunset_color, sunset * sunset_strength);
	ALBEDO = (col * lit + atmosphere_color * forward) * shape * intensity;
}

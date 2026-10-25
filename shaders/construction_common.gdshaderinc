// Shared by construction_build and construction_holo: both passes must compute
// the exact same build line so their halves meet without gaps or overlap.

// Mesh space -> building space.
uniform mat4 to_site = mat4(1.0);
// Build line height, building space.
uniform float cut_y = -10000.0;
uniform float seam_width = 0.6;
// Height of the noise breakup along the build line, metres.
uniform float noise_amp = 0.4;
uniform vec4 seam_color : source_color = vec4(1.0, 0.58, 0.24, 1.0);

float c_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float c_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(c_hash(i), c_hash(i + vec2(1.0, 0.0)), u.x),
			mix(c_hash(i + vec2(0.0, 1.0)), c_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// The build line at building-space point p.
float cut_at(vec3 p) {
	vec2 q = p.xz * 0.35;
	float n = c_noise(q) * 0.65 + c_noise(q * 2.3 + 7.1) * 0.35;
	return cut_y + (n - 0.5) * noise_amp;
}

// Distance from the build line along the surface: x in metres, y in pixels.
// [param d] is the height above or below the line. On a flat deck the line
// crosses at a shallow slope (only the noise tilts it), so the height
// difference is divided by how fast it changes across the surface: the
// seam stays a thin band on decks too instead of lighting the whole face.
// Call before any discard (derivatives).
vec2 front_dist(float d, vec3 p) {
	float ds = max(fwidth(d), 1e-5);
	float slope = clamp(ds / max(length(fwidth(p)), 1e-5), 0.06, 1.0);
	return vec2(abs(d) / slope, abs(d) / ds);
}

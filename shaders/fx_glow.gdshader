// Soft additive glow dot on a 1x1 QuadMesh, turned to face the camera in the
// vertex stage. Used for weld sparks (CPUParticles3D mesh: COLOR and the
// particle scale apply) and the weld glow at the work point. Never smaller
// than min_px on screen; a dot forced bigger dims to match its real size, so
// small sparks do not twinkle as sub-pixel points at RTS zoom.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 glow_color : source_color = vec4(1.0, 0.8, 0.5, 1.0);
uniform float size = 0.2;
uniform float min_px = 2.0;
uniform float energy = 2.0;

varying vec4 v_color;
varying vec2 v_uv;
varying float v_dim;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	float scale = length(MODEL_MATRIX[0].xyz);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float dist = max(length(cam - center), 0.01);
	float world_per_px = 2.0 * dist / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float s = size * scale;
	float s2 = max(s, min_px * world_per_px);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 p = center + (right * VERTEX.x + up * VERTEX.y) * s2;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p, 1.0);
	v_color = COLOR;
	v_uv = VERTEX.xy * 2.0;
	v_dim = (s / s2) * (s / s2);
}

void fragment() {
	float r2 = dot(v_uv, v_uv);
	float a = exp(-r2 * 4.0) * (1.0 - smoothstep(0.7, 1.0, r2));
	vec3 c = glow_color.rgb * v_color.rgb;
	c = mix(c, vec3(1.0), exp(-r2 * 16.0) * 0.6);
	ALBEDO = c * a * v_color.a * energy * v_dim;
}

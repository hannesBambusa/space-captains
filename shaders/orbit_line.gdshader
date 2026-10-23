// Thin anti-aliased orbit circle. The mesh is a strip on a circle (VERTEX on the
// circle, UV.y = -1 / +1 for the two edges); the vertex stage expands it toward
// the camera to a constant pixel width, so it stays crisp at any zoom.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float line_px = 1.6;
// Overall opacity, driven by zoom from solar_system.gd.
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
// Fade out the part of the line close to the camera (metres).
uniform float near_fade = 600.0;
instance uniform vec4 line_color : source_color = vec4(0.5, 0.65, 0.9, 0.35);

varying float v_side;
varying float v_fade;

void vertex() {
	vec3 center = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 dir = normalize((MODEL_MATRIX * vec4(VERTEX.x, 0.0, VERTEX.z, 0.0)).xyz);
	// Circle normal from the model (orbit lines on inclined planes).
	vec3 up = normalize((MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec3 tangent = normalize(cross(up, dir));
	vec3 to_cam = cam - center;
	float dist = length(to_cam);
	float world_per_px = 2.0 * dist / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	vec3 off = normalize(cross(tangent, to_cam / dist));
	float hw = (line_px + 1.5) * 0.5 * world_per_px;
	center += off * UV.y * hw;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(center, 1.0);
	v_side = UV.y;
	v_fade = smoothstep(near_fade * 0.5, near_fade, dist);
}

void fragment() {
	float w = line_px / (line_px + 1.5);
	float a = 1.0 - smoothstep(w * 0.6, 1.0, abs(v_side));
	ALBEDO = line_color.rgb * line_color.a * a * opacity * v_fade;
}

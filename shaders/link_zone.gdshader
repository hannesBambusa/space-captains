// Where a new structure's centre may go while placing: within link reach of
// a structure (discs) or of a corridor (segs), outside every keep-out
// (inner disc radius, corridor band), outside the planet band around the
// station and inside the build zone. Drawn on a flat quad in the station's
// frame (VERTEX.xz = frame-local position). Soft fill plus a thin edge.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

const int MAX_DISCS = 48;
const int MAX_SEGS = 64;

uniform vec4 zone_color : source_color = vec4(0.45, 0.85, 1.0, 1.0);
uniform float fill = 0.02;
uniform float edge = 0.35;
uniform float edge_px = 1.6;
// x, z, inner (keep-out) radius, outer (reach) radius.
uniform vec4 discs[MAX_DISCS];
uniform int disc_count = 0;
// ax, az, bx, bz.
uniform vec4 segs[MAX_SEGS];
uniform int seg_count = 0;
uniform float seg_inner = 40.0;
uniform float seg_reach = 400.0;
// Forbidden band of distances from the station (min, max); zero = none.
uniform vec2 band = vec2(0.0);
uniform float zone_radius = 3000.0;

varying vec2 v_pos;

void vertex() {
	v_pos = VERTEX.xz;
}

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-4), 0.0, 1.0);
	return length(p - a - ab * t);
}

void fragment() {
	vec2 p = v_pos;
	// Signed distances, negative inside.
	float reach = 1e9;
	float block = 1e9;
	for (int i = 0; i < disc_count; i++) {
		float d = length(p - discs[i].xy);
		reach = min(reach, d - discs[i].w);
		block = min(block, d - discs[i].z);
	}
	for (int i = 0; i < seg_count; i++) {
		float d = seg_dist(p, segs[i].xy, segs[i].zw);
		reach = min(reach, d - seg_reach);
		block = min(block, d - seg_inner);
	}
	float r = length(p);
	if (band.y > 0.0) {
		block = min(block, max(r - band.y, band.x - r));
	}
	block = min(block, zone_radius - r);
	float sd = max(reach, -block);
	float px = max(fwidth(sd), 1e-3);
	float inside = 1.0 - smoothstep(-px, px, sd);
	float line = 1.0 - smoothstep(edge_px * 0.5, edge_px * 0.5 + 1.0, abs(sd) / px);
	ALBEDO = zone_color.rgb * (inside * fill + line * edge);
}

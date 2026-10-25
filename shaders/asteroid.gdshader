// Asteroid material for MultiMesh belts and clusters. Carries the glb's PBR inputs (copied
// from its StandardMaterial3D at load time) and tumbles each instance in the
// vertex stage so thousands of asteroids spin for free.
// INSTANCE_CUSTOM: x = axis azimuth (0..1), y = axis z (0..1), z = spin rad/s, w = phase/tint seed.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_albedo_texture = false;
uniform bool use_vertex_color = false;

uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D metallic_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 metallic_channel = vec4(0.0, 0.0, 1.0, 0.0);
uniform bool use_metallic_texture = false;

uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D roughness_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 roughness_channel = vec4(0.0, 1.0, 0.0, 0.0);
uniform bool use_roughness_texture = false;
uniform float specular : hint_range(0.0, 1.0) = 0.5;

uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal_texture = false;
uniform float normal_scale : hint_range(-4.0, 4.0) = 1.0;

uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 1.0;
uniform sampler2D emission_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool use_emission_texture = false;

// Per MultiMeshInstance3D: lets each belt push crystal glow harder.
instance uniform float emission_boost = 1.0;
// Per MultiMeshInstance3D distance LOD: asteroids shrink to nothing between
// lod_fade_start and lod_fade_end (camera distance, metres). 0 = off.
instance uniform float lod_fade_start = 0.0;
instance uniform float lod_fade_end = 0.0;
// Per MultiMeshInstance3D cluster thinning: instances whose seed
// (INSTANCE_CUSTOM.w) is below thin_level shrink away (0 = all shown).
instance uniform float thin_level = 0.0;
// Slight per-instance brightness variation so repeated meshes read as different rocks.
uniform float tint_variation : hint_range(0.0, 0.5) = 0.18;

varying float v_tint;

mat3 axis_angle(vec3 axis, float a) {
	float s = sin(a);
	float c = cos(a);
	float t = 1.0 - c;
	return mat3(
			vec3(t * axis.x * axis.x + c, t * axis.x * axis.y + s * axis.z, t * axis.x * axis.z - s * axis.y),
			vec3(t * axis.x * axis.y - s * axis.z, t * axis.y * axis.y + c, t * axis.y * axis.z + s * axis.x),
			vec3(t * axis.x * axis.z + s * axis.y, t * axis.y * axis.z - s * axis.x, t * axis.z * axis.z + c));
}

void vertex() {
	float az = INSTANCE_CUSTOM.x * 6.2831853;
	float z = INSTANCE_CUSTOM.y * 2.0 - 1.0;
	float rxy = sqrt(max(1.0 - z * z, 0.0));
	vec3 axis = vec3(rxy * cos(az), z, rxy * sin(az));
	mat3 rot = axis_angle(axis, TIME * INSTANCE_CUSTOM.z + INSTANCE_CUSTOM.w * 6.2831853);
	float lod = 1.0;
	if (lod_fade_end > 0.0) {
		float d = distance(MODEL_MATRIX[3].xyz, INV_VIEW_MATRIX[3].xyz);
		lod = 1.0 - smoothstep(lod_fade_start, lod_fade_end, d);
	}
	if (thin_level > 0.0) {
		lod *= smoothstep(thin_level, thin_level + 0.04, INSTANCE_CUSTOM.w);
	}
	VERTEX = rot * VERTEX * lod;
	NORMAL = rot * NORMAL;
	TANGENT = rot * TANGENT;
	BINORMAL = rot * BINORMAL;
	v_tint = 1.0 + (fract(INSTANCE_CUSTOM.w * 13.37) * 2.0 - 1.0) * tint_variation;
}

void fragment() {
	vec4 alb = albedo_color;
	if (use_albedo_texture) {
		alb *= texture(albedo_texture, UV);
	}
	if (use_vertex_color) {
		alb *= COLOR;
	}
	ALBEDO = alb.rgb * v_tint;

	float m = metallic;
	if (use_metallic_texture) {
		m *= dot(texture(metallic_texture, UV), metallic_channel);
	}
	METALLIC = m;

	float r = roughness;
	if (use_roughness_texture) {
		r *= dot(texture(roughness_texture, UV), roughness_channel);
	}
	ROUGHNESS = r;
	SPECULAR = specular;

	if (use_normal_texture) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}

	vec3 e = emission_color * emission_energy;
	if (use_emission_texture) {
		e *= texture(emission_texture, UV).rgb;
	}
	EMISSION = e * emission_boost;
}

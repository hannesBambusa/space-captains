shader_type spatial;
// Scrap field chunks (one MultiMesh). Each instance tumbles about its own
// axis and catches the light now and then (a short emissive glint). [fade]
// shrinks the chunks away at the end of the field's life; [hot] makes fresh
// wrecks glow.

uniform vec3 base_color : source_color = vec3(0.62, 0.6, 0.57);
uniform float fade = 1.0;
uniform float hot = 0.0;
uniform float glint_strength = 4.0;

varying float v_glint;
varying float v_hot;

mat3 axis_rot(vec3 axis, float a) {
	float s = sin(a);
	float c = cos(a);
	float oc = 1.0 - c;
	return mat3(
		vec3(oc * axis.x * axis.x + c, oc * axis.x * axis.y + axis.z * s, oc * axis.z * axis.x - axis.y * s),
		vec3(oc * axis.x * axis.y - axis.z * s, oc * axis.y * axis.y + c, oc * axis.y * axis.z + axis.x * s),
		vec3(oc * axis.z * axis.x + axis.y * s, oc * axis.y * axis.z - axis.x * s, oc * axis.z * axis.z + c));
}

void vertex() {
	float id = float(INSTANCE_ID);
	vec3 axis = normalize(vec3(fract(id * 0.731) - 0.5, fract(id * 0.377) - 0.5 + 0.01, fract(id * 0.519) - 0.5));
	float a = TIME * (0.15 + fract(id * 0.613) * 0.5) + id * 1.7;
	mat3 r = axis_rot(axis, a);
	VERTEX = r * VERTEX * fade;
	NORMAL = r * NORMAL;
	float w = TIME * (1.2 + fract(id * 0.271) * 2.2) + id * 3.1;
	v_glint = pow(max(sin(w), 0.0), 16.0);
	v_hot = hot * fract(id * 0.913);
}

void fragment() {
	ALBEDO = base_color * COLOR.rgb;
	METALLIC = 0.75;
	ROUGHNESS = 0.42;
	EMISSION = vec3(1.0, 0.88, 0.7) * v_glint * glint_strength + vec3(1.0, 0.38, 0.1) * v_hot * 3.0;
}

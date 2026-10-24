class_name Star
extends Node3D
## The system's star at the origin: emissive sphere (shaders/sun.gdshader), a
## camera-facing corona (shaders/sun_corona.gdshader) that the glow pass blooms,
## and the OmniLight3D that lights everything on layer 1 from the centre.
## Layer 2 (station, gates) is lit by LocalSunLight instead, which casts shadows.

const SUN_SHADER: Shader = preload("res://shaders/sun.gdshader")
const CORONA_SHADER: Shader = preload("res://shaders/sun_corona.gdshader")
const CORONA_CORE_FRACTION := 0.22

## Distance falloff exponent of the star light (0 = none).
@export var light_falloff: float = 0.18
## Distance at which the light has exactly the configured energy.
@export var light_reference_distance: float = 12000.0
## Brightness of the star's disc and of its corona glow.
@export var disc_intensity: float = 3.2
@export var corona_intensity: float = 0.35

var radius: float = 1500.0
var color: Color = Color.WHITE
var light: OmniLight3D


func build(star_radius: float, star_color: Color, light_energy: float, light_range: float) -> void:
	radius = star_radius
	color = star_color
	set_meta(&"focus_radius", radius)
	set_meta(&"focus_distance", radius * 9.0)
	add_to_group(RTSCamera.FOCUS_GROUP)

	var sphere := MeshInstance3D.new()
	sphere.name = "Sphere"
	sphere.mesh = MeshUtil.unit_sphere(96)
	sphere.scale = Vector3.ONE * radius
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sm := ShaderMaterial.new()
	sm.shader = SUN_SHADER
	sm.set_shader_parameter("core_color", star_color.lerp(Color.WHITE, 0.55))
	sm.set_shader_parameter("limb_color", star_color.lerp(Color(1.0, 0.4, 0.1), 0.45))
	sm.set_shader_parameter("intensity", disc_intensity)
	sm.set_shader_parameter("granulation", 0.16)
	sphere.material_override = sm
	add_child(sphere)

	var corona := MeshInstance3D.new()
	corona.name = "Corona"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 2.0 / CORONA_CORE_FRACTION
	corona.mesh = quad
	corona.scale = Vector3.ONE * radius
	corona.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The quad turns to face the camera in the shader, so never cull it.
	corona.extra_cull_margin = radius * 2.0 / CORONA_CORE_FRACTION
	var cm := ShaderMaterial.new()
	cm.shader = CORONA_SHADER
	cm.render_priority = 1
	cm.set_shader_parameter("core_fraction", CORONA_CORE_FRACTION)
	cm.set_shader_parameter("corona_color", star_color.lerp(Color.WHITE, 0.65))
	cm.set_shader_parameter("outer_color", star_color.lerp(Color(1.0, 0.72, 0.45), 0.4))
	cm.set_shader_parameter("intensity", corona_intensity)
	cm.set_shader_parameter("falloff", 2.8)
	cm.set_shader_parameter("ray_strength", 0.16)
	corona.material_override = cm
	add_child(corona)

	light = OmniLight3D.new()
	light.name = "StarLight"
	light.light_color = star_color.lerp(Color.WHITE, 0.35)
	light.omni_range = light_range
	light.omni_attenuation = light_falloff
	light.light_energy = light_energy * pow(light_reference_distance, light_falloff)
	light.light_specular = 0.7
	light.shadow_enabled = false
	light.light_cull_mask = 0xFFFFF & ~2
	add_child(light)

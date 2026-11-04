class_name Star
extends Node3D
## The system's star at the origin: a burning plasma sphere (shaders/sun.gdshader:
## flows, granulation, filaments, sunspots, in the star's colour), a
## camera-facing corona (shaders/sun_corona.gdshader) that the glow pass blooms,
## and the OmniLight3D that lights everything on layer 1 from the centre.
## Layer 2 (station, gates) is lit by LocalSunLight instead, which casts shadows.

const SUN_SHADER: Shader = preload("res://shaders/sun.gdshader")
const CORONA_SHADER: Shader = preload("res://shaders/sun_corona.gdshader")
## The disc's share of the corona quad: the halo reaches about 3 sun radii
## (the sun is big now, so the glow stays off the inner planets).
const CORONA_CORE_FRACTION := 0.3

## Distance falloff exponent of the star light (0 = none).
@export var light_falloff: float = 0.18
## Distance at which the light has exactly the configured energy.
@export var light_reference_distance: float = 12000.0
## Brightness of the star's disc and of its corona glow.
@export var disc_intensity: float = 1.25
@export var corona_intensity: float = 0.3

var radius: float = 600.0
var color: Color = Color.WHITE
var light: OmniLight3D


## The colour the surface burns in: pale temperature colours (home's 5400 K
## is nearly white) get saturated, or the ramp from dark to white-hot runs
## grey. The light keeps the true colour.
static func surface_color(c: Color) -> Color:
	var out := Color(c, 1.0)
	if out.s < 0.6:
		out = Color.from_hsv(out.h, 0.62, 1.0)
	return out


func build(star_radius: float, star_color: Color, light_energy: float, light_range: float, light_color: Color = Color(0, 0, 0, 0)) -> void:
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
	# One look per star: the patterns are offset by its size and colour.
	var look_seed := fposmod(star_radius * 0.057 + star_color.h * 97.0, 1000.0)
	sm.set_shader_parameter("star_color", surface_color(star_color))
	sm.set_shader_parameter("intensity", disc_intensity)
	sm.set_shader_parameter("seed", look_seed)
	sm.set_shader_parameter("spots", 0.5)
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
	cm.set_shader_parameter("corona_color", star_color.lerp(Color.WHITE, 0.55))
	cm.set_shader_parameter("outer_color", star_color)
	cm.set_shader_parameter("seed", look_seed)
	cm.set_shader_parameter("intensity", corona_intensity)
	cm.set_shader_parameter("falloff", 2.8)
	cm.set_shader_parameter("ray_strength", 0.35)
	corona.material_override = cm
	add_child(corona)

	light = OmniLight3D.new()
	light.name = "StarLight"
	light.light_color = light_color if light_color.a > 0.0 else star_color.lerp(Color.WHITE, 0.35)
	light.omni_range = light_range
	light.omni_attenuation = light_falloff
	light.light_energy = light_energy * pow(light_reference_distance, light_falloff)
	light.light_specular = 0.7
	light.shadow_enabled = false
	light.light_cull_mask = 0xFFFFF & ~2
	add_child(light)

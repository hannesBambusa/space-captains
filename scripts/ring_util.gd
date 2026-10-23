class_name RingUtil
extends RefCounted
## Thin constant-pixel-width circles on the play plane (shaders/orbit_line.gdshader),
## for zone edges, footprints and selection rings.

const LINE_SHADER: Shader = preload("res://shaders/orbit_line.gdshader")


static func make_ring(radius: float, color: Color, line_px: float = 1.6, segments: int = 128) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Ring"
	mi.mesh = MeshUtil.make_orbit_strip(radius, segments)
	var m := ShaderMaterial.new()
	m.shader = LINE_SHADER
	m.set_shader_parameter("line_px", line_px)
	m.set_shader_parameter("opacity", 1.0)
	m.set_shader_parameter("near_fade", 1.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("line_color", color)
	return mi


static func set_color(ring: MeshInstance3D, color: Color) -> void:
	ring.set_instance_shader_parameter("line_color", color)

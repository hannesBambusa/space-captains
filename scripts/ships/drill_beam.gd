class_name DrillBeam
extends Node3D
## Mining laser: a thin emissive beam from the ship's nose to the asteroid,
## a hot spot at the contact point and a spray of sparks. World space
## (top_level), aimed every frame by the ship. Sparks freeze while paused.

@export var beam_color: Color = Color(0.55, 0.9, 1.0)
@export var spark_color: Color = Color(1.0, 0.62, 0.25)
@export var beam_radius: float = 0.22

var _beam: MeshInstance3D
var _core: MeshInstance3D
var _hot: MeshInstance3D
var _sparks: GPUParticles3D
var _on := false


func _ready() -> void:
	top_level = true
	visible = false
	_beam = _make_cylinder(beam_radius * 2.0, _additive(beam_color, 0.9, 0.22))
	_core = _make_cylinder(beam_radius * 0.55, _additive(beam_color.lerp(Color.WHITE, 0.5), 2.2, 0.9))
	var hot_mesh := SphereMesh.new()
	hot_mesh.radius = 0.8
	hot_mesh.height = 1.6
	hot_mesh.radial_segments = 12
	hot_mesh.rings = 6
	_hot = MeshInstance3D.new()
	_hot.name = "HotSpot"
	_hot.mesh = hot_mesh
	_hot.material_override = _additive(spark_color.lerp(Color.WHITE, 0.3), 2.2, 0.7)
	_hot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_hot)
	_sparks = _make_sparks()
	_hot.add_child(_sparks)


## Shows the beam from [param from] to [param to] (world).
func aim(from: Vector3, to: Vector3) -> void:
	var d := to - from
	var length := d.length()
	if length < 0.5:
		set_active(false)
		return
	set_active(true)
	global_position = from
	var up := Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT
	look_at(to, up)
	var flicker := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.031)
	for m in [_beam, _core]:
		var mi := m as MeshInstance3D
		mi.scale = Vector3(flicker, length, flicker)
		mi.position = Vector3(0.0, 0.0, -length * 0.5)
	_hot.position = Vector3(0.0, 0.0, -length)
	_hot.scale = Vector3.ONE * (0.8 + 0.4 * flicker)
	_sparks.speed_scale = 0.0 if SimClock.paused else clampf(SimClock.speed, 0.0, 4.0)


func set_active(on: bool) -> void:
	if _on == on:
		return
	_on = on
	visible = on
	_sparks.emitting = on


func _make_cylinder(radius: float, mat: Material) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 1.0
	cyl.radial_segments = 8
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The cylinder runs along its local Y; turned 90 deg about X it lies along Z.
	# Scale is applied before the rotation, so scale.y sets the beam length.
	mi.rotation.x = PI * 0.5
	add_child(mi)
	return mi


func _additive(color: Color, energy: float, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color * energy, alpha)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.disable_receive_shadows = true
	return m


func _make_sparks() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Sparks"
	p.amount = 28
	p.lifetime = 0.6
	p.emitting = false
	# Local: the rock (and ship) drift with the turning belt; sparks stay with them.
	p.local_coords = true
	p.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 0.0, 1.0)
	pm.spread = 55.0
	pm.initial_velocity_min = 6.0
	pm.initial_velocity_max = 16.0
	pm.gravity = Vector3.ZERO
	pm.damping_min = 4.0
	pm.damping_max = 8.0
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(spark_color.lerp(Color.WHITE, 0.5), 1.0))
	ramp.set_color(1, Color(spark_color, 0.0))
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	pm.color_ramp = tex
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.35, 0.35)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.vertex_color_use_as_albedo = true
	qm.albedo_color = Color(2.5, 1.8, 1.2, 1.0)
	quad.material = qm
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

class_name ShieldRipple
extends Node3D
## Ripples on ship shield bubbles (shaders/vfx_shield_hit.gdshader): a
## pooled sphere snaps around the struck ship for [constant LIFE] visual
## seconds and follows it. A second hit on the same ship restarts its
## ripple from the new point. Shared mesh and material, instance uniforms.

const LIFE := 0.45
const POOL := 10
const SHADER := preload("res://shaders/vfx_shield_hit.gdshader")
## Bubble radius per metre of hit radius.
const BUBBLE := 1.35

var _mesh: SphereMesh
var _mat: ShaderMaterial
var _items: Array[Dictionary] = []


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_mesh = SphereMesh.new()
	_mesh.radius = 1.0
	_mesh.height = 2.0
	_mesh.radial_segments = 24
	_mesh.rings = 12
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	for i in POOL:
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = Ship.RENDER_LAYER
		mi.visible = false
		mi.top_level = true
		add_child(mi)
		_items.append({"mi": mi, "target": null, "t": LIFE, "r": 1.0})
	set_process(false)


func ripple(target: Node3D, at: Vector3, radius: float) -> void:
	var pick: Dictionary = {}
	var oldest := -1.0
	for it in _items:
		var tg: Node3D = (it["target"] as WeakRef).get_ref() if it["target"] else null
		if tg == target:
			pick = it
			break
		if float(it["t"]) > oldest:
			oldest = float(it["t"])
			pick = it
	var mi := pick["mi"] as MeshInstance3D
	var r := maxf(radius * BUBBLE, 3.0)
	pick["target"] = weakref(target)
	pick["t"] = 0.0
	pick["r"] = r
	var hit := (at - target.global_position)
	mi.set_instance_shader_parameter(&"sh_hit", hit.normalized() if hit.length_squared() > 1e-4 else Vector3.UP)
	mi.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * r), target.global_position)
	mi.visible = true
	_apply(pick)
	set_process(true)


func _process(delta: float) -> void:
	var dt := Vfx.vis_dt(delta)
	var any := false
	for it in _items:
		if float(it["t"]) >= LIFE:
			continue
		it["t"] = float(it["t"]) + dt
		var tg: Node3D = (it["target"] as WeakRef).get_ref() if it["target"] else null
		var mi := it["mi"] as MeshInstance3D
		if float(it["t"]) >= LIFE or not is_instance_valid(tg):
			it["t"] = LIFE
			mi.visible = false
			continue
		any = true
		mi.global_position = tg.global_position
		_apply(it)
	if not any:
		set_process(false)


func _apply(it: Dictionary) -> void:
	var mi := it["mi"] as MeshInstance3D
	mi.set_instance_shader_parameter(&"sh_k", clampf(float(it["t"]) / LIFE, 0.0, 1.0))

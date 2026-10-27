class_name FlashPool
extends Node3D
## Every short flash of one system (muzzle flashes, hit glints, explosion
## cores, missile launch flares) in one MultiMesh: one draw call, no nodes
## per flash. A flash rises in a frame and falls off fast; it may run forward
## along a direction (muzzle). World space (top_level). Visual clock (Vfx).
## Full pool: the oldest flash is dropped.

const CAPACITY := 256
const SHADER := preload("res://shaders/vfx_flash.gdshader")

var _mm: MultiMesh
# Parallel arrays, one entry per live flash.
var _pos := PackedVector3Array()
var _dir := PackedVector3Array()
var _radius := PackedFloat32Array()
var _grow := PackedFloat32Array()
var _life := PackedFloat32Array()
var _age := PackedFloat32Array()
var _core := PackedFloat32Array()
var _colors := PackedColorArray()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	quad.material = mat
	_mm.mesh = quad
	_mm.instance_count = CAPACITY
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Flashes"
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-60000.0, -20000.0, -60000.0), Vector3(120000.0, 40000.0, 120000.0))
	mmi.layers = Ship.RENDER_LAYER
	add_child(mmi)


## A flash at [param pos]: [param radius] metres, growing to
## radius x [param grow] over its [param life] (visual seconds), running
## [param stretch] metres along [param dir] (zero: round). [param core] is
## the white-hot share of the centre.
func add(pos: Vector3, radius: float, color: Color, life: float, grow: float = 1.3, dir: Vector3 = Vector3.ZERO, stretch: float = 0.0, core: float = 0.6) -> void:
	if _pos.size() >= CAPACITY:
		_remove(0)
	_pos.append(pos)
	_dir.append(dir.normalized() * stretch if stretch > 0.0 and dir.length_squared() > 1e-8 else Vector3.ZERO)
	_radius.append(radius)
	_grow.append(grow)
	_life.append(maxf(life, 0.01))
	_age.append(0.0)
	_core.append(core)
	_colors.append(color)


func count() -> int:
	return _pos.size()


func _process(delta: float) -> void:
	var dt := Vfx.vis_dt(delta)
	var i := _pos.size() - 1
	while i >= 0:
		_age[i] += dt
		if _age[i] >= _life[i]:
			_remove(i)
		i -= 1
	var n := _pos.size()
	_mm.visible_instance_count = n
	for j in n:
		var k := _age[j] / _life[j]
		# Up in the first 8 % of the life, then a fast fall.
		var e := smoothstep(0.0, 0.08, k) * pow(1.0 - k, 2.0)
		var r := _radius[j] * lerpf(0.75, _grow[j], sqrt(k))
		_mm.set_instance_transform(j, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * r), _pos[j]))
		var c := _colors[j]
		_mm.set_instance_color(j, Color(c.r, c.g, c.b, c.a * e))
		var d := _dir[j] * lerpf(0.6, 1.0, sqrt(k))
		_mm.set_instance_custom_data(j, Color(d.x, d.y, d.z, _core[j]))


func _remove(i: int) -> void:
	_pos.remove_at(i)
	_dir.remove_at(i)
	_radius.remove_at(i)
	_grow.remove_at(i)
	_life.remove_at(i)
	_age.remove_at(i)
	_core.remove_at(i)
	_colors.remove_at(i)

class_name ProjectilePool
extends Node3D
## Every cannon tracer in flight, drawn with one MultiMesh (one draw call).
## Tracers fly straight from the muzzle to their aim point on sim time; a
## tracer that rolled a hit applies its damage to the target on arrival (if
## the target is still alive) and leaves a spark. Misses fly on and fade.
## Fixed capacity: when full, the oldest tracer is reused.
## Station shield: a hostile tracer that would enter an up bubble from
## outside hits its surface instead (StationShield.intercept): a hit's
## damage goes to the bubble, a miss only ripples it. Friendly tracers and
## hostile ones fired from inside pass.

const SPEED := 950.0
const CAPACITY := 600
const TRACER_LENGTH := 26.0
const TRACER_WIDTH := 1.3
## A miss keeps flying this far past its aim point before it vanishes.
const MISS_OVERSHOOT := 260.0

var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
# Parallel arrays, one entry per live tracer.
var _pos := PackedVector3Array()
var _dir := PackedVector3Array()
var _left := PackedFloat32Array()
var _flown := PackedFloat32Array()
var _damage := PackedFloat32Array()
var _hits: Array[bool] = []
var _targets: Array[WeakRef] = []
var _attackers: Array[WeakRef] = []
var _colors: Array[Color] = []
var _hostile: Array[bool] = []
var hits_applied: int = 0
## Tracers stopped by a station shield.
var shield_hits: int = 0
var _world: CombatWorld


func _ready() -> void:
	add_to_group(SimStepper.GROUP)
	_world = get_parent() as CombatWorld
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(2.4, 2.4, 2.4, 1.0)
	mat.disable_receive_shadows = true
	box.material = mat
	_mm.mesh = box
	_mm.instance_count = CAPACITY
	_mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Tracers"
	_mmi.multimesh = _mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.layers = 2
	add_child(_mmi)
	top_level = true
	global_transform = Transform3D.IDENTITY


func _process(delta: float) -> void:
	if not SimClock.paused:
		sim_step(delta * SimClock.speed)
	_draw_tracers()


func count() -> int:
	return _pos.size()


func fire(from: Vector3, aim: Vector3, target: Node3D, damage: float, hits: bool, attacker: Node3D, color: Color) -> void:
	var d := aim - from
	var length := d.length()
	if length < 1.0:
		return
	if _pos.size() >= CAPACITY:
		_remove(0)
	_pos.append(from)
	_dir.append(d / length)
	_left.append(length if hits else length + MISS_OVERSHOOT)
	_flown.append(0.0)
	_damage.append(damage)
	_hits.append(hits)
	_targets.append(weakref(target))
	_attackers.append(weakref(attacker))
	_colors.append(color)
	_hostile.append(is_instance_valid(attacker) and attacker.has_method(&"get_faction") and int(attacker.call(&"get_faction")) != Combat.Faction.PLAYER)


func sim_step(dt: float) -> void:
	if dt <= 0.0 or _pos.is_empty():
		return
	var step := SPEED * dt
	var shields: Array[StationShield] = []
	if _world:
		shields = _world.shields
	var i := _pos.size() - 1
	while i >= 0:
		var s := minf(step, _left[i])
		if _hostile[i] and not shields.is_empty() and _hit_shield(i, shields, s):
			_remove(i)
			i -= 1
			continue
		_pos[i] += _dir[i] * s
		_left[i] -= s
		_flown[i] += s
		if _left[i] <= 0.01:
			if _hits[i]:
				_apply_hit(i)
			_remove(i)
		i -= 1


func _apply_hit(i: int) -> void:
	var target := _targets[i].get_ref() as Node3D
	if not Combat.is_live(target):
		return
	var attacker := _attackers[i].get_ref() as Node3D
	var at := target.global_position - _dir[i] * float(target.call(&"get_hit_radius")) * 0.6
	at.y = _pos[i].y
	target.call(&"take_hit", _damage[i], attacker, at)
	hits_applied += 1
	var fx := CombatWorld.fx_of(get_tree())
	if fx:
		fx.spark(at, _colors[i])


## True when tracer [param i] runs into a shield within [param s] metres
## (the bubble takes the hit there).
func _hit_shield(i: int, shields: Array[StationShield], s: float) -> bool:
	var a := _pos[i]
	var b := a + _dir[i] * s
	for sh in shields:
		if not is_instance_valid(sh):
			continue
		var t := sh.intercept(a, b)
		if t < 0.0:
			continue
		var at := a.lerp(b, t)
		sh.absorb(_damage[i] if _hits[i] else 0.0, _attackers[i].get_ref() as Node3D, at)
		shield_hits += 1
		var fx := CombatWorld.fx_of(get_tree())
		if fx:
			fx.spark(at, _colors[i])
		return true
	return false


func _remove(i: int) -> void:
	_pos.remove_at(i)
	_dir.remove_at(i)
	_left.remove_at(i)
	_flown.remove_at(i)
	_damage.remove_at(i)
	_hits.remove_at(i)
	_targets.remove_at(i)
	_attackers.remove_at(i)
	_colors.remove_at(i)
	_hostile.remove_at(i)


func _draw_tracers() -> void:
	var n := _pos.size()
	_mm.visible_instance_count = n
	for i in n:
		var d := _dir[i]
		var length := minf(TRACER_LENGTH, _flown[i] + 2.0)
		var z := -d
		var x := Vector3.UP.cross(z)
		if x.length_squared() < 1e-6:
			x = Vector3.RIGHT
		x = x.normalized()
		var y := z.cross(x)
		var b := Basis(x * TRACER_WIDTH, y * TRACER_WIDTH * 0.6, z * length)
		_mm.set_instance_transform(i, Transform3D(b, _pos[i] - d * length * 0.5))
		var fade := 1.0
		if not _hits[i] and _left[i] < MISS_OVERSHOOT:
			fade = clampf(_left[i] / MISS_OVERSHOOT, 0.0, 1.0)
		_mm.set_instance_color(i, Color(_colors[i], fade))

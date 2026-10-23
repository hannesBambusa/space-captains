class_name ShipWeapon
extends RefCounted
## Cannons of one ship. Fires alternately from the model's muzzle empties
## (muzzle_l, muzzle_r) at [member ShipStats.fire_rate] shots per second when
## the target is in range and roughly ahead. Each shot rolls to hit
## (accuracy, range, target dodge) and becomes a tracer in the
## ProjectilePool that deals its damage when it arrives.

const MUZZLE_NAMES: PackedStringArray = ["muzzle_l", "muzzle_r"]
## Shots are only fired at targets within this angle of the nose, degrees.
const FIRE_CONE_DEG := 14.0

var ship: Node3D
var stats: ShipStats
var color: Color
var muzzles: Array[Node3D] = []
var shots_fired: int = 0

var _cooldown: float = 0.0
var _next_muzzle: int = 0
var _rng := RandomNumberGenerator.new()


func _init(owner_ship: Node3D, ship_stats: ShipStats, model: Node3D, tracer_color: Color) -> void:
	ship = owner_ship
	stats = ship_stats
	color = tracer_color
	_rng.randomize()
	for n in MUZZLE_NAMES:
		var m := model.find_child(n, true, false) as Node3D if model else null
		if m:
			muzzles.append(m)


func step(dt: float) -> void:
	_cooldown = maxf(_cooldown - dt, 0.0)


func in_range(target: Node3D) -> bool:
	return Combat.flat_distance(ship.global_position, target.global_position) <= stats.weapon_range + float(target.call(&"get_hit_radius"))


## True when the nose points at [param target] within the fire cone.
func facing(target: Node3D, cone_deg: float = FIRE_CONE_DEG) -> bool:
	var to := target.global_position - ship.global_position
	to.y = 0.0
	if to.length() < 1.0:
		return true
	var fwd := ship.global_basis * Vector3.FORWARD
	fwd.y = 0.0
	return fwd.normalized().dot(to.normalized()) >= cos(deg_to_rad(cone_deg))


## Fires one shot when ready, in range and facing. True when it fired.
func try_fire(target: Node3D) -> bool:
	if not stats.has_weapon() or _cooldown > 0.0 or not Combat.is_live_target(target):
		return false
	if not in_range(target) or not facing(target):
		return false
	var pool := CombatWorld.projectiles_of(ship.get_tree())
	if pool == null:
		return false
	_cooldown = 1.0 / stats.fire_rate
	var from := _muzzle_position()
	var tpos := target.global_position
	var dist := from.distance_to(tpos)
	var flight := dist / ProjectilePool.SPEED
	var aim := tpos + (target.call(&"get_aim_velocity") as Vector3) * flight
	var falloff := clampf(1.0 - 0.35 * (dist / maxf(stats.weapon_range, 1.0)), 0.5, 1.0)
	var hit_chance := stats.accuracy * falloff * (1.0 - float(target.call(&"get_dodge")))
	var hits := _rng.randf() < hit_chance
	var radius := float(target.call(&"get_hit_radius"))
	if hits:
		aim += Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.4, 0.4), _rng.randf_range(-1.0, 1.0)) * radius * 0.35
	else:
		var side := (aim - from).cross(Vector3.UP).normalized()
		aim += side * _rng.randf_range(radius * 1.2, radius * 2.5) * (1.0 if _rng.randf() < 0.5 else -1.0)
		aim += (aim - from).normalized() * _rng.randf_range(20.0, 120.0)
	pool.fire(from, aim, target, stats.weapon_damage, hits, ship, color)
	shots_fired += 1
	return true


func _muzzle_position() -> Vector3:
	if muzzles.is_empty():
		return ship.global_transform * Vector3(0.0, 0.0, -8.0)
	_next_muzzle = (_next_muzzle + 1) % muzzles.size()
	return muzzles[_next_muzzle].global_position

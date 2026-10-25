class_name DefenseTurret
extends DefenseStructure
## Service node of a Defense Turret: a standalone twin-barrel point-defence
## mount anywhere in the build zone (BuildingDef.standalone).
## Defends the station on its own, so the colony is not helpless while every
## mercenary is out on a job.
##
## Targeting ([constant RETARGET_INTERVAL]): hostiles within
## [member weapon_range]; raiders and ships attacking the station, its
## structures or its ships first, then the nearest; it sticks to its target.
## Aim: leads the target (tracer flight time), turns turret_yaw and
## turret_pitch toward the lead point at [member yaw_speed_deg] /
## [member pitch_speed_deg]; pitch may not drop below
## [member pitch_min_port_deg] over the -Z side (the barrels would clip the
## port block), [member pitch_min_deg] elsewhere. Fires alternately from
## muzzle_l / muzzle_r once lined up, through the ProjectilePool (friendly
## tracers pass out through the station shield). About two thirds of a stock
## mercenary's damage per second (24 vs about 35), with more range.
## Hold fire ([member fire_at_will] off): it still tracks, but does not shoot.
## Status light (turret_status_light): green idle, amber tracking, red firing.

enum Mode { IDLE, TRACKING, FIRING }

const MODE_NAMES: PackedStringArray = ["Idle", "Tracking", "Firing"]
const MUZZLE_NAMES: PackedStringArray = ["muzzle_l", "muzzle_r"]
const RETARGET_INTERVAL := 0.5
const IDLE_COLOR := Color(0.3, 1.0, 0.45)
const TRACK_COLOR := Color(1.0, 0.68, 0.18)
const FIRE_COLOR := Color(1.0, 0.18, 0.12)
## Seconds the light stays red after a shot.
const FIRE_HOLD := 0.6

@export var weapon_range: float = 900.0
@export var weapon_damage: float = 13.0
## Shots per sim second (both barrels together).
@export var fire_rate: float = 2.6
@export var accuracy: float = 0.72
@export var yaw_speed_deg: float = 95.0
@export var pitch_speed_deg: float = 60.0
@export var pitch_min_deg: float = -25.0
@export var pitch_min_port_deg: float = -8.0
@export var pitch_max_deg: float = 70.0
## Lined up within this angle (degrees) to fire.
@export var fire_tolerance_deg: float = 3.0
## Idle sweep speed, degrees per sim second.
@export var idle_sweep_deg: float = 7.0

var fire_at_will := true
var target: Node3D
var mode: Mode = Mode.IDLE
var kills: int = 0
var shots_fired: int = 0

var _yaw_node: Node3D
var _pitch_node: Node3D
var _muzzles: Array[Node3D] = []
var _light_mat: StandardMaterial3D
var _light_base := 1.0
var _yaw := 0.0
var _pitch := 0.0
var _cooldown := 0.0
var _retarget := 0.0
var _since_shot := INF
var _next_muzzle := 0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	max_hull = 650.0
	max_shields = 150.0
	shield_regen = 8.0
	hit_radius = 11.0
	aim_height = 14.0
	scrap_amount = 50
	explosion_size = 16.0


func _on_setup() -> void:
	_rng.randomize()
	var model := building.get_model()
	_yaw_node = model.find_child("turret_yaw", true, false) as Node3D if model else null
	_pitch_node = model.find_child("turret_pitch", true, false) as Node3D if model else null
	for n in MUZZLE_NAMES:
		var m := model.find_child(n, true, false) as Node3D if model else null
		if m:
			_muzzles.append(m)
	_light_mat = _own_material("turret_status_light")
	if _light_mat:
		_light_base = maxf(_light_mat.emission_energy_multiplier, 1.5)
	_yaw = _rng.randf_range(-PI, PI)
	_apply_pose()
	var world := CombatWorld.of(building.get_tree())
	if world:
		world.combatant_destroyed.connect(_on_combatant_destroyed)


func get_status_text() -> String:
	if dead:
		return "Destroyed"
	var text := "Holding fire" if not fire_at_will else MODE_NAMES[mode]
	if Combat.is_live_target(target):
		text += ": %s" % String(target.call(&"get_display_name"))
	return text + (", repairing" if repairing else "")


func set_fire_at_will(on: bool) -> void:
	if fire_at_will == on:
		return
	fire_at_will = on
	changed.emit()


## Current yaw / pitch of the mount, radians (model space).
func get_yaw() -> float:
	return _yaw


func get_pitch() -> float:
	return _pitch


func _step(dt: float) -> void:
	_cooldown = maxf(_cooldown - dt, 0.0)
	_since_shot += dt
	if not is_active():
		mode = Mode.IDLE
		return
	_retarget -= dt
	if _retarget <= 0.0 or not Combat.is_live_target(target):
		_retarget = RETARGET_INTERVAL
		_pick_target()
	if not Combat.is_live_target(target):
		target = null
		mode = Mode.IDLE
		_yaw = wrapf(_yaw + deg_to_rad(idle_sweep_deg) * dt, -PI, PI)
		_pitch = move_toward(_pitch, deg_to_rad(4.0), deg_to_rad(pitch_speed_deg) * 0.3 * dt)
		_apply_pose()
		return
	var lead := _lead_point(target)
	var want := _angles_to(lead)
	_yaw = wrapf(rotate_toward(_yaw, want.x, deg_to_rad(yaw_speed_deg) * dt), -PI, PI)
	_pitch = move_toward(_pitch, want.y, deg_to_rad(pitch_speed_deg) * dt)
	_apply_pose()
	var lined_up := absf(angle_difference(_yaw, want.x)) < deg_to_rad(fire_tolerance_deg) and absf(_pitch - want.y) < deg_to_rad(fire_tolerance_deg * 1.5)
	if fire_at_will and lined_up and _cooldown <= 0.0 and _in_range(target):
		_fire(target, lead)
	mode = Mode.FIRING if _since_shot < FIRE_HOLD else Mode.TRACKING


func _in_range(t: Node3D) -> bool:
	return global_position.distance_to(t.global_position) <= weapon_range + float(t.call(&"get_hit_radius"))


## Best hostile in range: raiders and anything attacking the colony first,
## then the nearest; the current target is kept unless something is clearly
## more urgent.
func _pick_target() -> void:
	var best: Node3D = null
	var best_score := INF
	for h in Combat.hostiles_near(get_tree(), global_position, weapon_range + 60.0, Combat.Faction.PLAYER):
		var score := Combat.flat_distance(global_position, h.global_position)
		var sc := h as ScavengerShip
		if sc:
			if sc.is_raider:
				score -= 200.0
			if sc.ai and Combat.is_live(sc.ai.target) and int(sc.ai.target.call(&"get_faction")) == Combat.Faction.PLAYER:
				score -= 350.0
		if h == target:
			score -= 250.0
		if score < best_score:
			best_score = score
			best = h
	if best != target:
		target = best
		changed.emit()


## Where to aim so a tracer from the barrels meets [param t].
func _lead_point(t: Node3D) -> Vector3:
	var from := _pitch_node.global_position if _pitch_node else global_position
	var tp := t.global_position
	var v := t.call(&"get_aim_velocity") as Vector3 - get_aim_velocity()
	var p := tp
	for i in 2:
		var flight := from.distance_to(p) / ProjectilePool.SPEED
		p = tp + v * flight
	return p


## (yaw, pitch) in the mount's space that point the barrels at [param world_pos].
func _angles_to(world_pos: Vector3) -> Vector2:
	if _yaw_node == null or _pitch_node == null:
		return Vector2(_yaw, _pitch)
	var parent := _yaw_node.get_parent_node_3d()
	var local := parent.to_local(world_pos) - _yaw_node.position
	var yaw := atan2(-local.x, -local.z)
	var pivot := parent.to_local(_pitch_node.global_position)
	var rel := parent.to_local(world_pos) - pivot
	var flat := Vector2(rel.x, rel.z).length()
	var pitch := atan2(rel.y, maxf(flat, 0.1))
	# Over the -Z side (yaw near 0) the barrels would clip the port block.
	var port := 1.0 - smoothstep(deg_to_rad(40.0), deg_to_rad(80.0), absf(yaw))
	var low := deg_to_rad(lerpf(pitch_min_deg, pitch_min_port_deg, port))
	return Vector2(yaw, clampf(pitch, low, deg_to_rad(pitch_max_deg)))


func _apply_pose() -> void:
	if _yaw_node:
		_yaw_node.rotation = Vector3(0.0, _yaw, 0.0)
	if _pitch_node:
		_pitch_node.rotation = Vector3(_pitch, 0.0, 0.0)


func _fire(t: Node3D, lead: Vector3) -> void:
	var pool := CombatWorld.projectiles_of(get_tree())
	if pool == null:
		return
	_cooldown = 1.0 / fire_rate
	var from := _muzzle_position()
	var dist := from.distance_to(t.global_position)
	var falloff := clampf(1.0 - 0.3 * (dist / maxf(weapon_range, 1.0)), 0.5, 1.0)
	var hits := _rng.randf() < accuracy * falloff * (1.0 - float(t.call(&"get_dodge")))
	var radius := float(t.call(&"get_hit_radius"))
	var aim := lead
	if hits:
		aim += Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.4, 0.4), _rng.randf_range(-1.0, 1.0)) * radius * 0.35
	else:
		var side := (aim - from).cross(Vector3.UP).normalized()
		aim += side * _rng.randf_range(radius * 1.2, radius * 2.5) * (1.0 if _rng.randf() < 0.5 else -1.0)
		aim += (aim - from).normalized() * _rng.randf_range(20.0, 120.0)
	pool.fire(from, aim, t, weapon_damage, hits, self, Combat.PLAYER_TRACER)
	shots_fired += 1
	_since_shot = 0.0


func _muzzle_position() -> Vector3:
	if _muzzles.is_empty():
		return global_position
	_next_muzzle = (_next_muzzle + 1) % _muzzles.size()
	return _muzzles[_next_muzzle].global_position


func _on_combatant_destroyed(node: Node3D, killer: Node3D) -> void:
	if killer == self and node != self:
		kills += 1
		changed.emit()


func _animate(_delta: float) -> void:
	if _light_mat == null:
		return
	var c := IDLE_COLOR
	var energy := _light_base
	if not is_active():
		c = Color(0.3, 0.32, 0.35)
		energy = 0.2
	elif mode == Mode.FIRING:
		c = FIRE_COLOR
		energy = _light_base * (1.6 - 0.6 * clampf(_since_shot / FIRE_HOLD, 0.0, 1.0))
	elif mode == Mode.TRACKING or (not fire_at_will and target):
		c = TRACK_COLOR
	_light_mat.albedo_color = c
	_light_mat.emission = c
	_light_mat.emission_energy_multiplier = energy


func _save_extra(d: Dictionary) -> void:
	d["extra"] = {"fire_at_will": fire_at_will, "kills": kills, "shots_fired": shots_fired}


func _load_extra(d: Dictionary) -> void:
	SaveUtil.apply_props(self, d)

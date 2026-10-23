class_name StationShield
extends Node3D
## The station shield bubble projected by the Shield Generator: a flattened
## sphere (vertical semi-axis [member height_ratio] of the radius) centred on
## the station complex, in the non-rotating "Structures" frame. Its radius
## fits every structure's footprint plus [member margin] and grows smoothly
## ([member grow_speed]) when the complex grows.
##
## Ships fly through it freely. Hostile tracers that start outside and would
## cross it hit its surface instead ([method intercept], used by the
## ProjectilePool): their damage goes to the bubble's HP and leaves a ripple.
## Hostiles already inside hit things normally; friendly shots pass out.
## Raiders shoot the bubble first while it is up (ScavengerBrain).
##
## States: OFFLINE (generator not built yet) -> RAISING -> UP. HP
## regenerates at [member regen] per second once it has not been hit for
## [member regen_delay] seconds. At 0 HP it COLLAPSES (an animation), stays
## DOWN for [member cooldown] seconds, then re-raises at
## [member restore_fraction] strength. Without its generator it goes down
## for good ([method shutdown]).
##
## Not in Combat.GROUP (area queries would treat a 400 m bubble like a
## ship); it implements the combatant API so raiders can target it.

signal state_changed(shield: StationShield)

enum State { OFFLINE, RAISING, UP, COLLAPSING, DOWN }

const STATE_NAMES: PackedStringArray = ["Offline", "Raising", "Up", "Collapsing", "Down"]
const GROUP := "station_shields"
const SHADER: Shader = preload("res://shaders/station_shield.gdshader")
const MAX_IMPACTS := 6
const RIPPLE_TIME := 1.3

@export var max_hp: float = 2400.0
## HP per sim second once not hit for [member regen_delay] seconds.
@export var regen: float = 30.0
@export var regen_delay: float = 5.0
## Sim seconds down after a collapse before it re-raises.
@export var cooldown: float = 45.0
## HP share it comes back with.
@export var restore_fraction: float = 0.4
## Clearance past the outermost footprint, m.
@export var margin: float = 70.0
@export var min_radius: float = 200.0
## Vertical semi-axis / radius.
@export var height_ratio: float = 0.42
## Radius / centre change speed, m per sim second.
@export var grow_speed: float = 45.0
@export var collapse_time: float = 1.6
@export var raise_time: float = 2.5
## Flickers below this HP share.
@export var low_fraction: float = 0.25

var state: State = State.OFFLINE
var hp: float = 0.0
## Current horizontal radius (the vertical one is radius * height_ratio).
var radius: float = 300.0
var generator: ShieldGenerator
## Supplies the complex (structures, bounds); the bubble refits when it changes.
var manager: BuildingManager
## Sim seconds left until it re-raises (DOWN).
var cooldown_left: float = 0.0
var last_hit_time: float = -INF
var hits_taken: int = 0
var damage_taken: float = 0.0
var collapses: int = 0

var _target_radius: float = 300.0
var _target_center := Vector3.ZERO
var _anim := 0.0
var _closing := false
var _mesh: MeshInstance3D
var _mat: ShaderMaterial
var _impacts := PackedVector4Array()
var _next_impact := 0
var _was_raised := false


## The live bubble of the player's station, or null.
static func find(tree: SceneTree) -> StationShield:
	if tree == null:
		return null
	for n in tree.get_nodes_in_group(GROUP):
		var s := n as StationShield
		if s and s.is_alive():
			return s
	return null


## The bubble if it shields [param p] from a shooter at [param from], else null.
static func shielding(tree: SceneTree, p: Vector3, from: Vector3) -> StationShield:
	var s := find(tree)
	return s if s and s.protects(p, from) else null


## Call before adding to the frame.
func setup(owner_generator: ShieldGenerator, building_manager: BuildingManager) -> void:
	generator = owner_generator
	manager = building_manager
	name = "StationShield"


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(SimStepper.GROUP)
	_impacts.resize(MAX_IMPACTS)
	for i in MAX_IMPACTS:
		_impacts[i] = Vector4(0.0, 1.0, 0.0, -100.0)
	_mesh = MeshInstance3D.new()
	_mesh.name = "Bubble"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	_mesh.mesh = sphere
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("impacts", _impacts)
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.layers = 2
	_mesh.visible = false
	add_child(_mesh)
	if manager:
		manager.layout_changed.connect(refit)
	refit()
	radius = _target_radius
	position = _target_center
	var world := CombatWorld.of(get_tree())
	if world:
		world.register_shield(self)
	_apply_shape()


func _exit_tree() -> void:
	var world := CombatWorld.of(get_tree())
	if world:
		world.unregister_shield(self)


func _process(delta: float) -> void:
	if not SimClock.paused:
		sim_step(delta * SimClock.speed)
	_update_look()


func sim_step(dt: float) -> void:
	if dt <= 0.0:
		return
	radius = move_toward(radius, _target_radius, grow_speed * dt)
	position = position.move_toward(_target_center, grow_speed * dt)
	_apply_shape()
	var gen_ok := generator_online()
	match state:
		State.OFFLINE:
			if gen_ok and not _closing:
				_raise(_was_raised)
		State.RAISING:
			_anim = minf(_anim + dt / raise_time, 1.0)
			_regen(dt)
			if _anim >= 1.0:
				_set_state(State.UP)
		State.UP:
			_regen(dt)
		State.COLLAPSING:
			_anim = maxf(_anim - dt / collapse_time, 0.0)
			if _anim <= 0.0:
				if _closing:
					queue_free()
					return
				cooldown_left = cooldown
				_set_state(State.DOWN)
		State.DOWN:
			cooldown_left = maxf(cooldown_left - dt, 0.0)
			if cooldown_left <= 0.0 and gen_ok:
				_raise(true)
	if (state == State.UP or state == State.RAISING) and not gen_ok:
		_collapse()


## True while the bubble stops hostile shots.
func is_up() -> bool:
	return state == State.UP or state == State.RAISING


func generator_online() -> bool:
	return is_instance_valid(generator) and generator.is_active()


func charge() -> float:
	return clampf(hp / max_hp, 0.0, 1.0) if is_up() else 0.0


func get_state_name() -> String:
	return STATE_NAMES[state]


## Seconds without a hit (regen starts after [member regen_delay]).
func seconds_since_hit() -> float:
	return SimClock.time - last_hit_time


func is_regenerating() -> bool:
	return is_up() and hp < max_hp and seconds_since_hit() >= regen_delay


## Recomputes the radius and centre that fit the complex (it then grows
## toward them smoothly).
func refit() -> void:
	if manager == null:
		return
	var box := manager.complex_bounds()
	var c := box.get_center()
	var centre := Vector3(c.x, 0.0, c.y)
	var r := Vector2(centre.x, centre.z).length() + manager.station_radius
	for b in manager.complex_structures():
		r = maxf(r, Vector2(b.position.x - centre.x, b.position.z - centre.z).length() + b.def.footprint_radius)
	_target_center = centre
	_target_radius = maxf(r + margin, min_radius)


func target_radius() -> float:
	return _target_radius


## World point [param p] inside the bubble (any state).
func contains(p: Vector3) -> bool:
	return _unit(p).length_squared() < 1.0


## True when [param p] is shielded from a shooter at [param from]: the
## bubble is up, [param p] is inside and [param from] is outside.
func protects(p: Vector3, from: Vector3) -> bool:
	return is_up() and contains(p) and not contains(from)


## Fraction (0..1) along the segment [param a] -> [param b] where it enters
## the bubble, or -1 when it does not (bubble down, or [param a] inside).
func intercept(a: Vector3, b: Vector3) -> float:
	if not is_up():
		return -1.0
	var la := _unit(a)
	var c := la.length_squared() - 1.0
	if c <= 0.0:
		return -1.0
	var d := _unit(b) - la
	var qa := d.length_squared()
	if qa < 1e-9:
		return -1.0
	var qb := 2.0 * la.dot(d)
	if qb >= 0.0:
		return -1.0
	var disc := qb * qb - 4.0 * qa * c
	if disc < 0.0:
		return -1.0
	var t := (-qb - sqrt(disc)) / (2.0 * qa)
	return t if t >= 0.0 and t <= 1.0 else -1.0


## Point a little inside the surface on the line from the centre toward
## [param from], jittered (raiders aim there).
func aim_point(from: Vector3, rng: RandomNumberGenerator) -> Vector3:
	var dir := _unit(from)
	dir.y *= 0.3
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.RIGHT
	dir = (dir + Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(0.0, 0.18), rng.randf_range(-0.12, 0.12))).normalized()
	return global_position + Vector3(dir.x * radius, dir.y * radius * height_ratio, dir.z * radius) * 0.985


## A hostile shot hit the surface at [param at]: ripple, HP loss.
func absorb(amount: float, attacker: Node3D, at: Vector3) -> void:
	if not is_up():
		return
	_add_impact(at)
	if amount <= 0.0:
		return
	last_hit_time = SimClock.time
	hits_taken += 1
	damage_taken += amount
	hp = maxf(hp - amount, 0.0)
	if is_instance_valid(attacker) and attacker is ScavengerShip:
		EventLog.post("Raiders are attacking the station shield", EventLog.Kind.THREAT, self, Vector3.INF, "shield_attack")
	if hp <= 0.0:
		_collapse()


## The generator is gone: collapse and free the node.
func shutdown() -> void:
	_closing = true
	if not is_inside_tree():
		queue_free()
	elif is_up():
		_collapse()
	elif state != State.COLLAPSING:
		queue_free()


# --- Combatant API (see Combat) ---------------------------------------------

func get_faction() -> int:
	return Combat.Faction.PLAYER


func is_alive() -> bool:
	return not _closing


func is_targetable() -> bool:
	return is_up() and is_inside_tree()


func get_hit_radius() -> float:
	return radius


func get_aim_velocity() -> Vector3:
	return SpaceNav.world_velocity(self)


func get_dodge() -> float:
	return 0.0


func get_display_name() -> String:
	return "Station Shield"


func take_hit(amount: float, attacker: Node3D, at: Vector3) -> void:
	absorb(amount, attacker, at)


# --- State ----------------------------------------------------------------------

func _raise(restored: bool) -> void:
	hp = max_hp * restore_fraction
	_anim = 0.0
	_set_state(State.RAISING)
	if restored:
		EventLog.post("Station shield restored", EventLog.Kind.INFO, self)
	else:
		EventLog.post("Station shield online", EventLog.Kind.INFO, self)
	_was_raised = true


func _collapse() -> void:
	if not is_up():
		return
	hp = 0.0
	collapses += 1
	_set_state(State.COLLAPSING)
	EventLog.post("Station shield down!", EventLog.Kind.THREAT, self)


func _regen(dt: float) -> void:
	if hp < max_hp and seconds_since_hit() >= regen_delay:
		hp = minf(hp + regen * dt, max_hp)


func _set_state(s: State) -> void:
	if state == s:
		return
	state = s
	state_changed.emit(self)


# --- Shape and look -------------------------------------------------------------

## World point -> unit-sphere space of the bubble.
func _unit(p: Vector3) -> Vector3:
	var l := p - global_position
	var r := maxf(radius, 1.0)
	return Vector3(l.x / r, l.y / (r * height_ratio), l.z / r)


func _apply_shape() -> void:
	if _mesh:
		_mesh.scale = Vector3(radius, radius * height_ratio, radius)


func _add_impact(at: Vector3) -> void:
	var u := _unit(at).normalized()
	_impacts[_next_impact] = Vector4(u.x, u.y, u.z, SimClock.time)
	_next_impact = (_next_impact + 1) % MAX_IMPACTS
	if _mat:
		_mat.set_shader_parameter("impacts", _impacts)


func _update_look() -> void:
	if _mat == null:
		return
	var shown := state != State.OFFLINE and state != State.DOWN
	_mesh.visible = shown
	if not shown:
		return
	var k := clampf(hp / max_hp, 0.0, 1.0)
	_mat.set_shader_parameter("sim_time", SimClock.time)
	_mat.set_shader_parameter("charge", k)
	_mat.set_shader_parameter("radius", radius)
	# Raising grows the cells in; collapsing breaks them up.
	var dissolve := 1.0 - _anim
	_mat.set_shader_parameter("dissolve", dissolve)
	_mat.set_shader_parameter("collapsing", 1.0 if state == State.COLLAPSING else 0.0)
	var flick := 0.0
	if is_up() and k < low_fraction:
		flick = 1.0 - k / low_fraction
	_mat.set_shader_parameter("flicker", flick)
	_mat.set_shader_parameter("view_fade", _view_fade())


## Fades the bubble with the camera: faint when the camera is inside or close
## (it would cover the view), full at complex range, gone at system range.
func _view_fade() -> float:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return 1.0
	var d := cam.global_position.distance_to(global_position)
	var near := smoothstep(radius * 0.8, radius * 2.2, d)
	var far := 1.0 - smoothstep(radius * 14.0, radius * 30.0, d)
	return lerpf(0.25, 1.0, near) * far

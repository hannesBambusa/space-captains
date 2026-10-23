class_name ScavengerDen
extends Node3D
## A Scavenger Den: a hollowed rock with a salvage hangar, built by
## SolarSystem from a [DenDef]. Launches scavengers up to its spawn cap (one
## per respawn time), sends raiders for the RaidDirector, shoots at player
## ships that come close (a couple of point-defence guns) and can be
## destroyed: a chain of explosions, a large scrap field, its belt's danger
## drops by the den's danger bonus and no more scavengers come from it.
## Model: res://assets/models/buildings/scavenger_den.glb (den_rock,
## den_salvage, den_hangar_glow pulsing, den_lights flickering, spawn_point
## with local -Z pointing out of the mouth).

signal destroyed(den: ScavengerDen, killer: Node3D)
signal spawned(den: ScavengerDen, ship: ScavengerShip)

const GROUP := "scavenger_dens"
const MODEL_PATH := "res://assets/models/buildings/scavenger_den.glb"
const RENDER_LAYER := 2
## Point defence: range, damage per shot, shots per second.
const GUN_RANGE := 650.0
const GUN_DAMAGE := 6.0
const GUN_RATE := 2.0

var def: DenDef
var belt: SystemBelt
var durability: Durability
var faction: Combat.Faction = Combat.Faction.SCAVENGER
var dead: bool = false
## Spawned ships still out (not raiders).
var spawns: Array[ScavengerShip] = []
var raiders: Array[ScavengerShip] = []
var total_spawned: int = 0
## Cargo shares brought home by its scavengers (stage 3: salvage loot).
var stash: float = 0.0
## Scrap per stashed load share when the den's stash spills into its ruins.
const STASH_SCRAP := 30.0

var _model: Node3D
var _glow_mats: Array[StandardMaterial3D] = []
var _glow_base: Array[float] = []
var _light_mats: Array[StandardMaterial3D] = []
var _light_base: Array[float] = []
var _hangar_light: OmniLight3D
var _respawn_clock: float = 0.0
var _gun_cooldown: float = 0.0
var _gun_target: Node3D
var _gun_timer: float = 0.0
var _rng := RandomNumberGenerator.new()
var _spawn_seq: int = 0


func setup(den_def: DenDef, claimed: SystemBelt) -> void:
	def = den_def
	belt = claimed
	name = StringName(def.name.validate_node_name().replace(" ", ""))


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(Combat.GROUP)
	add_to_group(SimStepper.GROUP)
	_rng.seed = hash(def.name)
	durability = Durability.new(def.hull, def.shields, def.shield_regen)
	durability.shield_delay = 6.0
	_model = ModelLoader.instantiate(MODEL_PATH, ModelLoader.building_placeholder.bind(50.0))
	_model.name = "Model"
	add_child(_model)
	ModelLoader.dim_emission(_model)
	MeshUtil.set_layers_recursive(_model, RENDER_LAYER)
	_collect_mats("den_hangar_glow", _glow_mats, _glow_base)
	_collect_mats("den_lights", _light_mats, _light_base)
	_hangar_light = OmniLight3D.new()
	_hangar_light.name = "HangarLight"
	_hangar_light.light_color = Color(1.0, 0.4, 0.2)
	_hangar_light.light_energy = 4.0
	_hangar_light.omni_range = 140.0
	_hangar_light.omni_attenuation = 1.5
	_hangar_light.light_cull_mask = RENDER_LAYER
	_hangar_light.position = Vector3(0.0, 4.0, 30.0)
	add_child(_hangar_light)
	set_meta(&"focus_radius", 60.0)
	set_meta(&"focus_distance", 520.0)
	add_to_group(RTSCamera.FOCUS_GROUP)
	_respawn_clock = def.respawn_time
	_initial_spawns.call_deferred()


func _initial_spawns() -> void:
	for i in def.initial_spawns:
		spawn(false, true)


func _process(delta: float) -> void:
	if not SimClock.paused:
		sim_step(delta * SimClock.speed)
	_animate()


func sim_step(dt: float) -> void:
	if dead or dt <= 0.0:
		return
	durability.step(dt)
	_prune()
	if spawns.size() < def.spawn_cap:
		_respawn_clock -= dt
		if _respawn_clock <= 0.0:
			_respawn_clock = def.respawn_time
			spawn(false)
	_guns(dt)


# --- Combatant API ------------------------------------------------------------

func get_faction() -> int:
	return faction


func is_alive() -> bool:
	return not dead


func is_targetable() -> bool:
	return not dead and is_inside_tree()


func get_hit_radius() -> float:
	return 42.0


func get_aim_velocity() -> Vector3:
	return Vector3.ZERO


func get_dodge() -> float:
	return 0.0


func get_display_name() -> String:
	return def.name if def else "Scavenger Den"


func get_status_text() -> String:
	if dead:
		return "Destroyed"
	return "Active, %d/%d out" % [spawns.size(), def.spawn_cap]


func hull_fraction() -> float:
	return durability.fraction()


func take_hit(amount: float, attacker: Node3D, at: Vector3) -> void:
	if dead:
		return
	durability.apply(amount, attacker)
	if durability.is_dead():
		destroy(attacker)
	elif _rng.randf() < 0.08:
		var fx := CombatWorld.fx_of(get_tree())
		if fx:
			fx.explode(at, 5.0)


# --- Spawning -------------------------------------------------------------------

## Launches one scavenger. [param raid] = a raider for the RaidDirector (does
## not count against the cap). [param out_already] places it outside the
## mouth (initial spawns) instead of in the hangar.
func spawn(raid: bool = false, out_already: bool = false) -> ScavengerShip:
	if dead:
		return null
	_spawn_seq += 1
	var s := ScavengerShip.new()
	s.setup_scavenger(self, "%s-%d" % [def.gang, _spawn_seq], raid)
	var mouth := _spawn_point()
	var out_dir := get_outward()
	var pos := mouth + out_dir * (_rng.randf_range(120.0, 400.0) if out_already else 6.0)
	if out_already:
		pos += out_dir.cross(Vector3.UP) * _rng.randf_range(-250.0, 250.0)
	pos.y = 0.0
	var root := SpaceNav.space_root(get_tree())
	root.add_child(s)
	s.global_position = pos
	s.mover.yaw = ShipMover.yaw_for(out_dir)
	s.rotation.y = s.mover.yaw
	s.mover.avoid_enabled = true
	s.mover.velocity = out_dir * 40.0
	if raid:
		raiders.append(s)
	else:
		spawns.append(s)
	total_spawned += 1
	spawned.emit(self, s)
	var world := CombatWorld.of(get_tree())
	if world:
		world.notify_spawned(s)
	return s


## A scavenger came home: it docks and leaves the map with its loot.
func recall(s: ScavengerShip) -> void:
	stash += s.loot
	spawns.erase(s)
	raiders.erase(s)
	s.leave_map()


func forget(s: ScavengerShip) -> void:
	spawns.erase(s)
	raiders.erase(s)


func get_mouth_position() -> Vector3:
	return _spawn_point()


func _spawn_point() -> Vector3:
	var n := _model.find_child("spawn_point", true, false) as Node3D if _model else null
	if n:
		return n.global_position
	return global_transform * Vector3(0.0, 0.0, 30.0)


func get_outward() -> Vector3:
	var n := _model.find_child("spawn_point", true, false) as Node3D if _model else null
	var d := -n.global_basis.z if n else global_basis.z
	d.y = 0.0
	return d.normalized() if d.length() > 0.01 else Vector3.FORWARD


func _prune() -> void:
	_prune_list(spawns)
	_prune_list(raiders)


static func _prune_list(a: Array[ScavengerShip]) -> void:
	var i := a.size() - 1
	while i >= 0:
		if not is_instance_valid(a[i]) or a[i].dead:
			a.remove_at(i)
		i -= 1


# --- Point defence ----------------------------------------------------------------

func _guns(dt: float) -> void:
	_gun_cooldown -= dt
	_gun_timer -= dt
	if _gun_timer <= 0.0:
		_gun_timer = 0.5
		_gun_target = Combat.nearest_hostile(get_tree(), global_position, GUN_RANGE + get_hit_radius(), faction)
	if _gun_cooldown > 0.0 or not Combat.is_live_target(_gun_target):
		return
	_gun_cooldown = 1.0 / GUN_RATE
	var pool := CombatWorld.projectiles_of(get_tree())
	if pool == null:
		return
	var from := global_transform * Vector3(_rng.randf_range(-25.0, 25.0), 14.0, _rng.randf_range(-20.0, 20.0))
	var tp := _gun_target.global_position
	var hits := _rng.randf() < 0.55 * (1.0 - float(_gun_target.call(&"get_dodge")))
	var aim := tp + (_gun_target.call(&"get_aim_velocity") as Vector3) * (from.distance_to(tp) / ProjectilePool.SPEED)
	if not hits:
		aim += Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized() * 30.0
	pool.fire(from, aim, _gun_target, GUN_DAMAGE, hits, self, Combat.HOSTILE_TRACER)


# --- Destruction ----------------------------------------------------------------

func destroy(killer: Node3D = null) -> void:
	if dead:
		return
	dead = true
	var world := CombatWorld.of(get_tree())
	if world:
		world.fx.explode_chain(global_position, 45.0, 7, 2.4)
		var ruins := world.spawn_scrap(global_position + get_outward() * 20.0, world.den_scrap, world.den_scrap_life, 130.0, "%s ruins" % get_display_name())
		ruins.set_meta(&"den_ruins", true)
		var extra := roundi(stash * STASH_SCRAP)
		if extra > 0:
			ruins.add_scrap(extra)
			EventLog.post("%s's stash of stolen cargo spilled into the ruins (+%d scrap)" % [get_display_name(), extra], EventLog.Kind.REWARD, ruins)
			stash = 0.0
	for path in ["den_salvage", "den_lights", "den_hangar_glow"]:
		var n := _model.find_child(path, true, false) as Node3D if _model else null
		if n:
			n.visible = false
	_hangar_light.visible = false
	for mi in ModelLoader.meshes_of(_model):
		if mi.visible:
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.16, 0.15, 0.14)
			m.roughness = 1.0
			m.emission_enabled = true
			m.emission = Color(1.0, 0.3, 0.08)
			m.emission_energy_multiplier = 0.15
			mi.material_override = m
	if belt:
		belt.danger_reduction += def.danger_bonus
	_credit_den_kill(killer)
	remove_from_group(Combat.GROUP)
	var by := ""
	if is_instance_valid(killer) and killer.has_method(&"get_display_name"):
		by = " by %s" % String(killer.call(&"get_display_name"))
	var has_bounty := false
	for c in ContractBoard.get_for_target(self):
		if c is BountyContract:
			has_bounty = true
	if not has_bounty:
		EventLog.post("%s destroyed%s" % [get_display_name(), by], EventLog.Kind.REWARD, self)
	destroyed.emit(self, killer)
	if world:
		world.notify_destroyed(self, killer)


## Reputation for everyone who fought the den: the killer most.
func _credit_den_kill(killer: Node3D) -> void:
	var done: Array[Ship] = []
	var k := killer as Ship
	if k and k.captain and k.faction == Combat.Faction.PLAYER:
		k.captain.add_reputation(Reputation.DEN)
		done.append(k)
	for o in durability.attackers(300.0):
		var s := o as Ship
		if s and not done.has(s) and s.captain and s.faction == Combat.Faction.PLAYER and not s.dead:
			s.captain.add_reputation(Reputation.DEN_ASSIST)
			done.append(s)


# --- Look -------------------------------------------------------------------------

func _collect_mats(node_name: String, mats: Array[StandardMaterial3D], base: Array[float]) -> void:
	var n := _model.find_child(node_name, true, false) if _model else null
	if n == null:
		return
	for mi in ModelLoader.meshes_of(n):
		for s in mi.get_surface_override_material_count():
			var src := mi.get_active_material(s) as StandardMaterial3D
			if src == null:
				continue
			var m := src.duplicate() as StandardMaterial3D
			m.emission_enabled = true
			mi.set_surface_override_material(s, m)
			mats.append(m)
			base.append(maxf(src.emission_energy_multiplier, 1.0))


func _animate() -> void:
	if dead:
		return
	var t := Time.get_ticks_msec() * 0.001
	var pulse := 0.65 + 0.35 * sin(t * 1.7)
	for i in _glow_mats.size():
		_glow_mats[i].emission_energy_multiplier = _glow_base[i] * pulse
	_hangar_light.light_energy = 3.0 + 3.0 * pulse
	# Bad wiring: mostly on, with short dropouts and stutters.
	var f := 1.0
	var k := fposmod(t * 0.7, 1.0)
	if k > 0.82 and k < 0.86:
		f = 0.15
	elif k > 0.9 and k < 0.91:
		f = 0.4
	else:
		f = 0.85 + 0.15 * sin(t * 23.0) * sin(t * 7.3)
	for i in _light_mats.size():
		_light_mats[i].emission_energy_multiplier = _light_base[i] * f

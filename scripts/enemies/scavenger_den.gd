class_name ScavengerDen
extends StaticCombatant
## A hostile base, built by SolarSystem from a [DenDef]: a Scavenger
## Hideout (a hollowed rock with a salvage hangar), a Corsair Nest or a
## Syndicate Fortress, by its [FactionDef]. Launches its faction's ships up
## to its spawn cap (one per respawn time, a whole pack for pack factions),
## sends raiders for the RaidDirector, shoots at player ships that come
## close (the faction's point-defence guns) and can be destroyed: a chain of
## explosions, a large scrap field, nearby asteroid clusters lose its
## danger bonus and no more ships come from it. It sits at a fixed spot;
## [member belt] is the cluster nearest to it right now (clusters drift).
## Base defence: a hit from the player's side raises the alarm for
## [constant ALERT_TIME] s after the last hit ("Rustjaw Hideout is calling
## its raiders home", at most every [constant ALERT_REPEAT] s). Its own
## ships within [constant RECALL_RADIUS] and same-faction ships of other
## bases within [constant ALLY_RADIUS] come back and fight the attackers
## (ScavengerBrain.defend), except those already fleeing home; while the
## alarm lasts it launches below its cap [constant ALERT_RESPAWN_MULT] times
## faster and every new ship joins the defence.
## Model: the faction's den model, else res://assets/models/buildings/scavenger_den.glb
## tinted in the faction colour (den_rock, den_salvage, den_hangar_glow
## pulsing, den_lights flickering, spawn_point with local -Z pointing out of
## the mouth).

signal destroyed(den: ScavengerDen, killer: Node3D)
signal spawned(den: ScavengerDen, ship: ScavengerShip)

const GROUP := "scavenger_dens"
const MODEL_PATH := FactionDef.SCAVENGER_DEN_MODEL
const RENDER_LAYER := 2

var def: DenDef
var faction_def: FactionDef
## The cluster within AsteroidCluster.DEN_REACH of the base right now, or null.
var belt: AsteroidCluster:
	get: return _near_cluster()
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
## Base defence (see the class notes): alarm length after the last hit,
## the event line's repeat gap, recall and ally radii, how often the call
## goes out again while hits keep coming, and the faster launches.
const ALERT_TIME := 25.0
const ALERT_REPEAT := 90.0
const RECALL_RADIUS := 14000.0
const ALLY_RADIUS := 6000.0
const CALL_INTERVAL := 3.0
const ALERT_RESPAWN_MULT := 1.5
## Defenders fight hostiles this close to the base, metres.
const GUARD_RADIUS := 1600.0

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
## A loaded game brings its own scavengers: no start-up launches.
var skip_initial_spawns: bool = false
## SimClock.time it arrived (ThreatDirector); far past for start dens.
var arrived_at: float = -1.0e9
## Sim seconds of the warp-in look (play_arrival).
const ARRIVAL_LOOK_TIME := 6.0
var _arrival_left: float = 0.0
var _arrival_mat: ShaderMaterial
## SimClock.time the alarm ends, and the last "calling its raiders home" line.
var _alert_until: float = -1.0e9
var _alert_line_at: float = -1.0e9
var _call_timer: float = 0.0


func setup(den_def: DenDef, _unused: Variant = null) -> void:
	def = den_def
	faction_def = den_def.get_faction()
	name = StringName(def.name.validate_node_name().replace(" ", ""))


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(Combat.GROUP)
	add_to_group(SimStepper.GROUP)
	_rng.seed = hash(def.name)
	durability = Durability.new(def.get_hull(), def.get_shields(), def.get_shield_regen())
	durability.shield_delay = 6.0
	var path := FactionDef.pick_model(faction_def.den_model_path, MODEL_PATH)
	_model = ModelLoader.instantiate(path, ModelLoader.building_placeholder.bind(50.0 * faction_def.den_hit_radius / 42.0, faction_def.color))
	_model.name = "Model"
	add_child(_model)
	if path != faction_def.den_model_path:
		ModelLoader.tint(_model, faction_def.color, faction_def.fallback_tint)
		_model.scale *= faction_def.den_fallback_scale
	ModelLoader.dim_emission(_model)
	MeshUtil.set_layers_recursive(_model, RENDER_LAYER)
	_collect_mats("den_hangar_glow", _glow_mats, _glow_base)
	_collect_mats("den_lights", _light_mats, _light_base)
	_hangar_light = OmniLight3D.new()
	_hangar_light.name = "HangarLight"
	_hangar_light.light_color = faction_def.light_color
	_hangar_light.light_energy = 4.0
	_hangar_light.omni_range = 140.0
	_hangar_light.omni_attenuation = 1.5
	_hangar_light.light_cull_mask = RENDER_LAYER
	# In front of the mouth (spawn_point, local +Z out): (0, 4, 30) on the scavenger den.
	var sp := _model.find_child("spawn_point", true, false) as Node3D
	var k := faction_def.den_scale()
	if sp:
		var o := ModelLoader.relative_transform(self, sp).origin
		_hangar_light.position = Vector3(o.x, 4.0 * k, o.z + 6.0 * k)
	else:
		_hangar_light.position = Vector3(0.0, 4.0, 30.0) * k
	_hangar_light.omni_range = 140.0 * k
	add_child(_hangar_light)
	set_meta(&"focus_radius", 60.0 * k)
	set_meta(&"focus_distance", 520.0 * k)
	add_to_group(RTSCamera.FOCUS_GROUP)
	_respawn_clock = def.respawn_time
	_initial_spawns.call_deferred()


func _initial_spawns() -> void:
	if skip_initial_spawns:
		return
	var left := def.initial_spawns
	while left > 0:
		var n := mini(faction_def.pack_size, left)
		spawn_pack(n, false, true)
		left -= n


func _process(delta: float) -> void:
	# Substepped: the guns' fire rate holds at high sim speed.
	SimClock.substep(sim_step)
	_animate()


func sim_step(dt: float) -> void:
	if dt > 0.0 and _arrival_left > 0.0:
		_step_arrival(dt)
	if dead or dt <= 0.0:
		return
	durability.step(dt)
	_prune()
	_call_timer -= dt
	if spawns.size() < def.spawn_cap:
		_respawn_clock -= dt * (ALERT_RESPAWN_MULT if is_alerted() else 1.0)
		if _respawn_clock <= 0.0:
			_respawn_clock = def.respawn_time
			spawn_pack(mini(faction_def.pack_size, def.spawn_cap - spawns.size()))
	_guns(dt)


# --- Arrival ----------------------------------------------------------------------

## Warp-in for a base arriving mid-game: a big flash, then the model builds
## up from a faction-tinted hologram grid (the buildings' construction look)
## over [constant ARRIVAL_LOOK_TIME] sim seconds. Cosmetic: the base is live
## at once.
func play_arrival() -> void:
	arrived_at = SimClock.time
	var k := faction_def.den_scale()
	WarpFx.flash(self, global_position, 110.0 * k)
	_arrival_mat = faction_def.holo_material(6.0 * k)
	for mi in ModelLoader.meshes_of(_model):
		mi.material_override = _arrival_mat
	_arrival_left = ARRIVAL_LOOK_TIME
	_step_arrival(0.0)


func _step_arrival(dt: float) -> void:
	_arrival_left = maxf(_arrival_left - dt, 0.0)
	var k := faction_def.den_scale()
	var p := 1.0 - _arrival_left / ARRIVAL_LOOK_TIME
	if _arrival_mat:
		_arrival_mat.set_shader_parameter("fill_y", global_position.y + lerpf(-70.0, 70.0, p) * k)
	if _arrival_left <= 0.0 and not dead:
		for mi in ModelLoader.meshes_of(_model):
			mi.material_override = null
		_arrival_mat = null


func is_arriving() -> bool:
	return _arrival_left > 0.0


# --- Combatant API ------------------------------------------------------------

func get_faction() -> int:
	return faction


func is_alive() -> bool:
	return not dead


func is_targetable() -> bool:
	return not dead and is_inside_tree()


func get_hit_radius() -> float:
	return faction_def.den_hit_radius


func get_aim_velocity() -> Vector3:
	return Vector3.ZERO


func get_display_name() -> String:
	return def.name if def else "Hostile base"


func get_status_text() -> String:
	if dead:
		return "Destroyed"
	if is_arriving():
		return "Arriving, %d/%d out" % [spawns.size(), def.spawn_cap]
	return "Active, %d/%d out" % [spawns.size(), def.spawn_cap]


func hull_fraction() -> float:
	return durability.fraction()


## Target panel blurb.
func info_text() -> String:
	return faction_def.den_info % [claim_name(), def.spawn_cap]


## Lower-case kind for headers and tooltips: "scavenger hideout".
func kind_name() -> String:
	return faction_def.den_kind


## What it holds, for tooltips: "claims Talon Reach".
func claim_text() -> String:
	return "claims %s" % claim_name()


## The cluster it preys on now, else its region ("Talon Reach").
func claim_name() -> String:
	var b := belt
	if b:
		return b.def.name
	return def.belt_name if def and not def.belt_name.is_empty() else "the outer dark"


func _near_cluster() -> AsteroidCluster:
	if not is_inside_tree():
		return null
	var sys := SolarSystem.of(self)
	return sys.cluster_near(global_position, AsteroidCluster.DEN_REACH) if sys else null


## Damage per second of its own guns (MercFleet's need estimate).
func gun_dps() -> float:
	return faction_def.den_gun_dps()


## Sends raids at the colony (RaidDirector) and counts as a hostile base
## for the threat clock (ThreatDirector). Garrisons do neither.
func is_raid_base() -> bool:
	return true


func take_hit(amount: float, attacker: Node3D, at: Vector3) -> void:
	if dead:
		return
	durability.apply(amount, attacker)
	if durability.is_dead():
		destroy(attacker)
		return
	if is_instance_valid(attacker) and attacker.has_method(&"get_faction") and Combat.hostile(int(attacker.call(&"get_faction")), faction):
		raise_alert()
	elif _rng.randf() < 0.08:
		var fx := CombatWorld.fx_of(self)
		if fx:
			fx.explode(at, 5.0)


# --- Base defence -----------------------------------------------------------------

## The alarm is on (hit in the last [constant ALERT_TIME] s).
func is_alerted() -> bool:
	return not dead and SimClock.time < _alert_until


## Hit by the player's side: calls the defenders (see the class notes).
func raise_alert() -> void:
	var now := SimClock.time
	var fresh := not is_alerted()
	_alert_until = now + ALERT_TIME
	if fresh and now - _alert_line_at >= ALERT_REPEAT:
		_alert_line_at = now
		EventLog.post("%s is calling its raiders home" % get_display_name(), EventLog.Kind.THREAT, self, Vector3.INF, "", faction_def.id)
	if fresh or _call_timer <= 0.0:
		_call_timer = CALL_INTERVAL
		call_defenders()


## Its ships near enough, and same-faction ships of other bases close by,
## come back to fight. Returns how many answered.
func call_defenders() -> int:
	var n := 0
	for o in SystemWorld.nodes_in(self, Ship.GROUP):
		var s := o as ScavengerShip
		if s == null or s.dead or s.ai == null or s.faction_def == null or s.faction_def.id != faction_def.id:
			continue
		var d := global_position.distance_to(s.global_position)
		if d > (RECALL_RADIUS if s.den == self else ALLY_RADIUS):
			continue
		if s.ai.defend(self):
			n += 1
	return n


## Who to fight near the base: its last attacker while it is close, else
## the nearest hostile ship inside [constant GUARD_RADIUS]. Null when clear.
func defence_target() -> Node3D:
	var la := durability.get_last_attacker() as Node3D
	if Combat.is_live_target(la) and durability.seconds_since_hit() < 8.0 and global_position.distance_to(la.global_position) < GUARD_RADIUS + get_hit_radius():
		return la
	for h in Combat.hostiles_near(self, global_position, GUARD_RADIUS + get_hit_radius(), faction):
		if h is Ship:
			return h
	return null


# --- Spawning -------------------------------------------------------------------

## Launches [param count] ships that fly together: the first leads, the
## others are its wingmen (ScavengerBrain.lead). Returns them.
func spawn_pack(count: int, raid: bool = false, out_already: bool = false) -> Array[ScavengerShip]:
	var out: Array[ScavengerShip] = []
	for i in maxi(count, 1):
		var s := spawn(raid, out_already)
		if s == null:
			break
		if not out.is_empty():
			s.ai.set_lead(out[0])
		out.append(s)
	return out


## Next callsign: a name-pool word ("Shrike-4") or the gang ("Rustjaw-3").
func _next_callsign() -> String:
	var pool := faction_def.name_pool
	if pool.is_empty():
		return "%s-%d" % [def.gang, _spawn_seq]
	return "%s-%d" % [pool[_rng.randi() % pool.size()], _spawn_seq]


## Launches one ship. [param raid] = a raider for the RaidDirector (does
## not count against the cap). [param out_already] places it outside the
## mouth (initial spawns) instead of in the hangar.
func spawn(raid: bool = false, out_already: bool = false) -> ScavengerShip:
	if dead:
		return null
	_spawn_seq += 1
	var s := ScavengerShip.new()
	s.setup_scavenger(self, _next_callsign(), raid, faction_def)
	var mouth := _spawn_point()
	var out_dir := get_outward()
	var pos := mouth + out_dir * (_rng.randf_range(120.0, 400.0) if out_already else 6.0)
	if out_already:
		pos += out_dir.cross(Vector3.UP) * _rng.randf_range(-250.0, 250.0)
	pos.y = mouth.y
	var root := SpaceNav.space_root(self)
	root.add_child(s)
	s.global_position = pos
	s.set_heading(ShipMover.yaw_for(out_dir))
	s.mover.avoid_enabled = true
	s.mover.velocity = out_dir * 40.0
	if raid:
		raiders.append(s)
	else:
		spawns.append(s)
		if is_alerted() and s.ai:
			s.ai.defend(self)
	total_spawned += 1
	spawned.emit(self, s)
	var world := CombatWorld.of(self)
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
	var f := faction_def
	if f.den_guns <= 0:
		return
	if _gun_timer <= 0.0:
		_gun_timer = 0.5
		_gun_target = Combat.nearest_hostile(self, global_position, f.den_gun_range + get_hit_radius(), faction)
	if _gun_cooldown > 0.0 or not Combat.is_live_target(_gun_target):
		return
	_gun_cooldown = 1.0 / f.den_gun_rate
	var pool := CombatWorld.projectiles_of(self)
	if pool == null:
		return
	var spread := f.den_scale()
	for g in f.den_guns:
		var from := global_transform * (Vector3(_rng.randf_range(-25.0, 25.0), 14.0, _rng.randf_range(-20.0, 20.0)) * spread)
		var tp := _gun_target.global_position
		var hits := _rng.randf() < 0.55 * (1.0 - float(_gun_target.call(&"get_dodge")))
		var aim := tp + (_gun_target.call(&"get_aim_velocity") as Vector3) * (from.distance_to(tp) / ProjectilePool.SPEED)
		if not hits:
			aim += Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized() * 30.0
		pool.fire(from, aim, _gun_target, f.den_gun_damage, hits, self, Combat.HOSTILE_TRACER)


# --- Destruction ----------------------------------------------------------------

func destroy(killer: Node3D = null) -> void:
	if dead:
		return
	dead = true
	var world := CombatWorld.of(self)
	if world:
		var size := faction_def.den_scale()
		world.fx.explode_chain(global_position, 45.0 * size, 7, 2.4)
		var ruins := world.spawn_scrap(global_position + get_outward() * 20.0, roundi(world.den_scrap * faction_def.loot_mult), world.den_scrap_life, 130.0 * size, "%s ruins" % get_display_name())
		ruins.set_meta(&"den_ruins", true)
		var extra := roundi(stash * STASH_SCRAP * faction_def.loot_mult)
		if extra > 0:
			ruins.add_scrap(extra)
			EventLog.post("%s's stash of stolen cargo spilled into the ruins (+%d scrap)" % [get_display_name(), extra], EventLog.Kind.REWARD, ruins, Vector3.INF, "", faction_def.id)
			stash = 0.0
	_apply_ruined_look()
	_credit_den_kill(killer)
	remove_from_group(Combat.GROUP)
	var by := Combat.by_suffix(killer)
	var has_bounty := false
	for c in ContractBoard.get_for_target(self):
		if c is BountyContract:
			has_bounty = true
	if not has_bounty:
		EventLog.post("%s destroyed%s" % [get_display_name(), by], EventLog.Kind.REWARD, self, Vector3.INF, "", faction_def.id)
	destroyed.emit(self, killer)
	if world:
		world.notify_destroyed(self, killer)


## Burnt-out rock: lights, glow and salvage gone.
func _apply_ruined_look() -> void:
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


# --- Save ---------------------------------------------------------------------

## Hull, stash, spawn counters and its ships (by save id; the ships are
## saved with the other ships).
func save_state() -> Dictionary:
	var sp := SaveUtil.ids(spawns, true)
	var rd := SaveUtil.ids(raiders, true)
	return {"id": SaveIds.of(self), "name": def.name if def else String(name), "dead": dead, "durability": SaveUtil.durability(durability),
			"total_spawned": total_spawned, "stash": stash, "respawn_clock": _respawn_clock, "spawn_seq": _spawn_seq,
			"gun_cooldown": _gun_cooldown, "arrived_at": arrived_at, "rng": SaveUtil.rng_state(_rng), "spawns": sp, "raiders": rd,
			"alert_until": _alert_until, "alert_line_at": _alert_line_at}


## State without the ships (see [method restore_ships]). A dead den gets its
## ruined look back without the explosion, scrap or messages (those are in
## the save already).
func load_state(d: Dictionary) -> void:
	skip_initial_spawns = true
	total_spawned = int(d.get("total_spawned", 0))
	stash = float(d.get("stash", 0.0))
	_respawn_clock = float(d.get("respawn_clock", def.respawn_time))
	_spawn_seq = int(d.get("spawn_seq", 0))
	_gun_cooldown = float(d.get("gun_cooldown", 0.0))
	arrived_at = float(d.get("arrived_at", arrived_at))
	_alert_until = float(d.get("alert_until", -1.0e9))
	_alert_line_at = float(d.get("alert_line_at", -1.0e9))
	SaveUtil.set_rng(_rng, d.get("rng", {}))
	if bool(d.get("dead", false)) and not dead:
		dead = true
		durability.hull = 0.0
		_apply_ruined_look()
		remove_from_group(Combat.GROUP)


## Durability (its tally links ships) and the spawn lists, after the ships exist.
func restore_ships(d: Dictionary, refs: SaveRefs) -> void:
	SaveUtil.set_durability(durability, d.get("durability", {}), refs)
	spawns.clear()
	raiders.clear()
	for id: int in d.get("spawns", []):
		var s := refs.ship(id) as ScavengerShip
		if s:
			spawns.append(s)
	for id: int in d.get("raiders", []):
		var s := refs.ship(id) as ScavengerShip
		if s:
			raiders.append(s)

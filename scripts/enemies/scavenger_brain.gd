class_name ScavengerBrain
extends RefCounted
## Scavenger decisions (no contracts, no captain):
## - ROAMING the den's belt (around the den, and toward the colony's mining
##   site when a contract is posted there);
## - HUNTING miners (salvagers too, and escape pods): prefers loaded,
##   unescorted ones within sensor range or on its belt near the den; shoots
##   them and steals [constant STEAL_SHARE] of the load once close or the
##   miner is disabled, then runs home;
## - ATTACKING whoever shoots at it;
## - FLEEING to the den when the hull drops below [constant FLEE_HULL]
##   (docks there and leaves the map with its loot);
## - RAIDING (raiders): fly at the colony and attack it in order: the
##   station shield bubble while it is up (nothing inside can be hit through
##   it), then the defense turrets, then the shield generator, then ships
##   near home; with nothing left to shoot, loot credits from a structure
##   until driven off.
## Targets inside an up shield bubble are never chased from outside: the
## bubble is attacked instead (raiders, retaliation) or the prey is skipped.
## Checks run on a timer ([constant AI_INTERVAL]).
## Warp hops (ShipMover): raiders hop toward the colony but drop out
## [constant RAID_WARP_DROP] short of it, so the raid warning still gives the
## player time; fleeing and returning scavengers hop home when no player gun
## is near. Roaming, hunting and fighting never warp.

enum State { LAUNCHING, ROAMING, HUNTING, ATTACKING, FLEEING, RAIDING, RETURNING }

const STATE_NAMES: PackedStringArray = ["Launching", "Roaming", "Hunting", "Attacking", "Fleeing", "Raiding", "Returning to hideout"]
const AI_INTERVAL := 0.5
const FLEE_HULL := 0.35
const STEAL_RANGE := 140.0
const STEAL_TIME := 2.5
const STEAL_SHARE := 0.5
const DISABLED_HULL := 0.35
## A miner with friendly guns this close counts as escorted, metres.
const ESCORT_RADIUS := 650.0
const RETALIATE_RANGE := 1000.0
## Raiders: looting a structure.
const RAID_ENGAGE_RADIUS := 2200.0
const RAID_LOOT_RANGE := 320.0
const RAID_LOOT_INTERVAL := 8.0
const RAID_LOOT_CREDITS := 15
const RAID_LOOT_MAX := 75
const ROAM_SPEED := 0.55
## Raiders drop out of a warp this far short of the colony, metres.
const RAID_WARP_DROP := 9000.0
const WARP_CLEAR := 1500.0

var ship: ScavengerShip
var state: State = State.LAUNCHING
var target: Node3D
var stolen_from: String = ""
var credits_looted: int = 0

var _ai_timer: float = 0.0
var _roam_point := Vector3.INF
var _steal_time: float = 0.0
var _loot_clock: float = 0.0
var _raid_target: Building
var _last_attacker: WeakRef
var _rng := RandomNumberGenerator.new()


func _init(owner_ship: ScavengerShip) -> void:
	ship = owner_ship
	_rng.randomize()
	_ai_timer = _rng.randf() * AI_INTERVAL
	if ship.is_raider:
		state = State.RAIDING


func get_status_text() -> String:
	match state:
		State.HUNTING:
			if _steal_time > 0.0:
				return "Stealing cargo"
			return "Hunting %s" % _name_of(target)
		State.ATTACKING:
			return "Attacking %s" % _name_of(target)
		State.FLEEING:
			return "Fleeing with loot" if ship.loot > 0.0 else "Fleeing"
		State.RAIDING:
			if Combat.is_live_target(target):
				return "Raiding, attacking %s" % _name_of(target)
			if is_instance_valid(_raid_target):
				return "Raiding %s" % _raid_target.display_name
			return "Raiding"
	return STATE_NAMES[state]


func can_warp() -> bool:
	if ship.durability.seconds_since_hit() < 5.0:
		return false
	match state:
		State.RAIDING:
			return not Combat.is_live_target(target)
		State.FLEEING, State.RETURNING:
			return Combat.nearest_hostile(ship.get_tree(), ship.global_position, WARP_CLEAR, ship.faction) == null
	return false


## May the ship fly its own cruise arc (Ship.cruise_band)? Roaming,
## heading home and on the raid approach; hunting and fights fly straight.
func cruise_free() -> bool:
	match state:
		State.ROAMING, State.RETURNING:
			return true
		State.RAIDING:
			return not Combat.is_live_target(target) and is_instance_valid(_raid_target) \
					and Combat.flat_distance(ship.global_position, _raid_target.global_position) > RAID_LOOT_RANGE * 3.0
	return false


func warp_drop() -> float:
	return RAID_WARP_DROP if state == State.RAIDING else SpaceNav.WARP_DROP


func destination_name() -> String:
	match state:
		State.RAIDING:
			return _raid_target.display_name if is_instance_valid(_raid_target) else "the colony"
		State.FLEEING, State.RETURNING:
			return ship.den.get_display_name() if is_instance_valid(ship.den) else ""
	return ""


func on_attacked(attacker: Node3D) -> void:
	if is_instance_valid(attacker):
		_last_attacker = weakref(attacker)


func update(dt: float) -> void:
	_ai_timer -= dt
	if _ai_timer <= 0.0:
		_ai_timer = AI_INTERVAL * _rng.randf_range(0.8, 1.2)
		_think()
	match state:
		State.LAUNCHING:
			_launch_step()
		State.ROAMING:
			_roam_step()
		State.HUNTING, State.ATTACKING:
			if Combat.is_live_target(target):
				ship.fight_step(target, ship.attack_side)
				if state == State.HUNTING:
					_steal_step(dt)
			else:
				target = null
				_set_state(State.RAIDING if ship.is_raider else State.ROAMING)
		State.FLEEING, State.RETURNING:
			_return_step()
		State.RAIDING:
			_raid_step(dt)


# --- Thinking -------------------------------------------------------------------

func _think() -> void:
	var den_alive := is_instance_valid(ship.den) and ship.den.is_alive()
	if state != State.FLEEING and state != State.RETURNING and ship.hull_fraction() < FLEE_HULL and den_alive:
		_set_state(State.FLEEING)
		target = null
		return
	if state == State.FLEEING or state == State.RETURNING:
		if not den_alive:
			# Nowhere to go: turn on the colony.
			ship.is_raider = true
			_set_state(State.RAIDING)
		return
	if state == State.LAUNCHING:
		return
	# Self-defence.
	var la := _last_attacker.get_ref() as Node3D if _last_attacker else null
	if Combat.is_live_target(la) and ship.durability.seconds_since_hit() < 4.0 and ship.global_position.distance_to(la.global_position) < RETALIATE_RANGE:
		if not (la is MinerShip):
			target = _through_shield(la)
			_set_state(State.ATTACKING)
			return
	if ship.is_raider:
		var t := _raid_pick()
		target = t
		if state != State.RAIDING:
			_set_state(State.RAIDING)
		return
	if state == State.ATTACKING and Combat.is_live_target(target) and ship.global_position.distance_to(target.global_position) < RETALIATE_RANGE * 1.4:
		target = _through_shield(target)
		return
	var prey := _pick_prey()
	if prey:
		if prey != target:
			_steal_time = 0.0
		target = prey
		_set_state(State.HUNTING)
	elif state == State.HUNTING or state == State.ATTACKING:
		target = null
		_set_state(State.ROAMING)


## Best miner to hunt, or null.
func _pick_prey() -> Ship:
	var tree := ship.get_tree()
	var pos := ship.global_position
	var den := ship.den if is_instance_valid(ship.den) else null
	var best: Ship = null
	var best_score := INF
	for n in tree.get_nodes_in_group(Ship.GROUP):
		var m := n as Ship
		if m == null or not (m is MinerShip or m is EscapePod) or not m.is_targetable():
			continue
		var d := pos.distance_to(m.global_position)
		var on_turf := false
		if den and den.belt:
			on_turf = Combat.flat_distance(den.global_position, m.global_position) < den.def.hunt_range \
					and SpaceNav.distance_to_belt(den.belt, m.global_position) < den.belt.def.width * 0.5 + 1500.0
		if d > ship.stats.sensor_range and not on_turf:
			continue
		if StationShield.shielding(tree, m.global_position, pos):
			continue
		var score := d
		if m is MinerShip and (m as MinerShip).is_loaded():
			score -= 1800.0
		elif m is EscapePod:
			score -= 600.0
		var escorts := _guns_near(m.global_position, ESCORT_RADIUS)
		score += 2500.0 * float(escorts)
		if m == target:
			score -= 400.0
		if score < best_score:
			best_score = score
			best = m
	return best


func _guns_near(pos: Vector3, radius: float) -> int:
	var n := 0
	for o in ship.get_tree().get_nodes_in_group(Ship.GROUP):
		var s := o as Ship
		if s and s.faction == Combat.Faction.PLAYER and s.weapon and s.is_targetable() and Combat.flat_distance(pos, s.global_position) < radius:
			n += 1
	return n


## Raid objective: the shield bubble while it is up (from outside), then the
## nearest turret, then the shield generator, then the nearest ship.
func _raid_pick() -> Node3D:
	var tree := ship.get_tree()
	var pos := ship.global_position
	var sys := tree.get_first_node_in_group(SolarSystem.GROUP) as SolarSystem
	var home := sys.home_station.global_position if sys and sys.home_station else pos
	if Combat.flat_distance(pos, home) > RAID_ENGAGE_RADIUS * 2.0:
		return null
	var bubble := StationShield.find(tree)
	if bubble and bubble.is_up() and not bubble.contains(pos):
		return bubble
	# Nearest first (hostiles_near sorts by distance).
	var near := Combat.hostiles_near(tree, pos, RAID_ENGAGE_RADIUS, ship.faction)
	for h in near:
		if h is DefenseTurret:
			return h
	for h in near:
		if h is ShieldGenerator:
			return h
	for h in near:
		if h is Ship:
			return h
	return null


## [param t], or the shield bubble when it stands between us and [param t].
func _through_shield(t: Node3D) -> Node3D:
	var bubble := StationShield.shielding(ship.get_tree(), t.global_position, ship.global_position)
	return bubble if bubble else t


# --- Steps ---------------------------------------------------------------------

func _launch_step() -> void:
	var den := ship.den
	if not is_instance_valid(den):
		_set_state(State.ROAMING)
		return
	var out := den.get_mouth_position() + den.get_outward() * 260.0
	ship.set_world_goal(out, Vector3.ZERO, Vector3.ZERO, 40.0, ship.max_speed * 0.5)
	if ship.global_position.distance_to(out) < 80.0:
		_set_state(State.RAIDING if ship.is_raider else State.ROAMING)


func _roam_step() -> void:
	if _roam_point == Vector3.INF or Combat.flat_distance(ship.global_position, _roam_point) < 120.0:
		_roam_point = _pick_roam_point()
	ship.set_world_goal(_roam_point, Vector3.ZERO, Vector3.ZERO, 80.0, ship.max_speed * ROAM_SPEED)


func _pick_roam_point() -> Vector3:
	var den := ship.den
	if not is_instance_valid(den) or den.belt == null:
		return ship.global_position + Vector3(_rng.randf_range(-800.0, 800.0), 0.0, _rng.randf_range(-800.0, 800.0))
	var belt := den.belt
	var base_angle := atan2(den.global_position.z, den.global_position.x)
	var arc := deg_to_rad(den.def.roam_arc_deg)
	var angle := base_angle + _rng.randf_range(-arc, arc)
	# Prowl toward the colony's mining site on this belt now and then.
	if _rng.randf() < 0.4:
		for c in ContractBoard.get_available(Contract.Type.MINING):
			var mc := c as MiningContract
			if mc and mc.belt == belt:
				var site := mc.get_site_position(_home_position())
				angle = atan2(site.z, site.x) + _rng.randf_range(-0.08, 0.08)
				break
	var r := belt.def.orbit_radius + _rng.randf_range(-0.35, 0.35) * belt.def.width
	return belt.global_position + Vector3(cos(angle), 0.0, sin(angle)) * r


func _steal_step(dt: float) -> void:
	var m := target as MinerShip
	if m == null or not m.is_loaded():
		_steal_time = 0.0
		return
	var close := ship.global_position.distance_to(m.global_position) < STEAL_RANGE
	if close or m.hull_fraction() < DISABLED_HULL:
		_steal_time += dt
	else:
		_steal_time = maxf(_steal_time - dt * 0.5, 0.0)
	if _steal_time < STEAL_TIME:
		return
	var taken := m.lose_cargo(STEAL_SHARE)
	ship.loot += taken
	stolen_from = m.get_display_name()
	_steal_time = 0.0
	EventLog.post("%s stole cargo from %s" % [ship.get_display_name(), stolen_from], EventLog.Kind.COMBAT, m)
	target = null
	_set_state(State.FLEEING)


func _return_step() -> void:
	var den := ship.den
	if not is_instance_valid(den) or not den.is_alive():
		return
	var mouth := den.get_mouth_position()
	var outside := mouth + den.get_outward() * 40.0
	ship.set_world_goal(outside, Vector3.ZERO, Vector3.ZERO, 30.0)
	if Combat.flat_distance(ship.global_position, outside) < 60.0 and absf(ship.global_position.y - outside.y) < 40.0:
		den.recall(ship)


func _raid_step(dt: float) -> void:
	if Combat.is_live_target(target):
		ship.fight_step(target, ship.attack_side)
		return
	if not is_instance_valid(_raid_target):
		_raid_target = _pick_raid_building()
		if _raid_target == null:
			_roam_step()
			return
	var bp := _raid_target.global_position
	var d := Combat.flat_distance(ship.global_position, bp)
	if d > RAID_LOOT_RANGE:
		ship.set_world_goal(bp, SpaceNav.world_velocity(_raid_target), Vector3.ZERO, RAID_LOOT_RANGE * 0.6)
		return
	# Circle the structure and skim credits off it.
	var around := (ship.global_position - bp)
	around.y = 0.0
	around = around.normalized() if around.length() > 1.0 else Vector3.RIGHT
	var orbit_pos := bp + around.rotated(Vector3.UP, 0.4 * ship.attack_side) * RAID_LOOT_RANGE * 0.7
	ship.set_world_goal(orbit_pos, SpaceNav.world_velocity(_raid_target), Vector3.ZERO, 20.0, ship.max_speed * 0.5)
	_loot_clock += dt
	if _loot_clock >= RAID_LOOT_INTERVAL:
		_loot_clock = 0.0
		var amount := mini(RAID_LOOT_CREDITS, maxi(Economy.credits, 0))
		if amount > 0:
			Economy.spend(amount)
			credits_looted += amount
			EventLog.post("Raiders are looting %s" % _raid_target.display_name, EventLog.Kind.THREAT, _raid_target)
		if credits_looted >= RAID_LOOT_MAX:
			_set_state(State.FLEEING)


func _pick_raid_building() -> Building:
	var mgr := ship.get_tree().get_first_node_in_group(BuildingManager.GROUP) as BuildingManager
	if mgr == null:
		return null
	var best: Building = null
	var best_d := INF
	for b in mgr.buildings:
		if not is_instance_valid(b):
			continue
		var d := Combat.flat_distance(ship.global_position, b.global_position)
		if d < best_d:
			best_d = d
			best = b
	return best


func _home_position() -> Vector3:
	var sys := ship.get_tree().get_first_node_in_group(SolarSystem.GROUP) as SolarSystem
	return sys.home_station.global_position if sys and sys.home_station else Vector3.ZERO


func _set_state(s: State) -> void:
	if state == s:
		return
	state = s
	ship.status_changed.emit(ship)


func _name_of(n: Variant) -> String:
	if is_instance_valid(n) and (n as Object).has_method(&"get_display_name"):
		return String((n as Object).call(&"get_display_name"))
	return "?"

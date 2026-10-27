class_name ScavengerBrain
extends RefCounted
## Raider decisions for every hostile faction (no contracts, no captain).
## The ship's [FactionDef] tunes them: prey (hunts_*), aggression (escort
## aversion, retaliation reach), flee threshold, steal share (0 = shoot to
## kill), packs and raid style. Scavenger values are the defaults below.
## - ROAMING around the den and the cluster drifting past it (toward the colony's mining
##   site when a contract is posted there);
## - HUNTING miners (salvagers too, and escape pods): prefers loaded,
##   unescorted ones within sensor range or at the cluster near the den; shoots
##   them and steals the faction's steal share of the load once close or the
##   miner is disabled, then runs home (factions that do not steal shoot
##   to kill; factions that hunt armed ships go for mercenaries in their
##   territory too);
## - PACKS: a wingman ([method set_lead]) flies beside its lead, hunts and
##   fights what the lead does and runs when it runs;
## - ATTACKING whoever shoots at it;
## - FLEEING to the den when the hull drops below the faction's flee_hull
##   (docks there and leaves the map with its loot);
## - RAIDING (raiders): fly at the raid's objective ([member raid_objective]:
##   an outpost, a cargo shuttle or the station itself, picked by the
##   RaidDirector) and attack the colony in order: the station shield bubble
##   while it is up (nothing inside can be hit through it), then the defense
##   turrets, then the shield generator, then the objective (a structure's
##   hull, StructureHull, or the shuttle), then shuttles and ships near home;
##   with nothing left to shoot (structures disabled), loot credits from a
##   structure until driven off. RaidStyle.STRUCTURES (the Syndicate) skips
##   the ships near home (unless they shoot) and shoots every structure's
##   hull, looting more.
## - DEFENDING a base under attack (ScavengerDen.call_defenders): fly back
##   and fight its attackers (ScavengerDen.defence_target); once the base's
##   alarm is over and nothing hostile is near it, back to roaming (or
##   raiding). Fleeing below the flee threshold still comes first.
## - GUARDING (planet garrison patrols, claim group escorts, PlanetClaims):
##   with a [member guard] set, roaming circles the guard (a planet or a
##   ship) between [member guard_inner] and [member guard_radius] and any
##   player ship inside the radius is prey. A guard that is gone, or a
##   base destroyed under a ship that guards ([member withdraw]), sends it
##   off the map with a warp flash once nothing is shooting at it.
## Targets inside an up shield bubble are never chased from outside: the
## bubble is attacked instead (raiders, retaliation) or the prey is skipped.
## Checks run on a timer ([constant AI_INTERVAL]).
## Warp hops (ShipMover): raiders hop toward the colony but drop out
## [constant RAID_WARP_DROP] short of it, so the raid warning still gives the
## player time; fleeing and returning scavengers hop home when no player gun
## is near. Roaming, hunting and fighting never warp.

enum State { LAUNCHING, ROAMING, HUNTING, ATTACKING, FLEEING, RAIDING, RETURNING, DEFENDING }

const STATE_NAMES: PackedStringArray = ["Launching", "Roaming", "Hunting", "Attacking", "Fleeing", "Raiding", "Returning to hideout", "Defending"]
## Defenders farther than this from their base may warp back, metres.
const DEFEND_WARP_DISTANCE := 4000.0
const AI_INTERVAL := 0.5
## Scavenger defaults (FactionDef.flee_hull, steal_share).
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
## Escort weight in prey scoring at aggression 0.5, metres per escort.
const ESCORT_PENALTY := 2500.0
## Landers (fast dropships on a raid, mostly out of the lanes) rank this much
## lower as prey, metres of distance.
const LANDER_PREY_PENALTY := 1500.0
## A wingman's slot beside its lead, metres.
const WING_OFFSET := 90.0
## Raiders drop out of a warp this far short of the colony, metres.
const RAID_WARP_DROP := 9000.0
const WARP_CLEAR := 1500.0

var ship: ScavengerShip
var fac: FactionDef
var state: State = State.LAUNCHING
var target: Node3D
var stolen_from: String = ""
var credits_looted: int = 0
## The base this ship is defending (DEFENDING).
var defend_den: ScavengerDen

## Guarding (see the class notes): what, how far out (metres from its centre).
var guard: Node3D
var guard_radius: float = 0.0
var guard_inner: float = 0.0
## Leaves the map once out of the fight (its garrison or charge is gone).
var withdraw: bool = false
var _guard_offset := Vector3.INF
var _guarding := false

var _ai_timer: float = 0.0
var _roam_point := Vector3.INF
var _steal_time: float = 0.0
var _loot_clock: float = 0.0
var _raid_target: Building
## What this raid came for: a Building, a CargoShuttle or the station's
## StructureHull (null = the nearest structure).
var raid_objective: Node3D
var _last_attacker: WeakRef
var _lead: WeakRef
var _rng := RandomNumberGenerator.new()


func _init(owner_ship: ScavengerShip) -> void:
	ship = owner_ship
	fac = ship.faction_def if ship.faction_def else Factions.scavengers()
	_rng.randomize()
	_ai_timer = _rng.randf() * AI_INTERVAL
	if ship.is_raider:
		state = State.RAIDING


## Flies as [param leader]'s wingman (packs).
func set_lead(leader: ScavengerShip) -> void:
	_lead = weakref(leader) if leader and leader != ship else null


## The live lead of this wingman, or null.
func lead() -> ScavengerShip:
	var l := _lead.get_ref() as ScavengerShip if _lead else null
	return l if l and not l.dead and l.is_inside_tree() and l.ai else null


## Sets the raid's objective (see [member raid_objective]).
func set_raid_objective(t: Node3D) -> void:
	raid_objective = t
	if t is Building:
		_raid_target = t as Building


## The objective's name, or "" when there is none (any more).
func objective_name() -> String:
	if not is_instance_valid(raid_objective):
		return ""
	if raid_objective is Building:
		return (raid_objective as Building).display_name
	return Combat.name_of(raid_objective, "?")


## The objective's combatant: a building's hull, the shuttle, the station
## hull. Null when it cannot be shot now.
func _objective_combatant() -> Node3D:
	if not is_instance_valid(raid_objective):
		return null
	var c: Node3D = raid_objective
	if raid_objective is Building:
		c = (raid_objective as Building).get_hull()
	return c if Combat.is_live_target(c) else null


func get_status_text() -> String:
	match state:
		State.RETURNING:
			return "Returning to %s" % fac.den_kind.get_slice(" ", fac.den_kind.get_slice_count(" ") - 1)
		State.ROAMING:
			if withdraw:
				return "Withdrawing"
			if is_guarding():
				return ("Escorting %s" % Combat.name_of(guard, "?")) if guard is Ship else ("Guarding %s" % _guard_name())
			return "Patrolling" if fac.hunts_armed else ("Flying wing" if lead() else "Roaming")
		State.HUNTING:
			if _steal_time > 0.0:
				return "Stealing cargo"
			return "Hunting %s" % Combat.name_of(target, "?")
		State.ATTACKING:
			return "Attacking %s" % Combat.name_of(target, "?")
		State.DEFENDING:
			var dn := defend_den.get_display_name() if is_instance_valid(defend_den) else "its base"
			return "Defending %s, attacking %s" % [dn, Combat.name_of(target, "?")] if Combat.is_live_target(target) else "Flying back to defend %s" % dn
		State.FLEEING:
			return "Fleeing with loot" if ship.loot > 0.0 else "Fleeing"
		State.RAIDING:
			if Combat.is_live_target(target):
				return "Raiding, attacking %s" % Combat.name_of(target, "?")
			var obj := objective_name()
			if not obj.is_empty():
				return "Raiding %s" % obj
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
			return ship.nearest_hostile(WARP_CLEAR) == null
		State.DEFENDING:
			return is_instance_valid(defend_den) and ship.global_position.distance_to(defend_den.global_position) > DEFEND_WARP_DISTANCE \
					and ship.nearest_hostile(WARP_CLEAR) == null
	return false


## May the ship fly its own cruise arc (Ship.cruise_band)? Roaming,
## heading home and on the raid approach; hunting and fights fly straight.
func cruise_free() -> bool:
	match state:
		State.ROAMING, State.RETURNING:
			return true
		State.RAIDING:
			var goal := _raid_goal()
			return not Combat.is_live_target(target) and goal != null \
					and SpaceNav.flat_distance(ship.global_position, goal.global_position) > RAID_LOOT_RANGE * 3.0
	return false


func warp_drop() -> float:
	return RAID_WARP_DROP if state == State.RAIDING else SpaceNav.WARP_DROP


func destination_name() -> String:
	match state:
		State.RAIDING:
			var obj := objective_name()
			if not obj.is_empty():
				return obj
			return _raid_target.display_name if is_instance_valid(_raid_target) else "the colony"
		State.FLEEING, State.RETURNING:
			return ship.den.get_display_name() if is_instance_valid(ship.den) else ""
		State.DEFENDING:
			return defend_den.get_display_name() if is_instance_valid(defend_den) else ""
	return ""


func on_attacked(attacker: Node3D) -> void:
	if is_instance_valid(attacker):
		_last_attacker = weakref(attacker)


## [param den] is under attack: come back and fight for it. False when this
## ship cannot (fleeing home, too damaged, already on it).
func defend(den: ScavengerDen) -> bool:
	if not is_instance_valid(den) or not den.is_alive() or ship.dead:
		return false
	if state == State.FLEEING or state == State.RETURNING or ship.hull_fraction() < fac.flee_hull:
		return false
	if state == State.DEFENDING and defend_den == den:
		return false
	defend_den = den
	_steal_time = 0.0
	target = den.defence_target()
	_set_state(State.DEFENDING)
	_ai_timer = 0.0
	return true


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
		State.DEFENDING:
			_defend_step()


# --- Thinking -------------------------------------------------------------------

## Guards [param node] (see the class notes).
func set_guard(node: Node3D, radius: float, inner: float = 0.0) -> void:
	guard = node
	guard_radius = radius
	guard_inner = inner
	_guarding = node != null
	_guard_offset = Vector3.INF


func is_guarding() -> bool:
	return _guarding and is_instance_valid(guard) and guard.is_inside_tree() and not (guard is Ship and (guard as Ship).dead)


## Withdrawing and clear of the fight: warps out. True when it left.
func _withdraw_step() -> bool:
	if ship.durability.seconds_since_hit() < 6.0:
		return false
	if ship.nearest_hostile(1200.0) != null:
		return false
	WarpFx.flash(ship, ship.global_position, 30.0)
	ship.leave_map()
	return true


func _think() -> void:
	if _guarding and not is_guarding():
		_guarding = false
		guard = null
		withdraw = true
	if withdraw and _withdraw_step():
		return
	var den_alive := is_instance_valid(ship.den) and ship.den.is_alive()
	if state != State.FLEEING and state != State.RETURNING and ship.hull_fraction() < fac.flee_hull and den_alive:
		_set_state(State.FLEEING)
		target = null
		return
	if state == State.FLEEING or state == State.RETURNING:
		if not den_alive:
			if withdraw or _guarding:
				# A garrison's ship with its base gone: leaves instead.
				withdraw = true
				_set_state(State.ROAMING)
				return
			# Nowhere to go: turn on the colony.
			ship.is_raider = true
			_set_state(State.RAIDING)
		return
	if state == State.LAUNCHING:
		return
	if state == State.DEFENDING:
		_defend_think()
		return
	# Self-defence.
	var la := _last_attacker.get_ref() as Node3D if _last_attacker else null
	if Combat.is_live_target(la) and ship.durability.seconds_since_hit() < 4.0 and ship.global_position.distance_to(la.global_position) < _retaliate_range():
		if not (la is MinerShip):
			target = _through_shield(la)
			_set_state(State.ATTACKING)
			return
	if withdraw:
		# Only fights back (above) on the way out.
		if state == State.HUNTING or state == State.ATTACKING:
			target = null
			_set_state(State.ROAMING)
		return
	if ship.is_raider:
		var t := _raid_pick()
		target = t
		if state != State.RAIDING:
			_set_state(State.RAIDING)
		return
	if state == State.ATTACKING and Combat.is_live_target(target) and ship.global_position.distance_to(target.global_position) < _retaliate_range() * 1.4:
		target = _through_shield(target)
		return
	if _follow_lead():
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


func _retaliate_range() -> float:
	return RETALIATE_RANGE * 2.0 * fac.aggression


## Wingman: take the lead's fight or flight. True when it decided.
func _follow_lead() -> bool:
	var l := lead()
	if l == null:
		return false
	match l.ai.state:
		State.FLEEING, State.RETURNING:
			target = null
			_set_state(State.FLEEING)
			return true
		State.HUNTING, State.ATTACKING:
			if Combat.is_live_target(l.ai.target):
				if l.ai.target != target:
					_steal_time = 0.0
				target = _through_shield(l.ai.target)
				_set_state(l.ai.state)
				return true
	if state == State.HUNTING or state == State.ATTACKING:
		target = null
		_set_state(State.ROAMING)
	return true


## Is [param s] prey for this faction?
func _is_prey(s: Ship) -> bool:
	if s is MobileStation:
		# A forward station on its way: every faction goes for it.
		return true
	if s is EscapePod:
		return fac.hunts_pods
	if s is SalvagerShip:
		return fac.hunts_salvagers
	if s is MinerShip or s is ExplorerShip:
		return fac.hunts_miners
	return fac.hunts_armed and s.faction == Combat.Faction.PLAYER and s.weapon != null and s.role == Ship.Role.MERCENARY


## Best prey to hunt, or null.
func _pick_prey() -> Ship:
	if is_guarding():
		return _guard_prey()
	var pos := ship.global_position
	var den := ship.den if is_instance_valid(ship.den) else null
	# The cluster in the base's reach right now (they drift past).
	var turf: AsteroidCluster = den.belt if den else null
	var best: Ship = null
	var best_score := INF
	for n in SystemWorld.nodes_in(ship, Ship.GROUP):
		var m := n as Ship
		if m == null or not m.is_targetable() or not _is_prey(m):
			continue
		var armed := m.weapon != null and not (m is MinerShip)
		var d := pos.distance_to(m.global_position)
		var on_turf := false
		if turf:
			on_turf = SpaceNav.flat_distance(den.global_position, m.global_position) < den.def.hunt_range \
					and (armed or turf.distance_to(m.global_position) < 1500.0)
		if d > ship.stats.sensor_range and not on_turf:
			continue
		if StationShield.shielding(ship, m.global_position, pos):
			continue
		var score := d
		if m is MinerShip and (m as MinerShip).is_loaded():
			score -= 1800.0
		elif m is EscapePod:
			score -= 600.0
		if m is LanderShip:
			score += LANDER_PREY_PENALTY
		var escorts := _guns_near(m.global_position, ESCORT_RADIUS) - (1 if armed else 0)
		score += ESCORT_PENALTY * 2.0 * (1.0 - fac.aggression) * float(maxi(escorts, 0))
		if m == target:
			score -= 400.0
		if score < best_score:
			best_score = score
			best = m
	return best


## Guarding: the player ship nearest this one inside the guard radius
## (any kind but cargo shuttles and pods), or null.
func _guard_prey() -> Ship:
	var c := guard.global_position
	var best: Ship = null
	var best_d := INF
	for n in SystemWorld.nodes_in(ship, Ship.GROUP):
		var m := n as Ship
		if m == null or m.faction != Combat.Faction.PLAYER or not m.is_targetable() or m is CargoShuttle or m is EscapePod:
			continue
		if m.global_position.distance_to(c) > guard_radius:
			continue
		if StationShield.shielding(ship, m.global_position, ship.global_position):
			continue
		var d := ship.global_position.distance_to(m.global_position) - (400.0 if m == target else 0.0)
		if d < best_d:
			best_d = d
			best = m
	return best


func _guns_near(pos: Vector3, radius: float) -> int:
	var n := 0
	for o in SystemWorld.nodes_in(ship, Ship.GROUP):
		var s := o as Ship
		if s and s.faction == Combat.Faction.PLAYER and s.weapon and s.is_targetable() and SpaceNav.flat_distance(pos, s.global_position) < radius:
			n += 1
	return n


## Raid target now: the shield bubble while it is up (from outside), then
## the nearest turret, then the shield generator, then the raid's objective,
## then a shuttle or ship near home (STRUCTURES: any structure's hull
## instead). Null = fly on to the objective / loot.
func _raid_pick() -> Node3D:
	var pos := ship.global_position
	var sys := SolarSystem.of(ship)
	var home := sys.home_station.global_position if sys and sys.home_station else pos
	if SpaceNav.flat_distance(pos, home) > RAID_ENGAGE_RADIUS * 2.0:
		# A shuttle out in space can be caught on the way in.
		var far := _objective_combatant()
		if far is CargoShuttle and pos.distance_to(far.global_position) < RAID_ENGAGE_RADIUS:
			return _through_shield(far)
		return null
	var bubble := StationShield.find(ship)
	if bubble and bubble.is_up() and not bubble.contains(pos):
		return bubble
	# Nearest first (hostiles_near sorts by distance).
	var near := Combat.hostiles_near(ship, pos, RAID_ENGAGE_RADIUS, ship.faction)
	for h in near:
		if h is DefenseTurret:
			return h
	for h in near:
		if h is ShieldGenerator:
			return h
	var obj := _objective_combatant()
	if obj and pos.distance_to(obj.global_position) < RAID_ENGAGE_RADIUS * 1.5:
		return _through_shield(obj)
	if fac.raid_style == FactionDef.RaidStyle.STRUCTURES:
		for h in near:
			if h is StructureHull:
				return h
		return null
	for h in near:
		if h is Ship:
			return h
	return null


## [param t], or the shield bubble when it stands between us and [param t].
func _through_shield(t: Node3D) -> Node3D:
	var bubble := StationShield.shielding(ship, t.global_position, ship.global_position)
	return bubble if bubble else t


## Defending: the base's attacker (or whoever shoots this ship near the
## base), until the alarm is over and the base is clear.
func _defend_think() -> void:
	var den := defend_den
	if not is_instance_valid(den) or not den.is_alive():
		_end_defence()
		return
	var t := den.defence_target()
	var la := _last_attacker.get_ref() as Node3D if _last_attacker else null
	if t == null and Combat.is_live_target(la) and ship.durability.seconds_since_hit() < 4.0 \
			and den.global_position.distance_to(la.global_position) < ScavengerDen.GUARD_RADIUS * 1.5:
		t = la
	if t:
		target = t
	elif not den.is_alerted():
		_end_defence()
	else:
		target = null


func _end_defence() -> void:
	defend_den = null
	target = null
	_set_state(State.RAIDING if ship.is_raider else State.ROAMING)


# --- Steps ---------------------------------------------------------------------

func _defend_step() -> void:
	if Combat.is_live_target(target):
		ship.fight_step(target, ship.attack_side)
		return
	var den := defend_den
	if not is_instance_valid(den):
		return
	# Hold off the mouth until something comes near.
	var guard := den.get_mouth_position() + den.get_outward() * 300.0
	ship.set_world_goal(guard, Vector3.ZERO, Vector3.ZERO, 60.0)



func _launch_step() -> void:
	var den := ship.den
	if not is_instance_valid(den):
		_set_state(State.ROAMING)
		return
	var out := den.get_mouth_position() + den.get_outward() * 260.0
	ship.set_world_goal(out, Vector3.ZERO, Vector3.ZERO, 40.0, ship.max_speed * 0.5)
	# Flat: in open space the ship holds its lane height, not the mouth's.
	if SpaceNav.flat_distance(ship.global_position, out) < 80.0:
		_set_state(State.RAIDING if ship.is_raider else State.ROAMING)


func _roam_step() -> void:
	var l := lead()
	if l:
		# Wingman: hold a slot beside the lead.
		var side := l.global_basis.x
		side.y = 0.0
		var slot := l.global_position + (side.normalized() if side.length() > 0.01 else Vector3.RIGHT) * WING_OFFSET * ship.attack_side
		ship.set_world_goal(slot, l.mover.velocity, Vector3.ZERO, 30.0, ship.max_speed)
		return
	if is_guarding():
		_guard_roam_step()
		return
	if withdraw:
		# Base gone, nothing to guard: hold still until it can warp out.
		ship.set_world_goal(ship.global_position, Vector3.ZERO, Vector3.ZERO, 200.0, ship.max_speed * 0.3)
		return
	if _roam_point == Vector3.INF or SpaceNav.flat_distance(ship.global_position, _roam_point) < 120.0:
		_roam_point = _pick_roam_point()
	ship.set_world_goal(_roam_point, Vector3.ZERO, Vector3.ZERO, 80.0, ship.max_speed * ROAM_SPEED)


func _guard_name() -> String:
	var body := guard as PlanetBody
	return body.def.name if body and body.def else Combat.name_of(guard, "?")


## Circles the guard: random points around it that ride along with it.
func _guard_roam_step() -> void:
	var c := guard.global_position
	var vel := (guard as Ship).get_world_velocity() if guard is Ship else SpaceNav.world_velocity(guard)
	if _guard_offset == Vector3.INF or ship.global_position.distance_to(c + _guard_offset) < (60.0 if guard is Ship else 140.0):
		var a := _rng.randf() * TAU
		if guard is Ship:
			_guard_offset = Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(120.0, 300.0) + Vector3.UP * _rng.randf_range(-40.0, 60.0)
		else:
			var lo := maxf(guard_inner, 200.0)
			var hi := maxf(guard_radius * 0.85, lo + 300.0)
			_guard_offset = Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(lo, hi) + Vector3.UP * _rng.randf_range(-250.0, 250.0)
	var speed := ship.max_speed if guard is Ship else ship.max_speed * ROAM_SPEED
	ship.set_world_goal(c + _guard_offset, vel, Vector3.ZERO, 40.0 if guard is Ship else 80.0, speed)


func _pick_roam_point() -> Vector3:
	var den := ship.den
	if not is_instance_valid(den):
		return ship.global_position + Vector3(_rng.randf_range(-800.0, 800.0), 0.0, _rng.randf_range(-800.0, 800.0))
	var belt := den.belt
	if belt and _rng.randf() < 0.6:
		# Prowl the cluster drifting past: the colony's mining site on it
		# now and then, else anywhere in the rocks.
		var c := belt.global_position
		var spot := Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)).limit_length(1.0) * belt.rock_half_width()
		var site := c + Vector3(spot.x, 0.0, spot.y)
		if _rng.randf() < 0.5:
			for con in ContractBoard.get_available(Contract.Type.MINING):
				var mc := con as MiningContract
				if mc and mc.belt == belt:
					site = mc.get_site_position(_home_position()) + Vector3(_rng.randf_range(-300.0, 300.0), 0.0, _rng.randf_range(-300.0, 300.0))
					break
		return Vector3(site.x, 0.0, site.z)
	# Around the base, along its orbit radius.
	var base_angle := atan2(den.global_position.z, den.global_position.x)
	var arc := deg_to_rad(den.def.roam_arc_deg)
	var angle := base_angle + _rng.randf_range(-arc, arc)
	var r := SpaceNav.flat_length(den.global_position) + _rng.randf_range(-1200.0, 1200.0)
	return Vector3(cos(angle), 0.0, sin(angle)) * r


func _steal_step(dt: float) -> void:
	var m := target as MinerShip
	if fac.steal_share <= 0.0 or m == null or not m.is_loaded():
		_steal_time = 0.0
		return
	var close := ship.global_position.distance_to(m.global_position) < STEAL_RANGE
	if close or m.hull_fraction() < DISABLED_HULL:
		_steal_time += dt
	else:
		_steal_time = maxf(_steal_time - dt * 0.5, 0.0)
	if _steal_time < STEAL_TIME:
		return
	var taken := m.lose_cargo(fac.steal_share)
	ship.loot += taken
	stolen_from = m.get_display_name()
	_steal_time = 0.0
	EventLog.post("%s stole cargo from %s" % [ship.get_display_name(), stolen_from], EventLog.Kind.COMBAT, m, Vector3.INF, "", fac.id)
	target = null
	_set_state(State.FLEEING)


func _return_step() -> void:
	var den := ship.den
	if not is_instance_valid(den) or not den.is_alive():
		return
	var mouth := den.get_mouth_position()
	var outside := mouth + den.get_outward() * 40.0
	ship.set_world_goal(outside, Vector3.ZERO, Vector3.ZERO, 30.0)
	if SpaceNav.flat_distance(ship.global_position, outside) < 60.0 and absf(ship.global_position.y - outside.y) < 40.0:
		den.recall(ship)


func _raid_step(dt: float) -> void:
	if Combat.is_live_target(target):
		ship.fight_step(target, ship.attack_side)
		return
	# Not a building (a shuttle, the station): fly at it until it can be shot
	# or is gone, then loot the nearest structure.
	var obj := _objective_combatant()
	if obj and not (raid_objective is Building):
		ship.set_world_goal(obj.global_position, SpaceNav.world_velocity(obj), Vector3.ZERO, RAID_LOOT_RANGE * 0.6)
		return
	if not is_instance_valid(_raid_target):
		_raid_target = _pick_raid_building()
		if _raid_target == null:
			_roam_step()
			return
	var bp := _raid_target.global_position
	var d := SpaceNav.flat_distance(ship.global_position, bp)
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
		var amount := mini(roundi(RAID_LOOT_CREDITS * fac.raid_loot_mult), maxi(Economy.credits, 0))
		if amount > 0:
			Economy.spend(amount, PackedInt32Array(), Ledger.OTHER, "Looted by raiders")
			credits_looted += amount
			var who := fac.raiders_label()
			EventLog.post("%s are looting %s" % [who, _raid_target.display_name], EventLog.Kind.THREAT, _raid_target, Vector3.INF, "", fac.id)
		if credits_looted >= roundi(RAID_LOOT_MAX * fac.raid_loot_mult):
			_set_state(State.FLEEING)


## Where the raid flies: the objective (or its building), else the structure to loot.
func _raid_goal() -> Node3D:
	if is_instance_valid(raid_objective) and not (raid_objective is Building) and _objective_combatant():
		return raid_objective
	return _raid_target if is_instance_valid(_raid_target) else null


func _pick_raid_building() -> Building:
	var mgr := BuildingManager.of(ship)
	if mgr == null:
		return null
	return Combat.nearest_of(mgr.buildings, ship.global_position) as Building


func _home_position() -> Vector3:
	var sys := SolarSystem.of(ship)
	return sys.home_station.global_position if sys and sys.home_station else Vector3.ZERO


func _set_state(s: State) -> void:
	if state == s:
		return
	state = s
	ship.status_changed.emit(ship)

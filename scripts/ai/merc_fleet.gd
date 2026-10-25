class_name MercFleet
extends RefCounted
## A group of mercenaries that band together for one bounty and split it.
##
## How strong a target is, in "default mercenaries needed" ([method need_for]):
## a den counts its hull and shields, its guns and the ships it has out
## (by their fighting power: they come home to defend it);
## a scavenger ship counts itself and the hostiles flying with it. Above
## [constant SOLO_NEED] (scaled by the merc's own ship) a bounty is too much
## for one ship. Then the merc (MercenaryEvaluator) either goes alone anyway
## (a lone wolf: high Nerve, low Teamwork, see Captain.daring), calls a fleet
## ([method call_fleet]), or refuses.
##
## Fleet size ([method assess]): enough ships, strongest free mercs first, for
## their combined power ([method power_of], summed) to reach
## [constant FLEET_POWER_SHARE] of the target's need, at least 2 and at most
## [constant MAX_SIZE] (and the contract's taker limit). A caller refuses
## when the free mercs cannot reach it ("Needs about 5 mercenaries, 3
## available") or when even a full fleet of mercs like the hired ones could
## not ("Too dangerous for the current fleet"); the target panel shows the
## same estimate.
##
## Life of a fleet:
## - FORMING: the caller waits at a rally point off the Home Station, toward
##   the target, and invites idle and patrolling mercs every
##   [constant INVITE_INTERVAL] (each says yes or no once, by Teamwork,
##   personality, their share, Grudge, distance, and how far the fleet's
##   power covers the need). Others that look at the contract may join too.
##   It takes more members than planned while it is still too weak. It
##   leaves when everyone wanted is at the rally point (or the members there
##   are strong enough), or after [constant FORM_WAIT] when strong enough;
##   still too weak after [constant FORM_WAIT_MAX] (or alone) it falls
##   apart. The leader is picked at departure by rank, then Nerve.
## - EN_ROUTE: the leader flies at the slowest member's pace (on its own
##   cruise arc, Ship.cruise_band), wingmen hold 3D offset slots behind it
##   ([method slot_offset]: left wing above, right wing below).
## - ENGAGING: inside [constant ENGAGE_RANGE] everyone shoots the fleet's
##   focus target (whoever is shooting at the fleet, else the bounty).
## - RETREATING: the leader breaks it off when the fleet's hull runs low
##   while the target still stands; everyone goes home together. Members
##   still retreat alone at their own hull threshold (they "fled early").
## The split ([method split]): [constant RANK_WEIGHT] of it by rank, the rest
## by damage done to the target; members who left early get
## [constant FLED_SHARE] of their weight, the lost get nothing. The parts
## always add up to the reward.

signal changed(fleet: MercFleet)

enum State { FORMING, EN_ROUTE, ENGAGING, RETREATING, DONE }

const STATE_NAMES: PackedStringArray = ["forming", "en route", "engaging", "breaking off", "done"]
## Above this need (default mercs), a bounty is too strong to take alone.
const SOLO_NEED := 1.3
const MAX_SIZE := 6
## A fleet sets out once its combined power covers this share of the need.
const FLEET_POWER_SHARE := 0.8
## Den hull plus shields one default mercenary is worth.
const DEN_EHP_PER_MERC := 2000.0
const DEN_GUN_NEED := 0.5
## Gun need of a den with [constant REF_DEN_GUN_DPS] of point defence (a
## Scavenger Hideout's); other factions scale by their guns.
const REF_DEN_GUN_DPS := 12.0
## Each hostile flying with a ship target. A den's own ships count by their
## fighting power ([method power_of], times 1 + their dodge chance): they
## come home to defend it (ScavengerDen.call_defenders), at
## [constant DEN_SHIP_NEED] each (they arrive one by one and some flee).
const ESCORT_NEED := 0.5
const DEN_SHIP_NEED := 0.6
const ESCORT_RADIUS := 900.0
## Reference default mercenary: hull plus shields, and damage per second.
const REF_EHP := 560.0
const REF_DPS := 57.6
## Rally point distance from the Home Station toward the target, metres.
const RALLY_DISTANCE := 700.0
const RALLY_RADIUS := 300.0
## Sim seconds a forming fleet waits for its members; past
## [constant FORM_WAIT_MAX] a fleet still too weak falls apart.
const FORM_WAIT := 55.0
const FORM_WAIT_MAX := 120.0
const INVITE_INTERVAL := 6.0
## A merc that said no is asked again after this many sim seconds.
const DECLINE_MEMORY := 40.0
## The fleet engages inside this distance of the target, metres.
const ENGAGE_RANGE := 1800.0
## Formation slots: side and back offsets per row, metres.
const SLOT_SIDE := 45.0
const SLOT_BACK := 38.0
## Formation slots: height per row (left above the leader, right below), metres.
const SLOT_RISE := 18.0
## Wingmen farther than this from their slot slow the leader down, metres.
const STRAGGLE_DISTANCE := 260.0
## Hostiles shooting at the fleet this close to the leader are focused first.
const FOCUS_RANGE := 900.0
## Share of the split by rank (the rest by damage done).
const RANK_WEIGHT := 0.4
const FLED_SHARE := 0.5
## The leader breaks off when the fleet's mean hull drops this far above
## its own retreat level while the target is above [constant RETREAT_TARGET_HULL].
const RETREAT_MARGIN := 0.12
const RETREAT_TARGET_HULL := 0.35

var contract: BountyContract
var leader: Ship
## Current members, leader first.
var members: Array[Ship] = []
## Everyone who flew in it: instance id -> {ref: WeakRef, name, rank, left_early, lost}.
var roster: Dictionary = {}
var state: State = State.FORMING
## Members wanted before it leaves.
var wanted: int = 2
var called_at: float = 0.0
var leader_name: String = ""
## What every member shoots while engaging.
var focus: Node3D
## Instance id of a merc that said no -> SimClock.time it did. Asked again
## after [constant DECLINE_MEMORY] s while the fleet still needs ships.
var declined: Dictionary = {}

var _next_invite: float = 0.0
var _last_tick: float = -1.0


# --- Strength ------------------------------------------------------------------

## Fighting power of [param ship] against the default mercenary (1.0).
static func power_of(ship: Ship) -> float:
	if ship == null or ship.stats == null:
		return 1.0
	var ehp := ship.stats.max_hull + ship.stats.max_shields
	var dps := ship.stats.dps()
	return clampf(sqrt(ehp / REF_EHP * maxf(dps, 1.0) / REF_DPS), 0.3, 4.0)


## Default mercenaries [param target] is worth.
static func target_need(target: Node3D) -> float:
	if not Combat.is_live(target):
		return 0.0
	if target is ScavengerDen:
		var den := target as ScavengerDen
		var ehp := den.durability.hull + den.durability.shields
		var need := ehp / DEN_EHP_PER_MERC + DEN_GUN_NEED * den.faction_def.den_gun_dps() / REF_DEN_GUN_DPS
		for s in den.spawns:
			if is_instance_valid(s) and not s.dead and s.stats:
				# Its ships come home to defend it: each by its fighting power (dodgers more).
				need += DEN_SHIP_NEED * power_of(s) * (1.0 + s.stats.dodge)
		return need
	var need := 0.6
	var d := target.get(&"durability") as Durability
	if d:
		need = (d.hull + d.shields) / REF_EHP
	if target.is_inside_tree():
		var near := Combat.hostiles_near(target.get_tree(), target.global_position, ESCORT_RADIUS, Combat.Faction.PLAYER)
		need += ESCORT_NEED * float(maxi(near.size() - 1, 0))
	return need


## Mercenaries like [param ship] needed for [param contract]'s target.
static func need_for(contract: Contract, ship: Ship) -> float:
	return target_need(contract.target) / power_of(ship)


## Fleet size wanted for [param need] default mercs, capped by the
## contract's taker limit (no ships known: one per default merc).
static func size_for(need: float, contract: Contract) -> int:
	return clampi(ceili(need * FLEET_POWER_SHARE - 0.05), 2, cap_for(contract))


## Most ships a fleet on [param contract] takes.
static func cap_for(contract: Contract) -> int:
	return MAX_SIZE if contract.max_takers <= 0 else clampi(contract.max_takers, 2, MAX_SIZE)


## How a fleet on [param contract] would stand now, seen by [param asker]
## (counted as free): {need (default mercs), goal (power to reach), wanted
## (ships), available (free mercs: idle or patrolling and repaired, the
## asker, members already in), power (the best [code]wanted[/code] of them),
## estimate (ships like the hired ones needed), enough, too_strong (even
## [method cap_for] ships like those could not), text}.
static func assess(contract: BountyContract, asker: Ship = null) -> Dictionary:
	var need := target_need(contract.target)
	var goal := need * FLEET_POWER_SHARE
	var cap := cap_for(contract)
	var tree: SceneTree = null
	if asker and asker.is_inside_tree():
		tree = asker.get_tree()
	elif Combat.is_live(contract.target) and contract.target.is_inside_tree():
		tree = contract.target.get_tree()
	var free: Array[float] = []
	var hired_sum := 0.0
	var hired := 0
	if tree:
		for n in tree.get_nodes_in_group(Ship.GROUP):
			var s := n as Ship
			var mb := s.brain as MercenaryBrain if s else null
			if mb == null or s.dead:
				continue
			var p := power_of(s)
			hired_sum += p
			hired += 1
			var member := contract.fleet != null and contract.fleet.members.has(s)
			if s == asker or member or mb.can_answer_fleet():
				free.append(p)
	free.sort()
	free.reverse()
	var avg := hired_sum / float(hired) if hired > 0 else 1.0
	var estimate := maxi(ceili(goal / maxf(avg, 0.3) - 0.05), 2)
	var wanted := 0
	var power := 0.0
	for i in mini(free.size(), cap):
		power += free[i]
		if power >= goal and i >= 1:
			wanted = i + 1
			break
	var enough := wanted > 0
	if not enough:
		wanted = clampi(estimate, 2, cap)
	var too_strong := not enough and estimate > cap
	var text := ""
	if too_strong:
		text = "Too dangerous for the current fleet: needs about %d mercenaries like yours, at most %d fly together" % [estimate, cap]
	elif not enough:
		text = "Needs about %d mercenaries, %d available" % [maxi(estimate, wanted), free.size()]
	else:
		text = "A fleet of %d can take it (power %.1f of %.1f needed)" % [wanted, power, goal]
	return {"need": need, "goal": goal, "wanted": wanted, "available": free.size(), "power": power, "estimate": estimate,
			"enough": enough, "too_strong": too_strong, "text": text}


## Combined power of the members (default mercs).
func power() -> float:
	var p := 0.0
	for m in members:
		if is_instance_valid(m) and not m.dead:
			p += power_of(m)
	return p


## True when the members are strong enough to set out.
func strong_enough(share: float = 1.0) -> bool:
	return power() >= target_need(contract.target) * FLEET_POWER_SHARE * share


# --- Forming -------------------------------------------------------------------

## [param caller] (already a taker of [param bounty]) calls a fleet of
## [param size] ships (0 = by [method assess]).
static func call_fleet(bounty: BountyContract, caller: Ship, size: int = 0) -> MercFleet:
	var f := MercFleet.new()
	f.contract = bounty
	f.wanted = clampi(size if size > 0 else int(assess(bounty, caller)["wanted"]), 2, cap_for(bounty))
	f.called_at = SimClock.time
	f._next_invite = SimClock.time
	bounty.fleet = f
	f._add_member(caller)
	f.leader = caller
	f.leader_name = caller.get_display_name()
	EventLog.post("%s calls a fleet for %s (%d ships wanted)" % [caller.get_display_name(), bounty.get_target_name(), f.wanted],
			EventLog.Kind.COMBAT, caller)
	f.invite(caller.get_tree())
	return f


## True while it still takes members: short of the planned size, or still
## too weak (up to the cap).
func is_recruiting() -> bool:
	if state != State.FORMING:
		return false
	return members.size() < wanted or (members.size() < cap_for(contract) and not strong_enough())


## Adds [param ship] (already a taker of the contract). False when full.
func join(ship: Ship) -> bool:
	if not is_recruiting() or members.has(ship):
		return false
	_add_member(ship)
	EventLog.post("%s joins %s's fleet for %s (%d/%d)" % [ship.get_display_name(), leader_name, contract.get_target_name(), members.size(), wanted],
			EventLog.Kind.COMBAT, ship)
	changed.emit(self)
	return true


func _add_member(ship: Ship) -> void:
	members.append(ship)
	var mb := ship.brain as MercenaryBrain
	if mb:
		mb.fleet = self
	roster[ship.get_instance_id()] = {"ref": weakref(ship), "name": ship.get_display_name(),
			"rank": ship.captain.rank if ship.captain else 0, "left_early": false, "lost": false}


## Asks the idle and patrolling mercs, once each.
func invite(tree: SceneTree) -> void:
	if tree == null or not is_recruiting():
		return
	var candidates: Array[MercenaryBrain] = []
	for n in tree.get_nodes_in_group(Ship.GROUP):
		var s := n as Ship
		var mb := s.brain as MercenaryBrain if s else null
		if mb == null or s.dead or members.has(s) or has_declined(s) or not mb.can_answer_fleet():
			continue
		candidates.append(mb)
	# Nearest first.
	var rp := rally_point()
	candidates.sort_custom(func(a: MercenaryBrain, b: MercenaryBrain) -> bool:
		return Combat.flat_distance(a.ship.global_position, rp) < Combat.flat_distance(b.ship.global_position, rp))
	for mb in candidates:
		if not is_recruiting():
			return
		var e := (mb.evaluator as MercenaryEvaluator).evaluate_fleet_join(mb, self)
		if e.accept:
			mb.join_fleet(self, e)
		else:
			declined[mb.ship.get_instance_id()] = SimClock.time
			mb.decline_fleet(self, e.reason, e)


## [param ship] said no to this fleet less than [constant DECLINE_MEMORY] s ago.
func has_declined(ship: Ship) -> bool:
	var at: Variant = declined.get(ship.get_instance_id())
	return at != null and SimClock.time - float(at) < DECLINE_MEMORY


## Credits one more member could expect (equal share).
func share_for_next() -> float:
	return float(contract.reward) / float(members.size() + 1)


# --- Update --------------------------------------------------------------------

## Advances the fleet. Every member calls it; it runs once per sim time.
func update() -> void:
	var now := SimClock.time
	if now == _last_tick or state == State.DONE:
		return
	_last_tick = now
	_prune()
	if contract.is_finished() or not Combat.is_live(contract.target):
		_set_state(State.DONE)
		return
	if members.is_empty():
		disband("")
		return
	match state:
		State.FORMING:
			if now >= _next_invite:
				_next_invite = now + INVITE_INTERVAL
				invite(leader.get_tree() if is_instance_valid(leader) else null)
			var strong := strong_enough()
			var all_in := members.size() >= 2 and (members.size() >= wanted or strong)
			if all_in:
				for m in members:
					if m.is_docked() or m.global_position.distance_to(rally_point()) > RALLY_RADIUS:
						all_in = false
						break
			var waited := now - called_at
			if members.size() >= 2 and (all_in or (waited > FORM_WAIT and strong)):
				_depart()
			elif waited > FORM_WAIT_MAX:
				if members.size() >= 2 and strong_enough(0.85):
					_depart()
				elif members.size() < 2:
					disband("No one answered %s's call for %s" % [leader_name, contract.get_target_name()])
				else:
					disband("Not enough mercenaries answered %s's call for %s: fleet power %.1f, it needs about %.1f" % [leader_name,
							contract.get_target_name(), power(), target_need(contract.target) * FLEET_POWER_SHARE])
		State.EN_ROUTE:
			if is_instance_valid(leader) and leader.global_position.distance_to(contract.target.global_position) < ENGAGE_RANGE:
				_set_state(State.ENGAGING)
				EventLog.post("%s's fleet (%d) engages %s" % [leader_name, members.size(), contract.get_target_name()], EventLog.Kind.COMBAT, leader)
		State.ENGAGING:
			focus = _pick_focus()
			_check_retreat()


func _depart() -> void:
	_pick_leader()
	declined.clear()
	_set_state(State.EN_ROUTE)
	var names: PackedStringArray = []
	for m in members:
		names.append(m.get_display_name())
	for m in members:
		if m.brain:
			m.brain.note(CaptainLog.Kind.FLEET, CaptainLog.Outcome.DID, "Set out in a fleet of %d for %s, as %s" % [members.size(), contract.get_target_name(), role_of(m)],
					"Leader by rank, then Nerve: %s" % leader_name, ", ".join(names))
	EventLog.post("%s's fleet (%d) sets out for %s: %s" % [leader_name, members.size(), contract.get_target_name(), ", ".join(names)],
			EventLog.Kind.COMBAT, leader)


## Leader: highest rank, then Nerve.
func _pick_leader() -> void:
	var best: Ship = null
	var best_score := -INF
	for m in members:
		var c := m.captain
		var score := (float(c.rank) * 10.0 + float(c.effective_nerve())) if c else 0.0
		if score > best_score:
			best_score = score
			best = m
	if best:
		leader = best
		leader_name = best.get_display_name()
		members.erase(best)
		members.insert(0, best)


## Whoever is shooting at the fleet near the leader, else the bounty target.
func _pick_focus() -> Node3D:
	var target := contract.target
	if not is_instance_valid(leader):
		return target
	var lp := leader.global_position
	var best: Node3D = null
	var best_d := FOCUS_RANGE
	for m in members:
		var a := m.durability.get_last_attacker() as Node3D
		if a is Ship and Combat.is_live_target(a) and m.durability.seconds_since_hit() < 5.0:
			var d := Combat.flat_distance(lp, a.global_position)
			if d < best_d:
				best_d = d
				best = a
	if Combat.is_live_target(focus) and focus != target and focus is Ship and Combat.flat_distance(lp, focus.global_position) < FOCUS_RANGE:
		return focus
	return best if best else target


## The leader breaks off when the fleet's hull runs low or it lost half its ships.
func _check_retreat() -> void:
	var d := contract.target.get(&"durability") as Durability
	var target_hull := d.fraction() if d else 1.0
	if target_hull < RETREAT_TARGET_HULL:
		return
	var lb := leader.brain as MercenaryBrain if is_instance_valid(leader) else null
	if lb == null:
		return
	var sum := 0.0
	for m in members:
		sum += m.hull_fraction()
	var mean := sum / float(maxi(members.size(), 1))
	var lost := 0
	for id in roster:
		if bool(roster[id]["lost"]):
			lost += 1
	if mean < lb.retreat_level() + RETREAT_MARGIN or (lost > 0 and lost * 2 >= roster.size()):
		_set_state(State.RETREATING)
		EventLog.post("%s's fleet breaks off from %s (hull %d%%)" % [leader_name, contract.get_target_name(), roundi(target_hull * 100.0)],
				EventLog.Kind.COMBAT, leader)
		for m in members.duplicate():
			var mb := m.brain as MercenaryBrain
			if mb:
				mb.note(CaptainLog.Kind.RETREAT, CaptainLog.Outcome.DID, "%s fleet broke off from %s" % ["Our" if m == leader else leader_name + "'s", contract.get_target_name()],
						"Fleet hull %d%% under the leader's retreat level %d%% + %d%%, or half the ships lost; the target still has %d%%" % [roundi(mean * 100.0),
						roundi(lb.retreat_level() * 100.0), roundi(RETREAT_MARGIN * 100.0), roundi(target_hull * 100.0)])
				mb.return_home(m.hull_fraction() < MercenaryBrain.REPAIRED)


## A member left: retreated alone, went home, or was destroyed ([param lost]).
func leave(ship: Ship, lost: bool) -> void:
	if not members.has(ship):
		return
	members.erase(ship)
	var id := ship.get_instance_id()
	if roster.has(id):
		roster[id]["lost"] = lost
		roster[id]["left_early"] = not lost and not contract.is_finished() and state != State.RETREATING
	var mb := ship.brain as MercenaryBrain
	if mb and mb.fleet == self:
		mb.fleet = null
	if state == State.DONE or state == State.RETREATING:
		if members.is_empty() and state == State.RETREATING:
			_set_state(State.DONE)
			if contract.fleet == self and not contract.is_finished():
				contract.fleet = null
		changed.emit(self)
		return
	if state == State.FORMING:
		# Someone who never took part does not count against the split.
		roster.erase(id)
		if members.is_empty():
			disband("")
		elif ship == leader:
			leader = members[0]
			leader_name = leader.get_display_name()
		changed.emit(self)
		return
	if ship == leader and not members.is_empty():
		_pick_leader()
	if members.size() == 1:
		_last_one_standing(members[0])
	elif members.is_empty():
		disband("")
	changed.emit(self)


## Only one left mid-run: go on alone when the target is nearly down or the
## captain is daring enough, else head home.
func _last_one_standing(s: Ship) -> void:
	var d := contract.target.get(&"durability") as Durability
	var target_hull := d.fraction() if d else 1.0
	var daring := s.captain.daring() if s.captain else 0.5
	var mb := s.brain as MercenaryBrain
	_set_state(State.DONE)
	contract.fleet = null
	if mb == null:
		return
	mb.fleet = null
	if target_hull < 0.35 or daring >= MercenaryEvaluator.LONE_WOLF_DARING:
		EventLog.post("%s fights on alone against %s" % [s.get_display_name(), contract.get_target_name()], EventLog.Kind.COMBAT, s)
		mb.go_solo()
	else:
		EventLog.post("%s's fleet is down to %s, who heads home" % [leader_name, s.get_display_name()], EventLog.Kind.COMBAT, s)
		mb.note(CaptainLog.Kind.FLEET, CaptainLog.Outcome.DID, "Left alone in the fleet, headed home from %s" % contract.get_target_name(),
				"Target at %d%% hull and daring %.2f below %.2f: not worth it alone" % [roundi(target_hull * 100.0), daring, MercenaryEvaluator.LONE_WOLF_DARING])
		mb.return_home(s.hull_fraction() < MercenaryBrain.REPAIRED)


## Ends the fleet; members go home. [param line] goes to the feed.
func disband(line: String) -> void:
	if state == State.DONE:
		return
	_set_state(State.DONE)
	if contract.fleet == self:
		contract.fleet = null
	if not line.is_empty():
		EventLog.post(line, EventLog.Kind.INFO, leader if is_instance_valid(leader) else null)
	for m in members.duplicate():
		var mb := m.brain as MercenaryBrain
		if mb and mb.fleet == self:
			mb.fleet = null
			mb.note(CaptainLog.Kind.FLEET, CaptainLog.Outcome.FAILED, "Fleet for %s fell apart" % contract.get_target_name(), line if not line.is_empty() else "Not enough ships stayed in it")
			mb.return_home(false)
	members.clear()


func _prune() -> void:
	for m in members.duplicate():
		if not is_instance_valid(m) or m.dead:
			members.erase(m)
	if not is_instance_valid(leader) or leader.dead:
		if not members.is_empty():
			_pick_leader()


func _set_state(s: State) -> void:
	if state == s:
		return
	state = s
	# Done: let go of the contract (no reference cycle left behind).
	if s == State.DONE and contract.fleet == self:
		contract.fleet = null
	changed.emit(self)


# --- Flying --------------------------------------------------------------------

## Where the fleet forms up: off the Home Station toward the target.
func rally_point() -> Vector3:
	var tree := leader.get_tree() if is_instance_valid(leader) and leader.is_inside_tree() else null
	var sys := tree.get_first_node_in_group(SolarSystem.GROUP) as SolarSystem if tree else null
	if sys == null or sys.home_station == null or not Combat.is_live(contract.target):
		return leader.global_position if is_instance_valid(leader) else Vector3.ZERO
	var home := sys.home_station.global_position
	var to := contract.target.global_position - home
	to.y = 0.0
	return home + to.normalized() * RALLY_DISTANCE


## Formation offset of slot [param index] (0 = the leader, in front).
static func slot_offset(index: int, fwd: Vector3) -> Vector3:
	if index <= 0:
		return Vector3.ZERO
	var right := fwd.cross(Vector3.UP)
	var side := 1.0 if index % 2 == 1 else -1.0
	var row := ceilf(index / 2.0)
	return right * side * SLOT_SIDE * row - fwd * SLOT_BACK * row - Vector3.UP * side * SLOT_RISE * row


## Steers [param ship] while forming up or flying to the target (not while
## fighting).
func steer(ship: Ship) -> void:
	var idx := maxi(members.find(ship), 0)
	var tp := contract.target.global_position if Combat.is_live(contract.target) else ship.global_position
	match state:
		State.FORMING:
			var rp := rally_point()
			var fwd := Vector3(tp.x - rp.x, 0.0, tp.z - rp.z).normalized()
			var spot := rp + slot_offset(idx, fwd)
			var face := fwd if ship.global_position.distance_to(spot) < 120.0 else Vector3.ZERO
			ship.set_world_goal(spot, Vector3.ZERO, face, 20.0)
		State.EN_ROUTE, State.ENGAGING:
			if ship == leader:
				var speed := _fleet_speed()
				ship.set_world_goal(tp, Vector3.ZERO, Vector3.ZERO, 60.0, speed)
				return
			if not is_instance_valid(leader):
				ship.set_world_goal(tp, Vector3.ZERO, Vector3.ZERO, 60.0)
				return
			var fwd := leader.global_basis * Vector3.FORWARD
			fwd.y = 0.0
			fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
			var spot := leader.global_position + slot_offset(idx, fwd)
			var face := fwd if ship.global_position.distance_to(spot) < 120.0 else Vector3.ZERO
			ship.set_world_goal(spot, leader.get_world_velocity(), face, 10.0)


## The leader's pace: the slowest member's, slower while wingmen catch up.
func _fleet_speed() -> float:
	var speed := INF
	var straggling := false
	var fwd := leader.global_basis * Vector3.FORWARD
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	for i in members.size():
		var m := members[i]
		speed = minf(speed, m.max_speed)
		if i > 0 and m.global_position.distance_to(leader.global_position + slot_offset(i, fwd)) > STRAGGLE_DISTANCE:
			straggling = true
	speed *= 0.85
	return speed * (0.55 if straggling else 1.0)


# --- Split ---------------------------------------------------------------------

## The bounty split: [{ship, name, credits, left_early}], adding up to
## [param reward]. [param tally] is the target's Durability.tally.
func split(reward: int, tally: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var rank_sum := 0.0
	var dmg_sum := 0.0
	for id in roster:
		var r: Dictionary = roster[id]
		var s := (r["ref"] as WeakRef).get_ref() as Ship
		if bool(r["lost"]) or s == null or s.dead or s.captain == null:
			continue
		var rank_w := 1.0 + 0.5 * float(s.captain.rank)
		var dmg := float((tally.get(id, {}) as Dictionary).get("damage", 0.0))
		rows.append({"ship": s, "name": String(r["name"]), "rank_w": rank_w, "damage": dmg, "left_early": bool(r["left_early"])})
		rank_sum += rank_w
		dmg_sum += dmg
	var out: Array[Dictionary] = []
	if rows.is_empty():
		return out
	var w_sum := 0.0
	for row in rows:
		var w := RANK_WEIGHT * float(row["rank_w"]) / rank_sum
		w += (1.0 - RANK_WEIGHT) * (float(row["damage"]) / dmg_sum if dmg_sum > 0.0 else float(row["rank_w"]) / rank_sum)
		if bool(row["left_early"]):
			w *= FLED_SHARE
		row["w"] = w
		w_sum += w
	# Largest remainder, so the parts add up to the reward.
	var given := 0
	for row in rows:
		var exact := float(reward) * float(row["w"]) / w_sum
		row["credits"] = floori(exact)
		row["rest"] = exact - floorf(exact)
		given += int(row["credits"])
	var by_rest := rows.duplicate()
	by_rest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["rest"]) > float(b["rest"]))
	var i := 0
	while given < reward and not by_rest.is_empty():
		by_rest[i % by_rest.size()]["credits"] = int(by_rest[i % by_rest.size()]["credits"]) + 1
		given += 1
		i += 1
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["credits"]) > int(b["credits"]))
	for row in rows:
		out.append({"ship": row["ship"], "name": row["name"], "credits": row["credits"], "left_early": row["left_early"]})
	return out


## Short label for the UI: "Fleet of 3 forming".
func get_label() -> String:
	return "Fleet of %d %s" % [members.size(), STATE_NAMES[state]]


func role_of(ship: Ship) -> String:
	return "leader" if ship == leader else "wingman"

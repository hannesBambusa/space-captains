class_name MercFleet
extends RefCounted
## A group of mercenaries that band together for one bounty and split it.
##
## How strong a target is, in "default mercenaries needed" ([method need_for]):
## a base counts its fighting power like a ship's ([method den_need]: hull,
## shields, guns and every ship it can field, out or still to launch);
## a ship counts itself and the hostiles flying with it. Above
## [constant SOLO_NEED] (scaled by the merc's own ship) a bounty is too much
## for one ship. Then the merc (MercenaryEvaluator) either goes alone anyway
## (a lone wolf: high Nerve, low Teamwork, see Captain.daring), calls a fleet
## ([method call_fleet]), or refuses.
##
## Fleet size ([method assess]): enough ships, strongest free mercs first, for
## their combined power ([method power_of], summed) to reach the target's
## need times a margin ([method share_for]: [constant FLEET_POWER_SHARE], by
## the caller's personality [constant SHARE_BY_PERSONALITY]), at least 2 and
## at most [constant MAX_SIZE] (and the contract's taker limit). A caller refuses
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
##   Until it sets out it takes members past the planned size (up to the
##   cap) from anyone who likes the share. It leaves when everyone wanted
##   is at the rally point (or the members there are strong enough), or
##   after [constant FORM_WAIT] when strong enough; after
##   [constant FORM_WAIT_MAX] it goes if it covers the bare need, else (or
##   alone) it falls apart. The leader is picked at departure by rank, then Nerve.
## - EN_ROUTE: the leader flies at the slowest member's pace (on its own
##   cruise arc, Ship.cruise_band), wingmen hold 3D offset slots behind it
##   ([method slot_offset]: left wing above, right wing below). Wingmen
##   near the leader hop with it; one left behind hops on its own, and
##   short of the target the leader holds until everyone is back in
##   formation ([constant REGROUP_DISTANCE], at most [constant REGROUP_WAIT]).
##   A ship shooting at a member while forming up or on the way is fought
##   by the whole fleet ([member focus]), then it flies on.
## - ENGAGING: inside [constant ENGAGE_RANGE] everyone shoots the fleet's
##   focus target (the ship doing the most damage to the fleet, else the bounty).
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
## A fleet sets out once its combined power covers the need times this
## margin (the default; a caller's personality sets its own fleet's,
## [constant SHARE_BY_PERSONALITY]).
const FLEET_POWER_SHARE := 1.3
## Margin by the caller's personality: Bold, Cautious, Greedy, Lazy.
const SHARE_BY_PERSONALITY: Array[float] = [1.0, 1.5, 1.15, 1.3]
## A base's fighting power ([method den_need]): its guns count at
## [constant DEN_GUN_SHARE] of their damage (they miss nimble ships), and
## every ship it can field (out now, or still to launch while the alarm
## lasts, up to its spawn cap) at [constant DEN_SHIP_SHARE] of its hull and
## damage (they come home one by one and some flee). Fitted to measured
## fleet fights against each base.
const DEN_GUN_SHARE := 0.5
const DEN_SHIP_SHARE := 0.5
## Each hostile flying with a ship target, times its fighting power (other
## combatants count this much each).
const ESCORT_NEED := 0.4
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
## Short of the target (after a hop) the leader holds while a wingman is
## farther than this from its slot, metres, for at most this long, sim seconds.
const REGROUP_DISTANCE := 500.0
const REGROUP_WAIT := 30.0
## Formation slots: side and back offsets per row, metres.
const SLOT_SIDE := 45.0
const SLOT_BACK := 38.0
## Formation slots: height per row (left above the leader, right below), metres.
const SLOT_RISE := 18.0
## Wingmen farther than this from their slot slow the leader down, metres.
const STRAGGLE_DISTANCE := 260.0
## Hostiles shooting at the fleet this close to the leader are focused first.
const FOCUS_RANGE := 2500.0
## Share of the split by rank (the rest by damage done).
const RANK_WEIGHT := 0.4
const FLED_SHARE := 0.5
## The leader breaks off when the fleet's mean hull drops this far above
## its own retreat level while the target is above [constant RETREAT_TARGET_HULL].
const RETREAT_MARGIN := 0.12
const RETREAT_TARGET_HULL := 0.35
## The fleet (or its last member) breaks off when the power of the members
## still fit to fight covers less than this share of the target's need now
## (its hull and ships as they are by then).
const BREAK_OFF_COVER := 0.7
## A cover goes to the feed when the member hurt most is below this hull.
const COVER_FEED_HULL := 0.75

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
## SimClock.time the leader started holding for stragglers (-1 = not).
var _regroup_from: float = -1.0
var _last_tick: float = -1.0
## Margin over the need this fleet aims for (its caller's, [method share_for]).
var share: float = FLEET_POWER_SHARE
## Attackers already logged as covered (instance id -> true).
var _covered: Dictionary = {}

static var _ship_cache: Dictionary = {}


# --- Strength ------------------------------------------------------------------

## Fighting power of [param ship] against the default mercenary (1.0).
static func power_of(ship: Ship) -> float:
	if ship == null or ship.stats == null:
		return 1.0
	var ehp := ship.stats.max_hull + ship.stats.max_shields
	var dps := ship.stats.dps()
	return clampf(sqrt(ehp / REF_EHP * maxf(dps, 1.0) / REF_DPS), 0.3, 4.0)


## Default mercenaries [param target] is worth. A ship: the mean of its
## toughness (hull plus shields against the default merc's) and its
## fighting power (a heavy gunship with weak guns counts less than its
## armour), plus the hostiles flying with it.
static func target_need(target: Node3D) -> float:
	if not Combat.is_live(target):
		return 0.0
	if target is ScavengerDen:
		return den_need(target as ScavengerDen)
	var need := 0.6
	var d := target.get(&"durability") as Durability
	if d:
		need = (d.hull + d.shields) / REF_EHP
		var ship := target as Ship
		if ship and ship.stats:
			need = sqrt(need * power_of(ship) * (1.0 + ship.stats.dodge))
	if target.is_inside_tree():
		for h in Combat.hostiles_near(target, target.global_position, ESCORT_RADIUS, Combat.Faction.PLAYER):
			if h == target:
				continue
			var hs := h as Ship
			need += ESCORT_NEED * (power_of(hs) * (1.0 + hs.stats.dodge) if hs and hs.stats else 1.0)
	return need


## A base's need: its fighting power like [method power_of]'s, the square
## root of toughness times damage. Toughness is its hull and shields plus
## its ships' (dodgers more), damage [constant DEN_GUN_SHARE] of its guns
## plus its ships'; each ship it can field counts at
## [constant DEN_SHIP_SHARE], the ones out now by their own numbers, the
## ones still to launch (up to the spawn cap) by its faction's.
static func den_need(den: ScavengerDen) -> float:
	var ehp := den.durability.hull + den.durability.shields
	var dps := DEN_GUN_SHARE * den.gun_dps()
	var out := 0
	for s in den.spawns:
		if is_instance_valid(s) and not s.dead and s.stats:
			ehp += DEN_SHIP_SHARE * (s.stats.max_hull + s.stats.max_shields) * (1.0 + s.stats.dodge)
			dps += DEN_SHIP_SHARE * s.stats.dps()
			out += 1
	var home := maxi(den.def.spawn_cap - out, 0) if den.def else 0
	if home > 0 and den.faction_def:
		var p := faction_ship(den.faction_def)
		ehp += DEN_SHIP_SHARE * float(home) * p.x
		dps += DEN_SHIP_SHARE * float(home) * p.y
	return sqrt(ehp / REF_EHP * maxf(dps, 1.0) / REF_DPS)


## A stock ship of [param f]: (hull plus shields times 1 + dodge, damage
## per second), from its loadout. Cached per faction.
static func faction_ship(f: FactionDef) -> Vector2:
	if _ship_cache.has(f.id):
		return _ship_cache[f.id]
	var l := f.loadout if f.loadout else ShipLoadout.default_for("Scavenger")
	var st := l.derive(null)
	var v := Vector2((st.max_hull + st.max_shields) * (1.0 + f.ship_dodge), st.dps())
	_ship_cache[f.id] = v
	return v


## Margin over the need a fleet called by [param ship] aims for, by the
## captain's personality (no captain: [constant FLEET_POWER_SHARE]).
static func share_for(ship: Ship) -> float:
	if ship == null or ship.captain == null:
		return FLEET_POWER_SHARE
	return SHARE_BY_PERSONALITY[ship.captain.personality]


## Mercenaries like [param ship] needed for [param contract]'s target.
static func need_for(contract: Contract, ship: Ship) -> float:
	return target_need(contract.target) / power_of(ship)


## Most ships a fleet on [param contract] takes.
static func cap_for(contract: Contract) -> int:
	return MAX_SIZE if contract.max_takers <= 0 else clampi(contract.max_takers, 2, MAX_SIZE)


## How a fleet on [param contract] would stand now, seen by [param asker]
## (counted as free; its personality sets the margin, a forming fleet's
## own margin wins): {need (default mercs), share, goal (power to reach), wanted
## (ships), available (free mercs: idle or patrolling and repaired, the
## asker, members already in), power (the best [code]wanted[/code] of them),
## estimate (ships like the hired ones needed), enough, too_strong (even
## [method cap_for] ships like those could not), text}.
static func assess(contract: BountyContract, asker: Ship = null) -> Dictionary:
	var need := target_need(contract.target)
	var share := share_for(asker)
	if contract.fleet and contract.fleet.state == State.FORMING:
		share = contract.fleet.share
	var goal := need * share
	var cap := cap_for(contract)
	var ctx: Node = null
	if asker and asker.is_inside_tree():
		ctx = asker
	elif Combat.is_live(contract.target) and contract.target.is_inside_tree():
		ctx = contract.target
	var free: Array[float] = []
	var hired_sum := 0.0
	var hired := 0
	if ctx:
		for n in SystemWorld.nodes_in(ctx, Ship.GROUP):
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
	return {"need": need, "share": share, "goal": goal, "wanted": wanted, "available": free.size(), "power": power, "estimate": estimate,
			"enough": enough, "too_strong": too_strong, "text": text}


## Combined power of the members (default mercs).
func power() -> float:
	var p := 0.0
	for m in members:
		if is_instance_valid(m) and not m.dead:
			p += power_of(m)
	return p


## Power this fleet aims for: the need times its margin.
func goal() -> float:
	return target_need(contract.target) * share


## True when the members are strong enough to set out ([param part] of the goal).
func strong_enough(part: float = 1.0) -> bool:
	return power() >= goal() * part


# --- Forming -------------------------------------------------------------------

## [param caller] (already a taker of [param bounty]) calls a fleet of
## [param size] ships (0 = by [method assess]).
static func call_fleet(bounty: BountyContract, caller: Ship, size: int = 0) -> MercFleet:
	var f := MercFleet.new()
	f.contract = bounty
	f.share = share_for(caller)
	f.wanted = clampi(size if size > 0 else int(assess(bounty, caller)["wanted"]), 2, cap_for(bounty))
	f.called_at = SimClock.time
	f._next_invite = SimClock.time
	bounty.fleet = f
	f._add_member(caller)
	f.leader = caller
	f.leader_name = caller.get_display_name()
	EventLog.post("%s calls a fleet for %s (%d ships wanted, aiming for %d%% of its need)" % [caller.get_display_name(), bounty.get_target_name(), f.wanted,
			roundi(f.share * 100.0)],
			EventLog.Kind.COMBAT, caller)
	f.invite(caller)
	return f


## True while it still takes members: until it sets out, up to the cap
## (past the planned size only those who like the share say yes).
func is_recruiting() -> bool:
	return state == State.FORMING and members.size() < cap_for(contract)


## True while it is short of the planned size or still too weak.
func is_short() -> bool:
	return members.size() < wanted or not strong_enough()


## Adds [param ship] (already a taker of the contract). False when full.
func join(ship: Ship) -> bool:
	if not is_recruiting() or members.has(ship):
		return false
	_add_member(ship)
	wanted = maxi(wanted, members.size())
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


## A member who went home for repairs ([method leave], left early, not
## lost) may fly back while the fleet is still on its way or fighting, in
## the same system, with room under [constant MAX_SIZE].
func can_rejoin(ship: Ship) -> bool:
	if state != State.EN_ROUTE and state != State.ENGAGING:
		return false
	if contract.is_finished() or not Combat.is_live(contract.target) or members.has(ship) or members.size() >= MAX_SIZE:
		return false
	if members.is_empty() or SystemWorld.of(members[0]) != SystemWorld.of(ship):
		return false
	var r: Variant = roster.get(ship.get_instance_id())
	return r is Dictionary and bool(r["left_early"]) and not bool(r["lost"])


## The running fleet [param ship] left for repairs and may rejoin, or null.
static func rejoinable(ship: Ship) -> MercFleet:
	for c in ContractBoard.contracts:
		var b := c as BountyContract
		if b and b.fleet and b.fleet.can_rejoin(ship):
			return b.fleet
	return null


## Back from repairs: [param ship] (a taker of the contract again) flies in
## its old slot; it no longer counts as left early in the split.
func rejoin(ship: Ship) -> void:
	if not can_rejoin(ship):
		return
	members.append(ship)
	var mb := ship.brain as MercenaryBrain
	if mb:
		mb.fleet = self
	roster[ship.get_instance_id()]["left_early"] = false
	EventLog.post("%s rejoins %s's fleet on %s after repairs (%d)" % [ship.get_display_name(), leader_name, contract.get_target_name(), members.size()],
			EventLog.Kind.COMBAT, ship)
	changed.emit(self)


## Asks the idle and patrolling mercs (in [param ctx]'s system), once each.
func invite(ctx: Node) -> void:
	if ctx == null or not ctx.is_inside_tree() or not is_recruiting():
		return
	var candidates: Array[MercenaryBrain] = []
	for n in SystemWorld.nodes_in(ctx, Ship.GROUP):
		var s := n as Ship
		var mb := s.brain as MercenaryBrain if s else null
		if mb == null or s.dead or members.has(s) or has_declined(s) or not mb.can_answer_fleet():
			continue
		candidates.append(mb)
	# Nearest first.
	var rp := rally_point()
	candidates.sort_custom(func(a: MercenaryBrain, b: MercenaryBrain) -> bool:
		return SpaceNav.flat_distance(a.ship.global_position, rp) < SpaceNav.flat_distance(b.ship.global_position, rp))
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
		finish()
		return
	if members.is_empty():
		disband("")
		return
	match state:
		State.FORMING:
			_set_focus(_attacker())
			if now >= _next_invite:
				_next_invite = now + INVITE_INTERVAL
				invite(leader if is_instance_valid(leader) else null)
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
				# Short of the margin after the long wait: it still goes when
				# it covers the bare need, never below it.
				if members.size() >= 2 and power() >= maxf(goal() * 0.85, target_need(contract.target)):
					_depart()
				elif members.size() < 2:
					disband("No one answered %s's call for %s" % [leader_name, contract.get_target_name()])
				else:
					disband("Not enough mercenaries answered %s's call for %s: fleet power %.1f, it needs about %.1f" % [leader_name,
							contract.get_target_name(), power(), goal()])
		State.EN_ROUTE:
			_set_focus(_attacker())
			if is_instance_valid(leader) and leader.global_position.distance_to(contract.target.global_position) < ENGAGE_RANGE:
				_set_state(State.ENGAGING)
				EventLog.post("%s's fleet (%d) engages %s" % [leader_name, members.size(), contract.get_target_name()], EventLog.Kind.COMBAT, leader)
		State.ENGAGING:
			_set_focus(_pick_focus())
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


## New focus: a ship turning on the fleet is logged once per attacker in
## the captains' logs, and in the feed when the member it hurt most is
## below [constant COVER_FEED_HULL] ("Kade Rask covers Mira Novak against
## Corsair Vane-1": covered by the leader, or the nearest other member).
func _set_focus(f: Node3D) -> void:
	var old := focus
	focus = f
	if f == null or f == old or f == contract.target or not (f is Ship):
		return
	var hurt: Ship = null
	var most := 0.0
	for m in members:
		var mb := m.brain as MercenaryBrain
		var dmg := float(mb.recent_attackers().get(f, 0.0)) if mb else 0.0
		if dmg > most:
			most = dmg
			hurt = m
	if hurt == null:
		return
	var helper: Ship = leader if hurt != leader else null
	if helper == null:
		var best := INF
		for m in members:
			var d := m.global_position.distance_to(hurt.global_position)
			if m != hurt and d < best:
				best = d
				helper = m
	var what := (f as Ship).get_display_name()
	if _covered.has(f.get_instance_id()):
		return
	_covered[f.get_instance_id()] = true
	if helper and hurt.hull_fraction() < COVER_FEED_HULL:
		EventLog.post("%s covers %s against %s, the fleet turns on it" % [helper.get_display_name(), hurt.get_display_name(), what], EventLog.Kind.COMBAT, helper)
	for m in members:
		if m.brain:
			m.brain.note(CaptainLog.Kind.FLEET, CaptainLog.Outcome.DID, "Fleet turned on %s, covering %s" % [what, "us" if m == hurt else hurt.get_display_name()],
					"It did the most damage to the fleet lately (%d hull on %s); back to %s once it is dead or gone" % [roundi(most), hurt.get_display_name(), contract.get_target_name()], "", "cover:%d" % f.get_instance_id())


## The ship doing the most damage to the fleet lately ([method _attacker]),
## else the bounty target: once the attackers are dead or gone the fleet
## goes back to the target.
func _pick_focus() -> Node3D:
	var a := _attacker()
	return a if a else contract.target


## The ship doing the most damage to the fleet lately (summed over the
## members, MercenaryBrain.recent_attackers) within
## [constant FOCUS_RANGE] of the leader, or null. A focus ship is kept
## while it still shoots at the fleet, unless another does clearly more
## (MercenaryBrain.RETARGET_MARGIN). Forming up and on the way the whole
## fleet turns on it too (MercenaryBrain picks [member focus]), so a wingman
## under fire is not left behind fighting alone.
func _attacker() -> Ship:
	var target := contract.target
	if not is_instance_valid(leader):
		return null
	var lp := leader.global_position
	var dmg := {}
	for m in members:
		var mb := m.brain as MercenaryBrain
		if mb == null:
			continue
		var hits := mb.recent_attackers()
		for a in hits:
			dmg[a] = float(dmg.get(a, 0.0)) + float(hits[a])
	var best: Ship = null
	var best_d := 0.0
	for a: Ship in dmg:
		if a != target and SpaceNav.flat_distance(lp, a.global_position) < FOCUS_RANGE and float(dmg[a]) > best_d:
			best_d = float(dmg[a])
			best = a
	if is_instance_valid(focus) and focus is Ship and Combat.is_live_target(focus) and focus != target and dmg.has(focus) and SpaceNav.flat_distance(lp, focus.global_position) < FOCUS_RANGE \
			and best_d < float(dmg[focus]) * MercenaryBrain.RETARGET_MARGIN:
		return focus as Ship
	return best


## Power of the members still fit to fight (above their own retreat level;
## the others are about to leave on their own), and how many they are.
func fit_power() -> Vector2:
	var p := 0.0
	var n := 0
	for m in members:
		var mb := m.brain as MercenaryBrain
		if is_instance_valid(m) and not m.dead and mb and m.hull_fraction() >= mb.retreat_level():
			p += power_of(m)
			n += 1
	return Vector2(p, n)


## Share of the target's need now that the fit members' power covers.
func cover_now() -> float:
	var need := target_need(contract.target)
	return fit_power().x / need if need > 0.0 else INF


## The leader re-judges the fight: the fleet breaks off together when the
## fit members' hull runs low, half the ships are lost, or what is left
## covers less than [constant BREAK_OFF_COVER] of the target's need now. A
## member below its own retreat level leaves alone and does not drag the
## others home. Near the end ([constant RETREAT_TARGET_HULL]) it fights on.
func _check_retreat() -> void:
	var d := contract.target.get(&"durability") as Durability
	var target_hull := d.fraction() if d else 1.0
	if target_hull < RETREAT_TARGET_HULL:
		return
	var lb := leader.brain as MercenaryBrain if is_instance_valid(leader) else null
	if lb == null:
		return
	var sum := 0.0
	var fit := 0
	for m in members:
		var mb := m.brain as MercenaryBrain
		if mb and m.hull_fraction() >= mb.retreat_level():
			sum += m.hull_fraction()
			fit += 1
	var mean := sum / float(fit) if fit > 0 else 0.0
	var lost := 0
	for id in roster:
		if bool(roster[id]["lost"]):
			lost += 1
	var cover := cover_now()
	var why := ""
	if fit == 0 or mean < lb.retreat_level() + RETREAT_MARGIN:
		why = "fleet hull %d%% under the leader's retreat level %d%% + %d%%" % [roundi(mean * 100.0), roundi(lb.retreat_level() * 100.0), roundi(RETREAT_MARGIN * 100.0)]
	elif lost > 0 and lost * 2 >= roster.size():
		why = "%d of %d ships lost" % [lost, roster.size()]
	elif cover < BREAK_OFF_COVER:
		why = "%d of %d left, covers %d%% of the need" % [fit, roster.size(), roundi(cover * 100.0)]
	if why.is_empty():
		return
	_set_state(State.RETREATING)
	EventLog.post("%s's fleet broke off from %s: %s (target at %d%%)" % [leader_name, contract.get_target_name(), why, roundi(target_hull * 100.0)],
			EventLog.Kind.COMBAT, leader)
	for m in members.duplicate():
		var mb := m.brain as MercenaryBrain
		if mb:
			mb.note(CaptainLog.Kind.RETREAT, CaptainLog.Outcome.DID, "%s fleet broke off from %s" % ["Our" if m == leader else leader_name + "'s", contract.get_target_name()],
					"%s; the target still has %d%%" % [why[0].to_upper() + why.substr(1), roundi(target_hull * 100.0)])
			mb.return_home(m.hull_fraction() < MercenaryBrain.REPAIRED)


## The target is down (or the contract closed): the fleet is done, one
## feed line ("Fleet disbanded: Rustjaw Hideout destroyed, 4 of 4 coming home").
func finish() -> void:
	if state == State.ENGAGING or state == State.EN_ROUTE:
		var out := 0
		for id in roster:
			if not bool(roster[id]["lost"]):
				out += 1
		var what := "%s destroyed" % contract.get_target_name() if not Combat.is_live(contract.target) else "the contract on %s closed" % contract.get_target_name()
		EventLog.post("%s's fleet disbanded: %s, %d of %d coming home" % [leader_name, what, out, roster.size()],
				EventLog.Kind.COMBAT, leader if is_instance_valid(leader) else null)
	_set_state(State.DONE)


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
	if state != State.DONE and (contract.is_finished() or not Combat.is_live(contract.target)):
		finish()
		changed.emit(self)
		return
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
		if members.size() > 1:
			EventLog.post("%s takes the lead of the fleet on %s" % [leader_name, contract.get_target_name()], EventLog.Kind.COMBAT, leader)
	if members.size() == 1:
		_last_one_standing(members[0])
	elif members.is_empty():
		disband("")
	changed.emit(self)


## Only one left mid-run: it re-judges. It goes on alone (solo rules: its
## own attack run, the solo retreat level) when the target is nearly down,
## its own power covers [constant BREAK_OFF_COVER] of the need now, or the
## captain is daring enough; else the fleet broke off and it heads home.
func _last_one_standing(s: Ship) -> void:
	var d := contract.target.get(&"durability") as Durability
	var target_hull := d.fraction() if d else 1.0
	var daring := s.captain.daring() if s.captain else 0.5
	var need := target_need(contract.target)
	var cover := power_of(s) / need if need > 0.0 else INF
	var mb := s.brain as MercenaryBrain
	var flown := roster.size()
	_set_state(State.DONE)
	contract.fleet = null
	if mb == null:
		return
	mb.fleet = null
	if target_hull < RETREAT_TARGET_HULL or cover >= BREAK_OFF_COVER or daring >= MercenaryEvaluator.LONE_WOLF_DARING:
		EventLog.post("%s fights on alone against %s: 1 of %d left, covers %d%% of the need (target at %d%%)" % [s.get_display_name(), contract.get_target_name(),
				flown, roundi(cover * 100.0), roundi(target_hull * 100.0)], EventLog.Kind.COMBAT, s)
		mb.go_solo()
	else:
		EventLog.post("%s's fleet broke off from %s: 1 of %d left, covers %d%% of the need; %s heads home" % [leader_name, contract.get_target_name(), flown,
				roundi(cover * 100.0), s.get_display_name()], EventLog.Kind.COMBAT, s)
		mb.note(CaptainLog.Kind.FLEET, CaptainLog.Outcome.DID, "Left alone in the fleet, headed home from %s" % contract.get_target_name(),
				"1 of %d left: covers %d%% of the need (needs %d%%), target at %d%% hull, daring %.2f below %.2f" % [flown, roundi(cover * 100.0),
				roundi(BREAK_OFF_COVER * 100.0), roundi(target_hull * 100.0), daring, MercenaryEvaluator.LONE_WOLF_DARING])
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
	var sys := SolarSystem.of(leader) if is_instance_valid(leader) else null
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
				if state == State.EN_ROUTE and _holding():
					ship.set_world_goal(ship.global_position, Vector3.ZERO, Vector3.ZERO, 60.0)
					return
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


## Leader short of the target (inside the hunt drop-out plus a margin)
## while a wingman is out of formation: hold there, for at most
## [constant REGROUP_WAIT].
func _holding() -> bool:
	if not is_instance_valid(leader) or leader.mover.warp_state != ShipMover.Warp.IDLE \
			or SpaceNav.flat_distance(leader.global_position, contract.target.global_position) > MercenaryBrain.HUNT_WARP_DROP + 400.0:
		return false
	var fwd := leader.global_basis * Vector3.FORWARD
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var out := false
	for i in range(1, members.size()):
		if SpaceNav.flat_distance(members[i].global_position, leader.global_position + slot_offset(i, fwd)) > REGROUP_DISTANCE:
			out = true
			break
	if not out:
		_regroup_from = -1.0
		return false
	if _regroup_from < 0.0:
		_regroup_from = SimClock.time
	return SimClock.time - _regroup_from < REGROUP_WAIT


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


## Target panel line: "Fleet 3/5 forming, 72% of what Obsidian Syndicate
## Fortress needs" (power against [method goal]).
func get_progress_label() -> String:
	var g := goal()
	var pct := roundi(power() / g * 100.0) if g > 0.0 else 100
	return "Fleet %d/%d %s, %d%% of what %s needs" % [members.size(), maxi(wanted, members.size()), STATE_NAMES[state], pct, contract.get_target_name()]


func role_of(ship: Ship) -> String:
	return "leader" if ship == leader else "wingman"

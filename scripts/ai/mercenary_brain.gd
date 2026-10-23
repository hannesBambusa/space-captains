class_name MercenaryBrain
extends CaptainBrain
## A mercenary captain's decisions. Reuses CaptainBrain's undock / dock /
## rest steps; adds the fighting work:
## - Defence: hostiles inside the home defence radius make docked mercs
##   scramble (Loyalty widens the radius); patrols fly loops around the Home
##   Station and engage what they find there, no contract needed.
## - Bounty (HUNTING): fly to the target and fight it until it dies.
## - Escort (ESCORTING): join a miner (or wait at its outpost for it to
##   launch), fly in formation, engage what comes near it, and finish when it
##   delivers (the board pays per trip) or docks.
## - Retreat: below the retreat hull level (profile minus Nerve) the merc
##   drops its job and goes home; docked, it repairs (REPAIRING, paid from
##   its wallet, see RepairBay) before it takes new work. A broke merc
##   repairs what it can pay for and flies on damaged.
## - Repairs after a fight: patrolling or defending with the hull below the
##   personality's repair level ([method repair_level]) and no hostile near,
##   it goes home to dock and repair. Escorts and fleet members keep their
##   job (they repair when it ends) unless below the retreat level.
## Target choice: whoever attacks the merc or its ward first, then the
## nearest hostile in the mode's area. AI checks run on a timer.
## Fleets ([MercFleet]): a bounty too strong for one ship is taken by a
## fleet (or by a lone wolf alone, [member solo_brave], who also holds on
## longer: [constant SOLO_RETREAT_SCALE]). Members fly the fleet's rally,
## formation and focus target instead of their own bounty steering.
## Warp hops: bounty runs and trips home warp (dropping out
## [constant HUNT_WARP_DROP] short of a target, outside its guns); fleet
## wingmen and escorts in formation hop with their leader or ward, never
## on their own; patrols, fights and defence never warp.

enum Mode { NONE, PATROL, DEFEND, BOUNTY, ESCORT }

## Sim seconds between target / retreat checks.
const AI_INTERVAL := 0.3
## Defence radius around the Home Station at Loyalty 5.5, metres.
const DEFENSE_RADIUS := 3600.0
## Patrol loop radius range around the station, metres.
const PATROL_RADIUS := Vector2(700.0, 1600.0)
const PATROL_TIME := Vector2(60.0, 110.0)
## Escorts engage hostiles this close to their miner, metres.
const ESCORT_GUARD_RADIUS := 1400.0
## Escort formation: side and back offsets from the miner, metres.
const ESCORT_SIDE := 42.0
const ESCORT_BACK := 26.0
## Escort formation: height off the miner (left above, right below), metres.
const ESCORT_RISE := 16.0
## A merc fights back against an attacker within this range, metres.
const RETALIATE_RANGE := 1100.0
## Gives up waiting for a miner to launch after this long, sim seconds.
const ESCORT_WAIT_LIMIT := 120.0
## Repairs are done at this hull fraction.
const REPAIRED := RepairBay.DONE_AT
## Calm this long (no hit, no hostile in guard range) before going home to repair.
const REPAIR_CALM := 6.0
## Lone wolves on a run above their weight retreat this much later.
const SOLO_RETREAT_SCALE := 0.6
## Warp drop-out short of a bounty target, metres (outside den guns).
const HUNT_WARP_DROP := 2200.0
## Escorts and wingmen hop with their lead within this distance, metres.
const FORMATION_WARP_RANGE := 600.0

var mode: Mode = Mode.NONE
var combat_target: Node3D
## True while heading home to repair.
var retreating: bool = false
## The fleet this merc flies in (null when none).
var fleet: MercFleet
## On a bounty above their weight, alone.
var solo_brave: bool = false

var _ai_timer: float = 0.0
var _patrol_until: float = 0.0
var _patrol_point := Vector3.ZERO
var _patrol_angle: float = 0.0
var _wait_time: float = 0.0
var _last_attacker: WeakRef
## The escorted miner has been seen out in space on this trip.
var _ward_was_out: bool = false
var _passing_timer: float = 0.0


func get_status_text() -> String:
	match state:
		State.PATROLLING:
			return "Patrolling" if mode == Mode.PATROL else "Defending home"
		State.ENGAGING:
			var tn := _name_of(combat_target)
			if mode == Mode.ESCORT and _ward():
				return "Escorting %s, engaging" % _ward().get_display_name()
			return "Engaging %s" % tn if not tn.is_empty() else "Engaging"
		State.ESCORTING:
			var w := _ward()
			if w == null:
				return "Waiting for a miner"
			if w.is_docked():
				return "Waiting for %s" % w.get_display_name()
			return "Escorting %s" % w.get_display_name()
		State.HUNTING:
			if fleet:
				var tn := trip.contract.get_target_name() if trip and trip.contract else "?"
				match fleet.state:
					MercFleet.State.FORMING:
						return "Forming up, %s's fleet (%d/%d)" % [fleet.leader_name, fleet.members.size(), fleet.wanted] if fleet.leader != ship \
								else "Calling a fleet for %s (%d/%d)" % [tn, fleet.members.size(), fleet.wanted]
					_:
						return "Leading a fleet of %d to %s" % [fleet.members.size(), tn] if fleet.leader == ship \
								else "In %s's fleet to %s" % [fleet.leader_name, tn]
			if solo_brave:
				return "Hunting %s alone" % (trip.contract.get_target_name() if trip and trip.contract else "bounty")
			return "Hunting bounty"
		State.RETURNING:
			return "Returning for repairs" if retreating else "Returning"
		State.REPAIRING:
			return "Repairing %d%%" % roundi(ship.hull_fraction() * 100.0)
		State.UNDOCKING:
			if mode == Mode.DEFEND:
				return "Scrambling"
	return super.get_status_text()


## The ward when escorting.
func _ward() -> Ship:
	if mode != Mode.ESCORT or trip == null:
		return null
	var ec := trip.contract as EscortContract
	return ec.miner_of(ship) if ec else null


func can_warp() -> bool:
	var calm := _calm()
	match state:
		State.HUNTING:
			if fleet:
				return calm and (fleet.state == MercFleet.State.EN_ROUTE or fleet.state == MercFleet.State.FORMING)
			return calm
		State.ESCORTING:
			return calm
		State.RETURNING:
			return calm and Combat.nearest_hostile(ship.get_tree(), ship.global_position, PANIC_WARP_CLEAR, ship.faction) == null
	return false


## Cruise arcs on bounty runs (solo, or leading a fleet en route), patrols
## and trips home; fights, escorts and wingmen fly straight at their goal.
func cruise_free() -> bool:
	match state:
		State.HUNTING:
			return fleet == null or (fleet.leader == ship and fleet.state == MercFleet.State.EN_ROUTE)
		State.PATROLLING, State.RETURNING:
			return true
	return false


func warp_drop() -> float:
	return HUNT_WARP_DROP if state == State.HUNTING else SpaceNav.WARP_DROP


## Breaking off for repairs counts as fleeing (evasive dives under fire).
func is_fleeing() -> bool:
	return super.is_fleeing() or (state == State.RETURNING and retreating)


## Fleet wingmen attack from their own plane, height and side (AttackRun).
func attack_slot() -> Vector2i:
	if fleet and fleet.members.has(ship):
		return Vector2i(fleet.members.find(ship), fleet.members.size())
	return Vector2i(0, 1)


## Wingmen follow the fleet leader's hops, escorts their miner's.
func warp_lead() -> ShipMover:
	var lead: Ship = null
	if state == State.HUNTING and fleet and fleet.state == MercFleet.State.EN_ROUTE and fleet.leader != ship:
		lead = fleet.leader
	elif state == State.ESCORTING:
		lead = _ward()
	if lead == null or not is_instance_valid(lead) or lead.dead or lead.mover == null or not lead.mover.avoid_enabled:
		return null
	if lead.global_position.distance_to(ship.global_position) > FORMATION_WARP_RANGE:
		return null
	return lead.mover


func destination_name() -> String:
	match state:
		State.HUNTING:
			return trip.contract.get_target_name() if trip and trip.contract else ""
		State.ESCORTING:
			var w := _ward()
			return w.brain.destination_name() if w and w.brain else ""
	return super.destination_name()


func on_attacked(attacker: Node3D) -> void:
	if is_instance_valid(attacker):
		_last_attacker = weakref(attacker)


# --- Update -------------------------------------------------------------------

func update(dt: float) -> void:
	match state:
		State.DOCKED:
			_timer -= dt
			if _timer <= 0.0:
				_set_state(State.EVALUATING)
				_timer = THINK_TIME
		State.EVALUATING:
			_timer -= dt
			if _timer <= 0.0:
				_decide_merc()
		State.REPAIRING:
			_timer -= dt
			if _timer <= 0.0:
				_timer = 1.0
				if _can_scramble() and not home_threats().is_empty():
					last_decision = "Scrambling to defend home"
					_note_scramble(true)
					_launch(Mode.DEFEND, null)
					return
			if ship.hull_fraction() >= REPAIRED:
				_set_state(State.RESTING)
				_timer = rest_duration() * 0.5
			elif not RepairBay.can_afford(ship):
				last_decision = "Out of credits for repairs (hull %d%%)" % roundi(ship.hull_fraction() * 100.0)
				note(CaptainLog.Kind.REPAIR, CaptainLog.Outcome.FAILED, "Stopped repairs at %d%% hull: out of credits" % roundi(ship.hull_fraction() * 100.0),
						"Wallet %s cr, %s cr more would finish the job; flies on damaged" % [UIUtil.amount(captain.wallet if captain else 0), UIUtil.amount(RepairBay.cost_to_repair(ship))], "", "repairs_broke")
				_set_state(State.RESTING)
				_timer = rest_duration() * 0.5
		State.UNDOCKING:
			if ship.mover.path_done():
				ship.enter_space()
				_enter_work_state()
		State.PATROLLING, State.ENGAGING, State.ESCORTING, State.HUNTING:
			_space_update(dt)
		State.RETURNING:
			_fire_in_passing(dt)
			_steer_home()
		State.DOCKING:
			if ship.mover.path_done():
				ship.on_docked_home()
				_end_trip()
				retreating = false
				mode = Mode.NONE
				if ship.hull_fraction() < REPAIRED and RepairBay.can_afford(ship):
					_set_state(State.REPAIRING)
					_timer = 1.0
				else:
					_set_state(State.RESTING)
					_timer = rest_duration()
		State.RESTING:
			_timer -= dt
			if _timer <= 0.0:
				_resting_on_break = false
				_set_state(State.DOCKED)
				_timer = rng.randf_range(0.3, 1.5)
		State.IDLE:
			ship.mover.hold()


# --- Decisions ----------------------------------------------------------------

func _decide_merc() -> void:
	if _can_scramble() and not home_threats().is_empty():
		last_decision = "Scrambling to defend home"
		_note_scramble(false)
		_launch(Mode.DEFEND, null)
		return
	if ship.hull_fraction() < REPAIRED and RepairBay.can_afford(ship):
		last_decision = "Repairing"
		note(CaptainLog.Kind.REPAIR, CaptainLog.Outcome.DID, "Stayed in the berth for repairs",
				"Hull %d%%, repairs run to %d%%; the bill is %s cr, the wallet has %s cr" % [roundi(ship.hull_fraction() * 100.0), roundi(REPAIRED * 100.0),
				UIUtil.amount(RepairBay.cost_to_repair(ship)), UIUtil.amount(captain.wallet if captain else 0)], "", "repairs_first")
		_set_state(State.REPAIRING)
		_timer = 1.0
		return
	var e := evaluator.pick(self, ContractBoard.get_available())
	if e and e.accept and _take(e.contract, e):
		return
	if e and not e.accept:
		var target := e.contract.get_target_name()
		var changed := e.reason != last_refusal or target != last_refusal_target
		last_refusal = e.reason
		last_refusal_target = target
		note_refusal(e, changed)
		if changed:
			decided.emit(self, false, "%s: %s" % [target, e.reason])
	var chance := profile.patrol_chance + 0.25 * (Captain.factor(captain.diligence) if captain else 0.0)
	if captain and captain.has_trait(CaptainTraits.GRUDGE):
		chance += 0.15
	if rng.randf() < clampf(chance, 0.05, 0.95):
		last_decision = "Flying a patrol"
		if captain:
			note(CaptainLog.Kind.COMBAT, CaptainLog.Outcome.DID, "Flew a patrol around the station",
					"Patrol chance %d%% per idle look (%s %d%%, Diligence %d%s)" % [roundi(clampf(chance, 0.05, 0.95) * 100.0), captain.get_personality_name(),
					roundi(profile.patrol_chance * 100.0), captain.diligence, ", Grudge +15%" if captain.has_trait(CaptainTraits.GRUDGE) else ""], "", "patrol")
		_launch(Mode.PATROL, null)
		return
	if e == null:
		last_decision = "No contracts posted"
		note_idle()
	elif not e.accept:
		last_decision = "Refused %s: %s" % [e.contract.get_target_name(), e.reason.to_lower()]
	_back_to_docked()


func _take(contract: Contract, e: RoleEvaluator.Evaluation = null) -> bool:
	var bounty := contract as BountyContract
	var terms: Dictionary = e.terms if e else {}
	if terms.has("join_fleet"):
		if bounty == null or bounty.fleet == null:
			return false
		join_fleet(bounty.fleet, e)
		return fleet != null
	if not contract.add_taker(ship):
		return false
	var m := Mode.BOUNTY if contract is BountyContract else Mode.ESCORT
	var t := Trip.new()
	t.contract = contract
	t.started_at = SimClock.time
	if contract is EscortContract:
		var ec := contract as EscortContract
		var ward := ec.pick_ward()
		if ward:
			ec.assign(ship, ward)
	last_refusal = ""
	last_refusal_target = ""
	last_decision = "Took %s, %s" % [contract.get_target_name(), contract.get_reward_text()]
	if bounty and terms.has("call_fleet"):
		last_decision = "Called a fleet for %s, %s" % [contract.get_target_name(), contract.get_reward_text()]
	elif bounty and terms.has("solo_brave"):
		last_decision = "Took on %s alone, %s" % [contract.get_target_name(), contract.get_reward_text()]
	if bounty and terms.has("call_fleet"):
		note_accept(e, "Called a fleet of %d for %s, %s" % [int(terms["call_fleet"]), DecisionNotes.job_name(contract), contract.get_reward_text()], CaptainLog.Kind.FLEET)
	elif bounty and terms.has("solo_brave"):
		note_accept(e, "Took on %s alone, %s" % [DecisionNotes.job_name(contract), contract.get_reward_text()], CaptainLog.Kind.FLEET)
	else:
		note_accept(e, "Accepted %s, %s" % [DecisionNotes.job_name(contract), contract.get_reward_text()])
	decided.emit(self, true, last_decision)
	_launch(m, t)
	if bounty and terms.has("call_fleet"):
		MercFleet.call_fleet(bounty, ship, float(terms.get("need", 2.0)))
	elif bounty and terms.has("solo_brave"):
		solo_brave = true
		bounty.claim_solo(ship)
		EventLog.post("%s took on the %s alone" % [ship.get_display_name(), contract.get_target_name()], EventLog.Kind.COMBAT, ship)
	return true


# --- Fleets -------------------------------------------------------------------

## Free to answer a fleet call: idle at home or on patrol, repaired.
func can_answer_fleet() -> bool:
	if fleet != null or trip != null or ship.dead or ship.hull_fraction() < MercenaryEvaluator.MIN_HULL:
		return false
	match state:
		State.DOCKED, State.EVALUATING, State.RESTING:
			return true
		State.PATROLLING:
			return mode == Mode.PATROL
	return false


## Joins [param f] and flies out to its rally point.
func join_fleet(f: MercFleet, e: RoleEvaluator.Evaluation = null) -> void:
	var c := f.contract
	if not f.is_recruiting() or not c.add_taker(ship):
		return
	var t := Trip.new()
	t.contract = c
	t.started_at = SimClock.time
	last_refusal = ""
	last_refusal_target = ""
	last_decision = "Joined %s's fleet for %s" % [f.leader_name, c.get_target_name()]
	note_accept(e, "Joined %s's fleet for %s, %s" % [f.leader_name, DecisionNotes.job_name(c), c.get_reward_text()], CaptainLog.Kind.FLEET)
	decided.emit(self, true, last_decision)
	_launch(Mode.BOUNTY, t)
	f.join(ship)


## Said no to [param f]'s call ([param e]: the join evaluation).
func decline_fleet(f: MercFleet, reason: String, e: RoleEvaluator.Evaluation = null) -> void:
	last_decision = "Declined %s's fleet: %s" % [f.leader_name, reason.to_lower()]
	if captain == null:
		return
	var why := DecisionNotes.why(self, e) if e else reason
	note(CaptainLog.Kind.FLEET, CaptainLog.Outcome.REFUSED, "Declined %s's fleet for %s: %s" % [f.leader_name, DecisionNotes.job_name(f.contract), reason.to_lower()],
			why, DecisionNotes.detail(self, e) if e else "", DecisionNotes.key_for("decline", f.contract, reason))


## The fleet fell apart around this merc and it goes on alone.
func go_solo() -> void:
	if captain and trip and trip.contract:
		note(CaptainLog.Kind.FLEET, CaptainLog.Outcome.DID, "Fought on alone against %s" % trip.contract.get_target_name(),
				"Last one left in the fleet: the target is nearly down or daring %.2f is high enough (from %.2f)" % [captain.daring(), MercenaryEvaluator.LONE_WOLF_DARING])
	fleet = null
	solo_brave = true
	if trip and trip.contract is BountyContract:
		(trip.contract as BountyContract).claim_solo(ship)
	_enter_work_state()


func _launch(m: Mode, t: Trip) -> void:
	mode = m
	trip = t
	retreating = false
	_wait_time = 0.0
	_ward_was_out = false
	combat_target = null
	if m == Mode.PATROL or m == Mode.DEFEND:
		_patrol_until = SimClock.time + rng.randf_range(PATROL_TIME.x, PATROL_TIME.y)
		_patrol_angle = rng.randf() * TAU
		_patrol_point = Vector3.INF
	if ship.is_docked():
		ship.start_undock()
		_set_state(State.UNDOCKING)
	else:
		_enter_work_state()


func _enter_work_state() -> void:
	match mode:
		Mode.PATROL, Mode.DEFEND:
			_set_state(State.PATROLLING)
		Mode.BOUNTY:
			_set_state(State.HUNTING)
		Mode.ESCORT:
			_set_state(State.ESCORTING)
		_:
			_set_state(State.RETURNING)


## Goes home: drops the contract (repairs) or just ends the patrol.
func return_home(for_repairs: bool) -> void:
	if for_repairs and not retreating and captain:
		EventLog.post("%s returning for repairs" % captain.captain_name, EventLog.Kind.COMBAT, ship)
	retreating = for_repairs
	_end_trip()
	combat_target = null
	_set_state(State.RETURNING)


func _end_trip() -> void:
	var f := fleet
	fleet = null
	if f:
		f.leave(ship, false)
	solo_brave = false
	if trip and trip.contract:
		trip.contract.remove_taker(ship)
	trip = null


## Called by the board when the escorted miner delivered and this escort was paid.
func on_escort_trip_completed(contract: EscortContract, _miner: Ship) -> void:
	if trip and trip.contract == contract:
		return_home(false)


func on_ship_destroyed() -> void:
	var f := fleet
	fleet = null
	if f:
		f.leave(ship, true)
	if solo_brave and trip and trip.contract and captain:
		EventLog.post("%s's solo run on %s ended in wreckage" % [captain.captain_name, trip.contract.get_target_name()], EventLog.Kind.LOSS, null, ship.global_position)
	_end_trip()
	combat_target = null
	_set_state(State.DESTROYED)


# --- In space -----------------------------------------------------------------

func _space_update(dt: float) -> void:
	_ai_timer -= dt
	if _ai_timer <= 0.0:
		_ai_timer = AI_INTERVAL * rng.randf_range(0.8, 1.2)
		if ship.hull_fraction() < retreat_level():
			if captain and not retreating:
				var job := _job_label()
				note(CaptainLog.Kind.RETREAT, CaptainLog.Outcome.DID, "Broke off and went home for repairs" + (" (left %s)" % job if not job.is_empty() else ""),
						"Hull %d%% fell below their retreat level %d%% (%s %d%%, Nerve %+d%%%s)" % [roundi(ship.hull_fraction() * 100.0), roundi(retreat_level() * 100.0),
						captain.get_personality_name(), roundi(profile.retreat_hull * 100.0), -roundi(captain.nerve_offset() * 100.0), ", solo run x%.1f" % SOLO_RETREAT_SCALE if solo_brave else ""])
			return_home(true)
			return
		if _wants_repairs():
			if captain:
				EventLog.post("%s heads home for repairs (hull %d%%)" % [captain.captain_name, roundi(ship.hull_fraction() * 100.0)], EventLog.Kind.INFO, ship)
				note(CaptainLog.Kind.REPAIR, CaptainLog.Outcome.DID, "Ended the %s for repairs" % ("patrol" if mode == Mode.PATROL else "defence"),
						"Hull %d%% after the fight, below their repair level %d%% (%s %d%%), no hostile near, the wallet can pay" % [roundi(ship.hull_fraction() * 100.0),
						roundi(repair_level() * 100.0), captain.get_personality_name(), roundi(profile.repair_hull * 100.0)])
			retreating = true
			_end_trip()
			combat_target = null
			_set_state(State.RETURNING)
			return
		if not _check_job():
			return
		if fleet:
			fleet.update()
			if not is_instance_valid(ship) or ship.dead or state == State.RETURNING:
				return
		combat_target = _pick_target()
	if Combat.is_live_target(combat_target):
		if state != State.ENGAGING:
			_set_state(State.ENGAGING)
		ship.fight_step(combat_target, (ship as MercenaryShip).attack_side if ship is MercenaryShip else 1.0)
		return
	combat_target = null
	if state == State.ENGAGING:
		_enter_work_state()
	match mode:
		Mode.PATROL, Mode.DEFEND:
			_patrol_step(dt)
			_reconsider_contracts(dt)
		Mode.BOUNTY:
			if fleet:
				fleet.steer(ship)
				return
			var t := trip.contract.target if trip else null
			if is_instance_valid(t):
				ship.set_world_goal(t.global_position, Vector3.ZERO, Vector3.ZERO, 60.0)
		Mode.ESCORT:
			_escort_step(dt)


## Damaged mercs still scramble against raiders while the hull is well
## above their retreat level.
func _can_scramble() -> bool:
	return ship.hull_fraction() >= maxf(retreat_level() + 0.25, 0.5)


func _note_scramble(repairing: bool) -> void:
	if captain == null:
		return
	var n := home_threats().size()
	note(CaptainLog.Kind.COMBAT, CaptainLog.Outcome.DID, "Scrambled to defend the station" + (", repairs cut short" if repairing else ""),
			"%d hostile ship%s inside the defence radius (%.1f km at Loyalty %d); hull %d%% is enough to fight" % [n, "" if n == 1 else "s",
			DEFENSE_RADIUS * (1.0 + 0.2 * Captain.factor(captain.loyalty)) / 1000.0, captain.loyalty, roundi(ship.hull_fraction() * 100.0)], "", "scramble")


## "the Scavenger Den bounty", "" when not on a job.
func _job_label() -> String:
	if trip == null or trip.contract == null:
		return ""
	return "the " + DecisionNotes.job_name(trip.contract)


## On patrol: now and then look at the board and take a contract straight
## from space (no need to dock first).
func _reconsider_contracts(dt: float) -> void:
	_timer -= dt
	if _timer > 0.0:
		return
	_timer = rng.randf_range(profile.evaluate_interval.x, profile.evaluate_interval.y)
	if mode != Mode.PATROL or ship.hull_fraction() < MercenaryEvaluator.MIN_HULL:
		return
	var e := evaluator.pick(self, ContractBoard.get_available())
	if e and e.accept:
		_take(e.contract, e)


## Hull fraction below which a patrol ends early for repairs (profile minus
## half the Nerve offset).
func repair_level() -> float:
	return clampf(profile.repair_hull - 0.5 * (captain.nerve_offset() if captain else 0.0), retreat_level(), 0.97)


## After a fight on patrol: damaged past the repair level, calm, can pay.
func _wants_repairs() -> bool:
	if mode != Mode.PATROL and mode != Mode.DEFEND:
		return false
	if ship.hull_fraction() >= repair_level() or ship.durability.seconds_since_hit() < REPAIR_CALM or not RepairBay.can_afford(ship):
		return false
	if Combat.is_live_target(combat_target):
		return false
	return Combat.nearest_hostile(ship.get_tree(), ship.global_position, RETALIATE_RANGE, ship.faction) == null


## Hull fraction below which this captain goes home (profile minus Nerve).
func retreat_level() -> float:
	var r := clampf(profile.retreat_hull - (captain.nerve_offset() if captain else 0.0), 0.1, 0.8)
	return r * SOLO_RETREAT_SCALE if solo_brave else r


## False when the job ended (and the merc is now returning).
func _check_job() -> bool:
	match mode:
		Mode.PATROL, Mode.DEFEND:
			if SimClock.time > _patrol_until and home_threats().is_empty():
				return_home(false)
				return false
		Mode.BOUNTY:
			if trip == null or trip.contract.is_finished() or not Combat.is_live(trip.contract.target):
				if trip and trip.contract:
					note(CaptainLog.Kind.COMBAT, CaptainLog.Outcome.DID, "Bounty on %s is over, heading home" % trip.contract.get_target_name(),
							"The target is destroyed" if not Combat.is_live(trip.contract.target) else "The contract closed")
				return_home(false)
				return false
		Mode.ESCORT:
			var ec := trip.contract as EscortContract if trip else null
			if ec == null or ec.is_finished():
				return_home(false)
				return false
			var w := ec.miner_of(ship)
			if w == null:
				var nw := ec.pick_ward()
				if nw:
					ec.assign(ship, nw)
			elif not w.is_docked():
				_ward_was_out = true
			elif _ward_was_out and w.brain and w.brain.trip == null:
				# The miner came home without a load to deliver: the trip is over.
				return_home(false)
				return false
		_:
			return_home(false)
			return false
	return true


## Who to shoot now, or null.
func _pick_target() -> Node3D:
	var tree := ship.get_tree()
	var pos := ship.global_position
	# Fight back first.
	var la := _last_attacker.get_ref() as Node3D if _last_attacker else null
	if Combat.is_live_target(la) and ship.durability.seconds_since_hit() < 5.0 and pos.distance_to(la.global_position) < RETALIATE_RANGE:
		return la
	match mode:
		Mode.BOUNTY:
			if fleet:
				# Forming up or on the way: only fight back. Engaging: the focus.
				if fleet.state == MercFleet.State.ENGAGING:
					if Combat.is_live_target(fleet.focus):
						return fleet.focus
					if Combat.is_live_target(trip.contract.target):
						return trip.contract.target
				return null
			var t := trip.contract.target
			if Combat.is_live_target(t):
				return t
		Mode.ESCORT:
			var w := _ward()
			if w and not w.is_docked():
				var wl := w.durability.get_last_attacker() as Node3D
				if Combat.is_live_target(wl) and w.durability.seconds_since_hit() < 6.0:
					return wl
				var near := _hostile_ships_near(tree, w.global_position, ESCORT_GUARD_RADIUS)
				if not near.is_empty():
					return near[0]
		Mode.PATROL, Mode.DEFEND:
			var threats := home_threats()
			var best: Node3D = null
			var best_d := INF
			for h in threats:
				var d := Combat.flat_distance(pos, h.global_position)
				if d < best_d:
					best_d = d
					best = h
			return best
	# Keep the current target while it stays close.
	if Combat.is_live_target(combat_target) and pos.distance_to(combat_target.global_position) < RETALIATE_RANGE:
		return combat_target
	return null


## Hostile ships (not dens) inside the home defence radius.
func home_threats() -> Array[Node3D]:
	var tree := ship.get_tree()
	var sys := tree.get_first_node_in_group(SolarSystem.GROUP) as SolarSystem
	if sys == null or sys.home_station == null:
		var none: Array[Node3D] = []
		return none
	var r := DEFENSE_RADIUS * (1.0 + 0.2 * (Captain.factor(captain.loyalty) if captain else 0.0))
	return _hostile_ships_near(tree, sys.home_station.global_position, r)


func _hostile_ships_near(tree: SceneTree, pos: Vector3, radius: float) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for h in Combat.hostiles_near(tree, pos, radius, ship.faction):
		if h is Ship:
			out.append(h)
	return out


func _patrol_step(_dt: float) -> void:
	var sys := ship.get_tree().get_first_node_in_group(SolarSystem.GROUP) as SolarSystem
	if sys == null or sys.home_station == null:
		return
	var st := sys.home_station
	var r := lerpf(PATROL_RADIUS.x, PATROL_RADIUS.y, 0.5 + 0.5 * sin(_patrol_angle * 1.7))
	var goal := st.global_position + Vector3(cos(_patrol_angle), 0.0, sin(_patrol_angle)) * r
	if Combat.flat_distance(ship.global_position, goal) < 140.0:
		_patrol_angle += rng.randf_range(0.5, 1.1)
	ship.set_world_goal(goal, SpaceNav.world_velocity(st), Vector3.ZERO, 60.0, ship.max_speed * 0.6)


func _escort_step(dt: float) -> void:
	var ec := trip.contract as EscortContract
	var w := ec.miner_of(ship)
	if w == null:
		# Linked contract with no miner out yet: wait off a mining outpost.
		_wait_time += dt
		if _wait_time > ESCORT_WAIT_LIMIT:
			return_home(false)
			return
		var spot := _waiting_spot(ec, null)
		ship.set_world_goal(spot["pos"], spot["vel"], Vector3.ZERO, 40.0)
		return
	if w.is_docked() or (w.brain and (w.brain.state == CaptainBrain.State.DOCKING or w.brain.state == CaptainBrain.State.UNDOCKING)):
		var spot := _waiting_spot(ec, w)
		ship.set_world_goal(spot["pos"], spot["vel"], Vector3.ZERO, 40.0)
		return
	_wait_time = 0.0
	var idx := maxi(ec.escorts_of(w).find(ship), 0)
	var side := -1.0 if idx % 2 == 0 else 1.0
	var row := floorf(idx / 2.0)
	var fwd := w.global_basis * Vector3.FORWARD
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP)
	# 3D slots: the left escort rides above the ward, the right one below.
	var pos := w.global_position + right * side * (ESCORT_SIDE + row * 26.0) - fwd * (ESCORT_BACK + row * 22.0) \
			- Vector3.UP * side * (ESCORT_RISE + row * 12.0)
	var vel := w.get_world_velocity()
	var face := fwd if ship.global_position.distance_to(pos) < 120.0 else Vector3.ZERO
	ship.set_world_goal(pos, vel, face, 10.0)


## Where to wait for [param w] (or any miner of the contract) to launch.
func _waiting_spot(ec: EscortContract, w: Ship) -> Dictionary:
	var b: Building = w.home if w else null
	if b == null and ec.mining_contract:
		for t in ec.mining_contract.takers:
			if t is Ship and is_instance_valid((t as Ship).home):
				b = (t as Ship).home
				break
	if b == null:
		var tree := ship.get_tree()
		var mgr := tree.get_first_node_in_group(BuildingManager.GROUP) as BuildingManager
		if mgr:
			for bb in mgr.buildings:
				if bb.def.hire_ship_script == null and bb.def.can_hire():
					b = bb
					break
	if b == null:
		return {"pos": home_position(), "vel": Vector3.ZERO}
	var p := b.to_global(b.approach_point() + Vector3(30.0, 0.0, 40.0))
	return {"pos": p, "vel": SpaceNav.world_velocity(b)}


## While flying home: shoot what crosses the nose, do not chase.
func _fire_in_passing(dt: float) -> void:
	if ship.weapon == null or ship.is_docked() or not ship.is_inside_tree():
		return
	_passing_timer -= dt
	if _passing_timer <= 0.0:
		_passing_timer = AI_INTERVAL
		combat_target = Combat.nearest_hostile(ship.get_tree(), ship.global_position, ship.stats.weapon_range, ship.faction)
	if Combat.is_live_target(combat_target):
		ship.weapon.try_fire(combat_target)


func _name_of(n: Variant) -> String:
	if is_instance_valid(n) and (n as Object).has_method(&"get_display_name"):
		return String((n as Object).call(&"get_display_name"))
	return ""

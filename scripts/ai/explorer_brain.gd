class_name ExplorerBrain
extends CaptainBrain
## An explorer's decisions (P3): explore contracts scored by
## ExplorerEvaluator, then the expedition. The trip keeps the survey data
## ([Survey], trip.meta["survey"]) the whole way and is never dropped by a
## gate trip:
## - out: GateTransit through the gates to the contract's gate and beyond
##   (state TRAVELING_TO_JOB; the transit hands the ship back at the target,
##   [method takes_ship_back]);
## - SURVEYING: flies the waypoint rings, sweeping every
##   [constant Survey.REVEAL_INTERVAL] with Survey.reveal_along (the same
##   call the abstract walk makes), the sensor dish turning; under threat
##   it runs (evasive dives, a warp hop as soon as no raider is within
##   it runs: its route skips ahead to the first waypoint at least
##   [constant ESCAPE_DIST] from the raider and its long-range drive spools
##   a warp hop there as soon as it has not been hit for
##   [constant ESCAPE_CALM] (a spool under way is not broken off by hits);
##   below [constant ABORT_HULL] it breaks the survey off (the contract
##   opens again, its finds still go home);
## - back: GateTransit home by the exit gate (RETURNING), then docks at the
##   outpost and delivers the survey (ContractBoard.deliver_survey: paid
##   once, the system known).
## While the ship is data the same survey is walked by Survey.step_data;
## [method restore] puts a re-created ship back where it was.

## Hull share below which the survey is broken off.
const ABORT_HULL := 0.35
## Sim seconds on one waypoint before it is skipped (stuck behind a body).
const LEG_GIVE_UP := 150.0
## Running from raiders: skip to a waypoint this far from the nearest one,
## metres, and spool the escape hop after this long without a hit, sim s.
const ESCAPE_DIST := 7000.0
const ESCAPE_CALM := 1.0
## Hostiles within this distance count when picking the escape point, metres.
const ESCAPE_SCAN := 3000.0

var _reveal_timer := 0.0
var _leg_time := 0.0
var _hit_noted := false


# --- Survey data --------------------------------------------------------------

func survey() -> Dictionary:
	return trip.meta.get("survey", {}) if trip else {}


func explore_contract() -> ExploreContract:
	return trip.contract as ExploreContract if trip else null


func _here() -> StringName:
	var w := SystemWorld.of(ship)
	return w.system_id if w else ClusterNetwork.HOME_ID


func _target_name() -> String:
	var def := Sector.system_def(StringName(survey().get("target", "")))
	return def.system_name if def else "?"


# --- Decisions ----------------------------------------------------------------

func _take(contract: Contract, e: RoleEvaluator.Evaluation = null) -> bool:
	var ec := contract as ExploreContract
	if ec == null:
		return super._take(contract, e)
	if not contract.add_taker(ship):
		return false
	trip = _begin_trip(contract)
	var s := Survey.make(ec, ship)
	trip.meta["survey"] = s
	last_decision = "Took %s, %s" % [ec.get_target_name(), ec.get_reward_text()]
	note_accept(e, "Accepted %s, %s" % [DecisionNotes.job_name(contract), contract.get_reward_text()])
	decided.emit(self, true, "Took %s, %s" % [ec.target_name(), ec.get_reward_text()])
	ec.note_progress(s)
	if GateTransit.start(ship, Survey.hops_out(s)) == null:
		_abort_trip()
		_back_to_docked()
		return false
	return true


## "Ostra behind Ostra Gate, 1 jump, danger ?".
static func explore_line(e: RoleEvaluator.Evaluation) -> String:
	var ec := e.contract as ExploreContract
	var j := int(e.terms.get("jumps", 1))
	return "%s behind %s, %d jump%s, danger %s" % [ec.target_name(), ec.gate_name, j, "" if j == 1 else "s",
			str(int(e.terms.get("danger_level", 1))) if bool(e.terms.get("known", false)) else "?"]


func note_accept(e: RoleEvaluator.Evaluation, headline: String, kind: CaptainLog.Kind = CaptainLog.Kind.CONTRACT) -> void:
	if e and e.contract is ExploreContract:
		headline = "Explore: %s for %s cr" % [explore_line(e), Fmt.amount(e.contract.reward)]
	super.note_accept(e, headline, kind)


func note_idle() -> void:
	note(CaptainLog.Kind.CONTRACT, CaptainLog.Outcome.DID, "Waited: no explore contracts posted",
			"Explorers only fly through a gate with an explore contract on it", "", "idle")


# --- Gate trips -----------------------------------------------------------------

## The trip (and its survey) stays on through the gates.
func begin_transit() -> void:
	if trip == null or not (trip.contract is ExploreContract):
		super.begin_transit()
		return
	_set_state(State.TRAVELING_TO_JOB if String(survey().get("phase", "")) == Survey.PHASE_OUT else State.RETURNING)


func takes_ship_back() -> bool:
	return trip != null and String(survey().get("phase", "")) == Survey.PHASE_OUT and _here() == StringName(survey().get("target", ""))


func end_transit() -> void:
	if trip == null or not (trip.contract is ExploreContract):
		super.end_transit()
		return
	if takes_ship_back():
		_begin_survey()
	else:
		_set_state(State.RETURNING)
	ship.status_changed.emit(ship)


# --- Update -------------------------------------------------------------------------

func update(dt: float) -> void:
	match state:
		State.SURVEYING:
			_survey_step(dt)
			return
		State.TRAVELING_TO_JOB:
			_resume_out()
			return
		State.RETURNING:
			if _here() != ClusterNetwork.HOME_ID:
				_resume_home()
				return
	super.update(dt)


## On the way out without a gate trip (after a load): start one, or survey
## when already there.
func _resume_out() -> void:
	var s := survey()
	if s.is_empty():
		_abort_trip()
		_set_state(State.RETURNING)
		return
	var here := _here()
	if here == StringName(s["target"]):
		_begin_survey()
		return
	var hops := Survey.hops_out(s) if here == ClusterNetwork.HOME_ID else Sector.hops_between(here, StringName(s["from"]))
	if here != ClusterNetwork.HOME_ID:
		hops.append(String(s["gate"]))
	if GateTransit.start(ship, hops) == null:
		_abort_trip()
		_set_state(State.RETURNING)


## Out in another system without a gate trip: the gates home.
func _resume_home() -> void:
	var s := survey()
	var hops := Survey.hops_home(s, _here()) if not s.is_empty() else Sector.hops_between(_here(), ClusterNetwork.HOME_ID)
	if hops.is_empty() or GateTransit.start(ship, hops) == null:
		_set_state(State.IDLE)


func _begin_survey() -> void:
	var s := survey()
	Survey.begin(s, ship.global_position)
	_reveal_timer = 0.0
	_leg_time = 0.0
	_hit_noted = false
	_set_state(State.SURVEYING)
	_sweep()
	var ec := explore_contract()
	if ec:
		ec.note_progress(s)
	note(CaptainLog.Kind.CONTRACT, CaptainLog.Outcome.DID, "Arrived in %s: surveying it" % _target_name(),
			"%d waypoints on %s, sweep radius %.1f km (sensor %d m, Surveying %d)" % [(s["points"] as PackedVector3Array).size(),
			"rings around the star", float(s["radius"]) / 1000.0, roundi(ship.stats.sensor_range) if ship.stats else 0, captain.skill if captain else 5])


func _sweep() -> void:
	var s := survey()
	Survey.reveal_along(_here(), ship.global_position, float(s["radius"]), String(s["finder"]), int(s["captain"]))
	DerelictLoot.queue_near(s, _here(), ship.global_position, float(s["radius"]))


func _survey_step(dt: float) -> void:
	var s := survey()
	if s.is_empty():
		_set_state(State.RETURNING)
		return
	_reveal_timer -= dt
	if _reveal_timer <= 0.0:
		_reveal_timer = Survey.REVEAL_INTERVAL
		_sweep()
	current_threat(dt)
	if ship.hull_fraction() < ABORT_HULL:
		_abort_survey("hull %d%%" % roundi(ship.hull_fraction() * 100.0))
		return
	if not is_fleeing() and _visit_step(dt):
		return
	var pts: PackedVector3Array = s["points"]
	var i := int(s["i"])
	if i >= pts.size():
		_finish_survey()
		return
	if is_fleeing() and ship.mover.warp_state == ShipMover.Warp.IDLE:
		i = _escape_index(pts, i)
		s["i"] = i
	var goal := pts[i]
	ship.set_world_goal(goal, Vector3.ZERO, Vector3.ZERO, 300.0)
	_leg_time += dt
	var reached := ship.mover.warp_state == ShipMover.Warp.IDLE and SpaceNav.flat_distance(ship.global_position, goal) < Survey.REACH
	if reached or _leg_time > LEG_GIVE_UP:
		s["i"] = i + 1
		_leg_time = 0.0
		var ec := explore_contract()
		if ec:
			ec.note_progress(s)
		ship.status_changed.emit(ship)


## A derelict on the salvage list (DerelictLoot): flies to it, hovers
## DerelictLoot.HOVER and strips it (the abstract walk does the same,
## Survey._visit_data). True while busy with one.
func _visit_step(dt: float) -> bool:
	var s := survey()
	var v := DerelictLoot.next_visit(s)
	if v.is_empty():
		return false
	if not s.has("visit"):
		s["visit"] = v
		s["visit_t"] = 0.0
		_leg_time = 0.0
		ship.status_changed.emit(ship)
	var at := DerelictLoot.hover_point(_here(), v)
	ship.set_world_goal(at, Vector3.ZERO, Vector3.ZERO, 40.0)
	if ship.mover.warp_state == ShipMover.Warp.IDLE and ship.global_position.distance_to(at) < DerelictLoot.REACH:
		s["visit_t"] = float(s.get("visit_t", 0.0)) + dt
		if float(s["visit_t"]) >= DerelictLoot.HOVER:
			var got := DerelictLoot.salvage(_here(), s, v)
			_leg_time = 0.0
			if not got.is_empty():
				note(CaptainLog.Kind.CONTRACT, CaptainLog.Outcome.DID, "Salvaged %s" % v, got)
			ship.status_changed.emit(ship)
	else:
		_leg_time += dt
		if _leg_time > LEG_GIVE_UP:
			DerelictLoot.end_visit(s, v)
			_leg_time = 0.0
	return true


## Running: the first waypoint from [param i] on at least ESCAPE_DIST from
## the nearest raider (a warp hop away), else [param i].
func _escape_index(pts: PackedVector3Array, i: int) -> int:
	var h := ship.nearest_hostile(ESCAPE_SCAN)
	if h == null:
		return i
	for k in range(i, pts.size()):
		if SpaceNav.flat_distance(pts[k], h.global_position) >= ESCAPE_DIST and SpaceNav.flat_distance(pts[k], ship.global_position) > SpaceNav.WARP_MIN_LEG + SpaceNav.WARP_DROP:
			if k != i:
				var ec := explore_contract()
				if ec:
					ec.note_progress(survey())
			return k
	return i


## Route flown: charts aboard, through the exit gate and home.
func _finish_survey() -> void:
	var s := survey()
	var here := _here()
	Survey.finish(s, here)
	trip.loaded = true
	var ec := explore_contract()
	if ec:
		ec.note_progress(s)
	note(CaptainLog.Kind.CONTRACT, CaptainLog.Outcome.DID, "Surveyed %s, heading home" % _target_name(), Survey.tally_text(here))
	var hops := Survey.hops_home(s, here)
	if hops.is_empty() or GateTransit.start(ship, hops) == null:
		_set_state(State.RETURNING)


## Too much damage: the contract opens again, the finds still go home.
func _abort_survey(why: String) -> void:
	var s := survey()
	s["phase"] = Survey.PHASE_BACK
	s["aborted"] = true
	trip.loaded = false
	var ec := explore_contract()
	if ec:
		ec.release_explorer(captain)
	EventLog.post("%s broke off the survey of %s (%s) and is heading home" % [ship.get_display_name(), _target_name(), why], EventLog.Kind.COMBAT, ship)
	note(CaptainLog.Kind.RETREAT, CaptainLog.Outcome.DID, "Broke off the survey of %s" % _target_name(), "%s, below %d%%: home with what was found" % [why.capitalize(), roundi(ABORT_HULL * 100.0)])
	var hops := Survey.hops_home(s, _here())
	if hops.is_empty() or GateTransit.start(ship, hops) == null:
		_set_state(State.RETURNING)


func on_attacked(attacker: Node3D) -> void:
	if _hit_noted or state != State.SURVEYING:
		return
	_hit_noted = true
	var by := String(attacker.call(&"get_display_name")) if is_instance_valid(attacker) and attacker.has_method(&"get_display_name") else "raiders"
	EventLog.post("%s is under fire in %s (%s), running" % [ship.get_display_name(), _target_name(), by], EventLog.Kind.COMBAT, ship, Vector3.INF, "explorer_hit:%s" % ship.get_display_name())


# --- Delivery ---------------------------------------------------------------------------

func _deliver() -> void:
	var ec := explore_contract()
	if ec == null:
		super._deliver()
		return
	var s := survey()
	var id := StringName(s.get("target", ec.target_system))
	DerelictLoot.deliver(ship, s)
	if trip.loaded and not bool(s.get("aborted", false)):
		var pay := ContractBoard.deliver_survey(ec, ship, s)
		if captain:
			captain.add_reputation(Reputation.for_load(AsteroidBelt.OreType.TITANIUM, ec.get_danger()) * 2.0)
			captain.note_job(false)
		ship.on_cargo_delivered()
		ship.show_toast("+%d cr survey" % pay, Ship.TOAST_REWARD)
		note(CaptainLog.Kind.CONTRACT, CaptainLog.Outcome.DID, "Delivered the survey of %s for %s cr" % [_target_name(), Fmt.amount(pay)], Survey.tally_text(id))
	else:
		var n := Sector.deliver_discoveries(id, SaveIds.of(captain))
		if captain:
			captain.discoveries += n
		DiscoveryBounty.pay(id, SaveIds.of(captain), captain)
		if not bool(s.get("aborted", false)):
			_release(ec)
	trip = null


# --- Flight hooks ------------------------------------------------------------------------

func can_warp() -> bool:
	if state == State.SURVEYING:
		# A hop under way is kept; a new one spools once not hit for a moment.
		return ship.mover.warp_state != ShipMover.Warp.IDLE or ship.durability.seconds_since_hit() > ESCAPE_CALM
	return super.can_warp()


func cruise_free() -> bool:
	return state == State.SURVEYING or super.cruise_free()


## Surveying under threat (evasive dives; not while spooling, the hop
## needs a level ship).
func is_fleeing() -> bool:
	return super.is_fleeing() or (state == State.SURVEYING and _threat >= flee_level() and ship.mover.warp_state == ShipMover.Warp.IDLE)


func destination_name() -> String:
	if state == State.SURVEYING:
		return "the next waypoint"
	return super.destination_name()


func get_status_text() -> String:
	var s := survey()
	match state:
		State.SURVEYING:
			var n := (s.get("points", PackedVector3Array()) as PackedVector3Array).size()
			var run := ", running" if is_fleeing() else ""
			if s.has("visit"):
				return "Salvaging %s in %s%s" % [String(s["visit"]), _target_name(), run]
			return "Surveying %s, waypoint %d of %d%s" % [_target_name(), mini(int(s.get("i", 0)) + 1, n), n, run]
		State.TRAVELING_TO_JOB:
			return "Heading for %s" % _target_name()
		State.RETURNING:
			if _here() != ClusterNetwork.HOME_ID:
				var def := Sector.system_def(_here())
				return "Heading home from %s" % (def.system_name if def else "?")
			if trip and trip.loaded:
				return "Returning with the %s charts" % _target_name()
	return super.get_status_text()


# --- Save -------------------------------------------------------------------------------

## A ship re-created from a save or from data ([param docked] in its
## berth): the state and trip it had (ShipCodec).
func restore(saved: State, saved_trip: CaptainBrain.Trip, docked: bool) -> void:
	trip = saved_trip if saved_trip and saved_trip.contract is ExploreContract else null
	var st := saved
	if docked:
		match saved:
			State.DOCKED, State.EVALUATING, State.RESTING, State.REPAIRING, State.UNLOADING:
				trip = null
			State.DOCKING:
				pass
			State.UNDOCKING, State.TRAVELING_TO_JOB:
				st = State.TRAVELING_TO_JOB if trip else State.DOCKED
			_:
				trip = null
				st = State.DOCKED
	else:
		match saved:
			State.SURVEYING, State.TRAVELING_TO_JOB, State.RETURNING:
				if trip == null:
					st = State.RETURNING
			_:
				st = State.RETURNING
	var ec := explore_contract()
	if ec:
		ec.attach_ship(ship)
	if trip:
		# Live again: the abstract walk's bookkeeping (Survey.step_data) is stale.
		var s := survey()
		s.erase("walk_from")
		s.erase("walk_n")
	state = st
	state_changed.emit(self)

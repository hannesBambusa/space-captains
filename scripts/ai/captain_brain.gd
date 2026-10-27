class_name CaptainBrain
extends RefCounted
## A captain's decisions. Generic over roles: the [RoleEvaluator] scores
## contracts, the ship does the role-specific work through its job hooks
## (Ship.job_begin / job_target / job_work / job_end), and the brain runs the
## trip: undock, travel, work, return, dock, unload, rest.
##
## Docked captains re-evaluate every few sim seconds (profile interval plus
## jitter, so they do not all decide on the same frame). A refusal is
## remembered with its reason for the UI.
##
## Stage 2: [method assess_threat] reads nearby hostiles, recent hits and
## escort cover; above the captain's flee level (profile plus Nerve) the
## captain abandons the job and flees (FLEEING) toward home, or toward the
## nearest friendly mercenary when one is closer. Attributes feed the pacing
## (Diligence: rest and breaks). Subclasses (MercenaryBrain) reuse the
## undock / dock / rest steps and add their own work states.
##
## Stage 3: deliveries earn reputation (ore and danger raise it) and count
## toward traits (Crystal Hound, Lone Wolf); back in the berth the ship
## counts the trip's damage (Ship.on_docked_home). Salvage runs the same
## trip (SalvagerShip does the work, the Salvage Yard pays per load, a posted
## contract adds a bonus).
## Repairs: a badly damaged captain who can pay waits in the berth for the
## (paid, RepairBay) repairs before the next trip.
## Warp hops (ShipMover): allowed on the way out and home while nothing
## threatens the ship; a fleeing captain may make a panic hop only with no
## hostile within [constant PANIC_WARP_CLEAR] and no hit for
## [constant WARP_HIT_CALM] (scavengers in a belt still catch slow miners).
## Escorted mining (an EscortContract linked to the trip's mining contract):
## the miner leaves only with an escort beside it (WAITING_ESCORT in the
## berth until one is within [constant ESCORT_JOIN_RANGE]), flies at the
## slowest escort's pace, holds where it is when its escorts fall behind
## ([constant ESCORT_LOST_RANGE]), hops only with them in formation (they
## jump with it), and turns back home to wait when no escort is left on the
## way out. On the way home with a load it waits for its escorts the same way,
## but flies on alone when they are gone. Cancelling the escort contract
## releases the waiting miners.

signal state_changed(brain: CaptainBrain)
## A decision on a contract: accepted, or refused with a reason.
signal decided(brain: CaptainBrain, accepted: bool, text: String)

enum State {
	DOCKED, IDLE, EVALUATING, UNDOCKING, TRAVELING_TO_JOB, MINING, RETURNING, DOCKING, UNLOADING, RESTING, FLEEING,
	PATROLLING, ENGAGING, ESCORTING, HUNTING, REPAIRING, DESTROYED, SURVEYING, WAITING_ESCORT,
}

const STATE_NAMES: PackedStringArray = [
	"Docked", "Idle", "Evaluating", "Undocking", "En route", "Mining", "Returning", "Docking", "Unloading", "Resting", "Fleeing",
	"Patrolling", "Engaging", "Escorting", "Hunting bounty", "Repairing", "Destroyed", "Surveying", "Waiting for an escort",
]
const ORE_NAMES: PackedStringArray = ["rock", "iron", "titanium", "crystal"]
## Sim seconds spent "thinking" in EVALUATING (so the UI can show it).
const THINK_TIME := 1.0
const UNLOAD_TIME := 4.0
## Distance to the outpost's approach point at which the ship matches its
## frame and starts the docking path, metres.
const DOCK_HANDOFF_DISTANCE := 120.0
## Height gap to the approach point at which the home frame takes over, metres.
const DOCK_HANDOFF_HEIGHT := 25.0
## Hostiles within this distance raise the threat level, metres.
const THREAT_RADIUS := 1300.0
## Friendly mercenaries within this distance lower it (escort cover), metres.
const COVER_RADIUS := 600.0
## Sim seconds between threat checks.
const THREAT_INTERVAL := 0.4
## A fleeing captain runs to a mercenary closer than this instead of home.
const RUN_TO_MERC_RANGE := 2500.0
## Warp hops: no hostile this close for a panic hop, metres; no hit this long, sim seconds.
const PANIC_WARP_CLEAR := 1500.0
const WARP_HIT_CALM := 5.0
## Escorted trips: an escort this close has joined (leave, resume), metres.
const ESCORT_JOIN_RANGE := 450.0
## Escorts farther than this behind: hold and wait for them, metres.
const ESCORT_LOST_RANGE := 650.0
## Escorted trips fly at this share of the slowest escort's top speed.
const ESCORT_PACE := 0.85


class Trip:
	var contract: Contract
	var started_at: float = 0.0
	## Stage 2: escorts may attach to trips that ask for it.
	var escort_requested: bool = false
	## Free-form data for later systems (escort ship, threat notes).
	var meta: Dictionary = {}
	## Work progress 0..1 (mining: drilling).
	var progress: float = 0.0
	## Mining: belt asteroid index, its ore, the hover point in belt space.
	var asteroid: int = -1
	var ore: int = 0
	var standoff_local := Vector3.ZERO
	var work_time: float = 10.0
	## Cargo aboard (a mined load).
	var loaded: bool = false
	## Share of the load still aboard (scavengers can take part of it).
	var cargo: float = 1.0


var ship: Ship
var captain: Captain
var profile: PersonalityProfile
var evaluator: RoleEvaluator
var state: State = State.DOCKING
var trip: Trip
var rng := RandomNumberGenerator.new()
## Last refusal, for the UI ("" when the last decision was a yes).
var last_refusal: String = ""
var last_refusal_target: String = ""
## Mercenaries: the latest refusal per target, with its numbers (target
## panel): target name -> [reason line, SimClock.time]. Not saved.
var refusal_lines: Dictionary = {}
## Refusal lines older than this (sim seconds) are not shown.
const REFUSAL_LINE_TTL := 120.0
## Last decision line for the UI ("Took Cinder Cluster", "Refused Talon Reach: ...").
var last_decision: String = ""

var _timer: float = 0.0
var _resting_on_break: bool = false
var _threat_timer: float = 0.0
var _threat: float = 0.0
## While fleeing: the friendly ship being run to (null = home).
var _flee_to: Ship
var _calm_time: float = 0.0
## Escorted trip: holding in space for escorts that fell behind.
var _escort_holding: bool = false
## Escorted trip: turned back on the way out, docks to wait (saved).
var _escort_wait_home: bool = false


func _init(owner_ship: Ship, role_evaluator: RoleEvaluator) -> void:
	ship = owner_ship
	captain = owner_ship.captain
	evaluator = role_evaluator
	profile = PersonalityProfile.for_personality(captain.personality if captain else Captain.Personality.BOLD)
	rng.randomize()


func get_state_name() -> String:
	return STATE_NAMES[state]


func get_status_text() -> String:
	match state:
		State.TRAVELING_TO_JOB:
			return "En route to %s" % _trip_target_name()
		State.MINING:
			return "Mining %d%%" % roundi((trip.progress if trip else 0.0) * 100.0)
		State.RETURNING:
			if trip and trip.loaded:
				return "Returning with %s" % ORE_NAMES[clampi(trip.ore, 0, ORE_NAMES.size() - 1)]
			return "Returning"
		State.UNLOADING:
			return "Unloading"
		State.RESTING:
			return "Taking a break" if _resting_on_break else "Resting"
		State.FLEEING:
			if is_instance_valid(_flee_to):
				return "Fleeing to %s" % _flee_to.get_display_name()
			return "Fleeing home"
		State.WAITING_ESCORT:
			var mine := _assigned_escorts()
			if not ship.is_docked():
				return "Returning to wait for an escort"
			if not mine.is_empty():
				return "Waiting for escort %s" % mine[0].get_display_name()
			return "Waiting for an escort"
	if _escort_holding and (state == State.TRAVELING_TO_JOB or state == State.RETURNING):
		var mine := _assigned_escorts()
		return "Waiting for escort %s" % mine[0].get_display_name() if not mine.is_empty() else "Waiting for an escort"
	return get_state_name()


func is_on_trip() -> bool:
	return trip != null


# --- Warp ---------------------------------------------------------------------

## May the ship warp now (see ShipMover)?
func can_warp() -> bool:
	match state:
		State.TRAVELING_TO_JOB, State.RETURNING:
			return _threat < 0.05 and _calm() and _escorts_can_hop()
		State.WAITING_ESCORT:
			return not ship.is_docked() and _threat < 0.05 and _calm()
		State.FLEEING:
			return _calm() and ship.nearest_hostile(PANIC_WARP_CLEAR) == null
	return false


## May the ship fly its own cruise arc (Ship.cruise_band, CruiseLeg)? On
## the way out and home; fleeing, working and docking fly straight.
func cruise_free() -> bool:
	return state == State.TRAVELING_TO_JOB or state == State.RETURNING


## Drop-out distance before the destination, metres.
func warp_drop() -> float:
	return SpaceNav.WARP_DROP


## Running for safety (Ship.is_fleeing: evasive dives under fire).
func is_fleeing() -> bool:
	return state == State.FLEEING


## (slot, size) in the ship's attack group (Ship.attack_slot); alone by default.
func attack_slot() -> Vector2i:
	return Vector2i(0, 1)


## The mover whose hops this ship follows, or null.
func warp_lead() -> ShipMover:
	return null


## Where the ship is heading, for status lines ("Cinder Cluster", "home").
func destination_name() -> String:
	match state:
		State.TRAVELING_TO_JOB, State.MINING:
			return _trip_target_name()
		State.RETURNING, State.DOCKING:
			return ship.home.display_name if is_instance_valid(ship.home) else "home"
		State.FLEEING:
			return _flee_to.get_display_name() if is_instance_valid(_flee_to) else (ship.home.display_name if is_instance_valid(ship.home) else "home")
	return ""


func _calm() -> bool:
	return ship.durability.seconds_since_hit() > WARP_HIT_CALM


## World position of the home outpost (or the ship when homeless).
func home_position() -> Vector3:
	if ship.home and is_instance_valid(ship.home):
		return ship.home.global_position
	return ship.global_position


## Called when the ship is placed in its berth instantly.
func on_snapped_to_berth() -> void:
	if state == State.DOCKING:
		_set_state(State.DOCKED)
		_timer = rng.randf_range(0.2, 1.0)


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
				_decide()
		State.UNDOCKING:
			if ship.mover.path_done():
				ship.enter_space()
				if ship.job_begin(trip):
					_set_state(State.TRAVELING_TO_JOB)
				else:
					_abort_trip()
					_set_state(State.RETURNING)
		State.TRAVELING_TO_JOB:
			var pace := _escort_pace(false)
			if state != State.TRAVELING_TO_JOB:
				return
			if _escort_holding:
				ship.mover.hold()
				_check_threats(dt)
				return
			_steer_to_job(false, pace)
			if _check_threats(dt):
				return
			if ship.mover.arrived(3.0):
				_set_state(State.MINING)
		State.MINING:
			_steer_to_job(true)
			if _check_threats(dt):
				return
			if ship.job_work(trip, dt * ship.work_speed()):
				ship.job_end(trip)
				trip.loaded = true
				_set_state(State.RETURNING)
		State.RETURNING:
			var pace := -1.0
			if trip and trip.loaded:
				if _check_threats(dt):
					return
				pace = _escort_pace(true)
				if _escort_holding:
					ship.mover.hold()
					return
			else:
				# Keep the threat fresh (can_warp reads it) without fleeing empty.
				current_threat(dt)
			_steer_home(pace)
		State.FLEEING:
			_update_flee(dt)
		State.DOCKING:
			if ship.mover.path_done():
				ship.on_docked_home()
				if trip == null:
					_back_to_docked()
				elif _escort_wait_home and not trip.loaded:
					_set_state(State.WAITING_ESCORT)
					_timer = 0.0
				else:
					_set_state(State.UNLOADING)
					_timer = UNLOAD_TIME
					_deliver()
		State.UNLOADING:
			_timer -= dt
			if _timer <= 0.0:
				_resting_on_break = false
				_set_state(State.RESTING)
				_timer = rest_duration()
		State.RESTING:
			_timer -= dt
			if _timer <= 0.0:
				_resting_on_break = false
				_set_state(State.DOCKED)
				_timer = rng.randf_range(0.3, 1.5)
		State.WAITING_ESCORT:
			_wait_for_escort(dt)
		State.IDLE:
			ship.mover.hold()


# --- Decisions ----------------------------------------------------------------

## [param text] with its first letter in lower case (keeps names in
## reasons like "Claimed by Redwake Corsairs" capitalised).
static func lower_first(text: String) -> String:
	return text.left(1).to_lower() + text.substr(1) if not text.is_empty() else text


## Scores the available contracts now. Returns the chosen evaluation (or the
## best refused one, or null when there is nothing for this role).
func score_contracts(contracts: Array[Contract] = []) -> RoleEvaluator.Evaluation:
	if contracts.is_empty():
		contracts = ContractBoard.get_available(-1, system_id())
	return evaluator.pick(self, contracts)


## The system the ship is in (its contracts are there), "" = unknown (any).
func system_id() -> StringName:
	var w := SystemWorld.of(ship) if is_instance_valid(ship) else null
	return w.system_id if w else &""


func _decide() -> void:
	if RepairBay.should_repair(ship, MercenaryEvaluator.MIN_HULL):
		last_decision = "Repairing first (hull %d%%)" % roundi(ship.hull_fraction() * 100.0)
		note_repairs_first()
		_back_to_docked()
		return
	var contracts := ContractBoard.get_available(-1, system_id())
	var e := evaluator.pick(self, contracts)
	if e == null:
		last_decision = "No contracts posted"
		note_idle()
		_back_to_docked()
		return
	if break_chance() > 0.0 and rng.randf() < break_chance():
		last_decision = "Taking a break"
		_resting_on_break = true
		_set_state(State.RESTING)
		_timer = rng.randf_range(profile.break_time.x, profile.break_time.y)
		if captain:
			note(CaptainLog.Kind.REST, CaptainLog.Outcome.DID, "Took a break instead of working",
					"%s, Diligence %d: break chance %d%% per look at the board (profile %d%%)" % [captain.get_personality_name(), captain.diligence,
					roundi(break_chance() * 100.0), roundi(profile.break_chance * 100.0)],
					"Break of %s (profile %s to %s, sim time)" % [Fmt.clock(_timer), Fmt.clock(profile.break_time.x), Fmt.clock(profile.break_time.y)], "break")
		return
	if e.accept and _take(e.contract, e):
		return
	last_decision = "Refused %s: %s" % [e.contract.get_target_name(), lower_first(e.reason)]
	_record_refusal(e)
	_back_to_docked()


## Remembers the refusal of [param e] for the decision log; the HUD hears of
## it when it is new (another reason or another contract).
func _record_refusal(e: RoleEvaluator.Evaluation) -> void:
	var target := e.contract.get_target_name()
	var changed := e.reason != last_refusal or target != last_refusal_target
	last_refusal = e.reason
	last_refusal_target = target
	if evaluator is MercenaryEvaluator:
		remember_refusal(target, DecisionNotes.merc_refusal_reason(self, e))
	note_refusal(e, changed)
	if changed:
		decided.emit(self, false, "%s: %s" % [target, e.reason])


## Keeps [param line] as the latest refusal of [param target] (target panel).
func remember_refusal(target: String, line: String) -> void:
	refusal_lines[target] = [line, SimClock.time]


## The latest refusal of [param target] within [constant REFUSAL_LINE_TTL], or "".
func refusal_line_for(target: String) -> String:
	var r: Variant = refusal_lines.get(target)
	if r == null or SimClock.time - float(r[1]) > REFUSAL_LINE_TTL:
		return ""
	return String(r[0])


# --- Decision log -------------------------------------------------------------

## Writes a line to the captain's decision log (CaptainLog).
func note(kind: CaptainLog.Kind, outcome: CaptainLog.Outcome, headline: String, why: String = "", detail: String = "", key: String = "") -> void:
	if captain:
		captain.flight_log.note(kind, outcome, headline, why, detail, key)


## Logs a refusal. Unchanged repeats only count up (no text is built).
func note_refusal(e: RoleEvaluator.Evaluation, changed: bool) -> void:
	if captain == null or e == null or e.contract == null:
		return
	var bounty := e.contract as BountyContract
	if e.reason == MercenaryEvaluator.DECLINED and bounty and bounty.fleet:
		# Same line as the answer to the fleet's call (MercenaryBrain.decline_fleet).
		var dkey := DecisionNotes.key_for("decline", e.contract, e.reason)
		if not captain.flight_log.bump(dkey):
			note(CaptainLog.Kind.FLEET, CaptainLog.Outcome.REFUSED, "Declined to join %s's fleet on %s (%s cr): %s" % [bounty.fleet.leader_name, e.contract.get_target_name(), Fmt.amount(e.contract.reward), DecisionNotes.merc_refusal_reason(self, e)],
					DecisionNotes.why(self, e), DecisionNotes.detail(self, e), dkey)
		return
	var merc := evaluator is MercenaryEvaluator
	# Mercenaries: a new line when the numbers move noticeably.
	var key := DecisionNotes.key_for("no", e.contract, e.reason + ("|" + DecisionNotes.merc_refusal_tag(self, e) if merc else ""))
	if not changed and captain.flight_log.bump(key):
		return
	var kind := CaptainLog.Kind.FLEET if e.terms.has("join_fleet") or e.reason == MercenaryEvaluator.FLEET_FULL else CaptainLog.Kind.CONTRACT
	var headline := DecisionNotes.merc_refusal_line(self, e) if merc else "Refused %s: %s" % [DecisionNotes.job_name(e.contract), lower_first(e.reason)]
	note(kind, CaptainLog.Outcome.REFUSED, headline, DecisionNotes.why(self, e), DecisionNotes.detail(self, e), key)


## Logs a taken contract with [param headline].
func note_accept(e: RoleEvaluator.Evaluation, headline: String, kind: CaptainLog.Kind = CaptainLog.Kind.CONTRACT) -> void:
	if captain == null or e == null:
		return
	note(kind, CaptainLog.Outcome.ACCEPTED, headline, DecisionNotes.why(self, e), DecisionNotes.detail(self, e), DecisionNotes.key_for("yes", e.contract))


func note_repairs_first() -> void:
	note(CaptainLog.Kind.REPAIR, CaptainLog.Outcome.DID, "Stayed in the berth for repairs",
			"Hull %d%%, below %d%%, and the wallet (%s cr) can pay the %s cr bill" % [roundi(ship.hull_fraction() * 100.0), roundi(MercenaryEvaluator.MIN_HULL * 100.0),
			Fmt.amount(captain.wallet if captain else 0), Fmt.amount(RepairBay.cost_to_repair(ship))], "", "repairs_first")


func note_idle() -> void:
	note(CaptainLog.Kind.CONTRACT, CaptainLog.Outcome.DID, "Waited: no contracts for a %s" % (captain.role.to_lower() if captain else "ship"),
			"Nothing on the board this role can work", "", "idle")


## Starts a trip on [param contract]. False when it filled up meanwhile.
func _take(contract: Contract, e: RoleEvaluator.Evaluation = null) -> bool:
	if not contract.add_taker(ship):
		return false
	trip = _begin_trip(contract)
	last_decision = "Took %s, %s" % [contract.get_target_name(), contract.get_reward_text()]
	note_accept(e, "Accepted %s, %s" % [DecisionNotes.job_name(contract), contract.get_reward_text()])
	decided.emit(self, true, "Took %s, %s" % [contract.get_target_name(), contract.get_reward_text()])
	if escort_contract() and not _escort_joined():
		_start_escort_wait()
		return true
	ship.start_undock()
	_set_state(State.UNDOCKING)
	return true


## A new trip on [param contract] (the taker is on it already); the last
## refusal is forgotten.
func _begin_trip(contract: Contract) -> Trip:
	var t := Trip.new()
	t.contract = contract
	t.started_at = SimClock.time
	last_refusal = ""
	last_refusal_target = ""
	refusal_lines.erase(contract.get_target_name())
	return t


## Rest after a trip, sim seconds (profile range scaled by Diligence).
func rest_duration() -> float:
	var k := captain.rest_scale() if captain else 1.0
	return rng.randf_range(profile.rest_time.x, profile.rest_time.y) * k


func break_chance() -> float:
	var b := profile.break_chance + (captain.break_bonus() if captain else 0.0)
	return clampf(b, 0.0, 0.6) if profile.break_chance > 0.0 or b > 0.02 else 0.0


## Threat level at which this captain flees (profile plus Nerve).
func flee_level() -> float:
	return clampf(profile.flee_threat + (captain.nerve_offset() if captain else 0.0), 0.1, 0.98)


func _back_to_docked() -> void:
	_set_state(State.DOCKED)
	_timer = rng.randf_range(profile.evaluate_interval.x, profile.evaluate_interval.y)


# --- Trip steps ---------------------------------------------------------------

func _steer_to_job(working: bool, speed: float = -1.0) -> void:
	if trip == null:
		_set_state(State.RETURNING)
		return
	var t := ship.job_target(trip, working)
	if t.is_empty():
		_abort_trip()
		_set_state(State.RETURNING)
		return
	ship.mover.set_goal(t["pos"], t["vel"], speed, true, t.get("face", Vector3.ZERO), 4.0 if working else 6.0)


func _steer_home(speed: float = -1.0) -> void:
	var home := ship.home
	if home == null or not is_instance_valid(home):
		_set_state(State.IDLE)
		return
	# At the complex's height (the station rides its planet's inclined orbit).
	var approach := home.to_global(home.approach_point())
	ship.set_world_goal(approach, SpaceNav.world_velocity(home), Vector3.ZERO, 20.0, speed)
	var rel := approach - ship.global_position
	var dy := absf(rel.y)
	rel.y = 0.0
	if rel.length() < DOCK_HANDOFF_DISTANCE and dy < DOCK_HANDOFF_HEIGHT and ship.mover.relative_speed() < 45.0:
		ship.enter_home_frame()
		ship.start_dock()
		_set_state(State.DOCKING)


func _deliver() -> void:
	if trip == null:
		return
	var c := trip.contract
	if trip.loaded and c is MiningContract:
		var res := ContractBoard.deliver_mining_load(c as MiningContract, ship, trip.ore, trip.cargo)
		var ore := trip.ore
		if captain:
			captain.loads_delivered += 1
		_record_delivery(res, Reputation.for_load(ore, c.get_danger()), "+%d %s" % [int(res["materials"]), Economy.ore_name(Economy.ore_of_belt(ore))],
				func() -> void:
					if ore == AsteroidBelt.OreType.CRYSTAL:
						captain.crystal_loads += 1
						if captain.crystal_loads >= CaptainTraits.CRYSTAL_LOADS:
							captain.add_trait(CaptainTraits.CRYSTAL_HOUND, "%d crystal loads delivered" % captain.crystal_loads))
	elif trip.loaded and c is SalvageContract:
		var scrap := roundi(float(trip.meta.get("scrap", 0)) * trip.cargo)
		var res := ContractBoard.deliver_salvage_load(c as SalvageContract, ship, scrap)
		if captain:
			captain.salvage_loads += 1
		var owed: int = res["owed"]
		_record_delivery(res, Reputation.SALVAGE_LOAD * clampf(float(scrap) / float(SalvageContract.LOAD_SCRAP), 0.3, 1.5),
				"+%d cr, %d scrap to the yard%s" % [int(res["credits"]), int(res["scrap"]), ", %d cr owed" % owed if owed > 0 else ""])
	elif trip.loaded and c is PlanetRaidContract:
		var rc := c as PlanetRaidContract
		var units := roundi(float(trip.meta.get("units", 0)) * trip.cargo / maxf(float(trip.meta.get("cargo_full", 1.0)), 0.01))
		var res := ContractBoard.deliver_raid_load(rc, ship, units, trip.cargo / maxf(float(trip.meta.get("cargo_full", 1.0)), 0.01))
		if captain:
			captain.loads_delivered += 1
			captain.raid_loads += 1
		_record_delivery(res, Reputation.for_load(AsteroidBelt.OreType.TITANIUM, c.get_danger()), "+%d %s" % [int(res["materials"]), Economy.ore_name(rc.loot)])
	else:
		_release(c)
	trip = null


## The captain's tally for a delivered load the board paid ([param res]):
## credits, [param rep] reputation, [param extra] (more tallies, before the
## job counts), the job; then the ship's [param toast].
func _record_delivery(res: Dictionary, rep: float, toast: String, extra: Callable = Callable()) -> void:
	if captain:
		captain.credits_earned += int(res["credits"])
		captain.add_reputation(rep)
		if extra.is_valid():
			extra.call()
		captain.note_job(bool(res.get("escorted", false)))
	ship.on_cargo_delivered()
	ship.show_toast(toast, Ship.TOAST_DELIVERY)


## Ends [param c] for this ship without a delivery.
func _release(c: Contract) -> void:
	if c == null:
		return
	if c is LoadContract:
		(c as LoadContract).finish_trip(ship, false)
	else:
		c.remove_taker(ship)


## A gate trip takes the ship (GateTransit): the job is dropped and the
## brain waits as RETURNING (it does not run until the trip ends).
func begin_transit() -> void:
	_abort_trip()
	_set_state(State.RETURNING)


## The gate trip ended outside home with no hop left: true = the brain
## flies the ship there (an explorer's survey), false = it holds (PARK).
func takes_ship_back() -> bool:
	return false


## Back at home after a gate trip: fly to the outpost and dock.
func end_transit() -> void:
	trip = null
	_set_state(State.RETURNING)
	ship.status_changed.emit(ship)


func _abort_trip() -> void:
	if trip == null:
		return
	_release(trip.contract)
	ship.job_end(trip)
	trip = null


# --- Escorted trips -----------------------------------------------------------

## The open escort contract linked to the trip's mining contract, or null.
func escort_contract() -> EscortContract:
	if trip == null or not (trip.contract is MiningContract):
		return null
	return ContractBoard.escort_for_mining(trip.contract)


## Escorts flying this trip: assigned to this ship and out in space on the
## escort job (not docked, launching or gone home).
func trip_escorts() -> Array[Ship]:
	var out: Array[Ship] = []
	var ec := escort_contract()
	if ec == null:
		return out
	for e in ec.escorts_of(ship):
		if e.dead or e.is_docked() or e.brain == null or e.brain.trip == null or e.brain.trip.contract != ec:
			continue
		if e.brain.state == State.ESCORTING or e.brain.state == State.ENGAGING:
			out.append(e)
	return out


## Escorts the escort contract gave this ship (anywhere).
func _assigned_escorts() -> Array[Ship]:
	var ec := escort_contract()
	if ec == null:
		var none: Array[Ship] = []
		return none
	return ec.escorts_of(ship)


## An escort in formation (escorting, not fighting) within
## [constant ESCORT_JOIN_RANGE], or null.
func _joined_escort() -> Ship:
	for e in trip_escorts():
		if e.brain.state == State.ESCORTING and e.global_position.distance_to(ship.global_position) <= ESCORT_JOIN_RANGE:
			return e
	return null


func _escort_joined() -> bool:
	return _joined_escort() != null


## Escorted trip in space: the speed to fly at (-1 = own), and
## [member _escort_holding] when the escorts fell behind. On the way out
## with no escort left the ship turns back to wait ([param homeward] false).
func _escort_pace(homeward: bool) -> float:
	if escort_contract() == null:
		_escort_holding = false
		return -1.0
	var list := trip_escorts()
	if list.is_empty():
		_escort_holding = false
		if not homeward:
			_turn_back_for_escort()
		return -1.0
	var far := 0.0
	var slow := INF
	for e in list:
		far = maxf(far, e.global_position.distance_to(ship.global_position))
		slow = minf(slow, e.max_speed)
	var was := _escort_holding
	_escort_holding = far > (ESCORT_JOIN_RANGE if _escort_holding else ESCORT_LOST_RANGE)
	if _escort_holding != was:
		ship.status_changed.emit(ship)
		if _escort_holding and captain:
			note(CaptainLog.Kind.CONTRACT, CaptainLog.Outcome.DID, "Held position for %s" % list[0].get_display_name(),
					"Escorted trip: the escort is %d m behind (more than %d m), the miner waits for it" % [roundi(far), roundi(ESCORT_LOST_RANGE)], "", "escort_hold")
	return slow * ESCORT_PACE


## Hops only with every escort in formation and free to jump with it
## (they follow the hop, ShipMover warp_lead).
func _escorts_can_hop() -> bool:
	if escort_contract() == null:
		return true
	for e in trip_escorts():
		if e.brain.state != State.ESCORTING or e.global_position.distance_to(ship.global_position) > ESCORT_JOIN_RANGE or not e.can_warp():
			return false
	return true


## Took an escorted contract with no escort beside it: stay in the berth.
func _start_escort_wait() -> void:
	var mine := _assigned_escorts()
	last_decision = "Waiting for an escort before leaving for %s" % _trip_target_name()
	note(CaptainLog.Kind.CONTRACT, CaptainLog.Outcome.DID, "Waiting for an escort before leaving for %s" % _trip_target_name(),
			("Escorted contract: miners leave only with a mercenary beside them. %s is on the way" % mine[0].get_display_name()) if not mine.is_empty() \
			else "Escorted contract: miners leave only with a mercenary beside them, and no mercenary has taken the escort contract yet", "", "escort_wait")
	_escort_wait_home = false
	_escort_holding = false
	_set_state(State.WAITING_ESCORT)
	_timer = 0.0


## On the way out with no escort left: drop the rock and go home to wait.
func _turn_back_for_escort() -> void:
	ship.job_end(trip)
	trip.progress = 0.0
	_escort_wait_home = true
	_escort_holding = false
	last_decision = "Turned back: no escort"
	note(CaptainLog.Kind.CONTRACT, CaptainLog.Outcome.DID, "Turned back to wait for an escort",
			"No mercenary flies with it any more (lost, gone for repairs or recalled); escorted trips wait for a new one", "", "escort_lost")
	EventLog.post("%s turned back: no escort" % ship.get_display_name(), EventLog.Kind.INFO, ship)
	_set_state(State.WAITING_ESCORT)


## WAITING_ESCORT: in the berth, or flying home to it after turning back.
## Leaves once an escort has joined, or freely once the escort contract is gone.
func _wait_for_escort(dt: float) -> void:
	var docked := ship.is_docked()
	if not docked and _check_threats(dt):
		_escort_wait_home = false
		return
	var mc := trip.contract as MiningContract if trip else null
	if mc == null or mc.is_finished() or mc.depleted:
		_escort_wait_home = false
		_abort_trip()
		if docked:
			_back_to_docked()
		else:
			_set_state(State.RETURNING)
		return
	if escort_contract() == null:
		note(CaptainLog.Kind.CONTRACT, CaptainLog.Outcome.DID, "Left for %s without an escort" % _trip_target_name(), "The escort contract was cancelled", "", "escort_off")
		_leave_for_job(docked)
		return
	var e := _joined_escort()
	if e:
		note(CaptainLog.Kind.CONTRACT, CaptainLog.Outcome.DID, "Left for %s with %s" % [_trip_target_name(), e.get_display_name()],
				"The escort joined %d m off" % roundi(e.global_position.distance_to(ship.global_position)), "", "escort_join")
		_leave_for_job(docked)
		return
	if not docked:
		_steer_home()


func _leave_for_job(docked: bool) -> void:
	_escort_wait_home = false
	_escort_holding = false
	if docked:
		ship.start_undock()
		_set_state(State.UNDOCKING)
	elif ship.job_begin(trip):
		_set_state(State.TRAVELING_TO_JOB)
	else:
		_abort_trip()
		_set_state(State.RETURNING)


# --- Threats ------------------------------------------------------------------

## 0..1 danger near the ship right now: a recent hit, hostiles within
## [constant THREAT_RADIUS] (closer = worse), minus escort cover.
func assess_threat() -> float:
	if ship.dead or not ship.is_inside_tree():
		return 0.0
	var t := 0.0
	if ship.durability.seconds_since_hit() < 4.0:
		t += 0.55
	var pos := ship.global_position
	var hostiles := Combat.hostiles_near(ship, pos, THREAT_RADIUS, ship.faction)
	for h in hostiles:
		var d := SpaceNav.flat_distance(pos, h.global_position)
		t += 0.1 + 0.35 * (1.0 - d / THREAT_RADIUS)
	if t > 0.0:
		t -= 0.2 * float(_friendly_guns_near(pos, COVER_RADIUS).size())
	return clampf(t, 0.0, 1.0)


## Cached threat level, refreshed every [constant THREAT_INTERVAL].
func current_threat(dt: float = 0.0) -> float:
	_threat_timer -= dt
	if _threat_timer <= 0.0:
		_threat_timer = THREAT_INTERVAL
		_threat = assess_threat()
	return _threat


## True when the captain broke off to flee.
func _check_threats(dt: float = 0.1) -> bool:
	if current_threat(dt) < flee_level():
		return false
	flee()
	return true


## Drops the job and runs for safety. Cargo aboard is kept.
func flee() -> void:
	if trip and not trip.loaded:
		_abort_trip()
	_flee_to = _nearest_guardian()
	_calm_time = 0.0
	if state != State.FLEEING and captain:
		EventLog.post("%s is fleeing" % captain.captain_name, EventLog.Kind.COMBAT, ship)
		var threat := current_threat()
		var why := "Threat %.2f reached their flee level %.2f (%s %.2f, Nerve %+.2f)" % [threat, flee_level(), captain.get_personality_name(), profile.flee_threat, captain.nerve_offset()]
		if threat < flee_level():
			why = "Under fire with the shields down" if ship.durability.shields <= 0.0 else "Under fire, hull %d%%: a Nerve %d captain runs early" % [roundi(ship.hull_fraction() * 100.0), captain.nerve]
		note(CaptainLog.Kind.RETREAT, CaptainLog.Outcome.DID, "Fled to %s" % (_flee_to.get_display_name() if is_instance_valid(_flee_to) else "home") + (", dropping the job" if trip == null else ", cargo aboard"),
				why, "Hull %d%%, shields %d%%" % [roundi(ship.hull_fraction() * 100.0), roundi(ship.shield_fraction() * 100.0)])
	_set_state(State.FLEEING)


## Fleeing: run to the guardian until close or the danger passed, then home.
func _update_flee(dt: float) -> void:
	if current_threat(dt) < 0.05:
		_calm_time += dt
	else:
		_calm_time = 0.0
	if is_instance_valid(_flee_to) and not _flee_to.dead and _flee_to.is_targetable():
		var d := ship.global_position.distance_to(_flee_to.global_position)
		if d > 160.0 and _calm_time < 3.0:
			var p := ship.get_parent() as Node3D
			var goal := _flee_to.global_position
			if p:
				goal = p.to_local(goal)
			ship.mover.set_goal(goal, _flee_to.get_world_velocity(), -1.0, false, Vector3.ZERO, 30.0)
			return
	_flee_to = null
	_steer_home()


## Nearest armed friendly ship in open space closer than home, or null.
func _nearest_guardian() -> Ship:
	var pos := ship.global_position
	var home_d := SpaceNav.flat_distance(pos, home_position())
	var best: Ship = null
	var best_d := minf(RUN_TO_MERC_RANGE, home_d)
	for s in _friendly_guns_near(pos, RUN_TO_MERC_RANGE):
		var d := SpaceNav.flat_distance(pos, s.global_position)
		if d < best_d:
			best_d = d
			best = s
	return best


func _friendly_guns_near(pos: Vector3, radius: float) -> Array[Ship]:
	var out: Array[Ship] = []
	for n in SystemWorld.nodes_in(ship, Ship.GROUP):
		var s := n as Ship
		if s == ship or s.dead or s.faction != ship.faction or s.weapon == null or not s.is_targetable():
			continue
		if SpaceNav.flat_distance(pos, s.global_position) <= radius:
			out.append(s)
	return out


## The ship blew up: release the contract, stop.
func on_ship_destroyed() -> void:
	if trip:
		_release(trip.contract)
		trip = null
	_set_state(State.DESTROYED)


func _trip_target_name() -> String:
	return trip.contract.get_target_name() if trip and trip.contract else "?"


func _set_state(s: State) -> void:
	if state == s:
		return
	state = s
	state_changed.emit(self)
	ship.status_changed.emit(ship)

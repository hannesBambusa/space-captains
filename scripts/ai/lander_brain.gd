class_name LanderBrain
extends CaptainBrain
## A lander's decisions: the miner's trip on planet raid contracts, scored
## by LanderEvaluator. The landing itself (LanderShip) runs in the MINING
## state; it starts once the dropship reaches its entry point (checked in
## 3D, the planet moves on an inclined orbit) and cannot be broken off by
## a threat: down in the atmosphere nothing can reach it before C4.


## [param body] was just claimed: on the way there, turn back home.
func check_claim(body: PlanetBody) -> void:
	if state != State.TRAVELING_TO_JOB or trip == null:
		return
	var rc := trip.contract as PlanetRaidContract
	if rc == null or rc.planet != body:
		return
	var reason := PlanetClaims.claim_reason(body)
	if reason.is_empty():
		return
	last_decision = "Turned back from %s: %s" % [body.def.name, CaptainBrain.lower_first(reason)]
	note(CaptainLog.Kind.CONTRACT, CaptainLog.Outcome.REFUSED, "Turned back from %s: %s" % [body.def.name, CaptainBrain.lower_first(reason)],
			"The planet was claimed while the dropship was on its way", "", "claim_turn")
	_abort_trip()
	_set_state(State.RETURNING)


func update(dt: float) -> void:
	if state == State.TRAVELING_TO_JOB:
		var rc := trip.contract as PlanetRaidContract if trip else null
		if rc and is_instance_valid(rc.planet):
			check_claim(rc.planet)
			if state != State.TRAVELING_TO_JOB:
				return
		_steer_to_job(false)
		if state != State.TRAVELING_TO_JOB or _check_threats(dt):
			return
		var ls := ship as LanderShip
		if ls and trip and ls.near_entry(trip):
			_set_state(State.MINING)
		return
	super.update(dt)


func _check_threats(dt: float = 0.1) -> bool:
	var ls := ship as LanderShip
	if ls and ls.landing_active():
		return false
	return super._check_threats(dt)


func get_status_text() -> String:
	var ls := ship as LanderShip
	var where := _trip_target_name()
	match state:
		State.TRAVELING_TO_JOB:
			return "Flying to %s" % where
		State.MINING:
			match ls.phase_of(trip) if ls else "":
				LanderShip.PHASE_DESCENT:
					return "Descending to %s" % where
				LanderShip.PHASE_SURFACE:
					return "On %s %d%%" % [where, roundi((trip.progress if trip else 0.0) * 100.0)]
				LanderShip.PHASE_CLIMB:
					return "Climbing out of %s" % where
			return "Entering orbit of %s" % where
		State.RETURNING:
			if trip and trip.loaded:
				var rc := trip.contract as PlanetRaidContract
				var units := roundi(float(trip.meta.get("units", 0)) * trip.cargo / maxf(float(trip.meta.get("cargo_full", 1.0)), 0.01))
				return "Returning with %d %s" % [units, Economy.ore_name(rc.loot) if rc else "loot"]
			return "Returning"
	return super.get_status_text()


## "Khepri, 31 silicates a load, 7.2 km, danger 2".
static func raid_line(e: RoleEvaluator.Evaluation) -> String:
	var rc := e.contract as PlanetRaidContract
	return "%s, %d %s a load, %.1f km, danger %d" % [rc.get_target_name(), int(e.terms.get("units", 0)), String(e.terms.get("loot_name", "loot")),
			float(e.terms.get("km", 0.0)), int(e.terms.get("danger_level", 1))]


func note_accept(e: RoleEvaluator.Evaluation, headline: String, kind: CaptainLog.Kind = CaptainLog.Kind.CONTRACT) -> void:
	if e and e.contract is PlanetRaidContract:
		headline = "Planet raid: %s for %d cr" % [raid_line(e), e.contract.reward]
	super.note_accept(e, headline, kind)


func note_idle() -> void:
	note(CaptainLog.Kind.CONTRACT, CaptainLog.Outcome.DID, "Waited: no planet raids posted",
			"Landers only fly to a planet or moon with a planet raid contract on it", "", "idle")

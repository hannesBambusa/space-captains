class_name SalvagerBrain
extends CaptainBrain
## A salvager captain's decisions: the miner's trip (undock, travel, work,
## return, deliver, rest; flee when threatened) on salvage, scored by
## SalvageEvaluator. Salvagers need no contract: every scrap field is free
## salvage paid by their yard (SalvageYard); player contracts add a bonus.
## The status lines and the decision log lines for free salvage differ.


func get_status_text() -> String:
	match state:
		State.MINING:
			return "Salvaging %d%%" % roundi((trip.progress if trip else 0.0) * 100.0)
		State.RETURNING:
			if trip and trip.loaded:
				return "Returning with %d scrap" % roundi(float(trip.meta.get("scrap", 0)) * trip.cargo)
			return "Returning"
	return super.get_status_text()


## "Free salvage: Scrap field (Raider), 140 scrap, 2.1 km, low danger".
static func field_line(e: RoleEvaluator.Evaluation) -> String:
	var sc := e.contract as SalvageContract
	return "%s, %d scrap, %.1f km, %s danger" % [sc.get_target_name(), int(e.terms.get("scrap", 0)), float(e.terms.get("km", 0.0)),
			danger_word(int(e.terms.get("danger_level", 1)))]


static func danger_word(level: int) -> String:
	return "low" if level <= 2 else ("medium" if level == 3 else "high")


func note_accept(e: RoleEvaluator.Evaluation, headline: String, kind: CaptainLog.Kind = CaptainLog.Kind.CONTRACT) -> void:
	var sc := e.contract as SalvageContract if e else null
	if sc and sc.free:
		headline = "Free salvage: %s" % field_line(e)
		last_decision = "Free salvage at %s" % sc.get_target_name()
	elif sc:
		headline = "Salvage contract: %s, +%d cr bonus" % [field_line(e), sc.reward]
	super.note_accept(e, headline, kind)


func note_refusal(e: RoleEvaluator.Evaluation, changed: bool) -> void:
	var sc := e.contract as SalvageContract if e else null
	if captain == null or sc == null or not sc.free:
		super.note_refusal(e, changed)
		return
	var key := DecisionNotes.key_for("no", sc, e.reason)
	if not changed and captain.flight_log.bump(key):
		return
	note(CaptainLog.Kind.CONTRACT, CaptainLog.Outcome.REFUSED, "Passed on free salvage: %s: %s" % [field_line(e), e.reason.to_lower()],
			DecisionNotes.why(self, e), DecisionNotes.detail(self, e), key)


func note_idle() -> void:
	last_decision = "No scrap fields to salvage"
	note(CaptainLog.Kind.CONTRACT, CaptainLog.Outcome.DID, "Waited: no scrap fields to salvage",
			"No wreck with scrap left that a salvager is free to work", "", "idle")

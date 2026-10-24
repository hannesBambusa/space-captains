class_name DecisionNotes
extends RefCounted
## Plain-words text for the decision log (CaptainLog), built from the real
## scoring terms of a [RoleEvaluator.Evaluation]. Only called when an entry
## is written, never per evaluation.

## How many other options the detail lists.
const ALTERNATIVES := 3


## "Cinder Belt mining", "Rustjaw Hideout (Scavengers) bounty".
static func job_name(c: Contract) -> String:
	if c == null:
		return "?"
	var target := c.get_target_name()
	var bc := c as BountyContract
	if bc:
		var f := Factions.of(bc.target)
		if f and not target.contains(f.unit_name):
			target += " (%s)" % f.display_name
	return "%s %s" % [target, c.get_type_name().to_lower()]


## Log key for a contract decision (coalesces repeats).
static func key_for(prefix: String, c: Contract, reason: String = "") -> String:
	return "%s:%d:%s" % [prefix, c.id if c else 0, reason]


## The one-line reason in plain words.
static func why(brain: CaptainBrain, e: RoleEvaluator.Evaluation) -> String:
	var t := e.terms
	var cap := brain.captain
	var prof := brain.profile
	var pname := cap.get_personality_name() if cap else "captain"
	match e.reason:
		RoleEvaluator.CANT_PAY:
			return "The station has %s cr, one payout is %s cr" % [UIUtil.amount(Economy.credits), UIUtil.amount(e.contract.reward)]
		RoleEvaluator.TOO_FAR:
			var km := float(t.get("km", 0.0))
			if RoleEvaluator.too_long(prof, _trip(t)):
				return "%.1f km is %s, past a %s's limit of %d s" % [km, SpaceNav.travel_text(_trip(t)), pname, roundi(prof.max_trip_km * 1000.0 / SpaceNav.REF_SPEED)]
			return "%.1f km (%s) costs %.2f, too much for pay worth %.2f" % [km, SpaceNav.travel_text(_trip(t)), float(t.get("distance", 0.0)), float(t.get("pay", 0.0))]
		RoleEvaluator.TOO_DANGEROUS:
			if _premium_refusal(brain, e):
				var fair := int(t["fair"])
				return "Danger %d: a %s wants %s cr (%.1fx the fair %s), offered %s" % [int(t["danger_level"]), pname,
						UIUtil.amount(ceili(fair * prof.premium_factor)), prof.premium_factor, UIUtil.amount(fair), UIUtil.amount(int(t["reward"]))]
			if t.has("join_chance"):
				return "Danger split %d ways still weighs %.2f against a share worth %.2f" % [int(t.get("heads", 1)), float(t.get("danger", 0.0)), float(t.get("pay", 0.0))]
			return score_line(brain, e)
		RoleEvaluator.BELOW_FAIR:
			return "Pays %s cr, fair is %s cr: Union Rep scores it -%.2f" % [UIUtil.amount(int(t.get("reward", 0))), UIUtil.amount(int(t.get("fair", 0))), MinerEvaluator.UNION_SULK]
		RoleEvaluator.NOT_WORTH_IT:
			return score_line(brain, e)
		MercenaryEvaluator.NEEDS_REPAIRS:
			return "Hull %d%%: repairs first (below %d%%), the wallet can pay" % [roundi(brain.ship.hull_fraction() * 100.0), roundi(MercenaryEvaluator.MIN_HULL * 100.0)]
		MercenaryEvaluator.TOO_STRONG:
			return "Needs %.1f ships like theirs (solo up to %.1f): Teamwork %d too low to call a fleet, daring %.2f too low to go alone" % [
					float(t.get("need", 0.0)), MercFleet.SOLO_NEED, cap.effective_teamwork() if cap else 5, float(t.get("daring", 0.0))]
		MercenaryEvaluator.DECLINED:
			if t.has("join_chance"):
				return "Join chance %d%% (Teamwork %d, %s), share %s cr, %.1f km to the rally point: said no" % [
						roundi(clampf(float(t["join_chance"]), 0.0, 1.0) * 100.0), cap.effective_teamwork() if cap else 5, pname,
						UIUtil.amount(roundi(float(t.get("share", 0.0)))), float(t.get("km", 0.0))]
			return "Already said no to this fleet"
		MercenaryEvaluator.FLEET_FULL:
			return "Every place in that fleet is taken"
		MercenaryEvaluator.NO_MINER:
			return "No miner is out or about to launch on that contract"
	if e.reason.is_empty():
		if t.has("call_fleet"):
			return "Too strong alone (needs %.1f ships), Teamwork %d: calls a fleet of %d, about %s cr each" % [
					float(t.get("need", 0.0)), cap.effective_teamwork() if cap else 5, int(t["call_fleet"]), UIUtil.amount(roundi(float(e.contract.reward) / float(t["call_fleet"])))]
		if t.has("solo_brave"):
			return "Daring %.2f (Nerve %d, Teamwork %d): goes alone against %.1f ships' worth, %d%% chance, keeps all %s cr" % [
					float(t.get("daring", 0.0)), cap.effective_nerve() if cap else 5, cap.effective_teamwork() if cap else 5,
					float(t.get("need", 0.0)), roundi(float(t.get("solo_chance", 0.0)) * 100.0), UIUtil.amount(e.contract.reward)]
		if t.has("join_fleet"):
			if bool(t.get("grudge", false)):
				var gf := Factions.of(e.contract.target) if e.contract else null
				return "Grudge against %s: always joins, share %s cr" % [gf.display_name.to_lower() if gf else "raiders", UIUtil.amount(roundi(float(t.get("share", 0.0))))]
			return "Share %s cr, danger split %d ways, join chance %d%% (Teamwork %d)" % [UIUtil.amount(roundi(float(t.get("share", 0.0)))),
					int(t.get("heads", 1)), roundi(clampf(float(t.get("join_chance", 0.0)), 0.0, 1.0) * 100.0), cap.effective_teamwork() if cap else 5]
		return score_line(brain, e)
	return e.reason


## "Pay 50 cr (fair 50) +1.00, 4.2 km -0.84, danger 3 -1.00 (Cautious x0.87); score 0.42 >= 0.30"
static func score_line(brain: CaptainBrain, e: RoleEvaluator.Evaluation) -> String:
	var t := e.terms
	var cap := brain.captain
	var pay := "Pay %s cr" % UIUtil.amount(int(t.get("reward", e.contract.reward if e.contract else 0)))
	if t.has("fair"):
		pay += " (fair %s)" % UIUtil.amount(int(t["fair"]))
	var dscale := brain.profile.danger_weight * (cap.danger_scale() if cap else 1.0)
	var cmp := ">=" if e.utility >= brain.profile.accept_threshold else "<"
	return "%s %+.2f, %.1f km (%s) -%.2f, danger %d -%.2f (%s x%.2f); score %.2f %s %.2f" % [pay, float(t.get("pay", 0.0)), float(t.get("km", 0.0)),
			SpaceNav.travel_text(_trip(t)), float(t.get("distance", 0.0)), int(t.get("danger_level", 1)), float(t.get("danger", 0.0)),
			cap.get_personality_name() if cap else "captain", dscale, e.utility, cmp, brain.profile.accept_threshold]


## Every term with its source, then the best other options weighed.
static func detail(brain: CaptainBrain, e: RoleEvaluator.Evaluation) -> String:
	var t := e.terms
	var cap := brain.captain
	var prof := brain.profile
	var lines: PackedStringArray = []
	if t.has("pay"):
		var src := "share %s cr" % UIUtil.amount(roundi(float(t["share"]))) if t.has("share") else "%s cr" % UIUtil.amount(int(t.get("reward", 0)))
		lines.append("Pay: %s / %d x weight %.2f x Greed %.2f%s = %+.2f" % [src, roundi(float(t.get("pay_div", 1.0))), prof.pay_weight, cap.pay_scale() if cap else 1.0,
				" (split, or grudge)" if t.has("call_fleet") or bool(t.get("grudge", false)) else "", float(t["pay"])])
		lines.append("Travel: %.1f km = %s, / %d s x weight %.2f = -%.2f" % [float(t.get("km", 0.0)), SpaceNav.travel_text(_trip(t)),
				roundi(float(t.get("time_div", RoleEvaluator.TRAVEL_SCALE_S))), prof.distance_weight, float(t.get("distance", 0.0))])
		var dl := int(t.get("danger_level", 1))
		var parts: PackedStringArray = []
		if int(t.get("base_danger", dl)) != dl:
			parts.append("site %d" % int(t["base_danger"]))
			if bool(t.get("escorted", false)):
				parts.append("escort -%d" % MinerEvaluator.ESCORT_DANGER_RELIEF)
			if int(t.get("gear", 0)) > 0:
				parts.append("gear -%d" % int(t["gear"]))
		lines.append("Danger: level %d%s x weight %.2f x Nerve %.2f = -%.2f" % [dl, " (%s)" % ", ".join(parts) if not parts.is_empty() else "",
				prof.danger_weight, cap.danger_scale() if cap else 1.0, float(t.get("danger", 0.0))])
		if t.has("size"):
			lines.append("Field size: %d scrap %+.2f" % [int(t.get("scrap", 0)), float(t["size"])] if t.has("scrap") else "Field size: %+.2f" % float(t["size"]))
		if float(t.get("crowd", 0.0)) > 0.0:
			lines.append("Crowding: %d salvager%s already on it -%.2f" % [roundi(float(t["crowd"]) / SalvageEvaluator.CROWD_WEIGHT),
					"" if roundi(float(t["crowd"]) / SalvageEvaluator.CROWD_WEIGHT) == 1 else "s", float(t["crowd"])])
		if int(t.get("bonus", 0)) > 0:
			lines.append("Pay is the yard's %d cr plus your %d cr bonus" % [int(t["reward"]) - int(t["bonus"]), int(t["bonus"])])
		lines.append("Loyalty %+.2f, traits %+.2f, luck %+.2f" % [float(t.get("loyal", 0.0)), float(t.get("traits", 0.0)), float(t.get("noise", 0.0))])
		lines.append("Score %.2f, a %s accepts from %.2f" % [e.utility, cap.get_personality_name() if cap else "captain", prof.accept_threshold])
	if t.has("need"):
		lines.append("Strength: target needs %.1f ships like theirs, solo up to %.1f" % [float(t["need"]), MercFleet.SOLO_NEED])
	if t.has("daring"):
		lines.append("Daring %.2f (lone wolf from %.2f), solo chance %d%%" % [float(t["daring"]), MercenaryEvaluator.LONE_WOLF_DARING, roundi(float(t.get("solo_chance", 0.0)) * 100.0)])
	if t.has("join_chance"):
		lines.append("Join chance %d%%: base %d%% + Teamwork, %s %+d%%, share and distance" % [roundi(clampf(float(t["join_chance"]), 0.0, 1.0) * 100.0),
				roundi(MercenaryEvaluator.JOIN_BASE * 100.0), cap.get_personality_name() if cap else "captain",
				roundi(MercenaryEvaluator.JOIN_PERSONALITY[cap.personality] * 100.0) if cap else 0])
	var alt := alternatives(brain, e)
	if not alt.is_empty():
		lines.append("Also weighed: " + alt)
	return "\n".join(lines)


## "Ash Drift mining 0.20 (not worth it), Talon Reach mining -0.46 (too dangerous)"
static func alternatives(brain: CaptainBrain, e: RoleEvaluator.Evaluation) -> String:
	var others: Array[RoleEvaluator.Evaluation] = []
	for o in brain.evaluator.scored:
		if o != e and o.contract != e.contract:
			others.append(o)
	if others.is_empty():
		return ""
	others.sort_custom(func(a: RoleEvaluator.Evaluation, b: RoleEvaluator.Evaluation) -> bool: return a.utility > b.utility)
	var out: PackedStringArray = []
	for i in mini(others.size(), ALTERNATIVES):
		var o := others[i]
		out.append("%s %.2f (%s)" % [job_name(o.contract), o.utility, "would take" if o.accept else o.reason.to_lower()])
	return ", ".join(out)


static func _trip(t: Dictionary) -> Vector2:
	return Vector2(float(t.get("warp_s", 0.0)), float(t.get("flight_s", 0.0)))


static func _premium_refusal(brain: CaptainBrain, e: RoleEvaluator.Evaluation) -> bool:
	var t := e.terms
	var prof := brain.profile
	return t.has("fair") and prof.premium_danger > 0 and int(t.get("danger_level", 1)) >= prof.premium_danger \
			and float(t.get("reward", 0)) < float(t["fair"]) * prof.premium_factor

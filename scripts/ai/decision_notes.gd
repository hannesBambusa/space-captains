class_name DecisionNotes
extends RefCounted
## Plain-words text for the decision log (CaptainLog), built from the real
## scoring terms of a [RoleEvaluator.Evaluation]. Only called when an entry
## is written, never per evaluation.

## How many other options the detail lists.
const ALTERNATIVES := 3


## "Cinder Cluster mining", "Rustjaw Hideout (Scavengers) bounty".
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
	if t.has("claim_why"):
		return String(t["claim_why"])
	if t.has("why"):
		return String(t["why"])
	match e.reason:
		RoleEvaluator.CANT_PAY:
			return "The station has %s cr, one payout is %s cr" % [Fmt.amount(Economy.credits), Fmt.amount(e.contract.reward)]
		RoleEvaluator.NOT_WORTH_TRIP:
			if t.has("jumps"):
				return "%s through the gates and back costs %.2f for a %s, too much for pay worth %.2f: better pay would do it" % [
						_route(t), float(t.get("distance", 0.0)), pname, float(t.get("pay", 0.0))]
			return "%.1f km (%s) costs %.2f for a %s, too much for pay worth %.2f: better pay would do it" % [float(t.get("km", 0.0)),
					SpaceNav.travel_text(_trip(t)), float(t.get("distance", 0.0)), pname, float(t.get("pay", 0.0))]
		RoleEvaluator.TOO_DANGEROUS:
			if _premium_refusal(brain, e):
				var fair := int(t["fair"])
				return "Danger %d: a %s wants %s cr (%.1fx the fair %s), offered %s" % [int(t["danger_level"]), pname,
						Fmt.amount(ceili(fair * prof.premium_factor)), prof.premium_factor, Fmt.amount(fair), Fmt.amount(int(t["reward"]))]
			if t.has("join_chance"):
				return "Danger split %d ways still weighs %.2f against a share worth %.2f" % [int(t.get("heads", 1)), float(t.get("danger", 0.0)), float(t.get("pay", 0.0))]
			return score_line(brain, e)
		RoleEvaluator.BELOW_FAIR:
			return "Pays %s cr, fair is %s cr: Union Rep scores it -%.2f" % [Fmt.amount(int(t.get("reward", 0))), Fmt.amount(int(t.get("fair", 0))), RoleEvaluator.UNION_SULK]
		RoleEvaluator.NOT_WORTH_IT:
			return score_line(brain, e)
		MercenaryEvaluator.NEEDS_REPAIRS:
			return "Hull %d%%: repairs first (below %d%%), the wallet can pay" % [roundi(brain.ship.hull_fraction() * 100.0), roundi(MercenaryEvaluator.MIN_HULL * 100.0)]
		MercenaryEvaluator.TOO_STRONG:
			return "Needs %.1f ships like theirs (solo up to %.1f): Teamwork %d too low to call a fleet, daring %.2f too low to go alone" % [
					float(t.get("need", 0.0)), MercFleet.SOLO_NEED, cap.effective_teamwork() if cap else 5, float(t.get("daring", 0.0))]
		MercenaryEvaluator.FLEET_SHORT, MercenaryEvaluator.FLEET_TOO_WEAK:
			return "%s (target needs %.1f ships like theirs; free mercs' power %.1f of %.1f)" % [String(t.get("fleet_text", e.reason)),
					float(t.get("need", 0.0)), float(t.get("fleet_power", 0.0)), float(t.get("fleet_goal", 0.0))]
		MercenaryEvaluator.DECLINED:
			if t.has("join_chance"):
				return "Join chance %d%% (Teamwork %d, %s), share %s cr, %.1f km to the rally point: said no" % [
						roundi(clampf(float(t["join_chance"]), 0.0, 1.0) * 100.0), cap.effective_teamwork() if cap else 5, pname,
						Fmt.amount(roundi(float(t.get("share", 0.0)))), float(t.get("km", 0.0))]
			return "Already said no to this fleet"
		MercenaryEvaluator.FLEET_FULL:
			return "Every place in that fleet is taken"
		MercenaryEvaluator.NO_MINER:
			return "No miner is out or about to launch on that contract"
	if e.reason.is_empty():
		if t.has("call_fleet"):
			return "Too strong alone (needs %.1f ships), Teamwork %d: calls a fleet of %d, about %s cr each" % [
					float(t.get("need", 0.0)), cap.effective_teamwork() if cap else 5, int(t["call_fleet"]), Fmt.amount(roundi(float(e.contract.reward) / float(t["call_fleet"])))]
		if t.has("solo_brave"):
			return "Daring %.2f (Nerve %d, Teamwork %d): goes alone against %.1f ships' worth, %d%% chance, keeps all %s cr" % [
					float(t.get("daring", 0.0)), cap.effective_nerve() if cap else 5, cap.effective_teamwork() if cap else 5,
					float(t.get("need", 0.0)), roundi(float(t.get("solo_chance", 0.0)) * 100.0), Fmt.amount(e.contract.reward)]
		if t.has("join_fleet"):
			if bool(t.get("grudge", false)):
				var gf := Factions.of(e.contract.target) if e.contract else null
				return "Grudge against %s: always joins, share %s cr" % [gf.display_name.to_lower() if gf else "raiders", Fmt.amount(roundi(float(t.get("share", 0.0))))]
			return "Share %s cr, danger split %d ways, join chance %d%% (Teamwork %d)" % [Fmt.amount(roundi(float(t.get("share", 0.0)))),
					int(t.get("heads", 1)), roundi(clampf(float(t.get("join_chance", 0.0)), 0.0, 1.0) * 100.0), cap.effective_teamwork() if cap else 5]
		return score_line(brain, e)
	return e.reason


## One log line for a mercenary refusing a bounty or escort, or a fleet
## invite: what, the reason and the numbers behind it.
## "Refused bounty on Rustjaw Hideout (800 cr): needs about 4 mercs, 2 free"
static func merc_refusal_line(brain: CaptainBrain, e: RoleEvaluator.Evaluation) -> String:
	var c := e.contract
	var t := e.terms
	var head := ""
	if t.has("join_fleet"):
		head = "Declined to join %s's fleet on %s (%s cr share)" % [String(t.get("leader", "a")), c.get_target_name(), Fmt.amount(roundi(float(t.get("share", 0.0))))]
	else:
		head = "Refused %s on %s (%s cr)" % [c.get_type_name().to_lower(), c.get_target_name(), Fmt.amount(c.reward)]
	return "%s: %s" % [head, merc_refusal_reason(brain, e)]


## The reason part of [method merc_refusal_line] (also the target panel's
## line per merc).
static func merc_refusal_reason(brain: CaptainBrain, e: RoleEvaluator.Evaluation) -> String:
	var t := e.terms
	var cap := brain.captain
	var pname := cap.get_personality_name() if cap else "captain"
	var join := t.has("join_fleet")
	var offered := roundi(float(t.get("share", 0.0))) if join else int(t.get("reward", e.contract.reward))
	var wants := "%s %s vs wants ~%s" % ["share" if join else "pay", Fmt.amount(offered), Fmt.amount(roundi(float(t.get("wants", 0.0)) / 5.0) * 5)]
	if t.has("fleet_size") and not join:
		wants = "pay %s split %d ways vs wants ~%s" % [Fmt.amount(offered), int(t["fleet_size"]), Fmt.amount(roundi(float(t.get("wants", 0.0)) / 5.0) * 5)]
	var danger := int(t.get("danger_level", 1))
	match e.reason:
		MercenaryEvaluator.NEEDS_REPAIRS:
			return "hull %d%%, needs %d%% before a job" % [roundi(brain.ship.hull_fraction() * 100.0), roundi(MercenaryEvaluator.MIN_HULL * 100.0)]
		MercenaryEvaluator.TOO_STRONG:
			return "too strong alone, needs about %.1f mercs like this one; teamwork %d (a fleet call needs %d), daring %.2f (solo from %.2f)" % [
					float(t.get("need", 0.0)), cap.effective_teamwork() if cap else 5, MercenaryEvaluator.CALL_TEAMWORK,
					float(t.get("daring", 0.0)), MercenaryEvaluator.LONE_WOLF_DARING]
		MercenaryEvaluator.FLEET_SHORT:
			var ships := maxi(int(t.get("fleet_estimate", 0)), int(t.get("fleet_size", 0)))
			var free := int(t.get("fleet_available", 0))
			if ships > free:
				return "needs about %d mercs, %d free" % [ships, free]
			return "needs about %d mercs, %d free, but their combined power %.1f falls short of the %.1f needed" % [ships, free,
					float(t.get("fleet_power", 0.0)), float(t.get("fleet_goal", 0.0))]
		MercenaryEvaluator.FLEET_TOO_WEAK:
			return "too strong for any fleet, needs about %d mercs like ours, at most %d fly together" % [int(t.get("fleet_estimate", 0)), int(t.get("fleet_cap", MercFleet.MAX_SIZE))]
		RoleEvaluator.CANT_PAY:
			return "the station can't pay (%s cr on hand)" % Fmt.amount(Economy.credits)
		RoleEvaluator.NOT_WORTH_TRIP:
			return "not worth the trip, %s (%.1f km, danger %d, %s)" % [wants, float(t.get("km", 0.0)), danger, pname]
		RoleEvaluator.NOT_WORTH_IT:
			if join:
				return "not worth it, %s (fleet covers %d%% of the need, %s)" % [wants, roundi(float(t.get("covers", 0.0)) * 100.0), pname]
			return "not worth it, %s (%.1f km, danger %d, %s)" % [wants, float(t.get("km", 0.0)), danger, pname]
		RoleEvaluator.TOO_DANGEROUS:
			if join:
				return "too dangerous, %s (danger %d split %d ways, fleet covers %d%% of the need, %s, nerve %d)" % [wants, danger, int(t.get("heads", 1)),
						roundi(float(t.get("covers", 0.0)) * 100.0), pname, cap.effective_nerve() if cap else 5]
			return "too dangerous, %s (danger %d, %.1f km, %s, nerve %d)" % [wants, danger, float(t.get("km", 0.0)), pname, cap.effective_nerve() if cap else 5]
		MercenaryEvaluator.DECLINED:
			if t.has("join_chance"):
				return "teamwork %d, join chance %d%%, said no (fleet covers %d%% of the need)" % [cap.effective_teamwork() if cap else 5,
						roundi(clampf(float(t["join_chance"]), 0.0, 1.0) * 100.0), roundi(float(t.get("covers", 0.0)) * 100.0)]
			return "already said no to this fleet, asked again after %d s" % roundi(MercFleet.DECLINE_MEMORY)
		MercenaryEvaluator.FLEET_FULL:
			return "every place in that fleet is taken"
		MercenaryEvaluator.NO_MINER:
			return "no miner is out or about to launch on that contract"
	return lower_reason(e.reason)


## Key part for [method merc_refusal_line]: a new log line when the numbers
## move noticeably (wanted pay by 50 cr, free mercs, hull by 10%).
static func merc_refusal_tag(brain: CaptainBrain, e: RoleEvaluator.Evaluation) -> String:
	var t := e.terms
	match e.reason:
		MercenaryEvaluator.NEEDS_REPAIRS:
			return str(floori(brain.ship.hull_fraction() * 10.0))
		MercenaryEvaluator.FLEET_SHORT, MercenaryEvaluator.FLEET_TOO_WEAK:
			return "%d/%d" % [maxi(int(t.get("fleet_estimate", 0)), int(t.get("fleet_size", 0))), int(t.get("fleet_available", 0))]
		RoleEvaluator.NOT_WORTH_TRIP, RoleEvaluator.NOT_WORTH_IT, RoleEvaluator.TOO_DANGEROUS:
			return str(roundi(float(t.get("wants", 0.0)) / 50.0))
	return ""


static func lower_reason(text: String) -> String:
	return text.left(1).to_lower() + text.substr(1) if not text.is_empty() else text


## "Pay 50 cr (fair 50) +1.00, 4.2 km -0.84, danger 3 -1.00 (Cautious x0.87); score 0.42 >= 0.30"
static func score_line(brain: CaptainBrain, e: RoleEvaluator.Evaluation) -> String:
	var t := e.terms
	var cap := brain.captain
	var pay := "Pay %s cr" % Fmt.amount(int(t.get("reward", e.contract.reward if e.contract else 0)))
	if t.has("fair"):
		pay += " (fair %s)" % Fmt.amount(int(t["fair"]))
	var dscale := brain.profile.danger_weight * (cap.danger_scale() if cap else 1.0)
	var cmp := ">=" if e.utility >= brain.profile.accept_threshold else "<"
	var rich := ", rich world %+.2f" % float(t["rich"]) if t.has("rich") else ""
	if t.has("jumps"):
		var bold := ", uncharted %+.2f" % float(t["unknown"]) if float(t.get("unknown", 0.0)) > 0.0 else ""
		return "%s %+.2f, %s -%.2f, danger %s -%.2f (%s x%.2f)%s; score %.2f %s %.2f" % [pay, float(t.get("pay", 0.0)), _route(t),
				float(t.get("distance", 0.0)), str(int(t.get("danger_level", 1))) if bool(t.get("known", false)) else "%d (a guess)" % int(t.get("danger_level", 1)),
				float(t.get("danger", 0.0)), cap.get_personality_name() if cap else "captain", dscale, bold, e.utility, cmp, brain.profile.accept_threshold]
	return "%s %+.2f, %.1f km (%s) -%.2f, danger %d -%.2f (%s x%.2f)%s; score %.2f %s %.2f" % [pay, float(t.get("pay", 0.0)), float(t.get("km", 0.0)),
			SpaceNav.travel_text(_trip(t)), float(t.get("distance", 0.0)), int(t.get("danger_level", 1)), float(t.get("danger", 0.0)),
			cap.get_personality_name() if cap else "captain", dscale, rich, e.utility, cmp, brain.profile.accept_threshold]


## Every term with its source, then the best other options weighed.
static func detail(brain: CaptainBrain, e: RoleEvaluator.Evaluation) -> String:
	var t := e.terms
	var cap := brain.captain
	var prof := brain.profile
	var lines: PackedStringArray = []
	if t.has("pay"):
		var src := "share %s cr" % Fmt.amount(roundi(float(t["share"]))) if t.has("share") else "%s cr" % Fmt.amount(int(t.get("reward", 0)))
		lines.append("Pay: %s / %d x weight %.2f x Greed %.2f%s = %+.2f" % [src, roundi(float(t.get("pay_div", 1.0))), prof.pay_weight, cap.pay_scale() if cap else 1.0,
				" (split, or grudge)" if t.has("call_fleet") or bool(t.get("grudge", false)) else "", float(t["pay"])])
		if t.has("jumps"):
			lines.append("Trip: %s = %s, / %d s x weight %.2f%s = -%.2f" % [_route(t), Fmt.clock(float(t.get("trip_s", 0.0))),
					roundi(float(t.get("time_div", 1.0))), prof.distance_weight, ", Lazy %.2f a jump past the first" % ExplorerEvaluator.LAZY_JUMP if float(t.get("lazy", 0.0)) > 0.0 else "",
					float(t.get("distance", 0.0))])
		else:
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
		if float(t.get("crowd", 0.0)) > 0.0 and not t.has("rich"):
			lines.append("Crowding: %d salvager%s already on it -%.2f" % [roundi(float(t["crowd"]) / SalvageEvaluator.CROWD_WEIGHT),
					"" if roundi(float(t["crowd"]) / SalvageEvaluator.CROWD_WEIGHT) == 1 else "s", float(t["crowd"])])
		if t.has("rich"):
			lines.append("Rich world: one load is %d %s, about %s cr at the Factory, %+.2f (%s taste x%.2f with Greed)" % [int(t.get("units", 0)), String(t.get("loot_name", "loot")),
					Fmt.amount(roundi(float(t.get("loot_value", 0.0)))), float(t["rich"]), cap.get_personality_name() if cap else "captain", float(t.get("taste", 1.0))])
			if int(t.get("landers", 0)) > 0:
				lines.append("Crowding: %d lander%s already on it -%.2f" % [int(t["landers"]), "" if int(t["landers"]) == 1 else "s", float(t.get("crowd", 0.0))])
		if int(t.get("bonus", 0)) > 0:
			lines.append("Pay is the yard's %d cr plus your %d cr bonus" % [int(t["reward"]) - int(t["bonus"]), int(t["bonus"])])
		lines.append("Loyalty %+.2f, traits %+.2f, luck %+.2f" % [float(t.get("loyal", 0.0)), float(t.get("traits", 0.0)), float(t.get("noise", 0.0))])
		lines.append("Score %.2f, a %s accepts from %.2f" % [e.utility, cap.get_personality_name() if cap else "captain", prof.accept_threshold])
	if t.has("need"):
		lines.append("Strength: target needs %.1f ships like theirs, solo up to %.1f" % [float(t["need"]), MercFleet.SOLO_NEED])
	if t.has("fleet_text"):
		lines.append("Fleet: %s; %d free, their combined power must cover %d%% of the need" % [String(t["fleet_text"]), int(t.get("fleet_available", 0)),
				roundi(float(t.get("fleet_share", MercFleet.FLEET_POWER_SHARE)) * 100.0)])
	if t.has("cover"):
		lines.append("Fleet cover: danger x%.2f (need against the fleet's power with this ship)" % float(t["cover"]))
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
		out.append("%s %.2f (%s)" % [job_name(o.contract), o.utility, "would take" if o.accept else CaptainBrain.lower_first(o.reason)])
	return ", ".join(out)


## "2 jumps out, survey" for explore trips.
static func _route(t: Dictionary) -> String:
	var j := int(t.get("jumps", 1))
	return "%d jump%s out, survey" % [j, "" if j == 1 else "s"]


static func _trip(t: Dictionary) -> Vector2:
	return Vector2(float(t.get("warp_s", 0.0)), float(t.get("flight_s", 0.0)))


static func _premium_refusal(brain: CaptainBrain, e: RoleEvaluator.Evaluation) -> bool:
	var t := e.terms
	var prof := brain.profile
	return t.has("fair") and prof.premium_danger > 0 and int(t.get("danger_level", 1)) >= prof.premium_danger \
			and float(t.get("reward", 0)) < float(t["fair"]) * prof.premium_factor

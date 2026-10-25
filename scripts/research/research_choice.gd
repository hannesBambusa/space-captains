class_name ResearchChoice
extends RefCounted
## How a researcher picks a project among the funded ones nobody works on
## (indirect control: you fund, they choose). Score = field factor x
## personality factor x resume factor:
##   field       1.0 in their field, 0.55 outside it
##   Ambitious   x(1 + 0.5 per tier above I) x(1 + credits / 1500)
##   Cautious    x1.8 defensive work, x0.6 weapons
##   Curious     x2.2 Planetary, x1.4 unlocks a building
##   Methodical  x1.5 tier I, x1.0 tier II, x0.7 tier III, x1.4 on cheap ones (under 600 cr)
##   resume      x1.3 when the project already has progress (x1.6 Methodical)
## The best score wins; [method pick] returns it with a reason line that
## names the factors and the runner-up.

const OFF_FIELD := 0.55


## {tech: TechDef or null, score: float, reason: String}.
static func pick(r: Researcher, candidates: Array[TechDef], progress: Dictionary) -> Dictionary:
	var scored: Array[Dictionary] = []
	for t in candidates:
		var s := score(r, t, float(progress.get(t.id, 0.0)) > 0.0)
		scored.append({"tech": t, "score": s["score"], "why": s["why"]})
	if scored.is_empty():
		return {"tech": null, "score": 0.0, "reason": "No funded project free"}
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	var best := scored[0]
	var t := best["tech"] as TechDef
	var reason := "Picked %s: %s, score %.2f" % [t.display_name, best["why"], float(best["score"])]
	if scored.size() > 1:
		reason += " over %s %.2f" % [(scored[1]["tech"] as TechDef).display_name, float(scored[1]["score"])]
	return {"tech": t, "score": best["score"], "reason": reason}


## {score: float, why: String} for [param r] on [param t].
static func score(r: Researcher, t: TechDef, started: bool) -> Dictionary:
	var parts: PackedStringArray = []
	var s := 1.0
	if t.field == r.field:
		parts.append("%s is their field" % t.field_name())
	else:
		s *= OFF_FIELD
		parts.append("outside their field x%.2f" % OFF_FIELD)
	var p := personality_factor(r, t)
	s *= float(p["factor"])
	if not String(p["why"]).is_empty():
		parts.append(String(p["why"]))
	if started:
		var resume := 1.6 if r.personality == Researcher.Personality.METHODICAL else 1.3
		s *= resume
		parts.append("already started x%.1f" % resume)
	return {"score": s, "why": ", ".join(parts)}


## {factor: float, why: String}.
static func personality_factor(r: Researcher, t: TechDef) -> Dictionary:
	var name := r.personality_name()
	match r.personality:
		Researcher.Personality.AMBITIOUS:
			var f := (1.0 + 0.5 * float(t.tier - 1)) * (1.0 + float(t.cost_credits) / 1500.0)
			return {"factor": f, "why": "%s likes big projects (%s, %s cr) x%.2f" % [name, TechDef.TIER_NAMES[t.tier], Fmt.amount(t.cost_credits), f]}
		Researcher.Personality.CAUTIOUS:
			if t.has_tag("defence"):
				return {"factor": 1.8, "why": "%s likes defensive work x1.8" % name}
			if t.has_tag("weapons"):
				return {"factor": 0.6, "why": "%s dislikes weapons work x0.6" % name}
		Researcher.Personality.CURIOUS:
			var f := 1.0
			var why: PackedStringArray = []
			if t.field == TechDef.Field.PLANETARY:
				f *= 2.2
				why.append("Planetary work x2.2")
			if not t.unlock_buildings.is_empty():
				f *= 1.4
				why.append("a new building x1.4")
			if f != 1.0:
				return {"factor": f, "why": "%s likes %s" % [name, " and ".join(why)]}
		Researcher.Personality.METHODICAL:
			var f: float = [1.0, 1.5, 1.0, 0.7][clampi(t.tier, 0, 3)]
			if t.cost_credits < 600:
				f *= 1.4
			return {"factor": f, "why": "%s likes small steps (%s%s) x%.2f" % [name, TechDef.TIER_NAMES[t.tier], ", cheap" if t.cost_credits < 600 else "", f]}
	return {"factor": 1.0, "why": ""}

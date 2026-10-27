class_name ResearchTip
extends RefCounted
## Research tooltips ([RichTooltip]) for the HUD research list, the Science
## Lab's project rows and the top bar research box. One project: title,
## field, tier and state chips, the tech's [member TechDef.benefit] line, the
## benefits made from its data (modules the Factory can make with their
## numbers, buildings, crew-wide bonuses, what it leads to), then cost, time,
## the researcher, progress and time left, why it is paused, or what it needs
## first. The content is rebuilt live while the tooltip is open.

const H := preload("res://scripts/ui/theme/hud_style.gd")
const STATE_CHIPS := {
	"done": "Researched", "in_progress": "In progress", "funded": "Paused", "available": "Available", "locked": "Locked",
}


## The tooltip for [param t]; [param click] is the footer hint ("" = none).
static func make(t: TechDef, click: String = "") -> RichTooltip:
	return RichTooltip.make(fill.bind(t, click), ScienceLabPanel.FIELD_COLORS[t.field])


## The top bar's tooltip: every funded project, compact.
static func make_summary() -> RichTooltip:
	return RichTooltip.make(fill_summary, H.HOLO)


## Plain-language list of what [param t] gives, from its data.
static func benefits(t: TechDef) -> PackedStringArray:
	var out: PackedStringArray = []
	for id in t.unlock_modules:
		var m := ModuleCatalog.shared().find(id)
		if m == null:
			continue
		var who := "any ship" if m.roles.is_empty() else _join(ModuleTips._plural_roles(m.roles))
		var fx := m.effect_text()
		out.append("Factory can make %s for %s%s" % [m.display_name, who, " (%s)" % fx if not fx.is_empty() else ""])
	var tree := Engine.get_main_loop() as SceneTree
	var home := SystemWorld.home(tree) if tree else null
	var mgr := BuildingManager.of(home) if home else null
	for id in t.unlock_buildings:
		var def := mgr.def_by_id(id) if mgr else null
		var bname := def.display_name if def else String(id).capitalize()
		out.append("Unlocks the %s on the build bar%s" % [bname, " (in service in a later update)" if def and not def.in_service else ""])
	if t.merc_accuracy != 0.0:
		out.append("Every mercenary: %+d accuracy points, no refit needed" % roundi(t.merc_accuracy * 100.0))
	if t.miner_hold != 0.0:
		out.append("Every miner: %+d%% load per trip, no refit needed" % roundi(t.miner_hold * 100.0))
	if t.id == ShipLoadout.HEAVY_DROPSHIPS:
		out.append("Every lander: %+d%% loot per planet raid" % roundi(ShipLoadout.HEAVY_CARGO_BONUS * 100.0))
	if t.id == ShipLoadout.ARMOURED_DROPSHIPS:
		out.append("Every lander: %+d%% hull and %+d shields" % [roundi((ShipLoadout.ARMOURED_HULL_MULT - 1.0) * 100.0), roundi(ShipLoadout.ARMOURED_SHIELD_BONUS)])
	var next: PackedStringArray = []
	for o in Research.catalog().techs:
		if o and not o.hidden and o.prerequisites.has(t.id):
			next.append(o.display_name)
	if not next.is_empty():
		out.append("Opens research: %s" % _join(next))
	return out


## Builds [param tip] for [param t] (RichTooltip builder).
static func fill(tip: RichTooltip, t: TechDef, click: String) -> void:
	var field_col: Color = ScienceLabPanel.FIELD_COLORS[t.field]
	var state := Research.state_of(t)
	var why := ResearchList.pause_reason(t) if state == "funded" or state == "in_progress" else ""
	var chip_state := "Paused" if not why.is_empty() else String(STATE_CHIPS[state])
	var state_col: Color = H.WARN if not why.is_empty() else (H.TEXT_DIM if state == "locked" else ScienceLabPanel.STATE_COLORS[state])
	tip.title(t.display_name)
	tip.chips([{"text": t.field_name(), "color": field_col}, {"text": TechDef.TIER_NAMES[t.tier], "color": CaptainPanel.TIER_COLORS[t.tier]},
			{"text": chip_state, "color": state_col}] as Array[Dictionary])
	var lead := t.benefit if not t.benefit.is_empty() else t.description
	if not lead.is_empty():
		tip.text(lead, H.TEXT_BRIGHT, 14)
	var list := benefits(t)
	if not list.is_empty():
		tip.section("Benefits")
		for b in list:
			tip.bullet(b, field_col)
	tip.section("Project")
	if state != "done":
		tip.stat("Cost", t.cost_text(), H.CREDITS)
		tip.stat("Research time", "%s in the field, %s outside" % [UIUtil.clock(t.research_time), UIUtil.clock(t.research_time / Researcher.OFF_FIELD_SPEED)])
	match state:
		"done":
			tip.text("Researched. Everything above is yours.", H.GOOD)
		"in_progress", "funded":
			var r := Research.researcher_on(t.id)
			if r:
				tip.stat("Researcher", "%s, skill %d, %d%%%s" % [r.researcher_name, r.skill, roundi(r.speed_on(t) * 100.0),
						"" if r.field == t.field else " (off field)"], H.TEXT_BRIGHT, false)
			else:
				tip.stat("Researchers", "1 needed, none on it", H.WARN, false)
			var p := Research.progress_of(t)
			var eta := Research.eta_of(t)
			var left := "%s left" % UIUtil.clock(eta) if r and not r.unpaid and eta < INF else "stalled"
			tip.stat("Progress", "%d%%   %s" % [floori(p * 100.0), left], H.TEXT_BRIGHT if why.is_empty() else H.WARN)
			tip.bar(p, field_col if why.is_empty() else H.WARN)
			tip.stat("Reserved", "%s cr" % UIUtil.amount(int(Research.projects[t.id].get("credits", 0))), H.CREDITS)
			if not why.is_empty():
				tip.text("Paused: %s." % _paused_text(why), H.WARN)
		"locked":
			if t.hidden:
				tip.text("Not available yet: comes in a later update.", H.TEXT_DIM)
			else:
				tip.section("Requires", H.WARN)
				for p in t.prerequisites:
					var pt := Research.catalog().find(p)
					if pt:
						var ok := Research.is_done(p)
						tip.bullet("%s%s" % [pt.display_name, " (done)" if ok else ""], H.GOOD if ok else H.WARN, H.TEXT if ok else H.TEXT_BRIGHT)
		_:
			tip.stat("Researchers", "1 needed", H.TEXT_BRIGHT, false)
			var problem := Research.fund_problem(t)
			if not problem.is_empty():
				tip.text(problem + ".", H.WARN)
			else:
				tip.text("Fund it at the Science Lab: the cost is reserved now, a researcher picks it up when free.", H.TEXT_DIM)
	if not click.is_empty():
		tip.hint(click)


## Top bar: staff and wages, then every funded project with its progress.
static func fill_summary(tip: RichTooltip) -> void:
	var active := Research.active_projects()
	var working := 0
	for a in active:
		if a["researcher"] != null:
			working += 1
	tip.title("Research")
	tip.chips([{"text": "%d funded" % active.size(), "color": H.HOLO}, {"text": "%d at work" % working, "color": H.GOOD if working > 0 else H.WARN},
			{"text": "%d of %d researchers" % [Research.researchers.size(), Research.MAX_RESEARCHERS], "color": H.TEXT_DIM}] as Array[Dictionary])
	if not Research.researchers.is_empty():
		tip.stat("Wages", "%s cr/min" % String.num(Research.wages_per_min(), 1).trim_suffix(".0"), H.CREDITS)
	var tree := Engine.get_main_loop() as SceneTree
	var home := SystemWorld.home(tree) if tree else null
	if home == null or ScienceLab.find(home) == null:
		tip.text("No Science Lab: the work is on hold.", H.WARN)
	if active.is_empty():
		tip.text("Nothing funded. Fund projects at the Science Lab.", H.TEXT_DIM)
	for a in active:
		var t := a["tech"] as TechDef
		var r := a["researcher"] as Researcher
		var why := ResearchList.pause_reason(t)
		tip.section(t.display_name, ScienceLabPanel.FIELD_COLORS[t.field])
		var eta := Research.eta_of(t)
		tip.stat(r.researcher_name if r else "Nobody on it", "%d%%   %s" % [floori(float(a["progress"]) * 100.0),
				"%s left" % UIUtil.clock(eta) if why.is_empty() and eta < INF else "paused"], H.TEXT_BRIGHT if why.is_empty() else H.WARN)
		tip.bar(float(a["progress"]), ScienceLabPanel.FIELD_COLORS[t.field] if why.is_empty() else H.WARN)
		if not why.is_empty():
			tip.text("Paused: %s." % _paused_text(why), H.WARN, 12)
	tip.hint("Click: open the Science Lab")


## "Waiting for a researcher" -> a hint at what to do.
static func _paused_text(why: String) -> String:
	match why:
		"No researchers":
			return "no researchers hired. Hire one in the Science Lab's Staff tab"
		"Waiting for a researcher":
			return "every researcher is busy. It starts when one is free, or hire another"
		"Out of credits for wages":
			return "the station cannot pay the researcher's wage. Work goes on when credits come in"
	return why.to_lower()


## "a", "a and b", "a, b and c".
static func _join(parts: PackedStringArray) -> String:
	if parts.size() <= 2:
		return " and ".join(parts)
	return "%s and %s" % [", ".join(parts.slice(0, parts.size() - 1)), parts[parts.size() - 1]]

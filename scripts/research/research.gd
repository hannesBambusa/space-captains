extends Node
## Autoload "Research". What the colony has researched, the funded projects
## and the researchers hired at the Science Lab (ScienceLab, a station addon).
##
## Unlocks: a module is offered by the Factory and the Outfitter when it is in
## [constant START_MODULES] (one Mk I per slot for each role), or no tech
## unlocks it, or its tech ([TechCatalog.for_module]) is done. Buildings the
## same way ([method building_lock_reason]).
##
## Funding (the bounty escrow idea): funding a project reserves its credits
## (and spends its ore) at once; you cannot fund past your credits. The
## reserve is used up when the project is done. Cancel: everything back while
## nobody has worked on it, half the credits and half the ore once started.
##
## Researchers (1 to [constant MAX_RESEARCHERS]) are hired from a pool of
## [constant APPLICANTS] applicants that changes every [constant
## APPLICANT_REFRESH] sim seconds. An idle researcher picks among the funded
## projects nobody works on by field and personality ([ResearchChoice]) and
## keeps it until done. Speed: [method Researcher.speed_on]. Every second
## completed project raises their skill by 1. Work only runs while a Science
## Lab is built ([method sim_step] is driven by the lab).
## Wages: every hired researcher draws [method Researcher.wage_per_min]
## credits per minute from the player's credits. One who cannot be paid is
## "Unpaid" and does not work until the credits are there again.

signal changed
signal tech_completed(tech: TechDef)

const MAX_RESEARCHERS := 3
const APPLICANTS := 3
const APPLICANT_REFRESH := 240.0
## Share of the credits and ore given back when a started project is cancelled.
const STARTED_REFUND := 0.5
const MAX_LOG := 16
## Offered from the start: one Mk I module per slot for each role.
const START_MODULES: Array[StringName] = [
	&"mining_laser_1", &"ore_hold_1", &"reinforced_plating_1", &"ion_drive_1", &"prospector_array_1",
	&"autocannon_1", &"ammo_rack_1", &"armor_plating_1", &"combat_thrusters_1", &"targeting_array_1",
	&"salvage_claw_1", &"salvage_hold_1", &"wreck_scanner_1",
]

## Tech id -> sim time it was done.
var done: Dictionary = {}
## Tech id -> {credits: int (reserved), ore: PackedInt32Array (spent),
## progress: float (sim seconds of work at speed 1), funded_at: float}.
var projects: Dictionary = {}
var researchers: Array[Researcher] = []
var applicants: Array[Researcher] = []
## Sim time the applicant pool changes next.
var applicants_at: float = 0.0
## Newest last: {time, text}.
var log_lines: Array[Dictionary] = []
var next_id: int = 1
var rng := RandomNumberGenerator.new()
## The last load had no research data (an older save): [method grant_legacy]
## runs once the scene is loaded.
var legacy_pending: bool = false


func _ready() -> void:
	reset()


func catalog() -> TechCatalog:
	return TechCatalog.shared()


# --- Unlocks ----------------------------------------------------------------------

func is_done(tech_id: StringName) -> bool:
	return done.has(tech_id)


func is_module_unlocked(module_id: StringName) -> bool:
	if START_MODULES.has(module_id):
		return true
	var t := catalog().for_module(module_id)
	return t == null or is_done(t.id)


## "Needs research: Shield lattice" or "".
func module_lock_reason(module_id: StringName) -> String:
	if is_module_unlocked(module_id):
		return ""
	return "Needs research: %s" % catalog().for_module(module_id).display_name


func is_building_unlocked(building_id: StringName) -> bool:
	var t := catalog().for_building(building_id)
	return t == null or is_done(t.id)


func building_lock_reason(building_id: StringName) -> String:
	if is_building_unlocked(building_id):
		return ""
	return "Needs research: %s" % catalog().for_building(building_id).display_name


## Prerequisites of [param t] not done yet.
func missing_prereqs(t: TechDef) -> Array[TechDef]:
	var out: Array[TechDef] = []
	for p in t.prerequisites:
		if not is_done(p):
			var pt := catalog().find(p)
			if pt:
				out.append(pt)
	return out


## "done", "in_progress", "funded", "available" or "locked".
func state_of(t: TechDef) -> String:
	if is_done(t.id):
		return "done"
	if projects.has(t.id):
		return "in_progress" if researcher_on(t.id) != null else "funded"
	return "locked" if not missing_prereqs(t).is_empty() or t.hidden else "available"


func researcher_on(tech_id: StringName) -> Researcher:
	for r in researchers:
		if r.project == tech_id:
			return r
	return null


## 0..1 progress of a funded project.
func progress_of(t: TechDef) -> float:
	var p: Dictionary = projects.get(t.id, {})
	return clampf(float(p.get("progress", 0.0)) / maxf(t.research_time, 0.01), 0.0, 1.0)


## Sim seconds left at the current researcher's speed (INF while nobody works on it).
func eta_of(t: TechDef) -> float:
	var r := researcher_on(t.id)
	if r == null or not projects.has(t.id):
		return INF
	return maxf(t.research_time - float(projects[t.id]["progress"]), 0.0) / maxf(r.speed_on(t), 0.01)


## Hit chance every mercenary gets from finished techs (TechDef.merc_accuracy).
func merc_accuracy() -> float:
	return _done_sum(&"merc_accuracy")


## Hold every miner gets from finished techs (TechDef.miner_hold).
func miner_hold() -> float:
	return _done_sum(&"miner_hold")


func _done_sum(prop: StringName) -> float:
	var n := 0.0
	for id: StringName in done:
		var t := catalog().find(id)
		if t:
			n += float(t.get(prop))
	return n


## "The Factory can make Shield Projector Mk I and Deflector Mk I." style.
func unlock_text(t: TechDef) -> String:
	var parts: PackedStringArray = []
	var mods: PackedStringArray = []
	for id in t.unlock_modules:
		var m := ModuleCatalog.shared().find(id)
		if m:
			mods.append(m.display_name)
	if not mods.is_empty():
		parts.append("The Factory can make %s." % " and ".join(mods) if mods.size() <= 2 else "The Factory can make %s and %s." % [", ".join(mods.slice(0, mods.size() - 1)), mods[mods.size() - 1]])
	var mgr := BuildingManager.of(get_tree()) if is_inside_tree() else null
	for id in t.unlock_buildings:
		var def := mgr.def_by_id(id) if mgr else null
		parts.append("Unlocks the %s." % (def.display_name if def else String(id).capitalize()))
	if parts.is_empty():
		# Upgrades with no module or building (dropship research).
		return t.description
	return " ".join(parts)


# --- Funding -----------------------------------------------------------------------

func lab() -> ScienceLab:
	return ScienceLab.find(get_tree()) if is_inside_tree() else null


## Why [param t] cannot be funded now, or "".
func fund_problem(t: TechDef) -> String:
	if t == null or t.hidden:
		return "Not available yet"
	if is_done(t.id):
		return "Already researched"
	if projects.has(t.id):
		return "Already funded"
	var miss := missing_prereqs(t)
	if not miss.is_empty():
		var names: PackedStringArray = []
		for m in miss:
			names.append(m.display_name)
		return "Needs research: %s first" % " and ".join(names)
	if lab() == null:
		return "Build a Science Lab first"
	var short := Economy.shortfall_text(t.cost_credits, t.cost_ore())
	if not short.is_empty():
		return short + ": funding reserves the credits now"
	return ""


## Reserves the credits and spends the ore. False when it cannot be funded.
func fund(t: TechDef) -> bool:
	if not fund_problem(t).is_empty():
		return false
	if not Economy.spend(t.cost_credits, t.cost_ore()):
		return false
	projects[t.id] = {"credits": t.cost_credits, "ore": t.cost_ore(), "progress": 0.0, "funded_at": SimClock.time}
	_log("Funded %s: %s reserved" % [t.display_name, t.cost_text()])
	_assign_idle()
	changed.emit()
	return true


## What cancelling gives back now: {credits, ore: PackedInt32Array, started: bool}.
func cancel_terms(t: TechDef) -> Dictionary:
	var p: Dictionary = projects.get(t.id, {})
	if p.is_empty():
		return {"credits": 0, "ore": PackedInt32Array([0, 0, 0]), "started": false}
	var started := float(p.get("progress", 0.0)) > 0.0
	var share := STARTED_REFUND if started else 1.0
	var ore := PackedInt32Array(p.get("ore", PackedInt32Array([0, 0, 0])))
	var back := PackedInt32Array()
	for v in ore:
		back.append(floori(float(v) * share))
	return {"credits": floori(float(int(p.get("credits", 0))) * share), "ore": back, "started": started}


## Tooltip for the cancel button.
func cancel_text(t: TechDef) -> String:
	var c := cancel_terms(t)
	var ore := Economy.cost_text(c["ore"])
	var back := "%s cr%s" % [Fmt.amount(int(c["credits"])), " + " + ore if not ore.is_empty() else ""]
	if bool(c["started"]):
		return "Cancel: work has started, half comes back (%s). The progress is lost." % back
	return "Cancel: nobody has worked on it yet, all of it comes back (%s)." % back


func cancel(t: TechDef) -> void:
	if not projects.has(t.id):
		return
	var c := cancel_terms(t)
	projects.erase(t.id)
	Economy.add_income(int(c["credits"]), "Research refund")
	Economy.add(0, c["ore"])
	var r := researcher_on(t.id)
	if r:
		r.project = &""
		r.reason = "%s was cancelled" % t.display_name
	_log("Cancelled %s: %s cr back" % [t.display_name, Fmt.amount(int(c["credits"]))])
	_assign_idle()
	changed.emit()


## Credits reserved for funded projects.
func escrow_total() -> int:
	var n := 0
	for id: StringName in projects:
		n += int(projects[id].get("credits", 0))
	return n


## Funded projects in work order: {tech, progress (0..1), researcher or null}.
func active_projects() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: StringName in projects:
		var t := catalog().find(id)
		if t:
			out.append({"tech": t, "progress": progress_of(t), "researcher": researcher_on(id)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var aw := a["researcher"] != null
		var bw := b["researcher"] != null
		return aw if aw != bw else float(a["progress"]) > float(b["progress"]))
	return out


# --- Researchers --------------------------------------------------------------------

## Why [param a] cannot be hired now, or "".
func hire_problem(a: Researcher) -> String:
	if lab() == null:
		return "Build a Science Lab first"
	if researchers.size() >= MAX_RESEARCHERS:
		return "The lab has room for %d researchers" % MAX_RESEARCHERS
	if a == null or not applicants.has(a):
		return "No such applicant"
	return Economy.shortfall_text(a.hire_cost)


func hire(a: Researcher) -> bool:
	if not hire_problem(a).is_empty() or not Economy.spend(a.hire_cost):
		return false
	applicants.erase(a)
	a.hired_at = SimClock.time
	researchers.append(a)
	applicants.append(_new_applicant())
	_log("Hired %s (%s, skill %d, %s) for %s cr" % [a.researcher_name, a.field_name(), a.skill, a.personality_name(), Fmt.amount(a.hire_cost)])
	var l := lab()
	EventLog.post("%s joined the Science Lab (%s, skill %d)" % [a.researcher_name, a.field_name(), a.skill], EventLog.Kind.INFO, l.building if l else null)
	_assign_idle()
	changed.emit()
	return true


## Lets [param r] go. Their project stays funded with its progress.
func fire(r: Researcher) -> void:
	if not researchers.has(r):
		return
	researchers.erase(r)
	var t := catalog().find(r.project) if not r.project.is_empty() else null
	_log("%s left the lab%s" % [r.researcher_name, ", %s waits for someone else" % t.display_name if t else ""])
	r.project = &""
	_assign_idle()
	changed.emit()


func _new_applicant() -> Researcher:
	var a := Researcher.generate(rng, next_id)
	next_id += 1
	return a


func _refresh_applicants() -> void:
	applicants.clear()
	for i in APPLICANTS:
		applicants.append(_new_applicant())
	applicants_at = SimClock.time + APPLICANT_REFRESH


# --- Work ------------------------------------------------------------------------------

## One step of lab work (called by the active ScienceLab).
func sim_step(dt: float) -> void:
	if dt <= 0.0:
		return
	if SimClock.time >= applicants_at:
		_refresh_applicants()
		changed.emit()
	_assign_idle()
	for r in researchers:
		_pay_wage(r, dt)
	for r in researchers.duplicate():
		if r.is_idle() or r.unpaid:
			continue
		var t := catalog().find(r.project)
		if t == null or not projects.has(r.project):
			r.project = &""
			continue
		var p: Dictionary = projects[r.project]
		p["progress"] = float(p["progress"]) + dt * r.speed_on(t)
		if float(p["progress"]) >= t.research_time:
			_complete(t, r)


## Wages per sim minute for the whole staff, credits.
func wages_per_min() -> float:
	var w := 0.0
	for r in researchers:
		w += r.wage_per_min()
	return w


## True while any researcher is unpaid.
func any_unpaid() -> bool:
	for r in researchers:
		if r.unpaid:
			return true
	return false


## Accrues [param r]'s wage and pays it in whole credits; no credits, no work.
func _pay_wage(r: Researcher, dt: float) -> void:
	if not r.unpaid:
		r.wage_due += r.wage_per_min() * dt / 60.0
	var whole := floori(r.wage_due)
	if whole < 1 and not r.unpaid:
		return
	whole = maxi(whole, 1)
	if Economy.spend(whole):
		r.wage_due = maxf(r.wage_due - float(whole), 0.0)
		if r.unpaid:
			r.unpaid = false
			_log("%s is paid again" % r.researcher_name)
			changed.emit()
	elif not r.unpaid:
		r.unpaid = true
		_log("%s is unpaid: the station cannot pay the wage, research paused" % r.researcher_name)
		EventLog.post("%s is unpaid, research paused" % r.researcher_name, EventLog.Kind.THREAT, null)
		changed.emit()


## Idle researchers pick among the funded projects nobody works on.
func _assign_idle() -> void:
	for r in researchers:
		if not r.is_idle():
			continue
		var free: Array[TechDef] = []
		var progress := {}
		for id: StringName in projects:
			if researcher_on(id) == null:
				var t := catalog().find(id)
				if t:
					free.append(t)
					progress[id] = float(projects[id]["progress"])
		if free.is_empty():
			return
		var pick := ResearchChoice.pick(r, free, progress)
		var t := pick["tech"] as TechDef
		if t == null:
			continue
		r.project = t.id
		r.reason = String(pick["reason"])
		_log("%s: %s" % [r.researcher_name, r.reason])
		changed.emit()


func _complete(t: TechDef, r: Researcher) -> void:
	projects.erase(t.id)
	done[t.id] = SimClock.time
	r.project = &""
	r.completed += 1
	var grew := r.completed % 2 == 0 and r.skill < Researcher.MAX_SKILL
	if grew:
		r.skill += 1
	r.reason = "Finished %s" % t.display_name
	_log("%s finished %s%s" % [r.researcher_name, t.display_name, ", skill now %d" % r.skill if grew else ""])
	var l := lab()
	EventLog.post("Research complete: %s (%s). %s" % [t.display_name, r.researcher_name, unlock_text(t)], EventLog.Kind.REWARD, l.building if l else null)
	tech_completed.emit(t)
	_assign_idle()
	changed.emit()


## Marks [param t] (and its prerequisites) done at once (old saves, tests).
func grant(t: TechDef) -> void:
	if t == null or is_done(t.id):
		return
	done[t.id] = SimClock.time
	for p in t.prerequisites:
		grant(catalog().find(p))
	if projects.has(t.id):
		var c := int(projects[t.id].get("credits", 0))
		projects.erase(t.id)
		Economy.add_income(c, "Research refund")
		var r := researcher_on(t.id)
		if r:
			r.project = &""
	changed.emit()


## An older save without research: it keeps what it could use before. Every
## module tech up to the Factory's tooling tier is done, and the techs of
## every module a captain has fitted, holds in the warehouse or ordered.
## Building techs (the Raider Dock) are not granted.
func grant_legacy(tree: SceneTree) -> void:
	legacy_pending = false
	var f := Factory.find(tree)
	var tier := f.tooling_tier if f else 1
	var cat := catalog()
	for t in cat.techs:
		if t and not t.hidden and not t.unlock_modules.is_empty() and t.tier <= tier:
			grant(t)
	var owned: Array[StringName] = []
	for n in tree.get_nodes_in_group(Ship.GROUP):
		var s := n as Ship
		if s and s.loadout:
			for m in s.loadout.modules():
				if m:
					owned.append(m.id)
	if f:
		for id: StringName in f.warehouse:
			owned.append(StringName(id))
		for o in f.backorders:
			owned.append((o["module"] as ShipModule).id)
	for id in owned:
		grant(cat.for_module(id))
	_log("Older save: %d techs counted as researched" % done.size())


# --- Save --------------------------------------------------------------------------

func reset() -> void:
	done.clear()
	projects.clear()
	researchers.clear()
	applicants.clear()
	log_lines.clear()
	next_id = 1
	legacy_pending = false
	rng.randomize()
	_refresh_applicants()
	changed.emit()


func save_state() -> Dictionary:
	var rs := []
	for r in researchers:
		rs.append(r.save_state())
	var aps := []
	for a in applicants:
		aps.append(a.save_state())
	var ps := {}
	for id: StringName in projects:
		var p: Dictionary = projects[id]
		ps[id] = {"credits": int(p["credits"]), "ore": PackedInt32Array(p["ore"]), "progress": float(p["progress"]), "funded_at": float(p.get("funded_at", 0.0))}
	return {"done": done.duplicate(), "projects": ps, "researchers": rs, "applicants": aps, "applicants_at": applicants_at,
			"log": log_lines.duplicate(true), "next_id": next_id, "rng": SaveUtil.rng_state(rng)}


## Call after SimClock is restored. Empty [param d] (an older save): the start
## set, and [member legacy_pending] so the loader grants what the save used.
func load_state(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		legacy_pending = true
		return
	done = (d.get("done", {}) as Dictionary).duplicate()
	var cat := catalog()
	for id: Variant in (d.get("projects", {}) as Dictionary):
		var p: Dictionary = d["projects"][id]
		if cat.find(StringName(id)) == null:
			# A tech that no longer exists: give its reserve back.
			Economy.add(int(p.get("credits", 0)), PackedInt32Array(p.get("ore", [])))
			continue
		projects[StringName(id)] = {"credits": int(p.get("credits", 0)), "ore": PackedInt32Array(p.get("ore", [0, 0, 0])),
				"progress": float(p.get("progress", 0.0)), "funded_at": float(p.get("funded_at", 0.0))}
	researchers.clear()
	for rd: Dictionary in d.get("researchers", []):
		var r := Researcher.from_save(rd)
		if not r.project.is_empty() and not projects.has(r.project):
			r.project = &""
		researchers.append(r)
	applicants.clear()
	for ad: Dictionary in d.get("applicants", []):
		applicants.append(Researcher.from_save(ad))
	applicants_at = float(d.get("applicants_at", SimClock.time + APPLICANT_REFRESH))
	log_lines.assign(d.get("log", []))
	next_id = int(d.get("next_id", 1))
	SaveUtil.set_rng(rng, d.get("rng", {}))
	if applicants.is_empty():
		_refresh_applicants()
	changed.emit()


func _log(text: String) -> void:
	log_lines.append({"time": SimClock.time, "text": text})
	if log_lines.size() > MAX_LOG:
		log_lines.remove_at(0)

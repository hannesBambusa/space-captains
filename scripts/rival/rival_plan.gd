class_name RivalPlan
extends RefCounted
## RivalManager's build plan for a rival station world that is data
## ([RivalData]): the same priorities, thresholds and limits
## (RivalManager's static helpers), read from the saved world and what the
## data sim added, paying the real costs. What it builds goes into
## "builds" ({def, done}: sim time it is finished), what it hires into
## "hires" ({def, b}: the building key, see RivalData.berths), mining it
## posts into "mining" ({belt, pay}); RivalData.restore makes them real.
## Left out while data: escorts, the defence zone and den bounties (live
## only); a Forward Station that is due asks for the world live.

var tree: SceneTree
var id: StringName
var st: RemoteSystemState
var r: Corp
var d: Dictionary
var data: Dictionary
var hq := false
var eco: CorpEconomy
var res: CorpResearch


func _init(p_tree: SceneTree, p_id: StringName, p_st: RemoteSystemState, p_r: Corp) -> void:
	tree = p_tree
	id = p_id
	st = p_st
	r = p_r
	d = st.world
	data = d["data"]
	for k: String in ["builds", "hires", "mining"]:
		if not data.has(k):
			data[k] = []
	hq = bool(st.station.get("hq", false))
	eco = r.economy
	res = r.research


func run() -> void:
	var note := func(text: String) -> void: _note("", text)
	if hq:
		RivalManager.swap_for_iron(eco, note)
		RivalManager.swap_for_goal(eco, _goal_or_forward(), note)
	var done := 0
	for step: Callable in _plan():
		if done >= RivalManager.ACTIONS_PER_TICK:
			break
		if bool(step.call()):
			done += 1


func _minutes() -> float:
	return SimClock.time / 60.0


func spare() -> int:
	return eco.credits - RivalManager.RESERVE


## Same order as RivalManager._plan.
func _plan() -> Array[Callable]:
	var war := RivalManager.at_war(r)
	var first: Array[Callable] = [_building.bind(&"mining_outpost", 0.0, 1), _hire.bind(&"mining_outpost", 2), _mining_contracts]
	var guard: Array[Callable] = [_building.bind(&"mercenary_outpost", 2.0, RivalManager.merc_outposts_want(_minutes(), war)),
			_hire.bind(&"mercenary_outpost", RivalManager.merc_target_for(_minutes(), RivalManager.hostile(r)))]
	var grow: Array[Callable] = [_building.bind(&"explorer_outpost", 0.0, 1), _hire.bind(&"explorer_outpost", 1), _science, _mining_outposts,
			_hire.bind(&"mining_outpost", RivalManager.miner_target(_minutes())), _turrets, _building.bind(&"outfitter", 12.0, 1),
			_building.bind(&"shield_generator", 20.0, 1)]
	if not hq:
		return first + guard + [_building.bind(&"mining_outpost", 0.0, 2), _hire.bind(&"mining_outpost", 2), _turrets]
	if war:
		return guard + [_turrets, _building.bind(&"shield_generator", 0.0, 1)] + first + grow
	return first + guard + grow + [_forward_station]


## Why [param def] cannot be built here (BuildingManager.limit_reason on
## the counts), "" when it can.
func _limit(def: BuildingDef) -> String:
	if not hq and not def.allowed_forward:
		return "home station only"
	var locked := res.building_lock_reason(def.id)
	if not locked.is_empty():
		return locked
	if not def.in_service:
		return "not in service"
	var most := def.forward_max_count if not hq and def.forward_max_count >= 0 else def.max_count
	if most > 0 and RivalData.count(d, def.id) >= most:
		return "at the limit"
	return ""


func _building(def_id: StringName, after_min: float, want: int) -> bool:
	if _minutes() < after_min:
		return false
	var def := RivalData.def_of(def_id)
	if def == null or RivalData.count(d, def_id) >= want or not _limit(def).is_empty():
		return false
	if spare() < def.cost_credits or not eco.has_ore(def.cost_ore()):
		return false
	if RivalManager.EXTRAS.has(def_id) and not RivalManager.at_war(r):
		var goal := _saving_for()
		if goal and goal.id != def_id:
			var need := goal.cost_ore()
			if spare() < def.cost_credits + goal.cost_credits or eco.ore[Economy.Ore.IRON] < def.cost_iron + (need[0] if need.size() > 0 else 0):
				return false
	if RivalManager.DEFENCE_EXTRAS.has(def_id) and not RivalManager.at_war(r) and not (def_id == &"defense_turret" and RivalData.count(d, def_id) < 2):
		var rc := RivalManager.research_cost(res, _minutes())
		if rc > 0 and spare() < def.cost_credits + rc:
			return false
	if def.station_addon and _free_bays() <= 0:
		return false
	if not eco.spend(def.cost_credits, def.cost_ore(), Ledger.BUILDINGS, def.display_name):
		return false
	(data["builds"] as Array).append({"def": String(def_id), "done": SimClock.time + def.build_time})
	_note("", "Building a %s" % def.display_name)
	return true


func _free_bays() -> int:
	var used := 0
	for bd: Dictionary in (d.get("buildings", {}) as Dictionary).get("buildings", []):
		if int(bd.get("bay", 0)) > 0:
			used += 1
	for pb: Dictionary in data["builds"]:
		var def := RivalData.def_of(StringName(pb["def"]))
		if def and def.station_addon:
			used += 1
	return (RivalData.HQ_BAYS if hq else RivalData.FORWARD_BAYS) - used


## The key building it saves for (RivalManager._saving_for).
func _saving_for() -> BuildingDef:
	if not hq:
		return null
	for def_id: StringName in [&"science_lab", &"explorer_outpost"]:
		var def := RivalData.def_of(def_id)
		if def == null or RivalData.count(d, def_id) > 0 or not _limit(def).is_empty():
			continue
		if def_id == &"science_lab" and _minutes() < 7.0:
			continue
		return def
	return null


## The saving goal, or the Forward Station when one is due (for the swap).
func _goal_or_forward() -> BuildingDef:
	var goal := _saving_for()
	if goal == null and _forward_due():
		goal = RivalData.def_of(ForwardStations.BUILD_ID)
	return goal


func _forward_due() -> bool:
	var def := RivalData.def_of(ForwardStations.BUILD_ID)
	return def != null and _minutes() >= RivalManager.forward_after and res.building_lock_reason(def.id).is_empty() \
			and ForwardStations.free_slots(tree, r.id) > 0


func _hire(def_id: StringName, per_building: int) -> bool:
	var def := RivalData.def_of(def_id)
	if def == null or spare() < def.hire_cost_credits:
		return false
	if not hq and _supply_blocks():
		return false
	var b := RivalData.berths(d, def_id)
	for key: String in b:
		if int(b[key]) >= mini(per_building, def.max_hires):
			continue
		if not eco.spend(def.hire_cost_credits, PackedInt32Array(), Ledger.HIRES, "Hire at %s" % def.display_name):
			return false
		(data["hires"] as Array).append({"def": String(def_id), "b": key})
		_note("", "Hired a %s at the %s" % [def.hire_role.to_lower(), def.display_name])
		return true
	return false


## A forward station's supply blocks hiring while upkeep is owed (StationSupply).
func _supply_blocks() -> bool:
	return eco.credits <= 0


func _mining_outposts() -> bool:
	return _building(&"mining_outpost", 0.0, RivalManager.mining_outposts_want(_minutes()))


func _turrets() -> bool:
	var hostile := RivalManager.hostile(r)
	if not hostile and eco.ore[Economy.Ore.IRON] < 220:
		return false
	return _building(&"defense_turret", 0.0, RivalManager.turret_want(_minutes(), hostile))


## One mining job per miner pair on the best cluster (RivalManager._mining_contracts).
func _mining_contracts() -> bool:
	var miners := RivalData.captains_of(d, &"mining_outpost")
	if miners == 0:
		return false
	var jobs := RivalData.mining_jobs(d)
	var on := {}
	var open := 0
	for j: Dictionary in jobs:
		var cd := RivalData.cluster(d, String(j["belt"]))
		if not cd.is_empty() and int(cd.get("left", 0)) > 0:
			open += 1
			on[String(j["belt"])] = true
	var want := clampi(ceili(miners / 2.0), 1, 3)
	if open >= want:
		return false
	var site := _station_position()
	var mercs := RivalData.captains_of(d, &"mercenary_outpost")
	var best := {}
	var best_score := INF
	for cd: Dictionary in (d.get("clusters", {}) as Dictionary).get("list", []):
		var cname := String(cd.get("name", ""))
		if on.has(cname) or int(cd.get("left", 0)) <= 0:
			continue
		var danger := int(cd.get("danger", 1))
		if danger > 1 + floori(mercs / 2.0):
			continue
		var cdef := ClusterDef.from_dict(cd)
		var km := site.distance_to(Survey.cluster_position(cdef, SimClock.time)) / 1000.0
		var value := float(ContractBoard.mining_rules.materials_for(cdef.ore_type))
		var score := km + 8.0 * float(danger) - value / 15.0
		var ore := Economy.ore_of_belt(cdef.ore_type)
		if ore < RivalManager.KEEP.size() and eco.ore[ore] < RivalManager.KEEP[ore]:
			score -= 8.0 if ore == Economy.Ore.IRON else 4.0
		elif ore < RivalManager.KEEP.size() and eco.ore[ore] > RivalManager.KEEP[ore] * RivalManager.OVERSTOCK:
			score += 30.0
		if score < best_score:
			best_score = score
			best = cd
	if best.is_empty():
		return false
	var cdef2 := ClusterDef.from_dict(best)
	var base := ContractBoard.mining_rules.base_reward[clampi(cdef2.ore_type, 0, ContractBoard.mining_rules.base_reward.size() - 1)] \
			+ ContractBoard.mining_rules.danger_premium * maxi(cdef2.danger - 1, 0)
	var bonus := 40 if Economy.ore_of_belt(cdef2.ore_type) == Economy.Ore.IRON else 20
	var pay := ContractBoard.mining_rules.clamp_reward(base + bonus)
	if Corps.difficulty == CorpRegistry.Difficulty.HARD:
		pay = ContractBoard.mining_rules.clamp_reward(roundi(pay * 1.2))
	(data["mining"] as Array).append({"belt": String(best["name"]), "pay": pay})
	_note("", "Posted mining on %s at %d cr/load" % [best["name"], pay])
	return true


## Where the station is now (its site planet's position).
func _station_position() -> Vector3:
	var def := Sector.system_def(id)
	var planet := String(st.station.get("planet", ""))
	if def:
		for p in def.planets:
			if p.name == planet:
				return Survey.planet_position(p, SimClock.time)
	return Vector3.ZERO


## The Science Lab, then researchers and funding (RivalManager.science_step).
func _science() -> bool:
	if _minutes() < 7.0:
		return false
	if _building(&"science_lab", 7.0, 1):
		return true
	if not RivalData.has_lab(st):
		return false
	res.data_lab = true
	var goal := _saving_for()
	return RivalManager.science_step(res, spare(), _minutes(), goal != null and goal.id == &"explorer_outpost", func(text: String) -> void: _note("", text))


## A Forward Station is due: the live RivalManager founds it.
func _forward_station() -> bool:
	var def := RivalData.def_of(ForwardStations.BUILD_ID)
	if not _forward_due() or spare() < def.cost_credits:
		return false
	var need := def.cost_ore()
	if eco.ore[Economy.Ore.IRON] < need[Economy.Ore.IRON] or eco.ore[Economy.Ore.TITANIUM] < need[Economy.Ore.TITANIUM]:
		return false
	if RivalManager.pick_target(tree, r.id).is_empty():
		return false
	var rw := RivalWorlds.of(tree)
	if rw:
		rw.request(id, 120.0, "a forward station is due")
	return true


## An intel line, one per [param key] while it repeats ("" = always).
func _note(key: String, text: String) -> void:
	var noted: Dictionary = data.get("noted", {})
	data["noted"] = noted
	if not key.is_empty():
		if noted.get(key, "") == text:
			return
		noted[key] = text
	r.mind.note(text)

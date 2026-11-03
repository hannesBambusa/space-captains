class_name RivalManager
extends Node
## The rival corporation's colony manager (rival corporation plan, R2):
## child of the rival headquarters' [SystemWorld] (SystemHost.materialise).
## Every [method interval] sim seconds it takes at most [constant
## ACTIONS_PER_TICK] steps of its build plan, through the same calls the
## HUD uses (BuildingManager.place / install_addon, Building.hire,
## (no Salvage Yard: its auto-buy would spend the credits on held ore)
## ContractBoard.post_*, CorpResearch.fund / hire), inside
## Corps.act_as(its corp), so it pays real costs and obeys every limit.
## One per rival station, each for the corp of its system (rivals plan M1).
## Its captains are ordinary captains with ordinary brains on its contracts.
##
## Stateless on purpose: every tick reads the colony as it is, so nothing
## here is saved. The boardroom ([RivalCorp], [RivalMind]) sets the mood:
## at war it keeps more mercenaries and turrets and spends on defence first.

## Credits kept back for contract pay and wages.
const RESERVE := 400
const ACTIONS_PER_TICK := 2
## Tick length by difficulty (Off, Easy, Normal, Hard), sim seconds.
const INTERVALS: PackedFloat32Array = [12.0, 20.0, 12.0, 8.0]
## Research the manager funds, first that it can get first.
const TECH_ORDER: Array[StringName] = [&"eng_jump_navigation", &"eng_shield_emitters", &"wpn_ballistic_calibration", &"pln_cargo_racks",
		&"eng_survival_systems", &"wpn_rail_cannons", &"eng_laminated_alloys", &"pln_deep_core",
		&"wpn_fire_control", &"eng_shield_lattice", &"eng_forward_operations", &"eng_ion_tuning", &"wpn_linked_feeds"]
## Den bounty base pay (TargetPanel.den_reward) and the share of credits it may use.
const DEN_BOUNTY := 800
## Pay per escorted trip.
const ESCORT_PAY := 40
## Sim minutes before it founds a forward station (tests lower it).
static var forward_after := 25.0
## "Keep at least" on its Factory: iron, titanium, crystal for building.
const KEEP: PackedInt32Array = [300, 80, 20]
## Builds that wait while it saves up for a key one (see [method _saving_for]).
const EXTRAS: Array[StringName] = [&"defense_turret", &"shield_generator", &"outfitter", &"mining_outpost", &"mercenary_outpost"]
## Iron per unit of titanium / crystal in the corp office swap (by Ore index).
const SWAP_RATES := {1: 2, 2: 4}
const SWAP_MAX := 100

var _clock := 0.0
var _rng := RandomNumberGenerator.new()
## Last line per kind, so the intel log is not flooded.
var _noted := {}


func _ready() -> void:
	add_to_group(SimStepper.GROUP)
	_rng.seed = hash("rival_manager:%d" % Sector.get_seed())
	# Spread the first tick so it does not land with everything else.
	_clock = 2.0


func _process(delta: float) -> void:
	if not SimClock.paused:
		sim_step(delta * SimClock.speed)


func interval() -> float:
	return INTERVALS[clampi(Corps.difficulty, 0, INTERVALS.size() - 1)]


func sim_step(dt: float) -> void:
	if not Corps.has_rival() or dt <= 0.0:
		return
	var r := corp()
	if r == null or r.mind.eliminated:
		return
	_clock -= dt
	if _clock > 0.0:
		return
	_clock = interval()
	Corps.act_as(r.id, _tick)


## The rival this station belongs to (its system's corp).
func corp() -> Corp:
	return Corps.rival(_cid())


func _cid() -> StringName:
	var w := world()
	return w.corp_id if w else &""


## At war with any corp.
func _at_war() -> bool:
	var r := corp()
	if r == null:
		return false
	for k: StringName in r.mind.ties:
		if Corps.corps_at_war(r.id, k):
			return true
	return false


## Harassing or at war with any corp.
func _hostile() -> bool:
	var r := corp()
	if r == null:
		return false
	for k: StringName in r.mind.ties:
		if (r.mind.ties[k] as RivalMind.Tie).hostile() or Corps.corps_at_war(r.id, k):
			return true
	return false


func world() -> SystemWorld:
	return SystemWorld.of(self)


func mgr() -> BuildingManager:
	var w := world()
	return w.buildings if w else null


func eco() -> CorpEconomy:
	return corp().economy


func research() -> CorpResearch:
	return corp().research


## Free credits above the reserve.
func spare() -> int:
	return eco().credits - RESERVE


func _tick() -> void:
	var b := mgr()
	if b == null or b.frame == null:
		return
	if world().is_hq:
		_keep_ore()
		_swap_for_iron()
		_dispatch()
	var done := 0
	for step: Callable in _plan():
		if done >= ACTIONS_PER_TICK:
			break
		if bool(step.call()):
			done += 1


## The build plan in priority order (each returns true when it acted):
## a first mining outpost and miners, then mercenaries to guard them, then
## growth. At war defence comes first.
func _plan() -> Array[Callable]:
	var war := _at_war()
	var first: Array[Callable] = [_building.bind(&"mining_outpost", 0.0, 1), _hire.bind(&"mining_outpost", 2), _mining_contracts, _escorts]
	var guard: Array[Callable] = [_building.bind(&"mercenary_outpost", 2.0, _merc_outposts()), _hire.bind(&"mercenary_outpost", _merc_target())]
	# Scouting first once researched: it is how the rival finds anyone.
	var grow: Array[Callable] = [_building.bind(&"explorer_outpost", 0.0, 1), _hire.bind(&"explorer_outpost", 1), _science, _mining_outposts, _hire.bind(&"mining_outpost", _miner_target()), _turrets, _zone,
			_addon.bind(&"outfitter", 12.0),
			_building.bind(&"shield_generator", 20.0, 1), _den_bounty]
	if not world().is_hq:
		# A forward station: mining and its guard.
		return first + guard + [_building.bind(&"mining_outpost", 0.0, 2), _hire.bind(&"mining_outpost", 2), _turrets]
	var found: Array[Callable] = [_forward_station]
	if war:
		return guard + [_turrets, _building.bind(&"shield_generator", 0.0, 1)] + first + grow
	return first + guard + grow + found


## The Factory keeps building ore back from auto-sell ([constant KEEP]).
func _keep_ore() -> void:
	var f := Factory.find(self)
	var m := f.market if f else null
	if m == null:
		return
	var p := m.primary()
	for i in KEEP.size():
		if p.reserve[i] != KEEP[i]:
			p.set_reserve(i, KEEP[i])


## Short of iron with surplus crystal or titanium: the corp office swaps
## some (at most [constant SWAP_MAX] iron a tick, [constant SWAP_RATES] iron
## per unit). An AI-only crutch: it has no planet raids or refinery.
func _swap_for_iron() -> void:
	var o := eco().ore
	var iron := Economy.Ore.IRON
	if o[iron] >= KEEP[iron]:
		return
	for t: int in [Economy.Ore.CRYSTAL, Economy.Ore.TITANIUM]:
		var spare_units := o[t] - KEEP[t] - 100
		if spare_units <= 0:
			continue
		var rate: int = SWAP_RATES[t]
		var units := mini(spare_units, ceili(float(SWAP_MAX) / rate))
		var take := Economy.zero_ore()
		take[t] = units
		if eco().spend(0, take):
			eco().add_ore_of(iron, units * rate)
			_note("swap", "The corp office swapped %d %s for %d iron" % [units, Economy.ore_name(t), units * rate])
		return


func _minutes() -> float:
	return SimClock.time / 60.0


func _miner_target() -> int:
	return 2 if _minutes() < 20.0 else 3


func _merc_outposts() -> int:
	var war := _at_war()
	return 2 if war or _minutes() > 30.0 else 1


func _merc_target() -> int:
	var war := _hostile()
	if war:
		return 4
	return 2 if _minutes() < 25.0 else 3


# --- Steps --------------------------------------------------------------------

func _mining_outposts() -> bool:
	var want := 1 + (1 if _minutes() > 4.0 else 0) + (1 if _minutes() > 16.0 else 0)
	return _building(&"mining_outpost", 0.0, want)


## Builds one more [param id] (structure or addon) when it is past
## [param after_min] sim minutes, below [param want] of them and affordable.
func _building(id: StringName, after_min: float, want: int) -> bool:
	if _minutes() < after_min:
		return false
	var b := mgr()
	var def := b.def_by_id(id)
	if def == null or b.count_of(def) >= want or not b.limit_reason(def).is_empty():
		return false
	if spare() < def.cost_credits or not eco().has_ore(def.cost_ore()):
		return false
	# Extras wait while it saves up for the Science Lab or the Explorer Outpost.
	if EXTRAS.has(id) and not _at_war():
		var goal := _saving_for()
		if goal and goal.id != id:
			var need := goal.cost_ore()
			if spare() < def.cost_credits + goal.cost_credits or eco().ore[Economy.Ore.IRON] < def.cost_iron + (need[0] if need.size() > 0 else 0):
				return false
	if def.station_addon:
		return _install(def)
	var spot := _find_spot(def)
	if spot == Vector3.INF:
		_note("spot:%s" % id, "No room for a %s near the station" % def.display_name)
		return false
	if b.place(def, spot) == null:
		return false
	_note("", "Building a %s" % def.display_name)
	return true


## The key building it saves up for, null when none: the Science Lab
## (from minute 7), then the Explorer Outpost once it is researched.
func _saving_for() -> BuildingDef:
	var b := mgr()
	if not world().is_hq:
		return null
	for id: StringName in [&"science_lab", &"explorer_outpost"]:
		var def := b.def_by_id(id)
		if def == null or b.count_of(def) > 0 or not b.limit_reason(def).is_empty():
			continue
		if id == &"science_lab" and _minutes() < 7.0:
			continue
		return def
	return null


func _addon(id: StringName, after_min: float) -> bool:
	return _building(id, after_min, 1)


func _install(def: BuildingDef) -> bool:
	var b := mgr()
	var bays := b.free_bays()
	if bays.is_empty() or b.install_addon(def, bays[0]) == null:
		return false
	_note("", "Installing the %s" % def.display_name)
	return true


## A free spot for [param def]: rings round the station, nearest first.
func _find_spot(def: BuildingDef) -> Vector3:
	var b := mgr()
	var start := _rng.randf_range(0.0, TAU)
	var r := 280.0
	while r <= 1600.0:
		for i in 16:
			var a := start + TAU * float(i) / 16.0
			var off := Vector3(cos(a) * r, 0.0, sin(a) * r)
			if b.plan_placement(def, off).is_valid():
				return off
		r += 110.0
	return Vector3.INF


## Hires at each active [param id] up to [param per_building] captains.
func _hire(id: StringName, per_building: int) -> bool:
	var b := mgr()
	for bld in b.buildings:
		if not is_instance_valid(bld) or bld.def.id != id or bld.captains.size() >= per_building:
			continue
		if not bld.hire_block_reason().is_empty() or spare() < bld.def.hire_cost_credits:
			continue
		var s := bld.hire()
		if s:
			_note("", "Hired %s at %s" % [s.captain.captain_name if s.captain else "a pilot", bld.display_name])
			return true
	return false


## One open mining contract per miner pair, on the safest near clusters.
func _mining_contracts() -> bool:
	var w := world()
	var sys := w.sys if w else null
	if sys == null:
		return false
	var miners := _captains_of(&"mining_outpost")
	if miners == 0:
		return false
	var open := 0
	var on := {}
	for c in ContractBoard.contracts:
		var mc := c as MiningContract
		if mc and mc.corp == _cid() and not mc.is_finished() and mc.system_id == w.system_id:
			open += 1
			on[mc.belt] = true
	var want := clampi(ceili(miners / 2.0), 1, 3)
	var iron_short := eco().ore[Economy.Ore.IRON] < KEEP[Economy.Ore.IRON]
	if open >= want:
		# Short of iron: a contract on other ore makes room for an iron one.
		if iron_short and _free_iron_cluster(sys, on):
			for c in ContractBoard.contracts:
				var mc := c as MiningContract
				if mc and mc.corp == _cid() and not mc.is_finished() and mc.system_id == w.system_id and is_instance_valid(mc.belt) \
						and Economy.ore_of_belt(mc.belt.ore_type) != Economy.Ore.IRON:
					ContractBoard.cancel(mc)
					_note("", "Moved the miners off %s: iron first" % mc.belt.def.name)
					return true
		return false
	var station := sys.home_station
	var best: AsteroidCluster = null
	var best_score := INF
	for belt in sys.belts:
		if not is_instance_valid(belt) or belt.is_depleted or on.has(belt) or not belt.has_ore_for_new_trip():
			continue
		var km := station.global_position.distance_to(belt.global_position) / 1000.0 if station else 10.0
		# Danger past what its mercenaries can cover is out.
		if belt.danger > 1 + floori(_captains_of(&"mercenary_outpost") / 2.0):
			continue
		var value := float(ContractBoard.mining_rules.materials_for(belt.ore_type))
		var score := km + 8.0 * float(belt.danger) - value / 15.0
		# The ore it is short of for building comes first.
		var ore := Economy.ore_of_belt(belt.ore_type)
		if ore < KEEP.size() and eco().ore[ore] < KEEP[ore]:
			score -= 8.0 if ore == Economy.Ore.IRON else 4.0
		if score < best_score:
			best_score = score
			best = belt
	if best == null:
		return false
	# A little over fair pay, so its miners take the work.
	var bonus := 40 if Economy.ore_of_belt(best.ore_type) == Economy.Ore.IRON else 20
	var pay := ContractBoard.mining_rules.clamp_reward(ContractBoard.mining_rules.default_reward(best) + bonus)
	if Corps.difficulty == CorpRegistry.Difficulty.HARD:
		pay = ContractBoard.mining_rules.clamp_reward(roundi(pay * 1.2))
	if ContractBoard.post_mining(best, pay) == null:
		return false
	_note("", "Posted mining on %s at %d cr/load" % [best.def.name, pay])
	return true


## An escort contract on each mining contract past danger 1 while it has
## two mercenaries or more.
func _escorts() -> bool:
	if _captains_of(&"mercenary_outpost") < 2:
		return false
	for c in ContractBoard.contracts:
		var mc := c as MiningContract
		if mc == null or mc.corp != _cid() or mc.is_finished() or not is_instance_valid(mc.belt) or mc.belt.danger < 2:
			continue
		if ContractBoard.escort_for_mining(mc) != null:
			continue
		if spare() < ESCORT_PAY * 3:
			return false
		if ContractBoard.post_escort_for_mining(mc, ESCORT_PAY) != null:
			_note("", "Escorts for the miners on %s" % mc.belt.def.name)
			return true
	return false


## A safe iron cluster with ore and no contract of its own, else null.
func _free_iron_cluster(sys: SolarSystem, on: Dictionary) -> AsteroidCluster:
	for belt in sys.belts:
		if is_instance_valid(belt) and not belt.is_depleted and not on.has(belt) and belt.has_ore_for_new_trip() \
				and Economy.ore_of_belt(belt.ore_type) == Economy.Ore.IRON and belt.danger <= 1 + floori(_captains_of(&"mercenary_outpost") / 2.0):
			return belt
	return null


func _captains_of(id: StringName) -> int:
	var n := 0
	for bld in mgr().buildings:
		if is_instance_valid(bld) and bld.def.id == id:
			n += bld.captains.size()
	return n


func _turrets() -> bool:
	var war := _hostile()
	var want := 0
	if _minutes() > 9.0:
		want = 2
	if _minutes() > 25.0:
		want = 4
	if war:
		want = 6
	# Peacetime turrets wait for spare iron (outposts and the lab come first).
	if not war and eco().ore[Economy.Ore.IRON] < 220:
		return false
	return _building(&"defense_turret", 0.0, want)


## The Science Lab, researchers, and the next tech of [constant TECH_ORDER].
func _science() -> bool:
	if _minutes() < 7.0:
		return false
	if _building(&"science_lab", 7.0, 1):
		return true
	var res := research()
	if res.lab() == null:
		return false
	if res.researchers.size() < (1 if _minutes() < 20.0 else 2) and not res.applicants.is_empty():
		var a := res.applicants[0]
		for x in res.applicants:
			if x.skill > a.skill:
				a = x
		if spare() >= a.hire_cost + 300 and res.hire(a):
			_note("", "Hired researcher %s" % a.researcher_name)
			return true
	# No new funding while it saves for the Explorer Outpost (tech costs ore too).
	var goal := _saving_for()
	if goal and goal.id == &"explorer_outpost":
		return false
	if res.projects.size() >= maxi(res.researchers.size(), 1):
		return false
	for id in TECH_ORDER:
		var t := res.catalog().find(id)
		if t == null or not res.fund_problem(t).is_empty():
			continue
		if spare() < t.cost_credits + 300:
			return false
		if res.fund(t):
			_note("", "Funded research: %s" % t.display_name)
			return true
	return false


## A defence zone over the station once it has mercenaries.
func _zone() -> bool:
	var w := world()
	var zones := DefenseZones.of(w) if w else null
	if zones == null or zones.count() > 0 or _captains_of(&"mercenary_outpost") < 2:
		return false
	var st := w.sys.home_station if w.sys else null
	if st == null or not zones.place_problem(st.global_position).is_empty():
		return false
	if zones.place(st.global_position, 2400.0) == null:
		return false
	_note("", "Placed a defence zone over the station")
	return true


## A bounty on the nearest standing base once its mercenaries can take it.
func _den_bounty() -> bool:
	if _captains_of(&"mercenary_outpost") < 3 or _minutes() < 14.0:
		return false
	var w := world()
	var sys := w.sys if w else null
	if sys == null:
		return false
	for c in ContractBoard.contracts:
		var bc := c as BountyContract
		if bc and bc.corp == _cid() and not bc.is_finished() and bc.is_den() and bc.system_id == w.system_id:
			return false
	var st := sys.home_station
	var best: ScavengerDen = null
	var best_d := INF
	for den in sys.dens:
		if not Combat.is_live(den) or den is ClaimGarrison:
			continue
		var d := st.global_position.distance_to(den.global_position) if st else 0.0
		if d < best_d:
			best_d = d
			best = den
	if best == null:
		return false
	var fac := Factions.of(best)
	var pay := roundi(DEN_BOUNTY * (fac.bounty_mult if fac else 1.0) / 25.0) * 25
	if spare() < pay + 600:
		return false
	if ContractBoard.post_bounty(best, pay) == null:
		return false
	_note("", "Posted a %d cr bounty on %s" % [pay, best.get_display_name()])
	return true


# --- Forward stations (R8) ------------------------------------------------------

## A Forward Station once Forward operations is researched, past
## [constant forward_after] minutes, with a free slot. The rival has no
## planet raids, so the corp ships it the water the build needs.
func _forward_station() -> bool:
	if _minutes() < forward_after:
		return false
	var b := mgr()
	var def := b.def_by_id(ForwardStations.BUILD_ID)
	if def == null or not b.limit_reason(def).is_empty():
		return false
	if _pick_target().is_empty() or b.count_of(def) > 0 or spare() < def.cost_credits:
		return false
	var need := def.cost_ore()
	if eco().ore[Economy.Ore.IRON] < need[Economy.Ore.IRON] or eco().ore[Economy.Ore.TITANIUM] < need[Economy.Ore.TITANIUM]:
		return false
	if need.size() > Economy.Ore.WATER and eco().ore[Economy.Ore.WATER] < need[Economy.Ore.WATER]:
		eco().add_ore_of(Economy.Ore.WATER, need[Economy.Ore.WATER] - eco().ore[Economy.Ore.WATER])
		_note("", "The corp shipped water for a forward station")
	return _building(ForwardStations.BUILD_ID, forward_after, b.count_of(def) + 1)


## Parked mobile stations of the rival at the HQ get a destination.
func _dispatch() -> void:
	for n in SystemWorld.nodes_in(self, MobileStation.MOBILE_GROUP):
		var ms := n as MobileStation
		if ms == null or ms.dead or ms.corp != _cid() or ms.state != MobileStation.State.PARKED:
			continue
		var t := _pick_target()
		if t.is_empty():
			return
		var site := RivalCorp.hq_site(StringName(t["id"]))
		if site.is_empty():
			return
		if ms.set_destination_site(StringName(t["id"]), String(site["planet"])):
			_note("", "%s is on its way to %s" % [ms.get_display_name(), t["name"]])


## The best charted system for a forward station: between the two
## charters, danger at most ForwardStations.MAX_DANGER, no station, nobody
## headed there, with clusters. {} when none.
func _pick_target() -> Dictionary:
	var rc := RivalCorp.of(get_tree())
	var net := Sector.network
	if rc == null or net == null:
		return {}
	var mine := Corps.home_of(_cid())
	var best := {}
	var best_s := INF
	for id in rc.charted(_cid()):
		if not Corps.corp_at_home(id).is_empty():
			continue
		var e := net.entry(id)
		var st := Sector.state(id)
		var def := Sector.system_def(id)
		if e == null or st == null or def == null or not st.station.is_empty() or e.danger > ForwardStations.MAX_DANGER or def.belts.is_empty():
			continue
		if MobileStation.headed_to(get_tree(), id):
			continue
		var from_me := net.path(mine, id).size() - 1
		var from_them := net.path(ClusterNetwork.HOME_ID, id).size() - 1
		var score := absf(from_me - from_them) + 0.5 * from_me + 0.3 * e.danger
		if score < best_s:
			best_s = score
			best = {"id": id, "name": def.system_name}
	return best


## A private intel line ([param key] keeps one per kind, "" = always).
func _note(key: String, text: String) -> void:
	var m := corp().mind if corp() else null
	if m == null:
		return
	if not key.is_empty():
		if _noted.get(key, "") == text:
			return
		_noted[key] = text
	m.note(text)

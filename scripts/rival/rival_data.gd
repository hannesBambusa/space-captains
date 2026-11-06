class_name RivalData
extends RefCounted
## A rival station world as data (rival corporation plan, "Data sim for
## unviewed rival worlds"; [RivalWorlds] decides when).
##
## Leaving: [method capture] (from SystemHost.dematerialise) saves the
## whole world with the save code (GameSnapshot.capture_system: captains,
## buildings, clusters, dens, scrap, ships, fleets, directors, zones,
## supply) plus its contracts (ContractCodec, this system's only; they come
## off the board) into RemoteSystemState.world, with a "data" part for the
## data sim. Coming back: [method restore] (from SystemHost.materialise)
## applies it with GameSnapshot.apply_systems, launches the base packs that
## RemoteSim counted meanwhile, then settles what the data sim did: the
## structures it built (placed done, or still under construction), the
## captains it hired (the hire was paid while data: refunded, then hired
## for real) and the mining contracts it posted.
##
## The data step ([method step], every RivalManager.interval sim seconds,
## inside Corps.act_as its corp) runs the colony from counts:
## - mining: each miner flies [constant LOADS_PER_MIN] loads a sim minute
##   on the corp's mining contracts there (the saved ones and the ones the
##   data sim posted), each the ore of the contract's cluster, the units
##   MiningRules.materials_for times [constant UNITS_FACTOR], paid the
##   contract's reward; the cluster's loads count down;
## - Factory sales (headquarters): ore over RivalManager.KEEP sells at
##   [constant SELL_PRICE] per unit, at most [constant SELL_PER_MIN] a minute;
## - captains: station fees, [constant FEE_SHARE] of the mining pay (what
##   the miners spend at the station), less [constant REPAIRS_PER_MIN] a
##   captain and minute for repairs;
## - a forward station's upkeep (StationSupply.upkeep_per_minute, free for
##   its first two minutes as live);
## - new clusters: with fewer than SystemDef.cluster_min left, a cluster the
##   data sim mined out fills up again after SystemDef.cluster_respawn (a
##   shortcut for ClusterSpawner, which needs the live system to place a
##   new one; the live spawner takes over when the world is back);
## - research (headquarters with a Science Lab): CorpResearch.sim_step,
##   wages included (CorpResearch.data_lab stands in for the lab);
## - the build plan: RivalManager's priorities and thresholds on the counts
##   ([method _plan]), paying the real costs into "builds" and "hires".
## Not modelled while data: escorts, defence zones, den bounties. Pirate
## raids are left out on purpose: measured live (smoke --rival --rival-live,
## 60 min) they cost a rival next to nothing, its mercs and turrets kill
## the raiders (0 ships lost, no cargo stolen, 1 to 2% of miner time
## fleeing over 5 to 8 raids). A Forward Station that is due asks for the world
## live (RivalWorlds.request) so RivalManager founds it.
##
## The rates are from live smoke runs (see the rival corporation doc).

## Mining loads per miner and sim minute (live: loads delivered / miner-minutes).
const LOADS_PER_MIN := 0.3
## Units per load: MiningRules.materials_for times this (live average).
const UNITS_FACTOR := 1.0
## Factory price per unit sold (iron, titanium, crystal; live average).
const SELL_PRICE: PackedFloat32Array = [9.0, 15.0, 23.0]
## Most units the Factory takes per sim minute (live: about 14 iron a
## minute while it holds a surplus; FactoryMarket buys slower than its
## max_buy_per_min at the follow-market ask).
const SELL_PER_MIN: PackedFloat32Array = [15.0, 12.0, 10.0]
## Station fees per credit of mining pay (live: fees / contract pay).
const FEE_SHARE := 0.25
## Repairs the corp pays per captain and sim minute (live average).
const REPAIRS_PER_MIN := 0.5
## A data merc's fighting power when none was measured (MercFleet reference).
const MERC_POWER := 1.0
## Station bays (HomeStation.bay_count; forward profile 2).
const HQ_BAYS := 6
const FORWARD_BAYS := 2
const DEF_PATH := "res://data/buildings/%s.tres"

static var _defs := {}


## A building def by id (data/buildings), cached.
static func def_of(id: StringName) -> BuildingDef:
	if not _defs.has(id):
		_defs[id] = load(DEF_PATH % id) as BuildingDef if ResourceLoader.exists(DEF_PATH % id) else null
	return _defs[id]


# --- Capture and restore ----------------------------------------------------------

## True when [param w] is a rival station world that goes data when dropped.
static func is_rival_world(w: SystemWorld) -> bool:
	if w == null or w.is_home or not w.has_station:
		return false
	return Corps.is_rival(RivalWorlds.site_corp(w.system_id)) and RivalWorlds.data_enabled


## The whole live world [param w] as data (see the class notes). Its
## contracts leave the board.
static func capture(w: SystemWorld) -> Dictionary:
	var id := w.system_id
	var corp := w.corp_id
	var trips: Array[Contract] = []
	var d := GameSnapshot.capture_system(w, trips, false)
	var kept := _contracts_of(w)
	var keep := func(c: Contract) -> bool: return kept.has(c) or ContractCodec.system_of(c) == id
	d["contracts"] = ContractCodec.save_all(trips, keep)
	var power := 0.0
	var mercs := 0
	for n in SystemWorld.nodes_in(w, Ship.GROUP):
		var s := n as Ship
		if s and not s.dead and s.role == Ship.Role.MERCENARY and s.captain and Corps.owner_of(s) == corp:
			power += MercFleet.power_of(s)
			mercs += 1
	d["data"] = {"since": SimClock.time, "builds": [], "hires": [], "mining": [], "merc_power": power, "merc_n": mercs, "acc": {}}
	for c in ContractBoard.contracts.duplicate():
		if keep.call(c):
			ContractBoard.shelve(c)
	for c in ContractBoard.held.duplicate():
		if keep.call(c):
			ContractBoard.shelve(c)
	var rw := RivalWorlds.of(w.get_tree())
	if rw:
		rw.went_data += 1
	return d


## The board's contracts that go with [param w] (as keys): its system's,
## and its corp's whose target or takers are in it (and the escorts linked
## to those), so no contract on the board is left pointing at ships that
## leave with the world.
static func _contracts_of(w: SystemWorld) -> Dictionary:
	var out := {}
	var all: Array[Contract] = []
	all.append_array(ContractBoard.contracts)
	all.append_array(ContractBoard.held)
	for c in all:
		if ContractCodec.system_of(c) == w.system_id:
			out[c] = true
		elif c.corp == w.corp_id and (_in(c.target, w) or _any_in(c.takers, w)):
			push_warning("RivalData: %s (system %s) has its target or takers in %s; it goes with it" % [c.get_title(), c.system_id, w.system_id])
			out[c] = true
	for c in all:
		var ec := c as EscortContract
		if ec and ec.mining_contract and out.has(ec.mining_contract):
			out[c] = true
	return out


static func _in(n: Variant, w: SystemWorld) -> bool:
	var node := n as Node if is_instance_valid(n) else null
	return node != null and node.is_inside_tree() and SystemWorld.of(node) == w


static func _any_in(list: Array, w: SystemWorld) -> bool:
	for n: Variant in list:
		if _in(n, w):
			return true
	return false


## Puts the data world of [param st] into the freshly built [param w]
## (SystemHost.materialise, after its StationSupply exists).
static func restore(w: SystemWorld, st: RemoteSystemState) -> void:
	var d := st.world
	st.world = {}
	if d.is_empty():
		return
	# The bases as RemoteSim left them (respawn clocks, shields, pending launches).
	var dens := []
	var pending := {}
	for dd: Dictionary in d.get("dens", []):
		var name := String(dd.get("name", ""))
		var now: Dictionary = st.dens.get(name, dd)
		pending[name] = int(now.get("pending", 0))
		var copy := now.duplicate(true)
		copy.erase("pending")
		dens.append(copy)
	d["dens"] = dens
	GameSnapshot.apply_systems([[w, d]])
	if w.sys:
		for den in w.sys.dens:
			if not is_instance_valid(den) or den.def == null:
				continue
			var n := mini(int(pending.get(den.def.name, 0)), den.def.spawn_cap - den.spawns.size())
			if n > 0:
				den.spawn_pack(n, false, true)
			var sd: Dictionary = st.dens.get(den.def.name, {})
			sd.erase("pending")
	var r := Corps.rival(w.corp_id)
	if r and w.is_hq:
		r.research.data_lab = false
	Corps.act_as(w.corp_id, func() -> void: _settle(w, d.get("data", {})))
	var rw := RivalWorlds.of(w.get_tree())
	if rw:
		rw.came_back += 1


## What the data sim did, made real in [param w].
static func _settle(w: SystemWorld, data: Dictionary) -> void:
	var mgr := w.buildings
	if mgr == null:
		return
	var eco := Corps.economy_of_corp(w.corp_id)
	var made := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("rival_data:%s:%d" % [w.system_id, int(SimClock.time)])
	for i in (data.get("builds", []) as Array).size():
		var pb: Dictionary = data["builds"][i]
		var def := mgr.def_by_id(StringName(pb["def"]))
		if def == null:
			continue
		var b: Building = null
		if def.station_addon:
			b = mgr.spawn_finished(def, Vector3.ZERO)
		else:
			# Paid while data: placed without the cost check.
			var spot := RivalManager.find_spot(mgr, def, rng.randf_range(0.0, TAU), false)
			if spot != Vector3.INF:
				b = mgr.spawn_finished(def, spot)
		if b == null:
			# No room or bay after all: the cost comes back.
			eco.add(def.cost_credits, def.cost_ore(), Ledger.BUILDINGS, "%s not built (no room)" % def.display_name)
			continue
		var left := float(pb.get("done", 0.0)) - SimClock.time
		if left > 0.0:
			b.set_construction_progress(1.0 - left / maxf(def.build_time, 0.001))
		made["p%d" % i] = b
	var by_id := {}
	for b in mgr.buildings:
		if is_instance_valid(b):
			by_id["%d" % SaveIds.of(b)] = b
	for h: Dictionary in data.get("hires", []):
		var key := String(h.get("b", ""))
		var bld := (made.get(key) if made.has(key) else by_id.get(key)) as Building
		var def := def_of(StringName(h.get("def", "")))
		var cost := def.hire_cost_credits if def else 0
		eco.add(cost, PackedInt32Array(), Ledger.HIRES, "Hire paid while away")
		if bld and bld.is_active() and bld.captains.size() < bld.def.max_hires:
			bld.hire()
	if w.sys:
		for m: Dictionary in data.get("mining", []):
			var belt := w.sys.find_cluster(String(m.get("belt", "")))
			if belt == null or belt.is_depleted or not belt.has_ore_for_new_trip():
				continue
			var taken := false
			for c in ContractBoard.contracts:
				var mc := c as MiningContract
				if mc and mc.corp == w.corp_id and not mc.is_finished() and mc.belt == belt:
					taken = true
			if not taken:
				ContractBoard.post_mining(belt, int(m.get("pay", 40)))


# --- Reading the data world ---------------------------------------------------------

## Save ids of the station buildings of system [param st] (the live world
## [param w] when there is one, else its data), as keys.
static func building_ids(w: SystemWorld, st: RemoteSystemState) -> Dictionary:
	var out := {}
	if w and w.buildings:
		for b in w.buildings.buildings:
			if is_instance_valid(b):
				out[SaveIds.of(b)] = true
	elif st and not st.world.is_empty():
		for bd: Dictionary in _buildings(st.world):
			out[int(bd.get("id", 0))] = true
	return out


static func _buildings(d: Dictionary) -> Array:
	return (d.get("buildings", {}) as Dictionary).get("buildings", [])


## Buildings of [param def_id] in the data world [param d]: saved and
## built by the data sim, under construction included; [param active] only
## the finished ones.
static func count(d: Dictionary, def_id: StringName, active: bool = false) -> int:
	var n := 0
	for bd: Dictionary in _buildings(d):
		if StringName(bd.get("def", "")) == def_id and (not active or bool(bd.get("active", true))):
			n += 1
	for pb: Dictionary in (d.get("data", {}) as Dictionary).get("builds", []):
		if StringName(pb["def"]) == def_id and (not active or SimClock.time >= float(pb.get("done", 0.0))):
			n += 1
	return n


## Captains by building key ("<save id>" or "p<i>" for one the data sim
## built) for the buildings of [param def_id] that are finished: {key: count}.
static func berths(d: Dictionary, def_id: StringName) -> Dictionary:
	var out := {}
	for bd: Dictionary in _buildings(d):
		if StringName(bd.get("def", "")) == def_id and bool(bd.get("active", true)):
			out["%d" % int(bd.get("id", 0))] = (bd.get("captains", []) as Array).size()
	var data: Dictionary = d.get("data", {})
	var builds: Array = data.get("builds", [])
	for i in builds.size():
		var pb: Dictionary = builds[i]
		if StringName(pb["def"]) == def_id and SimClock.time >= float(pb.get("done", 0.0)):
			out["p%d" % i] = 0
	for h: Dictionary in data.get("hires", []):
		var key := String(h.get("b", ""))
		if out.has(key):
			out[key] = int(out[key]) + 1
	return out


## Captains at the buildings of [param def_id] (finished ones).
static func captains_of(d: Dictionary, def_id: StringName) -> int:
	var n := 0
	var b := berths(d, def_id)
	for k: String in b:
		n += int(b[k])
	return n


## Captains by role in the data world of [param st] (tests, reports).
static func roles(st: RemoteSystemState) -> Dictionary:
	var out := {}
	if st == null or st.world.is_empty():
		return out
	for id: StringName in [&"mining_outpost", &"mercenary_outpost", &"explorer_outpost"]:
		var def := def_of(id)
		var n := captains_of(st.world, id)
		if def and n > 0:
			out[def.hire_role] = int(out.get(def.hire_role, 0)) + n
	return out


## "def/on|building/captains" per building of the data world of [param
## st], sorted (tests: the same list as a live world's, see the smoke test).
static func shape(st: RemoteSystemState) -> PackedStringArray:
	var out: PackedStringArray = []
	if st == null or st.world.is_empty():
		return out
	var d := st.world
	var data: Dictionary = d.get("data", {})
	var hired := {}
	for h: Dictionary in data.get("hires", []):
		hired[String(h.get("b", ""))] = int(hired.get(String(h.get("b", "")), 0)) + 1
	for bd: Dictionary in _buildings(d):
		out.append("%s/%s/%d" % [bd.get("def", ""), "on" if bool(bd.get("active", true)) else "building",
				(bd.get("captains", []) as Array).size() + int(hired.get("%d" % int(bd.get("id", 0)), 0))])
	var builds: Array = data.get("builds", [])
	for i in builds.size():
		var pb: Dictionary = builds[i]
		out.append("%s/%s/%d" % [pb["def"], "on" if SimClock.time >= float(pb.get("done", 0.0)) else "building", int(hired.get("p%d" % i, 0))])
	out.sort()
	return out


## Buildings by display name in the data world of [param st] (tests, reports).
static func builds(st: RemoteSystemState) -> Dictionary:
	var out := {}
	if st == null or st.world.is_empty():
		return out
	var seen := {}
	for bd: Dictionary in _buildings(st.world):
		seen[StringName(bd.get("def", ""))] = true
	for pb: Dictionary in (st.world.get("data", {}) as Dictionary).get("builds", []):
		seen[StringName(pb["def"])] = true
	for id: StringName in seen:
		var def := def_of(id)
		out[def.display_name if def else String(id)] = count(st.world, id)
	return out


## Fighting strength of the data world of [param st] for RivalCorp.strength:
## the station, its mercenaries (power measured when it went data, new ones
## at the average), finished turrets and the shield.
static func strength(st: RemoteSystemState) -> float:
	if st == null or st.world.is_empty():
		return 0.0
	var d := st.world
	var data: Dictionary = d.get("data", {})
	var n0 := int(data.get("merc_n", 0))
	var avg := float(data.get("merc_power", 0.0)) / n0 if n0 > 0 else MERC_POWER
	var mercs := captains_of(d, &"mercenary_outpost")
	var p := 1.5 + float(data.get("merc_power", 0.0)) + maxi(mercs - n0, 0) * avg
	p += 0.6 * count(d, &"defense_turret", true)
	p += 1.0 * mini(count(d, &"shield_generator", true), 1)
	return p


## The data world of [param st] has an Explorer Outpost with an explorer.
static func has_explorer(st: RemoteSystemState) -> bool:
	return st != null and not st.world.is_empty() and captains_of(st.world, &"explorer_outpost") > 0


## The data world of [param st] has a finished Science Lab.
static func has_lab(st: RemoteSystemState) -> bool:
	return st != null and not st.world.is_empty() and count(st.world, &"science_lab", true) > 0


# --- The data step ----------------------------------------------------------------------

## [param dt] sim seconds of rival station system [param id] as data.
static func step(tree: SceneTree, id: StringName, st: RemoteSystemState, dt: float) -> void:
	var corp := RivalWorlds.site_corp(id)
	var r := Corps.rival(corp)
	if r == null or r.mind.eliminated or st.world.is_empty():
		return
	Corps.act_as(corp, func() -> void: _step(tree, id, st, r, dt))


static func _step(tree: SceneTree, id: StringName, st: RemoteSystemState, r: Corp, dt: float) -> void:
	var d := st.world
	var data: Dictionary = d["data"]
	var hq := bool(st.station.get("hq", false))
	var eco := r.economy
	var acc: Dictionary = data.get("acc", {})
	data["acc"] = acc
	var rw := RivalWorlds.of(tree)
	_mine(d, data, eco, acc, dt, rw.data_loads if rw else {})
	_survey(id, d, acc)
	if hq:
		_sell(eco, acc, dt)
		if has_lab(st):
			r.research.data_lab = true
			r.research.sim_step(dt)
	var crew := captains_of(d, &"mining_outpost") + captains_of(d, &"mercenary_outpost") + captains_of(d, &"explorer_outpost")
	_trickle(eco, acc, "repairs", -crew * REPAIRS_PER_MIN * dt / 60.0, Ledger.REPAIRS, "Ship repairs")
	if not hq and SimClock.time - float(st.station.get("founded_at", 0.0)) > 120.0:
		_trickle(eco, acc, "upkeep", -40.0 * dt / 60.0, Ledger.UPKEEP, "Station upkeep")
	var plan := RivalPlan.new(tree, id, st, r)
	plan.run()


## Adds [param amount] (fractions carried in [param acc] under [param key])
## as income ([param amount] > 0) or a cost.
static func _trickle(eco: CorpEconomy, acc: Dictionary, key: String, amount: float, cat: String, label: String) -> void:
	var v := float(acc.get(key, 0.0)) + amount
	var whole := int(v)
	acc[key] = v - whole
	if whole > 0:
		eco.add_income(whole, cat, label)
	elif whole < 0:
		if not eco.spend(-whole, PackedInt32Array(), cat, label):
			acc[key] = 0.0


## The miners' loads since the last step (see the class notes).
static func _mine(d: Dictionary, data: Dictionary, eco: CorpEconomy, acc: Dictionary, dt: float, stats: Dictionary) -> void:
	var miners := captains_of(d, &"mining_outpost")
	var jobs := mining_jobs(d)
	if miners <= 0 or jobs.is_empty():
		return
	var loads := float(acc.get("loads", 0.0)) + miners * LOADS_PER_MIN * dt / 60.0
	var n := int(loads)
	acc["loads"] = loads - n
	var rules := ContractBoard.mining_rules
	var i := int(acc.get("job", 0))
	for k in n:
		if jobs.is_empty():
			break
		i = i % jobs.size()
		var job: Dictionary = jobs[i]
		var cd := cluster(d, String(job["belt"]))
		if cd.is_empty() or int(cd.get("left", 0)) <= 0:
			jobs.remove_at(i)
			continue
		var pay := int(job["pay"])
		if not eco.spend(pay, PackedInt32Array(), Ledger.CONTRACT_PAY, "Mining loads"):
			break
		cd["left"] = int(cd["left"]) - 1
		_trickle(eco, acc, "fees", pay * FEE_SHARE, Ledger.FEES, "Station fees")
		var belt_ore := int(cd.get("ore", AsteroidBelt.OreType.IRON))
		var ore := Economy.zero_ore()
		var units := roundi(rules.materials_for(belt_ore) * UNITS_FACTOR)
		ore[Economy.ore_of_belt(belt_ore)] = units
		eco.receive_cargo(ore, "Miners (as data)")
		var ls: Dictionary = stats.get_or_add(Corps.acting, {"loads": 0, "units": 0, "pay": 0})
		ls["loads"] += 1
		ls["units"] += units
		ls["pay"] += pay
		i += 1
	acc["job"] = i
	data["acc"] = acc


## ClusterSpawner as data: see the class notes.
static func _survey(id: StringName, d: Dictionary, acc: Dictionary) -> void:
	var sdef := Sector.system_def(id)
	if sdef == null:
		return
	var list: Array = (d.get("clusters", {}) as Dictionary).get("list", [])
	var active := 0
	var empty: Dictionary = {}
	for cd: Dictionary in list:
		if int(cd.get("left", 0)) > 0:
			active += 1
		elif empty.is_empty() or int(cd.get("total", 0)) > int(empty.get("total", 0)):
			empty = cd
	if active >= sdef.cluster_min or empty.is_empty():
		acc.erase("survey_at")
		return
	if not acc.has("survey_at"):
		acc["survey_at"] = SimClock.time + (sdef.cluster_respawn.x + maxf(sdef.cluster_respawn.x, sdef.cluster_respawn.y)) * 0.5
		return
	if SimClock.time >= float(acc["survey_at"]):
		acc.erase("survey_at")
		empty["left"] = maxi(int(empty.get("total", 30)), 1)
		empty["gone"] = []


## Open mining work in the data world [param d]: the saved contracts of
## its corp and the ones the data sim posted, [{belt, pay}].
static func mining_jobs(d: Dictionary) -> Array:
	var out := []
	for c: Dictionary in (d.get("contracts", {}) as Dictionary).get("contracts", []):
		if int(c.get("type", -1)) != Contract.Type.MINING or int(c.get("status", 0)) >= Contract.Status.COMPLETED:
			continue
		if String(c.get("belt", "")).is_empty() or bool((c.get("mining", {}) as Dictionary).get("depleted", false)):
			continue
		out.append({"belt": String(c["belt"]), "pay": int(c.get("reward", 40))})
	for m: Dictionary in (d.get("data", {}) as Dictionary).get("mining", []):
		out.append(m)
	return out


## The saved cluster [param name] of the data world [param d] ({} when gone).
static func cluster(d: Dictionary, name: String) -> Dictionary:
	for bd: Dictionary in (d.get("clusters", {}) as Dictionary).get("list", []):
		if String(bd.get("name", "")) == name:
			return bd
	return {}


## Ore over the keep sells to the Factory (see the class notes).
static func _sell(eco: CorpEconomy, acc: Dictionary, dt: float) -> void:
	for i in SELL_PRICE.size():
		var surplus := eco.ore[i] - RivalManager.KEEP[i]
		var key := "sell%d" % i
		if surplus <= 0:
			acc[key] = 0.0
			continue
		var v := float(acc.get(key, 0.0)) + SELL_PER_MIN[i] * dt / 60.0
		var n := mini(int(v), surplus)
		acc[key] = v - int(v)
		if n <= 0:
			continue
		var cost := Economy.zero_ore()
		cost[i] = n
		eco.spend(0, cost)
		eco.add_income(roundi(n * SELL_PRICE[i]), Ledger.FACTORY, "Ore sold to the Factory")

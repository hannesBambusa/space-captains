class_name GameSnapshot
extends RefCounted
## The whole game as one Dictionary ([method capture]) and back
## ([method apply_globals] before the system scene is built, then
## [method apply_scene] on the fresh scene, before its first sim step).
##
## Saved: the sim clock, economy, event log, every captain (all fields,
## traits, rank, wallet, career stats, decision log), every building
## (placement, construction, berths, its service: Factory market, stock,
## tooling, warehouse, orders, misses and log; Outfitter sales; Salvage
## Yard funds, debts, scrap, ore and auto-buy; cargo depot stock; defense
## structure hull and the shield bubble), every ship (see [ShipCodec]),
## contracts ([ContractCodec]), mercenary fleets, dens (hull, spawns,
## stash, ruins), scrap fields, the raid director (with an announced raid),
## the threat director (base arrivals, threat clock, a pending warning),
## defence zones (radius, kill bounty, budget, stats), structure and station
## hulls, raid objectives, the asteroid clusters (their defs: orbit, shape,
## ore, seed, name; the loads left; the spawner's due surveys and name
## pointer), the camera and the random number generators that pick
## captains, rare parts and career skills. Orbits follow from the clock;
## cluster rocks regenerate from their seeds. Not saved: shots in flight
## and effects, the selection.

## 2: the outer system (moved belts, planets and gates), factions (raider
## faction id and pack lead per ship, faction tag per event line).
## 3: threat escalation (arrived bases, threat clock, pending arrival).
## Phase B (defence zones, structure hulls, announced raids) added keys
## only; older v3 saves load with no zones and full hulls, so no bump.
## Phase C1 (research: done techs, funded projects with their reserve,
## researchers, applicants) added the "research" key only. A v3 save without
## it keeps what it could use before (Research.grant_legacy), so no bump.
## Phase C2 (planet raids: the "planets" raid records, planet raid
## contracts, landers, the planet goods in every ore array) added keys and
## longer arrays only; older saves pad their ore arrays, so no bump.
## Phase C3 (planet claims: garrisons saved with the dens plus the "claims"
## key, claim group ships, guard links) added keys only; older saves load
## with no claims until the ThreatDirector makes them, so no bump.
## Asteroid clusters (the "clusters" key) replaced the belts without a bump:
## a save without it keeps the starting clusters full, and its contracts'
## belt names map onto them ("Cinder Belt" -> "Cinder Cluster").
const VERSION := 3


static func capture(tree: SceneTree) -> Dictionary:
	var sys := SolarSystem.of(tree)
	var mgr := BuildingManager.of(tree)
	var world := CombatWorld.of(tree)
	var paused := -1
	var pm := tree.root.get_node_or_null(^"PauseMenu")
	if pm and pm.has_method(&"real_paused") and bool(pm.call(&"is_open")):
		paused = 1 if bool(pm.call(&"real_paused")) else 0
	var d := {"version": VERSION, "sim": SimClock.save_state(paused), "economy": Economy.save_state(), "events": EventLog.save_state(),
			"rng": {"salvage": SaveUtil.rng_state(SalvageContract.rng), "career": SaveUtil.rng_state(Career.rng)}}
	d["captains"] = _save_captains(tree, mgr)
	d["buildings"] = mgr.save_state() if mgr else {}
	var dens := []
	if sys:
		d["clusters"] = _save_clusters(sys)
		for den in sys.dens:
			if is_instance_valid(den):
				dens.append(den.save_state())
	d["dens"] = dens
	var scrap := []
	if world:
		for f in world.get_scrap_fields():
			scrap.append(f.save_state())
	d["scrap"] = scrap
	var trip_contracts: Array[Contract] = []
	d["ships"] = ShipCodec.save_all(tree, trip_contracts)
	d["contracts"] = ContractCodec.save_all(trip_contracts)
	d["fleets"] = _save_fleets(tree)
	d["raids"] = world.raids.save_state() if world and world.raids else {}
	d["threats"] = world.threats.save_state() if world and world.threats else {}
	d["claims"] = world.claims.save_state() if world and world.claims else {}
	d["zones"] = world.zones.save_state() if world and world.zones else {}
	d["research"] = Research.save_state()
	d["planets"] = PlanetRaidContract.save_records()
	d["camera"] = _save_camera(tree)
	d["ids_next"] = SaveIds.next
	return d


static func _save_clusters(sys: SolarSystem) -> Dictionary:
	var list := []
	for b in sys.belts:
		var bd := b.def.to_dict()
		bd["left"] = b.loads_left
		bd["total"] = b.reserve
		list.append(bd)
	return {"list": list, "spawner": sys.cluster_spawner.save_state() if sys.cluster_spawner else {}}


## Swaps the starting clusters for the saved ones.
static func _restore_clusters(sys: SolarSystem, cd: Dictionary) -> void:
	for b in sys.belts.duplicate():
		sys.remove_cluster(b)
	for bd: Dictionary in cd.get("list", []):
		if int(bd.get("left", 1)) <= 0:
			# Was fading out: gone (its contracts end with their trips).
			continue
		var b := sys.add_cluster(ClusterDef.from_dict(bd))
		b.set_loads_left(int(bd.get("left", b.reserve)), int(bd.get("total", b.reserve)))
	if sys.cluster_spawner:
		sys.cluster_spawner.load_state(cd.get("spawner", {}))


## Short facts for the load list.
static func summary(tree: SceneTree) -> Dictionary:
	var mgr := BuildingManager.of(tree)
	var n := 0
	if mgr:
		for b in mgr.buildings:
			if is_instance_valid(b):
				for c in b.captains:
					if c and c.alive:
						n += 1
	return {"sim_time": SimClock.time, "credits": Economy.credits, "captains": n}


static func _save_captains(tree: SceneTree, mgr: BuildingManager) -> Array:
	var all: Array[Captain] = []
	var add := func(c: Captain) -> void:
		if c and not all.has(c):
			all.append(c)
	if mgr:
		for b in mgr.buildings:
			if not is_instance_valid(b):
				continue
			for c in b.captains:
				add.call(c)
			for c in b.waiting:
				add.call(c)
			var f := b.get_service() as Factory
			if f:
				for o in f.backorders:
					add.call(o["captain"])
			var y := b.get_service() as SalvageYard
			if y:
				for o in y.owed:
					add.call(o["captain"])
	for n in tree.get_nodes_in_group(Ship.GROUP):
		var s := n as Ship
		if s and not s.dead:
			add.call(s.captain)
	var out := []
	for c in all:
		out.append(c.save_state())
	return out


static func _save_fleets(tree: SceneTree) -> Array:
	var fleets: Array[MercFleet] = []
	for n in tree.get_nodes_in_group(Ship.GROUP):
		var s := n as Ship
		var mb := s.brain as MercenaryBrain if s else null
		if mb and mb.fleet and not fleets.has(mb.fleet) and mb.fleet.state != MercFleet.State.DONE:
			fleets.append(mb.fleet)
	var out := []
	for f in fleets:
		out.append(ShipCodec.save_fleet(f))
	return out


static func _save_camera(tree: SceneTree) -> Dictionary:
	var cam := RTSCamera.of(tree)
	if cam == null:
		return {}
	var follow := cam.get_follow_target()
	return {"follow_home": follow != null and follow == cam.home_target, "pos": cam.get("_target_pos"), "dist": cam.get("_target_dist"),
			"yaw": rad_to_deg(float(cam.get("_target_yaw")))}


# --- Apply ----------------------------------------------------------------------

## Autoload state, before the system scene is built (orbits and timers read
## the clock while it builds). Clears the contract board.
static func apply_globals(d: Dictionary) -> void:
	SaveIds.reset(int(d.get("ids_next", 1)))
	ContractBoard.reset()
	SimClock.load_state(d.get("sim", {}))
	Economy.load_state(d.get("economy", {}))
	EventLog.load_state(d.get("events", []))
	Research.load_state(d.get("research", {}))
	PlanetRaidContract.load_records(d.get("planets", {}))
	var rng: Dictionary = d.get("rng", {})
	SaveUtil.set_rng(SalvageContract.rng, rng.get("salvage", {}))
	SaveUtil.set_rng(Career.rng, rng.get("career", {}))


## Everything in the scene. The scene is in the tree and built; nothing has
## stepped yet.
static func apply_scene(tree: SceneTree, d: Dictionary) -> void:
	var refs := SaveRefs.new()
	var sys := SolarSystem.of(tree)
	var mgr := BuildingManager.of(tree)
	var world := CombatWorld.of(tree)
	for cd: Dictionary in d.get("captains", []):
		refs.add(int(cd["id"]), Captain.from_save(cd))
	if mgr:
		mgr.load_state(d.get("buildings", {}), refs)
	if world and world.zones:
		world.zones.load_state(d.get("zones", {}))
	var belts := {}
	var den_data := {}
	if world and world.threats:
		# Builds the dens that had arrived, before their state is matched below.
		world.threats.load_state(d.get("threats", {}))
	if world and world.claims:
		# Garrisons are dens too: built before the den states are matched.
		world.claims.load_state(d.get("claims", {}))
	if sys:
		if d.has("clusters"):
			_restore_clusters(sys, d["clusters"])
		for b in sys.belts:
			belts[b.def.name] = b
		# Old saves: their belts are the starting clusters now.
		for bdef in sys.system_def.belts:
			var b := sys.find_cluster(bdef.name)
			if b:
				belts[bdef.name.replace(" Cluster", " Belt")] = b
		for dd: Dictionary in d.get("dens", []):
			for den in sys.dens:
				if den.def and den.def.name == String(dd.get("name", "")):
					den.load_state(dd)
					refs.add(int(dd["id"]), den)
					den_data[den] = dd
		for den in sys.dens:
			# Dens the save does not know (a newer system) start fresh.
			if not den_data.has(den):
				den.skip_initial_spawns = false
	if world:
		for fd: Dictionary in d.get("scrap", []):
			refs.add(int(fd["id"]), ScrapField.restore(world, fd))
	var ships := []
	for sd: Dictionary in d.get("ships", []):
		var s := ShipCodec.create(tree, sd, refs)
		if s:
			ships.append([s, sd])
	if mgr:
		for bd: Dictionary in (d.get("buildings", {}) as Dictionary).get("buildings", []):
			var b := refs.building(int(bd["id"]))
			if b:
				b.load_services(bd, refs)
	for den: ScavengerDen in den_data:
		den.restore_ships(den_data[den], refs)
	ContractCodec.restore_all(d.get("contracts", {}), refs, belts)
	for pair in ships:
		ShipCodec.finish(pair[0] as Ship, pair[1] as Dictionary, refs)
	for fd: Dictionary in d.get("fleets", []):
		ShipCodec.restore_fleet(fd, refs)
	if world and world.claims:
		world.claims.restore_links(refs)
	if world and world.raids:
		world.raids.load_state(d.get("raids", {}), refs)
	if Research.legacy_pending:
		Research.grant_legacy(tree)
	_restore_camera.call_deferred(tree, d.get("camera", {}))


## Deferred: after the system has set the camera up (it defers that too).
static func _restore_camera(tree: SceneTree, c: Dictionary) -> void:
	var cam := RTSCamera.of(tree)
	if cam == null or c.is_empty():
		return
	cam.set_yaw(float(c.get("yaw", cam.default_yaw_deg)), true)
	if bool(c.get("follow_home", false)) and is_instance_valid(cam.home_target):
		cam.focus_on(cam.home_target, float(c.get("dist", cam.default_distance)), true)
	else:
		var p := c.get("pos", Vector3.ZERO) as Vector3
		cam.set_view(p.x, p.z, float(c.get("dist", cam.default_distance)), float(c.get("yaw", 0.0)))

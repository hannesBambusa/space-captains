class_name SystemHost
extends SystemView
## One live remote system: its own container (a [SystemView]), SubViewport
## (own World3D) and scenes/system.tscn built from the generated SystemDef,
## without Buildings and ContractMarkers unless the system has a forward
## station (SystemWorld.has_station; its BuildingManager gets no Factory).
## Without one CombatWorld leaves out the raid and threat directors, zones
## and the alarm, ClusterSpawner does not respawn and FogOfWar hides what
## explorers have not revealed. A forward station system gets its
## [StationSupply] (upkeep, water, hauling fee). Made and dropped by the
## [ViewManager].
##
## [method materialise] builds the world and applies the system's
## [RemoteSystemState] (Sector): dens by name (hull, counters, the ships
## the abstract sim "launched" meanwhile: "pending"), cluster loads left
## by name, scrap fields, every ship stored there (ShipCodec dicts: the
## dens' scavengers and the player's ships, their [GateTransit] included).
## Hired ships keep their captain, home building and contract objects: the
## refs are filled from the live game by save id ([method known_refs]).
## [method capture_into_state] writes the live system back into the state
## (also before a save while it is live); [method dematerialise] does that
## and frees the world (hired ships let go of their berth and captain
## links the way a gate jump does). First visit: no state yet, the dens
## launch their starting ships as in a new game.

const SYSTEM_SCENE := "res://scenes/system.tscn"

var system_id: StringName
var world: SystemWorld
var viewport: SubViewport


## Builds [param id] live. Null when the network has no such system.
func materialise(id: StringName) -> SystemWorld:
	var def := Sector.system_def(id)
	if def == null:
		return null
	system_id = id
	viewport = SubViewport.new()
	viewport.name = "Host"
	viewport.own_world_3d = true
	viewport.handle_input_locally = true
	viewport.audio_listener_enable_3d = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	match_quality(viewport)
	_fit()
	var w := (load(SYSTEM_SCENE) as PackedScene).instantiate() as SystemWorld
	w.system_id = id
	(w.get_node(^"SolarSystem") as SolarSystem).system_def = def
	if w.has_station:
		var mgr := w.get_node_or_null(^"Buildings") as BuildingManager
		if mgr:
			mgr.factory_def = null
			mgr.forward = true
	else:
		for n: NodePath in [^"Buildings", ^"ContractMarkers"]:
			var x := w.get_node_or_null(n)
			if x:
				w.remove_child(x)
				x.free()
	# The environment (sky seed) is a sub-resource shared by every instance.
	var env := w.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if env and env.environment:
		env.environment = env.environment.duplicate(true) as Environment
	viewport.add_child(w)
	world = w
	apply_state(Sector.state(id))
	# A forward station's upkeep, water and hauling fee (F4).
	if w.has_station:
		var supply := StationSupply.new()
		supply.name = "StationSupply"
		w.add_child(supply)
	# Only what explorers revealed shows (P3); a station system shows all.
	if not w.has_station:
		var fog := FogOfWar.new()
		fog.name = "FogOfWar"
		w.add_child(fog)
	_refresh_contract_targets()
	return w


## Puts [param st] into the freshly built world.
func apply_state(st: RemoteSystemState) -> void:
	if st == null or world == null:
		return
	var sys := world.sys
	var refs := known_refs(get_tree())
	if sys:
		for b in sys.belts:
			var cd: Dictionary = st.clusters.get(b.def.name, {})
			if not cd.is_empty():
				b.set_loads_left(int(cd.get("left", b.reserve)), int(cd.get("total", b.reserve)))
	var den_data := {}
	if sys:
		for den in sys.dens:
			var dd: Dictionary = st.dens.get(den.def.name, {})
			if dd.is_empty():
				continue
			den.load_state(dd)
			refs.add(int(dd.get("id", 0)), den)
			den_data[den] = dd
	if world.combat:
		for fd: Dictionary in st.scrap:
			refs.add(int(fd.get("id", 0)), ScrapField.restore(world.combat, fd))
	var made := []
	for sd: Dictionary in st.ships:
		var s := ShipCodec.create(world, sd, refs)
		if s:
			made.append([s, sd])
	for den: ScavengerDen in den_data:
		den.restore_ships(den_data[den], refs)
	for pair in made:
		ShipCodec.finish(pair[0] as Ship, pair[1] as Dictionary, refs)
	for den: ScavengerDen in den_data:
		# Never past the cap (older saves could hold more pending than room).
		var pending := mini(int((den_data[den] as Dictionary).get("pending", 0)), den.def.spawn_cap - den.spawns.size())
		if pending > 0:
			den.spawn_pack(pending, false, true)
	# Live now: the data copy is stale until the next capture.
	st.ships.clear()
	st.scrap.clear()


## The live system into its state (it stays live).
func capture_into_state() -> void:
	var st := Sector.state(system_id)
	if st == null or world == null:
		return
	var sys := world.sys
	if sys:
		st.clusters.clear()
		for b in sys.belts:
			st.clusters[b.def.name] = {"left": b.loads_left, "total": b.reserve}
		for den in sys.dens:
			if is_instance_valid(den) and den.def:
				st.dens[den.def.name] = den.save_state()
	st.scrap.clear()
	if world.combat:
		for f in world.combat.get_scrap_fields():
			st.scrap.append(f.save_state())
	var contracts: Array[Contract] = []
	st.ships = ShipCodec.save_all(world, contracts)


## Writes the state, then frees the world. Hired ships let go of their
## berth list and captain (the state holds them now).
func dematerialise() -> void:
	if world == null:
		return
	capture_into_state()
	for n in SystemWorld.nodes_in(world, Ship.GROUP):
		var s := n as Ship
		if s:
			GateTransit.detach(s)
	for c in ContractBoard.contracts:
		var ec := c as ExploreContract
		if ec and ec.from_system == system_id:
			ec.target = null
	if viewport:
		viewport.queue_free()
	world = null
	viewport = null


## Explore contracts point at their gate while it is live (markers, panels).
static func _refresh_contract_targets() -> void:
	for c in ContractBoard.contracts:
		if c is ExploreContract:
			(c as ExploreContract).refresh_target()


## Objects a stored ship may link to, by save id: the buildings of every
## station system (home and the forward stations), every hired captain
## (berths and waiting lists), the contracts on the board and the ones it
## holds for ships far away (ContractBoard.held).
static func known_refs(tree: SceneTree) -> SaveRefs:
	var refs := SaveRefs.new()
	for w in SystemWorld.all(tree):
		var mgr := w.buildings if w.has_station else null
		if mgr == null:
			continue
		for b in mgr.buildings:
			if not is_instance_valid(b):
				continue
			refs.add(SaveIds.of(b), b)
			for c in b.captains:
				refs.add(SaveIds.of(c), c)
			for c in b.waiting:
				refs.add(SaveIds.of(c), c)
	for c in ContractBoard.contracts:
		refs.add(SaveIds.of(c), c)
	for c in ContractBoard.held:
		refs.add(SaveIds.of(c), c)
	return refs

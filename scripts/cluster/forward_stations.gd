class_name ForwardStations
extends Node
## The player's forward stations: remote systems with a station site
## (RemoteSystemState.station, SystemWorld.has_station). Child of the
## [ViewManager] (made in its _enter_tree). Each one is pinned
## (ViewManager.pin): live for good, hidden while not viewed, simulating
## at full rate. A new game has none; on a load the saved sites are pinned
## and built right after the home system is restored (deferred).
##
## [method found] puts a station into a system (sets the site with
## founded_at = SimClock.time, pins, builds it, posts the event).
## [method debug_found] picks a site on a planet for tests.
## Upkeep, water and the hauling fee: StationSupply (forward plan F4).
##
## Founding in play (F6): the Forward Station structure is built at home
## (BuildingDef [constant BUILD_ID], ForwardStationYard), becomes a
## [MobileStation] when finished and flies with its escorts to a planet in
## another system ([method target_problem], [method site_problem]), then
## calls [method found]. [method free_slots]: what is left of
## [constant MAX_STATIONS] after the stations, the mobile ones and the
## ones under construction.

## A station was founded in [param system_id] ([param world]: its live world).
signal founded(system_id: StringName, world: SystemWorld)

const GROUP := "forward_stations"
## At most this many forward stations, one per system.
const MAX_STATIONS := 2
## Station orbit around its planet: planet radius plus this, metres.
const ORBIT_GAP := 1000.0
## Clear of a moon's orbit by at least this, metres.
const MOON_CLEARANCE := 600.0
const ORBIT_PERIOD := 330.0
## The Forward Station structure (data/buildings/forward_station.tres).
const BUILD_ID := &"forward_station"
## A destination system may have at most this danger.
const MAX_DANGER := 4
## A site planet must be this far from every hostile base, metres.
const MIN_BASE_DISTANCE := 6000.0
## site_on pushes the orbit past the moons; past this much over the
## planet's radius there is no clear orbit, metres.
const MAX_ORBIT_GAP := 4000.0


static func of(tree: SceneTree) -> ForwardStations:
	return tree.get_first_node_in_group(GROUP) as ForwardStations if tree else null


func _ready() -> void:
	add_to_group(GROUP)
	# After the scene's own load (GameSnapshot.apply_scene runs right after
	# the game scene entered): home's buildings and captains exist then.
	_pin_saved.call_deferred()


## Ids of the systems with a forward station, network order.
func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	if Sector.network == null:
		return out
	for id in Sector.network.remote_ids():
		var st := Sector.state(id)
		if st and not st.station.is_empty():
			out.append(id)
	return out


func count() -> int:
	return ids().size()


## The live world of station system [param id], or null.
func world(id: StringName) -> SystemWorld:
	var vm := get_parent() as ViewManager
	return vm.world(id) if vm else null


## Why a station cannot go to [param site] in [param system_id] now, or "".
func found_problem(system_id: StringName, site: Dictionary) -> String:
	if system_id == ClusterNetwork.HOME_ID:
		return "Home has its station"
	var def := Sector.system_def(system_id)
	var st := Sector.state(system_id)
	if def == null or st == null:
		return "No such system"
	if not st.station.is_empty():
		return "%s already has a station" % def.system_name
	if count() >= MAX_STATIONS:
		return "At most %d forward stations" % MAX_STATIONS
	if _planet_def(def, String(site.get("planet", ""))) == null:
		return "No planet %s in %s" % [site.get("planet", "?"), def.system_name]
	return ""


## Founds a station in [param system_id] at [param site] ({planet,
## orbit_radius, period, angle (deg), name}; founded_at is set here).
## A system live without a station is rebuilt with it (the view stays).
## Returns the live world, or null (pushes a warning with the reason).
func found(system_id: StringName, site: Dictionary) -> SystemWorld:
	var why := found_problem(system_id, site)
	if not why.is_empty():
		push_warning("ForwardStations: %s" % why)
		return null
	var vm := get_parent() as ViewManager
	var planet := String(site.get("planet", ""))
	var s := site.duplicate(true)
	s["founded_at"] = SimClock.time
	if not s.has("name"):
		s["name"] = "%s Station" % planet
	var was_viewed := vm.viewed_id() == system_id
	# Built without a station: drop it first (into its state), rebuild below.
	if vm.is_live(system_id):
		vm.dematerialise(system_id)
	Sector.state(system_id).station = s
	var w := vm.pin(system_id)
	if w and was_viewed:
		vm.view_now(system_id)
	var sys_name := Sector.system_def(system_id).system_name
	# Tagged "[<system>]" by the feed (the station is in that system).
	EventLog.post("Forward station founded at %s" % planet if w and w.sys else "Forward station founded at %s in %s" % [planet, sys_name], EventLog.Kind.INFO,
			w.sys.home_station if w and w.sys else null)
	founded.emit(system_id, w)
	return w


## A site on [param planet_name] in [param system_id] (empty: the planet
## nearest a cluster orbit), {} when there is no such planet.
static func site_on(system_id: StringName, planet_name: String = "") -> Dictionary:
	var def := Sector.system_def(system_id)
	if def == null or def.planets.is_empty():
		return {}
	var p := _planet_def(def, planet_name) if not planet_name.is_empty() else _planet_near_clusters(def)
	if p == null:
		return {}
	var r := p.radius + ORBIT_GAP
	for m: PlanetDef in p.moons:
		if absf(m.orbit_radius - r) < m.radius + MOON_CLEARANCE:
			r = m.orbit_radius + m.radius + MOON_CLEARANCE
	return {"planet": p.name, "orbit_radius": r, "period": ORBIT_PERIOD, "angle": 0.0}


## Debug: founds a station on [param planet_name] in [param system_id]
## ("" = the planet nearest a cluster orbit). Returns the live world or null.
static func debug_found(tree: SceneTree, system_id: StringName, planet_name: String = "") -> SystemWorld:
	var fs := of(tree)
	if fs == null:
		return null
	return fs.found(system_id, site_on(system_id, planet_name))


## Station slots left: [constant MAX_STATIONS] minus the stations, the
## mobile stations (live or as data) and the Forward Stations under
## construction at home.
static func free_slots(tree: SceneTree) -> int:
	var fs := of(tree)
	var used := fs.count() if fs else 0
	used += MobileStation.count_all(tree)
	var home := SystemWorld.home(tree)
	var mgr := home.buildings if home else null
	if mgr:
		var def := mgr.def_by_id(BUILD_ID)
		if def:
			used += mgr.count_of(def)
	return maxi(MAX_STATIONS - used, 0)


## Why a mobile station cannot be sent to [param system_id], or "":
## charted, danger at most [constant MAX_DANGER], no station there and no
## other mobile station headed there ([param skip]: the one asking).
static func target_problem(tree: SceneTree, system_id: StringName, skip: Node = null) -> String:
	if system_id == ClusterNetwork.HOME_ID:
		return "Home has its station"
	var def := Sector.system_def(system_id)
	var st := Sector.state(system_id)
	var e := Sector.network.entry(system_id) if Sector.network else null
	if def == null or st == null or e == null:
		return "No such system"
	if not st.known:
		return "%s is not charted: survey it first (explore contract)" % def.system_name
	if e.danger > MAX_DANGER:
		return "%s is too dangerous (danger %d, at most %d)" % [def.system_name, e.danger, MAX_DANGER]
	if not st.station.is_empty():
		return "%s already has a station" % def.system_name
	if MobileStation.headed_to(tree, system_id, skip):
		return "Another forward station is already headed for %s" % def.system_name
	return ""


## Why the station cannot orbit [param planet] (a live PlanetBody of
## system [param system_id]), or "": the target rules, a planet of that
## system, at least [constant MIN_BASE_DISTANCE] from every hostile base
## (now), and a clear orbit band (site_on clears the moons within
## [constant MAX_ORBIT_GAP]; outside the rings).
static func site_problem(tree: SceneTree, system_id: StringName, planet: PlanetBody, skip: Node = null) -> String:
	var why := target_problem(tree, system_id, skip)
	if not why.is_empty():
		return why
	if planet == null or planet.def == null:
		return "Pick a planet"
	var site := site_on(system_id, planet.def.name)
	if site.is_empty():
		return "Moons cannot hold a station: pick a planet"
	var sys := SolarSystem.of(planet)
	if sys:
		for den in sys.dens:
			if not is_instance_valid(den) or den.dead:
				continue
			var d := den.global_position.distance_to(planet.global_position)
			if d < MIN_BASE_DISTANCE:
				return "%s is %.1f km from %s (%.0f km needed)" % [planet.def.name, d / 1000.0, den.get_display_name(), MIN_BASE_DISTANCE / 1000.0]
	var r := float(site["orbit_radius"])
	if r > planet.def.radius + MAX_ORBIT_GAP:
		return "%s has no clear orbit between its moons" % planet.def.name
	if planet.def.has_rings and r < planet.def.radius * planet.def.ring_outer + 200.0:
		return "The rings of %s cross the station orbit" % planet.def.name
	return ""


func _pin_saved() -> void:
	var vm := get_parent() as ViewManager
	if vm == null:
		return
	for id in ids():
		vm.pin(id)


static func _planet_def(def: SystemDef, planet_name: String) -> PlanetDef:
	for p in def.planets:
		if p.name == planet_name:
			return p
	return null


static func _planet_near_clusters(def: SystemDef) -> PlanetDef:
	var best: PlanetDef = null
	var best_d := INF
	for p in def.planets:
		for b in def.belts:
			var d := absf(p.orbit_radius - b.orbit_radius)
			if d < best_d:
				best_d = d
				best = p
	return best if best else def.planets[0]

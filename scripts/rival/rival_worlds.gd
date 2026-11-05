class_name RivalWorlds
extends Node
## Which rival station worlds (rival headquarters and rival forward
## stations) run live, and the data step of the others (rival corporation
## plan, "Data sim for unviewed rival worlds"). Child of the [ViewManager]
## (made in its _enter_tree).
##
## A rival station world is live while the player views it (plus the
## ViewManager grace), or while something there has to run live
## ([method hold_reason]): ships of another corp in the system or in a jump
## to it, its own ships away from it (a strike, a convoy's escorts), a
## Forward Station structure or a mobile station of its corp, its station
## hull knocked out (the scuttle), contracts of another corp there, one of
## its corp's forward stations live (its Factory is at the headquarters),
## or a timed [method request] (a strike forming, a forward station due).
## While a reason holds the system is pinned (ViewManager.pin); after
## [constant QUIET_TIME] sim seconds without one it is unpinned, and the
## ViewManager drops it at once (or after the grace when the view just
## left it). Dropping it captures the whole world into its
## RemoteSystemState ([method RivalData.capture], from SystemHost), building
## it again restores it ([method RivalData.restore]).
##
## While a rival world is data, [method RivalData.step] runs its economy and
## build plan every [method RivalManager.interval] sim seconds. Ships of
## another corp coming out of a gate into a data rival system make it live
## first ([method before_arrival], from RemoteSim).

const GROUP := "rival_worlds"
## Sim seconds between hold checks.
const CHECK_TIME := 2.0
## Sim seconds a rival world stays pinned after its last hold reason.
const QUIET_TIME := 30.0

## Off: every rival station world stays pinned live (the behaviour before
## this feature; tests and comparisons, the smoke flag --rival-live).
static var data_enabled := true

## System id -> sim time a hold reason last applied.
var _held_at := {}
## System id -> {until: sim time, why: String} ([method request]).
var _requests := {}
## System id -> the last hold reason ("" = none), for tests and the report.
var reasons := {}
## System id -> sim seconds gathered toward the next data step.
var _data_dt := {}
var _check := 0.0
## How often a rival world went data and came back (RivalData counts them; tests).
var went_data := 0
var came_back := 0
## Corp id -> {loads, units, pay}: mining while data (tests, reports).
var data_loads := {}


static func of(tree: SceneTree) -> RivalWorlds:
	return tree.get_first_node_in_group(GROUP) as RivalWorlds if tree else null


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(SimStepper.GROUP)


func _process(delta: float) -> void:
	if not SimClock.paused:
		sim_step(delta * SimClock.speed)


func _vm() -> ViewManager:
	return get_parent() as ViewManager


## Systems with a station of a living rival (headquarters and forward), network order.
static func sites() -> Array[StringName]:
	var out: Array[StringName] = []
	if Sector.network == null or not Corps.has_rival():
		return out
	for id in Sector.network.remote_ids():
		var r := Corps.rival(site_corp(id))
		if r and not r.mind.eliminated:
			out.append(id)
	return out


## The corp of the station site in [param id], &"" without one.
static func site_corp(id: StringName) -> StringName:
	var st := Sector.state(id)
	if st == null or st.station.is_empty():
		return &""
	return Corps.norm(StringName(st.station.get("corp", Corps.PLAYER)))


## True when [param id] is a rival station system that runs as data now.
func is_data(id: StringName) -> bool:
	var st := Sector.state(id)
	return st != null and not st.world.is_empty() and not _vm().is_live(id)


## Keeps [param id] live for at least [param seconds] sim seconds (built
## now when it is data). [param why] shows in [member reasons].
func request(id: StringName, seconds: float, why: String) -> void:
	var r: Dictionary = _requests.get(id, {})
	_requests[id] = {"until": maxf(float(r.get("until", 0.0)), SimClock.time + seconds), "why": why}
	_hold(id, why)


## [method request] for every station system of [param corp].
func request_corp(corp: StringName, seconds: float, why: String) -> void:
	for id in WarStrikes.station_systems(corp):
		if id != ClusterNetwork.HOME_ID and Corps.is_rival(site_corp(id)):
			request(id, seconds, why)


## [method request] for the station systems of [param corp] that are data
## now, when they hold at least [param min_mercs] mercenaries in all. True
## when it asked.
func request_corp_if_data(corp: StringName, seconds: float, why: String, min_mercs: int = 0) -> bool:
	var ids: Array[StringName] = []
	var mercs := 0
	for id in WarStrikes.station_systems(corp):
		if id != ClusterNetwork.HOME_ID and is_data(id):
			ids.append(id)
			mercs += RivalData.captains_of(Sector.state(id).world, &"mercenary_outpost")
	if ids.is_empty() or mercs < min_mercs:
		return false
	for id in ids:
		request(id, seconds, why)
	return true


## A ship ([param d], a ShipCodec dict) is about to come out of a gate in
## [param to]: a data rival world is built first when it is another corp's
## ship, so it arrives into the live station.
func before_arrival(to: StringName, d: Dictionary) -> void:
	if not is_data(to) or not _foreign_dict(d, to):
		return
	_hold(to, "a ship of another corp arrives")


## Why [param id] must run live now, "" when it may be data.
func hold_reason(id: StringName) -> String:
	if not data_enabled:
		return "data sim off"
	var corp := site_corp(id)
	if corp.is_empty():
		return ""
	var rq: Dictionary = _requests.get(id, {})
	if not rq.is_empty():
		if SimClock.time < float(rq["until"]):
			return String(rq["why"])
		_requests.erase(id)
	var vm := _vm()
	var w := vm.world(id)
	var st := Sector.state(id)
	if w:
		var why := _live_reason(w, corp)
		if not why.is_empty():
			return why
	for d: Dictionary in st.ships:
		if _foreign_dict(d, id):
			return "ships of another corp in the system"
	var mine := RivalData.building_ids(w, st)
	for t: Dictionary in Sector.transits:
		var td: Dictionary = t["ship"]
		if t["to"] == id and _foreign_dict(td, id):
			return "ships of another corp in a jump here"
		if _dict_from(td, mine):
			return "its ships in a gate jump"
	for sid: StringName in Sector.states:
		if sid == id:
			continue
		for d: Dictionary in (Sector.states[sid] as RemoteSystemState).ships:
			if _dict_from(d, mine) or (MobileStation.is_mobile(d) and id == Corps.home_of(corp) and _mobile_corp(d) == corp):
				return "its ships away (as data)"
	for c in ContractBoard.contracts:
		if c.system_id == id and c.corp != corp and not c.is_finished():
			return "contracts of another corp here"
	if id == Corps.home_of(corp):
		for t: Dictionary in Sector.transits:
			if MobileStation.is_mobile(t["ship"]) and _mobile_corp(t["ship"]) == corp:
				return "its mobile station in a gate jump"
		for ow in SystemWorld.all(get_tree()):
			if ow.system_id != id and ow.has_station and not ow.is_home and ow.corp_id == corp:
				return "its forward station is live"
	return ""


## Reasons found in the live world [param w] of [param corp].
func _live_reason(w: SystemWorld, corp: StringName) -> String:
	var mgr := w.buildings
	if mgr:
		if mgr.station_hull and (mgr.station_hull.disabled or mgr.station_hull.scuttle_left > 0.0):
			return "its station is knocked out"
		for b in mgr.buildings:
			if is_instance_valid(b) and b.def.id == ForwardStations.BUILD_ID:
				return "a Forward Station is being built"
	for n in SystemWorld.nodes_in(w, Ship.GROUP):
		var s := n as Ship
		if s == null or s.dead:
			continue
		if s is MobileStation:
			return "a mobile station is here" if (s as MobileStation).corp == corp else "a mobile station of another corp is here"
		if s.captain == null or not is_instance_valid(s.home):
			continue
		if Corps.owner_of(s) != corp:
			return "ships of another corp in the system"
		if s.transit:
			return "its ships are leaving through a gate"
	# Its ships in other live worlds (a strike, escorts on their way home).
	for ow in SystemWorld.all(get_tree()):
		if ow == w:
			continue
		for n in SystemWorld.nodes_in(ow, Ship.GROUP):
			var s := n as Ship
			if s and not s.dead and is_instance_valid(s.home) and SystemWorld.of(s.home) == w:
				return "its ships away in %s" % ow.system_id
			var ms := n as MobileStation
			if ms and not ms.dead and ms.corp == corp and w.is_hq:
				return "its mobile station is under way"
	return ""


## [param d] is a hired ship or mobile station of a corp other than the
## one with the station in [param id].
func _foreign_dict(d: Dictionary, id: StringName) -> bool:
	var corp := site_corp(id)
	if MobileStation.is_mobile(d):
		return _mobile_corp(d) != corp
	if String(d.get("kind", "")) != ShipCodec.KIND_HIRED:
		return false
	var mine := RivalData.building_ids(_vm().world(id), Sector.state(id))
	return not mine.has(int(d.get("home", 0)))


static func _mobile_corp(d: Dictionary) -> StringName:
	return Corps.norm(StringName((d.get("mobile", {}) as Dictionary).get("corp", String(Corps.PLAYER))))


## [param d] (or an escort it carries) has its home in [param ids].
static func _dict_from(d: Dictionary, ids: Dictionary) -> bool:
	if ids.has(int(d.get("home", 0))) and String(d.get("kind", "")) == ShipCodec.KIND_HIRED:
		return true
	for ed: Dictionary in d.get("escorts", []):
		if ids.has(int(ed.get("home", 0))):
			return true
	return false


## Pins [param id] (built now when it is data) and notes the reason.
func _hold(id: StringName, why: String) -> void:
	_held_at[id] = SimClock.time
	reasons[id] = why
	var vm := _vm()
	if not vm.is_pinned(id):
		vm.pin(id)


func sim_step(dt: float) -> void:
	if dt <= 0.0 or not Corps.has_rival():
		return
	_check -= dt
	if _check <= 0.0:
		_check = CHECK_TIME
		_check_holds()
	var vm := _vm()
	for id in sites():
		if vm.is_live(id):
			_data_dt.erase(id)
			continue
		var st := Sector.state(id)
		if st.world.is_empty():
			continue
		var acc := float(_data_dt.get(id, 0.0)) + dt
		var tick := RivalManager.interval()
		if acc < tick:
			_data_dt[id] = acc
			continue
		_data_dt[id] = 0.0
		RivalData.step(get_tree(), id, st, acc)


func _check_holds() -> void:
	var vm := _vm()
	for id in sites():
		var why := hold_reason(id)
		if not why.is_empty():
			_hold(id, why)
			continue
		reasons[id] = ""
		if vm.is_pinned(id) and SimClock.time - float(_held_at.get(id, -INF)) >= QUIET_TIME:
			vm.unpin(id)


## Every rival station system live now and pinned (elimination, tests).
func materialise_corp(corp: StringName) -> void:
	for id in WarStrikes.station_systems(corp):
		if id != ClusterNetwork.HOME_ID and Corps.is_rival(site_corp(id)):
			_hold(id, "needed live")


## Tests: forgets the timed requests on [param id].
func clear_requests(id: StringName) -> void:
	_requests.erase(id)


## Tests: drops [param id] to data now (unpinned, captured), whatever holds it.
func debug_release(id: StringName) -> void:
	var vm := _vm()
	_requests.erase(id)
	_held_at.erase(id)
	vm.unpin(id)
	vm.dematerialise(id)

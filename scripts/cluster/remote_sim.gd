class_name RemoteSim
extends Node
## Steps the remote systems that are data (not live, see [ViewManager]) and
## the ships between gates. Child of the ViewManager (scenes/game.tscn);
## the data itself lives in the Sector autoload (RemoteSystemState per
## system, Sector.transits), so it is saved with the globals.
##
## Per system that is not live, every sim step:
## - Bases (RemoteSystemState.dens, ScavengerDen.save_state dicts): what a
##   live base would do on its own, as counters: below its spawn cap the
##   respawn clock runs and each time it runs out the base "launches" a
##   pack ("pending", built as real ships out at the mouth on the next
##   visit); shields recharge. Its ships stay where they were. No raids out
##   of a remote system yet.
## - Scrap fields age and vanish.
## - Ships: a dict with a "trip" ([method start_trip]: waypoints and a
##   speed, warp legs estimated like a live hop) moves along it; at the end
##   the trip is dropped and [signal trip_finished] fires, unless the ship
##   is on a [GateTransit] (that one runs its phases as data, step_data).
## Ships between gates ([method enqueue]) come out after
## GateTransit.TRANSIT_TIME: built in the target if it is live (home always
## is), else stored in its state.
##
## Explorers ([Survey.step_data]): an explorer dict surveying here walks
## its route with [method start_trip] and reveals along it with the same
## function the live explorer uses; [signal trip_finished] stays the
## generic abstract-travel API; a ship dict may carry any extra keys.
## Mobile stations (F6): their gate hops as GateTransit data, the rest
## (cruise, deploy, the founding) by MobileStation.step_data.

## A stored ship [param ship] (its dict) in system [param system_id] reached
## the end of its trip.
signal trip_finished(system_id: StringName, ship: Dictionary)
## A ship came out of a gate: [param ship] is the live Ship or the stored dict.
signal ship_arrived(system_id: StringName, ship: Variant)

const GROUP := "remote_sim"


static func of(tree: SceneTree) -> RemoteSim:
	return tree.get_first_node_in_group(GROUP) as RemoteSim if tree else null


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(SimStepper.GROUP)


func _process(delta: float) -> void:
	if not SimClock.paused:
		sim_step(delta * SimClock.speed)


# --- API ------------------------------------------------------------------------

## A ship (ShipCodec dict) went into a portal: it comes out of [param gate]
## in [param to] after the transit time.
static func enqueue(d: Dictionary, to: StringName, gate: String) -> void:
	Sector.transits.append({"ship": d, "to": to, "gate": gate, "at": SimClock.time + GateTransit.TRANSIT_TIME})


## Gives stored ship [param d] a trip through [param points] (world
## positions in its system) at [param ship_speed] m/s; legs longer than
## SpaceNav.WARP_MIN_LEG count as warp hops.
func start_trip(d: Dictionary, points: Array, ship_speed: float) -> void:
	d["trip"] = {"points": points.duplicate(), "speed": maxf(ship_speed, 1.0), "i": 0}


## Sim seconds a live ship at [param ship_speed] needs for a leg of
## [param dist] metres (warp spool and hop on long legs).
static func leg_time(dist: float, ship_speed: float) -> float:
	var v := maxf(ship_speed, 1.0)
	if dist < SpaceNav.WARP_MIN_LEG:
		return dist / v
	return SpaceNav.WARP_SPOOL + (dist - SpaceNav.WARP_DROP) / SpaceNav.WARP_SPEED + SpaceNav.WARP_DROP / v


static func has_player_ship(st: RemoteSystemState) -> bool:
	for d: Dictionary in st.ships:
		if String(d.get("kind", "")) == ShipCodec.KIND_HIRED or MobileStation.is_mobile(d):
			return true
	return false


## One of the player's ships is in the jump to [param id].
func player_ship_bound_for(id: StringName) -> bool:
	for t: Dictionary in Sector.transits:
		if t["to"] == id and (String((t["ship"] as Dictionary).get("kind", "")) == ShipCodec.KIND_HIRED or MobileStation.is_mobile(t["ship"])):
			return true
	return false


## After a load: the captains of ships that are data get their berth and
## whereabouts back (Captain.away_slot, away_in).
func after_load() -> void:
	var refs := SystemHost.known_refs(get_tree())
	for id: StringName in Sector.states:
		var def := Sector.system_def(id)
		for d: Dictionary in (Sector.states[id] as RemoteSystemState).ships:
			_mark_away(refs, d, def.system_name if def else String(id))
	for t: Dictionary in Sector.transits:
		var def := Sector.system_def(t["to"])
		_mark_away(refs, t["ship"], "the jump to %s" % (def.system_name if def else String(t["to"])))


func _mark_away(refs: SaveRefs, d: Dictionary, where: String) -> void:
	# A mobile station's escorts ride in its dict.
	for ed: Dictionary in d.get("escorts", []):
		_mark_away(refs, ed, where)
	if String(d.get("kind", "")) != ShipCodec.KIND_HIRED:
		return
	var c := refs.captain(int(d.get("captain", 0)))
	if c and not is_instance_valid(c.ship):
		c.away_slot = int(d.get("slot", -1))
		c.away_in = where


# --- Step -----------------------------------------------------------------------

func sim_step(dt: float) -> void:
	if dt <= 0.0:
		return
	_step_transits()
	var vm := get_parent() as ViewManager
	for id: StringName in Sector.states:
		if vm and vm.is_live(id):
			continue
		_step_system(id, Sector.states[id] as RemoteSystemState, dt)


func _step_transits() -> void:
	if Sector.transits.is_empty():
		return
	var vm := get_parent() as ViewManager
	var due: Array = []
	for t: Dictionary in Sector.transits:
		if SimClock.time >= float(t["at"]):
			due.append(t)
	for t: Dictionary in due:
		Sector.transits.erase(t)
		var to: StringName = t["to"]
		var d: Dictionary = t["ship"]
		var w := vm.world(to) if vm else null
		var def := Sector.system_def(to)
		var where := def.system_name if def else String(to)
		if w:
			var s := GateTransit.arrive_live(w, d, String(t["gate"]))
			if s:
				ship_arrived.emit(to, s)
		else:
			GateTransit.arrive_data(to, d, String(t["gate"]))
			_mark_away(SystemHost.known_refs(get_tree()), d, where)
			ship_arrived.emit(to, d)


func _step_system(id: StringName, st: RemoteSystemState, dt: float) -> void:
	var def := Sector.system_def(id)
	if def == null:
		return
	_step_dens(def, st, dt)
	for i in range(st.scrap.size() - 1, -1, -1):
		var f: Dictionary = st.scrap[i]
		f["_age"] = float(f.get("_age", 0.0)) + dt
		if float(f["_age"]) >= float(f.get("lifetime", 0.0)):
			st.scrap.remove_at(i)
	for d: Dictionary in st.ships.duplicate():
		if d.has("trip"):
			if _advance(d, dt):
				d.erase("trip")
				if not d.has("transit"):
					trip_finished.emit(id, d)
		if d.has("transit") and GateTransit.step_data(self, id, d, dt):
			st.ships.erase(d)
		elif MobileStation.is_mobile(d):
			if MobileStation.step_data(self, id, st, d, dt):
				st.ships.erase(d)
		elif Survey.step_data(self, id, st, d, dt):
			# Lost to a base on the way (already out of the list).
			st.ships.erase(d)


## Moves [param d] along its trip. True at the end.
func _advance(d: Dictionary, dt: float) -> bool:
	var tr: Dictionary = d["trip"]
	var pts: Array = tr["points"]
	var i := int(tr.get("i", 0))
	var left := dt
	var pos := d["position"] as Vector3
	while i < pts.size() and left > 0.0:
		var goal := pts[i] as Vector3
		var dist := pos.distance_to(goal)
		var leg_v := dist / maxf(leg_time(dist, float(tr["speed"])), 0.001) if not tr.has("leg_v") else float(tr["leg_v"])
		tr["leg_v"] = leg_v
		var stepd := leg_v * left
		if stepd >= dist:
			left -= dist / maxf(leg_v, 0.001)
			pos = goal
			i += 1
			tr.erase("leg_v")
		else:
			pos += (goal - pos) / maxf(dist, 0.001) * stepd
			left = 0.0
	d["position"] = pos
	tr["i"] = i
	return i >= pts.size()


## Ships of base dict [param dd] out in data system [param st]: its
## spawns still flying plus the pending launches (counted against the cap).
static func den_out(st: RemoteSystemState, dd: Dictionary, alive_ids: Dictionary = {}) -> int:
	var alive := alive_ids
	if alive.is_empty():
		alive = {}
		for d: Dictionary in st.ships:
			alive[int(d.get("id", 0))] = true
	var out := int(dd.get("pending", 0))
	for sid in dd.get("spawns", []):
		if alive.has(int(sid)):
			out += 1
	return out


func _step_dens(def: SystemDef, st: RemoteSystemState, dt: float) -> void:
	if st.dens.is_empty():
		return
	var alive_ids := {}
	for d: Dictionary in st.ships:
		alive_ids[int(d.get("id", 0))] = true
	for ddef in def.dens:
		var dd: Dictionary = st.dens.get(ddef.name, {})
		if dd.is_empty() or bool(dd.get("dead", false)):
			continue
		var dur: Dictionary = dd.get("durability", {})
		if not dur.is_empty():
			dur["shields"] = float(dur.get("max_shields", dur.get("shields", 0.0)))
		var out := den_out(st, dd, alive_ids)
		if out >= ddef.spawn_cap:
			continue
		var clock := float(dd.get("respawn_clock", ddef.respawn_time)) - dt
		if clock <= 0.0:
			clock = ddef.respawn_time
			var pack := ddef.get_faction().pack_size if ddef.get_faction() else 1
			dd["pending"] = int(dd.get("pending", 0)) + mini(maxi(pack, 1), ddef.spawn_cap - out)
		dd["respawn_clock"] = clock

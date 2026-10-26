class_name Survey
extends RefCounted
## An explorer's survey of one system (P3): the waypoint route, the one
## reveal function both the live explorer and the abstract one call, and
## the abstract walk itself (a ship dict in a system that is data, stepped
## by RemoteSim).
##
## The survey's data rides in the explorer's trip ([member CaptainBrain.Trip.meta]
## ["survey"], saved with the ship): target system, the gate it leaves by,
## the sweep radius, the route and how far along it is. Phases: "out" (on
## the way, GateTransit), "survey" (flying the route), "back" (heading home
## through the gates with the charts; delivered at the Explorer Outpost).
##
## Route ([method plan]): rings around the star. The orbit radii of every
## planet, cluster, base, derelict and gate are grouped into bands one sweep
## radius wide; each band gets a ring at its middle (pushed clear of the
## planets and their moons), outermost first. A ring is a full lap plus one
## step, flown against the direction the bodies orbit in, so anything on the
## band meets the ship at least once; points are [constant SPACING] sweep
## radii apart. Objects no ring reaches get a ring of their own. The route
## is the same for the same system, entry point and radius.
##
## Reveal ([method reveal_along]): every planet (with its moons), cluster,
## base, derelict and gate within the sweep radius of a position (flat
## distance), at their positions for that sim time (computed from the defs,
## so live and data agree). New names go into the system's revealed list
## (Sector.reveal, the fog of war shows them); new clusters, bases,
## derelicts and gates are recorded as discoveries (Sector.discoveries, a
## feed line, a toast for clusters, bases and derelicts).
##
## Danger, as data ([method _chase_rolls]): passing within
## [constant CHASE_RANGE] of a base with ships out, the explorer rolls once
## per base: the base's danger, its ships and faction against the ship's
## speed and Piloting. Caught: hull damage, at 0 the captain is lost (no
## ejection outside home). Live, the base's raiders really hunt it and it
## flees (ExplorerBrain).

## Sweep radius = sensor range x this x the Surveying skill (stock 1500 m
## array, skill 5: about 12 km).
const SENSOR_SCALE := 8.0
## Ring points this many sweep radii apart.
const SPACING := 2.0
## Orbit radii within this many sweep radii share a ring.
const BAND_WIDTH := 1.0
## A ring must pass this close (sweep radii) to every object's orbit.
const COVER := 0.85
const MIN_RING_POINTS := 4
## Rings keep this far outside a planet's reach (moons, rings), metres.
const PLANET_GAP := 1500.0
## Live: a waypoint counts as reached this close (flat), metres.
const REACH := 900.0
## Live: sim seconds between reveal sweeps.
const REVEAL_INTERVAL := 0.4
## Data: bases this close (flat) may chase the explorer, metres.
const CHASE_RANGE := 6000.0

const PHASE_OUT := "out"
const PHASE_SURVEY := "survey"
const PHASE_BACK := "back"

const KIND_PLANET := "planet"
const KIND_CLUSTER := "cluster"
const KIND_DEN := "den"
const KIND_DERELICT := "derelict"
const KIND_GATE := "gate"
const ORE_WORDS := ["rock", "iron", "titanium", "crystal"]
const DERELICT_WORDS := ["probe", "freighter", "frigate", "station hulk"]


# --- Setup ------------------------------------------------------------------------

## The sweep radius of [param ship] (sensor module, Surveying skill), metres.
static func radius_for(ship: Ship) -> float:
	var sensor := ship.stats.sensor_range if ship and ship.stats else 1500.0
	var k := ship.captain.survey_scale() if ship and ship.captain else 1.0
	return sensor * SENSOR_SCALE * k


## A new survey's data for [param contract] flown by [param ship] (taken at home).
static func make(contract: ExploreContract, ship: Ship) -> Dictionary:
	var cap := ship.captain
	return {"target": contract.target_system, "from": contract.from_system, "gate": contract.gate_name, "exit": contract.exit_gate,
			"radius": radius_for(ship), "speed": ship.max_speed, "piloting": cap.piloting if cap else 5,
			"finder": cap.captain_name if cap else ship.get_display_name(), "captain": SaveIds.of(cap),
			"phase": PHASE_OUT, "points": PackedVector3Array(), "i": 0, "found": 0, "rolled": PackedStringArray(),
			"done_at": -1.0, "seed": randi()}


## Gates from home to the target (through the contract's gate).
static func hops_out(s: Dictionary) -> PackedStringArray:
	var h := Sector.hops_between(ClusterNetwork.HOME_ID, StringName(s["from"]))
	h.append(String(s["gate"]))
	return h


## The gate the survey leaves the target by: the contract's exit gate, else
## the one it came in through.
static func exit_gate(s: Dictionary) -> String:
	var e := String(s.get("exit", ""))
	return e if not e.is_empty() else Sector.gate_between(StringName(s["target"]), StringName(s["from"]))


## Gates from system [param here] back home (out of the target by its exit gate).
static func hops_home(s: Dictionary, here: StringName) -> PackedStringArray:
	var h := PackedStringArray()
	if here == ClusterNetwork.HOME_ID:
		return h
	if here == StringName(s["target"]):
		var g := exit_gate(s)
		var t := Sector.network.gate_target(here, g) if Sector.network else {}
		if not t.is_empty():
			h.append(g)
			h.append_array(Sector.hops_between(t["system"], ClusterNetwork.HOME_ID))
			return h
	return Sector.hops_between(here, ClusterNetwork.HOME_ID)


## Starts flying the route from [param at] (sets the points).
static func begin(s: Dictionary, at: Vector3) -> void:
	var def := Sector.system_def(StringName(s["target"]))
	s["phase"] = PHASE_SURVEY
	s["points"] = plan(def, at, float(s["radius"]))
	s["i"] = 0


# --- Route --------------------------------------------------------------------------

## The waypoint route over [param def] from [param start] with sweep
## radius [param radius] (see the class notes). Points on the plane.
static func plan(def: SystemDef, start: Vector3, radius: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	if def == null:
		return pts
	var objs := object_radii(def)
	var radii: Array[float] = []
	for r: float in objs:
		radii.append(r)
	radii.sort()
	var rings: Array[float] = []
	var i := 0
	while i < radii.size():
		var lo := radii[i]
		var hi := lo
		while i + 1 < radii.size() and radii[i + 1] - lo <= radius * BAND_WIDTH:
			i += 1
			hi = radii[i]
		rings.append(_clear_ring((lo + hi) * 0.5, def))
		i += 1
	# Objects no ring passes close enough to get one of their own.
	for r in radii:
		var near := INF
		for g in rings:
			near = minf(near, absf(g - r))
		if near > radius * COVER:
			rings.append(_clear_ring(r, def))
	rings.sort()
	rings.reverse()
	var min_r := maxf(def.star_radius * 3.0, 3000.0)
	var a := atan2(start.z, start.x)
	for r in rings:
		r = maxf(r, min_r)
		var n := maxi(MIN_RING_POINTS, ceili(TAU * r / (SPACING * radius)))
		# Against the orbits (they run toward increasing angle).
		for k in n + 2:
			var ak := a - TAU * float(k) / float(n)
			pts.append(Vector3(cos(ak), 0.0, sin(ak)) * r)
	return pts


## Orbit radius (flat) of everything a survey reveals in [param def].
static func object_radii(def: SystemDef) -> Array[float]:
	var out: Array[float] = []
	for p in def.planets:
		out.append(p.orbit_radius)
	for c in def.belts:
		out.append(c.orbit_radius)
	for d in def.dens:
		out.append(Vector2(den_position(d).x, den_position(d).z).length())
	for x in def.derelicts:
		out.append(x.orbit_radius)
	for g in def.gates:
		out.append(g.orbit_radius)
	return out


## [param r] pushed out of every planet's reach (plus [constant PLANET_GAP]).
static func _clear_ring(r: float, def: SystemDef) -> float:
	for pass_i in 3:
		for p in def.planets:
			var gap := SystemGenerator.planet_reach(p) + PLANET_GAP
			var d := r - p.orbit_radius
			if absf(d) < gap:
				r = p.orbit_radius + gap * (signf(d) if absf(d) > 1.0 else 1.0)
	return r


## Seconds a ship at [param speed] needs for [param pts] from [param from]
## (RemoteSim leg times).
static func route_time(from: Vector3, pts: PackedVector3Array, speed: float) -> float:
	var t := 0.0
	var at := from
	for p in pts:
		t += RemoteSim.leg_time(at.distance_to(p), speed)
		at = p
	return t


# --- Positions ------------------------------------------------------------------------

## Fixed spot of a base (SolarSystem.den_position, from the def alone).
static func den_position(d: DenDef) -> Vector3:
	var r := (d.anchor_radius if d.anchor_radius > 0.0 else 10000.0) + d.radial_offset
	var a := deg_to_rad(d.angle_deg)
	return Vector3(cos(a), 0.0, sin(a)) * r + Vector3.UP * d.height


static func planet_position(p: PlanetDef, t: float) -> Vector3:
	var a := deg_to_rad(p.start_angle_deg)
	if p.orbit_period != 0.0:
		a += TAU * t / p.orbit_period
	return p.orbit_plane() * Vector3(cos(a), 0.0, sin(a)) * p.orbit_radius


static func cluster_position(c: ClusterDef, t: float) -> Vector3:
	var a := deg_to_rad(c.start_angle_deg)
	var period := c.get_orbit_period()
	if period != 0.0:
		a += TAU * t / period
	return Orbiter.inclined_basis(c.inclination_deg, c.ascending_node_deg) * Vector3(cos(a), 0.0, sin(a)) * c.orbit_radius


## Everything a survey can reveal in [param def] at sim time [param t]:
## [{key, names (the planet's moons too), kind, pos, detail}].
static func objects(def: SystemDef, t: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if def == null:
		return out
	for p in def.planets:
		var names := PackedStringArray([p.name])
		for m: PlanetDef in p.moons:
			names.append(m.name)
		out.append({"key": p.name, "names": names, "kind": KIND_PLANET, "pos": planet_position(p, t), "detail": ""})
	for c in def.belts:
		out.append({"key": c.name, "names": PackedStringArray([c.name]), "kind": KIND_CLUSTER, "pos": cluster_position(c, t),
				"detail": ORE_WORDS[clampi(c.ore_type, 0, 3)]})
	for d in def.dens:
		var f := d.get_faction()
		out.append({"key": d.name, "names": PackedStringArray([d.name]), "kind": KIND_DEN, "pos": den_position(d),
				"detail": f.display_name if f else ""})
	for x in def.derelicts:
		out.append({"key": x.name, "names": PackedStringArray([x.name]), "kind": KIND_DERELICT, "pos": x.position(),
				"detail": DERELICT_WORDS[clampi(x.kind, 0, 3)]})
	for g in def.gates:
		out.append({"key": g.name, "names": PackedStringArray([g.name]), "kind": KIND_GATE, "pos": JumpGate.position_for(g, t),
				"detail": g.target_system})
	return out


# --- Reveal -----------------------------------------------------------------------------

## Reveals what lies within [param radius] (flat) of [param position] in
## system [param id] at sim time [param t]. [param finder] / [param captain_id]:
## who found it (discoveries). Returns the newly revealed names. Shared by
## the live explorer (ExplorerBrain) and the abstract one ([method step_data]).
static func reveal_along(id: StringName, position: Vector3, radius: float, finder: String = "", captain_id: int = 0, t: float = NAN) -> PackedStringArray:
	var def := Sector.system_def(id)
	var st := Sector.state(id)
	var fresh := PackedStringArray()
	if def == null or st == null:
		return fresh
	if is_nan(t):
		t = SimClock.time
	var hits: Array[Dictionary] = []
	var names := PackedStringArray()
	for o in objects(def, t):
		if st.revealed.has(String(o["key"])):
			continue
		if SpaceNav.flat_distance(o["pos"] as Vector3, position) > radius:
			continue
		hits.append(o)
		names.append_array(o["names"] as PackedStringArray)
	if hits.is_empty():
		return fresh
	fresh = Sector.reveal(id, names)
	for o in hits:
		_note_find(id, def, o, finder, captain_id)
	return fresh


## Feed line, toast and discovery record for one find.
static func _note_find(id: StringName, def: SystemDef, o: Dictionary, finder: String, captain_id: int) -> void:
	var kind := String(o["kind"])
	if kind == KIND_PLANET:
		return
	var item := String(o["key"])
	var detail := String(o["detail"])
	Sector.add_discovery(id, kind, item, detail, finder, captain_id)
	var who := finder if not finder.is_empty() else "An explorer"
	var text := ""
	var toast := true
	match kind:
		KIND_CLUSTER:
			text = "%s found %s %s cluster in %s" % [who, "an" if detail == "iron" else "a", detail, def.system_name]
		KIND_DEN:
			text = "%s found the %s in %s" % [who, item, def.system_name]
		KIND_DERELICT:
			text = "%s found a derelict %s in %s" % [who, detail, def.system_name]
		_:
			text = "%s charted %s in %s (to %s)" % [who, item, def.system_name, detail]
			toast = false
	EventLog.post("%s (%s)" % [text, item] if kind == KIND_CLUSTER or kind == KIND_DERELICT else text,
			EventLog.Kind.THREAT if kind == KIND_DEN else EventLog.Kind.REWARD, null, Vector3.INF, "find:%s:%s" % [id, item])
	if toast:
		_toast(text)


static func _toast(text: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var pm := tree.root.get_node_or_null(^"PauseMenu") if tree else null
	if pm and pm.has_method(&"toast"):
		pm.call(&"toast", text)


## Revealed names of [param id] by kind: {planets, clusters, dens, derelicts, gates} counts.
static func tally(id: StringName) -> Dictionary:
	var def := Sector.system_def(id)
	var st := Sector.state(id)
	var out := {KIND_PLANET: 0, KIND_CLUSTER: 0, KIND_DEN: 0, KIND_DERELICT: 0, KIND_GATE: 0}
	if def == null or st == null:
		return out
	for o in objects(def, 0.0):
		if st.revealed.has(String(o["key"])):
			out[o["kind"]] = int(out[o["kind"]]) + 1
	return out


## "6 planets, 4 clusters, 2 bases, 3 derelicts, 3 gates".
static func tally_text(id: StringName) -> String:
	var t := tally(id)
	var parts: PackedStringArray = []
	for pair in [[KIND_PLANET, "planet"], [KIND_CLUSTER, "cluster"], [KIND_DEN, "base"], [KIND_DERELICT, "derelict"], [KIND_GATE, "gate"]]:
		var n := int(t[pair[0]])
		parts.append("%d %s%s" % [n, pair[1], "" if n == 1 else "s"])
	return ", ".join(parts)


# --- Abstract walk (RemoteSim) ---------------------------------------------------------------

## The survey data of a stored ship [param d] ({} when it is not surveying).
static func of_dict(d: Dictionary) -> Dictionary:
	var b: Dictionary = d.get("brain", {})
	var t: Dictionary = b.get("trip", {})
	var m: Dictionary = t.get("meta", {})
	return m.get("survey", {})


## One sim step of stored explorer [param d] in system [param id] (not
## live). True when the ship is gone (lost to a base).
static func step_data(sim: RemoteSim, id: StringName, st: RemoteSystemState, d: Dictionary, dt: float) -> bool:
	var s := of_dict(d)
	if s.is_empty() or String(d.get("kind", "")) != ShipCodec.KIND_HIRED:
		return false
	var b: Dictionary = d["brain"]
	match String(s.get("phase", "")):
		PHASE_OUT:
			if StringName(s["target"]) != id:
				return false
			var td: Dictionary = d.get("transit", {})
			if td.is_empty() or int(td.get("phase", GateTransit.Phase.PARK)) == GateTransit.Phase.PARK:
				d.erase("transit")
				d.erase("trip")
				begin(s, d["position"] as Vector3)
				b["state"] = CaptainBrain.State.SURVEYING
				reveal_along(id, d["position"] as Vector3, float(s["radius"]), String(s["finder"]), int(s["captain"]))
				DerelictLoot.queue_near(s, id, d["position"] as Vector3, float(s["radius"]))
				_progress(s, d)
		PHASE_SURVEY:
			if d.has("transit"):
				return false
			reveal_along(id, d["position"] as Vector3, float(s["radius"]), String(s["finder"]), int(s["captain"]))
			DerelictLoot.queue_near(s, id, d["position"] as Vector3, float(s["radius"]))
			if _chase_rolls(sim, id, st, d, s):
				return true
			if _visit_data(sim, id, d, s, dt):
				return false
			var pts: PackedVector3Array = s["points"]
			if d.has("trip"):
				var tr: Dictionary = d["trip"]
				var at := int(s.get("walk_from", 0)) + int(tr.get("i", 0))
				if at != int(s["i"]):
					s["i"] = at
					_progress(s, d)
			else:
				if s.has("walk_from"):
					s["i"] = int(s["walk_from"]) + int(s.get("walk_n", 0))
					s.erase("walk_from")
					s.erase("walk_n")
					_progress(s, d)
				if int(s["i"]) >= pts.size():
					_finish_data(id, d, s)
				else:
					var rest := Array(pts.slice(int(s["i"])))
					sim.start_trip(d, rest, float(s["speed"]))
					s["walk_from"] = int(s["i"])
					s["walk_n"] = rest.size()
	return false


## Data: a derelict on the survey's salvage list (DerelictLoot): the route
## walk pauses, the ship flies to the hulk, hovers DerelictLoot.HOVER and
## strips it, then the walk goes on from the next waypoint. True while busy.
static func _visit_data(sim: RemoteSim, id: StringName, d: Dictionary, s: Dictionary, dt: float) -> bool:
	var v := DerelictLoot.next_visit(s)
	if v.is_empty():
		return false
	var at := DerelictLoot.hover_point(id, v)
	if not s.has("visit"):
		# Pause the route walk where it is.
		if d.has("trip") and s.has("walk_from"):
			var tr: Dictionary = d["trip"]
			s["i"] = int(s["walk_from"]) + int(tr.get("i", 0))
			s.erase("walk_from")
			s.erase("walk_n")
			d.erase("trip")
			_progress(s, d)
		s["visit"] = v
		s["visit_t"] = 0.0
		sim.start_trip(d, [at], float(s["speed"]))
		return true
	if d.has("trip"):
		return true
	if (d["position"] as Vector3).distance_to(at) > DerelictLoot.REACH and float(s.get("visit_t", 0.0)) <= 0.0:
		# Picked up from a live ship that was still on its way.
		sim.start_trip(d, [at], float(s["speed"]))
		return true
	s["visit_t"] = float(s.get("visit_t", 0.0)) + dt
	if float(s["visit_t"]) >= DerelictLoot.HOVER:
		DerelictLoot.salvage(id, s, v)
	return true


## The walk is done: charts aboard, the gates home.
static func _finish_data(id: StringName, d: Dictionary, s: Dictionary) -> void:
	finish(s, id)
	var b: Dictionary = d["brain"]
	var trip: Dictionary = b.get("trip", {})
	trip["loaded"] = true
	b["state"] = CaptainBrain.State.RETURNING
	var hops := hops_home(s, id)
	if hops.is_empty():
		return
	d["transit"] = {"phase": GateTransit.Phase.APPROACH, "hops": hops, "dwell": 0.0, "wait": 0.0, "speed": float(s["speed"]), "gate": hops[0]}
	_progress(s, d)


## Marks the survey done (both ways): phase "back", the time, a feed line.
static func finish(s: Dictionary, id: StringName) -> void:
	s["phase"] = PHASE_BACK
	s["done_at"] = SimClock.time
	var def := Sector.system_def(id)
	EventLog.post("%s finished surveying %s and is heading home with the charts" % [String(s["finder"]), def.system_name if def else String(id)],
			EventLog.Kind.INFO)


## The contract's progress line follows the survey.
static func _progress(s: Dictionary, d: Dictionary) -> void:
	var trip: Dictionary = (d.get("brain", {}) as Dictionary).get("trip", {})
	var c := ContractBoard.find_saved(int(trip.get("contract", 0))) as ExploreContract
	if c:
		c.note_progress(s)


## Data: one roll per base the explorer passes near. True when it was lost.
static func _chase_rolls(sim: RemoteSim, id: StringName, st: RemoteSystemState, d: Dictionary, s: Dictionary) -> bool:
	var def := Sector.system_def(id)
	var pos := d["position"] as Vector3
	for dd in def.dens:
		var rolled: PackedStringArray = s["rolled"]
		if rolled.has(dd.name) or SpaceNav.flat_distance(den_position(dd), pos) > CHASE_RANGE:
			continue
		var out := ships_out(st, dd)
		if out <= 0:
			continue
		rolled.append(dd.name)
		s["rolled"] = rolled
		var f := dd.get_faction()
		var chance := chase_chance(dd, out, float(s["speed"]), int(s["piloting"]))
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%d:%s" % [int(s["seed"]), dd.name])
		var who := "%s %s" % [dd.gang, f.unit_name.to_lower() + "s" if f else "raiders"]
		var name := String(s["finder"])
		if rng.randf() >= chance:
			EventLog.post("%s slipped past %s in %s (%d%% chance to be caught)" % [name, who, def.system_name, roundi(chance * 100.0)], EventLog.Kind.COMBAT)
			continue
		var dur: Dictionary = d.get("durability", {})
		var max_hull := float(dur.get("max_hull", 240.0))
		var dmg := max_hull * rng.randf_range(0.3, 0.65) * (1.0 + 0.25 * float(dd.danger_bonus))
		var hull := float(dur.get("hull", max_hull)) - dmg
		if hull <= 0.0:
			lose_data(sim, id, d, "%s caught the ship near %s" % [who, dd.name])
			st.ships.erase(d)
			return true
		dur["hull"] = hull
		dur["shields"] = 0.0
		d["durability"] = dur
		EventLog.post("%s was chased by %s in %s and got away, hull %d%%" % [name, who, def.system_name, roundi(hull / max_hull * 100.0)], EventLog.Kind.COMBAT)
	return false


## Raider ships out of base [param dd] in a system that is data (its stored
## ships plus the ones launched meanwhile; never visited: its first pack).
static func ships_out(st: RemoteSystemState, dd: DenDef) -> int:
	var ds: Dictionary = st.dens.get(dd.name, {})
	if ds.is_empty():
		return dd.initial_spawns
	if bool(ds.get("dead", false)):
		return 0
	var n := int(ds.get("pending", 0))
	var ids := {}
	for sid in ds.get("spawns", []):
		ids[int(sid)] = true
	for x: Dictionary in st.ships:
		if String(x.get("kind", "")) == ShipCodec.KIND_SCAVENGER and ids.has(int(x.get("id", 0))):
			n += 1
	return n


## Chance base [param dd] with [param out] ships catches an explorer at
## [param speed] m/s flown with Piloting [param piloting].
static func chase_chance(dd: DenDef, out: int, speed: float, piloting: int) -> float:
	var f := dd.get_faction()
	var fast := 0.1 if f and f.id == &"corsair" else 0.0
	return clampf(0.1 + 0.08 * dd.danger_bonus + 0.04 * out + fast - 0.25 * Captain.unit(piloting) - (speed - 150.0) / 500.0, 0.03, 0.6)


## A stored explorer was destroyed: the captain is lost (no pod outside
## home), the berth freed, the contract open again.
static func lose_data(sim: RemoteSim, id: StringName, d: Dictionary, why: String) -> void:
	var refs := SystemHost.known_refs(sim.get_tree())
	var cap := refs.captain(int(d.get("captain", 0)))
	var home := refs.building(int(d.get("home", 0)))
	var trip: Dictionary = (d.get("brain", {}) as Dictionary).get("trip", {})
	var c := ContractBoard.find_saved(int(trip.get("contract", 0))) as ExploreContract
	if c:
		c.release_explorer(cap)
	var def := Sector.system_def(id)
	var where := def.system_name if def else String(id)
	if cap:
		cap.alive = false
		cap.away_slot = -1
		cap.away_in = ""
		cap.flight_log.note(CaptainLog.Kind.LOSS, CaptainLog.Outcome.FAILED, "Lost with the ship in %s" % where,
				"%s; no way out this far from home" % why, "Destroyed in %s" % where)
	if home and cap:
		home.forget_captain(cap)
	EventLog.post("%s was lost in %s (%s)" % [cap.captain_name if cap else "An explorer", where, why], EventLog.Kind.LOSS)

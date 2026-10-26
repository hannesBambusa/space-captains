class_name GateTransit
extends RefCounted
## A hired ship's trip through jump gates. While a ship has one
## (Ship.transit) it flies the trip and the brain waits (begin_transit /
## end_transit); the trip ends back at home, where the brain flies the ship
## to its outpost and docks.
##
## [member hops]: the gate to take in each system along the way, in order
## ("Ostra Gate", then "Solace Gate" for there and back); [member dwell]:
## sim seconds held in each system passed through before the next gate.
## Phases, live: UNDOCK (out of the berth), APPROACH (fly, warp allowed, to a
## point [constant APPROACH_DIST] in front of the portal), ENTER (straight
## into the portal over [constant ENTER_TIME], the hull shrinks, a flash in
## the portal colour), then the ship leaves its world: it is saved as a
## ShipCodec dict, freed, and spends [constant TRANSIT_TIME] sim seconds in
## Sector.transits (RemoteSim). It comes out of the target gate: in a live
## system it is created there from the dict (ARRIVE: out of the portal over
## [constant ARRIVE_TIME], growing back), otherwise the dict goes into the
## system's RemoteSystemState and RemoteSim walks the same phases as data
## (trips at the ship's speed, warp legs estimated). After arriving: DWELL,
## then the next hop; no hop left: home hands the ship back, anywhere else
## it holds (PARK) unless the brain takes it back there
## (CaptainBrain.takes_ship_back: an explorer at its target; as data the
## Survey walk picks the parked ship up). Never reparented across worlds: always dict and back.
## The captain, home building and contract objects stay the same (the dict
## links them by save id, SystemHost.known_refs); while the ship is data,
## Captain.away_slot keeps its berth and Captain.away_in says where it is.

enum Phase { UNDOCK, APPROACH, ENTER, ARRIVE, DWELL, PARK }

## Sim seconds between going into one portal and out of the other.
const TRANSIT_TIME := 8.0
## In front of the portal (along its axis) where the run-in starts, metres.
const APPROACH_DIST := 650.0
## Close enough to the approach point to start the run-in (flat), metres.
const APPROACH_REACH := 160.0
## Out of the portal on arrival, metres along the axis.
const EXIT_DIST := 700.0
const ENTER_TIME := 2.4
const ARRIVE_TIME := 2.2
## Hull scale inside the portal.
const SHRINK := 0.05

var ship: Ship
var phase: Phase = Phase.APPROACH
var hops: PackedStringArray = []
var dwell: float = 0.0
## DWELL: sim seconds left.
var wait: float = 0.0
## The ship's cruise speed (RemoteSim trips), m/s.
var speed: float = 150.0
## The gate flown to (APPROACH, ENTER) or out of (ARRIVE).
var gate_name: String = ""

var _t: float = 0.0
var _from := Vector3.ZERO
var _flashed := false
var _held := false


# --- Start, save --------------------------------------------------------------

## Puts [param s] on a trip through [param gate_hops]. Hired ships (a
## captain and a home) only; null otherwise or when the first gate is not
## in its system.
static func start(s: Ship, gate_hops: PackedStringArray, dwell_time: float = 0.0) -> GateTransit:
	if s == null or s.dead or s.captain == null or s.brain == null or not is_instance_valid(s.home) or gate_hops.is_empty():
		return null
	if _find_gate(s, gate_hops[0]) == null:
		return null
	var t := GateTransit.new()
	t.ship = s
	t.hops = gate_hops.duplicate()
	t.dwell = dwell_time
	t.speed = s.max_speed
	t.gate_name = gate_hops[0]
	s.transit = t
	s.brain.begin_transit()
	if s.is_docked():
		t.phase = Phase.UNDOCK
		s.start_undock()
	else:
		t.phase = Phase.APPROACH
	EventLog.post("%s is heading for %s" % [s.get_display_name(), t.gate_name], EventLog.Kind.INFO, s)
	s.status_changed.emit(s)
	return t


func to_dict() -> Dictionary:
	return {"phase": phase, "hops": hops, "dwell": dwell, "wait": wait, "speed": speed, "gate": gate_name}


## Gives [param s] back its trip from [param d] (a save, a system going live,
## a ship coming out of a gate).
static func restore(s: Ship, d: Dictionary) -> GateTransit:
	var t := GateTransit.new()
	t.ship = s
	t.phase = int(d.get("phase", Phase.PARK)) as Phase
	t.hops = PackedStringArray(d.get("hops", PackedStringArray()))
	t.dwell = float(d.get("dwell", 0.0))
	t.wait = float(d.get("wait", 0.0))
	t.speed = float(d.get("speed", s.max_speed))
	t.gate_name = String(d.get("gate", ""))
	s.transit = t
	match t.phase:
		Phase.UNDOCK:
			if s.is_docked():
				s.start_undock()
			else:
				t.phase = Phase.APPROACH
		Phase.ENTER:
			# Halfway into a portal: run in again.
			t.phase = Phase.APPROACH
		Phase.ARRIVE:
			t._from = s.global_position
	s.status_changed.emit(s)
	return t


## Lets go of [param s] without destroying anything: off its home's ship
## list, its captain keeps the berth ([member Captain.away_slot]), then the
## node is freed. For a ship that became data (through a portal, or its
## system dematerialised). [param where]: Captain.away_in.
static func detach(s: Ship, where: String = "") -> void:
	if s == null or s.dead:
		return
	if s.captain and s.captain.ship == s:
		s.captain.ship = null
		s.captain.away_slot = s.slot_index
		s.captain.away_in = where if not where.is_empty() else _system_name(SystemWorld.of(s))
	if is_instance_valid(s.home) and s.home.ships.has(s):
		s.home.ships.erase(s)
		s.home.hires_changed.emit(s.home)
	s.transit = null
	s.dead = true
	s._leave_world()


# --- Live ---------------------------------------------------------------------

## One sim step. True when this step placed the ship itself (the mover is
## skipped) or the ship left the world.
func step(dt: float) -> bool:
	match phase:
		Phase.UNDOCK:
			if ship.mover.path_done():
				ship.enter_space()
				_set_phase(Phase.APPROACH)
			return false
		Phase.APPROACH:
			return _approach()
		Phase.ENTER:
			return _enter(dt)
		Phase.ARRIVE:
			return _arrive(dt)
		Phase.DWELL:
			_hold()
			wait -= dt
			if wait <= 0.0:
				_next_hop()
			return false
		Phase.PARK:
			_hold()
	return false


func _approach() -> bool:
	var g := _find_gate(ship, gate_name)
	if g == null:
		_set_phase(Phase.PARK)
		return false
	var ap := g.portal_center() + g.portal_axis() * APPROACH_DIST
	ship.set_world_goal(ap, Vector3.ZERO, Vector3.ZERO, 60.0)
	if ship.mover.warp_state == ShipMover.Warp.IDLE and SpaceNav.flat_distance(ship.global_position, ap) < APPROACH_REACH:
		_from = ship.global_position
		_t = 0.0
		_flashed = false
		_set_phase(Phase.ENTER)
	return false


func _enter(dt: float) -> bool:
	var g := _find_gate(ship, gate_name)
	if g == null:
		_set_phase(Phase.PARK)
		return false
	_t += dt
	var k := clampf(_t / ENTER_TIME, 0.0, 1.0)
	var c := g.portal_center()
	var ax := g.portal_axis()
	var goal := c - ax * 30.0
	var e := k * k * (3.0 - 2.0 * k)
	var dir := goal - _from
	_place(_from.lerp(goal, e), dir, dir.length() / ENTER_TIME)
	_set_model_scale(lerpf(1.0, SHRINK, smoothstep(0.55, 1.0, k)))
	if k >= 0.8 and not _flashed:
		_flashed = true
		WarpFx.flash(ship, c, g.portal_radius * 0.9, g.def.portal_color.lerp(Color.WHITE, 0.35), 1.3, ax)
	if k >= 1.0:
		_jump(g)
	return true


func _arrive(dt: float) -> bool:
	var g := _find_gate(ship, gate_name)
	if g == null:
		_after_arrival()
		return false
	var c := g.portal_center()
	var ax := g.portal_axis()
	if _t <= 0.0:
		_from = c
		WarpFx.flash(ship, c, g.portal_radius * 0.9, g.def.portal_color.lerp(Color.WHITE, 0.35), 1.3, ax)
	_t += dt
	var k := clampf(_t / ARRIVE_TIME, 0.0, 1.0)
	var to := c + ax * EXIT_DIST
	var e := 1.0 - (1.0 - k) * (1.0 - k)
	var dir := to - _from
	_place(_from.lerp(to, e), dir, dir.length() / ARRIVE_TIME * (1.0 - k) + 20.0)
	_set_model_scale(lerpf(SHRINK, 1.0, smoothstep(0.0, 0.5, k)))
	if k >= 1.0:
		var flat := Vector3(dir.x, 0.0, dir.z).normalized()
		ship.place_in_space(ship.global_position, ShipMover.yaw_for(flat), flat * 40.0)
		_set_model_scale(1.0)
		_after_arrival()
	return true


func _after_arrival() -> void:
	var w := SystemWorld.of(ship)
	if not hops.is_empty():
		wait = dwell
		_set_phase(Phase.DWELL)
	elif w and w.is_home:
		_release()
	elif ship.brain and ship.brain.takes_ship_back():
		# An explorer at its target: the survey takes over.
		_release(true)
	else:
		_set_phase(Phase.PARK)


func _next_hop() -> void:
	if hops.is_empty():
		_set_phase(Phase.PARK)
		return
	gate_name = hops[0]
	_set_phase(Phase.APPROACH)


## Home again: the brain takes over and docks. [param quiet]: elsewhere
## (an explorer's survey), no "back in" line.
func _release(quiet: bool = false) -> void:
	ship.transit = null
	_set_model_scale(1.0)
	if ship.brain:
		ship.brain.end_transit()
	if quiet:
		return
	EventLog.post("%s is back in %s" % [ship.get_display_name(), _system_name(SystemWorld.of(ship))], EventLog.Kind.INFO, ship)


## Through the portal: the ship becomes data in Sector.transits.
func _jump(g: JumpGate) -> void:
	var w := SystemWorld.of(ship)
	var from_id := w.system_id if w else ClusterNetwork.HOME_ID
	var tgt := Sector.network.gate_target(from_id, gate_name) if Sector.network else {}
	if tgt.is_empty():
		push_warning("GateTransit: %s leads nowhere (%s)" % [gate_name, from_id])
		_set_model_scale(1.0)
		_set_phase(Phase.PARK)
		return
	if not hops.is_empty():
		hops.remove_at(0)
	var none: Array[Contract] = []
	var d := ShipCodec.save_ship(ship, none)
	phase = Phase.ARRIVE
	gate_name = String(tgt["gate"])
	d["transit"] = to_dict()
	d["docked"] = false
	var to_id: StringName = tgt["system"]
	RemoteSim.enqueue(d, to_id, gate_name)
	var to_name := Sector.system_def(to_id).system_name if Sector.system_def(to_id) else String(to_id)
	EventLog.post("%s jumped through %s" % [ship.get_display_name(), g.def.name], EventLog.Kind.INFO, null, g.global_position)
	detach(ship, "the jump to %s" % to_name)


func _place(pos: Vector3, dir: Vector3, spd: float) -> void:
	ship.global_position = pos
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() > 1.0:
		ship.set_heading(ShipMover.yaw_for(flat))
	var p := ship.get_parent() as Node3D
	var v := dir.normalized() * spd if dir.length_squared() > 0.01 else Vector3.ZERO
	ship.mover.velocity = (p.global_basis.inverse() * v) if p else v
	ship.mover.velocity.y = 0.0
	ship.mover.climb_rate = v.y
	ship.mover.hold()


func _hold() -> void:
	if not _held:
		_held = true
		ship.mover.hold()


func _set_phase(p: Phase) -> void:
	phase = p
	_held = false
	_t = 0.0
	ship.status_changed.emit(ship)


func _set_model_scale(k: float) -> void:
	var m := ship.get_node_or_null(^"Model") as Node3D
	if m:
		m.scale = Vector3.ONE * k


# --- Brain hooks (Ship) -----------------------------------------------------------

func can_warp() -> bool:
	return phase == Phase.APPROACH


func cruise_free() -> bool:
	return phase == Phase.APPROACH


func destination_name() -> String:
	return gate_name if phase == Phase.APPROACH or phase == Phase.ENTER else ""


func status_text() -> String:
	var here := _system_name(SystemWorld.of(ship))
	match phase:
		Phase.UNDOCK:
			return "Undocking for %s" % gate_name
		Phase.APPROACH:
			return "Heading for %s" % gate_name
		Phase.ENTER:
			return "Jumping through %s" % gate_name
		Phase.ARRIVE:
			return "Arriving in %s" % here
		Phase.DWELL:
			return "Holding in %s (%s)" % [here, Fmt.clock(maxf(wait, 0.0))]
	return "Holding in %s" % here


# --- As data (RemoteSim) -----------------------------------------------------------

## One step of a stored ship [param d] with a "transit" in system
## [param sid] (not live). True when it went into a portal (out of the
## system's ship list).
static func step_data(sim: RemoteSim, sid: StringName, d: Dictionary, dt: float) -> bool:
	var td: Dictionary = d["transit"]
	var def := Sector.system_def(sid)
	match int(td.get("phase", Phase.PARK)):
		Phase.APPROACH, Phase.ENTER:
			var gd := _gate_def(def, String(td.get("gate", "")))
			if gd == null:
				td["phase"] = Phase.PARK
				return false
			var c := JumpGate.position_for(gd, SimClock.time)
			var ap := c + JumpGate.axis_for(gd, c) * APPROACH_DIST
			if not d.has("trip"):
				if (d["position"] as Vector3).distance_to(ap) < APPROACH_REACH:
					return _jump_data(sid, d)
				sim.start_trip(d, [ap], float(td.get("speed", 150.0)))
		Phase.ARRIVE:
			if not d.has("trip"):
				if bool(td.get("out", false)):
					td.erase("out")
					_after_arrival_data(td)
				else:
					var gd := _gate_def(def, String(td.get("gate", "")))
					var c := JumpGate.position_for(gd, SimClock.time) if gd else d["position"] as Vector3
					var to := c + (JumpGate.axis_for(gd, c) if gd else Vector3.UP) * EXIT_DIST
					td["out"] = true
					sim.start_trip(d, [to], float(td.get("speed", 150.0)))
		Phase.DWELL:
			td["wait"] = float(td.get("wait", 0.0)) - dt
			if float(td["wait"]) <= 0.0:
				var h := PackedStringArray(td.get("hops", PackedStringArray()))
				if h.is_empty():
					td["phase"] = Phase.PARK
				else:
					td["gate"] = h[0]
					td["phase"] = Phase.APPROACH
	return false


static func _after_arrival_data(td: Dictionary) -> void:
	var h := PackedStringArray(td.get("hops", PackedStringArray()))
	if h.is_empty():
		td["phase"] = Phase.PARK
	else:
		td["wait"] = float(td.get("dwell", 0.0))
		td["phase"] = Phase.DWELL


## A stored ship reached its gate: into Sector.transits.
static func _jump_data(sid: StringName, d: Dictionary) -> bool:
	var td: Dictionary = d["transit"]
	var tgt := Sector.network.gate_target(sid, String(td.get("gate", "")))
	if tgt.is_empty():
		td["phase"] = Phase.PARK
		return false
	var h := PackedStringArray(td.get("hops", PackedStringArray()))
	if not h.is_empty():
		h.remove_at(0)
	td["hops"] = h
	td["phase"] = Phase.ARRIVE
	td["gate"] = String(tgt["gate"])
	td.erase("out")
	d.erase("trip")
	RemoteSim.enqueue(d, tgt["system"], String(tgt["gate"]))
	return true


## Out of gate [param exit_gate] in live system [param w]: the ship is built
## there from [param d]. Null when it cannot be (its captain or home is gone).
static func arrive_live(w: SystemWorld, d: Dictionary, exit_gate: String) -> Ship:
	var g := _gate_in(w, exit_gate)
	d["position"] = g.portal_center() if g else Vector3.ZERO
	d["velocity"] = Vector3.ZERO
	d["docked"] = false
	d.erase("trip")
	var td: Dictionary = d.get("transit", {})
	td["phase"] = Phase.ARRIVE
	td["gate"] = exit_gate
	td.erase("out")
	d["transit"] = td
	var refs := SystemHost.known_refs(w.get_tree())
	var s := ShipCodec.create(w, d, refs)
	if s == null:
		return null
	ShipCodec.finish(s, d, refs)
	if s.transit:
		s.transit._t = 0.0
		s.transit._set_model_scale(SHRINK)
	return s


## Out of the gate in a system that is data: [param d] joins its ships.
static func arrive_data(sid: StringName, d: Dictionary, exit_gate: String) -> void:
	var st := Sector.state(sid)
	if st == null:
		return
	var gd := _gate_def(Sector.system_def(sid), exit_gate)
	d["position"] = JumpGate.position_for(gd, SimClock.time) if gd else Vector3.ZERO
	d["velocity"] = Vector3.ZERO
	var td: Dictionary = d.get("transit", {})
	td["phase"] = Phase.ARRIVE
	td["gate"] = exit_gate
	td.erase("out")
	d["transit"] = td
	st.ships.append(d)


# --- Helpers ------------------------------------------------------------------------

static func _find_gate(s: Ship, gate: String) -> JumpGate:
	return _gate_in(SystemWorld.of(s), gate)


static func _gate_in(w: SystemWorld, gate: String) -> JumpGate:
	var sys := w.sys if w else null
	if sys == null:
		return null
	for g in sys.gates:
		if is_instance_valid(g) and g.def and g.def.name == gate:
			return g
	return null


static func _gate_def(def: SystemDef, gate: String) -> GateDef:
	if def == null:
		return null
	for g in def.gates:
		if g.name == gate:
			return g
	return null


static func _system_name(w: SystemWorld) -> String:
	if w and w.sys and w.sys.system_def:
		return w.sys.system_def.system_name
	return "?"


# --- Debug --------------------------------------------------------------------------

## Debug and tests: sends a mercenary from home through [param gate] (home
## side) and back, holding [param hold] sim seconds over there. Prefers a
## docked or idle merc. Returns the ship or null.
static func debug_round_trip(tree: SceneTree, gate: String = "Ostra Gate", hold: float = 30.0) -> Ship:
	var home := SystemWorld.home(tree)
	if home == null or _gate_in(home, gate) == null or Sector.network == null:
		return null
	var tgt := Sector.network.gate_target(ClusterNetwork.HOME_ID, gate)
	if tgt.is_empty():
		return null
	var best: Ship = null
	for n in SystemWorld.nodes_in(home, Ship.GROUP):
		var s := n as Ship
		if s == null or s.dead or s.transit or not (s is MercenaryShip):
			continue
		var mb := s.brain as MercenaryBrain
		if mb == null or mb.fleet:
			continue
		if best == null or (s.is_docked() and not best.is_docked()):
			best = s
	if best == null:
		return null
	var t := GateTransit.start(best, PackedStringArray([gate, String(tgt["gate"])]), hold)
	return t.ship if t else null

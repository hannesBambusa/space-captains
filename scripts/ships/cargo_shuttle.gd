class_name CargoShuttle
extends Ship
## A small cargo shuttle without a captain, owned by an outpost's
## [CargoDepot]. It replaces the old corridors: goods fly between the
## outposts and the Home Station.
##
## Trip: parked beside its outpost's apron (CargoDepot.berth_transform) it
## loads once the depot has a load ready, leaves the berth, rises clear of
## the outpost while it turns, and climbs straight for the gate of the
## nearest station docking pad (HomeStation.dock_pad; a taken one counts
## extra, [method _pick_pad]): the top of the glide onto the pad, on the
## shuttle's own line to the pad when that comes in from the pad's side of
## the hub, else at the edge of that sector ([method _gate_for]). It takes the pad (one shuttle per pad;
## the others hold beside the gate, or fly round to the other pad when it is
## free and that beats the wait), glides down onto it, unloads (the ore is
## credited to the player now, Economy.receive_cargo; at a forward station
## less the hauling fee, StationSupply.take_hauling_fee) and flies back with
## supplies (cosmetic), gliding down to its berth. The whole trip is flown
## in the station's non-rotating "Structures" frame, where the outposts and
## the pads stand still: straight lines over the structures ([constant
## OUT_HEIGHT], back at [constant BACK_HEIGHT], both above every roof), bent
## only round the station hub ([method _route]). Climbs and descents follow
## a slope (ShipMover.frame_climb_slope). No cruise arcs, no warp, no
## open-space routing: in the world frame the complex orbits at up to
## ~100 m/s. The "cargo_containers" mesh shows only while carrying something
## (smaller for supplies).
##
## Raiders can shoot it while it flies between the outpost and the pads
## (to the station and back); docked, loading or on the pads it is safe.
## Hits raise the colony alarm (ColonyAlarm); destroyed, the ore aboard is
## lost and the depot sends a new shuttle. While the station is disabled
## (StructureHull) its pads are closed: shuttles hold beside the approach
## point. Loaded from a save in open space, it moves into the frame first.
## Model: assets/models/ships/cargo_shuttle.glb; while missing, the miner
## glb scaled [constant FALLBACK_SCALE] with a tint. Sim time only
## ([method sim_step], also under SimStepper).

enum Phase { PARKED, LOADING, UNDOCKING, OUTBOUND, WAITING_PAD, LANDING, UNLOADING, LIFTOFF, RETURNING, DOCKING }

const MODEL_PATH := "res://assets/models/ships/cargo_shuttle.glb"
const FALLBACK_PATH := "res://assets/models/ships/miner.glb"
const FALLBACK_SCALE := 0.6
const FALLBACK_TINT := Color(0.85, 0.78, 0.6)
const CARGO_NODE := "cargo_containers"
const FALLBACK_CARGO_NODE := "miner_hold"
## Cruise speed relative to the (orbiting) station complex, m/s.
const CRUISE_SPEED := 70.0
const LOAD_TIME := 4.0
const UNLOAD_TIME := 5.0
## The glide onto a pad starts at its gate: this far from the pad, m, in the
## direction the shuttle comes from, at most [constant GATE_SECTOR_DEG] off
## the pad's outward line (never in over the hub). Leaving, the same the
## other way round.
const GLIDE_RUN := 110.0
const GATE_SECTOR_DEG := 70.0
## Speed through a gate the shuttle has to turn hard at (90 degrees or more), m/s.
const GATE_TURN_SPEED := 18.0
## Resting height above a pad's origin, m.
const PAD_HEIGHT := 2.3
## Flat distance to the gate where the shuttle takes its pad (or starts to
## hold), m.
const HANDOFF_DISTANCE := 150.0
## Trip heights in the structures frame (pads and berths sit near 0, the
## tallest roof is ~33 m), m: outbound and back at two heights, so the two
## streams pass apart.
const OUT_HEIGHT := 44.0
const BACK_HEIGHT := 60.0
## Height over the berth's line-up point where the trip starts and ends, m
## (clear of the outpost's roof): the shuttle rises to it while it turns
## away, and sinks from it while it turns to back in.
const DOCK_OVER := 22.0
## Climbs and descents: height per metre flown, the fastest rate (m/s), and
## the speed at the top of a descent (m/s; it brakes to rest down the glide).
const CLIMB_SLOPE := 0.36
const CLIMB_RATE := 18.0
const GLIDE_SPEED := 45.0
## The keep-out circle the route bends round: the station hub (addons, solar
## wings). HUB_CLEARANCE is the fallback; the station's is HomeStation.hub_clearance.
const HUB_CLEARANCE := 120.0
## Route waypoints sit this much outside a keep-out circle; arc step round it, radians.
const ROUTE_SLACK := 1.06
const ROUTE_ARC_STEP := 0.5
const ROUTE_MAX_DEPTH := 3
## Speed round a keep-out circle, m/s: at most this, and at most what
## [constant ROUTE_TURN_ACCEL] (m/s^2) holds on the circle. Braking for a
## slower stretch ahead is planned at [constant ROUTE_BRAKE] m/s^2.
const ROUTE_ARC_SPEED := 45.0
const ROUTE_TURN_ACCEL := 10.0
const ROUTE_BRAKE := 9.0
## Holding spot beside the approach point: sideways off the pad's line, and
## further out per shuttle already holding there, m.
const HOLD_SIDE := 45.0
const HOLD_SPACING := 28.0
## Supply-run cargo look: container scale.
const SUPPLY_SCALE := Vector3(1.0, 0.55, 0.6)

## Route metres a taken pad counts extra when picking one (its holder is
## often about to leave; the other pad may be the whole hub away).
const TAKEN_PAD_COST := 250.0

## Seconds the flight round to the other pad must beat the wait for this one by.
const SWITCH_MARGIN := 8.0
## Rough sim seconds of a landing from the approach point and of a liftoff.
const LANDING_TIME := 14.0
const LIFTOFF_TIME := 8.0

## Docking pad key ([method _pad_key]: system id and pad index) -> the
## shuttle holding it. Every station has its own pads.
static var _pads: Dictionary = {}

var depot: CargoDepot
var phase: Phase = Phase.PARKED
## Aboard: iron, titanium, crystal.
var cargo := Economy.zero_ore()
## Carrying supplies (cosmetic).
var supplies: bool = false
## System of this shuttle's station (cached by [method _pad_key]; shuttles never change systems).
var _pad_system: StringName = &""
## Docking pad in use or headed for (-1 = none).
var pad: int = -1
var number: int = 1
## Closest flat distance to the station centre during open-space flight, m.
var min_station_distance: float = INF
## Units delivered to the station by this shuttle.
var total_delivered: int = 0

var _timer: float = 0.0
## The current leg's route is set (cleared when the leg or its target changes).
var _routed: bool = false
## Gate of the pad headed for (frame space, [method _gate_for]).
var _gate := Vector3.INF
var _cargo_node: Node3D
var _cargo_scale := Vector3.ONE


func _init() -> void:
	role = Role.SHUTTLE
	hit_radius = 6.0


## Call before adding to the tree (as a child of the depot's building).
func setup_shuttle(owner_depot: CargoDepot, berth: int, shuttle_number: int) -> void:
	depot = owner_depot
	home = owner_depot.building
	slot_index = berth
	number = shuttle_number
	_model_path = MODEL_PATH
	name = StringName(("Shuttle_%s_%d" % [home.name, number]).validate_node_name())
	var l := ShipLoadout.new()
	l.role_name = "Cargo shuttle"
	l.base_hull = 180.0
	l.base_speed = CRUISE_SPEED
	l.base_acceleration = 20.0
	l.base_turn_rate_deg = 75.0
	l.base_sensor_range = 600.0
	loadout = l


func _on_ready_ship() -> void:
	set_meta(&"focus_radius", 8.0)
	set_meta(&"focus_distance", 90.0)
	_cargo_node = _model.find_child(CARGO_NODE, true, false) as Node3D
	if _cargo_node == null:
		_cargo_node = _model.find_child(FALLBACK_CARGO_NODE, true, false) as Node3D
	if _cargo_node:
		_cargo_scale = _cargo_node.scale
	_update_cargo_look()
	mover.frame_climb_slope = CLIMB_SLOPE
	mover.climb_speed = CLIMB_RATE
	mover.hold()


func _fallback_model() -> Node3D:
	if not ResourceLoader.exists(FALLBACK_PATH):
		return ModelLoader.ship_placeholder()
	var inner := ModelLoader.instantiate(FALLBACK_PATH, ModelLoader.ship_placeholder)
	inner.scale = Vector3.ONE * FALLBACK_SCALE
	for mi in ModelLoader.meshes_of(inner):
		if mi.mesh == null or mi.name == GLOW_NODE:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i) as StandardMaterial3D
			if src:
				var m := src.duplicate() as StandardMaterial3D
				m.albedo_color = m.albedo_color * FALLBACK_TINT
				mi.set_surface_override_material(i, m)
	var root := Node3D.new()
	root.name = "shuttle_fallback"
	root.add_child(inner)
	return root


func _leaves_scrap() -> bool:
	return false


## Only between the outpost and the pads (see the class notes).
func is_targetable() -> bool:
	return not dead and is_inside_tree() and phase in [Phase.OUTBOUND, Phase.WAITING_PAD, Phase.RETURNING]


func take_hit(amount: float, attacker: Node3D, at: Vector3) -> void:
	super.take_hit(amount, attacker, at)
	if not dead:
		ColonyAlarm.raise(self, self, "a cargo shuttle of %s" % home.display_name if is_instance_valid(home) else "a cargo shuttle", attacker)


## Never: the trips are short hops in the structures frame.
func can_warp() -> bool:
	return false


## Never: no cruise arcs on the short hops (the trip heights split the
## traffic instead, see [constant OUT_HEIGHT]).
func cruise_free() -> bool:
	return false


func get_display_name() -> String:
	return "Cargo shuttle, %s" % home.display_name if is_instance_valid(home) else "Cargo shuttle"


func get_status_text() -> String:
	var warp := warp_status_text()
	if not warp.is_empty():
		return warp
	var home_name := home.display_name if is_instance_valid(home) else "the outpost"
	match phase:
		Phase.PARKED:
			if depot and is_instance_valid(depot) and depot.is_supply_only():
				return "Docked at %s" % home_name
			return "Docked at %s, waiting for cargo" % home_name
		Phase.LOADING:
			return "Loading %s" % load_text()
		Phase.UNDOCKING, Phase.OUTBOUND, Phase.LANDING:
			return "Carrying %s to the station" % load_text()
		Phase.WAITING_PAD:
			return "Waiting for a docking pad with %s" % load_text()
		Phase.UNLOADING:
			return "Unloading %s at the station" % load_text()
	return "Carrying supplies back to %s" % home_name


## "48 iron", "30 iron, 12 titanium" or "supplies".
func load_text() -> String:
	var parts: PackedStringArray = []
	for i in cargo.size():
		if cargo[i] > 0:
			parts.append("%d %s" % [cargo[i], Economy.ore_name(i)])
	if parts.is_empty():
		return "supplies" if supplies else "nothing"
	return ", ".join(parts)


func cargo_total() -> int:
	var n := 0
	for v in cargo:
		n += v
	return n


## True while carrying ore or supplies.
func is_loaded() -> bool:
	return supplies or cargo_total() > 0


## Ore aboard on the way to the station (loading through unloading).
func is_carrying_cargo() -> bool:
	return cargo_total() > 0 and phase in [Phase.LOADING, Phase.UNDOCKING, Phase.OUTBOUND, Phase.WAITING_PAD, Phase.LANDING, Phase.UNLOADING]


## Loading at the outpost (or about to leave with the load).
func is_loading() -> bool:
	return phase == Phase.LOADING


# --- Trip ---------------------------------------------------------------------

func sim_step(dt: float) -> void:
	super.sim_step(dt)
	if dead or dt <= 0.0:
		return
	if not is_instance_valid(home) and phase in [Phase.PARKED, Phase.LOADING, Phase.UNDOCKING, Phase.RETURNING, Phase.DOCKING]:
		_retire()
		return
	if is_targetable():
		var st := _station_world()
		if st != Vector3.INF:
			min_station_distance = minf(min_station_distance, SpaceNav.flat_distance(global_position, st))
	match phase:
		Phase.PARKED:
			if depot and is_instance_valid(depot) and depot.load_ready() and not depot.loading_busy(self):
				var got := depot.take_load()
				var n := 0
				for v in got:
					n += v
				if n > 0 or depot.is_supply_only():
					cargo = got
					supplies = n == 0
					phase = Phase.LOADING
					_timer = LOAD_TIME
					_update_cargo_look()
					status_changed.emit(self)
		Phase.LOADING:
			_timer -= dt
			if _timer <= 0.0:
				repairing = false
				pad = _pick_pad()
				mover.set_path(_undock_path())
				phase = Phase.UNDOCKING
				status_changed.emit(self)
		Phase.UNDOCKING:
			if mover.path_done() and _enter_frame():
				_routed = false
				phase = Phase.OUTBOUND
		Phase.OUTBOUND, Phase.WAITING_PAD:
			_fly_to_pad()
		Phase.LANDING:
			if mover.path_done():
				phase = Phase.UNLOADING
				_timer = UNLOAD_TIME
				status_changed.emit(self)
		Phase.UNLOADING:
			_timer -= dt
			if _timer <= 0.0:
				_deliver()
				mover.set_path(_liftoff_path())
				phase = Phase.LIFTOFF
				status_changed.emit(self)
		Phase.LIFTOFF:
			if mover.path_done():
				_release_pad()
				_routed = false
				phase = Phase.RETURNING
		Phase.RETURNING:
			_fly_home()
		Phase.DOCKING:
			if mover.path_done():
				supplies = false
				cargo = Economy.zero_ore()
				_update_cargo_look()
				mover.hold()
				phase = Phase.PARKED
				status_changed.emit(self)


func _fly_to_pad() -> void:
	if not _enter_frame():
		return
	if pad < 0:
		pad = _pick_pad()
		_routed = false
		if pad < 0:
			return
	if phase == Phase.OUTBOUND:
		if not _routed or _gate == Vector3.INF:
			_route_to_gate()
			_routed = true
		_skip_passed()
		if SpaceNav.flat_distance(position, _gate) > HANDOFF_DISTANCE and not mover.path_done():
			return
	var mgr := BuildingManager.of(self)
	if mgr and mgr.station_hull and mgr.station_hull.disabled:
		_hold()
		return
	if _claim_pad(pad):
		# From the holding spot the gate is right there: straight down.
		if phase != Phase.OUTBOUND or _gate == Vector3.INF:
			_gate = _gate_for(pad, position)
		mover.set_path(_landing_path())
		phase = Phase.LANDING
		status_changed.emit(self)
		return
	var other := (pad + 1) % maxi(_pad_count(), 1)
	if not _pad_taken(other) and _route_length(position, _gate_for(other, position)) / ROUTE_ARC_SPEED + SWITCH_MARGIN < _pad_free_in(pad):
		# The other pad is free and getting there beats waiting: fly round
		# the hub to it (held from here on, so the shuttles waiting here do
		# not all set off for it).
		_claim_pad(other)
		pad = other
		phase = Phase.OUTBOUND
		_route_to_gate()
		_routed = true
		status_changed.emit(self)
		return
	_hold()


## Routes to the gate of [member pad] from here.
func _route_to_gate() -> void:
	_gate = _gate_for(pad, position)
	_set_route(_gate, OUT_HEIGHT, OUT_HEIGHT)


## Both pads taken (or closed): wait beside the approach point.
func _hold() -> void:
	if phase == Phase.WAITING_PAD:
		return
	if _gate == Vector3.INF:
		_gate = _gate_for(pad, position)
	var p := _pad_local(pad)
	var d := Vector3(_gate.x - p.x, 0.0, _gate.z - p.z).normalized()
	var side := d.cross(Vector3.UP)
	var queue := 0
	for n in SystemWorld.nodes_in(self, GROUP):
		var s := n as CargoShuttle
		if s and s != self and not s.dead and s.phase == Phase.WAITING_PAD and s.pad == pad:
			queue += 1
	var spot := _gate + side * HOLD_SIDE + d * HOLD_SPACING * queue
	var pts: Array[ShipMover.Waypoint] = []
	pts.append(ShipMover.Waypoint.new(Vector3(spot.x, OUT_HEIGHT, spot.z), 20.0, true, -d, 3.0))
	mover.set_path(pts)
	phase = Phase.WAITING_PAD
	status_changed.emit(self)


func _fly_home() -> void:
	if not _enter_frame():
		return
	var frame := _frame()
	var berth := depot.berth_transform(slot_index)
	var line_up := frame.to_local(home.to_global(berth.origin + home.dock_outward() * 20.0))
	if not _routed:
		# Straight off the pad: out through the pad's gate on the way home.
		var via := Vector3.INF
		if pad >= 0 and SpaceNav.flat_distance(position, _pad_local(pad)) < GLIDE_RUN * 0.8:
			via = _gate_for(pad, line_up)
		_set_route(line_up, BACK_HEIGHT, line_up.y + DOCK_OVER, via)
		_routed = true
	_skip_passed()
	if not mover.path_done():
		return
	enter_home_frame()
	mover.set_path(_dock_path())
	phase = Phase.DOCKING
	status_changed.emit(self)


## Into the structures frame (from the outpost's frame, or from open space
## after a load). False without a frame.
func _enter_frame() -> bool:
	var frame := _frame()
	if frame == null:
		return false
	if get_parent() != frame:
		mover.change_frame(frame, false)
		_routed = false
	mover.max_speed = CRUISE_SPEED
	return true


## Ore goes into the player's stock now.
func _deliver() -> void:
	var n := cargo_total()
	if n > 0:
		# A forward station: the haulers keep their share (StationSupply).
		var supply := StationSupply.of(self)
		var landed := supply.take_hauling_fee(cargo) if supply else cargo
		Corps.economy(self).receive_cargo(landed, get_display_name())
		total_delivered += n
		show_toast("+%s" % load_text(), TOAST_DELIVERY)
		if is_instance_valid(home) and home.get_service() is SalvageYard:
			# Bought ore is held back from Factory auto-sell.
			var f := Factory.find(self)
			if f:
				f.market.hold(landed)
			# Ore the player bought: say that it arrived (mining loads land too often to log).
			EventLog.post("Ore bought from %s landed at the station: %s" % [home.display_name, load_text()], EventLog.Kind.INFO, self)
	if depot and is_instance_valid(depot):
		depot.note_shipped(cargo)
	cargo = Economy.zero_ore()
	supplies = true
	_update_cargo_look()


func _retire() -> void:
	_release_pad()
	dead = true
	if depot and is_instance_valid(depot):
		depot.remove_shuttle(self)
	remove_from_group(GROUP)
	remove_from_group(RTSCamera.FOCUS_GROUP)
	queue_free()


func _on_destroyed(killer: Node3D) -> void:
	var lost := cargo_total()
	var by := Combat.by_suffix(killer)
	EventLog.post("%s destroyed%s%s" % [get_display_name(), by, ", %s lost" % load_text() if lost > 0 else ""], EventLog.Kind.LOSS, null, global_position)
	_release_pad()
	if depot and is_instance_valid(depot):
		depot.remove_shuttle(self, true)


func _exit_tree() -> void:
	if is_queued_for_deletion():
		_release_pad()


# --- Pads and paths -------------------------------------------------------------

## The station's non-rotating structures frame (pads and outposts live in it).
func _frame() -> Node3D:
	var mgr := BuildingManager.of(self)
	return mgr.frame if mgr else null


func _station() -> HomeStation:
	var sys := SolarSystem.of(self)
	return sys.home_station.get_node_or_null(^"Station") as HomeStation if sys and sys.home_station else null


func _station_world() -> Vector3:
	var sys := SolarSystem.of(self)
	return sys.home_station.global_position if sys and sys.home_station else Vector3.INF


## Docking pads on this system's station (HomeStation.dock_pad_count).
func _pad_count() -> int:
	var st := _station()
	return st.dock_pad_count if st else HomeStation.DOCK_PAD_FALLBACK.size()


## Keep-out radius round the station hub (HomeStation.hub_clearance).
func _hub_clearance() -> float:
	var st := _station()
	return st.hub_clearance if st else HUB_CLEARANCE


## Pad [param index] in frame space (its origin).
func _pad_local(index: int) -> Vector3:
	var st := _station()
	var frame := _frame()
	if st == null or frame == null:
		return HomeStation.DOCK_PAD_FALLBACK[clampi(index, 0, HomeStation.DOCK_PAD_FALLBACK.size() - 1)]
	return frame.to_local(st.to_global(st.dock_pad(index)))


## Flat outward direction of pad [param index] from the station centre.
func _pad_dir(index: int) -> Vector3:
	var p := _pad_local(index)
	var d := Vector3(p.x, 0.0, p.z)
	return d.normalized() if d.length() > 0.5 else Vector3.RIGHT


## The pad with the shortest route to its approach point, a taken one
## counting [constant TAKEN_PAD_COST] extra. A free pad that is not the
## nearest is claimed at once, so it is still free when the shuttle gets
## round the hub to it.
func _pick_pad() -> int:
	var frame := _frame()
	if frame == null:
		return -1
	var here := frame.to_local(global_position)
	var best := 0
	var best_d := INF
	var nearest := 0
	var nearest_d := INF
	for i in _pad_count():
		var d := _route_length(here, _gate_for(i, here))
		if d < nearest_d:
			nearest_d = d
			nearest = i
		if _pad_taken(i):
			d += TAKEN_PAD_COST
		if d < best_d:
			best_d = d
			best = i
	if best != nearest:
		_claim_pad(best)
	return best


## Rough sim seconds until pad [param index] is free again (0 = free).
func _pad_free_in(index: int) -> float:
	if not _pad_taken(index):
		return 0.0
	var s := _pads[_pad_key(index)] as CargoShuttle
	match s.phase:
		Phase.LANDING:
			return LANDING_TIME * 0.5 + UNLOAD_TIME + LIFTOFF_TIME
		Phase.UNLOADING:
			return s._timer + LIFTOFF_TIME
		Phase.LIFTOFF:
			return LIFTOFF_TIME * 0.5
	# Claimed from afar, still on its way.
	return SpaceNav.flat_distance(s.position, _pad_local(index)) / ROUTE_ARC_SPEED + LANDING_TIME + UNLOAD_TIME + LIFTOFF_TIME


func _pad_taken(index: int) -> bool:
	var s: Variant = _pads.get(_pad_key(index))
	return s != null and is_instance_valid(s) and s != self and not (s as CargoShuttle).dead


func _claim_pad(index: int) -> bool:
	if index < 0 or _pad_taken(index):
		return false
	_pads[_pad_key(index)] = self
	return true


func _release_pad() -> void:
	if pad >= 0 and _pads.get(_pad_key(pad)) == self:
		_pads.erase(_pad_key(pad))


## [member _pads] key of pad [param index] at this system's station.
func _pad_key(index: int) -> String:
	if _pad_system.is_empty():
		var w := SystemWorld.of(self)
		_pad_system = w.system_id if w else ClusterNetwork.HOME_ID
	return "%s/%d" % [_pad_system, index]


## Frame-space waypoints through the gate and down onto the pad, nose to the hub.
func _landing_path() -> Array[ShipMover.Waypoint]:
	var p := _pad_local(pad)
	var d := _pad_dir(pad)
	# A hard turn at the gate is flown slower, so it does not swing wide.
	var a := Vector3(_gate.x - position.x, 0.0, _gate.z - position.z)
	var b := Vector3(p.x - _gate.x, 0.0, p.z - _gate.z)
	var turn := a.angle_to(b) if a.length() > 20.0 else 0.0
	var gate_speed := lerpf(GLIDE_SPEED, GATE_TURN_SPEED, clampf(turn / (PI * 0.5), 0.0, 1.0))
	var pts: Array[ShipMover.Waypoint] = []
	pts.append(ShipMover.Waypoint.new(Vector3(_gate.x, OUT_HEIGHT, _gate.z), gate_speed, false, Vector3.ZERO, 14.0))
	pts.append(ShipMover.Waypoint.new(Vector3(p.x, p.y + 9.0, p.z), GLIDE_SPEED, true, -d, 2.0, true))
	pts.append(ShipMover.Waypoint.new(p + Vector3.UP * PAD_HEIGHT, 3.0, true, -d, 0.6))
	return pts


## Off the pad, out a little and turn toward the way home (the route home
## takes over there).
func _liftoff_path() -> Array[ShipMover.Waypoint]:
	var p := _pad_local(pad)
	var d := _pad_dir(pad)
	var top := Vector3(p.x, p.y + 9.0, p.z)
	var face := d
	var frame := _frame()
	if frame and is_instance_valid(home) and depot and is_instance_valid(depot):
		var to := _gate_for(pad, frame.to_local(home.to_global(depot.berth_transform(slot_index).origin))) - (top + d * 25.0)
		to.y = 0.0
		if to.length() > 1.0:
			face = to.normalized()
	var pts: Array[ShipMover.Waypoint] = []
	pts.append(ShipMover.Waypoint.new(top, 4.0, true, -d, 1.0))
	pts.append(ShipMover.Waypoint.new(top + d * 25.0, 8.0, true, face, 3.0, true))
	return pts


# --- Route ----------------------------------------------------------------------

## Gate of pad [param index] for a shuttle coming from (or leaving for)
## [param from], frame space, at the pads' height: [constant GLIDE_RUN]
## from the pad (less when [param from] is nearer), toward [param from] but
## at most [constant GATE_SECTOR_DEG] off the pad's outward line.
func _gate_for(index: int, from: Vector3) -> Vector3:
	var p := _pad_local(index)
	var d := _pad_dir(index)
	var to := Vector3(from.x - p.x, 0.0, from.z - p.z)
	var dist := to.length()
	var dir := d
	if dist > 1.0:
		var lim := deg_to_rad(GATE_SECTOR_DEG)
		dir = d.rotated(Vector3.UP, clampf(d.signed_angle_to(to / dist, Vector3.UP), -lim, lim))
	return Vector3(p.x, p.y + 9.0, p.z) + dir * clampf(dist - 30.0, 40.0, GLIDE_RUN)


## Flies a route from here to [param goal] (frame space) at [param height]:
## fly-through waypoints round the hub, braking to rest at the goal at
## [param end_height] (the pad is taken, or the berth lined up, before it
## comes to a stop). A lower end height is reached on a glide down the last
## stretch. [param via]: a first point to fly through (INF = none).
func _set_route(goal: Vector3, height: float, end_height: float, via: Vector3 = Vector3.INF) -> void:
	var pts: PackedVector3Array
	if via == Vector3.INF:
		pts = _route(position, goal)
	else:
		pts = PackedVector3Array([Vector3(via.x, 0.0, via.z)])
		pts.append_array(_route(via, goal))
	# Speed limit on the way to each waypoint: what its circle allows, and
	# slow enough to brake for the goal in the route left after it.
	var speeds := PackedFloat32Array()
	speeds.resize(pts.size())
	var left := 0.0
	for i in range(pts.size() - 1, -1, -1):
		var cap := ROUTE_ARC_SPEED if pts[i].y <= 0.0 else minf(ROUTE_ARC_SPEED, sqrt(ROUTE_TURN_ACCEL * pts[i].y))
		speeds[i] = minf(cap, sqrt(2.0 * ROUTE_BRAKE * left) + 8.0)
		if i > 0:
			left += SpaceNav.flat_distance(pts[i], pts[i - 1])
	if via != Vector3.INF and pts.size() > 1:
		# The first point is a turn, not a circle: slower the harder the
		# turn, and slow enough to stop in the route left after it.
		var a := Vector3(pts[0].x - position.x, 0.0, pts[0].z - position.z)
		var b := Vector3(pts[1].x - pts[0].x, 0.0, pts[1].z - pts[0].z)
		var turn := a.angle_to(b) if a.length() > 1.0 and b.length() > 1.0 else 0.0
		var rest := 0.0
		for i in range(1, pts.size()):
			rest += SpaceNav.flat_distance(pts[i], pts[i - 1])
		speeds[0] = minf(lerpf(GLIDE_SPEED, GATE_TURN_SPEED, clampf(turn / (PI * 0.5), 0.0, 1.0)), sqrt(2.0 * ROUTE_BRAKE * 0.75 * rest))
	var wps: Array[ShipMover.Waypoint] = []
	var prev := position
	for i in pts.size():
		var p := Vector3(pts[i].x, height, pts[i].z)
		if i == pts.size() - 1:
			# Top of the descent: far enough out to lose the height on the slope.
			var run := (height - end_height) / CLIMB_SLOPE * 1.15 + 10.0
			var last := SpaceNav.flat_distance(prev, p)
			var glide := end_height < height - 1.0 and last > run + 20.0
			if glide:
				var back := (Vector3(prev.x, 0.0, prev.z) - Vector3(p.x, 0.0, p.z)).normalized()
				var top := p + back * run
				# Down to the glide speed by the top of the descent.
				var slow := (CRUISE_SPEED * CRUISE_SPEED - GLIDE_SPEED * GLIDE_SPEED) / (2.0 * ROUTE_BRAKE)
				if last - run > slow + 20.0:
					var q := top + back * slow
					wps.append(ShipMover.Waypoint.new(Vector3(q.x, height, q.z), CRUISE_SPEED, false, Vector3.ZERO, 12.0))
				wps.append(ShipMover.Waypoint.new(Vector3(top.x, height, top.z), GLIDE_SPEED, false, Vector3.ZERO, 12.0))
			wps.append(ShipMover.Waypoint.new(Vector3(p.x, end_height, p.z), GLIDE_SPEED if glide else CRUISE_SPEED, true, Vector3.ZERO, 4.0))
			break
		# A long leg into a slow stretch: full speed until the braking starts.
		var brake := (CRUISE_SPEED * CRUISE_SPEED - speeds[i] * speeds[i]) / (2.0 * ROUTE_BRAKE)
		var leg := SpaceNav.flat_distance(prev, p)
		if leg > brake + 20.0:
			var q := p + (Vector3(prev.x, 0.0, prev.z) - Vector3(p.x, 0.0, p.z)).normalized() * brake
			wps.append(ShipMover.Waypoint.new(Vector3(q.x, height, q.z), CRUISE_SPEED, false, Vector3.ZERO, 12.0))
		wps.append(ShipMover.Waypoint.new(p, speeds[i], false, Vector3.ZERO, 12.0))
		prev = p
	mover.set_path(wps)


## Drops route waypoints already passed (the shuttle is beyond them along
## the next leg), so a wide swing round a keep-out never turns back for one.
func _skip_passed() -> void:
	var path := mover.path
	var n := 0
	while n < path.size() - 1:
		var a := path[n].pos
		var b := path[n + 1].pos
		if Vector2(position.x - a.x, position.z - a.z).dot(Vector2(b.x - a.x, b.z - a.z)) <= 0.0:
			break
		n += 1
	if n > 0:
		var rest: Array[ShipMover.Waypoint] = path.slice(n)
		mover.set_path(rest)


## Flat length of [method _route] from [param from] to [param to], m.
func _route_length(from: Vector3, to: Vector3) -> float:
	var total := 0.0
	var prev := from
	for p in _route(from, to):
		total += SpaceNav.flat_distance(prev, p)
		prev = p
	return total


## Keep-out circles in frame space: Vector3(x, z, radius).
func _keepouts() -> PackedVector3Array:
	var out := PackedVector3Array()
	var frame := _frame()
	var st := _station_world()
	if frame and st != Vector3.INF:
		var c := frame.to_local(st)
		out.append(Vector3(c.x, c.z, _hub_clearance()))
	return out


## Flat frame-space route from [param from] to [param to]: the waypoints
## after [param from], ending at [param to] (y = radius of the keep-out
## circle a waypoint goes round, 0 = none). Straight where clear; a leg
## that cuts a keep-out circle goes round it the shorter way (tangent, arc,
## tangent), [constant ROUTE_MAX_DEPTH] circles deep. Circles holding
## either end are ignored.
func _route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var circles := _keepouts()
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	var skip: Array[int] = []
	for i in circles.size():
		var c := Vector2(circles[i].x, circles[i].y)
		if a.distance_to(c) < circles[i].z or b.distance_to(c) < circles[i].z:
			skip.append(i)
	_route_into(out, a, b, circles, skip, 0)
	return out


func _route_into(out: PackedVector3Array, a: Vector2, b: Vector2, circles: PackedVector3Array, skip: Array[int], depth: int) -> void:
	var hit := -1
	var best := INF
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 1e-6)
	for i in circles.size():
		if skip.has(i):
			continue
		var c := Vector2(circles[i].x, circles[i].y)
		var t := clampf((c - a).dot(ab) / len2, 0.0, 1.0)
		if (a + ab * t).distance_to(c) < circles[i].z and t < best:
			best = t
			hit = i
	if hit < 0 or depth >= ROUTE_MAX_DEPTH:
		out.append(Vector3(b.x, 0.0, b.y))
		return
	var c := Vector2(circles[hit].x, circles[hit].y)
	var r := circles[hit].z * ROUTE_SLACK
	var da := maxf(a.distance_to(c), r * 1.001)
	var db := maxf(b.distance_to(c), r * 1.001)
	var pa := (a - c).angle()
	var pb := (b - c).angle()
	var al := acos(r / da)
	var be := acos(r / db)
	# The shorter way round: tangent, arc, tangent.
	var side := 1.0
	var sweep := INF
	for s: float in [1.0, -1.0]:
		var w := fposmod(s * ((pb - s * be) - (pa + s * al)), TAU)
		if w < sweep:
			sweep = w
			side = s
	var th0 := pa + side * al
	var sub: Array[int] = skip.duplicate()
	sub.append(hit)
	_route_into(out, a, c + Vector2.from_angle(th0) * r, circles, sub, depth + 1)
	out[out.size() - 1].y = r
	var n := maxi(ceili(sweep / ROUTE_ARC_STEP), 1)
	for k in range(1, n + 1):
		var p := c + Vector2.from_angle(th0 + side * sweep * float(k) / float(n)) * r
		out.append(Vector3(p.x, r, p.y))
	_route_into(out, c + Vector2.from_angle(th0 + side * sweep) * r, b, circles, sub, depth + 1)


## Building-space waypoints out of the berth, then up clear of the roof
## while turning on the spot toward the route to the pad (it takes over there).
func _undock_path() -> Array[ShipMover.Waypoint]:
	var berth := depot.berth_transform(slot_index)
	var out := home.dock_outward()
	var exit := berth.origin + out * 18.0
	var pts: Array[ShipMover.Waypoint] = []
	pts.append(ShipMover.Waypoint.new(exit, 8.0, false, out, 3.0))
	var frame := _frame()
	if frame and pad >= 0:
		var from := frame.to_local(home.to_global(exit))
		var route := _route(from, _gate_for(pad, from))
		var to := home.to_local(frame.to_global(Vector3(route[0].x, from.y, route[0].z))) - exit
		to.y = 0.0
		if to.length() > 1.0:
			pts.append(ShipMover.Waypoint.new(exit + out * 4.0 + Vector3.UP * DOCK_OVER, 4.0, true, to.normalized(), 2.0, true))
	return pts


## Sink to the berth's height outside it while turning nose-out, then back in.
func _dock_path() -> Array[ShipMover.Waypoint]:
	var berth := depot.berth_transform(slot_index)
	var out := home.dock_outward()
	var pts: Array[ShipMover.Waypoint] = []
	pts.append(ShipMover.Waypoint.new(berth.origin + out * 20.0, 14.0, true, out, 2.5, true))
	pts.append(ShipMover.Waypoint.new(berth.origin, 3.0, true, out, 0.6))
	return pts


# --- Visuals ------------------------------------------------------------------

func _update_cargo_look() -> void:
	if _cargo_node == null:
		return
	_cargo_node.visible = is_loaded()
	_cargo_node.scale = _cargo_scale * (SUPPLY_SCALE if supplies and cargo_total() == 0 else Vector3.ONE)

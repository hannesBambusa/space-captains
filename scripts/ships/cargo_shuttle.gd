class_name CargoShuttle
extends Ship
## A small cargo shuttle without a captain, owned by an outpost's
## [CargoDepot]. It replaces the old corridors: goods fly between the
## outposts and the Home Station.
##
## Trip: parked beside its outpost's apron (CargoDepot.berth_transform) it
## loads once the depot has a load ready, backs out of the berth, flies in
## open space to the approach point off a station docking pad
## (HomeStation.dock_pad; the world-frame flight uses ShipMover / NavRoute /
## SpaceNav like every ship, so it routes round the station hub, planets and
## belts, and may warp where the rules allow), takes the pad (one shuttle per
## pad, the others hold at the approach point), descends onto it in the
## station's "Structures" frame, unloads (the ore is credited to the player
## now, Economy.receive_cargo) and flies back with supplies (cosmetic). The
## "cargo_containers" mesh shows only while carrying something (smaller for
## supplies).
##
## Raiders can shoot it while it flies in open space (to the station and
## back); docked, loading or on the pads it is safe. Hits raise the colony
## alarm (ColonyAlarm); destroyed, the ore aboard is lost and the depot
## sends a new shuttle. While the station is disabled (StructureHull) its
## pads are closed: shuttles wait at the approach point.
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
## Pad approach point and line-up distance from the station centre, m.
const PAD_APPROACH := 230.0
const PAD_LINE_UP := 95.0
## Resting height above a pad's origin, m.
const PAD_HEIGHT := 2.3
## Flat distance to an approach point where the shuttle changes frame, and
## the most relative speed it may carry into the frame's path, m and m/s.
## The last leg near the station is flown as a frame path: open-space
## routing round the hub would keep it circling the approach point.
const HANDOFF_DISTANCE := 60.0
const HANDOFF_SPEED := 80.0
const HANDOFF_HEIGHT := 20.0
## Supply-run cargo look: container scale.
const SUPPLY_SCALE := Vector3(1.0, 0.55, 0.6)

## Docking pad index -> the shuttle holding it.
static var _pads: Dictionary = {}

var depot: CargoDepot
var phase: Phase = Phase.PARKED
## Aboard: iron, titanium, crystal.
var cargo := Economy.zero_ore()
## Carrying supplies (cosmetic).
var supplies: bool = false
## Docking pad in use or headed for (-1 = none).
var pad: int = -1
var number: int = 1
## Closest flat distance to the station centre during open-space flight, m.
var min_station_distance: float = INF
## Units delivered to the station by this shuttle.
var total_delivered: int = 0

var _timer: float = 0.0
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


## Only in open space (see the class notes).
func is_targetable() -> bool:
	return not dead and is_inside_tree() and mover.avoid_enabled and phase in [Phase.OUTBOUND, Phase.WAITING_PAD, Phase.RETURNING]


func take_hit(amount: float, attacker: Node3D, at: Vector3) -> void:
	super.take_hit(amount, attacker, at)
	if not dead:
		ColonyAlarm.raise(self, self, "a cargo shuttle of %s" % home.display_name if is_instance_valid(home) else "a cargo shuttle", attacker)


## Warp hops follow the usual rules (never near the station or structures).
func can_warp() -> bool:
	return mover.avoid_enabled


## Short cruise arcs on the open-space legs (the highway rule splits the
## traffic to and from the station by a few dozen metres).
func cruise_free() -> bool:
	return phase == Phase.OUTBOUND or phase == Phase.RETURNING


func cruise_band() -> Vector3:
	return Vector3(18.0, 40.0, 900.0)


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
	if mover.avoid_enabled:
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
				mover.set_path(_undock_path())
				phase = Phase.UNDOCKING
				status_changed.emit(self)
		Phase.UNDOCKING:
			if mover.path_done():
				enter_space()
				pad = _pick_pad()
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
				enter_space()
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
	var frame := _frame()
	if frame == null or pad < 0:
		pad = _pick_pad()
		return
	var d := _pad_dir(pad)
	var goal := frame.to_global(d * PAD_APPROACH)
	var vel := SpaceNav.world_velocity(frame)
	mover.max_speed = CRUISE_SPEED + vel.length()
	set_world_goal(goal, vel, Vector3.ZERO, 20.0, CRUISE_SPEED)
	if not _handoff_ready(goal):
		return
	var mgr := BuildingManager.of(self)
	if mgr and mgr.station_hull and mgr.station_hull.disabled:
		if phase != Phase.WAITING_PAD:
			phase = Phase.WAITING_PAD
			status_changed.emit(self)
		return
	if not _claim_pad(pad):
		var other := 1 - pad
		if _claim_pad(other):
			pad = other
		else:
			if phase != Phase.WAITING_PAD:
				phase = Phase.WAITING_PAD
				status_changed.emit(self)
			return
	mover.max_speed = CRUISE_SPEED
	mover.change_frame(frame, false)
	mover.set_path(_landing_path())
	phase = Phase.LANDING
	status_changed.emit(self)


func _fly_home() -> void:
	var goal := home.to_global(home.approach_point())
	var vel := SpaceNav.world_velocity(home)
	mover.max_speed = CRUISE_SPEED + vel.length()
	set_world_goal(goal, vel, Vector3.ZERO, 20.0, CRUISE_SPEED)
	if not _handoff_ready(goal):
		return
	mover.max_speed = CRUISE_SPEED
	enter_home_frame()
	mover.set_path(_dock_path())
	phase = Phase.DOCKING
	status_changed.emit(self)


## Close enough to [param goal] (world) for the frame to take over: on the
## plane, in height (the complex rides an inclined orbit) and in speed.
func _handoff_ready(goal: Vector3) -> bool:
	return SpaceNav.flat_distance(global_position, goal) <= HANDOFF_DISTANCE \
			and absf(global_position.y - goal.y) <= HANDOFF_HEIGHT and mover.relative_speed() <= HANDOFF_SPEED


## Ore goes into the player's stock now.
func _deliver() -> void:
	var n := cargo_total()
	if n > 0:
		Economy.receive_cargo(cargo, get_display_name())
		total_delivered += n
		show_toast("+%s" % load_text(), TOAST_DELIVERY)
		if is_instance_valid(home) and home.get_service() is SalvageYard:
			# Bought ore is held back from Factory auto-sell.
			var f := Factory.find(self)
			if f:
				f.market.hold(cargo)
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


## Pad [param index] in frame space (its origin).
func _pad_local(index: int) -> Vector3:
	var st := _station()
	var frame := _frame()
	if st == null or frame == null:
		return HomeStation.DOCK_PAD_FALLBACK[index]
	return frame.to_local(st.to_global(st.dock_pad(index)))


## Flat outward direction of pad [param index] from the station centre.
func _pad_dir(index: int) -> Vector3:
	var p := _pad_local(index)
	var d := Vector3(p.x, 0.0, p.z)
	return d.normalized() if d.length() > 0.5 else Vector3.RIGHT


## The free pad nearest this shuttle (or the nearest when both are taken).
func _pick_pad() -> int:
	var frame := _frame()
	if frame == null:
		return -1
	var here := frame.to_local(global_position)
	var best := 0
	var best_d := INF
	for i in HomeStation.DOCK_PAD_FALLBACK.size():
		var d := Vector2(here.x, here.z).distance_to(Vector2(_pad_dir(i).x, _pad_dir(i).z) * PAD_APPROACH)
		if _pad_taken(i):
			d += 100000.0
		if d < best_d:
			best_d = d
			best = i
	return best


func _pad_taken(index: int) -> bool:
	var s: Variant = _pads.get(index)
	return s != null and is_instance_valid(s) and s != self and not (s as CargoShuttle).dead


func _claim_pad(index: int) -> bool:
	if index < 0 or _pad_taken(index):
		return false
	_pads[index] = self
	return true


func _release_pad() -> void:
	if pad >= 0 and _pads.get(pad) == self:
		_pads.erase(pad)


## Frame-space waypoints from the approach point onto the pad, nose to the hub.
func _landing_path() -> Array[ShipMover.Waypoint]:
	var p := _pad_local(pad)
	var d := _pad_dir(pad)
	var pts: Array[ShipMover.Waypoint] = []
	pts.append(ShipMover.Waypoint.new(d * PAD_LINE_UP + Vector3.UP * (p.y + 9.0), 25.0, false, -d, 6.0))
	pts.append(ShipMover.Waypoint.new(Vector3(p.x, p.y + 9.0, p.z), 10.0, true, -d, 2.0, true))
	pts.append(ShipMover.Waypoint.new(p + Vector3.UP * PAD_HEIGHT, 3.0, true, -d, 0.6))
	return pts


## Off the pad, turn round, out to the approach point.
func _liftoff_path() -> Array[ShipMover.Waypoint]:
	var p := _pad_local(pad)
	var d := _pad_dir(pad)
	var pts: Array[ShipMover.Waypoint] = []
	pts.append(ShipMover.Waypoint.new(Vector3(p.x, p.y + 9.0, p.z), 4.0, true, -d, 1.0))
	pts.append(ShipMover.Waypoint.new(Vector3(p.x, p.y + 9.0, p.z) + d * 25.0, 8.0, true, d, 3.0, true))
	pts.append(ShipMover.Waypoint.new(d * PAD_APPROACH, 35.0, false, Vector3.ZERO, 12.0))
	return pts


## Building-space waypoints from the berth out past the approach point.
func _undock_path() -> Array[ShipMover.Waypoint]:
	var berth := depot.berth_transform(slot_index)
	var out := home.dock_outward()
	var pts: Array[ShipMover.Waypoint] = []
	pts.append(ShipMover.Waypoint.new(berth.origin + out * 18.0, 8.0, false, out, 3.0))
	pts.append(ShipMover.Waypoint.new(home.approach_point() + out * 40.0, 40.0, false, Vector3.ZERO, 12.0))
	return pts


## Line up outside the berth nose-out, then back in.
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

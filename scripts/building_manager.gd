class_name BuildingManager
extends Node
## Owns the player's buildings. They live in a non-rotating frame
## ("Structures") under the home station's orbiter, so they keep their offset
## from the station as it orbits and do not spin with it.
##
## Build zone: within [member zone_radius] of the station, clear of the
## station hub and of other footprints, and clear of the host planet over the
## whole orbit (the frame does not rotate, so an offset of length d sweeps
## distances |orbit - d| .. orbit + d from the planet). On top of that every
## structure links to the station complex by a corridor ([member links],
## CorridorNetwork), which decides the link range and the building's yaw.
##
## The Factory ([member factory_def]) is there from the start: placed at
## [member factory_offset] with its corridor as if the player had built it,
## counted like any structure (link range, overlaps), but not in the build
## menu and never built again (max 1).

signal building_added(building: Building)
signal building_changed(building: Building)

const GROUP := "building_manager"

@export var solar_system_path: NodePath = ^"../SolarSystem"
## Buildable defs, one build menu button each.
@export var building_defs: Array[BuildingDef] = []
## Pre-built at game start (not buildable). Null = none.
@export var factory_def: BuildingDef
## Frame-local offset of the Factory: out of the way of the spots near the
## station, its dock mouth turned away from the complex.
@export var factory_offset: Vector3 = Vector3(-138.0, 0.0, -40.0)
@export var zone_radius: float = 3000.0
## Keep-out radius around the station hub.
@export var station_clearance: float = 75.0
## Extra gap kept from the host planet's surface.
@export var planet_margin: float = 60.0

var solar_system: SolarSystem
var frame: Node3D
var buildings: Array[Building] = []
## Corridors joining the station and its structures (created with the frame).
var links: CorridorNetwork
var rng := RandomNumberGenerator.new()
## The start Factory building (null without [member factory_def]).
var factory_building: Building

var _counts: Dictionary = {}


func _ready() -> void:
	add_to_group(GROUP)
	rng.randomize()
	solar_system = get_node_or_null(solar_system_path) as SolarSystem
	if solar_system == null:
		push_warning("BuildingManager: no SolarSystem at %s" % solar_system_path)
		return
	if solar_system.home_station:
		_make_frame()
	else:
		solar_system.built.connect(_make_frame, CONNECT_ONE_SHOT)


func has_zone() -> bool:
	return frame != null


## World position on the plane -> frame-local offset from the station.
func to_local_offset(world_pos: Vector3) -> Vector3:
	var p := frame.to_local(world_pos)
	p.y = 0.0
	return p


func to_world(local_offset: Vector3) -> Vector3:
	return frame.to_global(local_offset)


## Host planet of the station and the station's orbit radius around it.
func get_host_planet() -> PlanetBody:
	if solar_system == null or solar_system.home_station == null:
		return null
	return solar_system.home_station.get_parent() as PlanetBody


## Forbidden band of offset lengths from the station (host planet sweep),
## as Vector2(min, max). Vector2.ZERO when there is no host planet.
func planet_band(footprint: float) -> Vector2:
	var host := get_host_planet()
	if host == null:
		return Vector2.ZERO
	var orbit := solar_system.home_station.orbit_radius
	var reach := host.def.radius + footprint + planet_margin
	return Vector2(maxf(orbit - reach, 0.0), orbit + reach)


## "" when [param def] fits at frame-local [param offset], else the reason.
func placement_problem(def: BuildingDef, offset: Vector3, check_cost: bool = true) -> String:
	if frame == null:
		return "No home station"
	return plan_placement(def, offset, check_cost).problem


## The corridor link for [param def] at [param offset] (yaw included), with
## [member CorridorNetwork.Plan.problem] set to the first reason it cannot be
## built there: count limit, zone, station, planet band, overlap, link, cost.
## NAN [param fixed_yaw] lets the link choose the yaw.
func plan_placement(def: BuildingDef, offset: Vector3, check_cost: bool = true, fixed_yaw: float = NAN) -> CorridorNetwork.Plan:
	var p := links.plan(def, offset, fixed_yaw) if links else CorridorNetwork.Plan.new()
	var base := _base_problem(def, offset)
	if not base.is_empty():
		p.problem = base
	elif p.is_valid() and check_cost and not Economy.can_afford(def.cost_credits, def.cost_ore()):
		p.problem = Economy.shortfall_text(def.cost_credits, def.cost_ore())
	return p


func _base_problem(def: BuildingDef, offset: Vector3) -> String:
	if frame == null:
		return "No home station"
	var limit := limit_reason(def)
	if not limit.is_empty():
		return limit
	var d := Vector2(offset.x, offset.z).length()
	if d > zone_radius - def.footprint_radius:
		return "Outside the build zone (%.1f km from the station)" % (zone_radius / 1000.0)
	if d < station_clearance + def.footprint_radius:
		return "Too close to the station"
	var band := planet_band(def.footprint_radius)
	if band != Vector2.ZERO and d > band.x and d < band.y:
		return "Orbit path crosses %s" % get_host_planet().def.name
	for b in buildings:
		var bd := Vector2(b.position.x - offset.x, b.position.z - offset.z).length()
		if bd < b.def.footprint_radius + def.footprint_radius:
			return "Overlaps %s" % b.display_name
	return ""


## Buildings of [param def]'s type the player owns.
func count_of(def: BuildingDef) -> int:
	var n := 0
	for b in buildings:
		if is_instance_valid(b) and b.def.id == def.id:
			n += 1
	return n


## "" unless the player already owns the most allowed of this type.
func limit_reason(def: BuildingDef) -> String:
	if def.max_count > 0 and count_of(def) >= def.max_count:
		return "Only %d %s allowed" % [def.max_count, def.display_name if def.max_count == 1 else UIUtil.plural(def.display_name)]
	return ""


## First active building of [param def_id], or null.
func find_active(def_id: StringName) -> Building:
	for b in buildings:
		if is_instance_valid(b) and b.def.id == def_id and b.is_active():
			return b
	return null


## Pays for and places a building at frame-local [param offset], with its
## corridor. NAN [param yaw] = the link turns it (docking mouth away from the
## complex). Null when the spot is invalid or the cost cannot be paid.
func place(def: BuildingDef, offset: Vector3, yaw: float = NAN) -> Building:
	var p := plan_placement(def, offset, true, yaw)
	if not p.is_valid():
		return null
	if not Economy.spend(def.cost_credits, def.cost_ore()):
		return null
	var b := _spawn(def, offset, p.yaw)
	links.commit(p, b)
	return b


## Places without cost or zone checks and finishes construction at once.
## Used by the demos and tests. Links a corridor when one fits: with
## [param yaw] if possible, else turned the way the link wants.
func spawn_finished(def: BuildingDef, offset: Vector3, yaw: float = 0.0) -> Building:
	var p: CorridorNetwork.Plan = null
	if links:
		p = links.plan(def, offset, yaw)
		if not p.is_valid():
			p = links.plan(def, offset)
			if p.is_valid():
				yaw = p.yaw
	var b := _spawn(def, offset, yaw)
	if p and p.is_valid():
		links.commit(p, b)
	b.finish_construction()
	return b


## Removes a building and its corridors.
func remove_building(b: Building) -> void:
	if not buildings.has(b):
		return
	buildings.erase(b)
	if links:
		links.remove_building(b)
	b.queue_free()


## The Factory service of the start Factory, or null.
func get_factory() -> Factory:
	return factory_building.get_service() as Factory if is_instance_valid(factory_building) else null


## [param label] "" = "<name> <n>".
func _spawn(def: BuildingDef, offset: Vector3, yaw: float, label: String = "") -> Building:
	var n: int = _counts.get(def.id, 0) + 1
	_counts[def.id] = n
	var b := Building.new()
	b.setup(def, label if not label.is_empty() else "%s %d" % [def.display_name, n], SimClock.time)
	b.captain_rng = rng
	b.position = Vector3(offset.x, 0.0, offset.z)
	b.rotation.y = yaw
	frame.add_child(b)
	buildings.append(b)
	b.state_changed.connect(_on_building_changed)
	b.hires_changed.connect(_on_building_changed)
	b.tree_exiting.connect(_on_building_exiting.bind(b))
	if links:
		links.add_building(b)
	building_added.emit(b)
	return b


func _on_building_changed(b: Building) -> void:
	building_changed.emit(b)


## A building freed some other way still loses its corridors.
func _on_building_exiting(b: Building) -> void:
	if b.is_queued_for_deletion():
		buildings.erase(b)
		if links:
			links.remove_building(b)


func _make_frame() -> void:
	frame = Node3D.new()
	frame.name = "Structures"
	# The station orbiter only translates, never rotates, so a plain child keeps
	# a fixed orientation while following the orbit.
	solar_system.home_station.add_child(frame)
	links = CorridorNetwork.new()
	links.name = "Corridors"
	frame.add_child(links)
	links.setup(solar_system.home_station.get_node_or_null(^"Station") as HomeStation)
	_spawn_factory()


## The start Factory with its corridor, finished. The link turns its dock
## mouth away from the station.
func _spawn_factory() -> void:
	if factory_def == null:
		return
	var p := links.plan(factory_def, factory_offset)
	if not p.is_valid():
		push_warning("BuildingManager: Factory link at %s: %s" % [factory_offset, p.problem])
	factory_building = _spawn(factory_def, factory_offset, p.yaw, factory_def.display_name)
	if p.has_link:
		links.commit(p, factory_building)
	factory_building.finish_construction()

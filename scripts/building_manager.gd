class_name BuildingManager
extends Node
## Owns the player's buildings. They live in a non-rotating frame
## ("Structures") under the home station's orbiter, so they keep their offset
## from the station as it orbits and do not spin with it.
##
## Build zone: within [member zone_radius] of the station, clear of the
## station hub and of other footprints, and clear of the host planet over the
## whole orbit (the frame does not rotate, so an offset of length d sweeps
## distances |orbit - d| .. orbit + d from the planet), and clear of every
## moon's orbit sweep ([method moon_sweeping]). Structures are not
## joined by corridors: cargo shuttles (CargoDepot, CargoShuttle) fly the
## goods between the outposts and the station. Placement rules
## ([method plan_placement]): clear of the station keep-outs
## ([member keepouts]: a disc round the hub plus the addon bay and solar wing
## strips), [member min_gap] clear of every other footprint, and docking
## lanes (dock mouth out past the approach point) clear of the keep-outs and
## of other footprints. The docking mouth turns away from the station; a
## structure without one (turrets, the shield generator) turns its back port
## (link_point) toward it.
##
## Station addons (BuildingDef.station_addon) skip all of that: they sit on
## one of the station core's [constant BAY_COUNT] addon bays ([method
## bay_transform]), one building per bay. The Factory
## ([member factory_def]) is the default addon, installed finished in bay 1
## at the start; it is not in the build menu and never built again (max 1).

signal building_added(building: Building)
signal building_changed(building: Building)
## A structure was added or removed (the shield bubble refits).
signal layout_changed

const GROUP := "building_manager"
## Addon bays on the Home Station core, numbered 1..BAY_COUNT.
const BAY_COUNT := 6
## Bay empties in the station model: "addon_bay_1".."addon_bay_6".
const BAY_NODE := "addon_bay_%d"

@export var solar_system_path: NodePath = ^"../SolarSystem"
## Buildable defs, one build menu button each.
@export var building_defs: Array[BuildingDef] = []
## Station addon installed finished in bay 1 at game start (not buildable). Null = none.
@export var factory_def: BuildingDef
@export_group("Addon bays")
## Fallback bay ring used while the station model has no "addon_bay_N"
## empties: radius from the station centre, m, and the angle of bay 1, degrees.
@export var bay_radius: float = 47.0
@export var bay_angle_offset_deg: float = 255.0
@export_group("")
@export var zone_radius: float = 3000.0
## Keep-out radius around the station hub.
## Covers the addons on the station bays (~92 m) and the solar wings (~87 m).
@export var station_clearance: float = 100.0
## Extra gap kept from the host planet's surface.
@export var planet_margin: float = 60.0
## Extra gap kept from a moon's surface along its whole orbit, m.
@export var moon_margin: float = 80.0
@export_group("Spacing")
## Minimum clear gap between the footprint edges of any two structures, m
## (BuildingDef.min_gap can lower it for small ones).
@export var min_gap: float = 25.0
## Station edge used for the complex bounds (shield bubble), m.
@export var station_radius: float = 95.0
## Half width of a docking lane (dock point out past the approach point), m.
@export var lane_half_width: float = 12.0
## Docking lane reach past the spawn point (Building.approach_distance + exit), m.
@export var lane_reach: float = 80.0
## Hull of the Home Station itself (StructureHull): raiders can shoot it;
## at 0 its docking pads close until it is repaired.
@export var station_hull_points: float = 5000.0
@export_group("Station keep-outs")
## One strip per addon bay along the bay's +Z and one per solar wing. Lengths
## and half widths in m.
@export var bay_keepout_length: float = 46.0
@export var bay_keepout_half_width: float = 15.0
## Solar wing directions (station space, on the plane) and their radial span.
@export var solar_wing_dirs: PackedVector3Array = PackedVector3Array([Vector3(0.7071, 0.0, 0.7071), Vector3(-0.7071, 0.0, -0.7071)])
@export var solar_wing_span: Vector2 = Vector2(53.0, 88.0)
@export var solar_wing_half_width: float = 15.0
@export_group("")


## Result of [method plan_placement]: [member problem] is "" when valid.
class Plan:
	extends RefCounted
	var problem := ""
	var yaw := 0.0

	func is_valid() -> bool:
		return problem.is_empty()


## Per model: docking mouth and lane (model space).
class ModelInfo:
	extends RefCounted
	## Docking mouth outward direction (ZERO = no docking mouth).
	var mouth := Vector3.ZERO
	var lane_a := Vector3.ZERO
	var lane_b := Vector3.ZERO
	## Models without a docking mouth: direction of their back port
	## (link_point empty), model space. It turns toward the station.
	var link := Vector3.ZERO

var solar_system: SolarSystem
var frame: Node3D
var buildings: Array[Building] = []
## Station keep-outs (created with the frame).
var keepouts: StationKeepouts
## The station's own hull (created with the frame).
var station_hull: StructureHull
var rng := RandomNumberGenerator.new()
var _counts: Dictionary = {}
## Bay number -> the addon Building in it.
var _bays: Dictionary = {}
var _infos: Dictionary = {}


static func of(tree: SceneTree) -> BuildingManager:
	return tree.get_first_node_in_group(GROUP) as BuildingManager if tree else null


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


## Station orbit samples for [method moon_sweeping].
const MOON_SWEEP_STEPS := 360


## A moon of the host planet whose sphere (its reach plus
## [member moon_margin]) passes within [param reach] metres of frame-local
## [param pos] at some point, or null. The frame does not rotate, so over
## time the spot meets every phase of the moon's (inclined) orbit: the
## test is the 3D distance from the spot to the moon's orbit circle, at
## every point of the station's own orbit.
func moon_sweeping(pos: Vector3, reach: float) -> PlanetBody:
	var host := get_host_planet()
	if host == null:
		return null
	var st := solar_system.home_station
	for c in host.get_children():
		var moon := c as PlanetBody
		if moon == null or moon.def == null:
			continue
		var r := SpaceNav.body_reach(moon.def) + reach + moon_margin
		var n := (moon.orbit_basis * Vector3.UP).normalized()
		# A moon on the station's period keeps its phase to the station: only
		# its actual position at each station angle matters, not the whole ring.
		var locked := is_equal_approx(moon.orbit_period, st.orbit_period)
		var phase := moon.orbit_angle(0.0) - st.orbit_angle(0.0)
		for i in MOON_SWEEP_STEPS:
			var a := TAU * float(i) / float(MOON_SWEEP_STEPS)
			# The spot relative to the planet, with the station at angle a.
			var p := st.orbit_point(a) + pos
			if locked:
				var m := moon.orbit_point(a + phase)
				if p.distance_to(m) < r:
					return moon
				continue
			var h := p.dot(n)
			var q := p - n * h
			if Vector2(q.length() - moon.orbit_radius, h).length() < r:
				return moon
	return null


# --- Station addon bays ---------------------------------------------------------

## Frame-local transform of addon bay [param bay] (1..BAY_COUNT): origin at
## the bay collar's outer face, +Z radially outward, +Y up. From the
## station model's "addon_bay_N" empty, or the computed fallback ring.
func bay_transform(bay: int) -> Transform3D:
	var station := solar_system.home_station.get_node_or_null(^"Station") as HomeStation if solar_system and solar_system.home_station else null
	var model := station.get_model() if station else null
	var n := model.find_child(BAY_NODE % bay, true, false) as Node3D if model else null
	if n and frame:
		# Both hang off the station orbiter: relative transforms work in or out of the tree.
		var xf := frame.transform.affine_inverse() * ModelLoader.relative_transform(solar_system.home_station, n)
		xf.basis = xf.basis.orthonormalized()
		return xf
	var a := deg_to_rad(bay_angle_offset_deg + 360.0 / BAY_COUNT * (bay - 1))
	var basis := Basis(Vector3.UP, a)
	return Transform3D(basis, basis.z * bay_radius)


## The addon in [param bay], or null.
func addon_in_bay(bay: int) -> Building:
	var b: Variant = _bays.get(bay)
	return b as Building if is_instance_valid(b) else null


## Bay numbers with no addon, ascending.
func free_bays() -> Array[int]:
	var out: Array[int] = []
	for i in range(1, BAY_COUNT + 1):
		if addon_in_bay(i) == null:
			out.append(i)
	return out


func used_bays() -> int:
	return BAY_COUNT - free_bays().size()


## "" when [param def] can go onto some free bay (cost aside), else the reason.
func addon_block_reason(def: BuildingDef) -> String:
	if frame == null:
		return "No home station"
	var limit := limit_reason(def)
	if not limit.is_empty():
		return limit
	if free_bays().is_empty():
		return "No free addon bay"
	return ""


## "" when [param def] can be installed in [param bay] now, else the reason.
func addon_problem(def: BuildingDef, bay: int, check_cost: bool = true) -> String:
	if not def.station_addon:
		return "Not a station addon"
	var why := addon_block_reason(def)
	if not why.is_empty():
		return why
	if bay < 1 or bay > BAY_COUNT:
		return "No such addon bay"
	if addon_in_bay(bay):
		return "Bay %d holds the %s" % [bay, addon_in_bay(bay).display_name]
	if check_cost:
		return Economy.shortfall_text(def.cost_credits, def.cost_ore())
	return ""


## Pays for [param def] and starts building it on [param bay]. With
## [param finished] it is free and done at once (start Factory, demos,
## tests). Null when the bay is taken or the cost cannot be paid.
func install_addon(def: BuildingDef, bay: int, finished: bool = false, label: String = "") -> Building:
	if not addon_problem(def, bay, not finished).is_empty():
		return null
	if not finished and not Economy.spend(def.cost_credits, def.cost_ore()):
		return null
	var b := _spawn(def, Vector3.ZERO, 0.0, label, bay)
	if finished:
		b.finish_construction()
	return b


## Takes an addon off its bay.
func remove_addon(b: Building) -> void:
	remove_building(b)


## "" when [param def] fits at frame-local [param offset], else the reason.
func placement_problem(def: BuildingDef, offset: Vector3, check_cost: bool = true) -> String:
	if frame == null:
		return "No home station"
	return plan_placement(def, offset, check_cost).problem


## Yaw for [param def] at [param offset], with [member Plan.problem] set to
## the first reason it cannot be built there: count limit, zone, station
## keep-outs, planet band, overlap, gap, docking lanes, cost. NAN
## [param fixed_yaw] = turn it the default way (see the class notes).
func plan_placement(def: BuildingDef, offset: Vector3, check_cost: bool = true, fixed_yaw: float = NAN) -> Plan:
	var p := Plan.new()
	if def.station_addon:
		p.problem = "Install it on a station addon bay"
		return p
	var pos := StationKeepouts.flat(offset)
	p.yaw = fixed_yaw if not is_nan(fixed_yaw) else default_yaw(def, pos)
	p.problem = _base_problem(def, pos, p.yaw)
	if p.is_valid() and check_cost and not Economy.can_afford(def.cost_credits, def.cost_ore()):
		p.problem = Economy.shortfall_text(def.cost_credits, def.cost_ore())
	return p


## Docking mouth away from the station; no mouth: back port toward it.
func default_yaw(def: BuildingDef, pos: Vector3) -> float:
	var info := model_info(def)
	var d := StationKeepouts.flat(pos)
	if d.length() < 0.5:
		return 0.0
	d = d.normalized()
	if info.mouth != Vector3.ZERO:
		return _yaw_facing(info.mouth, d)
	if info.link != Vector3.ZERO:
		return _yaw_facing(info.link, -d)
	return 0.0


## Clear gap [param def] keeps to other structures, m.
func gap_for(def: BuildingDef) -> float:
	return def.min_gap if def.min_gap >= 0.0 else min_gap


func _base_problem(def: BuildingDef, pos: Vector3, yaw: float) -> String:
	if frame == null:
		return "No home station"
	var limit := limit_reason(def)
	if not limit.is_empty():
		return limit
	var r := def.footprint_radius
	var d := SpaceNav.flat_length(pos)
	if d > zone_radius - r:
		return "Outside the build zone (%.1f km from the station)" % (zone_radius / 1000.0)
	if d < station_clearance + r:
		return "Too close to the station"
	if keepouts:
		var k := keepouts.spot_problem(pos, r)
		if not k.is_empty():
			return k
	var band := planet_band(r)
	if band != Vector2.ZERO and d > band.x and d < band.y:
		return "Orbit path crosses %s" % get_host_planet().def.name
	# Structures with a docking mouth keep their docking lane clear too.
	var moon := moon_sweeping(pos, r + (lane_reach if model_info(def).mouth != Vector3.ZERO else 0.0))
	if moon:
		return "%s's orbit sweeps through here" % moon.def.name
	var gap := gap_for(def)
	var p2 := StationKeepouts.v2(pos)
	for b in buildings:
		if not is_instance_valid(b) or b.def.station_addon:
			continue
		var bd := p2.distance_to(StationKeepouts.v2(b.position))
		if bd < b.def.footprint_radius + r:
			return "Overlaps %s" % b.display_name
		if bd - b.def.footprint_radius - r < minf(gap, gap_for(b.def)):
			return "Too close to %s" % b.display_name
	for b in buildings:
		if not is_instance_valid(b) or b.def.station_addon:
			continue
		var lane := lane_of(b.def, b.position, b.rotation.y)
		if not lane.is_empty() and StationKeepouts.seg_point(StationKeepouts.v2(lane[0]), StationKeepouts.v2(lane[1]), p2) < r + lane_half_width:
			return "Blocks the docking lane of %s" % b.display_name
	var own := lane_of(def, pos, yaw)
	if not own.is_empty():
		if keepouts:
			var k := keepouts.lane_problem(own[0], own[1], lane_half_width)
			if not k.is_empty():
				return k
		for b in buildings:
			if not is_instance_valid(b) or b.def.station_addon:
				continue
			if StationKeepouts.seg_point(StationKeepouts.v2(own[0]), StationKeepouts.v2(own[1]), StationKeepouts.v2(b.position)) < b.def.footprint_radius + lane_half_width:
				return "Docking lane blocked by %s" % b.display_name
	return ""


## Docking lane of [param def] at [param pos] turned by [param yaw]: [a, b]
## frame-local, or empty without a docking mouth.
func lane_of(def: BuildingDef, pos: Vector3, yaw: float) -> Array[Vector3]:
	var info := model_info(def)
	var out: Array[Vector3] = []
	if info.mouth == Vector3.ZERO:
		return out
	var c := StationKeepouts.flat(pos)
	out.append(c + info.lane_a.rotated(Vector3.UP, yaw))
	out.append(c + info.lane_b.rotated(Vector3.UP, yaw))
	return out


## Docking mouth and lane of [param def]'s model (cached per model).
func model_info(def: BuildingDef) -> ModelInfo:
	var has_file := not def.model_path.is_empty() and ResourceLoader.exists(def.model_path)
	var key := def.model_path if has_file else "placeholder:%s" % def.footprint_radius
	if _infos.has(key):
		return _infos[key]
	var model := ModelLoader.instantiate(def.model_path, ModelLoader.building_placeholder.bind(def.footprint_radius))
	var info := ModelInfo.new()
	# Same rules as Building._dock() / _dock_outward() / _spawn().
	var dock := Vector3(def.footprint_radius, 0.0, 0.0)
	var out := Vector3.ZERO
	var dock_node := model.find_child("dock_point", true, false) as Node3D
	if dock_node:
		var xf := ModelLoader.relative_transform(model, dock_node)
		dock = xf.origin
		out = -xf.basis.z
		if SpaceNav.flat_length(out) < 0.1:
			out = dock
	out.y = 0.0
	out = out.normalized() if out.length() > 0.01 else Vector3.RIGHT
	var spawn_node := model.find_child("spawn_point", true, false) as Node3D
	var spawn := ModelLoader.relative_transform(model, spawn_node).origin if spawn_node else dock + out * 18.0
	info.mouth = out
	info.lane_a = StationKeepouts.flat(dock)
	info.lane_b = StationKeepouts.flat(spawn) + out * lane_reach
	if dock_node == null:
		# No docking mouth (turrets, the shield generator): no lane.
		info.mouth = Vector3.ZERO
		var link_node := model.find_child("link_point", true, false) as Node3D
		var lp := StationKeepouts.flat(ModelLoader.relative_transform(model, link_node).origin) if link_node else Vector3.ZERO
		if lp.length() > 0.5:
			info.link = lp.normalized()
	model.free()
	_infos[key] = info
	return info


## Yaw that turns model-space [param dir_model] onto [param dir].
static func _yaw_facing(dir_model: Vector3, dir: Vector3) -> float:
	if dir_model == Vector3.ZERO:
		return 0.0
	return atan2(dir.x, dir.z) - atan2(dir_model.x, dir_model.z)


## Plane rectangle (frame-local x, z) covering the station and every
## structure that is part of the complex (not standalone, not an addon).
func complex_bounds() -> Rect2:
	var box := Rect2(-station_radius, -station_radius, station_radius * 2.0, station_radius * 2.0)
	for b in complex_structures():
		var r := b.def.footprint_radius
		box = box.merge(Rect2(b.position.x - r, b.position.z - r, r * 2.0, r * 2.0))
	return box


## Structures on the plane that count toward the complex (shield bubble,
## build view): not standalone, not station addons.
func complex_structures() -> Array[Building]:
	var out: Array[Building] = []
	for b in buildings:
		if is_instance_valid(b) and not b.def.station_addon and not b.def.standalone and not b.is_queued_for_deletion():
			out.append(b)
	return out


## Buildings of [param def]'s type the player owns.
func count_of(def: BuildingDef) -> int:
	var n := 0
	for b in buildings:
		if is_instance_valid(b) and b.def.id == def.id:
			n += 1
	return n


## "" unless the player already owns the most allowed of this type, the
## type still needs research (Research), or it is not in service yet.
func limit_reason(def: BuildingDef) -> String:
	var locked := Research.building_lock_reason(def.id)
	if not locked.is_empty():
		return locked
	if not def.in_service:
		return "Not in service yet: the %s comes in a later update" % def.display_name
	if def.max_count > 0 and count_of(def) >= def.max_count:
		return "Only %d %s allowed" % [def.max_count, def.display_name if def.max_count == 1 else Fmt.plural(def.display_name)]
	return ""


## First active building of [param def_id], or null.
func find_active(def_id: StringName) -> Building:
	for b in buildings:
		if is_instance_valid(b) and b.def.id == def_id and b.is_active():
			return b
	return null


## Pays for and places a building at frame-local [param offset]. NAN
## [param yaw] = the default turn (docking mouth away from the station).
## Null when the spot is invalid or the cost cannot be paid.
func place(def: BuildingDef, offset: Vector3, yaw: float = NAN) -> Building:
	var p := plan_placement(def, offset, true, yaw)
	if not p.is_valid():
		return null
	if not Economy.spend(def.cost_credits, def.cost_ore()):
		return null
	return _spawn(def, offset, p.yaw)


## Places without cost or zone checks and finishes construction at once.
## Used by the demos and tests. NAN [param yaw] = the default turn.
func spawn_finished(def: BuildingDef, offset: Vector3, yaw: float = NAN) -> Building:
	if def.station_addon:
		var bays := free_bays()
		return install_addon(def, bays[0], true) if not bays.is_empty() else null
	if is_nan(yaw):
		yaw = default_yaw(def, offset)
	var b := _spawn(def, offset, yaw)
	b.finish_construction()
	return b


## Removes a building.
func remove_building(b: Building) -> void:
	if not buildings.has(b):
		return
	buildings.erase(b)
	_free_bay(b)
	b.queue_free()
	layout_changed.emit()


## [param label] "" = "<name> <n>". [param bay] > 0 = a station addon on that
## bay ([param offset] and [param yaw] unused).
func _spawn(def: BuildingDef, offset: Vector3, yaw: float, label: String = "", bay: int = 0) -> Building:
	var n: int = _counts.get(def.id, 0) + 1
	_counts[def.id] = n
	var b := Building.new()
	b.setup(def, label if not label.is_empty() else "%s %d" % [def.display_name, n], SimClock.time)
	b.captain_rng = rng
	if bay > 0:
		b.bay = bay
		b.transform = bay_transform(bay)
		_bays[bay] = b
	else:
		b.position = Vector3(offset.x, 0.0, offset.z)
		b.rotation.y = yaw
	frame.add_child(b)
	buildings.append(b)
	b.state_changed.connect(_on_building_changed)
	b.hires_changed.connect(_on_building_changed)
	b.tree_exiting.connect(_on_building_exiting.bind(b))
	building_added.emit(b)
	layout_changed.emit()
	return b


func _on_building_changed(b: Building) -> void:
	building_changed.emit(b)


## A building freed some other way still leaves the list.
func _on_building_exiting(b: Building) -> void:
	if b.is_queued_for_deletion() and buildings.has(b):
		buildings.erase(b)
		_free_bay(b)
		layout_changed.emit()


func _make_frame() -> void:
	frame = Node3D.new()
	frame.name = "Structures"
	# The station orbiter only translates, never rotates, so a plain child keeps
	# a fixed orientation while following the orbit.
	solar_system.home_station.add_child(frame)
	keepouts = StationKeepouts.build(solar_system.home_station.get_node_or_null(^"Station") as HomeStation, station_clearance,
			bay_keepout_length, bay_keepout_half_width, solar_wing_dirs, solar_wing_span, solar_wing_half_width)
	if station_hull_points > 0.0:
		station_hull = StructureHull.new()
		station_hull.setup("Home Station", station_hull_points, 45.0, 6.0)
		frame.add_child(station_hull)
	_install_factory()


## The default addon (the Factory), finished in bay 1.
func _install_factory() -> void:
	if factory_def == null:
		return
	if install_addon(factory_def, 1, true, factory_def.display_name) == null:
		push_warning("BuildingManager: could not install %s in bay 1" % factory_def.display_name)


func _free_bay(b: Building) -> void:
	if b.bay > 0 and _bays.get(b.bay) == b:
		_bays.erase(b.bay)


# --- Save ---------------------------------------------------------------------

func save_state() -> Dictionary:
	var list := []
	for b in buildings:
		if is_instance_valid(b) and not b.is_queued_for_deletion():
			list.append(b.save_state())
	var d := {"counts": _counts, "rng": SaveUtil.rng_state(rng), "buildings": list}
	if station_hull:
		d["station_hull"] = station_hull.save_state()
	return d


## The def with [param id] (buildable ones and the Factory), or null.
func def_by_id(id: StringName) -> BuildingDef:
	if factory_def and factory_def.id == id:
		return factory_def
	for d in building_defs:
		if d and d.id == id:
			return d
	return null


## Rebuilds every saved building (the start Factory is reused when the save
## has it in the same bay, else removed). Registers each under its save id.
func load_state(d: Dictionary, refs: SaveRefs) -> void:
	var kept: Array[Building] = []
	for s: Dictionary in d.get("buildings", []):
		var def := def_by_id(StringName(s["def"]))
		if def == null:
			push_warning("BuildingManager: unknown building '%s' in the save" % s["def"])
			continue
		var bay := int(s.get("bay", 0))
		var b := addon_in_bay(bay) if bay > 0 else null
		if b == null or b.def.id != def.id or kept.has(b):
			b = _spawn(def, s["offset"] as Vector3, float(s["yaw"]), String(s["label"]), bay)
		refs.add(int(s["id"]), b)
		b.load_state(s, refs)
		kept.append(b)
	for b in buildings.duplicate():
		if not kept.has(b):
			remove_building(b)
	_counts = (d.get("counts", {}) as Dictionary).duplicate()
	SaveUtil.set_rng(rng, d.get("rng", {}))
	if station_hull and d.has("station_hull"):
		station_hull.load_state(d["station_hull"], refs)

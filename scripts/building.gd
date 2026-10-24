class_name Building
extends Node3D
## A placed building. Built from a BuildingDef: instances the model (or a
## placeholder), shows the construction look and a progress bar for
## def.build_time sim seconds, then becomes active and focusable.
## Buildings with hire options spawn ships for hired captains (the def's
## ship script: MinerShip, MercenaryShip, SalvagerShip). Lost ships free
## their berth.
##
## Stage 3: a captain who ejected keeps the berth: their pod lands here
## ([method receive_pod]) and they wait ([member waiting]) until their wallet
## buys a new ship ([member BuildingDef.ship_cost]) or the player pays for one
## ([method buy_replacement]). [method adopt] gives an existing captain a ship
## here (career switch). Ship sales pay [constant SHIP_SALE_SHARE] back to the
## player. Station addons (BuildingDef.station_addon: Factory, Outfitter)
## are Buildings too, placed on a station bay ([member bay]). Defs with a
## service script (the Outfitter) get that node as a child
## ([method get_service]). Defs with BuildingDef.max_shuttles get a
## [CargoDepot] ([method get_cargo_depot]): deliveries wait there and cargo
## shuttles fly them to the station.

signal state_changed(building: Building)
signal hires_changed(building: Building)

enum State { CONSTRUCTING, ACTIVE }

const CONSTRUCTION_SHADER: Shader = preload("res://shaders/construction.gdshader")
const BAR_SHADER: Shader = preload("res://shaders/screen_bar.gdshader")
const RENDER_LAYER := 2
## Share of a captain-bought ship's price that comes back to the player.
const SHIP_SALE_SHARE := 0.5
## Waiting captains check their wallet this often, sim seconds.
const WAIT_CHECK_INTERVAL := 2.0

## Camera distance when focusing this building.
@export var focus_distance: float = 380.0
## Berths: the first [member inner_berths] sit side by side inside the hangar,
## [member berth_depth] metres in from the dock point; the rest wait beside the
## apron, [member outer_berth_side] metres to either side of the hangar axis.
@export var inner_berths: int = 2
@export var berth_spacing: float = 8.8
@export var berth_depth: float = 11.0
@export var outer_berth_side: float = 17.0
@export var outer_berth_height: float = 2.0
@export var outer_berth_step: float = 12.0
## Approach point distance out from the spawn point, metres.
@export var approach_distance: float = 60.0
## Construction progress bar size on screen, pixels.
@export var bar_size_px: Vector2 = Vector2(84.0, 8.0)

var def: BuildingDef
var display_name: String = ""
var state: State = State.CONSTRUCTING
## SimClock.time when construction started.
var started_at: float = 0.0
var captains: Array[Captain] = []
var ships: Array[Ship] = []
## Captains back from an ejection, waiting here for a new ship.
var waiting: Array[Captain] = []
## Shared by all buildings unless the manager hands out its own.
var captain_rng: RandomNumberGenerator
## Station addon bay (1..BuildingManager.BAY_COUNT) this addon sits in, 0 = not an addon.
var bay: int = 0

var _model: Node3D
var _construction_mat: ShaderMaterial
var _bar: MeshInstance3D
var _bar_mat: ShaderMaterial
var _model_box: AABB
var _service: Node
var _depot: CargoDepot
var _unload_fx: OutpostUnloadFx
var _wait_timer := 0.0


## Call before adding to the tree.
func setup(building_def: BuildingDef, label: String, start_time: float) -> void:
	def = building_def
	display_name = label
	started_at = start_time
	if def.inner_berths >= 0:
		inner_berths = def.inner_berths
	if def.berth_spacing > 0.0:
		berth_spacing = def.berth_spacing
	if def.berth_depth > 0.0:
		berth_depth = def.berth_depth
	if def.outer_berth_side > 0.0:
		outer_berth_side = def.outer_berth_side
	outer_berth_step = def.outer_berth_step
	name = StringName(label.validate_node_name().replace(" ", ""))


func _ready() -> void:
	add_to_group(SimStepper.GROUP)
	_model = def.instantiate_model()
	add_child(_model)
	ModelLoader.dim_emission(_model)
	MeshUtil.set_layers_recursive(_model, RENDER_LAYER)
	_model_box = ModelLoader.local_aabb(_model)
	_make_bar()
	if def.service_script:
		_service = def.service_script.new() as Node
		if _service:
			_service.name = "Service"
			add_child(_service)
			if _service.has_method(&"setup"):
				_service.call(&"setup", self)
	if def.max_shuttles > 0:
		_depot = CargoDepot.new()
		_depot.name = "CargoDepot"
		_depot.setup(self)
		add_child(_depot)
	if state == State.CONSTRUCTING:
		_apply_construction_look(true)
		_update_construction()
	else:
		_activate()
	# After the construction look: it clears material overrides.
	if _model.find_child("unload_arm", true, false):
		_unload_fx = OutpostUnloadFx.new()
		_unload_fx.name = "UnloadFx"
		add_child(_unload_fx)
		_unload_fx.setup(self, _model)


func _process(delta: float) -> void:
	if state == State.CONSTRUCTING:
		_update_construction()
	if not SimClock.paused:
		sim_step(delta * SimClock.speed)


## Waiting captains buy a ship as soon as their wallet allows.
func sim_step(dt: float) -> void:
	if waiting.is_empty() or dt <= 0.0:
		return
	_wait_timer -= dt
	if _wait_timer > 0.0:
		return
	_wait_timer = WAIT_CHECK_INTERVAL
	for c in waiting.duplicate():
		c.update_traits()
		if c.wallet >= def.ship_cost and is_active():
			buy_replacement(c, false)


## The unloading look (Mining Outpost) or null.
func get_unload_fx() -> OutpostUnloadFx:
	return _unload_fx


## The cargo depot (outposts with shuttles) or null.
func get_cargo_depot() -> CargoDepot:
	return _depot


## The service node (Outfitter) or null.
func get_service() -> Node:
	return _service


## The instanced model (or its placeholder).
func get_model() -> Node3D:
	return _model


## Centre of the model on its base plane, building space. Addons extend
## outward from their attach point, so picking and the selection ring use
## this instead of the origin.
func local_center() -> Vector3:
	if bay <= 0 or _model == null:
		return Vector3.ZERO
	var c := _model_box.get_center()
	return Vector3(c.x, 0.0, c.z)


## [method local_center] in world space.
func pick_center() -> Vector3:
	return global_transform * local_center()


func get_progress() -> float:
	if state == State.ACTIVE:
		return 1.0
	return clampf((SimClock.time - started_at) / maxf(def.build_time, 0.001), 0.0, 1.0)


func is_active() -> bool:
	return state == State.ACTIVE


func get_status_text() -> String:
	if state == State.CONSTRUCTING:
		return "Constructing %d%%" % int(get_progress() * 100.0)
	if _service is DefenseStructure:
		return (_service as DefenseStructure).get_status_text()
	var n := repairing_count()
	return "Active, repairing %d" % n if n > 0 else "Active"


## Docked ships being repaired now.
func repairing_count() -> int:
	var n := 0
	for s in ships:
		if is_instance_valid(s) and s.repairing:
			n += 1
	return n


## Skips the rest of construction.
func finish_construction() -> void:
	if state == State.CONSTRUCTING:
		started_at = SimClock.time - def.build_time
		if is_inside_tree():
			_update_construction()
		else:
			state = State.ACTIVE


## Puts the building (back) under construction at [param progress] (0..1).
## Used by demos and tests.
func set_construction_progress(progress: float) -> void:
	started_at = SimClock.time - def.build_time * clampf(progress, 0.0, 0.999)
	if state == State.ACTIVE:
		state = State.CONSTRUCTING
		remove_from_group(RTSCamera.FOCUS_GROUP)
		if is_inside_tree():
			_apply_construction_look(true)
			_bar.visible = true
		state_changed.emit(self)
	if is_inside_tree():
		_update_construction()


# --- Hiring -------------------------------------------------------------------

func can_hire_more() -> bool:
	return def.can_hire() and captains.size() < def.max_hires


## Why hiring is not possible right now, or "".
func hire_block_reason() -> String:
	if not def.can_hire():
		return "This building does not hire captains"
	if state != State.ACTIVE:
		return "Finish construction first"
	if captains.size() >= def.max_hires:
		return "All %d berths are taken" % def.max_hires
	return Economy.shortfall_text(def.hire_cost_credits)


## Pays the hire cost and spawns a ship with a new captain. Null on failure.
## [param personality] >= 0 forces the captain's personality (demos, tests).
func hire(personality: int = -1) -> Ship:
	if not hire_block_reason().is_empty():
		return null
	if not Economy.spend(def.hire_cost_credits):
		return null
	if captain_rng == null:
		captain_rng = RandomNumberGenerator.new()
		captain_rng.randomize()
	var captain := Captain.generate(captain_rng, def.hire_role, personality)
	captain.add_history("Hired as a %s at %s" % [def.hire_role.to_lower(), display_name])
	captains.append(captain)
	return _spawn_ship(captain)


## Gives [param captain] (hired elsewhere, e.g. a career switch) a new ship
## here. Null when every berth is taken.
func adopt(captain: Captain) -> Ship:
	if not captains.has(captain):
		if captains.size() >= def.max_hires:
			return null
		captains.append(captain)
	waiting.erase(captain)
	return _spawn_ship(captain)


func _spawn_ship(captain: Captain) -> Ship:
	var ship: Ship = def.hire_ship_script.new() as Ship if def.hire_ship_script else MinerShip.new()
	ship.setup_ship(captain, def.hire_ship_path, self, _free_berth())
	ship.position = get_point("spawn_point", Vector3(0.0, 0.0, def.footprint_radius))
	ship.rotation.y = ShipMover.yaw_for(-_dock_outward())
	add_child(ship)
	# Fly in from the spawn point to the berth.
	ship.mover.set_path(dock_path(ship.slot_index, true))
	ships.append(ship)
	hires_changed.emit(self)
	return ship


## A hired ship was lost or retired: its berth is freed, and its captain
## too unless [param keep_captain] (ejected: the pod is on its way).
func remove_ship(ship: Ship, keep_captain: bool = false) -> void:
	if not ships.has(ship):
		return
	ships.erase(ship)
	if not keep_captain:
		captains.erase(ship.captain)
	hires_changed.emit(self)


## An escape pod landed: its captain waits here for a new ship.
func receive_pod(captain: Captain) -> void:
	if captain == null:
		return
	if not captains.has(captain):
		captains.append(captain)
	if not waiting.has(captain):
		waiting.append(captain)
	captain.stranded = true
	EventLog.post("%s is back at %s and needs a new ship (%s cr)" % [captain.captain_name, display_name, UIUtil.amount(def.ship_cost)], EventLog.Kind.INFO, self)
	hires_changed.emit(self)


## The captain died (pod shot down): the berth is free.
func forget_captain(captain: Captain) -> void:
	captains.erase(captain)
	waiting.erase(captain)
	hires_changed.emit(self)


## Why [param captain] cannot get a replacement ship now, or "".
## [param player_pays] = from the player's credits, else the captain's wallet.
func replacement_block_reason(captain: Captain, player_pays: bool) -> String:
	if not waiting.has(captain):
		return "Not waiting for a ship"
	if not is_active():
		return "Finish construction first"
	if player_pays:
		return Economy.shortfall_text(def.ship_cost)
	if captain.wallet < def.ship_cost:
		return "Wallet %s of %s cr" % [UIUtil.amount(captain.wallet), UIUtil.amount(def.ship_cost)]
	return ""


## A new ship for a waiting captain. Paid by the player or from the
## captain's wallet (then part of the price comes back as income).
func buy_replacement(captain: Captain, player_pays: bool) -> Ship:
	if not replacement_block_reason(captain, player_pays).is_empty():
		return null
	if player_pays:
		if not Economy.spend(def.ship_cost):
			return null
	else:
		captain.wallet -= def.ship_cost
		Economy.add_income(roundi(def.ship_cost * SHIP_SALE_SHARE), "Ship sales")
	captain.add_history("New %s from %s" % ["ship paid by the station" if player_pays else "ship bought", display_name])
	var ship := adopt(captain)
	EventLog.post("%s is flying again (%s)" % [captain.captain_name, "station paid" if player_pays else "bought a ship for %s cr" % UIUtil.amount(def.ship_cost)],
			EventLog.Kind.INFO, ship)
	return ship


## Local position of a named empty in the model, or [param fallback].
func get_point(point_name: String, fallback: Vector3) -> Vector3:
	var n := _model.find_child(point_name, true, false) as Node3D if _model else null
	if n == null:
		return fallback
	return global_transform.affine_inverse() * n.global_position if is_inside_tree() else fallback


# --- Berths and docking paths (building space) ----------------------------------

## Berth [param index]: origin = where the ship rests, -Z = its nose (facing out).
func berth_transform(index: int) -> Transform3D:
	var dock := _dock()
	var out := _dock_outward()
	var side := out.cross(Vector3.UP)
	var p: Vector3
	if index < inner_berths:
		var row := float(index) - (float(mini(inner_berths, maxi(def.max_hires, 1))) - 1.0) * 0.5
		p = dock - out * berth_depth + side * row * berth_spacing
		p.y = dock.y
	else:
		var k := index - inner_berths
		var sgn := -1.0 if k % 2 == 0 else 1.0
		var spawn := _spawn()
		p = spawn - out * 8.0 + side * sgn * (outer_berth_side + outer_berth_step * floorf(k / 2.0))
		p.y = dock.y + outer_berth_height
	return Transform3D(Basis.looking_at(out, Vector3.UP), p)


## Point ships fly to before docking: out past the spawn point.
func approach_point() -> Vector3:
	return _spawn() + _dock_outward() * approach_distance


## Waypoints into berth [param index]: line up outside, turn nose-out, back in.
func dock_path(index: int, from_spawn: bool = false) -> Array[ShipMover.Waypoint]:
	var out := _dock_outward()
	var berth := berth_transform(index).origin
	var line_up := berth + out * (_spawn() - berth).dot(out)
	line_up.y = berth.y
	var pts: Array[ShipMover.Waypoint] = []
	if not from_spawn:
		pts.append(ShipMover.Waypoint.new(approach_point(), 45.0, false, Vector3.ZERO, 14.0))
	pts.append(ShipMover.Waypoint.new(line_up, 16.0, true, out, 2.5, true))
	if index < inner_berths:
		var mouth := berth + out * (_dock() - berth).dot(out)
		mouth.y = berth.y
		pts.append(ShipMover.Waypoint.new(mouth, 6.0, false, out, 2.0))
	pts.append(ShipMover.Waypoint.new(berth, 4.0, true, out, 0.6))
	return pts


## Waypoints from berth [param index] out past the approach point.
func undock_path(index: int) -> Array[ShipMover.Waypoint]:
	var out := _dock_outward()
	var berth := berth_transform(index).origin
	var pts: Array[ShipMover.Waypoint] = []
	if index < inner_berths:
		var mouth := berth + out * (_dock() - berth).dot(out)
		mouth.y = berth.y
		pts.append(ShipMover.Waypoint.new(mouth, 8.0, false, out, 2.0))
	var line_up := berth + out * (_spawn() - berth).dot(out)
	line_up.y = 0.0
	pts.append(ShipMover.Waypoint.new(line_up, 18.0, false, out, 3.0))
	var exit := approach_point() + out * 40.0
	pts.append(ShipMover.Waypoint.new(exit, 60.0, false, Vector3.ZERO, 12.0))
	return pts


## Direction ships leave the dock, building space (see [method _dock_outward]).
func dock_outward() -> Vector3:
	return _dock_outward()


## Spawn point just outside the dock mouth, building space.
func spawn_local() -> Vector3:
	return _spawn()


func _dock() -> Vector3:
	return get_point("dock_point", Vector3(def.footprint_radius, 0.0, 0.0))


func _spawn() -> Vector3:
	return get_point("spawn_point", _dock() + _dock_outward() * 18.0)


func _free_berth() -> int:
	for i in maxi(def.max_hires, 1):
		var used := false
		for s in ships:
			if is_instance_valid(s) and s.slot_index == i:
				used = true
				break
		if not used:
			return i
	return ships.size()


## Direction (building space, on the plane) ships leave the dock: the dock
## empty's -Z, or straight away from the centre when it has no rotation info.
func _dock_outward() -> Vector3:
	var n := _model.find_child("dock_point", true, false) as Node3D if _model else null
	var out := Vector3.ZERO
	if n and is_inside_tree():
		out = global_transform.basis.inverse() * -n.global_basis.z
	if Vector2(out.x, out.z).length() < 0.1 and n:
		out = get_point("dock_point", Vector3.RIGHT)
	out.y = 0.0
	return out.normalized() if out.length() > 0.01 else Vector3.RIGHT


# --- Construction -------------------------------------------------------------

func _update_construction() -> void:
	var p := get_progress()
	_bar_mat.set_shader_parameter("progress", p)
	var lo := _model_box.position.y
	var hi := _model_box.end.y
	_construction_mat.set_shader_parameter("fill_y", global_position.y + lerpf(lo - 0.5, hi + 0.5, p))
	if p >= 1.0:
		_activate()
		state_changed.emit(self)


func _activate() -> void:
	state = State.ACTIVE
	_apply_construction_look(false)
	if _bar:
		_bar.visible = false
	set_meta(&"focus_radius", def.footprint_radius)
	set_meta(&"focus_distance", focus_distance)
	add_to_group(RTSCamera.FOCUS_GROUP)


func _apply_construction_look(on: bool) -> void:
	if on and _construction_mat == null:
		_construction_mat = ShaderMaterial.new()
		_construction_mat.shader = CONSTRUCTION_SHADER
		_construction_mat.set_shader_parameter("grid_size", maxf(def.footprint_radius / 12.0, 1.0))
	for mi in ModelLoader.meshes_of(_model):
		mi.material_override = _construction_mat if on else null
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _make_bar() -> void:
	_bar = MeshInstance3D.new()
	_bar.name = "ProgressBar"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_bar.mesh = quad
	_bar.custom_aabb = AABB(Vector3.ONE * -def.footprint_radius, Vector3.ONE * def.footprint_radius * 2.0)
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar_mat = ShaderMaterial.new()
	_bar_mat.shader = BAR_SHADER
	_bar_mat.render_priority = 20
	# Set explicitly: the shader's vertex-stage uniform defaults did not apply.
	_bar_mat.set_shader_parameter("size_px", bar_size_px)
	_bar_mat.set_shader_parameter("offset_px", Vector2(0.0, 46.0))
	_bar_mat.set_shader_parameter("progress", 0.0)
	_bar_mat.set_shader_parameter("fill_color", Color(1.0, 0.6, 0.24))
	_bar_mat.set_shader_parameter("back_color", Color(0.03, 0.05, 0.08, 0.85))
	_bar_mat.set_shader_parameter("border_color", Color(0.75, 0.82, 0.9, 0.7))
	_bar.material_override = _bar_mat
	_bar.position = local_center() + Vector3(0.0, _model_box.end.y + 4.0, 0.0)
	add_child(_bar)


# --- Save ---------------------------------------------------------------------

## Placement, construction, berths (captains by save id) and the service
## and cargo depot state. Ships are saved on their own (ShipCodec).
func save_state() -> Dictionary:
	var caps := []
	for c in captains:
		caps.append(SaveIds.of(c))
	var wait := []
	for c in waiting:
		wait.append(SaveIds.of(c))
	var d := {"id": SaveIds.of(self), "def": def.id, "label": display_name, "bay": bay, "offset": position, "yaw": rotation.y,
			"active": is_active(), "started_at": started_at, "captains": caps, "waiting": wait, "wait_timer": _wait_timer}
	if _service and _service.has_method(&"save_state"):
		d["service"] = _service.call(&"save_state")
	if _depot:
		d["depot"] = _depot.save_state()
	return d


## Construction and berths; call once the captains exist. The service and
## depot state come later ([method load_services]), after the ships.
func load_state(d: Dictionary, refs: SaveRefs) -> void:
	display_name = String(d.get("label", display_name))
	if bool(d.get("active", true)):
		finish_construction()
	else:
		set_construction_progress(0.0)
		started_at = float(d.get("started_at", SimClock.time))
		_update_construction()
	captains.clear()
	for id: int in d.get("captains", []):
		var c := refs.captain(id)
		if c:
			captains.append(c)
	waiting.clear()
	for id: int in d.get("waiting", []):
		var c := refs.captain(id)
		if c:
			waiting.append(c)
	_wait_timer = float(d.get("wait_timer", 0.0))
	hires_changed.emit(self)


func load_services(d: Dictionary, refs: SaveRefs) -> void:
	if _service and _service.has_method(&"load_state") and d.has("service"):
		_service.call(&"load_state", d["service"], refs)
	if _depot and d.has("depot"):
		_depot.load_state(d["depot"], refs)


## Puts a loaded ship back: in its berth ([param docked]) or under the space
## root. The ship must be set up (setup_ship, loadout) and not in the tree.
func restore_ship(ship: Ship, docked: bool) -> void:
	if docked:
		var berth := berth_transform(ship.slot_index)
		ship.position = berth.origin
		ship.rotation.y = ShipMover.yaw_for(-berth.basis.z)
		add_child(ship)
		ship.snap_to_slot()
	else:
		SpaceNav.space_root(get_tree()).add_child(ship)
		ship.mover.avoid_enabled = true
	if not ships.has(ship):
		ships.append(ship)
	hires_changed.emit(self)

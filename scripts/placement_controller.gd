class_name PlacementController
extends Node3D
## Build placement. [method arm] flies the camera to a build view of the
## station complex (follows the Home Station, fairly top-down, distance that
## fits the complex plus [member build_reach]) and shows a translucent ghost
## of the building under the cursor (green = valid, red = invalid) and the
## area its centre may go (outside the station keep-outs and the other
## footprints' gaps, inside the build zone). The ghost turns the default way
## (BuildingManager.default_yaw: docking mouth away from the station). A
## structure with a BuildingDef.preview_range (defense turrets) also shows
## that range ring.
##
## Station addons (BuildingDef.station_addon) use bay-pick mode instead: a
## faint ghost of the addon and a ring on every free station bay
## (BuildingManager.free_bays); the bay nearest the cursor lights up (green
## or red with the reason) and a click installs it there
## (BuildingManager.install_addon). The view frames the station.
##
## A left click (press and release within [member click_slop_px], no camera
## orbit) places, Shift keeps placing; a left drag orbits the camera and
## scroll or pinch zooms as usual. Right-click or Escape cancels. The camera
## stays where it is on cancel or confirm. Mouse events over UI never reach
## here (_unhandled_input), and the ghost hides while the cursor is over a panel.

signal armed_changed(def: BuildingDef)
signal validity_changed(valid: bool, reason: String)
signal placed(building: Building)

const GROUP := "placement_controller"
const VALID_COLOR := Color(0.35, 1.0, 0.55)
const INVALID_COLOR := Color(1.0, 0.32, 0.26)
const ZONE_COLOR := Color(0.45, 0.85, 1.0)
const ZONE_SHADER: Shader = preload("res://shaders/placement_zone.gdshader")
const MAX_ZONE_DISCS := 48
const MAX_ZONE_SEGS := 64

## Max mouse travel (px) between press and release that still counts as a click.
@export var click_slop_px: float = 3.0
@export_group("Build view")
## Camera tilt for placing, degrees below horizontal.
@export var build_pitch_deg: float = 64.0
## Pitches already inside this range are kept.
@export var good_pitch_range: Vector2 = Vector2(48.0, 80.0)
## Framed radius = complex half-size + build reach + footprint, times this.
@export var frame_margin: float = 1.05
## How far past the complex the build view (and the zone quad) reaches, m.
@export var build_reach: float = 260.0

## Screen position used instead of the mouse when x >= 0 (screenshots, tests).
var cursor_override := Vector2(-1.0, -1.0)

var manager: BuildingManager
var def: BuildingDef
var valid := false
var reason := ""
## Frame-local offset under the cursor; Vector3.INF when off the plane.
var offset := Vector3.INF
## Placement check for the current spot (null when off the plane).
var plan: BuildingManager.Plan
## Bay-pick mode: the free bay under the cursor (0 = none).
var bay: int = 0

var _cursor := Vector2.ZERO
var _over_ui := false
var _press_pos := Vector2.INF
var _ghost: Node3D
var _ghost_mat: StandardMaterial3D
var _ghost_ring: MeshInstance3D
var _zone: MeshInstance3D
var _zone_mat: ShaderMaterial
var _camera: RTSCamera
## Bay-pick mode: bay -> {"node", "meshes", "ring", "center" (frame-local)}.
var _bay_ghosts: Dictionary = {}
var _idle_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group(GROUP)
	# The viewed system's (this controller sits outside the systems, game.tscn).
	manager = BuildingManager.of(self)
	if manager:
		manager.building_added.connect(func(_b: Building) -> void: _update_zone())
	set_process(false)


func is_armed() -> bool:
	return def != null


func arm(building_def: BuildingDef) -> void:
	if manager == null or not manager.has_zone():
		return
	cancel()
	def = building_def
	_camera = RTSCamera.of(self)
	if def.station_addon:
		_build_bay_ghosts()
	else:
		_build_ghost()
		_build_zone()
	valid = false
	reason = ""
	_press_pos = Vector2.INF
	frame_build_view()
	set_process(true)
	_update()
	armed_changed.emit(def)


func cancel() -> void:
	if def == null:
		return
	def = null
	plan = null
	set_process(false)
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if _zone:
		_zone.queue_free()
		_zone = null
	_clear_bay_ghosts()
	bay = 0
	offset = Vector3.INF
	armed_changed.emit(null)


## Places at the current ghost spot. Returns the building or null.
func confirm() -> Building:
	_update()
	if def == null or not valid:
		return null
	var b: Building
	if def.station_addon:
		b = manager.install_addon(def, bay)
		if b:
			# Shift keeps the mode armed: the bay just used is no longer free.
			_build_bay_ghosts()
	else:
		b = manager.place(def, offset)
	if b:
		placed.emit(b)
	return b


## Flies the camera to the build view for the armed building: follows the
## Home Station, pivot on the complex, distance fitting the complex and
## [member build_reach], pitch [member build_pitch_deg]. Keeps what is already fine.
func frame_build_view(snap: bool = false) -> void:
	if _camera == null or def == null or manager.solar_system.home_station == null:
		return
	if def.station_addon:
		var r := (manager.bay_radius + def.footprint_radius * 2.0 + 40.0) * frame_margin
		_camera.frame_area(manager.solar_system.home_station, Vector3.ZERO, r, build_pitch_deg, true, snap,
				Vector2(0.75, 1.6), good_pitch_range)
		return
	var box := manager.complex_bounds()
	var reach := build_reach + def.footprint_radius * 2.0
	if def.standalone:
		# Room to see the range ring around a spot near the complex.
		reach = maxf(reach, def.preview_range * 0.8)
	var radius := (maxf(box.size.x, box.size.y) * 0.5 + reach) * frame_margin
	var c := box.get_center()
	var center := manager.to_world(Vector3(c.x, 0.0, c.y)) - manager.to_world(Vector3.ZERO)
	_camera.frame_area(manager.solar_system.home_station, center, radius, build_pitch_deg, true, snap,
			Vector2(0.75, 1.6), good_pitch_range)


func _input(event: InputEvent) -> void:
	if def == null:
		return
	if event is InputEventMouse:
		_cursor = (event as InputEventMouse).position
		# Reset in _unhandled_input if no Control consumed the event.
		if event is InputEventMouseMotion:
			_over_ui = true


func _unhandled_input(event: InputEvent) -> void:
	if def == null:
		return
	if event is InputEventMouseMotion:
		_over_ui = false
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			# The press is left to the camera (a drag orbits); a click
			# places on release.
			if mb.pressed:
				_over_ui = false
				_press_pos = mb.position if not mb.alt_pressed and not mb.double_click else Vector2.INF
				return
			var was_click := _press_pos != Vector2.INF and mb.position.distance_to(_press_pos) <= click_slop_px \
					and not (_camera and _camera.is_orbiting())
			_press_pos = Vector2.INF
			if not was_click:
				return
			_over_ui = false
			# Shift keeps placement armed for the next one.
			if confirm() and not mb.shift_pressed:
				cancel()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			cancel()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		cancel()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	if def == null or _camera == null:
		return
	var screen := cursor_override if cursor_override.x >= 0.0 else _cursor
	# The level plane through the station (it rides its planet's inclined orbit).
	var hit := _camera.screen_to_ground(screen, manager.frame.global_position.y)
	var over_ui := _over_ui and cursor_override.x < 0.0
	if def.station_addon:
		_update_bays(Vector3.INF if over_ui else hit)
		return
	if hit == Vector3.INF or over_ui:
		offset = Vector3.INF
		plan = null
		_ghost.visible = false
		_set_valid(false, "Point at open space")
		return
	offset = manager.to_local_offset(hit)
	plan = manager.plan_placement(def, offset)
	_ghost.visible = true
	_ghost.position = offset
	_ghost.rotation.y = plan.yaw
	_set_valid(plan.is_valid(), plan.problem)


func _set_valid(v: bool, why: String) -> void:
	var c := VALID_COLOR if v else INVALID_COLOR
	if _ghost_mat:
		_ghost_mat.albedo_color = Color(c, 0.32)
		_ghost_mat.emission = c
	if is_instance_valid(_ghost_ring):
		RingUtil.set_color(_ghost_ring, Color(c, 0.9))
	if v != valid or why != reason:
		valid = v
		reason = why
		validity_changed.emit(valid, reason)


# --- Bay-pick mode (station addons) ---------------------------------------------

## The free bay nearest [param hit] (world, on the plane) within reach of its
## ghost lights up; the rest stay faint.
func _update_bays(hit: Vector3) -> void:
	var best := 0
	if hit != Vector3.INF:
		var local := manager.to_local_offset(hit)
		var best_d := def.footprint_radius * 2.0 + 12.0
		for i: int in _bay_ghosts:
			var c: Vector3 = _bay_ghosts[i]["center"]
			var d := SpaceNav.flat_distance(c, local)
			if d < best_d:
				best_d = d
				best = i
	if best != bay:
		if _bay_ghosts.has(bay):
			_style_bay(bay, false)
		bay = best
		if _bay_ghosts.has(bay):
			_style_bay(bay, true)
	offset = Vector3.INF if bay == 0 else (_bay_ghosts[bay]["center"] as Vector3)
	if bay == 0:
		_set_valid(false, "No free addon bay" if _bay_ghosts.is_empty() else "Point at a free addon bay")
		return
	var why := manager.addon_problem(def, bay)
	_set_valid(why.is_empty(), why)


func _style_bay(i: int, hovered: bool) -> void:
	var g: Dictionary = _bay_ghosts[i]
	for mi: MeshInstance3D in g["meshes"]:
		mi.material_override = _ghost_mat if hovered else _idle_mat
	var ring: MeshInstance3D = g["ring"]
	if hovered:
		_ghost_ring = ring
		RingUtil.set_color(ring, Color(VALID_COLOR if valid else INVALID_COLOR, 0.9))
	else:
		RingUtil.set_color(ring, Color(ZONE_COLOR, 0.5))


func _build_bay_ghosts() -> void:
	_clear_bay_ghosts()
	if _ghost_mat == null:
		_ghost_mat = _make_ghost_mat()
	if _idle_mat == null:
		_idle_mat = _make_ghost_mat()
		_idle_mat.albedo_color = Color(ZONE_COLOR, 0.14)
		_idle_mat.emission = ZONE_COLOR
		_idle_mat.emission_energy_multiplier = 0.3
	for i in manager.free_bays():
		var node := Node3D.new()
		node.name = "BayGhost%d" % i
		node.transform = manager.bay_transform(i)
		var model := def.instantiate_model()
		node.add_child(model)
		manager.frame.add_child(node)
		var meshes := ModelLoader.meshes_of(model)
		for mi in meshes:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var box := ModelLoader.local_aabb(model)
		var centre := Vector3(box.get_center().x, 0.0, box.get_center().z)
		var ring := RingUtil.make_ring(def.footprint_radius, Color(ZONE_COLOR, 0.5), 1.6, 64)
		ring.position = centre
		node.add_child(ring)
		_bay_ghosts[i] = {"node": node, "meshes": meshes, "ring": ring, "center": node.transform * centre}
		_style_bay(i, false)
	bay = 0
	_ghost_ring = null


func _clear_bay_ghosts() -> void:
	for i: int in _bay_ghosts:
		(_bay_ghosts[i]["node"] as Node3D).queue_free()
	_bay_ghosts.clear()
	_ghost_ring = null


func _make_ghost_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission_energy_multiplier = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	return m


func _build_ghost() -> void:
	_ghost = Node3D.new()
	_ghost.name = "PlacementGhost"
	var model := def.instantiate_model()
	_ghost.add_child(model)
	_ghost_mat = _make_ghost_mat()
	for mi in ModelLoader.meshes_of(model):
		mi.material_override = _ghost_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost_ring = RingUtil.make_ring(def.footprint_radius, VALID_COLOR, 2.0, 64)
	_ghost.add_child(_ghost_ring)
	if def.preview_range > 0.0:
		var reach := RingUtil.make_ring(def.preview_range, Color(ZONE_COLOR, 0.55), 3.0, 128)
		reach.name = "RangeRing"
		_ghost.add_child(reach)
	manager.frame.add_child(_ghost)


func _build_zone() -> void:
	_zone = MeshInstance3D.new()
	_zone.name = "PlacementZone"
	_zone_mat = ShaderMaterial.new()
	_zone_mat.shader = ZONE_SHADER
	_zone_mat.set_shader_parameter("zone_color", ZONE_COLOR)
	_zone.material_override = _zone_mat
	_zone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_zone.position.y = 0.4
	manager.frame.add_child(_zone)
	_update_zone()


## Feeds the keep-outs (station disc and strips, structure gaps, docking
## lanes) to the zone shader and sizes its quad.
func _update_zone() -> void:
	if _zone == null or def == null:
		return
	var r := def.footprint_radius
	var gap := manager.gap_for(def)
	var discs := PackedVector4Array()
	discs.append(Vector4(0.0, 0.0, manager.station_clearance + r, 0.0))
	for b in manager.buildings:
		if is_instance_valid(b) and not b.def.station_addon:
			discs.append(Vector4(b.position.x, b.position.z, b.def.footprint_radius + r + minf(gap, manager.gap_for(b.def)), 0.0))
	var segs := PackedVector4Array()
	var halves := PackedFloat32Array()
	if manager.keepouts:
		for k in manager.keepouts.strips:
			var a: Vector3 = k["a"]
			var e: Vector3 = k["b"]
			segs.append(Vector4(a.x, a.z, e.x, e.z))
			halves.append(float(k["half"]) + r)
	for b in manager.buildings:
		if not is_instance_valid(b) or b.def.station_addon:
			continue
		var lane := manager.lane_of(b.def, b.position, b.rotation.y)
		if not lane.is_empty():
			segs.append(Vector4(lane[0].x, lane[0].z, lane[1].x, lane[1].z))
			halves.append(manager.lane_half_width + r)
	if discs.size() > MAX_ZONE_DISCS:
		discs.resize(MAX_ZONE_DISCS)
	if segs.size() > MAX_ZONE_SEGS:
		segs.resize(MAX_ZONE_SEGS)
		halves.resize(MAX_ZONE_SEGS)
	var n_discs := discs.size()
	var n_segs := segs.size()
	discs.resize(MAX_ZONE_DISCS)
	segs.resize(MAX_ZONE_SEGS)
	halves.resize(MAX_ZONE_SEGS)
	_zone_mat.set_shader_parameter("discs", discs)
	_zone_mat.set_shader_parameter("disc_count", n_discs)
	_zone_mat.set_shader_parameter("segs", segs)
	_zone_mat.set_shader_parameter("seg_half", halves)
	_zone_mat.set_shader_parameter("seg_count", n_segs)
	_zone_mat.set_shader_parameter("band", manager.planet_band(r))
	_zone_mat.set_shader_parameter("zone_radius", manager.zone_radius - r)
	var box := manager.complex_bounds().grow(build_reach + r * 2.0 + 20.0)
	var quad := PlaneMesh.new()
	quad.size = box.size
	quad.center_offset = Vector3(box.get_center().x, 0.0, box.get_center().y)
	_zone.mesh = quad

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
##
## Works in every system with a station (home or a forward one): [method arm]
## takes the viewed system's [BuildingManager], so the ghost, the zone and
## the build area are that station's. A view switch while armed re-arms in
## the new system when it has a station that allows the def, else cancels.
##
## Station site mode (F6, [method arm_site]): a [MobileStation] at home
## picks its destination planet in another system. The view goes there
## first (armed on the view change, like the re-arm above); every planet
## gets a ring on the would-be station orbit, green where
## ForwardStations.site_problem allows a station, red where not, and the
## planet under the cursor shows its name and the reason in a label. A
## click on a green one sets the destination (MobileStation.set_destination:
## the escort contract is posted); right-click or Escape cancels.

signal armed_changed(def: BuildingDef)
signal validity_changed(valid: bool, reason: String)
signal placed(building: Building)
## Station site mode on or off.
signal site_changed(on: bool)

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
## Station site mode: the station choosing, the system, the planet under
## the cursor, PlanetBody -> {"ring", "label", "why"}, a pending
## {"station", "system"} while the view switches there, the hint.
var site_station: MobileStation
var site_system: StringName = &""
var site_planet: PlanetBody
var _site_rings: Dictionary = {}
var _site_pending: Dictionary = {}
var _site_hint: Label
var _site_layer: CanvasLayer


func _ready() -> void:
	add_to_group(GROUP)
	# The viewed system's (this controller sits outside the systems, game.tscn).
	manager = BuildingManager.of(self)
	var vm := ViewManager.of(get_tree())
	if vm:
		vm.view_changed.connect(_on_view_changed)
	set_process(false)


## Armed: the same def in the new system's station, or cancel. Site mode
## starts when the view reached its system, and ends on any other switch.
func _on_view_changed(w: SystemWorld) -> void:
	if is_site_armed():
		cancel_site()
	if not _site_pending.is_empty():
		var p := _site_pending
		_site_pending = {}
		if is_instance_valid(w) and w.system_id == StringName(p["system"]) and is_instance_valid(p["station"]):
			_start_site(p["station"] as MobileStation, w.system_id)
	if def == null:
		manager = BuildingManager.of(self)
		return
	var d := def
	cancel()
	var mgr := BuildingManager.of(self)
	if mgr and mgr.allows(d):
		arm(d)
	else:
		manager = mgr


func _on_building_added(_b: Building) -> void:
	_update_zone()


func is_armed() -> bool:
	return def != null


func arm(building_def: BuildingDef) -> void:
	# The viewed system's station (systems without one have no manager).
	cancel()
	var mgr := BuildingManager.of(self)
	if mgr == null or not mgr.has_zone() or not mgr.allows(building_def):
		return
	_set_manager(mgr)
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


## Moves the building_added link to [param mgr].
func _set_manager(mgr: BuildingManager) -> void:
	if is_instance_valid(manager) and manager.building_added.is_connected(_on_building_added):
		manager.building_added.disconnect(_on_building_added)
	manager = mgr
	if manager and not manager.building_added.is_connected(_on_building_added):
		manager.building_added.connect(_on_building_added)


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
		Sfx.ui(&"build_placed")
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
	if def == null and not is_site_armed():
		return
	if event is InputEventMouse:
		_cursor = (event as InputEventMouse).position
		# Reset in _unhandled_input if no Control consumed the event.
		if event is InputEventMouseMotion:
			_over_ui = true


func _unhandled_input(event: InputEvent) -> void:
	if is_site_armed():
		_site_input(event)
		return
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
	if is_site_armed():
		_update_site()
		return
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


# --- Station site mode (F6) -----------------------------------------------------------

func is_site_armed() -> bool:
	return is_instance_valid(site_station) and not site_system.is_empty()


## [param ms] picks its destination planet in [param system_id]: the view
## goes there first (the mode starts on the view change).
func arm_site(ms: MobileStation, system_id: StringName) -> void:
	cancel()
	cancel_site()
	if ms == null or ms.dead:
		return
	var vm := ViewManager.of(get_tree())
	if vm and vm.viewed_id() != system_id:
		if not vm.can_view(system_id):
			return
		_site_pending = {"station": ms, "system": system_id}
		vm.view(system_id)
		return
	_start_site(ms, system_id)


func cancel_site() -> void:
	_site_pending = {}
	if not is_site_armed() and _site_rings.is_empty():
		return
	for p: PlanetBody in _site_rings:
		var e: Dictionary = _site_rings[p]
		for k in ["ring", "label"]:
			if is_instance_valid(e[k]):
				(e[k] as Node).queue_free()
	_site_rings.clear()
	site_station = null
	site_system = &""
	site_planet = null
	if _site_layer:
		_site_layer.visible = false
	set_process(def != null)
	site_changed.emit(false)


func _start_site(ms: MobileStation, system_id: StringName) -> void:
	var sys := SolarSystem.of(self)
	_camera = RTSCamera.of(self)
	if sys == null or _camera == null:
		return
	site_station = ms
	site_system = system_id
	for p in sys.planets:
		if not is_instance_valid(p) or not p.is_visible_in_tree():
			continue
		var site := ForwardStations.site_on(system_id, p.def.name)
		var why := ForwardStations.site_problem(get_tree(), system_id, p, ms)
		var ring := RingUtil.make_ring(float(site.get("orbit_radius", p.def.radius * 2.0)), Color(VALID_COLOR if why.is_empty() else INVALID_COLOR, 0.6), 2.4, 128)
		ring.name = "SiteRing"
		p.add_child(ring)
		var label := Label3D.new()
		label.name = "SiteLabel"
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.fixed_size = true
		label.pixel_size = 0.0007
		label.font_size = 22
		label.outline_size = 6
		label.no_depth_test = true
		label.shaded = false
		label.render_priority = 12
		label.outline_render_priority = 11
		label.offset = Vector2(0.0, -46.0)
		label.text = ("%s: station site" % p.def.name) if why.is_empty() else why
		label.modulate = Color(VALID_COLOR if why.is_empty() else INVALID_COLOR, 0.9)
		label.visible = false
		MeshUtil.set_layers_recursive(ring, 2)
		p.add_child(label)
		_site_rings[p] = {"ring": ring, "label": label, "why": why}
	_show_site_hint("Pick a planet for %s: green rings can hold it. Right-click / Esc: cancel" % ms.get_display_name())
	# After the new system's own camera setup (deferred when it was built).
	get_tree().process_frame.connect(func() -> void:
		if is_site_armed() and is_instance_valid(_camera):
			_camera.fit_system(), CONNECT_ONE_SHOT)
	set_process(true)
	site_changed.emit(true)
	_update_site()


func _show_site_hint(text: String) -> void:
	if _site_layer == null:
		_site_layer = CanvasLayer.new()
		_site_layer.name = "SiteHint"
		_site_layer.layer = 5
		add_child(_site_layer)
		var panel := PanelContainer.new()
		panel.theme_type_variation = &"HintPanel"
		panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
		panel.position.y = 64.0
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_site_layer.add_child(panel)
		_site_hint = UIUtil.label("", &"DimLabel")
		_site_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(_site_hint)
	_site_layer.visible = true
	_site_hint.text = text
	var panel := _site_hint.get_parent() as Control
	panel.reset_size()
	panel.position.x = (get_viewport().get_visible_rect().size.x - panel.size.x) * 0.5


## The planet under the cursor (its ring or body on screen) lights up.
func _update_site() -> void:
	var cam := SystemWorld.camera_3d(self)
	if cam == null:
		return
	var screen := cursor_override if cursor_override.x >= 0.0 else _cursor
	var px_per_rad := get_viewport().get_visible_rect().size.y / (2.0 * tan(deg_to_rad(cam.fov) * 0.5))
	var best: PlanetBody = null
	var best_score := INF
	for p: PlanetBody in _site_rings:
		if not is_instance_valid(p) or cam.is_position_behind(p.global_position):
			continue
		var ring := _site_rings[p]["ring"] as MeshInstance3D
		var r_world := (ring.mesh as Mesh).get_aabb().size.x * 0.5 if ring and ring.mesh else p.def.radius
		var d := maxf(cam.global_position.distance_to(p.global_position), 1.0)
		var r_px := maxf(r_world / d * px_per_rad, 22.0)
		var off := cam.unproject_position(p.global_position).distance_to(screen)
		if off <= r_px * 1.15 and off / r_px < best_score:
			best_score = off / r_px
			best = p
	if (_over_ui and cursor_override.x < 0.0):
		best = null
	site_planet = best
	for p: PlanetBody in _site_rings:
		var e: Dictionary = _site_rings[p]
		var ok := String(e["why"]).is_empty()
		RingUtil.set_color(e["ring"], Color(VALID_COLOR if ok else INVALID_COLOR, 1.0 if p == best else 0.55))
		(e["label"] as Label3D).visible = p == best
	if best:
		var why := String(_site_rings[best]["why"])
		_set_valid(why.is_empty(), why if not why.is_empty() else "Click: %s flies to %s" % [site_station.get_display_name(), best.def.name])
	else:
		_set_valid(false, "Point at a planet")


func _site_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_over_ui = false
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_over_ui = false
				_press_pos = mb.position if not mb.double_click else Vector2.INF
				return
			var was_click := _press_pos != Vector2.INF and mb.position.distance_to(_press_pos) <= click_slop_px \
					and not (_camera and _camera.is_orbiting())
			_press_pos = Vector2.INF
			if was_click:
				confirm_site()
				get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			cancel_site()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		cancel_site()
		get_viewport().set_input_as_handled()


## Sets the destination on the planet under the cursor. True when it did.
func confirm_site() -> bool:
	_update_site()
	if not is_site_armed() or site_planet == null:
		return false
	var why := site_station.destination_problem(site_system, site_planet)
	if not why.is_empty():
		_toast(why)
		return false
	var ms := site_station
	var planet_name := site_planet.def.name
	if not ms.set_destination(site_system, site_planet):
		return false
	cancel_site()
	_toast("%s: destination %s. Waiting for an escort" % [ms.get_display_name(), planet_name])
	return true


func _toast(text: String) -> void:
	var pm := get_tree().root.get_node_or_null(^"PauseMenu")
	if pm and pm.has_method(&"toast"):
		pm.call(&"toast", text)

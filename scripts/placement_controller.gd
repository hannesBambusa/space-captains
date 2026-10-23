class_name PlacementController
extends Node3D
## Build placement. [method arm] flies the camera to a build view of the
## station complex (follows the Home Station, fairly top-down, distance that
## fits the complex plus the link reach) and shows a translucent ghost of
## the building under the cursor (green = valid, red = invalid), its link
## corridor to the complex as a ghost corridor, and the area a new
## structure's centre can link from. The ghost turns the way the link wants
## (docking mouth away from the complex).
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
const ZONE_SHADER: Shader = preload("res://shaders/link_zone.gdshader")
const MAX_ZONE_DISCS := 48
const MAX_ZONE_SEGS := 64

@export var manager_path: NodePath = ^"../Buildings"
## Max mouse travel (px) between press and release that still counts as a click.
@export var click_slop_px: float = 3.0
@export_group("Build view")
## Camera tilt for placing, degrees below horizontal.
@export var build_pitch_deg: float = 64.0
## Pitches already inside this range are kept.
@export var good_pitch_range: Vector2 = Vector2(48.0, 80.0)
## Framed radius = complex half-size + link reach + footprint, times this.
@export var frame_margin: float = 1.05

## Screen position used instead of the mouse when x >= 0 (screenshots, tests).
var cursor_override := Vector2(-1.0, -1.0)

var manager: BuildingManager
var def: BuildingDef
var valid := false
var reason := ""
## Frame-local offset under the cursor; Vector3.INF when off the plane.
var offset := Vector3.INF
## Link for the current spot (null when off the plane).
var plan: CorridorNetwork.Plan

var _cursor := Vector2.ZERO
var _over_ui := false
var _press_pos := Vector2.INF
var _ghost: Node3D
var _ghost_mat: StandardMaterial3D
var _ghost_ring: MeshInstance3D
var _ghost_corridor: Node3D
var _preview: Dictionary = {}
var _zone: MeshInstance3D
var _zone_mat: ShaderMaterial
var _camera: RTSCamera


func _ready() -> void:
	add_to_group(GROUP)
	manager = get_node_or_null(manager_path) as BuildingManager
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
	_camera = get_tree().get_first_node_in_group("rts_camera") as RTSCamera
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
	if _ghost_corridor:
		_ghost_corridor.queue_free()
		_ghost_corridor = null
	_preview.clear()
	if _zone:
		_zone.queue_free()
		_zone = null
	offset = Vector3.INF
	armed_changed.emit(null)


## Places at the current ghost spot. Returns the building or null.
func confirm() -> Building:
	_update()
	if def == null or not valid:
		return null
	var b := manager.place(def, offset)
	if b:
		placed.emit(b)
	return b


## Flies the camera to the build view for the armed building: follows the
## Home Station, pivot on the complex, distance fitting the complex and the
## link reach, pitch [member build_pitch_deg]. Keeps what is already fine.
func frame_build_view(snap: bool = false) -> void:
	if _camera == null or def == null or manager.solar_system.home_station == null:
		return
	var box := manager.links.complex_bounds()
	var reach := manager.links.max_link + def.footprint_radius * 2.0
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
	var hit := _camera.screen_to_ground(screen)
	var over_ui := _over_ui and cursor_override.x < 0.0
	if hit == Vector3.INF or over_ui:
		offset = Vector3.INF
		plan = null
		_ghost.visible = false
		_show_preview(null)
		_set_valid(false, "Point at open space")
		return
	offset = manager.to_local_offset(hit)
	plan = manager.plan_placement(def, offset)
	_ghost.visible = true
	_ghost.position = offset
	_ghost.rotation.y = plan.yaw
	_show_preview(plan)
	_set_valid(plan.is_valid(), plan.problem)


func _set_valid(v: bool, why: String) -> void:
	var c := VALID_COLOR if v else INVALID_COLOR
	_ghost_mat.albedo_color = Color(c, 0.32)
	_ghost_mat.emission = c
	RingUtil.set_color(_ghost_ring, Color(c, 0.9))
	if v != valid or why != reason:
		valid = v
		reason = why
		validity_changed.emit(valid, reason)


func _show_preview(p: CorridorNetwork.Plan) -> void:
	var pieces := manager.links.plan_pieces(p) if p else {}
	for part: CorridorKit.Part in CorridorNetwork.PARTS:
		var mmi: MultiMeshInstance3D = _preview.get(part)
		if mmi:
			CorridorNetwork.fill_multimesh(mmi, pieces.get(part, []))


func _build_ghost() -> void:
	_ghost = Node3D.new()
	_ghost.name = "PlacementGhost"
	var model := ModelLoader.instantiate(def.model_path, ModelLoader.building_placeholder.bind(def.footprint_radius))
	_ghost.add_child(model)
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.emission_enabled = true
	_ghost_mat.emission_energy_multiplier = 0.6
	_ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost_mat.no_depth_test = false
	for mi in ModelLoader.meshes_of(model):
		mi.material_override = _ghost_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost_ring = RingUtil.make_ring(def.footprint_radius, VALID_COLOR, 2.0, 64)
	_ghost.add_child(_ghost_ring)
	manager.frame.add_child(_ghost)
	# Ghost corridor: frame-local pieces, so it sits on the frame beside the ghost.
	_ghost_corridor = Node3D.new()
	_ghost_corridor.name = "GhostCorridor"
	manager.frame.add_child(_ghost_corridor)
	for part: CorridorKit.Part in CorridorNetwork.PARTS:
		var mmi := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = CorridorKit.mesh(part)
		mmi.multimesh = mm
		mmi.material_override = _ghost_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visible = false
		_ghost_corridor.add_child(mmi)
		_preview[part] = mmi


func _build_zone() -> void:
	_zone = MeshInstance3D.new()
	_zone.name = "LinkZone"
	_zone_mat = ShaderMaterial.new()
	_zone_mat.shader = ZONE_SHADER
	_zone_mat.set_shader_parameter("zone_color", ZONE_COLOR)
	_zone.material_override = _zone_mat
	_zone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_zone.position.y = 0.4
	manager.frame.add_child(_zone)
	_update_zone()


## Feeds the structures and corridors to the zone shader and sizes its quad.
func _update_zone() -> void:
	if _zone == null or def == null:
		return
	var shapes := manager.links.zone_shapes(def.footprint_radius)
	var discs: PackedVector4Array = shapes["discs"]
	var segs: PackedVector4Array = shapes["segs"]
	if discs.size() > MAX_ZONE_DISCS:
		discs.resize(MAX_ZONE_DISCS)
	if segs.size() > MAX_ZONE_SEGS:
		segs.resize(MAX_ZONE_SEGS)
	var n_discs := discs.size()
	var n_segs := segs.size()
	discs.resize(MAX_ZONE_DISCS)
	segs.resize(MAX_ZONE_SEGS)
	_zone_mat.set_shader_parameter("discs", discs)
	_zone_mat.set_shader_parameter("disc_count", n_discs)
	_zone_mat.set_shader_parameter("segs", segs)
	_zone_mat.set_shader_parameter("seg_count", n_segs)
	_zone_mat.set_shader_parameter("seg_inner", shapes["seg_inner"])
	_zone_mat.set_shader_parameter("seg_reach", shapes["seg_reach"])
	_zone_mat.set_shader_parameter("band", manager.planet_band(def.footprint_radius))
	_zone_mat.set_shader_parameter("zone_radius", manager.zone_radius - def.footprint_radius)
	var box := manager.links.complex_bounds().grow(manager.links.max_link + def.footprint_radius * 2.0 + 20.0)
	var quad := PlaneMesh.new()
	quad.size = box.size
	quad.center_offset = Vector3(box.get_center().x, 0.0, box.get_center().y)
	_zone.mesh = quad

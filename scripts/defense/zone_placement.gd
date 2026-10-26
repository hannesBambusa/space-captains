class_name ZonePlacement
extends Node3D
## Placing a defence zone (DefenseZones), the build bar's "Defence zone"
## button. Same flow as PlacementController: [method arm] frames a wide
## view around the Home Station and shows a ghost zone under the cursor on
## the station's level plane (pulsing red where it cannot go); a left click
## (press and release within [member click_slop_px], no camera orbit) places
## it and selects it so its panel opens (radius, kill bounty, budget);
## right-click or Escape cancels. Arming one placement mode cancels the
## other. Zones are areas ships fly through, so the station keep-outs and
## structure gaps do not apply; only the zone limit and the system edge do.

signal armed_changed(on: bool)
signal validity_changed(valid: bool, reason: String)
signal placed(zone: DefenseZone)

const GROUP := "zone_placement"
## View radius framed while placing, m.
const VIEW_RADIUS := 6500.0
const VIEW_PITCH := 62.0

@export var click_slop_px: float = 3.0

## Screen position used instead of the mouse when x >= 0 (screenshots, tests).
var cursor_override := Vector2(-1.0, -1.0)
var armed := false
var valid := false
var reason := ""
## World point under the cursor (Vector3.INF when off the plane).
var world_pos := Vector3.INF
var radius: float = DefenseZones.DEFAULT_RADIUS

var _ghost: DefenseZone
var _camera: RTSCamera
var _cursor := Vector2.ZERO
var _over_ui := false
var _press_pos := Vector2.INF


func _ready() -> void:
	add_to_group(GROUP)
	set_process(false)
	var pc := get_tree().get_first_node_in_group(PlacementController.GROUP) as PlacementController
	if pc:
		pc.armed_changed.connect(func(d: BuildingDef) -> void:
			if d != null:
				cancel())


func is_armed() -> bool:
	return armed


func arm() -> void:
	var zones := DefenseZones.of(self)
	if zones == null or zones.count() >= DefenseZones.MAX_ZONES:
		return
	var pc := get_tree().get_first_node_in_group(PlacementController.GROUP) as PlacementController
	if pc:
		pc.cancel()
	cancel()
	armed = true
	_camera = RTSCamera.of(self)
	_ghost = DefenseZone.new()
	_ghost.name = "ZoneGhost"
	_ghost.zone_name = "New zone"
	_ghost.radius = radius
	SpaceNav.space_root(self).add_child(_ghost)
	_ghost.visible = false
	var sys := SolarSystem.of(self)
	if _camera and sys and sys.home_station:
		_camera.frame_area(sys.home_station, Vector3.ZERO, VIEW_RADIUS, VIEW_PITCH, true, false, Vector2(0.6, 2.2))
	valid = false
	reason = ""
	_press_pos = Vector2.INF
	set_process(true)
	_update()
	armed_changed.emit(true)


func cancel() -> void:
	if not armed:
		return
	armed = false
	set_process(false)
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	world_pos = Vector3.INF
	armed_changed.emit(false)


## Places a zone at the ghost. Returns it or null.
func confirm() -> DefenseZone:
	_update()
	if not armed or not valid:
		return null
	var zones := DefenseZones.of(self)
	var z := zones.place(world_pos, radius) if zones else null
	if z:
		placed.emit(z)
	return z


func _input(event: InputEvent) -> void:
	if not armed:
		return
	if event is InputEventMouse:
		_cursor = (event as InputEventMouse).position
		if event is InputEventMouseMotion:
			_over_ui = true


func _unhandled_input(event: InputEvent) -> void:
	if not armed:
		return
	if event is InputEventMouseMotion:
		_over_ui = false
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
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
			var z := confirm()
			if z:
				cancel()
				var sel := get_tree().get_first_node_in_group(SelectionController.GROUP) as SelectionController
				if sel:
					sel.select(z)
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
	if not armed or _camera == null:
		return
	var mgr := BuildingManager.of(self)
	var height := mgr.frame.global_position.y if mgr and mgr.frame else 0.0
	var screen := cursor_override if cursor_override.x >= 0.0 else _cursor
	var hit := _camera.screen_to_ground(screen, height)
	var over_ui := _over_ui and cursor_override.x < 0.0
	if hit == Vector3.INF or over_ui:
		world_pos = Vector3.INF
		if _ghost:
			_ghost.visible = false
		_set_valid(false, "Point at open space")
		return
	world_pos = hit
	var zones := DefenseZones.of(self)
	var why := zones.place_problem(hit) if zones else "No defence zones here"
	if _ghost:
		_ghost.visible = true
		_ghost.global_position = hit
		_ghost.raiders_inside = 0 if why.is_empty() else 1
		_ghost.refresh_look()
	if why.is_empty() and zones:
		why = ""
		var at := zones.anchor_text_at(hit)
		_set_valid(true, at if at != "Fixed in space" else "Fixed in space (more than %d km from the station, away from planets)" % roundi(DefenseZones.ANCHOR_REACH / 1000.0))
		return
	_set_valid(false, why)


func _set_valid(v: bool, why: String) -> void:
	if v != valid or why != reason:
		valid = v
		reason = why
		validity_changed.emit(valid, reason)

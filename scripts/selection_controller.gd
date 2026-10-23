class_name SelectionController
extends Node3D
## Click selection: buildings (by footprint), ships (hostile scavengers get a
## red ring), Scavenger Dens, scrap fields, and asteroid belts (a
## click near the belt ring or on its label anchor). Draws a ring on the plane
## around the selection. Escape or a click on empty space deselects (Escape is
## marked handled so the pause menu does not open as well). Double-clicks are
## left to the camera (fly-to). Clicks act on release; a left press that moves
## more than [member click_slop_px] is a camera orbit, not a click.
##
## Clicking a building or a ship also makes the camera follow it; clicking a
## belt anchor follows the anchor; clicking the belt ring selects the belt and
## leaves the camera alone. Planets, moons, gates and the star are followed
## but not selected.

signal selection_changed(target: Node3D)

const GROUP := "selection_controller"
const RING_COLOR := Color(1.0, 0.62, 0.26, 0.95)
const BELT_RING_COLOR := Color(1.0, 0.62, 0.26, 0.55)
const HOSTILE_RING_COLOR := Color(1.0, 0.28, 0.22, 0.95)
const SCRAP_RING_COLOR := Color(0.9, 0.82, 0.62, 0.8)

@export var manager_path: NodePath = ^"../Buildings"
## Minimum pick radius in pixels, so tiny far-away buildings stay clickable.
@export var min_pick_px: float = 14.0
## Selection ring radius as a multiple of the footprint.
@export var ring_scale: float = 1.2
## Ship pick radius on screen, pixels (at least).
@export var ship_pick_px: float = 16.0
## Extra pick tolerance around a belt's band, pixels.
@export var belt_pick_px: float = 10.0
@export var ship_ring_radius: float = 14.0
## Max mouse travel (px) between press and release that still counts as a click.
@export var click_slop_px: float = 3.0

var manager: BuildingManager
## A Building, a Ship or a SystemBelt (or null).
var selected: Node3D

var _ring: MeshInstance3D
var _press_pos := Vector2.INF


func _ready() -> void:
	add_to_group(GROUP)
	manager = get_node_or_null(manager_path) as BuildingManager


func _process(_delta: float) -> void:
	# Ship rings follow the ship but stay flat on its plane.
	if selected is Ship and is_instance_valid(_ring):
		_ring.global_position = selected.global_position + Vector3(0.0, -1.0, 0.0)


func get_selected_building() -> Building:
	return selected as Building


func get_selected_ship() -> Ship:
	return selected as Ship


func get_selected_belt() -> SystemBelt:
	return selected as SystemBelt


func select(target: Node3D) -> void:
	if target == selected:
		return
	_clear_ring()
	selected = target
	if target is Building:
		var b := target as Building
		_ring = RingUtil.make_ring(b.def.footprint_radius * ring_scale, RING_COLOR, 2.2, 96)
		_ring.position.y = 0.5
		b.add_child(_ring)
	elif target is Ship:
		var hostile := (target as Ship).is_hostile()
		_ring = RingUtil.make_ring(ship_ring_radius, HOSTILE_RING_COLOR if hostile else RING_COLOR, 1.8, 64)
		_ring.top_level = true
		target.add_child(_ring)
		_ring.global_position = target.global_position
	elif target is ScavengerDen:
		_ring = RingUtil.make_ring(78.0, HOSTILE_RING_COLOR, 2.2, 96)
		_ring.position.y = 0.5
		target.add_child(_ring)
	elif target is ScrapField:
		_ring = RingUtil.make_ring((target as ScrapField).radius * 1.15, SCRAP_RING_COLOR, 1.6, 96)
		target.add_child(_ring)
	elif target is SystemBelt:
		var belt := target as SystemBelt
		_ring = RingUtil.make_ring(belt.def.orbit_radius, BELT_RING_COLOR, 1.6, 1024)
		belt.get_parent().add_child(_ring)
		_ring.global_position = belt.global_position
	if _ring:
		_ring.name = "SelectionRing"
	if target:
		target.tree_exiting.connect(_on_selected_gone.bind(target), CONNECT_ONE_SHOT)
	selection_changed.emit(selected)


func deselect() -> void:
	select(null)


## Building whose footprint covers [param screen_pos], or null.
func pick_building(screen_pos: Vector2) -> Building:
	var cam := get_viewport().get_camera_3d()
	if cam == null or manager == null:
		return null
	var px_per_rad := _px_per_rad(cam)
	var best: Building = null
	var best_score := INF
	for b in manager.buildings:
		if not is_instance_valid(b) or cam.is_position_behind(b.global_position):
			continue
		var d := cam.global_position.distance_to(b.global_position)
		var r_px := maxf(b.def.footprint_radius / maxf(d, 1.0) * px_per_rad, min_pick_px)
		var off := cam.unproject_position(b.global_position).distance_to(screen_pos)
		if off <= r_px and off / r_px < best_score:
			best_score = off / r_px
			best = b
	return best


## Ship under [param screen_pos], or null.
func pick_ship(screen_pos: Vector2) -> Ship:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var px_per_rad := _px_per_rad(cam)
	var best: Ship = null
	var best_score := INF
	for n in get_tree().get_nodes_in_group(Ship.GROUP):
		var s := n as Ship
		if s == null or not s.is_visible_in_tree() or cam.is_position_behind(s.global_position):
			continue
		var d := cam.global_position.distance_to(s.global_position)
		var r_px := maxf(10.0 / maxf(d, 1.0) * px_per_rad, ship_pick_px)
		var off := cam.unproject_position(s.global_position).distance_to(screen_pos)
		if off <= r_px and off / r_px < best_score:
			best_score = off / r_px
			best = s
	return best


## Den or scrap field under [param screen_pos], or null.
func pick_group(screen_pos: Vector2, group: String) -> Node3D:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var px_per_rad := _px_per_rad(cam)
	var best: Node3D = null
	var best_score := INF
	for n in get_tree().get_nodes_in_group(group):
		var t := n as Node3D
		if t == null or t.is_queued_for_deletion() or cam.is_position_behind(t.global_position):
			continue
		var d := cam.global_position.distance_to(t.global_position)
		var r_px := maxf(float(t.get_meta(&"focus_radius", 40.0)) / maxf(d, 1.0) * px_per_rad, min_pick_px)
		var off := cam.unproject_position(t.global_position).distance_to(screen_pos)
		if off <= r_px and off / r_px < best_score:
			best_score = off / r_px
			best = t
	return best


## Belt whose band (plus a few pixels) contains the ground point under
## [param screen_pos], or null.
func pick_belt(screen_pos: Vector2) -> SystemBelt:
	var cam := get_tree().get_first_node_in_group("rts_camera") as RTSCamera
	var sys := get_tree().get_first_node_in_group(SolarSystem.GROUP) as SolarSystem
	if cam == null or sys == null:
		return null
	var g := cam.screen_to_ground(screen_pos)
	if g == Vector3.INF:
		return null
	var c3d := cam.get_camera()
	var world_per_px := cam.get_distance() / maxf(_px_per_rad(c3d), 1.0)
	var best: SystemBelt = null
	var best_off := INF
	for belt in sys.belts:
		var off := absf(Vector2(g.x - belt.global_position.x, g.z - belt.global_position.z).length() - belt.def.orbit_radius)
		var tol := belt.def.width * 0.5 + belt_pick_px * world_per_px
		if off <= tol and off < best_off:
			best_off = off
			best = belt
	return best


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var cam := get_tree().get_first_node_in_group("rts_camera") as RTSCamera
		# Select on release, so a left drag can orbit the camera instead. A
		# single click only selects; a double click also centres the camera.
		if mb.pressed:
			_press_pos = mb.position if not mb.double_click and not mb.alt_pressed else Vector2.INF
			if mb.double_click and not mb.alt_pressed:
				var target := _pick_selectable(mb.position)
				if target:
					select(target)
					if cam:
						cam.focus_on(target, cam.get_distance())
					get_viewport().set_input_as_handled()
			return
		var was_click := _press_pos != Vector2.INF and mb.position.distance_to(_press_pos) <= click_slop_px
		_press_pos = Vector2.INF
		if not was_click or (cam and cam.is_orbiting()):
			return
		var hit := _pick_selectable(mb.position)
		if hit:
			select(hit)
			get_viewport().set_input_as_handled()
			return
		# Planets, moons, gates, belt anchors: a click selects the belt; a
		# double click follows the body (RTSCamera).
		var body := cam.pick_focusable(mb.position) if cam else null
		if body:
			select(body.get_meta(&"belt", null) as SystemBelt)
			get_viewport().set_input_as_handled()
			return
		var belt := pick_belt(mb.position)
		select(belt)
		if belt:
			get_viewport().set_input_as_handled()
	elif selected and event.is_action_pressed("ui_cancel"):
		deselect()
		get_viewport().set_input_as_handled()


## Ship, structure, hideout or scrap field under [param screen_pos], or null.
## Ships first: their pick radius is tight, and parked ones sit inside
## their outpost's footprint.
func _pick_selectable(screen_pos: Vector2) -> Node3D:
	var hit: Node3D = pick_ship(screen_pos)
	if hit == null:
		hit = pick_building(screen_pos)
	if hit == null:
		hit = pick_group(screen_pos, ScavengerDen.GROUP)
	if hit == null:
		hit = pick_group(screen_pos, ScrapField.GROUP)
	return hit


func _px_per_rad(cam: Camera3D) -> float:
	return get_viewport().get_visible_rect().size.y / (2.0 * tan(deg_to_rad(cam.fov) * 0.5))


func _clear_ring() -> void:
	if is_instance_valid(_ring):
		_ring.queue_free()
	_ring = null
	if is_instance_valid(selected) and selected.tree_exiting.is_connected(_on_selected_gone):
		selected.tree_exiting.disconnect(_on_selected_gone)


func _on_selected_gone(target: Node3D) -> void:
	if target == selected:
		# Ships leave the tree briefly when they change frame; keep those selected.
		if target is Ship and not target.is_queued_for_deletion():
			target.tree_exiting.connect(_on_selected_gone.bind(target), CONNECT_ONE_SHOT)
			return
		_ring = null
		selected = null
		selection_changed.emit(null)

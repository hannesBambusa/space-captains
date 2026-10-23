class_name Minimap
extends PanelContainer
## Top-right minimap of the system plane, turned with the camera (view
## forward is up): the star, planet orbits and planets, belts as rings, dens,
## the home station and its shield bubble ring (while it is up), the camera's
## view on the plane, and a dot for every ship in the [ShipMarkers] colours.
## Click a ship dot to select and follow it, anywhere else to fly the camera
## there. The wheel (or the 1x button)
## zooms in steps (1x, 4x, 16x) around the camera. The header also cycles
## the marker density (M) and collapses the map.

const ZOOM_LEVELS: Array[float] = [1.0, 0.25, 0.0625]
const STAR_COLOR := Color(1.0, 0.86, 0.55)
const ORBIT_COLOR := Color(0.6, 0.72, 0.9, 0.22)
const PLANET_COLOR := Color(0.75, 0.82, 0.95)
const BELT_COLOR := Color(0.75, 0.62, 0.48, 0.28)
const HOME_COLOR := Color(1.0, 0.7, 0.35)
const VIEW_COLOR := Color(0.85, 0.92, 1.0, 0.55)

@export var map_px: float = 232.0
@export var dot_pick_px: float = 7.0

var hud: HUD
var markers: ShipMarkers
var is_open := true

var _canvas: Control
var _mode_button: Button
var _toggle_button: Button
var _zoom_button: Button
var _zoom := 0
## Placed at a clicked map point so the camera can fly there and stay.
var _anchor: Node3D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(UIUtil.label("MAP", &"HeaderLabel"))
	h.add_child(UIUtil.spacer())
	_mode_button = UIUtil.button("Markers: All", &"IconButton")
	_mode_button.custom_minimum_size = Vector2(0.0, 22.0)
	_mode_button.tooltip_text = "Ship markers on the map: all, hostiles plus selected, off (M)"
	_mode_button.pressed.connect(func() -> void:
		if markers:
			markers.cycle_mode())
	h.add_child(_mode_button)
	_zoom_button = UIUtil.button("1x", &"IconButton")
	_zoom_button.custom_minimum_size = Vector2(34.0, 22.0)
	_zoom_button.tooltip_text = "Zoom the map around the view (mouse wheel over the map)"
	_zoom_button.pressed.connect(func() -> void: _set_zoom((_zoom + 1) % ZOOM_LEVELS.size()))
	h.add_child(_zoom_button)
	_toggle_button = UIUtil.button("-", &"IconButton")
	_toggle_button.custom_minimum_size = Vector2(26.0, 22.0)
	_toggle_button.tooltip_text = "Collapse the map"
	_toggle_button.pressed.connect(toggle)
	h.add_child(_toggle_button)
	v.add_child(h)
	_canvas = Control.new()
	_canvas.name = "Map"
	_canvas.custom_minimum_size = Vector2(map_px, map_px)
	_canvas.clip_contents = true
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.mouse_default_cursor_shape = Control.CURSOR_CROSS
	_canvas.draw.connect(_draw_map)
	_canvas.gui_input.connect(_on_map_input)
	v.add_child(_canvas)


func setup(owner_hud: HUD, ship_markers: ShipMarkers) -> void:
	hud = owner_hud
	markers = ship_markers
	markers.mode_changed.connect(func(_m: ShipMarkers.Mode) -> void: _sync_mode())
	_sync_mode()


func toggle() -> void:
	is_open = not is_open
	_canvas.visible = is_open
	_toggle_button.text = "-" if is_open else "+"
	_toggle_button.tooltip_text = ("Collapse" if is_open else "Expand") + " the map"
	reset_size()


func _sync_mode() -> void:
	_mode_button.text = "Markers: %s" % markers.get_mode_name()


func _set_zoom(z: int) -> void:
	_zoom = clampi(z, 0, ZOOM_LEVELS.size() - 1)
	_zoom_button.text = "%dx" % roundi(1.0 / ZOOM_LEVELS[_zoom])
	_canvas.queue_redraw()


func _process(_delta: float) -> void:
	if is_open and is_visible_in_tree():
		_canvas.queue_redraw()


# --- Map frame ------------------------------------------------------------------

func _extent() -> float:
	var e := hud.solar_system.get_extent() if hud and hud.solar_system else 25000.0
	return maxf(e, 1000.0)


## World metres per map pixel.
func _scale() -> float:
	return _extent() * ZOOM_LEVELS[_zoom] / (map_px * 0.5)


func _center_world() -> Vector3:
	if _zoom == 0 or hud.camera == null:
		return Vector3.ZERO
	var p := hud.camera.global_position
	return Vector3(p.x, 0.0, p.z)


func _yaw() -> float:
	return hud.camera.rotation.y if hud.camera else 0.0


func _to_map(p: Vector3) -> Vector2:
	var yaw := _yaw()
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var back := Vector3(sin(yaw), 0.0, cos(yaw))
	var d := p - _center_world()
	d.y = 0.0
	return Vector2(d.dot(right), d.dot(back)) / _scale() + Vector2(map_px, map_px) * 0.5


func _to_world(m: Vector2) -> Vector3:
	var yaw := _yaw()
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var back := Vector3(sin(yaw), 0.0, cos(yaw))
	var q := (m - Vector2(map_px, map_px) * 0.5) * _scale()
	return _center_world() + right * q.x + back * q.y


# --- Input ------------------------------------------------------------------------

func _on_map_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		_set_zoom(_zoom + 1)
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_set_zoom(_zoom - 1)
	elif mb.button_index == MOUSE_BUTTON_LEFT:
		var ship := _ship_at(mb.position)
		if ship and markers:
			markers.select_and_follow(ship)
		else:
			_fly_to(_to_world(mb.position))
	else:
		return
	_canvas.accept_event()


func _ship_at(m: Vector2) -> Node3D:
	var best: Node3D = null
	var best_d := dot_pick_px
	for n in _map_targets():
		var d := _to_map(n.global_position).distance_to(m)
		if d < best_d:
			best_d = d
			best = n
	return best


## Ships and live dens shown as dots (parked ships excluded).
func _map_targets() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in get_tree().get_nodes_in_group(Ship.GROUP):
		var s := n as Ship
		if s and not s.dead and s.is_inside_tree() and not ShipMarkers.is_parked(s):
			out.append(s)
	if hud.solar_system:
		for d in hud.solar_system.dens:
			if is_instance_valid(d) and not d.dead:
				out.append(d)
	return out


func _fly_to(p: Vector3) -> void:
	if hud.camera == null:
		return
	if not is_instance_valid(_anchor):
		_anchor = Node3D.new()
		_anchor.name = "MinimapAnchor"
		get_tree().current_scene.add_child(_anchor)
	_anchor.global_position = Vector3(p.x, 0.0, p.z)
	hud.camera.focus_on(_anchor, hud.camera.get_distance())


# --- Drawing --------------------------------------------------------------------

func _draw_map() -> void:
	var c := _canvas
	var size := Vector2(map_px, map_px)
	c.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.035, 0.06, 0.72), true)
	if hud == null or hud.solar_system == null:
		return
	var sys := hud.solar_system
	var sc := _scale()
	var origin := _to_map(Vector3.ZERO)
	for belt in sys.belts:
		var bc := _to_map(belt.global_position)
		var w := maxf(belt.def.width / sc, 2.0)
		c.draw_arc(bc, belt.def.orbit_radius / sc, 0.0, TAU, 96, BELT_COLOR, w, true)
	for p in sys.planets:
		c.draw_arc(origin, p.def.orbit_radius / sc, 0.0, TAU, 96, ORBIT_COLOR, 1.0, true)
	for p in sys.planets:
		var pm := _to_map(p.global_position)
		c.draw_circle(pm, clampf(p.def.radius / sc, 2.0, 6.0), PLANET_COLOR.darkened(0.25))
	c.draw_circle(origin, 4.0, STAR_COLOR)
	c.draw_circle(origin, 7.0, Color(STAR_COLOR, 0.25))
	if is_instance_valid(sys.home_station):
		var hm := _to_map(sys.home_station.global_position)
		c.draw_rect(Rect2(hm - Vector2(3.5, 3.5), Vector2(7.0, 7.0)), HOME_COLOR, true)
		if markers:
			c.draw_arc(hm, markers.home_threat_radius / sc, 0.0, TAU, 64, Color(HOME_COLOR, 0.25), 1.0, true)
	var bubble := StationShield.find(get_tree())
	if bubble and bubble.is_up():
		var bc := _to_map(bubble.global_position)
		var br := maxf(bubble.radius / sc, 6.0)
		c.draw_arc(bc, br, 0.0, TAU, 48, Color(DefenseSection.SHIELD_COLOR, lerpf(0.35, 0.9, bubble.charge())), 1.5, true)
	_draw_view(c)
	var selected := hud.selection.selected if hud.selection else null
	var hostiles: Array[Node3D] = []
	for n in _map_targets():
		if n is ScavengerDen or (n as Ship).is_hostile():
			hostiles.append(n)
			continue
		var m := _to_map(n.global_position)
		_draw_warp_streak(c, n as Ship, m)
		c.draw_circle(m, 2.0, ShipMarkers.color_for(n))
	for n in hostiles:
		var m := _to_map(n.global_position)
		if n is Ship:
			_draw_warp_streak(c, n as Ship, m)
		if n is ScavengerDen:
			c.draw_rect(Rect2(m - Vector2(3.0, 3.0), Vector2(6.0, 6.0)), ShipMarkers.DEN_COLOR, false, 1.5)
		else:
			c.draw_circle(m, 2.4, ShipMarkers.color_for(n))
	if is_instance_valid(selected) and selected.is_inside_tree():
		c.draw_arc(_to_map(selected.global_position), 5.5, 0.0, TAU, 20, ShipMarkers.SELECT_COLOR, 1.5, true)
	c.draw_rect(Rect2(Vector2.ZERO, size), Color(0.5, 0.65, 0.85, 0.25), false, 1.0)


## The camera's footprint on the plane (screen corners), or its pivot.
## A short streak behind ships in a warp hop.
func _draw_warp_streak(c: Control, s: Ship, m: Vector2) -> void:
	if s.mover == null or s.mover.warp_state != ShipMover.Warp.WARP:
		return
	var back := _to_map(s.global_position - s.mover.warp_dir * 1800.0)
	c.draw_line(back, m, Color(ShipMarkers.color_for(s), 0.6), 1.5, true)


func _draw_view(c: Control) -> void:
	if hud.camera == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var pts := PackedVector2Array()
	for s: Vector2 in [Vector2(0.0, 0.0), Vector2(vp.x, 0.0), vp, Vector2(0.0, vp.y)]:
		var g := hud.camera.screen_to_ground(s)
		if g == Vector3.INF:
			pts.clear()
			break
		pts.append(_to_map(g))
	if pts.size() == 4:
		pts.append(pts[0])
		c.draw_polyline(pts, VIEW_COLOR, 1.0, true)
	var pm := _to_map(hud.camera.global_position)
	c.draw_line(pm - Vector2(3.0, 0.0), pm + Vector2(3.0, 0.0), VIEW_COLOR, 1.0)
	c.draw_line(pm - Vector2(0.0, 3.0), pm + Vector2(0.0, 3.0), VIEW_COLOR, 1.0)

class_name RTSCamera
extends Node3D
## Tilted top-down RTS camera. This node is the pivot on the y = 0 plane; the
## Camera3D child orbits it at [member distance] with a pitch that flattens up
## close and goes steeper (more top-down) far out. Inputs move targets; the view
## eases toward them (zoom eases in log space, so it feels exponential).
## Left-drag orbits freely all the way round: sideways turns around the pivot,
## up/down tilts over the top and under the plane (Home resets the tilt).
##
## Focus/follow: double-click a node in the "focusable" group (planet, moon,
## station, gate, star) to fly to it and follow it. Any manual pan breaks the
## follow. Home flies to [member home_target] (or [member home_position]),
## F fits the whole system.
##
## Focusable nodes may carry metas "focus_radius" (m, picking size) and
## "focus_distance" (m, camera distance after the fly).
##
## [method frame_area] flies to a view of a circle on the plane (build
## placement): follows a node with the pivot offset from it, fits the
## distance and eases the tilt to a set pitch, also back from over the top or
## under the plane.

signal view_changed(pivot: Vector3, distance: float, yaw_deg: float)
signal follow_changed(target: Node3D)

const FOCUS_GROUP := "focusable"

@export_group("Zoom")
@export var min_distance: float = 80.0
@export var max_distance: float = 1200.0
@export var default_distance: float = 700.0
## Fraction of the current distance per wheel notch.
@export_range(0.01, 0.5, 0.01) var zoom_step: float = 0.14
## Pitch (degrees below horizontal) at min and max distance.
@export_range(10.0, 89.0, 0.5) var pitch_near_deg: float = 42.0
@export_range(10.0, 89.0, 0.5) var pitch_far_deg: float = 58.0
## Shape of the pitch curve over log-zoom. 1 = linear, > 1 stays flat longer.
@export_range(0.2, 6.0, 0.05) var pitch_curve: float = 0.5
## Distance F zooms out to. 0 = max_distance.
@export var fit_distance: float = 0.0

@export_group("Clip planes")
## Near plane = distance * this. Keeps depth precision up close.
@export var near_factor: float = 0.004
@export var near_min: float = 0.05
## Far plane = distance + this.
@export var far_extent: float = 90000.0

@export_group("Pan")
## Pan speed as a fraction of the current distance per second.
@export var pan_speed: float = 1.1
@export var edge_pan_enabled: bool = true
@export var edge_pan_margin_px: int = 10
## Mouse button that drag-pans. Right is reserved for orders.
@export var drag_button: MouseButton = MOUSE_BUTTON_MIDDLE
## Option/Alt + left drag also pans (trackpads have no middle button).
## Trackpad two-finger scroll zoom, log-distance per gesture unit.
@export var trackpad_zoom_speed: float = 0.04
## Rectangle on the XZ plane the pivot is clamped to (x, z, width, depth).
## Ignored when [member bounds_radius] > 0.
@export var bounds: Rect2 = Rect2(-1500.0, -1500.0, 3000.0, 3000.0)
## Circular bounds around the origin. 0 = use [member bounds].
@export var bounds_radius: float = 0.0
@export var home_position: Vector3 = Vector3.ZERO

@export_group("Rotate")
@export var rotate_speed_deg: float = 90.0
@export var default_yaw_deg: float = 0.0
## Left-drag orbit: degrees per pixel of mouse travel.
@export var orbit_speed_deg: float = 0.5
## Mouse travel (px) before a left press turns into an orbit drag.
@export var orbit_threshold_px: float = 3.0

@export_group("Feel")
## Higher = snappier easing toward targets.
@export var smoothing: float = 9.0
## Easing of the fly-to when focusing a body.
@export var fly_smoothing: float = 3.2
## Easing of the fly to a framed area (position and tilt), see [method frame_area].
@export var frame_smoothing: float = 4.2
## Minimum pick radius around focusable bodies, pixels.
@export var pick_radius_px: float = 18.0

@onready var camera: Camera3D = $Camera3D

## Node Home flies to and follows. Null = [member home_position].
var home_target: Node3D

var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _target_dist := 700.0
var _pos := Vector3.ZERO
var _yaw := 0.0
var _dist := 700.0
var _dragging := false
## Edge pan stays off until the mouse has actually moved over the window
## (no drift at startup or in headless runs, where the cursor reads as 0,0).
var _mouse_seen := false
var _follow: Node3D
var _follow_offset := Vector3.ZERO
## Pivot offset from the followed node (world axes), kept while following.
var _follow_anchor := Vector3.ZERO
## Easing rate of the current fly (fly_smoothing or frame_smoothing).
var _fly_rate := 3.2
## Total pitch (degrees) the tilt eases to; NAN = no tilt fly.
var _pitch_goal := NAN
## Added to the zoom-driven pitch by left-drag orbiting, degrees.
var _pitch_bias := 0.0
var _left_down := false
var _left_travel := 0.0
var _left_pending := Vector2.ZERO
var _orbiting := false


func _ready() -> void:
	add_to_group("rts_camera")
	reset_view(true)
	# Launched from a terminal on macOS the window can open without keyboard focus.
	if DisplayServer.get_name() != "headless" and not Engine.is_editor_hint():
		DisplayServer.window_move_to_foreground()


func get_camera() -> Camera3D:
	return camera


func get_distance() -> float:
	return _dist


func get_follow_target() -> Node3D:
	return _follow if is_instance_valid(_follow) else null


## Home view: flies to [member home_target] and follows it, or eases to
## [member home_position]. snap = true places it immediately.
func reset_view(snap: bool = false) -> void:
	_target_yaw = deg_to_rad(default_yaw_deg)
	_pitch_bias = 0.0
	_pitch_goal = NAN
	if is_instance_valid(home_target):
		focus_on(home_target, default_distance, snap)
		return
	stop_follow()
	_target_pos = home_position
	_target_dist = default_distance
	if snap:
		_snap()


## Places the camera immediately, without following. Used by the screenshot mode.
func set_view(pivot_x: float, pivot_z: float, dist: float, yaw_deg: float) -> void:
	stop_follow()
	_target_pos = Vector3(pivot_x, 0.0, pivot_z)
	_target_dist = dist
	_target_yaw = deg_to_rad(yaw_deg)
	_snap()


func set_yaw(yaw_deg: float, snap: bool = false) -> void:
	_target_yaw = deg_to_rad(yaw_deg)
	if snap:
		_yaw = _target_yaw
		_apply()


func set_distance(dist: float, snap: bool = false) -> void:
	_target_dist = clampf(dist, min_distance, max_distance)
	if snap:
		_dist = _target_dist
		_apply()


## Flies to [param target] and follows it. dist < 0 uses its "focus_distance" meta.
func focus_on(target: Node3D, dist: float = -1.0, snap: bool = false) -> void:
	if not is_instance_valid(target):
		return
	if dist < 0.0:
		dist = float(target.get_meta(&"focus_distance", maxf(float(target.get_meta(&"focus_radius", 100.0)) * 5.0, min_distance)))
	_follow = target
	_follow_anchor = Vector3.ZERO
	_fly_rate = fly_smoothing
	_target_dist = clampf(dist, min_distance, max_distance)
	var tp := _ground(target.global_position)
	_follow_offset = Vector3.ZERO if snap else _pos - tp
	if snap:
		_pos = tp
		_target_pos = tp
		_dist = _target_dist
		_yaw = _target_yaw
		_apply()
	follow_changed.emit(_follow)


## Flies to a view of the circle of [param radius] around [param target]
## + [param center_offset] (plane, world axes) and follows [param target].
## The distance fits the circle on screen; the tilt eases to
## [param pitch_deg] (normalized from any orbit, over the top or under the
## plane); the yaw stays. With [param keep_good], only what is off changes:
## a pivot already near the centre stays put, a distance within
## [param distance_slack] (min, max factor of the fitted one) stays, a pitch
## within [param pitch_range] stays.
func frame_area(target: Node3D, center_offset: Vector3, radius: float, pitch_deg: float,
		keep_good: bool = false, snap: bool = false,
		distance_slack: Vector2 = Vector2(0.75, 1.6), pitch_range: Vector2 = Vector2(48.0, 80.0)) -> void:
	if not is_instance_valid(target):
		return
	var center := _ground(target.global_position) + _ground(center_offset)
	var need := fit_distance_for(radius)
	var dist := need
	if keep_good and _target_dist >= need * distance_slack.x and _target_dist <= need * distance_slack.y:
		dist = _target_dist
	var pitch := pitch_deg
	var now := current_pitch_deg()
	if keep_good and now >= pitch_range.x and now <= pitch_range.y:
		pitch = now
	var anchor := _ground(center_offset)
	if keep_good and _pos.distance_to(center) < radius * 0.25:
		anchor = _pos - _ground(target.global_position)
	var had := _follow
	_follow = target
	_follow_anchor = anchor
	_fly_rate = frame_smoothing
	_target_dist = clampf(dist, min_distance, max_distance)
	var tp := _ground(target.global_position) + anchor
	if snap:
		_follow_offset = Vector3.ZERO
		_pos = tp
		_target_pos = tp
		_dist = _target_dist
		_pitch_goal = NAN
		_pitch_bias = wrapf(pitch - _zoom_pitch_deg(), -180.0, 180.0)
		_apply()
	else:
		_follow_offset = _pos - tp
		_pitch_goal = pitch if absf(angle_difference(deg_to_rad(now), deg_to_rad(pitch))) > deg_to_rad(0.05) else NAN
	if had != _follow:
		follow_changed.emit(_follow)


## Camera distance that fits a circle of [param radius] on the plane in view.
func fit_distance_for(radius: float) -> float:
	var half := deg_to_rad(camera.fov) * 0.5 if camera else deg_to_rad(25.0)
	return radius / maxf(tan(half), 0.05)


## True while the tilt is still easing toward a framed pitch.
func is_framing() -> bool:
	return not is_nan(_pitch_goal) or _follow_offset.length() > maxf(_dist * 0.01, 1.0)


func stop_follow() -> void:
	if _follow == null:
		return
	_follow = null
	_follow_anchor = Vector3.ZERO
	_follow_offset = Vector3.ZERO
	_target_pos = _pos
	follow_changed.emit(null)


## Zooms out over the origin to show the whole system.
func fit_system() -> void:
	stop_follow()
	_target_pos = Vector3.ZERO
	_target_dist = fit_distance if fit_distance > 0.0 else max_distance


## Ray from the camera through a screen point, hit on the y = 0 plane.
## Returns Vector3.INF when the ray does not reach the plane.
func screen_to_ground(screen_pos: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 1e-5:
		return Vector3.INF
	var t := -origin.y / dir.y
	if t <= 0.0:
		return Vector3.INF
	return origin + dir * t


## Focusable node under a screen point, or null.
func pick_focusable(screen_pos: Vector2) -> Node3D:
	var best: Node3D = null
	var best_score := INF
	var vp_h := maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var px_per_rad := vp_h / (2.0 * tan(deg_to_rad(camera.fov) * 0.5))
	for node in get_tree().get_nodes_in_group(FOCUS_GROUP):
		var n := node as Node3D
		if n == null or not n.is_visible_in_tree():
			continue
		var p := n.global_position
		if camera.is_position_behind(p):
			continue
		var d := camera.global_position.distance_to(p)
		var r_px := float(n.get_meta(&"focus_radius", 50.0)) / maxf(d, 1.0) * px_per_rad
		var accept := maxf(r_px, pick_radius_px)
		var off := camera.unproject_position(p).distance_to(screen_pos)
		if off > accept:
			continue
		var score := off / accept
		if score < best_score:
			best_score = score
			best = n
	return best


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cam_zoom_in"):
		_target_dist = clampf(_target_dist * (1.0 - zoom_step), min_distance, max_distance)
	elif event.is_action_pressed("cam_zoom_out"):
		_target_dist = clampf(_target_dist * (1.0 + zoom_step), min_distance, max_distance)
	elif event.is_action_pressed("cam_reset"):
		reset_view()
	elif InputMap.has_action("cam_fit") and event.is_action_pressed("cam_fit"):
		fit_system()
	elif event is InputEventMagnifyGesture:
		# Trackpad pinch. factor > 1 = fingers apart = zoom in.
		var mg := event as InputEventMagnifyGesture
		_target_dist = clampf(_target_dist / maxf(mg.factor, 0.01), min_distance, max_distance)
		get_viewport().set_input_as_handled()
	elif event is InputEventPanGesture:
		# Trackpad two-finger scroll zooms, like a mouse wheel. Scroll down = zoom out.
		var pg := event as InputEventPanGesture
		_target_dist = clampf(_target_dist * exp(pg.delta.y * trackpad_zoom_speed), min_distance, max_distance)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var alt_drag := mb.button_index == MOUSE_BUTTON_LEFT and (mb.alt_pressed or not mb.pressed) and (mb.pressed or _dragging)
		if mb.button_index == drag_button or alt_drag:
			_dragging = mb.pressed
			if mb.pressed:
				get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and mb.double_click:
			var hit := pick_focusable(mb.position)
			if hit:
				focus_on(hit)
				get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			# Plain left press: a click (selection acts on release) unless the
			# mouse travels far enough first; then it orbits. The press is not consumed.
			_left_down = mb.pressed
			_left_travel = 0.0
			_left_pending = Vector2.ZERO
			if not mb.pressed and _orbiting:
				_orbiting = false
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _left_down and not _dragging \
			and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
		# The release went to someone else (a click that placed or selected).
		_mouse_seen = true
		_left_down = false
		_orbiting = false
	elif event is InputEventMouseMotion and _left_down and not _dragging:
		var mm := event as InputEventMouseMotion
		_mouse_seen = true
		_left_travel += mm.relative.length()
		_left_pending += mm.relative
		if _orbiting or _left_travel >= orbit_threshold_px:
			# The first move also applies the travel inside the click slop,
			# so the view does not lag behind the cursor.
			_orbiting = true
			_orbit(_left_pending)
			_left_pending = Vector2.ZERO
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and not _dragging:
		_mouse_seen = true
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_drag_pan(mm.position - mm.relative, mm.position)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_dragging = false
		_left_down = false
		_orbiting = false
	elif what == NOTIFICATION_WM_MOUSE_EXIT:
		_mouse_seen = false


func _process(delta: float) -> void:
	var gui_busy := get_viewport().gui_get_focus_owner() != null
	var move := Vector2.ZERO
	if not gui_busy:
		move = Vector2(Input.get_axis("cam_left", "cam_right"), Input.get_axis("cam_up", "cam_down"))
	if edge_pan_enabled and not _dragging and not _orbiting:
		move += _edge_pan_vector()
	if move.length_squared() > 1.0:
		move = move.normalized()
	if move != Vector2.ZERO:
		stop_follow()
		var speed := pan_speed * _target_dist * delta
		_target_pos += (_right() * move.x + _back() * move.y) * speed
		_target_pos = _clamp_to_bounds(_target_pos)

	if not gui_busy:
		var rot := Input.get_axis("cam_rotate_left", "cam_rotate_right")
		if rot != 0.0:
			_target_yaw += deg_to_rad(rotate_speed_deg) * rot * delta

	var k := 1.0 - exp(-smoothing * delta)
	if is_instance_valid(_follow):
		_follow_offset *= exp(-_fly_rate * delta)
		_target_pos = _ground(_follow.global_position) + _follow_anchor
		_pos = _target_pos + _follow_offset
	else:
		_follow = null
		_pos = _pos.lerp(_target_pos, k)
	_dist = exp(lerpf(log(_dist), log(_target_dist), k))
	_yaw = lerp_angle(_yaw, _target_yaw, k)
	if not is_nan(_pitch_goal):
		_ease_pitch(delta)
	_apply()


## Tilt fly: eases the orbit bias so the total pitch reaches [member _pitch_goal]
## along the shorter way round, then stops.
func _ease_pitch(delta: float) -> void:
	var k := 1.0 - exp(-_fly_rate * delta)
	var want := deg_to_rad(_pitch_goal - _zoom_pitch_deg())
	_pitch_bias = wrapf(rad_to_deg(lerp_angle(deg_to_rad(_pitch_bias), want, k)), -180.0, 180.0)
	var off := absf(angle_difference(deg_to_rad(current_pitch_deg()), deg_to_rad(_pitch_goal)))
	if off < deg_to_rad(0.1) and absf(log(_dist / _target_dist)) < 0.002:
		_pitch_goal = NAN


func _snap() -> void:
	_target_pos = _clamp_to_bounds(_target_pos)
	_target_dist = clampf(_target_dist, min_distance, max_distance)
	_pos = _target_pos
	_yaw = _target_yaw
	_dist = _target_dist
	_apply()


func _apply() -> void:
	position = _pos
	rotation = Vector3(0.0, _yaw, 0.0)
	var pitch := deg_to_rad(current_pitch_deg())
	camera.position = Vector3(0.0, sin(pitch), cos(pitch)) * _dist
	camera.rotation = Vector3(-pitch, 0.0, 0.0)
	camera.near = maxf(_dist * near_factor, near_min)
	camera.far = _dist + far_extent
	view_changed.emit(_pos, _dist, rad_to_deg(_yaw))


## True while a left drag is orbiting the camera (the click is then not a click).
func is_orbiting() -> bool:
	return _orbiting


## Pitch for the current distance (flatter when close, steeper when far),
## plus whatever the player added by orbiting. Unlimited: past 90 the camera
## goes over the top, below 0 it looks up from under the plane.
func current_pitch_deg() -> float:
	return wrapf(_zoom_pitch_deg() + _pitch_bias, -180.0, 180.0)


func _zoom_pitch_deg() -> float:
	var t := 0.0
	if max_distance > min_distance:
		t = clampf(log(_dist / min_distance) / log(max_distance / min_distance), 0.0, 1.0)
	return lerpf(pitch_near_deg, pitch_far_deg, pow(t, pitch_curve))


## Left-drag orbit around the pivot: x turns, y tilts. Drag up = look more
## level, drag down = look more straight down.
func _orbit(rel: Vector2) -> void:
	_pitch_goal = NAN
	_target_yaw -= deg_to_rad(rel.x * orbit_speed_deg)
	_yaw = _target_yaw
	_pitch_bias = wrapf(_pitch_bias + rel.y * orbit_speed_deg, -180.0, 180.0)
	_apply()


## Grab-and-drag: the ground point under the cursor stays under the cursor.
func _drag_pan(from_px: Vector2, to_px: Vector2) -> void:
	stop_follow()
	var a := screen_to_ground(from_px)
	var b := screen_to_ground(to_px)
	var delta := Vector3.ZERO
	var max_jump := _dist * 4.0
	if a != Vector3.INF and b != Vector3.INF and a.distance_to(b) < max_jump \
			and a.distance_to(_pos) < max_jump and b.distance_to(_pos) < max_jump:
		delta = a - b
	else:
		var vp_h := maxf(get_viewport().get_visible_rect().size.y, 1.0)
		var world_per_px := 2.0 * _dist * tan(deg_to_rad(camera.fov) * 0.5) / vp_h
		var pitch := deg_to_rad(current_pitch_deg())
		var rel := to_px - from_px
		delta = -(_right_of(_yaw) * rel.x * world_per_px) \
				- _back_of(_yaw) * rel.y * world_per_px / maxf(sin(pitch), 0.2)
	_pos = _clamp_to_bounds(_pos + delta)
	_target_pos = _pos
	_apply()


func _edge_pan_vector() -> Vector2:
	if not _mouse_seen or not DisplayServer.window_is_focused():
		return Vector2.ZERO
	var vp := get_viewport()
	var rect := vp.get_visible_rect()
	var m := vp.get_mouse_position()
	if not rect.has_point(m):
		return Vector2.ZERO
	var v := Vector2.ZERO
	if m.x <= edge_pan_margin_px:
		v.x -= 1.0
	elif m.x >= rect.size.x - edge_pan_margin_px:
		v.x += 1.0
	if m.y <= edge_pan_margin_px:
		v.y -= 1.0
	elif m.y >= rect.size.y - edge_pan_margin_px:
		v.y += 1.0
	return v


func _right() -> Vector3:
	return _right_of(_target_yaw)


func _back() -> Vector3:
	return _back_of(_target_yaw)


static func _right_of(yaw: float) -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))


static func _back_of(yaw: float) -> Vector3:
	return Vector3(sin(yaw), 0.0, cos(yaw))


static func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)


func _clamp_to_bounds(p: Vector3) -> Vector3:
	if bounds_radius > 0.0:
		var g := _ground(p)
		return g.limit_length(bounds_radius)
	return Vector3(
			clampf(p.x, bounds.position.x, bounds.end.x),
			0.0,
			clampf(p.z, bounds.position.y, bounds.end.y))

class_name RideAlong
extends PanelContainer
## Ride along with one captain: a low chase camera behind their ship that
## turns with it, and in a fight swings to face the target and pulls back
## so both stay in view. It follows the captain, not the ship node: the
## node is freed at each gate jump and rebuilt on the far side
## ([GateTransit]), so while the ship is data the view goes ahead to the
## system it will come out in (or the one it is parked in) and picks the
## new node up when it appears. A lost captain holds the view for
## [constant LOST_HOLD] s, then the ride ends.
## Start: V with a player ship selected, or the captain panel's Ride
## button ([method start]). Stop: V again, Esc, panning the camera, or
## focusing something else (the camera's follow moves off the ship).
## The banner at the top centre names the captain and what they are doing
## ([method PilotCard.status_text]).

const H := preload("res://scripts/ui/theme/hud_style.gd")

## Total camera pitch while riding, degrees below the horizon.
const CHASE_PITCH := 14.0
## Chase distance in ship hit radii (clamped to the camera's range).
const CHASE_RADII := 11.0
const CHASE_MAX := 420.0
## How fast the view turns after the ship (1/s, exponential).
const YAW_RATE := 1.8
## In a fight the camera pulls back to this share of the gap to the target.
const FIGHT_GAP := 1.15
const FIGHT_MAX := 2600.0
## Real seconds the view stays on a lost captain.
const LOST_HOLD := 3.0
const STATUS_EVERY := 0.25

var hud: HUD
var captain: Captain

var _ship: Ship
var _cam: RTSCamera
## Player orbit on top of the automatic heading, radians.
var _yaw_off := 0.0
var _orbited := false
var _fighting := false
var _calm_dist := -1.0
var _lost_at := -1.0
## System the view was last sent to while the ship is data.
var _sent_to: StringName = &""
var _status_clock := 0.0
var _name: Label
var _status: Label


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var head := UIUtil.label("RIDING WITH", &"HeaderLabel")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	_name = UIUtil.label("", &"TitleLabel")
	_name.add_theme_color_override("font_color", H.ACCENT)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_name)
	_status = UIUtil.label("", &"")
	_status.add_theme_color_override("font_color", H.HOLO)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_status)
	var hint := UIUtil.label("V, Esc or pan to stop", &"")
	hint.add_theme_color_override("font_color", H.TEXT_DIM)
	hint.add_theme_font_size_override("font_size", 11)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)


func setup(owner_hud: HUD) -> void:
	hud = owner_hud


func is_riding() -> bool:
	return captain != null


## Starts riding with [param c] (a hired player captain).
func start(c: Captain) -> void:
	if c == null or not c.alive or hud == null:
		return
	stop()
	captain = c
	_yaw_off = 0.0
	_lost_at = -1.0
	_sent_to = &""
	_name.text = "%s  ·  %s" % [c.captain_name, c.get_personality_name()]
	_status_clock = 0.0
	visible = true
	_place.call_deferred()


func stop() -> void:
	if captain == null:
		return
	captain = null
	_ship = null
	_bind_camera(null)
	_fighting = false
	_calm_dist = -1.0
	visible = false


## The selected ship's captain, when it is one of the player's.
func selected_captain() -> Captain:
	var s := hud.selection.selected as Ship if hud and hud.selection else null
	if s == null or s.captain == null or s.faction != Combat.Faction.PLAYER:
		return null
	return s.captain


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or k.physical_keycode != KEY_V \
			or k.ctrl_pressed or k.meta_pressed or k.alt_pressed:
		return
	if is_riding():
		stop()
	else:
		var c := selected_captain()
		if c == null:
			return
		start(c)
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if is_riding() and event.is_action_pressed("ui_cancel") and not event.is_echo():
		stop()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if captain == null:
		return
	if hud == null or not hud.visible:
		stop()
		return
	_status_clock -= delta
	if _status_clock <= 0.0:
		_status_clock = STATUS_EVERY
		_status.text = _status_line()
	if not captain.alive:
		_hold_lost()
		return
	var s := captain.ship
	if is_instance_valid(s) and s.is_inside_tree() and not s.dead:
		_sent_to = &""
		if s != _ship or _cam != hud.camera:
			_attach(s)
		if _cam:
			_chase(s, delta)
		return
	_ship = null
	_go_where_data()


func _status_line() -> String:
	if captain == null:
		return ""
	if not captain.alive:
		return "Lost"
	var s := captain.ship if is_instance_valid(captain.ship) else null
	var line := PilotCard.status_text(captain, s)
	var jump := _transit_target()
	if s == null and jump != &"" and hud.view_manager:
		line = "Jumping to %s" % hud.view_manager.system_name(jump)
	return line


func _hold_lost() -> void:
	if _lost_at < 0.0:
		_lost_at = Time.get_ticks_msec() / 1000.0
		_bind_camera(null)
	if Time.get_ticks_msec() / 1000.0 - _lost_at >= LOST_HOLD:
		stop()


## Shows [param s]'s system and puts the chase camera on it.
func _attach(s: Ship) -> void:
	if not hud.show_system_of(s):
		return
	_ship = s
	var cam := hud.camera
	# A new system's camera cuts straight to the ship (the view switch
	# faded); the first attach flies in.
	var snap := is_instance_valid(_cam) and _cam != cam
	_bind_camera(null)
	if cam == null:
		return
	var dist := clampf(s.hit_radius * CHASE_RADII, cam.min_distance, CHASE_MAX)
	_fighting = false
	_calm_dist = dist
	cam.focus_on(s, dist, snap)
	cam.set_pitch(CHASE_PITCH)
	cam.set_yaw(rad_to_deg(_heading_yaw(s) + _yaw_off), true)
	_bind_camera(cam)


func _bind_camera(cam: RTSCamera) -> void:
	if is_instance_valid(_cam) and _cam.follow_changed.is_connected(_on_follow):
		_cam.follow_changed.disconnect(_on_follow)
	_cam = cam
	if _cam:
		_cam.follow_changed.connect(_on_follow)


## The camera's follow moved off the ship: the player panned or focused
## something else.
func _on_follow(target: Node3D) -> void:
	if captain != null and target != _ship:
		stop()


func _chase(s: Ship, delta: float) -> void:
	var foe := s.get(&"_fight_target") as Node3D
	var fight := is_instance_valid(foe) and foe.is_inside_tree() and foe.get_viewport() == s.get_viewport()
	if fight != _fighting:
		_fighting = fight
		if fight:
			_calm_dist = _cam.get_distance()
		else:
			_cam.set_distance(_calm_dist)
			_cam.set_pitch(CHASE_PITCH)
	if fight:
		var gap := s.global_position.distance_to(foe.global_position)
		_cam.set_distance(clampf(gap * FIGHT_GAP, _calm_dist, FIGHT_MAX))
	var auto := _look_yaw(s, foe if fight else null)
	var cur := _cam.rotation.y
	if _cam.is_orbiting():
		_orbited = true
		return
	if _orbited:
		# The drag ended: keep the turn the player gave the view.
		_orbited = false
		_yaw_off = wrapf(cur - auto, -PI, PI)
	var want := auto + _yaw_off
	var k := 1.0 - exp(-YAW_RATE * delta)
	_cam.set_yaw(rad_to_deg(lerp_angle(cur, want, k)), true)


## Camera yaw that looks along [param s]'s nose, or from it toward [param foe].
func _look_yaw(s: Ship, foe: Node3D) -> float:
	if foe:
		var d := foe.global_position - s.global_position
		if Vector2(d.x, d.z).length() > 1.0:
			return atan2(-d.x, -d.z)
	return _heading_yaw(s)


func _heading_yaw(s: Ship) -> float:
	var nose := -s.global_basis.z
	if Vector2(nose.x, nose.z).length() < 0.05:
		return _cam.rotation.y if _cam else 0.0
	return atan2(-nose.x, -nose.z)


## The ship is data (in a jump, or parked in a system nobody views): send
## the view to where it will show up, once per place.
func _go_where_data() -> void:
	var to := _transit_target()
	if to == &"":
		to = _parked_in()
	if to == &"" or to == _sent_to or hud.view_manager == null:
		return
	_sent_to = to
	if hud.view_manager.viewed_id() != to and hud.view_manager.can_view(to):
		hud.view_manager.view(to)


func _transit_target() -> StringName:
	var id := SaveIds.of(captain)
	for t: Dictionary in Sector.transits:
		var d: Dictionary = t.get("ship", {})
		if int(d.get("captain", -1)) == id:
			return StringName(t.get("to", &""))
	return &""


func _parked_in() -> StringName:
	if Sector.network == null:
		return &""
	var id := SaveIds.of(captain)
	for sid in Sector.network.remote_ids():
		var st := Sector.state(sid)
		if st == null:
			continue
		for d: Dictionary in st.ships:
			if int(d.get("captain", -1)) == id:
				return sid
	return &""


## Top centre, under the top bar.
func _place() -> void:
	reset_size()
	var vp := get_viewport_rect().size
	position = Vector2((vp.x - size.x) * 0.5, 64.0)

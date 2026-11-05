class_name SurfaceMode
extends CanvasLayer
## Planet mode (planet outposts plan): the surface of one outpost on screen.
## A CanvasLayer over the HUD with its own SubViewport (own World3D) holding
## the live [SurfaceWorld] and the [SurfaceHud]. Entering hides the station
## HUD, stops the system view drawing and its camera taking input, and tells
## [Outposts] this outpost runs live; [method leave] (UP, Backspace, H)
## undoes it all and frees the surface (its data sim carries on). The system
## keeps simulating underneath the whole time.
##
## Camera: a tilted RTS view of the landing zone, pan with WASD, the arrows
## or a middle / right drag, zoom with the wheel, turn with Q / E. Clicks
## pick on the ground (SurfaceTerrain.raycast): select, or place a building
## while the HUD is placing one.

const GROUP := "surface_mode"
const LAYER := 11
const DIST := Vector2(90.0, 2600.0)
const PITCH := deg_to_rad(52.0)
## Pitch at the closest zoom: the camera levels out as it comes in, so the
## horizon and the sky (star, parent planet) show up close to the ground.
const PITCH_LOW := deg_to_rad(20.0)
## Zoom distance from which the full [constant PITCH] holds, m.
const LEVEL_FROM := 900.0
## Real seconds of the fade in from black on entering and leaving.
const FADE := 0.45

var outpost: OutpostState
var world: SurfaceWorld
var hud: SurfaceHud
var _container: SubViewportContainer
var _viewport: SubViewport
var _pivot := Vector2.ZERO
var _yaw := 0.6
var _dist := 520.0
var _target_dist := 520.0
var _drag := false
var _drag_from := Vector2.ZERO
## The system world hidden under the surface (restored on leaving).
var _hidden: SystemWorld
## Key actions that still reach the game below (sim speed, pause menu).
const PASS_ACTIONS: Array[StringName] = [&"sim_pause", &"sim_speed_1", &"sim_speed_2", &"sim_speed_3", &"sim_speed_4", &"sim_speed_5",
		&"sim_speed_6", &"sim_speed_up", &"sim_speed_down", &"ui_cancel"]


static func of(tree: SceneTree) -> SurfaceMode:
	return tree.get_first_node_in_group(GROUP) as SurfaceMode if tree else null


## Shows the surface of [param o] (founded outposts only). Null when it cannot.
static func enter(tree: SceneTree, o: OutpostState) -> SurfaceMode:
	if o == null or not o.is_founded() or tree == null:
		return null
	var have := of(tree)
	if have:
		if have.outpost == o:
			return have
		have.leave()
	var vm := ViewManager.of(tree)
	if vm == null:
		return null
	var sm := SurfaceMode.new()
	sm.outpost = o
	vm.add_child(sm)
	return sm


func _ready() -> void:
	add_to_group(GROUP)
	layer = LAYER
	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.audio_listener_enable_3d = true
	_viewport.msaa_3d = get_viewport().msaa_3d
	_container.add_child(_viewport)
	world = SurfaceWorld.new()
	world.setup(outpost)
	_viewport.add_child(world)
	hud = SurfaceHud.new()
	hud.setup(self)
	add_child(hud)
	_set_station_view(false)
	var vm := ViewManager.of(get_tree())
	if vm:
		# Any view switch (founding, a station lost) ends planet mode first.
		vm.view_changed.connect(_on_view_changed)
	var o := Outposts.of(get_tree())
	if o:
		o.live = outpost
	_apply_camera()
	fade_in(get_tree())
	EventLog.post("Down on the surface of %s" % outpost.planet, EventLog.Kind.INFO)


## A black cover over everything that fades out over [constant FADE] real
## seconds: the cut into or out of planet mode reads as a fade. It never
## takes input and runs while the game is paused.
static func fade_in(tree: SceneTree) -> void:
	if tree == null:
		return
	var layer := CanvasLayer.new()
	layer.name = "SurfaceFade"
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var rect := ColorRect.new()
	rect.color = Color(0.0, 0.0, 0.0, 1.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	var host: Node = ViewManager.of(tree)
	(host if host else tree.root).add_child(layer)
	var tw := layer.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(rect, "color:a", 0.0, FADE).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(layer.queue_free)


func _on_view_changed(_w: SystemWorld) -> void:
	leave.call_deferred()


## Back to orbit: the surface is freed, the station HUD and view come back.
func leave() -> void:
	if is_queued_for_deletion():
		return
	var o := Outposts.of(get_tree())
	if o and o.live == outpost:
		o.live = null
	if o and world and not outpost.lost:
		world.sync_trips()
		var left := world.hostiles_left()
		for kind: String in left:
			o.resolve_attack(outpost, float(left[kind]), kind, "the %s still on the ground" % kind)
	_set_station_view(true)
	fade_in(get_tree())
	queue_free()


func _set_station_view(on: bool) -> void:
	var main_hud := get_tree().get_first_node_in_group(HUD.GROUP) as CanvasLayer
	if main_hud:
		main_hud.visible = on
	var vm := ViewManager.of(get_tree())
	if not on:
		_hidden = vm.viewed if vm else null
		# Panels open in orbit would keep taking Escape under the hidden HUD.
		var h := main_hud as HUD
		if h:
			if h.ledger and h.ledger.visible:
				h.ledger.close_panel()
			if h.rival_panel and h.rival_panel.visible:
				h.rival_panel.close_panel()
			if h.cluster_map and h.cluster_map.visible:
				h.cluster_map.close_map()
	var w := _hidden
	if on and vm and vm.viewed != _hidden:
		# The view moved while hidden: the old world gets its input back too.
		if is_instance_valid(_hidden) and _hidden.camera:
			_hidden.camera.set_process_unhandled_input(true)
		w = vm.viewed
	if w and is_instance_valid(w):
		var c := w.get_viewport().get_parent() as SystemView
		if c:
			c.set_shown(on)
		if w.camera:
			w.camera.input_enabled = on
			w.camera.set_process_unhandled_input(on)


func _process(delta: float) -> void:
	var move := Vector2(Input.get_axis("cam_left", "cam_right"), Input.get_axis("cam_up", "cam_down"))
	if get_viewport().gui_get_focus_owner() == null and move != Vector2.ZERO:
		var right := Vector2(cos(_yaw), -sin(_yaw))
		var back := Vector2(sin(_yaw), cos(_yaw))
		_pivot += (right * move.x + back * move.y) * _dist * 0.9 * delta
	var rot := Input.get_axis("cam_rotate_left", "cam_rotate_right")
	if rot != 0.0:
		_yaw += rot * 1.6 * delta
	var lim := OutpostState.ZONE_SIZE * 0.5
	_pivot = _pivot.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
	_dist = lerpf(_dist, _target_dist, clampf(delta * 8.0, 0.0, 1.0))
	_apply_camera()


func _apply_camera() -> void:
	if world == null or world.camera == null:
		return
	var target := world.deck_at(_pivot.x, _pivot.y)
	var pitch := lerpf(PITCH_LOW, PITCH, smoothstep(DIST.x, LEVEL_FROM, _dist))
	var off := Vector3(sin(_yaw) * cos(pitch), sin(pitch), cos(_yaw) * cos(pitch)) * _dist
	var pos := target + off
	# Low and close, a hill behind the pivot could swallow the camera.
	var ground := world.terrain.height(pos.x, pos.z)
	if world.terrain.has_liquid():
		ground = maxf(ground, SurfaceTerrain.LIQUID_LEVEL)
	pos.y = maxf(pos.y, ground + 15.0)
	world.camera.global_position = pos
	world.camera.look_at(target, Vector3.UP)


## Ground point under screen position [param sp] (HUD coordinates), INF when none.
func ground_under(sp: Vector2) -> Vector3:
	var cam := world.camera
	var vp_size := _viewport.get_visible_rect().size
	var root_size := get_viewport().get_visible_rect().size
	var p := sp * vp_size / root_size
	return world.terrain.raycast(cam.project_ray_origin(p), cam.project_ray_normal(p))


## Keys first, before the hidden station HUD's shortcuts (_unhandled_key_input
## runs before _unhandled_input): Backspace or H leaves, sim speed, pause and
## the window keys pass, every other key stops here (the camera keys are read
## by polling in _process, which consuming the event does not affect).
func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return
	var plain := not (k.ctrl_pressed or k.meta_pressed or k.alt_pressed or k.shift_pressed)
	if not k.echo and plain and (k.physical_keycode == KEY_BACKSPACE or k.physical_keycode == KEY_H):
		leave()
		get_viewport().set_input_as_handled()
		return
	if not k.echo and k.is_action("ui_cancel"):
		_escape()
		get_viewport().set_input_as_handled()
		return
	# Shift+1..3 is the hidden HUD's view switch; other shifted keys ('+') may pass.
	var shift_digit := k.shift_pressed and k.physical_keycode >= KEY_0 and k.physical_keycode <= KEY_9
	if not shift_digit:
		for a in PASS_ACTIONS:
			if k.is_action(a):
				return
	if k.keycode == KEY_F11 or (k.keycode == KEY_ENTER and k.alt_pressed) or (k.keycode == KEY_F and k.meta_pressed and k.ctrl_pressed) or (k.meta_pressed and k.keycode == KEY_Q):
		return
	get_viewport().set_input_as_handled()


## Escape: cancel placing or the selection down here, else the pause menu
## (handled here, or the hidden orbit selection would take it first).
func _escape() -> void:
	var pm := get_tree().root.get_node_or_null(^"PauseMenu")
	if pm and pm.call(&"is_open"):
		pm.call(&"close")
	elif hud and (not hud.placing.is_empty() or hud.has_selection()):
		hud.cancel()
	elif pm:
		pm.call(&"open")


func _unhandled_input(event: InputEvent) -> void:
	var mag := event as InputEventMagnifyGesture
	if mag:
		_target_dist = clampf(_target_dist / maxf(mag.factor, 0.01), DIST.x, DIST.y)
		get_viewport().set_input_as_handled()
		return
	var pan := event as InputEventPanGesture
	if pan:
		_target_dist = clampf(_target_dist * exp(pan.delta.y * 0.05), DIST.x, DIST.y)
		get_viewport().set_input_as_handled()
		return
	var mb := event as InputEventMouseButton
	if mb:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_target_dist = clampf(_target_dist * 0.88, DIST.x, DIST.y)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_target_dist = clampf(_target_dist * 1.14, DIST.x, DIST.y)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE or (mb.button_index == MOUSE_BUTTON_RIGHT and hud.placing.is_empty()):
			_drag = mb.pressed
			_drag_from = mb.position
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var p := ground_under(mb.position)
			if p != Vector3.INF:
				hud.clicked(p)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			hud.cancel()
		get_viewport().set_input_as_handled()
		return
	var mm := event as InputEventMouseMotion
	if mm:
		if _drag:
			var d := mm.position - _drag_from
			_drag_from = mm.position
			var right := Vector2(cos(_yaw), -sin(_yaw))
			var back := Vector2(sin(_yaw), cos(_yaw))
			_pivot -= (right * d.x + back * d.y) * _dist * 0.0016
		hud.hover(mm.position)
		get_viewport().set_input_as_handled()

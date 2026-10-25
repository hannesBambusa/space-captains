class_name ConstructionDrone
extends Node3D
## One small worker drone of a construction site ([ConstructionDrones],
## its parent, in building space). Cosmetic only: no collision, no groups,
## not saved. Flies in from the station, then loops: pick a work point near
## the build line, fly there (around the structure, not through it), settle,
## face it, swing the arm down and weld (beam, glow and sparks), move on.
## [method depart] sends it back to the station, where it fades out.
## Driven by the site every frame ([method step]) on sim time.

enum Mode { ARRIVE, TRAVEL, SETTLE, WELD, LEAVE, GONE }

const CRUISE_SPEED := 32.0
const WORK_SPEED := 14.0
const ACCEL := 3.4
const FADE_TIME := 0.5
## Sim seconds a leaving drone flies toward the station before it fades out.
const LEAVE_TIME := 3.5
## Weld tip rest offset from the arm's shoulder, used when the model has no weld_tip.
const TIP_FALLBACK := Vector3(0.0, -0.5, -0.34)

var mode: Mode = Mode.ARRIVE
## The point being welded (building space), valid while welding.
var work_point := Vector3.ZERO

var _site: ConstructionDrones
var _index := 0
var _model: Node3D
var _arm: Node3D
var _tip: Node3D
var _light: Node3D
var _beam: MeshInstance3D
var _glow: MeshInstance3D
var _sparks: CPUParticles3D
var _pos := Vector3.ZERO
var _vel := Vector3.ZERO
var _path: Array[Vector3] = []
var _hover := Vector3.ZERO
var _work_normal := Vector3.UP
var _timer := 0.0
var _delay := 0.0
var _started := false
var _has_job := false
var _home := Vector3.ZERO
var _yaw := 0.0
var _yaw_rate := 0.0
var _roll := 0.0
var _pitch := 0.0
var _arm_angle := 0.0
var _fade := 0.0
var _phase := 0.0
var _clock := 0.0
var _scale := 1.0
var _tip_rest := TIP_FALLBACK


func setup(site: ConstructionDrones, index: int, model: Node3D, start: Vector3, delay: float, drone_scale: float) -> void:
	_site = site
	_index = index
	_model = model
	_pos = start
	_home = start
	_delay = delay
	_scale = drone_scale
	_phase = float(index) * 1.7
	name = "Drone%d" % index


func _ready() -> void:
	add_child(_model)
	_model.scale = Vector3.ONE * _scale
	_arm = _model.find_child("drone_arm", true, false) as Node3D
	_tip = _model.find_child("weld_tip", true, false) as Node3D
	_light = _model.find_child("drone_light", true, false) as Node3D
	if _arm and _tip:
		_tip_rest = ModelLoader.relative_transform(_arm, _tip).origin
	for mi in ModelLoader.meshes_of(_model):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = ConstructionDrones.VISIBLE_RANGE
	MeshUtil.set_layers_recursive(_model, Building.RENDER_LAYER)
	_beam = _site.make_beam()
	_glow = _site.make_glow()
	_sparks = _site.make_sparks()
	position = _pos
	visible = false
	_yaw = ShipMover.yaw_for(_site.box_center() - _pos)


func _exit_tree() -> void:
	for n: Node in [_beam, _glow, _sparks]:
		if is_instance_valid(n):
			n.queue_free()


func is_gone() -> bool:
	return mode == Mode.GONE


func is_welding() -> bool:
	return mode == Mode.WELD


## Fly back to [param home] (building space) and fade out there.
func depart(home: Vector3) -> void:
	if mode == Mode.GONE or mode == Mode.LEAVE:
		return
	_home = home
	mode = Mode.LEAVE
	_path = [_pos + Vector3.UP * 4.0, home]
	_timer = 0.0
	_stop_fx()


## [param dt] sim seconds (0 while paused), [param real_dt] for the idle
## bob. [param snap]: the sim jumped (fast-forward), skip to the goal.
func step(dt: float, real_dt: float, paused: bool, snap: bool) -> void:
	if mode == Mode.GONE:
		return
	_clock += real_dt
	if not _started:
		_delay -= dt
		if _delay > 0.0:
			return
		_started = true
		visible = true
		if mode == Mode.ARRIVE:
			_next_job()
			if not _has_job:
				_path = _site.route(_pos, _site.approach_point(_index))
			mode = Mode.ARRIVE
	if snap:
		_snap()
	var left := dt
	while left > 0.0:
		var h := minf(left, 1.0 / 30.0)
		_think(h)
		_move(h)
		left -= h
	_fade = clampf(_fade + (dt / FADE_TIME) * (-1.0 if mode == Mode.LEAVE and _timer < 0.0 else 1.0), 0.0, 1.0)
	_pose(dt, paused)
	if mode == Mode.LEAVE and _timer < 0.0 and _fade <= 0.0:
		mode = Mode.GONE
		visible = false


func _think(h: float) -> void:
	match mode:
		Mode.ARRIVE, Mode.TRAVEL:
			if _path.is_empty():
				mode = Mode.SETTLE
				_timer = 0.25
		Mode.SETTLE:
			if not _has_job or (_pos.distance_to(_hover) < 1.2 and _vel.length() < 3.0):
				_timer -= h
			if _timer <= 0.0 and _has_job:
				mode = Mode.WELD
				_timer = randf_range(1.3, 2.6)
		Mode.WELD:
			_timer -= h
			if _timer <= 0.0 or _site.point_built_over(work_point):
				_stop_fx()
				_next_job()
		Mode.LEAVE:
			if _timer >= 0.0:
				_timer += h
				if _path.is_empty() or _timer > LEAVE_TIME:
					_timer = -1.0
	if mode == Mode.SETTLE and not _has_job and _timer <= 0.0:
		_next_job()


## Picks the next work point and flies there.
func _next_job() -> void:
	var job := _site.pick_work_point(_index, _pos)
	_has_job = not job.is_empty()
	if not _has_job:
		mode = Mode.SETTLE
		_timer = 0.8
		return
	work_point = job[0]
	_work_normal = job[1]
	_hover = _site.hover_point(work_point, _work_normal)
	_path = _site.route(_pos, _hover)
	mode = Mode.TRAVEL


func _snap() -> void:
	if mode == Mode.LEAVE:
		_timer = -1.0
		_fade = 0.0
		return
	if not _path.is_empty():
		_pos = _path.back()
		_path.clear()
	_vel = Vector3.ZERO


func _move(h: float) -> void:
	var goal := _path[0] if not _path.is_empty() else (_hover if mode != Mode.LEAVE else _pos)
	var to := goal - _pos
	var dist := to.length()
	var remaining := dist
	for i in range(1, _path.size()):
		remaining += _path[i - 1].distance_to(_path[i])
	var top := CRUISE_SPEED if remaining > 45.0 else WORK_SPEED
	var speed := minf(top, remaining * 2.2 + 0.4) if _path.size() <= 1 else top
	var desired := to / dist * speed if dist > 0.01 else Vector3.ZERO
	_vel = _vel.lerp(desired, 1.0 - exp(-ACCEL * h))
	_pos += _vel * h
	if not _path.is_empty() and _path.size() > 1 and dist < 3.0:
		_path.pop_front()
	elif not _path.is_empty() and _path.size() == 1 and dist < 0.8:
		_path.pop_front()


## Model pose: position with a hover bob, yaw toward travel or the work point,
## banking into turns, arm aimed while welding.
func _pose(dt: float, paused: bool) -> void:
	var bob := Vector3(0.0, sin(_clock * 1.9 + _phase) * 0.22, 0.0) * _scale
	position = _pos + bob
	var speed := SpaceNav.flat_length(_vel)
	var want := _yaw
	if mode == Mode.WELD or mode == Mode.SETTLE:
		var d := work_point - _pos
		if SpaceNav.flat_length(d) > 0.2:
			want = ShipMover.yaw_for(d)
	elif speed > 1.5:
		want = ShipMover.yaw_for(_vel)
	var k := 1.0 - exp(-4.0 * dt)
	var dy := wrapf(want - _yaw, -PI, PI) * k
	_yaw += dy
	_yaw_rate = lerpf(_yaw_rate, dy / dt if dt > 0.0 else 0.0, k)
	_roll = lerpf(_roll, clampf(-_yaw_rate * speed * 0.05, -0.55, 0.55), k)
	var fwd := -Basis(Vector3.UP, _yaw).z
	_pitch = lerpf(_pitch, clampf(-_vel.dot(fwd) * 0.012, -0.3, 0.2), k)
	basis = Basis.from_euler(Vector3(_pitch, _yaw, _roll))
	_model.scale = Vector3.ONE * _scale * maxf(_fade, 0.001)
	if _light:
		_light.scale = Vector3.ONE * (1.0 + 0.18 * sin(_clock * 5.0 + _phase))
	var welding := mode == Mode.WELD and not paused
	if _arm:
		var aim := 0.0
		if mode == Mode.WELD:
			aim = _arm_aim() + sin(_clock * 9.0 + _phase) * 0.1
		_arm_angle = lerpf(_arm_angle, aim, 1.0 - exp(-6.0 * dt)) if dt > 0.0 else _arm_angle
		_arm.rotation.x = _arm_angle
	_beam.visible = welding
	_glow.visible = welding
	_sparks.speed_scale = 0.0 if paused else clampf(SimClock.speed, 0.0, 4.0)
	_sparks.emitting = welding
	if welding:
		_aim_fx()


## Arm angle about its X axis that points the weld tip at the work point.
func _arm_aim() -> float:
	if _model == null or not _model.is_inside_tree():
		return 0.0
	var t := _model.global_transform.affine_inverse() * _site.to_global(work_point)
	t -= _arm.position if _arm else Vector3.ZERO
	var want := atan2(t.y, -t.z)
	var rest := atan2(_tip_rest.y, -_tip_rest.z)
	return clampf(want - rest, -1.2, 0.9)


func _aim_fx() -> void:
	var tip := _site.to_local(_tip.global_position) if _tip else _pos
	var d := work_point - tip
	var length := d.length()
	if length < 0.05:
		_beam.visible = false
	else:
		var y := d
		var x := y.cross(Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT).normalized()
		var z := x.cross(y).normalized()
		_beam.transform = Transform3D(Basis(x, y, z), tip + d * 0.5)
	var flick := 0.75 + 0.25 * sin(_clock * 37.0 + _phase) * sin(_clock * 23.0)
	_beam.set_instance_shader_parameter("strength", flick)
	_glow.position = work_point + _work_normal * 0.12
	_glow.scale = Vector3.ONE * (0.75 + 0.35 * flick)
	_sparks.transform = Transform3D(_site.basis_up_to(_work_normal), work_point + _work_normal * 0.1)


func _stop_fx() -> void:
	if _beam:
		_beam.visible = false
		_glow.visible = false
		_sparks.emitting = false

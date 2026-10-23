class_name ShipMover
extends RefCounted
## Movement for every ship (miners now, mercenaries and scavengers later).
## Flies on the plane in the ship's parent frame: limited acceleration that
## works best along the nose, max speed, turn rate, banking, arrival with
## velocity matching (so moving targets like orbiting outposts and rotating
## asteroids can be reached), and steering around the star, planets, moons and
## the station hub while in the world frame.
## Height: in a building frame the ship eases to the goal's height at
## [member climb_speed]. In the world frame the owner sets [member cruise_y]
## every step (belt lanes, see Ship) and the ship climbs or dives toward it
## with limited vertical acceleration, at most [member climb_angle_deg] steep,
## pitching the nose into the climb ([member pitch], visual only).
##
## Goals come in two forms:
## - [method set_goal]: one target, refreshed every step by the owner for
##   moving targets (position and velocity in the parent frame).
## - [method set_path]: a list of fixed [Waypoint]s in the parent frame
##   (docking and undocking inside a building's frame).
## Call [method step] with sim seconds only (0 while paused).

class Waypoint:
	var pos: Vector3
	## Speed limit on the way to this point, m/s.
	var speed: float
	## Come to rest here (true) or fly through (false).
	var stop: bool
	## Nose direction to hold while moving there. ZERO = face the motion.
	var face: Vector3
	var radius: float
	## Wait at a stop point until the nose matches [member face].
	var align: bool

	func _init(p: Vector3, spd: float, stop_here: bool = true, face_dir: Vector3 = Vector3.ZERO, arrive_radius: float = 2.0, wait_align: bool = false) -> void:
		pos = p
		speed = spd
		stop = stop_here
		face = face_dir
		radius = arrive_radius
		align = wait_align


var ship: Node3D
var max_speed: float = 150.0
var acceleration: float = 32.0
var turn_rate_deg: float = 110.0
var bank_max_deg: float = 28.0
## Thrust efficiency sideways and backwards, relative to the main engine.
var lateral_efficiency: float = 0.45
var reverse_efficiency: float = 0.6
## Vertical easing speed toward the goal height in a building frame, m/s.
var climb_speed: float = 8.0
## World-frame climbs and dives: steepest flight path, slowest and fastest
## vertical speed, vertical acceleration (m/s, m/s^2), largest nose pitch.
var climb_angle_deg: float = 16.0
var min_climb_rate: float = 14.0
var max_climb_rate: float = 40.0
var vertical_accel: float = 9.0
var pitch_max_deg: float = 14.0

## Velocity in the parent frame, m/s.
var velocity := Vector3.ZERO
var yaw: float = 0.0
var bank: float = 0.0
## 0..1, smoothed main-engine demand (drives the engine glow).
var thrust: float = 0.0
## Steer around bodies. On while the ship flies in the world frame.
var avoid_enabled: bool = false
## Extra velocity pushing away from nearby ships (set by the owner while in
## the world frame, see Ship). Added after body avoidance.
var separation := Vector3.ZERO
## Height to fly at (parent frame), set by the owner each step while
## [member cruise_active]. Off: ease to the goal's height (building frames).
var cruise_y: float = 0.0
var cruise_active: bool = false
## Vertical speed, m/s (world-frame climbs only; [member velocity] stays flat).
var climb_rate: float = 0.0
## Nose pitch from the climb, radians (+ = nose up).
var pitch: float = 0.0
## Climb straight out: ignore the goal and drift at [member hold_velocity]
## (riding with a belt's rocks) until the owner clears it.
var hold_climb: bool = false
var hold_velocity := Vector3.ZERO

var goal_pos := Vector3.ZERO
var goal_vel := Vector3.ZERO
var goal_speed: float = -1.0
var goal_stop: bool = true
var goal_face := Vector3.ZERO
var goal_radius: float = 8.0
var goal_y: float = 0.0
## False for goals on the plane whose height is up to the ship (Ship.set_world_goal).
var goal_has_altitude: bool = true
var path: Array[Waypoint] = []

var _yaw_rate: float = 0.0
var _has_goal: bool = false


func _init(owner_ship: Node3D) -> void:
	ship = owner_ship
	yaw = owner_ship.rotation.y


## Single (possibly moving) target, in the parent frame. Clears the path.
func set_goal(pos: Vector3, vel: Vector3 = Vector3.ZERO, speed: float = -1.0, stop: bool = true, face: Vector3 = Vector3.ZERO, radius: float = 8.0) -> void:
	path.clear()
	goal_pos = pos
	goal_vel = vel
	goal_speed = speed
	goal_stop = stop
	goal_face = face
	goal_radius = radius
	goal_y = pos.y
	goal_has_altitude = true
	_has_goal = true


func set_path(points: Array[Waypoint]) -> void:
	path = points.duplicate()
	_has_goal = not path.is_empty()
	if _has_goal:
		_load_waypoint(path[0])


## Hold the current spot (relative to the parent frame).
func hold() -> void:
	set_goal(ship.position, Vector3.ZERO, -1.0, true, Vector3.ZERO, 1.0)


func path_done() -> bool:
	return path.is_empty()


func distance_to_goal() -> float:
	var rel := goal_pos - ship.position
	return Vector2(rel.x, rel.z).length()


func arrived(speed_tolerance: float = 4.0) -> bool:
	if goal_has_altitude and absf(ship.position.y - goal_y) > 3.0:
		return false
	return distance_to_goal() <= goal_radius and (velocity - goal_vel).length() <= speed_tolerance


## Nose direction (parent frame, on the plane).
func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


static func yaw_for(dir: Vector3) -> float:
	return atan2(dir.x, dir.z) + PI


## Moves the ship under [param new_parent], keeping its world position,
## heading and world velocity.
func change_frame(new_parent: Node3D, world_frame: bool) -> void:
	var old_parent := ship.get_parent() as Node3D
	var v_world := velocity
	if old_parent:
		v_world = old_parent.global_basis * velocity + SpaceNav.world_velocity(old_parent)
	var fwd_world := ship.global_basis * Vector3.FORWARD
	if old_parent:
		ship.reparent(new_parent, true)
	else:
		new_parent.add_child(ship)
	velocity = new_parent.global_basis.inverse() * (v_world - SpaceNav.world_velocity(new_parent))
	velocity.y = 0.0
	climb_rate = 0.0
	var fwd_local := new_parent.global_basis.inverse() * fwd_world
	yaw = yaw_for(fwd_local)
	avoid_enabled = world_frame


func step(dt: float) -> void:
	if dt <= 0.0:
		return
	if not path.is_empty():
		_advance_path()
	var pos := ship.position
	var rel := goal_pos - pos
	rel.y = 0.0
	var d := rel.length()
	var limit := max_speed if goal_speed <= 0.0 else minf(goal_speed, max_speed)
	var desired := goal_vel
	if hold_climb:
		desired = hold_velocity
	elif _has_goal and d > 0.01:
		var dir := rel / d
		var s := limit
		if goal_stop:
			var brake := acceleration * 0.45
			s = minf(limit, sqrt(2.0 * brake * maxf(d - goal_radius * 0.25, 0.0)))
			s = minf(s, d * 1.1)
		desired += dir * s
	desired.y = 0.0
	if avoid_enabled and not hold_climb:
		desired = _avoid(pos, desired, d)
		desired += separation
	if desired.length() > max_speed:
		desired = desired.normalized() * max_speed

	# Thrust works best along the nose: sideways and backwards burns are weaker.
	var dv := desired - velocity
	var dv_len := dv.length()
	var eff := 1.0
	if dv_len > 0.001:
		var along := forward().dot(dv / dv_len)
		eff = lerpf(lateral_efficiency, 1.0, along) if along >= 0.0 else lerpf(lateral_efficiency, reverse_efficiency, -along)
	var max_dv := acceleration * eff * dt
	var a := dv.limit_length(max_dv)
	velocity += a
	velocity.y = 0.0
	pos += velocity * dt
	pos.y = _step_height(pos.y, dt)
	ship.position = pos
	var demand := clampf(a.length() / maxf(acceleration * dt, 1e-5), 0.0, 1.0) * maxf(forward().dot(a.normalized()) if a.length() > 1e-5 else 0.0, 0.25)
	thrust = lerpf(thrust, demand, 1.0 - exp(-4.0 * dt))
	_turn(dt, d)


## New height after [param dt]. World frame: ease toward [member cruise_y]
## (speed-limited approach, so climbs start and end smoothly), no steeper
## than [member climb_angle_deg] once moving, and pitch the nose with it.
func _step_height(y: float, dt: float) -> float:
	var hs := Vector2(velocity.x, velocity.z).length()
	if not cruise_active:
		climb_rate = 0.0
		y = move_toward(y, goal_y, climb_speed * dt)
	else:
		var err := cruise_y - y
		var vmax := clampf(hs * tan(deg_to_rad(climb_angle_deg)), min_climb_rate, max_climb_rate)
		var want := signf(err) * minf(vmax, sqrt(1.6 * vertical_accel * absf(err)))
		climb_rate = move_toward(climb_rate, want, vertical_accel * dt)
		y += climb_rate * dt
		if absf(cruise_y - y) < 0.05 and absf(climb_rate) < 0.3:
			y = cruise_y
			climb_rate = 0.0
	var pitch_max := deg_to_rad(pitch_max_deg)
	var pitch_target := clampf(atan2(climb_rate, maxf(hs, 30.0)), -pitch_max, pitch_max)
	pitch = lerpf(pitch, pitch_target, 1.0 - exp(-3.0 * dt))
	return y


## Speed relative to the goal (what the pilot feels), m/s.
func relative_speed() -> float:
	return (velocity - goal_vel).length()


func _turn(dt: float, goal_dist: float) -> void:
	var face := goal_face
	if face == Vector3.ZERO:
		# Face the motion relative to the target once close, so a ship matching
		# an orbiting outpost's speed noses toward it instead of crabbing.
		var blend := 1.0 - smoothstep(800.0, 3000.0, goal_dist)
		var fv := velocity - goal_vel * blend
		fv.y = 0.0
		if fv.length() > 3.0:
			face = fv
	var turn := deg_to_rad(turn_rate_deg)
	var target_rate := 0.0
	if face != Vector3.ZERO:
		var diff := angle_difference(yaw, yaw_for(face))
		target_rate = clampf(diff * 2.5, -turn, turn)
	_yaw_rate = lerpf(_yaw_rate, target_rate, 1.0 - exp(-6.0 * dt))
	yaw = wrapf(yaw + _yaw_rate * dt, -PI, PI)
	var bank_target := clampf(-_yaw_rate / turn, -1.0, 1.0) * deg_to_rad(bank_max_deg)
	bank = lerpf(bank, bank_target, 1.0 - exp(-3.0 * dt))


func aligned(face: Vector3, tolerance_deg: float = 6.0) -> bool:
	return absf(angle_difference(yaw, yaw_for(face))) <= deg_to_rad(tolerance_deg)


func _advance_path() -> void:
	var w := path[0]
	var rel := w.pos - ship.position
	var d := Vector2(rel.x, rel.z).length()
	var done := false
	if w.stop:
		done = d <= w.radius and velocity.length() <= 1.5
		if done and w.align and w.face != Vector3.ZERO:
			done = aligned(w.face, 4.0)
	else:
		done = d <= maxf(w.radius, velocity.length() * 0.6)
	if not done:
		return
	path.remove_at(0)
	if path.is_empty():
		# Hold the last point exactly.
		goal_stop = true
		return
	_load_waypoint(path[0])


func _load_waypoint(w: Waypoint) -> void:
	goal_pos = w.pos
	goal_vel = Vector3.ZERO
	goal_speed = w.speed
	goal_stop = w.stop
	goal_face = w.face
	goal_radius = w.radius
	goal_y = w.pos.y


## Steers the desired velocity past the nearest body blocking the way.
## Works in each body's moving frame (planets and moons orbit), so a ship
## crossing an orbit swerves around where the body will be.
func _avoid(pos: Vector3, desired: Vector3, goal_dist: float) -> Vector3:
	if desired.length() < 1.0:
		return desired
	var p := Vector3(pos.x, 0.0, pos.z)
	var goal := Vector3(goal_pos.x, 0.0, goal_pos.z)
	var best_along := INF
	var out := desired
	var push := Vector3.ZERO
	for o in SpaceNav.obstacles(ship.get_tree()):
		var node := o["node"] as Node3D
		if not is_instance_valid(node):
			continue
		var c := node.global_position
		c.y = 0.0
		var core: float = o["radius"]
		var r := core + clampf(core * 0.25, 30.0, 400.0)
		# A goal inside the keep-out (an outpost near its planet): only avoid the body.
		if goal.distance_to(c) < r:
			r = core + 10.0
			if goal.distance_to(c) < r:
				continue
		var to_c := c - p
		var dist := to_c.length()
		if dist < r:
			push -= to_c / maxf(dist, 1.0) * (r - dist) / r * max_speed
			continue
		if dist - r > max_speed * 28.0 + 1200.0:
			continue
		var v_obs := SpaceNav.world_velocity(node)
		var rel := desired - v_obs
		var speed := rel.length()
		if speed < 1.0:
			continue
		var dir := rel / speed
		var along := to_c.dot(dir)
		if along <= 0.0 or along > goal_dist + r or along - r > maxf(speed * 14.0, 1200.0):
			continue
		var lateral := to_c - dir * along
		var lat := lateral.length()
		if lat >= r or along >= best_along:
			continue
		best_along = along
		var side := -lateral / lat if lat > 1.0 else dir.cross(Vector3.UP)
		out = v_obs + (to_c + side * r * 1.1).normalized() * speed
	return out + push

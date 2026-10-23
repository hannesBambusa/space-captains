class_name ShipMover
extends RefCounted
## Movement for every ship (miners now, mercenaries and scavengers later).
## Flies on the plane in the ship's parent frame: limited acceleration that
## works best along the nose, max speed, turn rate, banking, arrival with
## velocity matching (so moving targets like orbiting outposts and rotating
## asteroids can be reached), and, in the world frame, routing around the
## star, planets, moons and the station hub ([NavRoute]: waypoints on each
## body's clearance circle, where the body will be), a soft push away inside
## a planning radius and a hard push-out so no ship ever ends inside a body.
##
## Warp hops (world frame): a leg longer than SpaceNav.WARP_MIN_LEG to the
## next route point, when the owner allows it ([member warp_allowed]: not in
## combat, not fleeing under fire) and neither end is in a no-warp zone
## (the station complex, the shield bubble, structures): the ship spools for
## SpaceNav.WARP_SPOOL (turning onto the line and climbing to the lane height
## of any belt band on it, [member warp_altitude]), jumps at up to
## SpaceNav.WARP_SPEED and drops out [member warp_drop] before the point,
## then flies on normally. A ship with a [member warp_lead] (fleet wingmen,
## escorts in formation) never starts its own hop: it spools and jumps with
## the lead, at the lead's velocity, so the formation holds.
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

signal warp_changed(mover: ShipMover, state: Warp)

enum Warp { IDLE, SPOOL, WARP }

## Seconds between hops.
const WARP_COOLDOWN := 3.0
## A warp only starts with the nose this close to the line (cosine).
const WARP_ALIGN := 0.94


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
## Body routing (world frame).
var route := NavRoute.new()
## Warp hops: set by the owner every step.
var warp_allowed: bool = false
var warp_drop: float = SpaceNav.WARP_DROP
var warp_lead: ShipMover
var warp_state: Warp = Warp.IDLE
## Lane height held through the hop (unsigned; 0 = the plane).
var warp_altitude: float = 0.0
var warp_dir := Vector3.ZERO
var warp_speed: float = 0.0
## Sim seconds of spool left.
var warp_timer: float = 0.0
## Where the current hop drops out (flat, world).
var warp_end := Vector3.ZERO
var _warp_cooldown: float = 0.0

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
	route.clear()
	if not world_frame:
		_end_warp()


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
	var via := false
	if avoid_enabled and _has_goal and not hold_climb:
		var tree := ship.get_tree()
		var flat := Vector3(pos.x, 0.0, pos.z)
		var g := _outside_bodies(Vector3(goal_pos.x, 0.0, goal_pos.z))
		if g.x != goal_pos.x or g.z != goal_pos.z:
			# A goal inside a body (a patrol point behind a planet): aim at its edge.
			rel = Vector3(g.x - pos.x, 0.0, g.z - pos.z)
			d = rel.length()
		var plan_speed := maxf(Vector2(velocity.x, velocity.z).length(), max_speed * 0.5)
		# Spooling or in a hop, the leg is flown at warp speed: plan for it.
		route.update(tree, flat, g, WARP_SPEED_PLAN if warp_state != Warp.IDLE else maxf(plan_speed, 30.0), dt)
		if route.has_waypoint():
			var w := route.waypoint()
			rel = Vector3(w.x - pos.x, 0.0, w.z - pos.z)
			via = true
		if _warp_step(dt, Vector3(pos.x + rel.x, 0.0, pos.z + rel.z), via):
			return
	elif warp_state != Warp.IDLE:
		_end_warp()
	var desired := goal_vel
	if hold_climb:
		desired = hold_velocity
	elif via:
		# Fly through route waypoints at cruise speed, in the body's frame.
		desired = route.waypoint_velocity() + rel.normalized() * limit
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
		desired += _body_push(pos, _outside_bodies(Vector3(goal_pos.x, 0.0, goal_pos.z)))
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
	if avoid_enabled:
		pos = _push_out(pos)
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
	if warp_state == Warp.SPOOL and warp_dir != Vector3.ZERO:
		face = warp_dir
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


# --- Bodies -------------------------------------------------------------------

## [param p] (flat, world), moved out to the planning radius of any body
## whose hard radius holds it.
func _outside_bodies(p: Vector3) -> Vector3:
	for o in SpaceNav.obstacles(ship.get_tree()):
		var node := o["node"] as Node3D
		if not is_instance_valid(node):
			continue
		var c := node.global_position
		var to := Vector3(p.x - c.x, 0.0, p.z - c.z)
		var dist := to.length()
		if dist < float(o["radius"]):
			var n := to / dist if dist > 0.5 else Vector3.RIGHT
			return Vector3(c.x, 0.0, c.z) + n * float(o["plan"]) * 1.06
	return p

## Outward velocity inside a body's planning radius (stronger toward the
## hard radius), unless the goal itself lies in there.
func _body_push(pos: Vector3, goal: Vector3) -> Vector3:
	var push := Vector3.ZERO
	for o in SpaceNav.obstacles(ship.get_tree()):
		var node := o["node"] as Node3D
		if not is_instance_valid(node):
			continue
		var c := node.global_position
		var to := Vector3(pos.x - c.x, 0.0, pos.z - c.z)
		var dist := to.length()
		var hard: float = o["radius"]
		var r: float = o["plan"]
		if dist >= r or dist < 1.0:
			continue
		if Vector2(goal.x - c.x, goal.z - c.z).length() < r:
			r = hard + 15.0
			if dist >= r:
				continue
		push += to / dist * clampf((r - dist) / maxf(r - hard, 1.0), 0.0, 1.0) * max_speed * 0.6
	return push


## Hard rule: never inside a body. Moves [param pos] back onto the hard
## radius and drops the inward part of the velocity (relative to the body).
func _push_out(pos: Vector3) -> Vector3:
	for o in SpaceNav.obstacles(ship.get_tree()):
		var node := o["node"] as Node3D
		if not is_instance_valid(node):
			continue
		var hard: float = o["radius"]
		var c := node.global_position
		var to := Vector3(pos.x - c.x, 0.0, pos.z - c.z)
		var dist := to.length()
		if dist >= hard:
			continue
		var n := to / dist if dist > 0.5 else Vector3.RIGHT
		pos.x = c.x + n.x * hard
		pos.z = c.z + n.z * hard
		var vb := SpaceNav.world_velocity(node)
		var inward := (velocity - vb).dot(n)
		if inward < 0.0:
			velocity -= n * inward
	return pos


# --- Warp ---------------------------------------------------------------------

const WARP_SPEED_PLAN := SpaceNav.WARP_SPEED


func is_warping() -> bool:
	return warp_state == Warp.WARP


## Advances a hop toward [param target] (flat world: the next route point or
## the goal). True when the warp moved the ship this step (skip normal flight).
func _warp_step(dt: float, target: Vector3, _via: bool) -> bool:
	_warp_cooldown -= dt
	var pos := ship.position
	var flat := Vector3(pos.x, 0.0, pos.z)
	var lead := warp_lead if warp_lead != null and is_instance_valid(warp_lead.ship) else null
	if lead:
		return _follow_warp(dt, lead)
	match warp_state:
		Warp.IDLE:
			if not warp_allowed or _warp_cooldown > 0.0:
				return false
			var end := _warp_end_for(flat, target)
			if end == Vector3.INF:
				return false
			warp_end = end
			warp_dir = (end - flat).normalized()
			warp_altitude = SpaceNav.segment_lane_altitude(ship.get_tree(), flat, end)
			warp_timer = SpaceNav.WARP_SPOOL
			_set_warp(Warp.SPOOL)
			return false
		Warp.SPOOL:
			if not warp_allowed:
				_end_warp()
				return false
			var end := _warp_end_for(flat, target)
			if end == Vector3.INF:
				_end_warp()
				return false
			warp_end = end
			warp_dir = (end - flat).normalized()
			warp_altitude = SpaceNav.segment_lane_altitude(ship.get_tree(), flat, end)
			warp_timer -= dt
			var level := absf(pos.y - cruise_y) < 4.0 or not cruise_active
			if warp_timer <= 0.0 and level and forward().dot(warp_dir) >= WARP_ALIGN:
				warp_speed = maxf(Vector2(velocity.x, velocity.z).length(), max_speed)
				_set_warp(Warp.WARP)
			return false
		Warp.WARP:
			if not warp_allowed:
				_end_warp()
				return false
			# Re-aim at the (moving) point; drop out short of it.
			var to := Vector3(target.x - flat.x, 0.0, target.z - flat.z)
			var left := to.length() - warp_drop
			if left <= 1.0:
				_end_warp()
				return false
			warp_dir = to.normalized()
			# A belt band ahead the hop is not high enough for: climb if
			# already there, else drop out before it.
			var need := SpaceNav.segment_lane_altitude(ship.get_tree(), flat, flat + warp_dir * left)
			if need > warp_altitude + 0.5:
				if absf(pos.y) >= need - 2.0:
					warp_altitude = need
				else:
					_end_warp()
					return false
			warp_speed = move_toward(warp_speed, SpaceNav.WARP_SPEED, SpaceNav.WARP_SPEED / SpaceNav.WARP_RAMP * dt)
			var stride := minf(warp_speed * dt, left)
			if _warp_blocked(flat, stride):
				_end_warp()
				return false
			velocity = warp_dir * warp_speed
			pos.x += warp_dir.x * stride
			pos.z += warp_dir.z * stride
			pos.y = _step_height(pos.y, dt)
			ship.position = _push_out(pos)
			yaw = yaw_for(warp_dir)
			_yaw_rate = 0.0
			bank = lerpf(bank, 0.0, 1.0 - exp(-3.0 * dt))
			thrust = 1.0
			if stride >= left - 0.5:
				_end_warp()
			return true
	return false


## Wingman or escort: spool and jump with [param lead], at its velocity.
func _follow_warp(dt: float, lead: ShipMover) -> bool:
	match lead.warp_state:
		Warp.IDLE:
			if warp_state != Warp.IDLE:
				_end_warp()
			return false
		Warp.SPOOL:
			if warp_state == Warp.IDLE and warp_allowed:
				warp_altitude = lead.warp_altitude
				warp_dir = lead.warp_dir
				warp_timer = lead.warp_timer
				_set_warp(Warp.SPOOL)
			elif warp_state == Warp.SPOOL:
				warp_dir = lead.warp_dir
				warp_timer = lead.warp_timer
				warp_altitude = lead.warp_altitude
			return false
		Warp.WARP:
			if warp_state == Warp.IDLE:
				return false
			if warp_state == Warp.SPOOL:
				# Only with the lead's lane height reached.
				if cruise_active and absf(ship.position.y - cruise_y) > 4.0:
					_end_warp()
					return false
				warp_speed = lead.warp_speed
				_set_warp(Warp.WARP)
			if not warp_allowed:
				_end_warp()
				return false
			var pos := ship.position
			warp_dir = lead.warp_dir
			warp_speed = lead.warp_speed
			warp_altitude = lead.warp_altitude
			velocity = lead.velocity
			if absf(pos.y) < warp_altitude - 2.0:
				_end_warp()
				return false
			var stride := velocity.length() * dt
			if _warp_blocked(Vector3(pos.x, 0.0, pos.z), stride):
				_end_warp()
				return false
			pos += Vector3(velocity.x, 0.0, velocity.z) * dt
			pos.y = _step_height(pos.y, dt)
			ship.position = _push_out(pos)
			yaw = yaw_for(warp_dir)
			_yaw_rate = 0.0
			thrust = 1.0
			return true
	return false


## Drop-out point for a hop from [param from] to [param target], or INF when
## no hop fits (too short, or starting in a no-warp zone).
func _warp_end_for(from: Vector3, target: Vector3) -> Vector3:
	var to := Vector3(target.x - from.x, 0.0, target.z - from.z)
	var length := to.length()
	if length < SpaceNav.WARP_MIN_LEG:
		return Vector3.INF
	var dir := to / length
	var reach := length - warp_drop
	for o in SpaceNav.obstacles(ship.get_tree()):
		var node := o["node"] as Node3D
		if is_instance_valid(node) and Vector2(from.x - node.global_position.x, from.z - node.global_position.z).length() < float(o["plan"]):
			return Vector3.INF
	for z in SpaceNav.no_warp_zones(ship.get_tree()):
		var c: Vector3 = z["center"]
		var r: float = z["radius"]
		var cf := Vector3(c.x, 0.0, c.z)
		if from.distance_to(cf) < r:
			return Vector3.INF
		# Stop at the zone's edge when the hop would end inside it.
		var along := (cf - from).dot(dir)
		if along > 0.0 and along < reach + r:
			var lat2 := (cf - from).length_squared() - along * along
			if lat2 < r * r:
				reach = minf(reach, along - sqrt(r * r - lat2))
	if reach < SpaceNav.WARP_MIN_LEG * 0.6:
		return Vector3.INF
	return from + dir * reach


## True when the next stride of the hop would enter a body's planning circle.
func _warp_blocked(flat: Vector3, stride: float) -> bool:
	var ahead := flat + warp_dir * (stride * 2.0 + 50.0)
	for o in SpaceNav.obstacles(ship.get_tree()):
		var node := o["node"] as Node3D
		if not is_instance_valid(node):
			continue
		var c := node.global_position
		c.y = 0.0
		var ab := ahead - flat
		var t := clampf((c - flat).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		if (flat + ab * t).distance_to(c) < float(o["radius"]) + 40.0 and (c - flat).dot(warp_dir) > 0.0:
			return true
	return false


func _end_warp() -> void:
	if warp_state == Warp.IDLE:
		return
	var was := warp_state
	if was == Warp.WARP:
		velocity = warp_dir * max_speed * 0.9
		_warp_cooldown = WARP_COOLDOWN
	warp_speed = 0.0
	warp_altitude = 0.0
	_set_warp(Warp.IDLE)


func _set_warp(st: Warp) -> void:
	if warp_state == st:
		return
	warp_state = st
	warp_changed.emit(self, st)

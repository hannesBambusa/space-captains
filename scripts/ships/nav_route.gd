class_name NavRoute
extends RefCounted
## Route planning around bodies for one ship in open space (ShipMover owns
## one). Every [constant REPLAN_INTERVAL] (and when a waypoint is passed) it
## checks the straight line to the goal against every body's planning radius
## (SpaceNav.obstacles) at the position the body will have when the ship gets
## there (SpaceNav.predict_position: moons orbit fast). Blocked: the
## waypoint is the tangent point on that body's clearance circle, on the side
## the goal lies, and the leg to it is checked the same way (up to
## [constant MAX_DEPTH] bodies deep). The tangent is taken in the body's
## frame (around where it is now, the ship's motion relative to it), and the
## waypoint rides with the body; the mover adds the body's velocity when
## flying to it. Clear: no waypoint, fly straight.
## Bodies are spheres: a leg whose heights ([member y_span]) pass above or
## below a body only keeps to the circle its sphere cuts there.
## A goal inside a body's planning radius (an outpost near its planet, a
## formation slot beside a moon) only keeps the hard radius for that body.

const REPLAN_INTERVAL := 0.5
const MAX_DEPTH := 3
## Waypoints sit this much outside the clearance circle.
const TANGENT_SLACK := 1.08
## Arc step round a circle the ship is already on, radians.
const HUG_STEP := 0.35

## The body the current waypoint goes around (null: straight to the goal).
var body: Node3D
## Which way round (+1 / -1), kept while the same body blocks.
var side: float = 1.0
## Heights (world, x = low, y = high) the ship covers on the way: set by the
## mover before [method update]. Bodies are spheres; one whose sphere this
## band clears does not block.
var y_span := Vector2.ZERO
var replans: int = 0

## Waypoint offset from the body's centre (flat).
var _offset := Vector3.ZERO
var _timer: float = 0.0


func has_waypoint() -> bool:
	return body != null and is_instance_valid(body)


## Current waypoint (flat, world), riding with its body.
func waypoint() -> Vector3:
	var c := body.global_position
	return Vector3(c.x + _offset.x, 0.0, c.z + _offset.z)


func waypoint_velocity() -> Vector3:
	var v := SpaceNav.world_velocity(body)
	v.y = 0.0
	return v


func clear() -> void:
	body = null
	_timer = 0.0


## Replans when due ([param ctx]: the ship, for its system). [param from] / [param goal] flat world points,
## [param speed] the speed the ship will cover the leg at.
func update(ctx: Node, from: Vector3, goal: Vector3, speed: float, dt: float) -> void:
	_timer -= dt
	if _timer > 0.0 and has_waypoint():
		var w := waypoint()
		if SpaceNav.flat_distance(w, from) > maxf(140.0, speed * 1.2):
			return
	elif _timer > 0.0:
		return
	_timer = REPLAN_INTERVAL * randf_range(0.85, 1.15)
	plan(ctx, from, goal, speed)


func plan(ctx: Node, from: Vector3, goal: Vector3, speed: float) -> void:
	replans += 1
	var obs := SpaceNav.obstacles(ctx)
	var target := goal
	var chosen: Dictionary = {}
	var skip: Array[Node3D] = []
	for i in MAX_DEPTH:
		var hit := first_block(obs, from, target, speed, goal, skip)
		if hit.is_empty():
			break
		chosen = hit
		target = _detour(from, target, hit)
		chosen["point"] = target
		# The leg to this waypoint is checked against every other body.
		skip = [hit["node"] as Node3D]
	if chosen.is_empty():
		body = null
		return
	var n := chosen["node"] as Node3D
	if n != body:
		side = chosen["side"]
	body = n
	var p: Vector3 = chosen["point"]
	var c := n.global_position
	_offset = Vector3(p.x - c.x, 0.0, p.z - c.z)


## First body whose clearance circle (where it will be) the segment
## [param a]-[param b] crosses: {node, c (predicted centre), r, hard, side},
## or empty. Bodies in [param skip] are ignored.
func first_block(obs: Array[Dictionary], a: Vector3, b: Vector3, speed: float, goal: Vector3, skip: Array[Node3D] = []) -> Dictionary:
	var ab := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var length := ab.length()
	if length < 1.0:
		return {}
	var dir := ab / length
	var spd := maxf(speed, 20.0)
	var spd_leg := length / spd
	var best: Dictionary = {}
	var best_along := INF
	for o in obs:
		var node := o["node"] as Node3D
		if not is_instance_valid(node) or skip.has(node):
			continue
		var vb := SpaceNav.world_velocity(node)
		var c0 := node.global_position
		# Spheres: only the circle cut at the leg's heights counts (bodies on
		# inclined orbits drift up or down meanwhile).
		var dy := maxf(SpaceNav.height_gap(c0.y, y_span) - absf(vb.y) * spd_leg, 0.0)
		var hard := SpaceNav.slice_radius(o["radius"], dy)
		var r := SpaceNav.slice_radius(o["plan"], dy)
		if r <= 0.0:
			continue
		c0.y = 0.0
		var gd := SpaceNav.flat_distance(goal, c0)
		if gd < r:
			r = hard
			if gd < hard:
				continue
		var ad := SpaceNav.flat_distance(a, c0)
		if ad < r:
			# Already inside the planning circle: hold this distance (never
			# closer than the hard radius) while going round.
			r = maxf(hard, ad - 15.0)
		# Closest approach in the body's frame (it may come at the ship), then
		# checked against where its orbit really puts it.
		vb.y = 0.0
		var leg_t := spd_leg
		var rel_p := a - c0
		var rel_v := dir * spd - vb
		var vv := rel_v.length_squared()
		var tc := clampf(-rel_p.dot(rel_v) / vv, 0.0, leg_t) if vv > 1e-6 else 0.0
		var slack := 0.2 * vb.length() * leg_t + 30.0
		if (rel_p + rel_v * tc).length() > r + slack:
			continue
		var c := Vector3.INF
		var near := INF
		for k: float in [tc - leg_t * 0.12, tc, tc + leg_t * 0.12]:
			var tk := clampf(k, 0.0, leg_t)
			var ck := SpaceNav.predict_position(node, tk)
			var sk := a + dir * spd * tk
			var dk := SpaceNav.flat_distance(sk, ck)
			if dk < near:
				near = dk
				c = Vector3(ck.x, 0.0, ck.z)
		if near >= r:
			continue
		var along := spd * tc
		if along < best_along:
			best_along = along
			var perp := Vector3(-dir.z, 0.0, dir.x)
			var s := -signf((c - a).dot(perp))
			if node == body:
				s = side
			best = {"node": node, "c": c, "c0": c0, "r": r, "hard": hard, "side": s if s != 0.0 else 1.0}
	return best


## Tangent point from [param a] on the clearance circle of [param hit],
## around the body's current centre (body frame).
func _detour(a: Vector3, _target: Vector3, hit: Dictionary) -> Vector3:
	var c: Vector3 = hit["c0"]
	var r: float = float(hit["r"]) * TANGENT_SLACK
	var s: float = hit["side"]
	var to := Vector3(c.x - a.x, 0.0, c.z - a.z)
	var d := to.length()
	if d < 1.0:
		return a + Vector3(r, 0.0, 0.0)
	var to_c := to / d
	var perp := Vector3(-to_c.z, 0.0, to_c.x) * s
	if d <= r * 1.02:
		# On the circle: step [constant HUG_STEP] round it (the chord stays outside).
		return c + (-to_c * cos(HUG_STEP) + perp * sin(HUG_STEP)) * maxf(r, d) * 1.02
	var th := asin(clampf(r / d, 0.0, 1.0))
	var tdir := to_c * cos(th) + perp * sin(th)
	var p := a + tdir * sqrt(maxf(d * d - r * r, 0.0))
	# A little past the tangent point, so the next leg clears the circle.
	return p + tdir * minf(r * 0.25, 300.0)

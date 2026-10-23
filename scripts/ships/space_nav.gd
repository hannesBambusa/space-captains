class_name SpaceNav
extends RefCounted
## Shared navigation helpers for every ship: world velocity of orbiting nodes,
## velocity of points on a rotating belt, the bodies ships steer around, belt
## lanes (the height that clears a belt's rocks), and the world-space
## container ships fly in while undocked.
##
## The orbit chain (planet -> moon/station -> structures frame -> building) never
## rotates, so a node's world velocity is the sum of its Orbiter ancestors'
## orbital velocities.

const SPACE_ROOT_NAME := "Ships"
## Belt lanes: the look-ahead covers this many seconds of flight on top of
## the distance a full climb takes.
const LANE_LEAD_TIME := 2.5
## Rock band slack for "caught low inside a band", metres.
const ROCK_BAND_SLACK := 4.0

## Cached obstacle list: Array of {node: Node3D, radius: float}.
static var _obstacles: Array[Dictionary] = []
static var _obstacle_source: SolarSystem


## Velocity (m/s, world axes) of [param node] caused by the orbits it rides on.
static func world_velocity(node: Node) -> Vector3:
	var v := Vector3.ZERO
	var n := node
	while n != null:
		if n is Orbiter:
			v += orbit_velocity(n as Orbiter)
		n = n.get_parent()
	return v


## Orbital velocity of one Orbiter relative to its parent.
static func orbit_velocity(o: Orbiter) -> Vector3:
	if o.orbit_period == 0.0 or o.orbit_radius == 0.0:
		return Vector3.ZERO
	var a := o.orbit_angle(SimClock.time)
	var w := TAU / o.orbit_period
	return Vector3(-sin(a), 0.0, cos(a)) * o.orbit_radius * w


## Velocity of a point riding on a rotating belt (belt centred on the origin).
static func belt_point_velocity(belt: SystemBelt, world_pos: Vector3) -> Vector3:
	if belt == null or belt.def == null or belt.def.rotation_period == 0.0:
		return Vector3.ZERO
	var w := -TAU / belt.def.rotation_period
	var r := world_pos - belt.global_position
	return Vector3(w * r.z, 0.0, -w * r.x)


## Point on the belt's centre line closest to [param world_pos] (on the plane).
static func nearest_belt_point(belt: SystemBelt, world_pos: Vector3) -> Vector3:
	var c := belt.global_position
	var d := Vector3(world_pos.x - c.x, 0.0, world_pos.z - c.z)
	if d.length_squared() < 1.0:
		d = Vector3.RIGHT
	return c + d.normalized() * belt.def.orbit_radius


## Straight-line distance from [param world_pos] to the belt's centre line.
static func distance_to_belt(belt: SystemBelt, world_pos: Vector3) -> float:
	var c := belt.global_position
	return absf(Vector2(world_pos.x - c.x, world_pos.z - c.z).length() - belt.def.orbit_radius)


## The system's belts (empty outside a SolarSystem).
static func belts(tree: SceneTree) -> Array[SystemBelt]:
	var sys := tree.get_first_node_in_group(SolarSystem.GROUP) as SolarSystem
	if sys:
		return sys.belts
	var none: Array[SystemBelt] = []
	return none


## Height (unsigned) a ship at [param pos] must hold to clear belt rocks: the
## highest lane altitude of the belts whose band, padded by the largest rock
## and the lane margin, lies on its way within the look-ahead (the straight
## line toward [param goal], and the current motion [param vel]). 0 = clear.
## [param climb_tan] = tangent of the steepest climb, sets how early to start.
static func belt_lane_altitude(tree: SceneTree, pos: Vector3, vel: Vector3, goal: Vector3, climb_tan: float) -> float:
	var need := 0.0
	var p := Vector2(pos.x, pos.z)
	var v := Vector2(vel.x, vel.z)
	var speed := v.length()
	var to_goal := Vector2(goal.x - pos.x, goal.z - pos.z)
	var gd := to_goal.length()
	for b in belts(tree):
		if b.def == null:
			continue
		var alt := b.lane_altitude()
		var lead := speed * LANE_LEAD_TIME + alt / maxf(climb_tan, 0.05) * 1.3 + 60.0
		var c := Vector2(b.global_position.x, b.global_position.z)
		var hw := b.rock_half_width() + b.def.max_scale + SystemBelt.LANE_MARGIN
		var inner := b.def.orbit_radius - hw
		var outer := b.def.orbit_radius + hw
		var end := p + to_goal / gd * minf(gd, lead) if gd > 1.0 else p
		var hit := _segment_meets_ring(p, end, c, inner, outer)
		if not hit and speed > 2.0:
			hit = _segment_meets_ring(p, p + v / speed * lead, c, inner, outer)
		if hit:
			need = maxf(need, alt)
	return need


## The belt whose rock band (radially, plus the largest rock) holds
## [param pos], or null.
static func rock_band_at(tree: SceneTree, pos: Vector3) -> SystemBelt:
	for b in belts(tree):
		if b.def and distance_to_belt(b, pos) <= b.rock_half_width() + b.def.max_scale + ROCK_BAND_SLACK:
			return b
	return null


## True when the segment [param a]-[param b] (on the plane) passes through
## the ring between radii [param inner] and [param outer] around [param c].
static func _segment_meets_ring(a: Vector2, b: Vector2, c: Vector2, inner: float, outer: float) -> bool:
	var ab := b - a
	var t := clampf((c - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	var r_min := (a + ab * t - c).length()
	var r_max := maxf((a - c).length(), (b - c).length())
	return r_min <= outer and r_max >= inner


## The world-space node undocked ships live under (created on first use).
static func space_root(tree: SceneTree) -> Node3D:
	var sys := tree.get_first_node_in_group(SolarSystem.GROUP) as SolarSystem
	var parent: Node = sys if sys else tree.current_scene
	var root := parent.get_node_or_null(SPACE_ROOT_NAME) as Node3D
	if root == null:
		root = Node3D.new()
		root.name = SPACE_ROOT_NAME
		parent.add_child(root)
	return root


## Bodies ships steer around: star, planets (with rings), moons, the home
## station hub. Built once per SolarSystem.
static func obstacles(tree: SceneTree) -> Array[Dictionary]:
	var sys := tree.get_first_node_in_group(SolarSystem.GROUP) as SolarSystem
	if sys == _obstacle_source and (sys == null or not _obstacles.is_empty()):
		return _obstacles
	_obstacle_source = sys
	_obstacles = []
	if sys == null:
		return _obstacles
	if sys.star:
		_obstacles.append({"node": sys.star, "radius": sys.star.radius * 1.25})
	for p in sys.planets:
		var reach := p.def.radius * (p.def.ring_outer if p.def.has_rings else 1.0)
		_obstacles.append({"node": p, "radius": reach + 60.0})
		for c in p.get_children():
			if c is PlanetBody:
				_obstacles.append({"node": c, "radius": (c as PlanetBody).def.radius + 40.0})
	if sys.home_station:
		_obstacles.append({"node": sys.home_station, "radius": 70.0})
	return _obstacles


## "at Talon Reach", "near home", "near Verda": where [param pos] is, for
## event lines.
static func place_name(tree: SceneTree, pos: Vector3) -> String:
	var sys := tree.get_first_node_in_group(SolarSystem.GROUP) as SolarSystem
	if sys == null:
		return ""
	if sys.home_station and Vector2(pos.x - sys.home_station.global_position.x, pos.z - sys.home_station.global_position.z).length() < 3500.0:
		return "near home"
	for b in sys.belts:
		if distance_to_belt(b, pos) < b.def.width * 0.5 + 900.0:
			return "at %s" % b.def.name
	var best := ""
	var best_d := INF
	for p in sys.planets:
		var d := Vector2(pos.x - p.global_position.x, pos.z - p.global_position.z).length()
		if d < best_d:
			best_d = d
			best = p.def.name
	return "near %s" % best if not best.is_empty() else ""

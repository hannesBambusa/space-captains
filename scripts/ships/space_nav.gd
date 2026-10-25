class_name SpaceNav
extends RefCounted
## Shared navigation helpers for every ship: world velocity of orbiting nodes,
## velocity of points in a drifting asteroid cluster, the bodies ships steer
## around (and where they will be, [method predict_position]), cluster lanes
## (the height that clears a cluster's rocks when the way crosses it), warp hops (no-warp zones, travel time
## estimates) and the world-space container ships fly in while undocked.
##
## Bodies ([method obstacles]): each has a hard radius (the visible body:
## surface, atmosphere shell or rings, plus [constant SHIP_MARGIN]) no ship
## may ever cross, and a larger planning radius routes keep to (NavRoute).
## Both are spheres: bodies on inclined orbits sit above or below the plane,
## and a ship only steers round the circle the sphere cuts at its height
## ([method slice_radius]).
##
## The orbit chain (planet -> moon/station -> structures frame -> building) never
## rotates, so a node's world velocity is the sum of its Orbiter ancestors'
## orbital velocities.

const SPACE_ROOT_NAME := "Ships"
## Cluster lanes: the look-ahead covers this many seconds of flight on top of
## the distance a full climb takes.
const LANE_LEAD_TIME := 2.5
## Rock band slack for "caught low inside a band", metres.
const ROCK_BAND_SLACK := 4.0

## Kept between a ship and a body's visible edge, metres.
const SHIP_MARGIN := 30.0
## Home Station hard / planning radius, m: the hub plus the addons on its
## bays (they reach ~92 m) and the solar wings (~87 m).
const STATION_HARD_RADIUS := 100.0
const STATION_PLAN_RADIUS := 140.0
## Planning radius beyond the hard radius: this share of it, clamped
## (metres), plus [constant PLAN_PAD_SPEED] sim seconds of the body's speed
## (fast moons get a wider berth).
const PLAN_PAD_SHARE := 0.2
const PLAN_PAD := Vector2(90.0, 450.0)
const PLAN_PAD_SPEED := 2.0
## Warp hops (ShipMover): legs longer than this warp, metres.
const WARP_MIN_LEG := 3000.0
const WARP_SPOOL := 2.5
const WARP_SPEED := 2600.0
## Sim seconds from drop-in speed to full warp speed.
const WARP_RAMP := 1.2
## Default drop-out distance before the destination, metres.
const WARP_DROP := 650.0
## No warping this close to the Home Station (the complex, the shield
## bubble), or to any structure, metres.
const NO_WARP_STATION := 1200.0
const NO_WARP_BUILDING := 260.0
## Reference cruise speed for trip limits in km (PersonalityProfile.max_trip_km), m/s.
const REF_SPEED := 150.0

## Cached obstacle list: Array of {node: Node3D, radius: float (hard),
## plan: float (planning radius)}.
static var _obstacles: Array[Dictionary] = []
static var _obstacle_source: SolarSystem


## Distance between [param a] and [param b] on the plane (x, z).
static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Length of [param v] on the plane (x, z).
static func flat_length(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


## Velocity (m/s, world axes) of [param node] caused by the orbits it rides on.
static func world_velocity(node: Node) -> Vector3:
	var v := Vector3.ZERO
	var n := node
	while n != null:
		if n is Orbiter:
			v += orbit_velocity(n as Orbiter)
		n = n.get_parent()
	return v


## Orbital velocity of one Orbiter relative to its parent (3D: inclined
## orbits rise and sink).
static func orbit_velocity(o: Orbiter) -> Vector3:
	return o.orbit_velocity_at(SimClock.time)


## Radius of the circle a body's sphere of [param radius] cuts at
## [param dy] metres above or below its centre; 0 = the height clears it.
static func slice_radius(radius: float, dy: float) -> float:
	var r2 := radius * radius - dy * dy
	return sqrt(r2) if r2 > 0.0 else 0.0


## Smallest height gap between [param y] and the band [param span] (x = low,
## y = high), 0 inside it.
static func height_gap(y: float, span: Vector2) -> float:
	if y < span.x:
		return span.x - y
	if y > span.y:
		return y - span.y
	return 0.0


## Velocity of a point riding with an asteroid cluster (the whole clump
## drifts on its orbit without turning, so every point moves alike).
static func belt_point_velocity(belt: AsteroidCluster, _world_pos: Vector3 = Vector3.ZERO) -> Vector3:
	if belt == null or belt.def == null:
		return Vector3.ZERO
	return world_velocity(belt)


## Point on the cluster's rim facing [param world_pos] (inside: the point itself
## at the cluster's height).
static func nearest_belt_point(belt: AsteroidCluster, world_pos: Vector3) -> Vector3:
	return belt.nearest_point(world_pos)


## Flat distance from [param world_pos] to the cluster's rim (0 inside).
static func distance_to_belt(belt: AsteroidCluster, world_pos: Vector3) -> float:
	return belt.distance_to(world_pos)


## The system's clusters (empty outside a SolarSystem).
static func belts(tree: SceneTree) -> Array[AsteroidCluster]:
	var sys := SolarSystem.of(tree)
	if sys:
		return sys.belts
	var none: Array[AsteroidCluster] = []
	return none


## Height (unsigned) a ship at [param pos] must hold to clear cluster rocks:
## the highest lane altitude of the clusters whose footprint, padded by the
## largest rock and the lane margin, lies on its way within the look-ahead
## (the straight line toward [param goal], and the current motion
## [param vel]). 0 = clear. Ships whose way misses every cluster fly level.
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
		var hw := b.rock_half_width() + b.def.max_scale + AsteroidCluster.LANE_MARGIN
		var end := p + to_goal / gd * minf(gd, lead) if gd > 1.0 else p
		var hit := _segment_meets_disc(p, end, c, hw)
		if not hit and speed > 2.0:
			hit = _segment_meets_disc(p, p + v / speed * lead, c, hw)
		if hit:
			need = maxf(need, alt)
	return need


## The cluster whose footprint (plus the largest rock) holds [param pos]
## on the plane, or null.
static func rock_band_at(tree: SceneTree, pos: Vector3) -> AsteroidCluster:
	for b in belts(tree):
		if b.def and b.distance_to(pos) <= b.def.max_scale + ROCK_BAND_SLACK:
			return b
	return null


## True when the segment [param a]-[param b] (on the plane) passes within
## [param radius] of [param c].
static func _segment_meets_disc(a: Vector2, b: Vector2, c: Vector2, radius: float) -> bool:
	var ab := b - a
	var t := clampf((c - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return (a + ab * t - c).length() <= radius


## The world-space node undocked ships live under (created on first use).
static func space_root(tree: SceneTree) -> Node3D:
	var sys := SolarSystem.of(tree)
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
	var sys := SolarSystem.of(tree)
	if sys == _obstacle_source and (sys == null or not _obstacles.is_empty()):
		return _obstacles
	_obstacle_source = sys
	_obstacles = []
	if sys == null:
		return _obstacles
	if sys.star:
		_add_obstacle(sys.star, sys.star.radius * 1.25 + SHIP_MARGIN)
	for p in sys.planets:
		_add_obstacle(p, body_reach(p.def) + SHIP_MARGIN)
		for c in p.get_children():
			if c is PlanetBody:
				_add_obstacle(c as PlanetBody, body_reach((c as PlanetBody).def) + SHIP_MARGIN)
	if sys.home_station:
		_obstacles.append({"node": sys.home_station, "radius": STATION_HARD_RADIUS, "plan": STATION_PLAN_RADIUS})
	return _obstacles


static func _add_obstacle(node: Node3D, hard: float) -> void:
	var pad := clampf(hard * PLAN_PAD_SHARE, PLAN_PAD.x, PLAN_PAD.y) + PLAN_PAD_SPEED * world_velocity(node).length()
	_obstacles.append({"node": node, "radius": hard, "plan": hard + pad})


## Visible reach of a planet or moon from its centre: the surface, the
## atmosphere shell or the rings, whichever is widest, metres.
static func body_reach(def: PlanetDef) -> float:
	var r := def.radius
	if def.atmosphere_color.a > 0.0:
		r = def.radius / PlanetBody.ATMO_INNER_RATIO
	if def.has_rings:
		r = maxf(r, def.radius * def.ring_outer)
	return r


## World position of [param node] [param ahead] sim seconds from now, from
## the orbit chain (Orbiters never rotate, so offsets just add up).
static func predict_position(node: Node3D, ahead: float) -> Vector3:
	if ahead <= 0.0:
		return node.global_position
	var t := SimClock.time + ahead
	var offset := Vector3.ZERO
	var n: Node = node
	while n is Node3D:
		if n is Orbiter:
			offset += (n as Orbiter).orbit_offset(t)
			n = n.get_parent()
		else:
			return (n as Node3D).global_position + offset
	return offset


## Lane height (unsigned) for a straight warp from [param a] to [param b]:
## the highest lane altitude of the clusters the segment crosses, 0 when
## none (a warp never crosses rocks at their height).
static func segment_lane_altitude(tree: SceneTree, a: Vector3, b: Vector3) -> float:
	var need := 0.0
	for belt in belts(tree):
		if belt.def == null:
			continue
		var c := Vector2(belt.global_position.x, belt.global_position.z)
		var hw := belt.rock_half_width() + belt.def.max_scale + AsteroidCluster.LANE_MARGIN
		if _segment_meets_disc(Vector2(a.x, a.z), Vector2(b.x, b.z), c, hw):
			need = maxf(need, belt.lane_altitude())
	return need


## Places no warp starts or ends: [{center: Vector3, radius: float}] (the
## Home Station complex and shield bubble, every structure).
static func no_warp_zones(tree: SceneTree) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var sys := SolarSystem.of(tree)
	if sys and sys.home_station:
		var r := NO_WARP_STATION
		var bubble := StationShield.find(tree)
		if bubble:
			r = maxf(r, bubble.radius + 200.0)
		out.append({"center": sys.home_station.global_position, "radius": r})
	var mgr := BuildingManager.of(tree)
	if mgr:
		for b in mgr.buildings:
			if is_instance_valid(b):
				out.append({"center": b.global_position, "radius": NO_WARP_BUILDING + b.def.footprint_radius})
	return out


## Sim seconds of a trip of [param distance] metres at [param speed]:
## x = the warp part (spool, ramp, the hop), y = normal flight (leaving
## home, the drop-out approach). Short trips are all flight.
static func travel_estimate(distance: float, speed: float) -> Vector2:
	var cruise := maxf(speed, 30.0) * 0.85
	if distance <= WARP_MIN_LEG + WARP_DROP:
		return Vector2(0.0, distance / cruise)
	var flown := WARP_DROP + NO_WARP_BUILDING + 200.0
	var hop := maxf(distance - flown, 0.0)
	return Vector2(WARP_SPOOL + WARP_RAMP * 0.5 + 1.5 + hop / WARP_SPEED, flown / cruise)


## "12 s warp + 9 s flight" (or "40 s flight").
static func travel_text(t: Vector2) -> String:
	if t.x <= 0.0:
		return "%d s flight" % roundi(t.y)
	return "%d s warp + %d s flight" % [roundi(t.x), roundi(t.y)]


## "at Talon Reach", "near home", "near Verda": where [param pos] is, for
## event lines.
static func place_name(tree: SceneTree, pos: Vector3) -> String:
	var sys := SolarSystem.of(tree)
	if sys == null:
		return ""
	if sys.home_station and flat_distance(pos, sys.home_station.global_position) < 3500.0:
		return "near home"
	for b in sys.belts:
		if b.distance_to(pos) < 900.0:
			return "at %s" % b.def.name
	var best := ""
	var best_d := INF
	for p in sys.planets:
		var d := flat_distance(pos, p.global_position)
		if d < best_d:
			best_d = d
			best = p.def.name
	return "near %s" % best if not best.is_empty() else ""

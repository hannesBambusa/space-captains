class_name StationKeepouts
extends RefCounted
## Keep-out areas around the Home Station, in the non-rotating "Structures"
## frame (the station sits at the frame origin and does not turn): a disc of
## [member clearance] around the centre, plus one strip per addon bay
## (occupied or free, from the station model's "addon_bay_N" empties, along
## the bay's +Z) and one per solar wing. No structure footprint and no
## docking lane may touch them (BuildingManager.plan_placement).

## Structures and docking lanes stay this far from the station centre, m.
var clearance: float = 100.0
## Frame-local strips: {a, b (Vector3 on the plane), half (float), label}.
var strips: Array[Dictionary] = []


## Builds the strips from [param station_node]'s model. Bay strips are
## [param bay_length] long and [param bay_half] wide on each side; solar
## wings run along [param wing_dirs] (station space) over [param wing_span]
## (radial from, to) with half width [param wing_half].
static func build(station_node: HomeStation, centre_clearance: float, bay_length: float, bay_half: float,
		wing_dirs: PackedVector3Array, wing_span: Vector2, wing_half: float) -> StationKeepouts:
	var k := StationKeepouts.new()
	k.clearance = centre_clearance
	var model := station_node.get_model() if station_node else null
	for i in range(1, BuildingManager.BAY_COUNT + 1):
		var n := model.find_child(BuildingManager.BAY_NODE % i, true, false) as Node3D if model else null
		if n == null:
			continue
		var xf := station_node.transform * ModelLoader.relative_transform(station_node, n)
		var o := flat(xf.origin)
		var out := flat(xf.basis.z).normalized()
		k.strips.append({"a": o, "b": o + out * bay_length, "half": bay_half, "label": "station addon bay %d" % i})
	for d in wing_dirs:
		var dir := flat(d).normalized()
		k.strips.append({"a": dir * wing_span.x, "b": dir * wing_span.y, "half": wing_half, "label": "the station's solar wings"})
	return k


## Why a footprint of radius [param r] at frame-local [param pos] touches a
## keep-out, or "".
func spot_problem(pos: Vector3, r: float) -> String:
	var p := v2(pos)
	if p.length() < clearance + r:
		return "Too close to the station"
	for s in strips:
		if seg_point(v2(s["a"]), v2(s["b"]), p) < float(s["half"]) + r:
			return "Blocks %s" % s["label"]
	return ""


## Why a lane from [param a] to [param b] (half width [param half]) crosses
## a keep-out, or "".
func lane_problem(a: Vector3, b: Vector3, half: float) -> String:
	var a2 := v2(a)
	var b2 := v2(b)
	if seg_point(a2, b2, Vector2.ZERO) < clearance:
		return "Docking lane blocked by the Home Station"
	for s in strips:
		if seg_seg(a2, b2, v2(s["a"]), v2(s["b"])) < float(s["half"]) + half:
			return "Docking lane crosses %s" % s["label"]
	return ""


# --- 2D helpers -----------------------------------------------------------------

static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func v2(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


static func seg_point(a: Vector2, b: Vector2, p: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))


static func seg_seg(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
		return 0.0
	return minf(minf(seg_point(c, d, a), seg_point(c, d, b)), minf(seg_point(a, b, c), seg_point(a, b, d)))

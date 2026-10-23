class_name CorridorNetwork
extends Node3D
## Corridors that join the Home Station and every built structure into one
## station complex. Lives in the non-rotating "Structures" frame (frame-local
## = this node's local space), so corridors are static relative to the
## station and the buildings.
##
## Graph: anchors (the station, one per building, junctions) linked by
## straight corridors at [member corridor_height], above the y = 0 plane
## ships fly on. A new structure links to the nearest anchor or to the middle
## of an existing corridor (a junction splits it), whichever gives the
## shortest valid link ([method plan]). Its docking mouth is turned away from
## the link, so the corridor leaves from its back.
##
## Drawing: every finished piece shares one MultiMesh per kit part
## (CorridorKit); pieces of a structure under construction get their own
## MultiMeshes with the construction shader until it is done.

signal changed

const CONSTRUCTION_SHADER: Shader = preload("res://shaders/construction.gdshader")
const PARTS := [CorridorKit.Part.SEGMENT, CorridorKit.Part.COLLAR, CorridorKit.Part.JUNCTION]

@export_group("Link rules")
## Minimum clear gap between the footprint edges of any two structures, m.
@export var min_gap: float = 60.0
## Longest link: gap from the new footprint edge to the target's edge, m.
@export var max_link: float = 300.0
## Shortest corridor (and shortest branch onto a corridor), m.
@export var min_corridor: float = 30.0
## Height of every corridor's centre line above the plane, m.
@export var corridor_height: float = 12.0
## Station hull edge used for link gaps, m.
@export var station_radius: float = 60.0
## Corridors and docking lanes not linked to the station stay this far from its centre, m.
@export var station_clearance: float = 72.0
## Extra clearance between a corridor and a footprint it passes, m.
@export var footprint_margin: float = 6.0
## Minimum distance between corridors that do not share an anchor, m.
@export var corridor_spacing: float = 14.0
## Minimum angle between corridors leaving the same structure, degrees.
@export var min_branch_angle_deg: float = 28.0
## Corridors keep at least this angle from a docking mouth's outward direction, degrees.
@export var mouth_clear_deg: float = 70.0
## Half width of a docking lane (dock point out past the approach point), m.
@export var lane_half_width: float = 12.0
## Docking lane reach past the spawn point (Building.approach_distance + exit), m.
@export var lane_reach: float = 80.0
## A junction keeps this far from either end of the corridor it splits, m.
@export var junction_margin: float = 30.0
## Corridor ends sink this far into the hull, m.
@export var collar_inset: float = 0.8

## Per model: hull profile at corridor height and docking lane, model space.
class ModelInfo:
	extends RefCounted
	var profile := PackedFloat32Array()
	## Docking mouth outward direction (ZERO = no docking mouth).
	var mouth := Vector3.ZERO
	var lane_a := Vector3.ZERO
	var lane_b := Vector3.ZERO


class Anchor:
	extends RefCounted
	enum Kind { STATION, BUILDING, JUNCTION }
	var kind: Kind = Kind.BUILDING
	var building: Building
	## Frame-local centre on the plane.
	var position := Vector3.ZERO
	## Footprint (station: hull edge, junction: port distance).
	var radius := 0.0
	## Junction: direction of the corridor it splits.
	var axis := Vector3.FORWARD
	## Junction: the structure whose link made it (builds with it).
	var owner: Building
	var info: ModelInfo
	var corridors: Array[Corridor] = []

	func yaw() -> float:
		return building.rotation.y if is_instance_valid(building) else 0.0

	func label() -> String:
		match kind:
			Kind.STATION:
				return "the Home Station"
			Kind.JUNCTION:
				return "a corridor junction"
		return building.display_name if is_instance_valid(building) else "a structure"

	func mouth_world() -> Vector3:
		return info.mouth.rotated(Vector3.UP, yaw()) if info else Vector3.ZERO

	func has_lane() -> bool:
		return kind == Kind.BUILDING and info != null and info.mouth != Vector3.ZERO

	func lane_a() -> Vector3:
		return position + info.lane_a.rotated(Vector3.UP, yaw())

	func lane_b() -> Vector3:
		return position + info.lane_b.rotated(Vector3.UP, yaw())


class Corridor:
	extends RefCounted
	var a: Anchor
	var b: Anchor
	## End points (frame-local, at corridor height) on a and on b.
	var pa := Vector3.ZERO
	var pb := Vector3.ZERO
	## Built together with this structure (solid once it is active).
	var owner: Building

	func end_at(an: Anchor) -> Vector3:
		return pa if an == a else pb

	func length() -> float:
		return pa.distance_to(pb)


## A proposed link for a new structure. [member problem] is "" when valid;
## the geometry is set whenever [member has_link] (also for invalid previews).
class Plan:
	extends RefCounted
	var problem := ""
	var has_link := false
	var yaw := 0.0
	var target: Anchor
	## Set when the link branches off the middle of this corridor.
	var split: Corridor
	var junction_pos := Vector3.ZERO
	## End on the new structure and end on the target (or junction port).
	var pa := Vector3.ZERO
	var pb := Vector3.ZERO

	func is_valid() -> bool:
		return problem.is_empty()


var station: Anchor
var anchors: Array[Anchor] = []
var corridors: Array[Corridor] = []

var _by_building: Dictionary = {}
var _infos: Dictionary = {}
var _solid: Dictionary = {}
## Building -> {"mat": ShaderMaterial, "mmis": {part: MultiMeshInstance3D}}
var _looks: Dictionary = {}


func _ready() -> void:
	set_process(false)


func _notification(what: int) -> void:
	# Anchors and corridors reference each other: break the cycles.
	if what == NOTIFICATION_PREDELETE:
		for an in anchors:
			an.corridors.clear()
		corridors.clear()
		anchors.clear()


## Call once after adding to the frame. [param station_node] gives the hull
## the station's corridors attach to.
func setup(station_node: HomeStation) -> void:
	station = Anchor.new()
	station.kind = Anchor.Kind.STATION
	station.radius = station_radius
	station.info = _station_info(station_node)
	anchors.append(station)
	for part: CorridorKit.Part in PARTS:
		_solid[part] = _make_mmi(part, null)


func _process(_delta: float) -> void:
	for owner: Building in _looks:
		if not is_instance_valid(owner):
			continue
		var mat: ShaderMaterial = _looks[owner]["mat"]
		var h := global_position.y + corridor_height
		var r := CorridorKit.TUBE_RADIUS + 1.5
		mat.set_shader_parameter("fill_y", lerpf(h - r, h + r, owner.get_progress()))


# --- Structures -----------------------------------------------------------------

## Registers a placed building as an anchor (before [method commit]).
func add_building(b: Building) -> void:
	if _by_building.has(b):
		return
	var an := Anchor.new()
	an.kind = Anchor.Kind.BUILDING
	an.building = b
	an.position = Vector3(b.position.x, 0.0, b.position.z)
	an.radius = b.def.footprint_radius
	an.info = model_info(b.def)
	anchors.append(an)
	_by_building[b] = an
	b.state_changed.connect(_on_building_state)


## Removes a building's corridors (and junctions left dangling).
func remove_building(b: Building) -> void:
	var an: Anchor = _by_building.get(b)
	if an == null:
		return
	for c in an.corridors.duplicate():
		_unlink(c)
	anchors.erase(an)
	_by_building.erase(b)
	for c in corridors:
		if c.owner == b:
			c.owner = null
	for j in anchors:
		if j.owner == b:
			j.owner = null
	_prune_junctions()
	if b.state_changed.is_connected(_on_building_state):
		b.state_changed.disconnect(_on_building_state)
	_rebuild()


func anchor_of(b: Building) -> Anchor:
	return _by_building.get(b)


## Corridors attached to [param b].
func corridors_of(b: Building) -> Array[Corridor]:
	var an := anchor_of(b)
	var out: Array[Corridor] = []
	if an:
		out.assign(an.corridors)
	return out


## Builds the planned corridor for the just-placed [param b].
func commit(p: Plan, b: Building) -> void:
	var an := anchor_of(b)
	if an == null or p == null or not p.has_link:
		return
	var end := p.target
	if p.split:
		end = _split(p.split, p.junction_pos, b)
	_link(an, end, p.pa, p.pb, b)
	_rebuild()


# --- Planning -------------------------------------------------------------------

## Best link for [param def] at frame-local [param offset]. NAN yaw = turn the
## docking mouth away from the link; a fixed yaw keeps the mouth where it is.
func plan(def: BuildingDef, offset: Vector3, fixed_yaw: float = NAN) -> Plan:
	var info := model_info(def)
	var pos := Vector3(offset.x, 0.0, offset.z)
	var r := def.footprint_radius
	var ok: Plan = null
	var first: Plan = null
	for c in _candidates(pos, r):
		var t := Plan.new()
		t.problem = _try(t, info, pos, r, fixed_yaw, c)
		if first == null:
			first = t
		if t.is_valid():
			ok = t
			break
	var p := ok if ok else first
	if p == null:
		p = Plan.new()
		p.yaw = 0.0 if is_nan(fixed_yaw) else fixed_yaw
		p.problem = "No station to link to"
	var g := _global_problem(pos, r)
	if not g.is_empty():
		p.problem = g
	return p


## Link candidates (anchors and corridor points) sorted by gap.
func _candidates(pos: Vector3, r: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for an in anchors:
		if an.kind == Anchor.Kind.JUNCTION:
			continue
		out.append({"anchor": an, "point": an.position, "gap": _flat(pos - an.position).length() - r - an.radius})
	for c in corridors:
		var a := _v2(c.pa)
		var b := _v2(c.pb)
		var length := a.distance_to(b)
		if length < junction_margin * 2.0 + CorridorKit.JUNCTION_PORT * 2.0:
			continue
		var q := Geometry2D.get_closest_point_to_segment(_v2(pos), a, b)
		var along := a.distance_to(q)
		if along < junction_margin + CorridorKit.JUNCTION_PORT or length - along < junction_margin + CorridorKit.JUNCTION_PORT:
			continue
		var point := Vector3(q.x, 0.0, q.y)
		out.append({"corridor": c, "point": point, "gap": _flat(pos - point).length() - r - CorridorKit.JUNCTION_PORT})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["gap"] < y["gap"])
	return out


## Fills [param t] with the link to candidate [param c]; returns its problem.
func _try(t: Plan, info: ModelInfo, pos: Vector3, r: float, fixed_yaw: float, c: Dictionary) -> String:
	var target: Anchor = c.get("anchor")
	var split: Corridor = c.get("corridor")
	var point: Vector3 = c["point"]
	var gap: float = c["gap"]
	var d := _flat(pos - point)
	d = d.normalized() if d.length() > 0.5 else Vector3.RIGHT
	t.target = target
	t.split = split
	t.junction_pos = point
	t.yaw = fixed_yaw if not is_nan(fixed_yaw) else _yaw_facing(info.mouth, d)
	t.pa = _attach(info.profile, pos, t.yaw, -d, r)
	if split:
		t.pb = point + d * CorridorKit.JUNCTION_PORT + Vector3.UP * corridor_height
	else:
		t.pb = _attach(target.info.profile, target.position, target.yaw(), d, target.radius)
	t.has_link = true
	var target_name := target.label() if target else "a corridor"

	if gap > max_link:
		return "Too far from the station complex (corridors reach %d m)" % roundi(max_link)
	if split and gap < min_corridor:
		return "Too close to a corridor"
	if info.mouth != Vector3.ZERO and _angle_deg(info.mouth.rotated(Vector3.UP, t.yaw), -d) < mouth_clear_deg:
		return "The corridor would leave through this structure's docking bay"
	if target and target.has_lane() and _angle_deg(target.mouth_world(), d) < mouth_clear_deg:
		return "The corridor would block the docking bay of %s" % target_name
	if t.pa.distance_to(t.pb) < min_corridor:
		return "Too close to %s" % target_name
	if target:
		for k in target.corridors:
			if _angle_deg(_flat(k.end_at(target) - target.position), d) < min_branch_angle_deg:
				return "Too close to another corridor at %s" % target_name

	var a2 := _v2(t.pa)
	var b2 := _v2(t.pb)
	for an in anchors:
		if an == target or an.kind == Anchor.Kind.JUNCTION:
			continue
		var dist := _seg_point(a2, b2, _v2(an.position))
		if an.kind == Anchor.Kind.STATION:
			if dist < station_clearance:
				return "The corridor would run through the Home Station"
			continue
		if dist < an.radius + footprint_margin + CorridorKit.TUBE_RADIUS:
			return "The corridor would run through %s" % an.label()
		if an.has_lane() and _seg_seg(a2, b2, _v2(an.lane_a()), _v2(an.lane_b())) < lane_half_width + CorridorKit.TUBE_RADIUS:
			return "The corridor would cross the docking lane of %s" % an.label()
	for k in corridors:
		if k == split or (target and (k.a == target or k.b == target)):
			continue
		if _seg_seg(a2, b2, _v2(k.pa), _v2(k.pb)) < corridor_spacing:
			return "The corridor would cross another corridor"

	if info.mouth != Vector3.ZERO:
		var la := _v2(pos + info.lane_a.rotated(Vector3.UP, t.yaw))
		var lb := _v2(pos + info.lane_b.rotated(Vector3.UP, t.yaw))
		for an in anchors:
			if an.kind == Anchor.Kind.STATION and _seg_point(la, lb, _v2(an.position)) < station_clearance:
				return "Docking lane blocked by the Home Station"
			if an.kind == Anchor.Kind.BUILDING and _seg_point(la, lb, _v2(an.position)) < an.radius + lane_half_width:
				return "Docking lane blocked by %s" % an.label()
		for k in corridors:
			if _seg_seg(la, lb, _v2(k.pa), _v2(k.pb)) < lane_half_width + CorridorKit.TUBE_RADIUS:
				return "Docking lane blocked by a corridor"
	return ""


## Problems of the spot itself, whatever the link.
func _global_problem(pos: Vector3, r: float) -> String:
	var p := _v2(pos)
	for an in anchors:
		if an.kind == Anchor.Kind.JUNCTION:
			continue
		if p.distance_to(_v2(an.position)) - r - an.radius < min_gap:
			return "Too close to %s" % an.label()
	for k in corridors:
		if _seg_point(_v2(k.pa), _v2(k.pb), p) < r + footprint_margin + CorridorKit.TUBE_RADIUS:
			return "Overlaps a corridor"
	for an in anchors:
		if an.has_lane() and _seg_point(_v2(an.lane_a()), _v2(an.lane_b()), p) < r + lane_half_width:
			return "Blocks the docking lane of %s" % an.label()
	return ""


## Corridor end on a hull: centre + dir * hull reach at corridor height.
func _attach(profile: PackedFloat32Array, centre: Vector3, yaw: float, dir: Vector3, footprint: float) -> Vector3:
	var reach := HullProfile.radius_at(profile, dir.rotated(Vector3.UP, -yaw))
	reach = clampf(reach - collar_inset, 4.0, footprint * 1.2)
	return Vector3(centre.x, corridor_height, centre.z) + dir * reach


## Yaw that turns model-space [param mouth] onto [param dir].
static func _yaw_facing(mouth: Vector3, dir: Vector3) -> float:
	if mouth == Vector3.ZERO:
		return 0.0
	return atan2(dir.x, dir.z) - atan2(mouth.x, mouth.z)


# --- Model info -----------------------------------------------------------------

## Hull profile and docking lane of [param def]'s model (cached per model).
func model_info(def: BuildingDef) -> ModelInfo:
	var has_file := not def.model_path.is_empty() and ResourceLoader.exists(def.model_path)
	var key := def.model_path if has_file else "placeholder:%s" % def.footprint_radius
	if _infos.has(key):
		return _infos[key]
	var model := ModelLoader.instantiate(def.model_path, ModelLoader.building_placeholder.bind(def.footprint_radius))
	var info := ModelInfo.new()
	info.profile = HullProfile.build(model, corridor_height, CorridorKit.TUBE_RADIUS, CorridorKit.TUBE_RADIUS * 0.8)
	# Same rules as Building._dock() / _dock_outward() / _spawn().
	var dock := Vector3(def.footprint_radius, 0.0, 0.0)
	var out := Vector3.ZERO
	var dock_node := model.find_child("dock_point", true, false) as Node3D
	if dock_node:
		var xf := ModelLoader.relative_transform(model, dock_node)
		dock = xf.origin
		out = -xf.basis.z
		if Vector2(out.x, out.z).length() < 0.1:
			out = dock
	out.y = 0.0
	out = out.normalized() if out.length() > 0.01 else Vector3.RIGHT
	var spawn_node := model.find_child("spawn_point", true, false) as Node3D
	var spawn := ModelLoader.relative_transform(model, spawn_node).origin if spawn_node else dock + out * 18.0
	info.mouth = out
	info.lane_a = _flat(dock)
	info.lane_b = _flat(spawn) + out * lane_reach
	model.free()
	_infos[key] = info
	return info


func _station_info(station_node: HomeStation) -> ModelInfo:
	var info := ModelInfo.new()
	var model := station_node.get_model() if station_node else null
	if model:
		info.profile = HullProfile.build(model, corridor_height, CorridorKit.TUBE_RADIUS, CorridorKit.TUBE_RADIUS * 0.8, station_node.get_ring())
	return info


# --- Graph edits ------------------------------------------------------------------

func _link(a: Anchor, b: Anchor, pa: Vector3, pb: Vector3, owner: Building) -> Corridor:
	var c := Corridor.new()
	c.a = a
	c.b = b
	c.pa = pa
	c.pb = pb
	c.owner = owner
	a.corridors.append(c)
	b.corridors.append(c)
	corridors.append(c)
	return c


func _unlink(c: Corridor) -> void:
	c.a.corridors.erase(c)
	c.b.corridors.erase(c)
	corridors.erase(c)


## Splits [param c] at plane point [param q] with a new junction.
func _split(c: Corridor, q: Vector3, owner: Building) -> Anchor:
	var j := Anchor.new()
	j.kind = Anchor.Kind.JUNCTION
	j.position = _flat(q)
	j.axis = _flat(c.pb - c.pa).normalized()
	j.radius = CorridorKit.JUNCTION_PORT
	j.owner = owner
	anchors.append(j)
	_unlink(c)
	var hub := j.position + Vector3.UP * corridor_height
	_link(c.a, j, c.pa, hub - j.axis * CorridorKit.JUNCTION_PORT, c.owner)
	_link(j, c.b, hub + j.axis * CorridorKit.JUNCTION_PORT, c.pb, c.owner)
	return j


## Drops junctions left with one corridor (and that stub), and merges a
## junction left with just its two straight-through halves.
func _prune_junctions() -> void:
	var again := true
	while again:
		again = false
		for j in anchors.duplicate():
			if j.kind != Anchor.Kind.JUNCTION:
				continue
			if j.corridors.size() <= 1:
				for c in j.corridors.duplicate():
					_unlink(c)
				anchors.erase(j)
				again = true
			elif j.corridors.size() == 2:
				var c1: Corridor = j.corridors[0]
				var c2: Corridor = j.corridors[1]
				var x: Anchor = c1.b if c1.a == j else c1.a
				var y: Anchor = c2.b if c2.a == j else c2.a
				var d1 := _flat(c1.end_at(x) - j.position)
				if absf(d1.normalized().dot(j.axis)) < 0.99:
					continue
				_unlink(c1)
				_unlink(c2)
				anchors.erase(j)
				_link(x, y, c1.end_at(x), c2.end_at(y), c1.owner if c1.owner else c2.owner)
				again = true


func _on_building_state(_b: Building) -> void:
	_rebuild()


# --- Drawing --------------------------------------------------------------------

## Kit piece transforms for a corridor from [param pa] to [param pb], added
## to [param out] (part -> Array[Transform3D]). Collars where an end meets a
## structure, segments tiled (uniformly stretched) in between.
static func corridor_pieces(pa: Vector3, pb: Vector3, collar_a: bool, collar_b: bool, out: Dictionary) -> void:
	var span := pb - pa
	var length := span.length()
	if length < 0.5:
		return
	var dir := span / length
	var basis := Basis.looking_at(dir, Vector3.UP)
	var start := pa
	var end := pb
	if collar_a:
		_push(out, CorridorKit.Part.COLLAR, Transform3D(basis, pa))
		start += dir * CorridorKit.COLLAR_LENGTH
	if collar_b:
		_push(out, CorridorKit.Part.COLLAR, Transform3D(Basis.looking_at(-dir, Vector3.UP), pb))
		end -= dir * CorridorKit.COLLAR_LENGTH
	var middle := (end - start).dot(dir)
	if middle < 0.5:
		return
	var n := maxi(roundi(middle / CorridorKit.SEGMENT_LENGTH), 1)
	var s := middle / (n * CorridorKit.SEGMENT_LENGTH)
	var seg_basis := basis * Basis.from_scale(Vector3(1.0, 1.0, s))
	for i in n:
		_push(out, CorridorKit.Part.SEGMENT, Transform3D(seg_basis, start + dir * (i * CorridorKit.SEGMENT_LENGTH * s)))


## Junction transform at plane point [param pos], through-axis [param axis].
func junction_piece(pos: Vector3, axis: Vector3, out: Dictionary) -> void:
	_push(out, CorridorKit.Part.JUNCTION, Transform3D(Basis.looking_at(axis, Vector3.UP), _flat(pos) + Vector3.UP * corridor_height))


## Pieces of a planned link, for the placement preview.
func plan_pieces(p: Plan) -> Dictionary:
	var out := {}
	if p == null or not p.has_link:
		return out
	corridor_pieces(p.pa, p.pb, true, p.split == null, out)
	if p.split:
		junction_piece(p.junction_pos, _flat(p.split.pb - p.split.pa).normalized(), out)
	return out


static func _push(out: Dictionary, part: CorridorKit.Part, xf: Transform3D) -> void:
	if not out.has(part):
		var list: Array[Transform3D] = []
		out[part] = list
	(out[part] as Array[Transform3D]).append(xf)


## Writes [param xfs] (Array[Transform3D]) into [param mmi]'s MultiMesh.
static func fill_multimesh(mmi: MultiMeshInstance3D, xfs: Array) -> void:
	var mm := mmi.multimesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	mmi.visible = not xfs.is_empty()


func _rebuild() -> void:
	var solid := {}
	var building := {}
	for c in corridors:
		var dst := solid if _is_solid(c.owner) else _bucket(building, c.owner)
		corridor_pieces(c.pa, c.pb, c.a.kind != Anchor.Kind.JUNCTION, c.b.kind != Anchor.Kind.JUNCTION, dst)
	for j in anchors:
		if j.kind == Anchor.Kind.JUNCTION:
			junction_piece(j.position, j.axis, solid if _is_solid(j.owner) else _bucket(building, j.owner))
	for part: CorridorKit.Part in PARTS:
		fill_multimesh(_solid[part], solid.get(part, []))
	for owner: Building in _looks.keys():
		if not building.has(owner):
			for mmi: MultiMeshInstance3D in (_looks[owner]["mmis"] as Dictionary).values():
				mmi.queue_free()
			_looks.erase(owner)
	for owner: Building in building:
		if not _looks.has(owner):
			var mat := ShaderMaterial.new()
			mat.shader = CONSTRUCTION_SHADER
			mat.set_shader_parameter("grid_size", 2.5)
			var mmis := {}
			for part: CorridorKit.Part in PARTS:
				mmis[part] = _make_mmi(part, mat)
			_looks[owner] = {"mat": mat, "mmis": mmis}
		var parts: Dictionary = building[owner]
		for part: CorridorKit.Part in PARTS:
			fill_multimesh(_looks[owner]["mmis"][part], parts.get(part, []))
	set_process(not _looks.is_empty())
	if not _looks.is_empty():
		_process(0.0)
	changed.emit()


static func _bucket(by_owner: Dictionary, owner: Building) -> Dictionary:
	if not by_owner.has(owner):
		by_owner[owner] = {}
	return by_owner[owner]


static func _is_solid(owner: Building) -> bool:
	return owner == null or not is_instance_valid(owner) or owner.is_active()


func _make_mmi(part: CorridorKit.Part, mat: Material) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Corridor%s" % ("Solid" if mat == null else "Build")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = CorridorKit.mesh(part)
	mmi.multimesh = mm
	mmi.layers = Building.RENDER_LAYER
	if mat:
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visible = false
	add_child(mmi)
	return mmi


# --- Placement zone and framing -------------------------------------------------

## Plane rectangle (frame-local x, z) covering every structure's footprint.
func complex_bounds() -> Rect2:
	var box := Rect2()
	var first := true
	for an in anchors:
		if an.kind == Anchor.Kind.JUNCTION:
			continue
		var r := Rect2(an.position.x - an.radius, an.position.z - an.radius, an.radius * 2.0, an.radius * 2.0)
		box = r if first else box.merge(r)
		first = false
	return box


## Zone shapes for a structure of footprint [param r], for shaders/link_zone:
## "discs" (x, z, inner, outer) per structure: centres between inner and outer
## reach it; "segs" (ax, az, bx, bz) per corridor, reach = "seg_reach".
func zone_shapes(r: float) -> Dictionary:
	var discs := PackedVector4Array()
	var segs := PackedVector4Array()
	for an in anchors:
		if an.kind == Anchor.Kind.JUNCTION:
			continue
		discs.append(Vector4(an.position.x, an.position.z, an.radius + r + min_gap, an.radius + r + max_link))
	for c in corridors:
		segs.append(Vector4(c.pa.x, c.pa.z, c.pb.x, c.pb.z))
	return {
		"discs": discs,
		"segs": segs,
		"seg_inner": r + footprint_margin + CorridorKit.TUBE_RADIUS,
		"seg_reach": r + CorridorKit.JUNCTION_PORT + max_link,
	}


# --- 2D helpers -----------------------------------------------------------------

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func _v2(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


static func _angle_deg(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(absf(Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z))))


static func _seg_point(a: Vector2, b: Vector2, p: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))


static func _seg_seg(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
		return 0.0
	return minf(minf(_seg_point(c, d, a), _seg_point(c, d, b)), minf(_seg_point(a, b, c), _seg_point(a, b, d)))

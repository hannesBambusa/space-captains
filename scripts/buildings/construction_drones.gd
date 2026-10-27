class_name ConstructionDrones
extends Node3D
## The worker drones of one construction site: a child of the [Building]
## (building space), made when construction starts and freed after the
## drones flew home. 3 to 6 [ConstructionDrone]s by footprint fly in from
## the station's nearer docking pad, weld along the build line
## ([ConstructionLook]) and fly back when the structure is done
## ([method depart]). Cosmetic only: no collision, no groups, not saved (a
## loaded site just gets fresh drones). One flickering weld light per site.
## Animates on sim time: paused = hovering idle, no welding.

const DRONE_PATH := "res://assets/models/ships/construction_drone.glb"
# Paths, loaded at runtime: preloaded consts in a script with static vars
# outlive the renderer at exit (leaked shader RIDs).
const BEAM_SHADER_PATH := "res://shaders/weld_beam.gdshader"
const GLOW_SHADER_PATH := "res://shaders/fx_glow.gdshader"
const WELD_COLOR := Color(1.0, 0.72, 0.4)
## Drones and their effects are hidden beyond this camera distance, metres.
const VISIBLE_RANGE := 1600.0
## Surface points sampled per model for work points.
const SAMPLE_COUNT := 260
## Drones appear (fading in) at most this far out toward the station, metres.
const ENTRY_DISTANCE := 75.0
## Drones avoid work points this close to another drone's, metres.
const CROWD_DISTANCE := 7.0
## A sim-time jump bigger than this (fast-forward) snaps the drones.
const SNAP_JUMP := 1.0

## Model scale: the drone is ~1.6 m long.
@export var drone_scale: float = 2.0
## Hover distance off the surface while welding, metres.
@export var standoff: float = 2.6

var _building: Building
var _look: ConstructionLook
var _box: AABB
var _drones: Array[ConstructionDrone] = []
var _points: Array[Vector3] = []
var _normals: Array[Vector3] = []
var _home := Vector3.ZERO
var _light: OmniLight3D
var _departing := false
var _last_time := 0.0
var _clock := 0.0
var _rng := RandomNumberGenerator.new()

# Shared by this site's drones.
var _beam_mat: ShaderMaterial
var _glow_mat: ShaderMaterial
var _spark_mesh: QuadMesh
var _spark_ramp: Gradient

static var _samples := {}


func setup(building: Building, look: ConstructionLook) -> void:
	_building = building
	_look = look
	_box = look.model_box()
	name = "ConstructionDrones"


func _ready() -> void:
	_rng.seed = hash(_building.name)
	_sample_points()
	_home = _station_home()
	_last_time = SimClock.time
	_light = OmniLight3D.new()
	_light.name = "WeldLight"
	_light.light_color = WELD_COLOR
	_light.omni_range = 9.0 * drone_scale
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.light_cull_mask = Building.RENDER_LAYER
	_light.visible = false
	add_child(_light)
	var count := clampi(int(_building.def.footprint_radius / 7.0), 3, 6)
	# They come in from the station's side, already close: the trip from the
	# pad itself would take most of a short build.
	var entry := _home.normalized() * minf(_home.length(), ENTRY_DISTANCE) + Vector3.UP * 6.0
	for i in count:
		var d := ConstructionDrone.new()
		var start := entry + Vector3(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-1.0, 2.0), _rng.randf_range(-3.0, 3.0))
		d.setup(self, i, _make_model(), start, float(i) * 0.3, drone_scale)
		add_child(d)
		_drones.append(d)


func _process(delta: float) -> void:
	var paused := SimClock.paused
	var dt := 0.0 if paused else delta * SimClock.speed
	var jump := SimClock.time - _last_time
	var snap := jump > maxf(dt * 3.0, SNAP_JUMP)
	_last_time = SimClock.time
	_clock += dt
	var any := false
	var lit: ConstructionDrone = null
	for d in _drones:
		d.step(dt, delta, paused, snap)
		if not d.is_gone():
			any = true
		if lit == null and d.is_welding() and not paused:
			lit = d
	if lit:
		_light.visible = true
		_light.position = lit.work_point + Vector3.UP * 0.6
		_light.light_energy = 1.1 + 0.6 * sin(_clock * 31.0) * sin(_clock * 17.0)
	else:
		_light.visible = false
	if _departing and not any:
		queue_free()


## Sends every drone home; the node frees itself when they are gone.
func depart() -> void:
	_departing = true
	for d in _drones:
		d.depart(_home)


func drone_count() -> int:
	return _drones.size()


## Drones still out (not faded home).
func active_count() -> int:
	var n := 0
	for d in _drones:
		if not d.is_gone():
			n += 1
	return n


func welding_count() -> int:
	var n := 0
	for d in _drones:
		if d.is_welding():
			n += 1
	return n


func box_center() -> Vector3:
	return _box.get_center()


## Where drone [param index] waits first: beside the base, in its sector.
func approach_point(index: int) -> Vector3:
	var c := _box.get_center()
	var a := _sector_angle(index)
	var r := _ring_radius()
	return Vector3(c.x + cos(a) * r, _box.position.y + 3.0, c.z + sin(a) * r)


## A work point near the build line for drone [param index] at [param from]:
## [position, outward normal] in building space, or [] when none.
func pick_work_point(index: int, from: Vector3) -> Array:
	if _points.is_empty():
		return []
	var cut := maxf(_cut(), _box.position.y + 1.5)
	var band := _band()
	var c := _box.get_center()
	var sector := _sector_angle(index)
	var spread := TAU / float(maxi(_drones.size(), 1))
	var best := -1
	var best_score := INF
	for t in 40:
		var i := _rng.randi_range(0, _points.size() - 1)
		var p := _points[i]
		var dy := cut - p.y
		var off := 0.0 if dy >= -band * 0.4 and dy <= band else absf(dy - band * 0.3)
		var ang := absf(wrapf(atan2(p.z - c.z, p.x - c.x) - sector, -PI, PI))
		var score := off * 2.0 + maxf(ang - spread * 0.6, 0.0) * 6.0 + from.distance_to(p) * 0.35 + _rng.randf() * 0.8
		for other in _drones:
			if other != _drones[index] and other.work_point.distance_to(p) < CROWD_DISTANCE:
				score += 12.0
		if score < best_score:
			best_score = score
			best = i
	return [_points[best], _normals[best]]


## True once the build line moved well past [param p].
func point_built_over(p: Vector3) -> bool:
	return p.y < _cut() - _band() * 1.6


## Where a drone hovers to weld [param p] (normal [param n]).
func hover_point(p: Vector3, n: Vector3) -> Vector3:
	var s := standoff * drone_scale / 1.5
	if n.y > 0.7:
		return p + Vector3.UP * s
	var flat := Vector3(n.x, 0.0, n.z).normalized()
	return p + flat * s + Vector3.UP * 0.8


## Waypoints from [param from] to [param to] that go around the structure
## instead of through it.
func route(from: Vector3, to: Vector3) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	if not _crosses(from, to):
		pts.append(to)
		return pts
	var c := _box.get_center()
	var a0 := atan2(from.z - c.z, from.x - c.x)
	var diff := wrapf(atan2(to.z - c.z, to.x - c.x) - a0, -PI, PI)
	var r := clampf(maxf(SpaceNav.flat_distance(from, c), SpaceNav.flat_distance(to, c)),
			_core_radius() + 3.0, maxf(_ring_radius(), _core_radius() + 3.0))
	var steps := maxi(ceili(absf(diff) / (PI * 0.25)), 2)
	for k in range(1, steps):
		var f := float(k) / float(steps)
		var a := a0 + diff * f
		pts.append(Vector3(c.x + cos(a) * r, lerpf(from.y, to.y, f) + 1.5, c.z + sin(a) * r))
	pts.append(to)
	return pts


## Basis whose +Y is [param n] (sparks fly out along it).
func basis_up_to(n: Vector3) -> Basis:
	var y := n.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y))


func make_beam() -> MeshInstance3D:
	if _beam_mat == null:
		_beam_mat = ShaderMaterial.new()
		_beam_mat.shader = load(BEAM_SHADER_PATH) as Shader
		_beam_mat.set_shader_parameter("beam_color", WELD_COLOR)
		_beam_mat.set_shader_parameter("width", 0.2)
		_beam_mat.set_shader_parameter("energy", 4.0)
	var mi := MeshInstance3D.new()
	mi.name = "WeldBeam"
	mi.mesh = _quad(Vector2.ONE)
	mi.material_override = _beam_mat
	_fx_instance(mi)
	return mi


func make_glow() -> MeshInstance3D:
	if _glow_mat == null:
		_glow_mat = ShaderMaterial.new()
		_glow_mat.shader = load(GLOW_SHADER_PATH) as Shader
		_glow_mat.set_shader_parameter("glow_color", Color(1.0, 0.55, 0.22))
		_glow_mat.set_shader_parameter("size", 2.6)
		_glow_mat.set_shader_parameter("min_px", 6.0)
		_glow_mat.set_shader_parameter("energy", 3.0)
	var mi := MeshInstance3D.new()
	mi.name = "WeldGlow"
	mi.mesh = _quad(Vector2.ONE)
	mi.material_override = _glow_mat
	_fx_instance(mi)
	return mi


## A few sparks (CPU particles: 14 each, cheaper than a GPU process
## shader per site).
func make_sparks() -> CPUParticles3D:
	if _spark_mesh == null:
		var m := ShaderMaterial.new()
		m.shader = load(GLOW_SHADER_PATH) as Shader
		m.set_shader_parameter("glow_color", Color(1.0, 0.85, 0.6))
		m.set_shader_parameter("size", 0.3)
		m.set_shader_parameter("min_px", 1.5)
		m.set_shader_parameter("energy", 3.0)
		_spark_mesh = _quad(Vector2.ONE)
		_spark_mesh.material = m
		_spark_ramp = Gradient.new()
		_spark_ramp.set_color(0, Color(1.0, 0.95, 0.8, 1.0))
		_spark_ramp.set_color(1, Color(1.0, 0.45, 0.15, 0.0))
	var p := CPUParticles3D.new()
	p.name = "WeldSparks"
	p.amount = 14
	p.lifetime = 0.5
	p.emitting = false
	p.local_coords = true
	p.mesh = _spark_mesh
	p.direction = Vector3.UP
	p.spread = 65.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 7.0
	p.gravity = Vector3.ZERO
	p.damping_min = 3.0
	p.damping_max = 6.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.color_ramp = _spark_ramp
	_fx_instance(p)
	return p


func _fx_instance(g: GeometryInstance3D) -> void:
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.visibility_range_end = VISIBLE_RANGE
	g.visible = false
	g.layers = Building.RENDER_LAYER
	if g is MeshInstance3D:
		g.custom_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	add_child(g)


static func _quad(size: Vector2) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = size
	return q


func _make_model() -> Node3D:
	return ModelLoader.instantiate(DRONE_PATH, _placeholder)


## Stand-in until the drone model exists: a body, an arm with a weld tip, a light.
static func _placeholder() -> Node3D:
	var root := Node3D.new()
	root.name = "drone_placeholder"
	var hull := StandardMaterial3D.new()
	hull.albedo_color = Color(0.85, 0.84, 0.8)
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.5, 1.2)
	box.material = hull
	body.mesh = box
	body.name = "drone_body"
	root.add_child(body)
	var arm := MeshInstance3D.new()
	var arm_box := BoxMesh.new()
	arm_box.size = Vector3(0.12, 0.12, 0.6)
	arm_box.material = hull
	arm.mesh = arm_box
	arm.name = "drone_arm"
	arm.position = Vector3(0.0, -0.17, -0.28)
	root.add_child(arm)
	var tip := Marker3D.new()
	tip.name = "weld_tip"
	tip.position = ConstructionDrone.TIP_FALLBACK
	arm.add_child(tip)
	var light := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.75, 0.3)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.75, 0.3)
	glow.emission_energy_multiplier = 5.0
	sphere.material = glow
	light.mesh = sphere
	light.name = "drone_light"
	light.position = Vector3(0.0, 0.3, 0.1)
	root.add_child(light)
	return root


# --- Geometry -------------------------------------------------------------------

## The build line now (the top once the look is gone).
func _cut() -> float:
	if is_instance_valid(_look):
		return _look.cut_height(_building.get_progress())
	return _box.end.y


func _sector_angle(index: int) -> float:
	return float(index) / float(maxi(_drones.size(), 1)) * TAU + 0.4


func _ring_radius() -> float:
	return SpaceNav.flat_length(_box.size) * 0.5 + standoff + 2.0


func _band() -> float:
	return maxf(2.5, _box.size.y * 0.12)


## Radius of the structure's solid core column (the model box is a loose
## fit, most hover points lie inside it).
func _core_radius() -> float:
	return minf(_box.size.x, _box.size.z) * 0.3


## True when the segment passes through the core column below the top.
func _crosses(a: Vector3, b: Vector3) -> bool:
	var c := _box.get_center()
	var r := _core_radius()
	for k in range(1, 8):
		var q := a.lerp(b, float(k) / 8.0)
		if q.y < _box.end.y and SpaceNav.flat_distance(q, c) < r:
			return true
	return false


## The nearer station docking pad (building space), or the station hub
## when there is none. Drones fly home toward it and fade out on the way.
func _station_home() -> Vector3:
	var frame := _building.get_parent() as Node3D
	var orbiter := frame.get_parent() as Node3D if frame else null
	var station := orbiter.get_node_or_null(^"Station") as HomeStation if orbiter else null
	var best := Vector3.ZERO
	if station:
		var best_d := INF
		for i in station.dock_pad_count:
			var p := to_local(station.global_transform * station.dock_pad(i))
			if p.length() < best_d:
				best_d = p.length()
				best = p
	elif frame:
		best = to_local(frame.global_position)
	if best.length() < 1.0:
		best = Vector3(0.0, _box.end.y + 20.0, 0.0)
	return best


## Area-weighted surface points of the model (building space) with their
## normals, skipping undersides; cached per building type.
func _sample_points() -> void:
	var key := _building.def.id
	if _samples.has(key):
		_points = _samples[key][0]
		_normals = _samples[key][1]
		return
	var tris: Array[Vector3] = []
	var tri_n: Array[Vector3] = []
	var areas: Array[float] = []
	var total := 0.0
	var model := _building.get_model()
	for mi in ModelLoader.meshes_of(model):
		if mi.mesh == null:
			continue
		var xf := _building.global_transform.affine_inverse() * mi.global_transform
		var nb := xf.basis.inverse().transposed()
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var n := idx.size() if not idx.is_empty() else verts.size()
			for t in range(0, n - 2, 3):
				var i0 := idx[t] if not idx.is_empty() else t
				var i1 := idx[t + 1] if not idx.is_empty() else t + 1
				var i2 := idx[t + 2] if not idx.is_empty() else t + 2
				var a := xf * verts[i0]
				var b := xf * verts[i1]
				var c := xf * verts[i2]
				var area := (b - a).cross(c - a).length() * 0.5
				if area < 1e-4:
					continue
				var fn := (b - a).cross(c - a).normalized()
				if not norms.is_empty():
					fn = (nb * (norms[i0] + norms[i1] + norms[i2])).normalized()
				tris.append_array([a, b, c])
				tri_n.append(fn)
				total += area
				areas.append(total)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(key))
	var pts: Array[Vector3] = []
	var nrm: Array[Vector3] = []
	if total > 0.0:
		for i in SAMPLE_COUNT * 3:
			if pts.size() >= SAMPLE_COUNT:
				break
			var ti := mini(areas.bsearch(rng.randf() * total), areas.size() - 1)
			var nn := tri_n[ti]
			if nn.y < -0.3:
				continue
			var a := tris[ti * 3]
			var b := tris[ti * 3 + 1]
			var c := tris[ti * 3 + 2]
			var u := rng.randf()
			var v := rng.randf()
			if u + v > 1.0:
				u = 1.0 - u
				v = 1.0 - v
			pts.append(a + (b - a) * u + (c - a) * v)
			nrm.append(nn)
	_samples[key] = [pts, nrm]
	_points = pts
	_normals = nrm

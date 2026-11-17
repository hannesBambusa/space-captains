class_name SurfaceDressing
extends Node3D
## Scenery of a live landing zone ([SurfaceWorld]), looks only, no rules:
## scattered rocks (three faceted rock shapes as MultiMeshes, seeded from
## the outpost, clumped, small where vehicles drive, boulders out in the
## scenery), a graded apron under every building, a track from the landing
## pad to each building with marker lamps along it, and a work light at
## each building. Aprons and tracks are thin meshes draped on the ground
## (shaders/surface_apron.gdshader). Gas giants get none of it (the decks
## float). [method add_building] dresses a building placed later and clears
## the rocks under it.

const ROCK_TRIES := 16000
const ROCK_REACH := 2700.0
## Rocks this far out may be boulders (no vehicle drives there).
const BOULDER_FROM := 1900.0
const PAD_CLEAR := 78.0
const APRON_MARGIN := 16.0
const LIFT := 0.22
const TRACK_WIDTH := 11.0
const LAMP_EVERY := 26.0
## Rock, apron and lamp colours by PlanetDef.Type.
const ROCK_COLOR := {PlanetDef.Type.ROCKY: Color(0.17, 0.15, 0.13), PlanetDef.Type.OCEAN: Color(0.2, 0.22, 0.2),
		PlanetDef.Type.DESERT: Color(0.34, 0.22, 0.14), PlanetDef.Type.ICE: Color(0.55, 0.68, 0.8), PlanetDef.Type.LAVA: Color(0.07, 0.06, 0.06)}
const APRON_COLOR := {PlanetDef.Type.ROCKY: Color(0.2, 0.19, 0.18), PlanetDef.Type.OCEAN: Color(0.27, 0.28, 0.27),
		PlanetDef.Type.DESERT: Color(0.36, 0.3, 0.24), PlanetDef.Type.ICE: Color(0.36, 0.4, 0.45), PlanetDef.Type.LAVA: Color(0.16, 0.15, 0.15)}

## Dust a hovering vehicle kicks up, by PlanetDef.Type (ocean: spray, ice: snow).
const DUST_COLOR := {PlanetDef.Type.ROCKY: Color(0.42, 0.37, 0.32), PlanetDef.Type.OCEAN: Color(0.6, 0.62, 0.6),
		PlanetDef.Type.DESERT: Color(0.72, 0.55, 0.36), PlanetDef.Type.ICE: Color(0.92, 0.95, 1.0), PlanetDef.Type.LAVA: Color(0.2, 0.18, 0.17)}

static var _puff: Texture2D

var world: SurfaceWorld
var _rocks: Array[MultiMeshInstance3D] = []
## Per rock shape: the instances' flat positions (to clear a spot later).
var _rock_at: Array = []
var _apron_mat: ShaderMaterial
var _track_mat: ShaderMaterial
var _lamps: MultiMeshInstance3D
var _lamp_at: Array[Vector3] = []


func setup(w: SurfaceWorld) -> void:
	world = w
	name = "Dressing"


func _ready() -> void:
	if world == null or world.terrain.is_gas():
		return
	_make_materials()
	_scatter_rocks()
	_lamps = MultiMeshInstance3D.new()
	_lamps.name = "TrackLamps"
	_lamps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(1.0, 0.72, 0.3)
	lm.emission_enabled = true
	lm.emission = Color(1.0, 0.62, 0.2)
	lm.emission_energy_multiplier = 3.0
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 1.1, 0.5)
	box.material = lm
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	_lamps.multimesh = mm
	add_child(_lamps)
	for b in world.outpost.buildings:
		_dress(b)
	_sync_lamps()


## A building placed after the zone was built.
func add_building(b: Dictionary) -> void:
	if world == null or world.terrain.is_gas():
		return
	_dress(b)
	_sync_lamps()


## A dust trail for a ground vehicle (a child of its node, [param below]
## metres under it, at the ground): on while it moves ([method SurfaceWorld._place]).
static func make_dust(planet_type: int, below: float) -> CPUParticles3D:
	if _puff == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64
		_puff = tex
	var c: Color = DUST_COLOR.get(planet_type, DUST_COLOR[PlanetDef.Type.ROCKY])
	var p := CPUParticles3D.new()
	p.name = "Dust"
	p.position = Vector3(0.0, -below + 0.6, 0.0)
	p.emitting = false
	p.local_coords = false
	p.amount = 26
	p.lifetime = 2.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 2.5
	p.direction = Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0.0, 0.5, 0.0)
	p.damping_min = 0.6
	p.damping_max = 1.2
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.35))
	grow.add_point(Vector2(1.0, 1.0))
	p.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(c.r, c.g, c.b, 0.0))
	fade.add_point(0.15, Color(c.r, c.g, c.b, 0.3))
	fade.set_color(fade.get_point_count() - 1, Color(c.r, c.g, c.b, 0.0))
	p.color_ramp = fade
	var quad := QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _puff
	m.disable_receive_shadows = true
	quad.material = m
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


# --- Buildings -----------------------------------------------------------------------

func _dress(b: Dictionary) -> void:
	var at := Vector2(float(b["x"]), float(b["z"]))
	var radius := float(OutpostState.BUILDINGS[StringName(b["kind"])]["radius"])
	_clear_rocks(at, radius + APRON_MARGIN)
	var apron := MeshInstance3D.new()
	apron.name = "Apron"
	apron.mesh = _disc_mesh(at, radius + APRON_MARGIN)
	apron.material_override = _apron_mat
	apron.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(apron)
	var light := OmniLight3D.new()
	light.name = "WorkLight"
	light.position = world.ground_at(at.x, at.y) + Vector3(0.0, 16.0, 0.0)
	light.light_color = Color(1.0, 0.86, 0.66)
	light.light_energy = 2.5
	light.omni_range = radius + 55.0
	light.omni_attenuation = 1.3
	add_child(light)
	if String(b["kind"]) == String(OutpostState.PAD) or at.length() < 1.0:
		return
	# A track from the pad's edge to this building's apron.
	var dir := at.normalized()
	var from := dir * (float(OutpostState.BUILDINGS[OutpostState.PAD]["radius"]) + 6.0)
	var to := at - dir * (radius + 4.0)
	if from.distance_to(to) < 12.0 or from.dot(dir) > to.dot(dir):
		return
	_clear_strip(from, to, TRACK_WIDTH * 0.5 + 2.0)
	var track := MeshInstance3D.new()
	track.name = "Track"
	track.mesh = _strip_mesh(from, to, TRACK_WIDTH)
	track.material_override = _track_mat
	track.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(track)
	var side := Vector2(-dir.y, dir.x) * (TRACK_WIDTH * 0.5 + 1.0)
	var n := maxi(int(from.distance_to(to) / LAMP_EVERY), 1)
	for i in n + 1:
		var p := from.lerp(to, float(i) / float(n))
		for s: float in [-1.0, 1.0]:
			var q := p + side * s
			_lamp_at.append(world.ground_at(q.x, q.y) + Vector3(0.0, 0.55, 0.0))


func _sync_lamps() -> void:
	var mm := _lamps.multimesh
	mm.instance_count = _lamp_at.size()
	for i in _lamp_at.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, _lamp_at[i]))


func _make_materials() -> void:
	var shader := load("res://shaders/surface_apron.gdshader") as Shader
	var c: Color = APRON_COLOR.get(world.outpost.planet_type, APRON_COLOR[PlanetDef.Type.ROCKY])
	_apron_mat = ShaderMaterial.new()
	_apron_mat.shader = shader
	_apron_mat.set_shader_parameter("base", c)
	_apron_mat.set_shader_parameter("track", false)
	_apron_mat.render_priority = 1
	_track_mat = ShaderMaterial.new()
	_track_mat.shader = shader
	_track_mat.set_shader_parameter("base", c)
	_track_mat.set_shader_parameter("track", true)
	_track_mat.render_priority = 2


## A disc draped on the ground round [param at]. UV: x = distance from the
## centre as a share of the radius, y = angle / TAU. UV2: zone metres.
func _disc_mesh(at: Vector2, radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 7
	var segs := 48
	for r in rings + 1:
		for s in segs + 1:
			var k := float(r) / float(rings)
			var a := TAU * float(s) / float(segs)
			var p := at + Vector2(cos(a), sin(a)) * radius * k
			st.set_normal(world.terrain.normal(p.x, p.y))
			st.set_uv(Vector2(k, float(s) / float(segs)))
			st.set_uv2(p)
			st.add_vertex(world.ground_at(p.x, p.y) + Vector3(0.0, LIFT, 0.0))
	for r in rings:
		for s in segs:
			var a := r * (segs + 1) + s
			var b := a + segs + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(b + 1)
	return st.commit()


## A strip draped on the ground from [param from] to [param to]. UV: x =
## across (0 to 1), y = metres along. UV2: zone metres.
func _strip_mesh(from: Vector2, to: Vector2, width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := from.distance_to(to)
	var dir := (to - from) / length
	var side := Vector2(-dir.y, dir.x)
	var n := maxi(int(length / 6.0), 1)
	var across := 4
	for i in n + 1:
		for j in across + 1:
			var along := length * float(i) / float(n)
			var p := from + dir * along + side * width * (float(j) / float(across) - 0.5)
			st.set_normal(world.terrain.normal(p.x, p.y))
			st.set_uv(Vector2(float(j) / float(across), along))
			st.set_uv2(p)
			st.add_vertex(world.ground_at(p.x, p.y) + Vector3(0.0, LIFT + 0.04, 0.0))
	for i in n:
		for j in across:
			var a := i * (across + 1) + j
			var b := a + across + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(b + 1)
	return st.commit()


# --- Rocks ---------------------------------------------------------------------------

func _scatter_rocks() -> void:
	var o := world.outpost
	var t := world.terrain
	var rng := RandomNumberGenerator.new()
	rng.seed = o.seed + 4101
	var clump := FastNoiseLite.new()
	clump.seed = o.seed + 77
	clump.frequency = 0.0022
	var base: Color = ROCK_COLOR.get(o.planet_type, ROCK_COLOR[PlanetDef.Type.ROCKY])
	var ice := o.planet_type == PlanetDef.Type.ICE
	var keep_out: Array[Vector3] = [Vector3(0.0, 0.0, PAD_CLEAR)]
	for d in o.deposits:
		keep_out.append(Vector3(float(d["x"]), float(d["z"]), 50.0))
	for d in o.nests:
		keep_out.append(Vector3(float(d["x"]), float(d["z"]), 60.0))
	var xf: Array = [[], [], []]
	var cols: Array = [[], [], []]
	_rock_at = [[], [], []]
	for i in ROCK_TRIES:
		# Uniform over the disc.
		var r := sqrt(rng.randf()) * ROCK_REACH
		var a := rng.randf() * TAU
		var p := Vector2(cos(a), sin(a)) * r
		var size_roll := rng.randf()
		var tilt := Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4))
		var squash := rng.randf_range(0.5, 0.95)
		var shade := rng.randf_range(0.72, 1.12)
		var shape := rng.randi() % 3
		# Rocks gather in fields; bare ground between them.
		var crowd := clump.get_noise_2d(p.x, p.y) * 0.5 + 0.5
		if rng.randf() > smoothstep(0.3, 0.7, crowd) + 0.08:
			continue
		var h := t.height(p.x, p.y)
		if t.has_liquid() and h < SurfaceTerrain.LIQUID_LEVEL + 1.0:
			continue
		var blocked := false
		for k in keep_out:
			if p.distance_to(Vector2(k.x, k.y)) < k.z:
				blocked = true
				break
		if blocked:
			continue
		# Mostly small stones; a few larger. Out in the scenery, boulders.
		var size := 0.6 + pow(size_roll, 3.0) * 3.2
		if r > BOULDER_FROM:
			size = 0.8 + pow(size_roll, 3.0) * 12.0
		var basis := Basis.from_euler(tilt).scaled(Vector3(size, size * (squash * (2.2 if ice else 1.0)), size))
		xf[shape].append(Transform3D(basis, Vector3(p.x, h - size * 0.25, p.y)))
		cols[shape].append(Color(base.r * shade, base.g * shade, base.b * shade))
		_rock_at[shape].append(p)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.35 if ice else 0.95
	mat.metallic = 0.0
	for s in 3:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _rock_mesh(o.seed + s * 31, ice)
		mm.instance_count = xf[s].size()
		for i in xf[s].size():
			mm.set_instance_transform(i, xf[s][i])
			mm.set_instance_color(i, cols[s][i])
		var mi := MultiMeshInstance3D.new()
		mi.name = "Rocks%d" % s
		mi.multimesh = mm
		mi.material_override = mat
		add_child(mi)
		_rocks.append(mi)


## One faceted rock about 1 m in radius: a coarse sphere pushed in and out
## by noise, flat shaded. Ice: sharper, taller shards.
static func _rock_mesh(seed_value: int, shard: bool) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.9
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 9
	sphere.rings = 5
	var arr := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in idx:
		var v := verts[i]
		var n := v.normalized()
		var k := 1.0 + noise.get_noise_3d(n.x * 2.0, n.y * 2.0, n.z * 2.0) * (0.75 if shard else 0.5)
		st.add_vertex(Vector3(n.x * k, n.y * k * (1.3 if shard else 0.8), n.z * k))
	st.generate_normals()
	return st.commit()


func _clear_rocks(at: Vector2, radius: float) -> void:
	for s in _rocks.size():
		var mm := _rocks[s].multimesh
		var list: Array = _rock_at[s]
		for i in list.size():
			if (list[i] as Vector2).distance_to(at) < radius:
				mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0.0, -1000.0, 0.0)))
				list[i] = Vector2(INF, INF)


func _clear_strip(from: Vector2, to: Vector2, half: float) -> void:
	var ab := to - from
	var len2 := maxf(ab.length_squared(), 1e-6)
	for s in _rocks.size():
		var mm := _rocks[s].multimesh
		var list: Array = _rock_at[s]
		for i in list.size():
			var p: Vector2 = list[i]
			if not is_finite(p.x):
				continue
			var k := clampf((p - from).dot(ab) / len2, 0.0, 1.0)
			if p.distance_to(from + ab * k) < half:
				mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0.0, -1000.0, 0.0)))
				list[i] = Vector2(INF, INF)

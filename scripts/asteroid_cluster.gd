class_name AsteroidCluster
extends Orbiter
## An asteroid cluster at system scale, built from a ClusterDef: a dense clump
## 1 to 3 km across on an inclined circular orbit around the star (an
## Orbiter: it never rotates, so cluster-local space is a level frame that
## drifts with the orbit). The class keeps its old name; "belt" in code
## means a cluster.
##
## Three layers, so it reads at every zoom:
## - near: detailed asteroid meshes in grid chunks (one MultiMeshInstance3D
##   per chunk and mesh variant) with visibility ranges; each asteroid shrinks
##   away in the vertex shader before its chunk is culled. No shadows.
## - mid/far: one camera-facing dot per asteroid (shaders/belt_glint.gdshader).
## - far: a dust disc (shaders/cluster_dust.gdshader).
##
## The clump is thick: rock heights are gaussian around the centre (sigma
## [constant HEIGHT_SIGMA] of [member ClusterDef.vertical_spread], thinner
## toward the rim), so ships cross it in a lane over or under
## ([method lane_altitude]).
##
## Depletion: it holds [member loads_left] loads ([method ClusterDef.get_reserve]).
## Each drilled load takes one ([method take_load]); the rocks thin out in the
## shaders as it empties (asteroids whose seed is under [member thin_level]
## shrink away and are skipped by the queries). The last load emits
## [signal depleted]; the cluster then fades out over [constant FADE_TIME]
## sim seconds and emits [signal faded] (SolarSystem removes it).

signal depleted(belt: AsteroidCluster)
signal faded(belt: AsteroidCluster)

const OreType := AsteroidBelt.OreType
const GLINT_SHADER: Shader = preload("res://shaders/belt_glint.gdshader")
const DUST_SHADER: Shader = preload("res://shaders/cluster_dust.gdshader")
## Gap between the highest (lowest) rock and a ship's centre in a lane, metres.
const LANE_MARGIN := 15.0
## Rock height spread: gaussian sigma as a share of the vertical spread.
const HEIGHT_SIGMA := 0.38
## Share of the far dust light in each of the sheets above and below the middle.
const DUST_SIDE_SHARE := 0.22
## Grid chunk edge, metres.
const CHUNK_SIZE := 600.0
## Thinning share reached just before the last load (the rest goes in the fade).
const THIN_MAX := 0.8
## Sim seconds a mined-out cluster takes to fade away.
const FADE_TIME := 12.0
## A picked rock's seed sits this far above the thinning level, so it stays
## visible for the next few loads.
const PICK_MARGIN := 0.08
## Hostile bases within this flat distance of the cluster's edge add their
## danger bonus, metres.
const DEN_REACH := 6000.0

## Camera distance where detailed asteroids start / finish shrinking away.
@export var detail_fade_start: float = 2300.0
@export var detail_fade_end: float = 3300.0
@export var size_bias: float = 2.8

var def: ClusterDef
var richness: float:
	get: return def.richness if def else 0.0
## Live danger 1..5: the base rating plus what living hostile bases nearby add.
var danger: int:
	get: return _live_danger()
var ore_type: AsteroidBelt.OreType:
	get: return def.ore_type if def else OreType.ROCK
## Loads still in the rock.
var loads_left: int = 0
## Loads it held when it was found.
var reserve: int = 0
## 0..1+: share of the rocks thinned out (shaders and queries).
var thin_level: float = 0.0
## Mined out: no new work, fading away.
var is_depleted: bool = false
var _fade_left: float = 0.0
var _last_t: float = NAN

# Per asteroid, sorted by chunk. Positions are cluster-local.
var _positions := PackedVector3Array()
var _radii := PackedFloat32Array()
var _ores := PackedByteArray()
var _variants := PackedByteArray()
## Thinning seed per asteroid (the shaders' INSTANCE_CUSTOM.w).
var _keys := PackedFloat32Array()
var _chunk_offsets := PackedInt32Array()
var _grid := 1
var _chunk_count := 0
var _variant_names: Array[String] = []
var _dust_mats: Array[ShaderMaterial] = []
var _glint_mat: ShaderMaterial
var _mesh_nodes: Array[MultiMeshInstance3D] = []
## Highest rock top above (or bottom below) the centre, metres (from the data).
var _layer_height := 0.0


func build(cluster_def: ClusterDef, star_position: Vector3, star_color: Color) -> void:
	def = cluster_def
	name = StringName(def.name.validate_node_name())
	add_to_group("asteroid_belts")
	reserve = def.get_reserve()
	loads_left = reserve
	setup_orbit(def.orbit_radius, def.get_orbit_period(), def.start_angle_deg,
			Orbiter.inclined_basis(def.inclination_deg, def.ascending_node_deg))
	_variant_names = _variant_list()
	var t0 := Time.get_ticks_msec()
	var data := _generate()
	_build_chunks(data)
	_build_glints(star_position, star_color)
	_build_dust(star_position, star_color)
	print("AsteroidCluster %s: %d asteroids, %d chunks, built in %d ms" % [def.name, _positions.size(), _chunk_count, Time.get_ticks_msec() - t0])


func update_sim(sim_time: float) -> void:
	super.update_sim(sim_time)
	if is_depleted and _fade_left > 0.0:
		var dt := 0.0 if is_nan(_last_t) else clampf(sim_time - _last_t, 0.0, 1.0)
		_fade_left = maxf(_fade_left - dt, 0.0)
		_set_thin(lerpf(1.05, THIN_MAX, _fade_left / FADE_TIME))
		if _fade_left <= 0.0:
			faded.emit(self)
	_last_t = sim_time


# --- Depletion ----------------------------------------------------------------

## True while miners may start on it: not mined out and a load left beyond
## the rocks already being drilled.
func has_ore_for_new_trip() -> bool:
	return not is_depleted and loads_left - MinerShip.claims_on(self) > 0


## One drilled load leaves the rock. The last one starts the fade.
func take_load() -> void:
	if is_depleted:
		return
	loads_left = maxi(loads_left - 1, 0)
	_apply_thin_from_loads()
	if loads_left <= 0:
		_start_fade()


## Restores the depletion state (save / load).
func set_loads_left(left: int, total: int) -> void:
	reserve = maxi(total, 1)
	loads_left = clampi(left, 0, reserve)
	_apply_thin_from_loads()
	if loads_left <= 0:
		_start_fade()


func fill_fraction() -> float:
	return float(loads_left) / float(maxi(reserve, 1))


func _apply_thin_from_loads() -> void:
	_set_thin((1.0 - fill_fraction()) * THIN_MAX)


func _start_fade() -> void:
	if is_depleted:
		return
	is_depleted = true
	_fade_left = FADE_TIME
	depleted.emit(self)


func _set_thin(level: float) -> void:
	thin_level = level
	for mmi in _mesh_nodes:
		mmi.set_instance_shader_parameter("thin_level", level)
	if _glint_mat:
		_glint_mat.set_shader_parameter("thin_level", level)
	var amount := clampf(1.0 - level, 0.0, 1.0)
	for m in _dust_mats:
		m.set_shader_parameter("amount", amount)


func _is_shown(i: int) -> bool:
	return thin_level <= 0.0 or _keys[i] >= thin_level


# --- Danger -------------------------------------------------------------------

func _live_danger() -> int:
	if def == null:
		return 1
	var d := def.danger
	var sys := get_parent() as SolarSystem
	if sys == null:
		return clampi(d, 1, 5)
	var bonus := 0
	var c := global_position
	for den in sys.dens:
		if not is_instance_valid(den) or not den.is_alive() or den.def == null:
			continue
		if SpaceNav.flat_distance(c, den.global_position) - def.radius() < DEN_REACH:
			bonus += den.def.danger_bonus
	return clampi(d + bonus, 1, 5)


## Living hostile bases whose danger reaches this cluster.
func nearby_dens() -> Array[ScavengerDen]:
	var out: Array[ScavengerDen] = []
	var sys := get_parent() as SolarSystem
	if sys == null:
		return out
	for den in sys.dens:
		if is_instance_valid(den) and SpaceNav.flat_distance(global_position, den.global_position) - def.radius() < DEN_REACH:
			out.append(den)
	return out


# --- Queries ------------------------------------------------------------------

func get_asteroid_count() -> int:
	return _positions.size()


## {index, position (world), local_position, radius, ore_type
## (AsteroidBelt.OreType), variant (mesh name)}. Empty if out of range.
func get_asteroid(i: int) -> Dictionary:
	if i < 0 or i >= _positions.size():
		return {}
	return {
		"index": i,
		"position": global_transform * _positions[i],
		"local_position": _positions[i],
		"radius": _radii[i],
		"ore_type": _ores[i],
		"variant": _variant_names[_variants[i]],
	}


func get_asteroid_position(i: int) -> Vector3:
	return global_transform * _positions[i]


## Index of the nearest ore-bearing asteroid to [param world_pos] that is
## still shown (and stays so for a few loads), or -1. [param ore] = -1
## matches any ore (not plain rock).
func find_nearest_ore(world_pos: Vector3, ore: int = -1) -> int:
	var lp := global_transform.affine_inverse() * world_pos
	var best := -1
	var best_d2 := INF
	var margin := PICK_MARGIN if thin_level > 0.0 else 0.0
	for i in _positions.size():
		var o := _ores[i]
		if o == OreType.ROCK or (ore >= 0 and o != ore):
			continue
		if margin > 0.0 and _keys[i] < thin_level + margin:
			continue
		var d2 := lp.distance_squared_to(_positions[i])
		if d2 < best_d2:
			best_d2 = d2
			best = i
	return best


## Radius on the plane that holds every asteroid centre, metres.
func rock_half_width() -> float:
	return def.radius()


## Height of the rock layer above (and below) the centre: the highest rock
## centre plus the largest radius, metres.
func rock_layer_height() -> float:
	return _layer_height if _layer_height > 0.0 else def.vertical_spread + def.max_scale


## Height (unsigned, from the system plane) ships fly at over or under the
## cluster: clears the rocks on both sides, wherever the inclined orbit has
## lifted or sunk the clump.
func lane_altitude() -> float:
	return absf(global_position.y) + rock_layer_height() + LANE_MARGIN


## Flat distance from [param world_pos] to the cluster's rim (0 inside).
func distance_to(world_pos: Vector3) -> float:
	return maxf(SpaceNav.flat_distance(world_pos, global_position) - rock_half_width(), 0.0)


## Point on the cluster's rim (at the centre's height) facing [param world_pos],
## the centre when inside.
func nearest_point(world_pos: Vector3) -> Vector3:
	var c := global_position
	var d := Vector3(world_pos.x - c.x, 0.0, world_pos.z - c.z)
	var r := rock_half_width()
	if d.length() <= r:
		return Vector3(world_pos.x, c.y, world_pos.z)
	return c + d.normalized() * r


func get_asteroid_local(i: int) -> Vector3:
	return _positions[i]


func get_asteroid_radius(i: int) -> float:
	return _radii[i]


## Asteroids whose surface comes within [param reach] of cluster-local point
## [param lp]. Scans the point's chunk and its neighbours, so keep
## [param reach] under [constant CHUNK_SIZE].
func asteroids_near_local(lp: Vector3, reach: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	if _chunk_count == 0:
		return out
	var cell := _cell_of(lp)
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var gx: int = cell.x + dx
			var gz: int = cell.y + dz
			if gx < 0 or gz < 0 or gx >= _grid or gz >= _grid:
				continue
			var ci := gx + gz * _grid
			for i in range(_chunk_offsets[ci], _chunk_offsets[ci + 1]):
				if not _is_shown(i):
					continue
				var r := reach + _radii[i]
				if lp.distance_squared_to(_positions[i]) <= r * r:
					out.append(i)
	return out


## True when the point lies inside the cluster's rock volume.
func contains_point(world_pos: Vector3) -> bool:
	if def == null:
		return false
	var lp := world_pos - global_position
	return SpaceNav.flat_length(lp) <= rock_half_width() and absf(lp.y) <= rock_layer_height()


func get_ore_fraction() -> float:
	if def == null or def.ore_type == OreType.ROCK:
		return 0.0
	return lerpf(0.04, 0.55, def.richness)


# --- Build --------------------------------------------------------------------

func _variant_list() -> Array[String]:
	var names: Array[String] = []
	names.append_array(AsteroidBelt.ROCK_VARIANTS)
	for ore in [def.ore_type, def.secondary_ore]:
		if ore != OreType.ROCK and AsteroidBelt.ORE_VARIANTS.has(ore):
			for v: String in AsteroidBelt.ORE_VARIANTS[ore]:
				if not names.has(v):
					names.append(v)
	return names


func _cell_of(lp: Vector3) -> Vector2i:
	var half := float(_grid) * CHUNK_SIZE * 0.5
	return Vector2i(clampi(int((lp.x + half) / CHUNK_SIZE), 0, _grid - 1), clampi(int((lp.z + half) / CHUNK_SIZE), 0, _grid - 1))


func _chunk_center(ci: int) -> Vector3:
	var half := float(_grid) * CHUNK_SIZE * 0.5
	return Vector3((float(ci % _grid) + 0.5) * CHUNK_SIZE - half, 0.0, (float(ci / _grid) + 0.5) * CHUNK_SIZE - half)


## Generates all asteroids in a few overlapping gaussian sub-clumps plus a
## thin halo, then stores them sorted by chunk. Returns the per-asteroid
## rotation/custom data needed for the meshes, in sorted order.
func _generate() -> Dictionary:
	var n := maxi(def.get_count(), 0)
	var big_r := def.radius()
	_grid = maxi(1, ceili(def.size / CHUNK_SIZE))
	_chunk_count = _grid * _grid
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(def.seed)

	# Sub-clumps: centre (x, z), sigma, cumulative weight.
	var clumps: Array[Vector4] = []
	var k := 3 + rng.randi() % 4
	var total := 0.0
	for j in k:
		var a := rng.randf() * TAU
		var d := big_r * 0.5 * sqrt(rng.randf())
		var w := rng.randf_range(0.6, 1.4)
		total += w
		clumps.append(Vector4(cos(a) * d, sin(a) * d, big_r * rng.randf_range(0.2, 0.36), total))
	var halo_share := 0.22

	var ore_fraction := get_ore_fraction()
	var lo := minf(def.min_scale, def.max_scale)
	var hi := maxf(def.min_scale, def.max_scale)
	var rock_count := AsteroidBelt.ROCK_VARIANTS.size()
	var vs := def.vertical_spread

	var pos := PackedVector3Array()
	pos.resize(n)
	var rad := PackedFloat32Array()
	rad.resize(n)
	var ores := PackedByteArray()
	ores.resize(n)
	var vars := PackedByteArray()
	vars.resize(n)
	var quats := PackedFloat32Array()
	quats.resize(n * 4)
	var customs := PackedFloat32Array()
	customs.resize(n * 4)
	var chunk := PackedInt32Array()
	chunk.resize(n)
	var counts := PackedInt32Array()
	counts.resize(_chunk_count)

	for i in n:
		var p := Vector2.ZERO
		for _try in 6:
			if rng.randf() < halo_share:
				p = Vector2(rng.randfn(0.0, big_r * 0.45), rng.randfn(0.0, big_r * 0.45))
			else:
				var pick := rng.randf() * total
				var c := clumps[0]
				for cl in clumps:
					c = cl
					if pick <= cl.w:
						break
				p = Vector2(c.x + rng.randfn(0.0, c.z), c.y + rng.randfn(0.0, c.z))
			if p.length() <= big_r:
				break
		if p.length() > big_r:
			p = p.normalized() * big_r * rng.randf_range(0.6, 1.0)
		# Thinner toward the rim: a lens.
		var lens := 0.45 + 0.55 * sqrt(maxf(1.0 - pow(p.length() / big_r, 2.0), 0.0))
		var y := rng.randfn(0.0, vs * HEIGHT_SIGMA * lens)
		for _try in 3:
			if absf(y) <= vs:
				break
			y = rng.randfn(0.0, vs * HEIGHT_SIGMA * lens)
		y = clampf(y, -vs, vs)
		pos[i] = Vector3(p.x, y, p.y)
		var s := lerpf(lo, hi, pow(rng.randf(), size_bias))
		rad[i] = s
		_layer_height = maxf(_layer_height, absf(y) + s)
		var ore := OreType.ROCK
		var v := rng.randi() % rock_count
		if rng.randf() < ore_fraction:
			ore = def.ore_type
			if def.secondary_ore != OreType.ROCK and rng.randf() < def.secondary_share:
				ore = def.secondary_ore
			var list: Array = AsteroidBelt.ORE_VARIANTS[ore]
			v = _variant_names.find(list[rng.randi() % list.size()])
		ores[i] = ore
		vars[i] = v
		var q := Quaternion(_random_axis(rng), rng.randf() * TAU)
		quats[i * 4] = q.x
		quats[i * 4 + 1] = q.y
		quats[i * 4 + 2] = q.z
		quats[i * 4 + 3] = q.w
		var spin := 0.25 * rng.randf_range(0.25, 1.0) * clampf(4.0 / s, 0.12, 1.0)
		if rng.randf() < 0.5:
			spin = -spin
		customs[i * 4] = rng.randf()
		customs[i * 4 + 1] = rng.randf()
		customs[i * 4 + 2] = spin
		customs[i * 4 + 3] = rng.randf()
		var cell := _cell_of(pos[i])
		var ci := cell.x + cell.y * _grid
		chunk[i] = ci
		counts[ci] += 1

	# Counting sort by chunk.
	_chunk_offsets.resize(_chunk_count + 1)
	_chunk_offsets[0] = 0
	for c in _chunk_count:
		_chunk_offsets[c + 1] = _chunk_offsets[c] + counts[c]
	var cursor := _chunk_offsets.duplicate()
	var order := PackedInt32Array()
	order.resize(n)
	for i in n:
		var c := chunk[i]
		order[cursor[c]] = i
		cursor[c] += 1

	_positions.resize(n)
	_radii.resize(n)
	_ores.resize(n)
	_variants.resize(n)
	_keys.resize(n)
	var s_quats := PackedFloat32Array()
	s_quats.resize(n * 4)
	var s_customs := PackedFloat32Array()
	s_customs.resize(n * 4)
	for j in n:
		var i := order[j]
		_positions[j] = pos[i]
		_radii[j] = rad[i]
		_ores[j] = ores[i]
		_variants[j] = vars[i]
		_keys[j] = customs[i * 4 + 3]
		for kk in 4:
			s_quats[j * 4 + kk] = quats[i * 4 + kk]
			s_customs[j * 4 + kk] = customs[i * 4 + kk]
	return {"quats": s_quats, "customs": s_customs}


func _build_chunks(data: Dictionary) -> void:
	var quats: PackedFloat32Array = data["quats"]
	var customs: PackedFloat32Array = data["customs"]
	var v_count := _variant_names.size()
	var meshes: Array[Mesh] = []
	for v_name in _variant_names:
		meshes.append(AsteroidBelt.get_variant_mesh(v_name))
	var chunk_radius := sqrt(2.0 * pow(CHUNK_SIZE * 0.5, 2.0) + pow(def.vertical_spread, 2.0))
	var glow := def.glow

	for c in _chunk_count:
		var a0 := _chunk_offsets[c]
		var a1 := _chunk_offsets[c + 1]
		if a1 <= a0:
			continue
		var center := _chunk_center(c)
		var chunk_node := Node3D.new()
		chunk_node.name = "Chunk%03d" % c
		chunk_node.position = center
		add_child(chunk_node)
		# Group this chunk's asteroids by variant.
		var per_variant: Array[PackedInt32Array] = []
		per_variant.resize(v_count)
		for i in range(a0, a1):
			var lst := per_variant[_variants[i]]
			lst.append(i)
			per_variant[_variants[i]] = lst
		for v in v_count:
			var ids := per_variant[v]
			if ids.is_empty():
				continue
			var buf := PackedFloat32Array()
			buf.resize(ids.size() * 16)
			var aabb := AABB(_positions[ids[0]] - center, Vector3.ZERO)
			var max_s := 0.0
			for j in ids.size():
				var i := ids[j]
				var q := Quaternion(quats[i * 4], quats[i * 4 + 1], quats[i * 4 + 2], quats[i * 4 + 3])
				var b := Basis(q).scaled(Vector3.ONE * _radii[i])
				var o := _positions[i] - center
				var kk := j * 16
				buf[kk] = b.x.x
				buf[kk + 1] = b.y.x
				buf[kk + 2] = b.z.x
				buf[kk + 3] = o.x
				buf[kk + 4] = b.x.y
				buf[kk + 5] = b.y.y
				buf[kk + 6] = b.z.y
				buf[kk + 7] = o.y
				buf[kk + 8] = b.x.z
				buf[kk + 9] = b.y.z
				buf[kk + 10] = b.z.z
				buf[kk + 11] = o.z
				buf[kk + 12] = customs[i * 4]
				buf[kk + 13] = customs[i * 4 + 1]
				buf[kk + 14] = customs[i * 4 + 2]
				buf[kk + 15] = customs[i * 4 + 3]
				aabb = aabb.expand(o)
				max_s = maxf(max_s, _radii[i])
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = meshes[v]
			mm.instance_count = ids.size()
			mm.buffer = buf
			var mmi := MultiMeshInstance3D.new()
			mmi.name = _variant_names[v]
			mmi.multimesh = mm
			mmi.custom_aabb = aabb.grow(max_s * 2.0)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = detail_fade_end + chunk_radius
			mmi.visibility_range_end_margin = 0.0
			mmi.set_instance_shader_parameter("emission_boost", glow)
			mmi.set_instance_shader_parameter("lod_fade_start", detail_fade_start)
			mmi.set_instance_shader_parameter("lod_fade_end", detail_fade_end)
			chunk_node.add_child(mmi)
			_mesh_nodes.append(mmi)


func _build_glints(star_position: Vector3, star_color: Color) -> void:
	var n := _positions.size()
	if n == 0:
		return
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_glint_mat = ShaderMaterial.new()
	_glint_mat.shader = GLINT_SHADER
	_glint_mat.set_shader_parameter("star_position", star_position)
	_glint_mat.set_shader_parameter("star_color", Color(star_color, 1.0).lerp(Color.WHITE, 0.5))
	_glint_mat.set_shader_parameter("near_start", detail_fade_start + 200.0)
	_glint_mat.set_shader_parameter("near_end", detail_fade_end)
	_glint_mat.set_shader_parameter("crystal_glow", def.glow * 0.5)
	quad.material = _glint_mat
	var buf := PackedFloat32Array()
	buf.resize(n * 16)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(def.seed + 5)
	for i in n:
		var o := _positions[i]
		var k := i * 16
		buf[k] = 1.0
		buf[k + 3] = o.x
		buf[k + 5] = 1.0
		buf[k + 7] = o.y
		buf[k + 10] = 1.0
		buf[k + 11] = o.z
		buf[k + 12] = _radii[i]
		buf[k + 13] = rng.randf_range(0.55, 1.0)
		buf[k + 14] = float(_ores[i])
		buf[k + 15] = _keys[i]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = n
	mm.buffer = buf
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Glints"
	mmi.multimesh = mm
	var r := def.radius() + 50.0
	var h := rock_layer_height() + 50.0
	mmi.custom_aabb = AABB(Vector3(-r, -h, -r), Vector3(r * 2.0, h * 2.0, r * 2.0))
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _build_dust(star_position: Vector3, star_color: Color) -> void:
	var big_r := def.radius()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * big_r * 3.2
	var glow_strength := 0.06 * def.glow if def.ore_type == OreType.CRYSTAL else 0.0
	# Midplane sheet keeps most of the light; thin sheets above and below
	# give the clump its thickness from afar.
	var sheets: Array[Vector2] = [Vector2(0.0, 1.0 - 2.0 * DUST_SIDE_SHARE), Vector2(-1.0, DUST_SIDE_SHARE), Vector2(1.0, DUST_SIDE_SHARE)]
	for sh in sheets:
		var mi := MeshInstance3D.new()
		mi.name = "Dust" if sh.x == 0.0 else ("DustUp" if sh.x > 0.0 else "DustDown")
		mi.mesh = plane
		mi.position.y = sh.x * def.vertical_spread * HEIGHT_SIGMA * 1.2
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := ShaderMaterial.new()
		m.shader = DUST_SHADER
		m.set_shader_parameter("star_position", star_position)
		m.set_shader_parameter("star_color", Color(star_color, 1.0).lerp(Color.WHITE, 0.5))
		m.set_shader_parameter("dust_color", Color(def.dust_color, 1.0))
		m.set_shader_parameter("cluster_radius", big_r)
		m.set_shader_parameter("seed", float(def.seed % 97) + 13.0 * sh.x)
		m.set_shader_parameter("intensity", 0.22 * def.dust_color.a * sh.y)
		m.set_shader_parameter("glow_strength", glow_strength)
		m.set_shader_parameter("near_fade_start", detail_fade_start * 0.6)
		m.set_shader_parameter("near_fade_end", detail_fade_end * 2.2)
		mi.material_override = m
		add_child(mi)
		_dust_mats.append(m)


static func _random_axis(rng: RandomNumberGenerator) -> Vector3:
	var z := rng.randf_range(-1.0, 1.0)
	var a := rng.randf() * TAU
	var rxy := sqrt(1.0 - z * z)
	return Vector3(rxy * cos(a), z, rxy * sin(a))

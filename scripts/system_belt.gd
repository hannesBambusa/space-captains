class_name SystemBelt
extends Node3D
## A full asteroid ring around the star at system scale, built from a BeltDef.
##
## Three layers, so it reads at every zoom:
## - near: detailed asteroid meshes in angular chunks (one MultiMeshInstance3D
##   per chunk and mesh variant) with visibility ranges; each asteroid shrinks
##   away in the vertex shader before its chunk is culled. No shadows.
## - mid/far: one camera-facing dot per asteroid (shaders/belt_glint.gdshader)
##   that fades in where the meshes fade out.
## - far: a dust band annulus (shaders/belt_dust.gdshader).
##
## The band is thick: rock heights are gaussian around y = 0 (denser near the
## midplane, sigma [constant HEIGHT_SIGMA] of [member BeltDef.vertical_spread],
## resampled past the spread), so lanes over and under it are high
## ([method lane_altitude]).
##
## The whole ring turns slowly with the sim clock. Per-asteroid data is kept
## (sorted by chunk) for gameplay queries; world positions include the rotation.

const OreType := AsteroidBelt.OreType
const GLINT_SHADER: Shader = preload("res://shaders/belt_glint.gdshader")
const DUST_SHADER: Shader = preload("res://shaders/belt_dust.gdshader")
const MAX_REJECTION_TRIES := 10
## Gap between the highest (lowest) rock and a ship's centre in a belt lane, metres.
const LANE_MARGIN := 15.0
## Radial reach of asteroid centres as a share of the width (the centre
## line wobbles by 0.18 width on top of the clamped half width).
const ROCK_REACH := 0.7
## Rock height spread: gaussian sigma as a share of the vertical spread.
const HEIGHT_SIGMA := 0.38
## Share of the far dust light in each of the sheets above and below the midplane.
const DUST_SIDE_SHARE := 0.22

## Target arc length of one chunk, metres.
@export var chunk_arc: float = 1400.0
## Camera distance where detailed asteroids start / finish shrinking away.
@export var detail_fade_start: float = 2300.0
@export var detail_fade_end: float = 3300.0
@export var size_bias: float = 2.8
@export var clumping: float = 0.6

var def: BeltDef
var richness: float:
	get: return def.richness if def else 0.0
## Live danger: the authored rating minus what destroyed dens took off it.
var danger: int:
	get: return maxi(def.danger - danger_reduction, 1) if def else 1
## Danger levels removed by destroyed Scavenger Dens on this belt.
var danger_reduction: int = 0
var ore_type: AsteroidBelt.OreType:
	get: return def.ore_type if def else OreType.ROCK

# Per asteroid, sorted by chunk. Positions are belt-local (before rotation).
var _positions := PackedVector3Array()
var _radii := PackedFloat32Array()
var _ores := PackedByteArray()
var _variants := PackedByteArray()
var _chunk_offsets := PackedInt32Array()
var _chunk_count := 0
var _variant_names: Array[String] = []
var _dust_mat: ShaderMaterial
var _glint_mat: ShaderMaterial
## Highest rock top above (or bottom below) the plane, metres (from the data).
var _layer_height := 0.0


func build(belt_def: BeltDef, star_position: Vector3, star_color: Color) -> void:
	def = belt_def
	name = StringName(def.name.validate_node_name())
	add_to_group("asteroid_belts")
	_variant_names = _variant_list()
	var t0 := Time.get_ticks_msec()
	var data := _generate()
	_build_chunks(data)
	_build_glints(star_position, star_color)
	_build_dust(star_position, star_color)
	print("SystemBelt %s: %d asteroids, %d chunks, built in %d ms" % [def.name, _positions.size(), _chunk_count, Time.get_ticks_msec() - t0])


func update_sim(sim_time: float) -> void:
	if def == null or def.rotation_period == 0.0:
		return
	rotation.y = -TAU * fposmod(sim_time / def.rotation_period, 1.0)


# --- Queries ------------------------------------------------------------------

func get_asteroid_count() -> int:
	return _positions.size()


## {index, position (world, includes ring rotation), local_position, radius,
## ore_type (AsteroidBelt.OreType), variant (mesh name)}. Empty if out of range.
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


## Index of the nearest ore-bearing asteroid to [param world_pos], or -1.
## [param ore] = -1 matches any ore (not plain rock).
func find_nearest_ore(world_pos: Vector3, ore: int = -1) -> int:
	if _chunk_count == 0:
		return -1
	var lp := global_transform.affine_inverse() * world_pos
	var c0 := _chunk_of(atan2(lp.z, lp.x))
	var inner_arc := TAU / float(_chunk_count) * maxf(def.orbit_radius - def.width * 0.5, 1.0)
	var best := -1
	var best_d2 := INF
	for k in _chunk_count / 2 + 1:
		if best >= 0:
			var min_d := (float(k) - 1.0) * inner_arc
			if min_d > 0.0 and min_d * min_d > best_d2:
				break
		for c in ([c0] if k == 0 else [c0 - k, c0 + k]):
			var ci := posmod(c, _chunk_count)
			for i in range(_chunk_offsets[ci], _chunk_offsets[ci + 1]):
				var o := _ores[i]
				if o == OreType.ROCK or (ore >= 0 and o != ore):
					continue
				var d2 := lp.distance_squared_to(_positions[i])
				if d2 < best_d2:
					best_d2 = d2
					best = i
	return best


## Half the radial width that holds every asteroid centre, metres.
func rock_half_width() -> float:
	return def.width * ROCK_REACH


## Height of the rock layer above (and below) the plane: the highest rock
## centre plus the largest radius, metres.
func rock_layer_height() -> float:
	return _layer_height if _layer_height > 0.0 else def.vertical_spread + def.max_scale


## Height ships fly at over (or under) the belt, metres.
func lane_altitude() -> float:
	return rock_layer_height() + LANE_MARGIN


## Belt-local position and radius of asteroid [param i].
func get_asteroid_local(i: int) -> Vector3:
	return _positions[i]


func get_asteroid_radius(i: int) -> float:
	return _radii[i]


## Asteroids whose surface comes within [param reach] of belt-local point
## [param lp]. Scans only the point's chunk and its two neighbours, so keep
## [param reach] well under [member chunk_arc].
func asteroids_near_local(lp: Vector3, reach: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	if _chunk_count == 0:
		return out
	var c0 := _chunk_of(atan2(lp.z, lp.x))
	for k in [-1, 0, 1]:
		var ci := posmod(c0 + k, _chunk_count)
		for i in range(_chunk_offsets[ci], _chunk_offsets[ci + 1]):
			var r := reach + _radii[i]
			if lp.distance_squared_to(_positions[i]) <= r * r:
				out.append(i)
	return out


## True when the point lies inside the belt's band (radially and vertically).
func contains_point(world_pos: Vector3) -> bool:
	if def == null:
		return false
	var lp := global_transform.affine_inverse() * world_pos
	var r := Vector2(lp.x, lp.z).length()
	return absf(r - def.orbit_radius) <= def.width * 0.5 and absf(lp.y) <= rock_layer_height()


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


func _chunk_of(angle: float) -> int:
	var f := fposmod(angle, TAU) / TAU
	return mini(int(f * _chunk_count), _chunk_count - 1)


## Generates all asteroids, then stores them sorted by chunk. Returns the
## per-asteroid rotation/custom data needed for the meshes, in sorted order.
func _generate() -> Dictionary:
	var n := maxi(def.count, 0)
	_chunk_count = maxi(8, int(round(TAU * def.orbit_radius / chunk_arc)))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(def.seed)
	var clump := FastNoiseLite.new()
	clump.seed = def.seed
	clump.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	clump.frequency = 1.0
	var wobble := FastNoiseLite.new()
	wobble.seed = def.seed + 77
	wobble.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	wobble.frequency = 1.0

	var ore_fraction := get_ore_fraction()
	var lo := minf(def.min_scale, def.max_scale)
	var hi := maxf(def.min_scale, def.max_scale)
	var rock_count := AsteroidBelt.ROCK_VARIANTS.size()
	var circumference := TAU * def.orbit_radius
	var sigma := 0.24 * def.width

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
		var angle := 0.0
		for _try in MAX_REJECTION_TRIES:
			angle = rng.randf() * TAU
			var along := angle * def.orbit_radius
			var density := clump.get_noise_1d(along / 1600.0) * 0.5 + 0.5
			density *= 0.7 + 0.3 * (clump.get_noise_1d(along / 300.0 + 91.0) * 0.5 + 0.5)
			if rng.randf() < lerpf(1.0, density * density * 1.8, clumping):
				break
		var center_r := def.orbit_radius + wobble.get_noise_1d(angle * circumference / TAU / 6000.0) * def.width * 0.18
		var r := center_r + clampf(rng.randfn(0.0, sigma), -def.width * 0.5, def.width * 0.5)
		var y := rng.randfn(0.0, def.vertical_spread * HEIGHT_SIGMA)
		for _try in 3:
			if absf(y) <= def.vertical_spread:
				break
			y = rng.randfn(0.0, def.vertical_spread * HEIGHT_SIGMA)
		y = clampf(y, -def.vertical_spread, def.vertical_spread)
		pos[i] = Vector3(cos(angle) * r, y, sin(angle) * r)
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
		var c := _chunk_of(angle)
		chunk[i] = c
		counts[c] += 1

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
		for k in 4:
			s_quats[j * 4 + k] = quats[i * 4 + k]
			s_customs[j * 4 + k] = customs[i * 4 + k]
	return {"quats": s_quats, "customs": s_customs}


func _build_chunks(data: Dictionary) -> void:
	var quats: PackedFloat32Array = data["quats"]
	var customs: PackedFloat32Array = data["customs"]
	var v_count := _variant_names.size()
	var meshes: Array[Mesh] = []
	for v_name in _variant_names:
		meshes.append(AsteroidBelt.get_variant_mesh(v_name))
	var chunk_radius := sqrt(pow(chunk_arc * 0.5, 2.0) + pow(def.width * 0.6, 2.0) + pow(def.vertical_spread, 2.0))
	var glow := def.glow

	for c in _chunk_count:
		var a0 := _chunk_offsets[c]
		var a1 := _chunk_offsets[c + 1]
		if a1 <= a0:
			continue
		var mid_angle := (float(c) + 0.5) / float(_chunk_count) * TAU
		var center := Vector3(cos(mid_angle), 0.0, sin(mid_angle)) * def.orbit_radius
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
				var k := j * 16
				buf[k] = b.x.x
				buf[k + 1] = b.y.x
				buf[k + 2] = b.z.x
				buf[k + 3] = o.x
				buf[k + 4] = b.x.y
				buf[k + 5] = b.y.y
				buf[k + 6] = b.z.y
				buf[k + 7] = o.y
				buf[k + 8] = b.x.z
				buf[k + 9] = b.y.z
				buf[k + 10] = b.z.z
				buf[k + 11] = o.z
				buf[k + 12] = customs[i * 4]
				buf[k + 13] = customs[i * 4 + 1]
				buf[k + 14] = customs[i * 4 + 2]
				buf[k + 15] = customs[i * 4 + 3]
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
		buf[k + 15] = rng.randf()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = n
	mm.buffer = buf
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Glints"
	mmi.multimesh = mm
	var r := def.orbit_radius + def.width
	var h := rock_layer_height() + 50.0
	mmi.custom_aabb = AABB(Vector3(-r, -h, -r), Vector3(r * 2.0, h * 2.0, r * 2.0))
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _build_dust(star_position: Vector3, star_color: Color) -> void:
	var hw := def.width * 0.5
	var mi := MeshInstance3D.new()
	mi.name = "DustBand"
	mi.mesh = MeshUtil.make_annulus(def.orbit_radius - hw * 1.7, def.orbit_radius + hw * 1.7, 720, 4)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dust_mat = ShaderMaterial.new()
	_dust_mat.shader = DUST_SHADER
	_dust_mat.set_shader_parameter("star_position", star_position)
	_dust_mat.set_shader_parameter("star_color", Color(star_color, 1.0).lerp(Color.WHITE, 0.5))
	_dust_mat.set_shader_parameter("dust_color", Color(def.dust_color, 1.0))
	_dust_mat.set_shader_parameter("ring_radius", def.orbit_radius)
	_dust_mat.set_shader_parameter("half_width", hw)
	_dust_mat.set_shader_parameter("seed", float(def.seed % 97))
	_dust_mat.set_shader_parameter("intensity", 0.16 * def.dust_color.a)
	var glow_strength := 0.0
	if def.ore_type == OreType.CRYSTAL:
		glow_strength = 0.06 * def.glow
	_dust_mat.set_shader_parameter("glow_strength", glow_strength)
	_dust_mat.set_shader_parameter("near_fade_start", detail_fade_start * 0.6)
	_dust_mat.set_shader_parameter("near_fade_end", detail_fade_end * 2.2)
	mi.material_override = _dust_mat
	add_child(mi)
	# Thin dust sheets above and below the midplane give the band its
	# thickness from afar (the midplane sheet keeps most of the light).
	_dust_mat.set_shader_parameter("intensity", 0.16 * def.dust_color.a * (1.0 - 2.0 * DUST_SIDE_SHARE))
	for sgn: float in [-1.0, 1.0]:
		var side := MeshInstance3D.new()
		side.name = "DustSheet%s" % ("Up" if sgn > 0.0 else "Down")
		side.mesh = mi.mesh
		side.position.y = sgn * def.vertical_spread * HEIGHT_SIGMA * 1.2
		side.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := _dust_mat.duplicate() as ShaderMaterial
		m.set_shader_parameter("intensity", 0.16 * def.dust_color.a * DUST_SIDE_SHARE)
		m.set_shader_parameter("seed", float(def.seed % 97) + 13.0 * sgn)
		side.material_override = m
		add_child(side)


static func _random_axis(rng: RandomNumberGenerator) -> Vector3:
	var z := rng.randf_range(-1.0, 1.0)
	var a := rng.randf() * TAU
	var rxy := sqrt(1.0 - z * z)
	return Vector3(rxy * cos(a), z, rxy * sin(a))

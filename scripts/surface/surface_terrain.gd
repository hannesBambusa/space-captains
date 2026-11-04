class_name SurfaceTerrain
extends RefCounted
## The ground of one landing zone (planet outposts plan): a seeded
## heightfield by planet type (PlanetDef.Type), flattened round the landing
## pad so the base stands level, rising toward the edges into ridges or
## dunes. [method height] is the one source for the mesh, the vehicles'
## hover height and picking. The mesh ([method build_mesh]) covers the zone
## plus a margin of scenery; shaders/terrain_surface.gdshader colours it.

const MARGIN := 1600.0
const CELLS := 180
## The flat base round the pad: fully flat inside, natural ground outside.
const FLAT_IN := 380.0
const FLAT_OUT := 900.0
## Water or lava level (ocean and lava worlds), metres.
const LIQUID_LEVEL := -6.0

var type: int = 0
var _hills := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()
var _amp := 60.0
var _dune_dir := Vector2(1.0, 0.0)


func _init(seed_value: int, planet_type: int) -> void:
	type = planet_type
	_hills.seed = seed_value
	_hills.frequency = 0.0007
	_hills.fractal_octaves = 4
	_detail.seed = seed_value + 7
	_detail.frequency = 0.006
	_detail.fractal_octaves = 3
	_ridge.seed = seed_value + 13
	_ridge.noise_type = FastNoiseLite.TYPE_PERLIN
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.frequency = 0.0011
	_ridge.fractal_octaves = 4
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var a := rng.randf() * TAU
	_dune_dir = Vector2(cos(a), sin(a))
	match type:
		PlanetDef.Type.ROCKY:
			_amp = 140.0
		PlanetDef.Type.DESERT:
			_amp = 55.0
		PlanetDef.Type.ICE:
			_amp = 45.0
		PlanetDef.Type.OCEAN:
			_amp = 30.0
		PlanetDef.Type.LAVA:
			_amp = 80.0
		PlanetDef.Type.GAS_GIANT:
			_amp = 22.0


## Ground height at zone-local ([param x], [param z]), metres.
func height(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	var wild := smoothstep(FLAT_IN, FLAT_OUT, r)
	var h := 0.0
	match type:
		PlanetDef.Type.DESERT:
			var along := Vector2(x, z).dot(_dune_dir)
			h = (sin(along * 0.012 + _hills.get_noise_2d(x, z) * 4.0) * 0.5 + 0.5) * 0.6 + _hills.get_noise_2d(x, z) * 0.5
		PlanetDef.Type.ICE:
			h = _hills.get_noise_2d(x, z) * 0.6 + maxf(_ridge.get_noise_2d(x, z), 0.0) * 0.8
		PlanetDef.Type.LAVA:
			h = _hills.get_noise_2d(x, z) * 0.7 + _ridge.get_noise_2d(x, z) * 0.6
		PlanetDef.Type.OCEAN:
			h = _hills.get_noise_2d(x, z) * 0.9 + 0.15
		PlanetDef.Type.GAS_GIANT:
			# The cloud deck: long slow swells, no rim, no flat base.
			return (_hills.get_noise_2d(x * 0.6, z * 0.6) * 0.8 + sin(Vector2(x, z).dot(_dune_dir) * 0.004) * 0.3) * _amp
		_:
			h = _hills.get_noise_2d(x, z) * 0.6 + _ridge.get_noise_2d(x, z) * 0.9
	h = h * _amp + _detail.get_noise_2d(x, z) * _amp * 0.06
	# Toward the edges the land rises into a rim, so the zone reads as a basin.
	var edge := smoothstep(OutpostState.ZONE_SIZE * 0.45, OutpostState.ZONE_SIZE * 0.5 + MARGIN, r)
	h += edge * _amp * 1.6
	return h * wild


## The ground normal at ([param x], [param z]).
func normal(x: float, z: float) -> Vector3:
	var e := 6.0
	var hx := height(x + e, z) - height(x - e, z)
	var hz := height(x, z + e) - height(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


## A gas giant: the ground is cloud tops, everything floats over it.
func is_gas() -> bool:
	return type == PlanetDef.Type.GAS_GIANT


func has_liquid() -> bool:
	return type == PlanetDef.Type.OCEAN or type == PlanetDef.Type.LAVA


## The ground mesh: the zone and its margin, normals from the heightfield.
func build_mesh() -> ArrayMesh:
	var half := OutpostState.ZONE_SIZE * 0.5 + MARGIN
	var n := CELLS + 1
	var step := half * 2.0 / CELLS
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	verts.resize(n * n)
	norms.resize(n * n)
	for j in n:
		for i in n:
			var x := -half + i * step
			var z := -half + j * step
			verts[j * n + i] = Vector3(x, height(x, z), z)
	for j in n:
		for i in n:
			var l := verts[j * n + maxi(i - 1, 0)]
			var r := verts[j * n + mini(i + 1, n - 1)]
			var d := verts[maxi(j - 1, 0) * n + i]
			var u := verts[mini(j + 1, n - 1) * n + i]
			norms[j * n + i] = (u - d).cross(r - l).normalized()
	var idx := PackedInt32Array()
	idx.resize(CELLS * CELLS * 6)
	var k := 0
	for j in CELLS:
		for i in CELLS:
			var a := j * n + i
			idx[k] = a
			idx[k + 1] = a + 1
			idx[k + 2] = a + n
			idx[k + 3] = a + 1
			idx[k + 4] = a + n + 1
			idx[k + 5] = a + n
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Where a ray from [param from] along [param dir] meets the ground, INF when it misses.
func raycast(from: Vector3, dir: Vector3) -> Vector3:
	var p := from
	var step := 20.0
	for i in 800:
		var h := height(p.x, p.z)
		if p.y <= h:
			# Back up and refine.
			var a := p - dir * step
			for k in 8:
				var m := (a + p) * 0.5
				if m.y <= height(m.x, m.z):
					p = m
				else:
					a = m
			return p
		p += dir * step
		step = minf(step * 1.02, 60.0)
	return Vector3.INF

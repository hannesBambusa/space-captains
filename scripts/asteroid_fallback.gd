class_name AsteroidFallback
extends RefCounted
## Procedural stand-in asteroid meshes, used only when a glb is missing.
## Noise-displaced sphere (~1 m radius) with baked vertex-colour variation.
## Crystal variants get a second emissive surface of shards.

const ROCK_COLOR := Color(0.32, 0.30, 0.29)
const ORE_COLORS := {
	"iron": Color(0.45, 0.24, 0.14),
	"titanium": Color(0.62, 0.66, 0.72),
	"crystal": Color(0.25, 0.80, 0.90),
}


static func build(v_name: String) -> ArrayMesh:
	var kind := "rock"
	for k in ORE_COLORS:
		if v_name.contains(k):
			kind = k
	var variant_seed := hash(v_name)
	var mesh := ArrayMesh.new()
	_add_rock_surface(mesh, variant_seed, kind)
	var rock_mat := AsteroidBelt.to_asteroid_material(null)
	rock_mat.set_shader_parameter("use_vertex_color", true)
	rock_mat.set_shader_parameter("roughness", 0.92)
	if kind == "titanium":
		rock_mat.set_shader_parameter("metallic", 0.35)
		rock_mat.set_shader_parameter("roughness", 0.6)
	mesh.surface_set_material(0, rock_mat)
	if kind == "crystal":
		_add_crystal_surface(mesh, variant_seed)
		var cmat := AsteroidBelt.to_asteroid_material(null)
		cmat.set_shader_parameter("albedo_color", ORE_COLORS["crystal"])
		cmat.set_shader_parameter("roughness", 0.15)
		cmat.set_shader_parameter("emission_color", Color(0.42, 0.93, 1.0))
		cmat.set_shader_parameter("emission_energy", 3.0)
		mesh.surface_set_material(1, cmat)
	return mesh


static func _add_rock_surface(mesh: ArrayMesh, variant_seed: int, kind: String) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	var noise := FastNoiseLite.new()
	noise.seed = variant_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.frequency = 0.9
	var squash := Vector3(1.0, 0.75 + absf(sin(float(variant_seed))) * 0.2, 0.9)
	var ore_color: Color = ORE_COLORS.get(kind, ROCK_COLOR)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for idx in indices:
		var v: Vector3 = verts[idx].normalized()
		var n := noise.get_noise_3dv(v * 1.3)
		var p := v * (1.0 + n * 0.35) * squash
		var detail := noise.get_noise_3dv(v * 5.0 + Vector3(9, 3, 1))
		var shade := 0.85 + detail * 0.3
		var col := ROCK_COLOR * shade
		if kind != "rock":
			var vein := smoothstep(0.15, 0.35, noise.get_noise_3dv(v * 3.0 + Vector3(4, 7, 2)))
			col = col.lerp(ore_color * shade, vein)
		col.a = 1.0
		st.set_color(col)
		st.add_vertex(p)
	st.index()
	st.generate_normals()
	st.commit(mesh)


static func _add_crystal_surface(mesh: ArrayMesh, variant_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = variant_seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 7:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized()
		var length := rng.randf_range(0.5, 1.1)
		var thick := rng.randf_range(0.10, 0.2)
		var side := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
		var side2 := dir.cross(side)
		var b := dir * 0.6
		var tip := dir * (0.6 + length)
		var ring: Array[Vector3] = []
		for k in 6:
			var a := TAU * k / 6.0
			ring.append(b + (side * cos(a) + side2 * sin(a)) * thick + dir * length * 0.6)
		for k in 6:
			var r0 := ring[k]
			var r1 := ring[(k + 1) % 6]
			var b0 := b + (r0 - b - dir * length * 0.6) * 0.6
			var b1 := b + (r1 - b - dir * length * 0.6) * 0.6
			_tri(st, r0, r1, tip)
			_tri(st, b0, b1, r1)
			_tri(st, b0, r1, r0)
	st.generate_normals()
	st.commit(mesh)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(b)

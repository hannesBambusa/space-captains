class_name MeshUtil
extends RefCounted
## Small procedural meshes used by the system builder.

static var _sphere_cache: Dictionary = {}


## Flat annulus in the XZ plane, facing +Y. UV.x = 0 inner .. 1 outer.
static func make_annulus(inner: float, outer: float, segments: int = 256, radial: int = 1) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in segments + 1:
		var a := TAU * float(i) / float(segments)
		var d := Vector3(cos(a), 0.0, sin(a))
		for j in radial + 1:
			var f := float(j) / float(radial)
			verts.append(d * lerpf(inner, outer, f))
			normals.append(Vector3.UP)
			uvs.append(Vector2(f, float(i) / float(segments)))
	var row := radial + 1
	for i in segments:
		for j in radial:
			var a0 := i * row + j
			var b0 := (i + 1) * row + j
			indices.append_array([a0, b0, a0 + 1, a0 + 1, b0, b0 + 1])
	return _commit(verts, normals, uvs, indices)


## Orbit line strip: vertices on a circle of [param radius], UV.y = -1 / +1
## for the two edges. shaders/orbit_line.gdshader widens it to pixels.
static func make_orbit_strip(radius: float, segments: int = 512) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in segments + 1:
		var a := TAU * float(i) / float(segments)
		var p := Vector3(cos(a), 0.0, sin(a)) * radius
		for side in [-1.0, 1.0]:
			verts.append(p)
			normals.append(Vector3.UP)
			uvs.append(Vector2(float(i) / float(segments), side))
	for i in segments:
		var a0 := i * 2
		indices.append_array([a0, a0 + 2, a0 + 1, a0 + 1, a0 + 2, a0 + 3])
	var mesh := _commit(verts, normals, uvs, indices)
	# The vertex shader moves vertices by a few pixels; keep culling generous.
	mesh.custom_aabb = AABB(Vector3(-radius, -radius * 0.05, -radius), Vector3(radius * 2.0, radius * 0.1, radius * 2.0)).grow(50.0)
	return mesh


## Unit sphere shared per resolution.
static func unit_sphere(segments: int) -> SphereMesh:
	if _sphere_cache.has(segments):
		return _sphere_cache[segments]
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = segments
	s.rings = segments / 2
	_sphere_cache[segments] = s
	return s


static func set_layers_recursive(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layers
	for c in node.get_children():
		set_layers_recursive(c, layers)


static func _commit(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

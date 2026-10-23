class_name HullProfile
extends RefCounted
## How far a model's hull reaches from its centre at one height, per
## direction on the plane ([constant BINS] bins of 5 degrees, angle =
## atan2(x, z) in model space). Corridors use it to end at the hull instead
## of at the footprint circle. Built once per model from the mesh triangles:
## slices through the band around [param height] plus the vertices inside it,
## each counted for the bins whose ray passes within [param lateral] metres.

const BINS := 72


## Profile of every mesh under [param root] (skipping the [param skip]
## subtree, e.g. a spinning ring). Works outside the scene tree.
static func build(root: Node3D, height: float, half_band: float, lateral: float, skip: Node = null) -> PackedFloat32Array:
	var prof := PackedFloat32Array()
	prof.resize(BINS)
	var slices := [height - half_band * 0.7, height, height + half_band * 0.7]
	for mi in ModelLoader.meshes_of(root):
		if mi.mesh == null or (skip != null and (mi == skip or skip.is_ancestor_of(mi))):
			continue
		var xf := ModelLoader.relative_transform(root, mi)
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var w := PackedVector3Array()
			w.resize(verts.size())
			for i in verts.size():
				w[i] = xf * verts[i]
				if absf(w[i].y - height) <= half_band:
					_add(prof, w[i].x, w[i].z, lateral)
			var tri_count := idx.size() / 3 if not idx.is_empty() else w.size() / 3
			for t in tri_count:
				var a := w[idx[t * 3]] if not idx.is_empty() else w[t * 3]
				var b := w[idx[t * 3 + 1]] if not idx.is_empty() else w[t * 3 + 1]
				var c := w[idx[t * 3 + 2]] if not idx.is_empty() else w[t * 3 + 2]
				var lo := minf(a.y, minf(b.y, c.y))
				var hi := maxf(a.y, maxf(b.y, c.y))
				if hi < height - half_band or lo > height + half_band:
					continue
				for h: float in slices:
					if h < lo or h > hi:
						continue
					_slice(prof, a, b, c, h, lateral)
	return prof


## Hull reach (m) along model-space direction [param dir] (0 = nothing there).
static func radius_at(prof: PackedFloat32Array, dir: Vector3) -> float:
	if prof.is_empty():
		return 0.0
	var a := atan2(dir.x, dir.z)
	return prof[posmod(roundi(a / TAU * BINS), BINS)]


static func _slice(prof: PackedFloat32Array, a: Vector3, b: Vector3, c: Vector3, h: float, lateral: float) -> void:
	var pts: Array[Vector2] = []
	for e in [[a, b], [b, c], [c, a]]:
		var p: Vector3 = e[0]
		var q: Vector3 = e[1]
		if (p.y - h) * (q.y - h) > 0.0 or is_equal_approx(p.y, q.y):
			continue
		var t := (h - p.y) / (q.y - p.y)
		var x := p.lerp(q, t)
		pts.append(Vector2(x.x, x.z))
	if pts.size() < 2:
		return
	var n := clampi(ceili(pts[0].distance_to(pts[1]) / 1.5), 1, 40)
	for i in n + 1:
		var s := pts[0].lerp(pts[1], float(i) / float(n))
		_add(prof, s.x, s.y, lateral)


## Counts point (x, z) for every bin whose ray passes within [param lateral].
static func _add(prof: PackedFloat32Array, x: float, z: float, lateral: float) -> void:
	var r := Vector2(x, z).length()
	if r < 0.5:
		return
	var a := atan2(x, z)
	var half := asin(minf(lateral / r, 1.0))
	var step := TAU / BINS
	var k0 := ceili((a - half) / step)
	var k1 := floori((a + half) / step)
	for k in range(k0, k1 + 1):
		var diff := absf(a - k * step)
		if diff >= PI * 0.5:
			continue
		var i := posmod(k, BINS)
		prof[i] = maxf(prof[i], r * cos(diff))

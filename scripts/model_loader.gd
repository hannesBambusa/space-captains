class_name ModelLoader
extends RefCounted
## Instances Blender models at runtime so scenes still load while a .glb is
## missing, and builds simple placeholders (boxes and cylinders) instead.
## Placeholders carry the same named empties as the real models.

const HULL_COLOR := Color(0.58, 0.6, 0.64)
const DARK_COLOR := Color(0.24, 0.26, 0.3)
const LIGHT_COLOR := Color(1.0, 0.66, 0.3)
## Emission scale for structure lights (see [method dim_emission]).
const BUILDING_LIGHT_DIM := 0.35


## Model at [param path], or the result of [param fallback] when it is missing.
static func instantiate(path: String, fallback: Callable) -> Node3D:
	if not path.is_empty() and ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed:
			var inst := packed.instantiate() as Node3D
			if inst:
				return inst
	return fallback.call() as Node3D


## Generic building placeholder about [param footprint] * 1.4 across.
## Empties: "dock_point" (end of the docking arm), "spawn_point".
## [param tint] (alpha > 0) recolours the hull and lights, so placeholder
## buildings of different types tell apart.
static func building_placeholder(footprint: float, tint: Color = Color(0, 0, 0, 0)) -> Node3D:
	var s := footprint / 35.0
	var root := Node3D.new()
	root.name = "building_placeholder"
	var hull := _mat(HULL_COLOR.lerp(tint, 0.45) if tint.a > 0.0 else HULL_COLOR, 0.5, 0.5)
	var dark := _mat(DARK_COLOR, 0.3, 0.7)
	var glow := _glow_mat(tint if tint.a > 0.0 else LIGHT_COLOR, 4.0)
	_add_cyl(root, 18.0 * s, 20.0 * s, 4.0 * s, Vector3(0.0, 2.0 * s, 0.0), dark)
	_add_cyl(root, 5.0 * s, 6.5 * s, 24.0 * s, Vector3(0.0, 14.0 * s, 0.0), hull)
	_add_cyl(root, 7.0 * s, 7.0 * s, 1.2 * s, Vector3(0.0, 22.0 * s, 0.0), glow)
	_add_box(root, Vector3(12.0, 9.0, 16.0) * s, Vector3(-11.0, 8.5, 2.0) * s, hull)
	_add_box(root, Vector3(10.0, 7.0, 10.0) * s, Vector3(8.0, 7.5, 9.0) * s, hull)
	_add_cyl(root, 3.5 * s, 3.5 * s, 10.0 * s, Vector3(7.0, 9.0, -9.0) * s, dark)
	_add_cyl(root, 3.5 * s, 3.5 * s, 10.0 * s, Vector3(-3.0, 9.0, -12.0) * s, dark)
	_add_box(root, Vector3(22.0, 2.5, 4.0) * s, Vector3(22.0, 5.0, 0.0) * s, hull)
	_add_box(root, Vector3(1.0, 1.0, 5.0) * s, Vector3(32.5, 6.5, 0.0) * s, glow)
	_add_empty(root, "dock_point", Vector3(34.0, 6.0, 0.0) * s, -PI * 0.5)
	_add_empty(root, "spawn_point", Vector3(0.0, 10.0, -24.0) * s)
	return root


## Small ship placeholder about 14 m long, nose along -Z.
## Child mesh "engine_glow" at the stern.
static func ship_placeholder() -> Node3D:
	var root := Node3D.new()
	root.name = "ship_placeholder"
	var hull := _mat(Color(0.7, 0.62, 0.5), 0.4, 0.5)
	var dark := _mat(DARK_COLOR, 0.3, 0.7)
	_add_box(root, Vector3(4.0, 2.6, 10.0), Vector3(0.0, 0.0, 0.5), hull)
	var nose := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(4.0, 3.5, 2.6)
	prism.material = hull
	nose.mesh = prism
	nose.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	nose.position = Vector3(0.0, 0.0, -6.2)
	root.add_child(nose)
	_add_cyl(root, 1.1, 1.1, 8.0, Vector3(-3.0, -0.3, 1.5), dark).rotation.x = PI * 0.5
	_add_cyl(root, 1.1, 1.1, 8.0, Vector3(3.0, -0.3, 1.5), dark).rotation.x = PI * 0.5
	_add_box(root, Vector3(2.0, 1.4, 3.0), Vector3(0.0, 1.8, -1.5), dark)
	var glow := _add_cyl(root, 1.4, 1.0, 0.6, Vector3(0.0, 0.0, 5.8), _glow_mat(Color(0.45, 0.8, 1.0), 6.0))
	glow.name = "engine_glow"
	glow.rotation.x = PI * 0.5
	return root


## Escape pod about 4 m long, nose along -Z, child mesh "engine_glow".
static func pod_placeholder() -> Node3D:
	var root := Node3D.new()
	root.name = "pod_placeholder"
	var hull := _mat(Color(0.9, 0.9, 0.86), 0.3, 0.45)
	var stripe := _glow_mat(Color(1.0, 0.55, 0.2), 3.0)
	var body := _add_cyl(root, 1.1, 1.3, 3.4, Vector3.ZERO, hull)
	body.rotation.x = PI * 0.5
	var band := _add_cyl(root, 1.35, 1.35, 0.35, Vector3(0.0, 0.0, -0.6), stripe)
	band.rotation.x = PI * 0.5
	var glow := _add_cyl(root, 0.7, 0.5, 0.4, Vector3(0.0, 0.0, 1.9), _glow_mat(Color(0.45, 0.8, 1.0), 6.0))
	glow.name = "engine_glow"
	glow.rotation.x = PI * 0.5
	return root


static func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


static func _glow_mat(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


static func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	mi.mesh = box
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _add_cyl(parent: Node3D, top: float, bottom: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = top
	cyl.bottom_radius = bottom
	cyl.height = height
	cyl.radial_segments = 24
	cyl.material = mat
	mi.mesh = cyl
	mi.position = pos
	parent.add_child(mi)
	return mi


## [param yaw] turns the empty's -Z (the "out" direction) on the plane.
static func _add_empty(parent: Node3D, empty_name: String, pos: Vector3, yaw: float = 0.0) -> void:
	var n := Marker3D.new()
	n.name = empty_name
	n.position = pos
	n.rotation.y = yaw
	parent.add_child(n)


## All MeshInstance3D nodes under [param node].
static func meshes_of(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(meshes_of(c))
	return out


## Scales the emission of every emissive material under [param root] by
## [param factor], so window and dock lights don't bloom. Dimmed copies are
## cached per source material and shared between instances.
static func dim_emission(root: Node, factor: float = BUILDING_LIGHT_DIM) -> void:
	for mi in meshes_of(root):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i) as StandardMaterial3D
			if src == null or not src.emission_enabled:
				continue
			var key := "%d:%s" % [src.get_instance_id(), factor]
			var m: StandardMaterial3D = _dimmed.get(key)
			if m == null:
				m = src.duplicate() as StandardMaterial3D
				m.emission_energy_multiplier = src.emission_energy_multiplier * factor
				_dimmed[key] = m
			mi.set_surface_override_material(i, m)


static var _dimmed := {}


## Recolours every mesh under [param root] toward [param color] by
## [param amount] (albedo multiplied, emission blended), skipping the
## "engine_glow" subtree (Ship animates those). For stand-in models of a
## faction whose own model is missing. Tinted copies are cached per source
## material and colour.
static func tint(root: Node, color: Color, amount: float) -> void:
	if root.name == &"engine_glow":
		return
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var src := mi.get_active_material(i) as BaseMaterial3D
				if src == null:
					continue
				var key := "%d:%s:%s" % [src.get_instance_id(), color.to_html(), amount]
				var m: BaseMaterial3D = _tinted.get(key)
				if m == null:
					m = src.duplicate() as BaseMaterial3D
					m.albedo_color = src.albedo_color * Color.WHITE.lerp(color, amount)
					if src.emission_enabled:
						m.emission = src.emission.lerp(color, minf(amount * 1.4, 1.0))
					_tinted[key] = m
				mi.set_surface_override_material(i, m)
	for c in root.get_children():
		tint(c, color, amount)


static var _tinted := {}


## Combined local-space AABB of all meshes under [param root], relative to it.
static func local_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var inv := root.global_transform.affine_inverse() if root.is_inside_tree() else Transform3D.IDENTITY
	for mi in meshes_of(root):
		if mi.mesh == null:
			continue
		var xf: Transform3D
		if root.is_inside_tree():
			xf = inv * mi.global_transform
		else:
			xf = _relative_xform(root, mi)
		var b := xf * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## Transform of [param node] relative to its ancestor [param root]; works
## outside the scene tree.
static func relative_transform(root: Node3D, node: Node3D) -> Transform3D:
	return _relative_xform(root, node)


static func _relative_xform(root: Node3D, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf

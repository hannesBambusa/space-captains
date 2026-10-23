class_name CorridorKit
extends RefCounted
## Modular corridor pieces from Blender (assets/models/buildings/connectors),
## each merged into one Mesh so a MultiMesh can draw every copy in a few draw
## calls. A missing .glb falls back to a procedural tube and truss piece with
## the same dimensions:
##   SEGMENT   straight tube, z = 0 .. -20, centre line at x = 0, y = 0, tiles.
##   COLLAR    airlock collar, z = 0 .. -5, flange at z = 0 facing +Z (the structure).
##   JUNCTION  node about 9 m across, centred, ports at +-X / +-Z.

enum Part { SEGMENT, COLLAR, JUNCTION }

const PATHS := {
	Part.SEGMENT: "res://assets/models/buildings/connectors/corridor_segment.glb",
	Part.COLLAR: "res://assets/models/buildings/connectors/corridor_collar.glb",
	Part.JUNCTION: "res://assets/models/buildings/connectors/corridor_junction.glb",
}
const SEGMENT_LENGTH := 20.0
const COLLAR_LENGTH := 5.0
## Junction port face distance from its centre.
const JUNCTION_PORT := 5.0
## Half width of the tube (ribs and rails included), for clearance checks.
const TUBE_RADIUS := 4.0

static var _meshes: Dictionary = {}


## Shared mesh for [param part] (cached).
static func mesh(part: Part) -> Mesh:
	if _meshes.has(part):
		return _meshes[part]
	var m := _from_glb(PATHS[part])
	if m == null:
		print("CorridorKit: %s not found, using placeholder" % PATHS[part])
		match part:
			Part.SEGMENT:
				m = _placeholder_segment()
			Part.COLLAR:
				m = _placeholder_collar()
			_:
				m = _placeholder_junction()
	_meshes[part] = m
	return m


## True when [param part] comes from the Blender kit.
static func has_model(part: Part) -> bool:
	return ResourceLoader.exists(PATHS[part])


## Merges every mesh in the glb (with its node transform and materials) into
## one ArrayMesh. Emissive materials are dimmed like structure lights.
static func _from_glb(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var root := packed.instantiate() as Node3D
	if root == null:
		return null
	var out := ArrayMesh.new()
	for mi in ModelLoader.meshes_of(root):
		if mi.mesh == null:
			continue
		var xf := ModelLoader.relative_transform(root, mi)
		for s in mi.mesh.get_surface_count():
			var st := SurfaceTool.new()
			st.append_from(mi.mesh, s, xf)
			st.set_material(_dimmed(mi.get_active_material(s)))
			st.commit(out)
	root.free()
	return out if out.get_surface_count() > 0 else null


static func _dimmed(src: Material) -> Material:
	var sm := src as StandardMaterial3D
	if sm == null or not sm.emission_enabled:
		return src
	var m := sm.duplicate() as StandardMaterial3D
	m.emission_energy_multiplier = sm.emission_energy_multiplier * ModelLoader.BUILDING_LIGHT_DIM
	return m


# --- Placeholders ---------------------------------------------------------------

static func _placeholder_segment() -> Mesh:
	var hull := _mat(ModelLoader.HULL_COLOR, 0.5, 0.5)
	var dark := _mat(ModelLoader.DARK_COLOR, 0.4, 0.7)
	var out := ArrayMesh.new()
	var tube := _cyl(2.6, 2.6, SEGMENT_LENGTH, 12)
	_append(out, tube, _along_z(-SEGMENT_LENGTH * 0.5), hull)
	var rib := _cyl(2.88, 2.88, 1.0, 12)
	for z in [-0.5, -SEGMENT_LENGTH + 0.5]:
		_append(out, rib, _along_z(z), dark)
	var rail := BoxMesh.new()
	rail.size = Vector3(0.45, 0.45, SEGMENT_LENGTH)
	for c in [Vector2(2.2, 2.2), Vector2(-2.2, 2.2), Vector2(2.2, -2.2), Vector2(-2.2, -2.2)]:
		_append(out, rail, Transform3D(Basis.IDENTITY, Vector3(c.x, c.y, -SEGMENT_LENGTH * 0.5)), dark)
	return out


static func _placeholder_collar() -> Mesh:
	var hull := _mat(ModelLoader.HULL_COLOR.darkened(0.1), 0.5, 0.5)
	var dark := _mat(ModelLoader.DARK_COLOR, 0.4, 0.7)
	var glow := _glow(ModelLoader.LIGHT_COLOR, 4.0 * ModelLoader.BUILDING_LIGHT_DIM)
	var out := ArrayMesh.new()
	_append(out, _cyl(4.2, 4.2, 1.0, 16), _along_z(-0.5), dark)
	_append(out, _cyl(3.3, 3.3, COLLAR_LENGTH - 1.0, 12), _along_z(-1.0 - (COLLAR_LENGTH - 1.0) * 0.5), hull)
	_append(out, _cyl(3.45, 3.45, 0.4, 12), _along_z(-2.6), glow)
	return out


static func _placeholder_junction() -> Mesh:
	var hull := _mat(ModelLoader.HULL_COLOR, 0.5, 0.5)
	var dark := _mat(ModelLoader.DARK_COLOR, 0.4, 0.7)
	var glow := _glow(ModelLoader.LIGHT_COLOR, 4.0 * ModelLoader.BUILDING_LIGHT_DIM)
	var out := ArrayMesh.new()
	_append(out, _cyl(4.5, 4.5, 7.0, 8), Transform3D.IDENTITY, hull)
	_append(out, _cyl(3.0, 3.0, 1.2, 8), Transform3D(Basis.IDENTITY, Vector3(0.0, 4.1, 0.0)), dark)
	_append(out, _cyl(4.6, 4.6, 0.4, 8), Transform3D(Basis.IDENTITY, Vector3(0.0, 1.8, 0.0)), glow)
	var port := _cyl(2.7, 2.7, JUNCTION_PORT * 2.0, 12)
	_append(out, port, _along_z(0.0), hull)
	_append(out, port, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO) * _along_z(0.0), hull)
	return out


static func _cyl(top: float, bottom: float, height: float, segments: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	return c


## Cylinder axis (Y) turned onto Z, centred at z.
static func _along_z(z: float) -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.0, z))


static func _append(out: ArrayMesh, src: Mesh, xf: Transform3D, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.append_from(src, 0, xf)
	st.set_material(mat)
	st.commit(out)


static func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


static func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := _mat(color, 0.0, 0.5)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m

class_name ConstructionLook
extends Node3D
## The under-construction look of a [Building] (child of it), in three
## phases over the build progress:
## [br]- 0 to [constant BLUEPRINT_END]: a holographic blueprint of the finished
## structure fades in, a projection sweep runs up it, a footprint ring shows
## on the base plane.
## [br]- to [constant ASSEMBLY_END]: the real model is revealed bottom-up
## behind a soft welding seam; above the seam it stays blueprint.
## [br]- to 1: the seam sweeps off the top, a flash runs along the edges and
## the lights come on. At 1 the original materials go back exactly.
## [br]Each surface gets its own construction material
## (shaders/construction_build, with the surface's baked textures copied in)
## plus the blueprint as its next_pass (shaders/construction_holo); the two
## passes draw complementary halves of the surface, so they cannot z-fight.

const BUILD_SHADER: Shader = preload("res://shaders/construction_build.gdshader")
const BUILD_DOUBLE_SHADER: Shader = preload("res://shaders/construction_build_double.gdshader")
const HOLO_SHADER: Shader = preload("res://shaders/construction_holo.gdshader")
const BLUEPRINT_END := 0.1
const ASSEMBLY_END := 0.95
const HOLO_COLOR := Color(0.35, 0.8, 1.0)
const SEAM_COLOR := Color(1.0, 0.58, 0.24)

var _building: Building
var _model: Node3D
var _box: AABB
var _margin := 1.0
## One entry per mesh: {mi, override, surfaces: Array[Material], shadow, mats: Array[ShaderMaterial]}.
var _saved: Array[Dictionary] = []
var _all_mats: Array[ShaderMaterial] = []
var _ring: MeshInstance3D
var _last := {}


## [param model_box]: the model's AABB in building space.
func setup(building: Building, model: Node3D, model_box: AABB) -> void:
	_building = building
	_model = model
	_box = model_box
	name = "ConstructionLook"


func _ready() -> void:
	var seam_w := clampf(_box.size.y * 0.02, 0.35, 1.2)
	var noise := clampf(_box.size.y * 0.025, 0.3, 1.2)
	_margin = noise + seam_w * 6.0
	var grid := maxf(_building.def.footprint_radius / 12.0, 1.0)
	for mi in ModelLoader.meshes_of(_model):
		if mi.mesh == null:
			continue
		var entry := {"mi": mi, "override": mi.material_override, "shadow": mi.cast_shadow, "surfaces": [], "mats": []}
		var to_site := _to_site(mi)
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i)
			(entry["surfaces"] as Array).append(mi.get_surface_override_material(i))
			var m := _make_material(src as StandardMaterial3D)
			m.set_shader_parameter("to_site", to_site)
			m.set_shader_parameter("seam_width", seam_w)
			m.set_shader_parameter("noise_amp", noise)
			var holo := m.next_pass as ShaderMaterial
			holo.set_shader_parameter("to_site", to_site)
			holo.set_shader_parameter("seam_width", seam_w)
			holo.set_shader_parameter("noise_amp", noise)
			holo.set_shader_parameter("grid_size", grid)
			holo.set_shader_parameter("scan_width", maxf(_box.size.y * 0.04, 0.8))
			m.set_shader_parameter("pulse_width", maxf(_box.size.y * 0.08, 1.5))
			(entry["mats"] as Array).append(m)
			_all_mats.append(m)
			_all_mats.append(holo)
		_saved.append(entry)
	for e in _saved:
		var mi: MeshInstance3D = e["mi"]
		mi.material_override = null
		var mats: Array = e["mats"]
		for i in mats.size():
			mi.set_surface_override_material(i, mats[i])
	if _building.bay <= 0:
		_ring = RingUtil.make_ring(_building.def.footprint_radius, Color(HOLO_COLOR, 0.0), 1.6)
		_ring.name = "FootprintRing"
		_ring.layers = Building.RENDER_LAYER
		_ring.position = Vector3(0.0, _box.position.y + 0.15, 0.0)
		add_child(_ring)


## Puts every original material, override and shadow setting back.
func restore() -> void:
	for e in _saved:
		var mi: MeshInstance3D = e["mi"]
		if not is_instance_valid(mi):
			continue
		var surfaces: Array = e["surfaces"]
		for i in surfaces.size():
			mi.set_surface_override_material(i, surfaces[i])
		mi.material_override = e["override"]
		mi.cast_shadow = e["shadow"]
	_saved.clear()
	_all_mats.clear()


## Building-space height of the build line at [param progress].
func cut_height(progress: float) -> float:
	var lo := _box.position.y - _margin
	var hi := _box.end.y + _margin
	if progress < BLUEPRINT_END:
		return lo
	return lerpf(lo, hi, clampf((progress - BLUEPRINT_END) / (ASSEMBLY_END - BLUEPRINT_END), 0.0, 1.0))


## The model's AABB, building space.
func model_box() -> AABB:
	return _box


func update(progress: float) -> void:
	var q := clampf((progress - ASSEMBLY_END) / (1.0 - ASSEMBLY_END), 0.0, 1.0)
	var intensity := smoothstep(0.0, 0.04, progress)
	var scan := -10000.0
	if progress < BLUEPRINT_END:
		scan = lerpf(_box.position.y - 2.0, _box.end.y + 6.0, smoothstep(0.0, 1.0, progress / BLUEPRINT_END))
	_set_all("cut_y", cut_height(progress))
	_set_all("intensity", intensity)
	_set_all("scan_y", scan)
	_set_all("fresh", 1.0 - q)
	_set_all("lights_on", smoothstep(0.3, 1.0, q))
	_set_all("pulse", sin(PI * q))
	_set_all("pulse_y", lerpf(_box.position.y - 2.0, _box.end.y + 4.0, q) if q > 0.0 else -10000.0)
	if _ring:
		RingUtil.set_color(_ring, Color(HOLO_COLOR, 0.45 * intensity * (1.0 - q)))


## Sets [param param] on every material, only when it changed.
func _set_all(param: StringName, value: float) -> void:
	if is_equal_approx(float(_last.get(param, NAN)), value):
		return
	_last[param] = value
	for m in _all_mats:
		m.set_shader_parameter(param, value)


func _to_site(mi: MeshInstance3D) -> Transform3D:
	if _building.is_inside_tree() and mi.is_inside_tree():
		return _building.global_transform.affine_inverse() * mi.global_transform
	return ModelLoader.relative_transform(_building, mi)


static func _make_material(src: StandardMaterial3D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var cull_off := src != null and src.cull_mode == BaseMaterial3D.CULL_DISABLED
	m.shader = BUILD_DOUBLE_SHADER if cull_off else BUILD_SHADER
	m.set_shader_parameter("seam_color", SEAM_COLOR)
	if src:
		m.set_shader_parameter("albedo_color", src.albedo_color)
		if src.albedo_texture:
			m.set_shader_parameter("albedo_tex", src.albedo_texture)
		if src.normal_enabled and src.normal_texture:
			m.set_shader_parameter("use_normal", true)
			m.set_shader_parameter("normal_tex", src.normal_texture)
			m.set_shader_parameter("normal_scale", src.normal_scale)
		m.set_shader_parameter("metallic", src.metallic)
		m.set_shader_parameter("roughness", src.roughness)
		m.set_shader_parameter("specular", src.metallic_specular)
		if src.metallic_texture:
			m.set_shader_parameter("metallic_tex", src.metallic_texture)
			m.set_shader_parameter("metallic_channel", _channel(src.metallic_texture_channel))
		if src.roughness_texture:
			m.set_shader_parameter("roughness_tex", src.roughness_texture)
			m.set_shader_parameter("roughness_channel", _channel(src.roughness_texture_channel))
		if src.emission_enabled:
			m.set_shader_parameter("emission_color", src.emission)
			m.set_shader_parameter("emission_energy", src.emission_energy_multiplier)
		m.set_shader_parameter("uv1_scale", src.uv1_scale)
		m.set_shader_parameter("uv1_offset", src.uv1_offset)
	else:
		m.set_shader_parameter("albedo_color", ModelLoader.HULL_COLOR)
		m.set_shader_parameter("metallic", 0.4)
		m.set_shader_parameter("roughness", 0.55)
	var holo := ShaderMaterial.new()
	holo.shader = HOLO_SHADER
	holo.set_shader_parameter("holo_color", HOLO_COLOR)
	holo.set_shader_parameter("seam_color", SEAM_COLOR)
	m.next_pass = holo
	return m


static func _channel(c: BaseMaterial3D.TextureChannel) -> Vector4:
	match c:
		BaseMaterial3D.TEXTURE_CHANNEL_RED:
			return Vector4(1, 0, 0, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN:
			return Vector4(0, 1, 0, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE:
			return Vector4(0, 0, 1, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA:
			return Vector4(0, 0, 0, 1)
	return Vector4(0.3333, 0.3333, 0.3333, 0.0)


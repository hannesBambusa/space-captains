@tool
class_name AsteroidBelt
extends Node3D
## Scatters asteroids in an arc-shaped band using one MultiMeshInstance3D per
## mesh variant. Asteroids tumble in the vertex shader (shaders/asteroid.gdshader),
## so the CPU never touches them after the build.
##
## The arc is centred on this node's origin plus [member arc_center]. Angle 0 points
## along +X, 90 degrees along +Z (screen-down at default yaw), 270 along -Z.

enum OreType { ROCK, IRON, TITANIUM, CRYSTAL }

const ASTEROID_DIR := "res://assets/models/asteroids/"
const ROCK_VARIANTS: Array[String] = [
	"asteroid_rock_01", "asteroid_rock_02", "asteroid_rock_03", "asteroid_rock_04", "asteroid_rock_05",
]
const ORE_VARIANTS := {
	OreType.IRON: ["asteroid_iron_01", "asteroid_iron_02"],
	OreType.TITANIUM: ["asteroid_titanium_01", "asteroid_titanium_02"],
	OreType.CRYSTAL: ["asteroid_crystal_01", "asteroid_crystal_02"],
}
const ASTEROID_SHADER: Shader = preload("res://shaders/asteroid.gdshader")
const MAX_REJECTION_TRIES := 12

## Prepared meshes (with asteroid shader materials), shared by all belts.
static var _mesh_cache: Dictionary = {}

@export_group("Shape")
@export var arc_center: Vector3 = Vector3.ZERO:
	set(v):
		arc_center = v
		_queue_rebuild()
@export var radius: float = 600.0:
	set(v):
		radius = maxf(v, 1.0)
		_queue_rebuild()
@export_range(-360.0, 720.0, 0.5, "degrees") var arc_start_deg: float = 0.0:
	set(v):
		arc_start_deg = v
		_queue_rebuild()
@export_range(-360.0, 720.0, 0.5, "degrees") var arc_end_deg: float = 90.0:
	set(v):
		arc_end_deg = v
		_queue_rebuild()
## Full radial width of the band in metres. Asteroids cluster toward its middle.
@export var width: float = 140.0:
	set(v):
		width = maxf(v, 0.0)
		_queue_rebuild()
## Max distance above/below the y = 0 play plane.
@export_range(0.0, 50.0, 0.5) var vertical_spread: float = 8.0:
	set(v):
		vertical_spread = v
		_queue_rebuild()
## 0 = even spread along the arc, 1 = strong clumps and gaps.
@export_range(0.0, 1.0, 0.01) var clumping: float = 0.55:
	set(v):
		clumping = v
		_queue_rebuild()

@export_group("Content")
@export_range(0, 5000, 1) var count: int = 600:
	set(v):
		count = v
		_queue_rebuild()
## Asteroid radius range in metres (meshes are ~1 m radius).
@export_range(0.5, 60.0, 0.1) var min_scale: float = 2.0:
	set(v):
		min_scale = v
		_queue_rebuild()
@export_range(0.5, 60.0, 0.1) var max_scale: float = 25.0:
	set(v):
		max_scale = v
		_queue_rebuild()
## Higher values make small asteroids more common than big ones.
@export_range(1.0, 6.0, 0.1) var size_bias: float = 2.6:
	set(v):
		size_bias = v
		_queue_rebuild()
@export var seed: int = 1:
	set(v):
		seed = v
		_queue_rebuild()
@export var ore_type: OreType = OreType.ROCK:
	set(v):
		ore_type = v
		_queue_rebuild()
## Optional second ore mixed in. ROCK means none.
@export var secondary_ore: OreType = OreType.ROCK:
	set(v):
		secondary_ore = v
		_queue_rebuild()
## Share of ore asteroids that use the secondary ore.
@export_range(0.0, 1.0, 0.01) var secondary_share: float = 0.3:
	set(v):
		secondary_share = v
		_queue_rebuild()
## 0..1. Drives the share of ore-bearing asteroids.
@export_range(0.0, 1.0, 0.01) var richness: float = 0.3:
	set(v):
		richness = v
		_queue_rebuild()
## 1..5. Gameplay metadata (no visual effect yet).
@export_range(1, 5, 1) var danger: int = 1

@export_group("Look")
## Max tumble speed in rad/s for the smallest asteroids. Big ones turn slower.
@export_range(0.0, 2.0, 0.01) var max_spin_speed: float = 0.25:
	set(v):
		max_spin_speed = v
		_queue_rebuild()
## Multiplies mesh emission (crystal glow) for this belt.
@export_range(0.0, 10.0, 0.05) var emission_boost: float = 1.0:
	set(v):
		emission_boost = v
		_apply_emission_boost()
@export var cast_shadows: bool = true:
	set(v):
		cast_shadows = v
		_queue_rebuild()

var _rebuild_queued := false
var _instances: Array[MultiMeshInstance3D] = []


func _ready() -> void:
	add_to_group("asteroid_belts")
	_rebuild()


## Share of asteroids that carry ore, from richness.
func get_ore_fraction() -> float:
	if ore_type == OreType.ROCK:
		return 0.0
	return lerpf(0.04, 0.55, richness)


func _queue_rebuild() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_queued = false
	for mmi in _instances:
		if is_instance_valid(mmi):
			mmi.queue_free()
	_instances.clear()
	if count <= 0:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed)
	var clump_noise := FastNoiseLite.new()
	clump_noise.seed = seed
	clump_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	clump_noise.frequency = 1.0

	var variants := _variant_names()
	var transforms: Dictionary = {}
	var customs: Dictionary = {}
	for v_name in variants:
		transforms[v_name] = []
		customs[v_name] = []

	var ore_fraction := get_ore_fraction()
	var lo := minf(min_scale, max_scale)
	var hi := maxf(min_scale, max_scale)
	var arc_len_deg := absf(arc_end_deg - arc_start_deg)
	var is_ring := arc_len_deg >= 359.0
	var arc_len_m := deg_to_rad(arc_len_deg) * radius

	for i in count:
		var t := 0.0
		for _try in MAX_REJECTION_TRIES:
			t = rng.randf()
			var density := clump_noise.get_noise_1d(t * arc_len_m / 260.0) * 0.5 + 0.5
			if rng.randf() < lerpf(1.0, density * density * 1.6, clumping):
				break
		var taper := 1.0 if is_ring else pow(sin(t * PI), 0.6)
		var angle := deg_to_rad(lerpf(arc_start_deg, arc_end_deg, t))
		var local_width := width * (0.25 + 0.75 * taper)
		var r_off := clampf(rng.randfn(0.0, 0.32), -0.5, 0.5) * local_width
		var r := radius + r_off
		var y := clampf(rng.randfn(0.0, vertical_spread * 0.4), -vertical_spread, vertical_spread)
		var pos := arc_center + Vector3(cos(angle) * r, y, sin(angle) * r)

		var s := lerpf(lo, hi, pow(rng.randf(), size_bias))
		# Thin tails get smaller rocks.
		s = lerpf(lo, s, 0.4 + 0.6 * taper)
		var q := Quaternion(_random_axis(rng), rng.randf() * TAU)
		var xf := Transform3D(Basis(q).scaled(Vector3.ONE * s), pos)

		var v_name: String
		if rng.randf() < ore_fraction:
			var ore := ore_type
			if secondary_ore != OreType.ROCK and rng.randf() < secondary_share:
				ore = secondary_ore
			var ore_list: Array = ORE_VARIANTS[ore]
			v_name = ore_list[rng.randi() % ore_list.size()]
		else:
			v_name = ROCK_VARIANTS[rng.randi() % ROCK_VARIANTS.size()]

		var spin := max_spin_speed * rng.randf_range(0.25, 1.0) * clampf(4.0 / s, 0.12, 1.0)
		if rng.randf() < 0.5:
			spin = -spin
		var custom := Color(rng.randf(), rng.randf(), spin, rng.randf())
		transforms[v_name].append(xf)
		customs[v_name].append(custom)

	var pad := hi * 2.0 + vertical_spread
	for v_name in variants:
		var xfs: Array = transforms[v_name]
		if xfs.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = get_variant_mesh(v_name)
		mm.instance_count = xfs.size()
		var aabb := AABB(xfs[0].origin, Vector3.ZERO)
		for j in xfs.size():
			mm.set_instance_transform(j, xfs[j])
			mm.set_instance_custom_data(j, customs[v_name][j])
			aabb = aabb.expand(xfs[j].origin)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = v_name
		mmi.multimesh = mm
		mmi.custom_aabb = aabb.grow(pad)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.set_instance_shader_parameter("emission_boost", emission_boost)
		add_child(mmi, false, Node.INTERNAL_MODE_BACK)
		_instances.append(mmi)


func _apply_emission_boost() -> void:
	for mmi in _instances:
		if is_instance_valid(mmi):
			mmi.set_instance_shader_parameter("emission_boost", emission_boost)


func _variant_names() -> Array[String]:
	var names: Array[String] = []
	names.append_array(ROCK_VARIANTS)
	for ore in ORE_VARIANTS:
		for v_name: String in ORE_VARIANTS[ore]:
			names.append(v_name)
	return names


func _random_axis(rng: RandomNumberGenerator) -> Vector3:
	var z := rng.randf_range(-1.0, 1.0)
	var a := rng.randf() * TAU
	var rxy := sqrt(1.0 - z * z)
	return Vector3(rxy * cos(a), z, rxy * sin(a))


# --- Mesh loading -----------------------------------------------------------

## Shared asteroid mesh (asteroid-shader materials) for a variant name, cached.
static func get_variant_mesh(v_name: String) -> Mesh:
	if _mesh_cache.has(v_name):
		return _mesh_cache[v_name]
	var mesh := _load_glb_mesh(ASTEROID_DIR + v_name + ".glb")
	if mesh == null:
		print("AsteroidBelt: %s.glb not found, using procedural fallback" % v_name)
		mesh = AsteroidFallback.build(v_name)
	_mesh_cache[v_name] = mesh
	return mesh


## Loads the first MeshInstance3D's mesh from a glb, then makes an in-memory copy
## whose surface materials are asteroid-shader versions of the originals. The
## imported file is never modified.
static func _load_glb_mesh(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var root := packed.instantiate()
	var mi := _find_mesh_instance(root)
	var result: ArrayMesh = null
	if mi != null and mi.mesh is ArrayMesh:
		result = mi.mesh.duplicate() as ArrayMesh
		for i in result.get_surface_count():
			result.surface_set_material(i, to_asteroid_material(mi.get_active_material(i)))
	root.free()
	return result


static func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return node
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found != null:
			return found
	return null


## Converts a BaseMaterial3D into an asteroid ShaderMaterial with the same look.
static func to_asteroid_material(src: Material) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = ASTEROID_SHADER
	var base := src as BaseMaterial3D
	if base == null:
		return mat
	mat.set_shader_parameter("albedo_color", base.albedo_color)
	if base.albedo_texture:
		mat.set_shader_parameter("albedo_texture", base.albedo_texture)
		mat.set_shader_parameter("use_albedo_texture", true)
	mat.set_shader_parameter("use_vertex_color", base.vertex_color_use_as_albedo)
	mat.set_shader_parameter("metallic", base.metallic)
	mat.set_shader_parameter("roughness", base.roughness)
	mat.set_shader_parameter("specular", base.metallic_specular)
	if base is ORMMaterial3D and (base as ORMMaterial3D).orm_texture:
		var orm := (base as ORMMaterial3D).orm_texture
		mat.set_shader_parameter("metallic_texture", orm)
		mat.set_shader_parameter("roughness_texture", orm)
		mat.set_shader_parameter("metallic_channel", Vector4(0, 0, 1, 0))
		mat.set_shader_parameter("roughness_channel", Vector4(0, 1, 0, 0))
		mat.set_shader_parameter("use_metallic_texture", true)
		mat.set_shader_parameter("use_roughness_texture", true)
	elif base is StandardMaterial3D:
		var std := base as StandardMaterial3D
		if std.metallic_texture:
			mat.set_shader_parameter("metallic_texture", std.metallic_texture)
			mat.set_shader_parameter("metallic_channel", _channel_vec(std.metallic_texture_channel))
			mat.set_shader_parameter("use_metallic_texture", true)
		if std.roughness_texture:
			mat.set_shader_parameter("roughness_texture", std.roughness_texture)
			mat.set_shader_parameter("roughness_channel", _channel_vec(std.roughness_texture_channel))
			mat.set_shader_parameter("use_roughness_texture", true)
	if base.normal_enabled and base.normal_texture:
		mat.set_shader_parameter("normal_texture", base.normal_texture)
		mat.set_shader_parameter("normal_scale", base.normal_scale)
		mat.set_shader_parameter("use_normal_texture", true)
	if base.emission_enabled:
		var e := base.emission
		mat.set_shader_parameter("emission_color", Color(e.r, e.g, e.b))
		mat.set_shader_parameter("emission_energy", base.emission_energy_multiplier)
		if base.emission_texture:
			mat.set_shader_parameter("emission_texture", base.emission_texture)
			mat.set_shader_parameter("use_emission_texture", true)
	return mat


static func _channel_vec(ch: int) -> Vector4:
	match ch:
		BaseMaterial3D.TEXTURE_CHANNEL_RED:
			return Vector4(1, 0, 0, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN:
			return Vector4(0, 1, 0, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE:
			return Vector4(0, 0, 1, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA:
			return Vector4(0, 0, 0, 1)
	return Vector4(0.299, 0.587, 0.114, 0)

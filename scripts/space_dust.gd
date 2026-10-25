class_name SpaceDust
extends MultiMeshInstance3D
## Faint drifting dust motes close to the play plane, for parallax while the
## camera moves. The motes live in a box that follows the RTS camera pivot and
## wraps (all in shaders/space_dust.gdshader), so a few thousand quads cover
## the whole sector.

const DUST_SHADER: Shader = preload("res://shaders/space_dust.gdshader")

@export var mote_count: int = 7000
## Edge length of the wrapping box on X/Z, in metres.
@export var box_extent: float = 1000.0
## Half-height of the dust layer around y = 0, in metres.
@export var half_height: float = 45.0
@export var max_drift_speed: float = 1.2
@export var seed_value: int = 4242
## Hide the dust when the camera is zoomed out further than this. 0 = never.
@export var max_camera_distance: float = 0.0

var _material: ShaderMaterial
var _focus_node: Node3D


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_material = ShaderMaterial.new()
	_material.shader = DUST_SHADER
	_material.set_shader_parameter("box_size", Vector3(box_extent, half_height * 2.0, box_extent))
	quad.material = _material

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = mote_count
	var half := box_extent * 0.5
	for i in mote_count:
		var pos := Vector3(
				rng.randf_range(-half, half),
				clampf(rng.randfn(0.0, half_height * 0.45), -half_height, half_height),
				rng.randf_range(-half, half))
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos))
		var vel := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.1, 0.1), rng.randf_range(-1, 1)) * max_drift_speed
		mm.set_instance_custom_data(i, Color(vel.x, vel.y, vel.z, pow(rng.randf(), 2.0) * 0.9 + 0.1))
	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Motes are moved in the shader anywhere inside the sector, so never cull.
	custom_aabb = AABB(Vector3(-4000, -100, -4000), Vector3(8000, 200, 8000))
	_focus_node = RTSCamera.of(get_tree())
	if _focus_node and max_camera_distance > 0.0 and _focus_node.has_signal("view_changed"):
		_focus_node.view_changed.connect(_on_view_changed)


func _on_view_changed(_pivot: Vector3, distance: float, _yaw_deg: float) -> void:
	visible = distance < max_camera_distance


func _process(_delta: float) -> void:
	if _focus_node == null:
		_focus_node = RTSCamera.of(get_tree())
		if _focus_node == null:
			return
	var focus := _focus_node.global_position
	_material.set_shader_parameter("focus", focus)
	# Keep the cull box around the wrapping volume wherever the camera goes.
	var local_focus := global_transform.affine_inverse() * focus
	var half := Vector3(box_extent, half_height * 2.0 + 20.0, box_extent)
	if custom_aabb.get_center().distance_to(local_focus) > box_extent * 0.5:
		custom_aabb = AABB(local_focus - half * 2.0, half * 4.0)

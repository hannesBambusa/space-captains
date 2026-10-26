class_name WarpFx
extends Node3D
## A short flash where a ship enters or leaves a warp hop: a bright sphere
## and a light that swell and fade over [constant LIFE] sim seconds (frozen
## while paused). Spawned by Ship; frees itself.

const LIFE := 0.6
const COLOR := Color(0.62, 0.85, 1.0)

static var _mesh: SphereMesh
static var _mat: StandardMaterial3D

var _age: float = 0.0
var _size: float = 30.0
var _ball: MeshInstance3D
var _light: OmniLight3D


## Adds a flash at [param pos] (world) under the ships' space root of
## [param ctx]'s system.
static func flash(ctx: Node, pos: Vector3, size: float = 30.0) -> void:
	if ctx == null or not ctx.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var fx := WarpFx.new()
	fx._size = size
	SpaceNav.space_root(ctx).add_child(fx)
	fx.global_position = pos


func _ready() -> void:
	if _mesh == null:
		_mesh = SphereMesh.new()
		_mesh.radius = 1.0
		_mesh.height = 2.0
		_mesh.radial_segments = 16
		_mesh.rings = 8
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_mat.no_depth_test = true
		_mat.albedo_color = Color(COLOR, 0.9)
	_ball = MeshInstance3D.new()
	_ball.mesh = _mesh
	_ball.material_override = _mat.duplicate()
	_ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ball.layers = Ship.RENDER_LAYER
	add_child(_ball)
	_light = OmniLight3D.new()
	_light.light_color = COLOR
	_light.omni_range = _size * 5.0
	_light.light_energy = 6.0
	_light.light_cull_mask = Ship.RENDER_LAYER
	add_child(_light)
	_apply()


func _process(delta: float) -> void:
	if SimClock.paused:
		return
	_age += delta * SimClock.speed
	if _age >= LIFE:
		queue_free()
		return
	_apply()


func _apply() -> void:
	var k := clampf(_age / LIFE, 0.0, 1.0)
	_ball.scale = Vector3.ONE * _size * lerpf(0.4, 1.6, sqrt(k))
	(_ball.material_override as StandardMaterial3D).albedo_color = Color(COLOR, 0.9 * (1.0 - k))
	_light.light_energy = 6.0 * (1.0 - k)

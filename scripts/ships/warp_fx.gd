class_name WarpFx
extends Node3D
## A short flash where a ship enters or leaves a warp hop (or a gate's
## portal, GateTransit; a den or claim group warping in): a camera-facing
## HDR flash (shaders/warp_flash.gdshader) that peaks fast and fades over
## the life, a thin shock ring (shaders/warp_ring.gdshader) expanding a
## little longer, across [param axis] (camera-facing without one), and a
## brief light. Sim time (frozen while paused). Both sizes are clamped on
## screen by the shaders, so a flash reads at close zoom and stays a small
## dot at system zoom. Pooled per space root: a finished flash hides and
## waits for the next one, nothing is allocated per frame.

const LIFE := 0.6
const COLOR := Color(0.62, 0.85, 1.0)
## The ring outlives the flash by this factor (at least RING_MIN_LIFE).
const RING_LIFE := 1.7
const RING_MIN_LIFE := 0.6
## The ring grows to this times the flash size.
const RING_SPREAD := 1.35
const POOL_META := &"warp_fx_pool"
const FLASH_SHADER := preload("res://shaders/warp_flash.gdshader")
const RING_SHADER := preload("res://shaders/warp_ring.gdshader")
## Culling box of the camera-sized quads (the shaders move the vertices).
const CULL := AABB(Vector3(-4000.0, -4000.0, -4000.0), Vector3(8000.0, 8000.0, 8000.0))

static var _quad: QuadMesh
static var _flash_mat: ShaderMaterial
static var _ring_mat: ShaderMaterial

var _age: float = 0.0
var _size: float = 30.0
var _color: Color = COLOR
var _life: float = LIFE
var _ring_life: float = RING_MIN_LIFE
var _axis := Vector3.ZERO
var _flash: MeshInstance3D
var _ring: MeshInstance3D
var _light: OmniLight3D
var _pool: Array
## A prewarm run: drawn for its short life at alpha 0.
var _silent := false


## Adds a flash at [param pos] (world) under the ships' space root of
## [param ctx]'s system. Gate jumps pass the portal colour, a longer life
## and the portal axis; ship hops their heading.
static func flash(ctx: Node, pos: Vector3, size: float = 30.0, color: Color = COLOR, life: float = LIFE, axis: Vector3 = Vector3.ZERO) -> void:
	if ctx == null or not ctx.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var pool := _pool_of(ctx)
	var fx: WarpFx = pool.pop_back() if not pool.is_empty() else _make(ctx, pool)
	fx._start(pos, size, color, maxf(life, 0.05), axis)


## Puts one idle flash in [param ctx]'s system ahead of time (a spooling
## ship), so its shaders are compiled before the jump: a flash on a material
## seen for the first time can miss its first frames.
static func prewarm(ctx: Node) -> void:
	if ctx == null or not ctx.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var pool := _pool_of(ctx)
	if pool.is_empty():
		var fx := _make(ctx, pool)
		fx._silent = true
		fx._start((ctx as Node3D).global_position if ctx is Node3D else Vector3.ZERO, 1.0, COLOR, 0.1, Vector3.ZERO)


static func _pool_of(ctx: Node) -> Array:
	var root := SpaceNav.space_root(ctx)
	if not root.has_meta(POOL_META):
		root.set_meta(POOL_META, [])
	return root.get_meta(POOL_META)


static func _make(ctx: Node, pool: Array) -> WarpFx:
	var fx := WarpFx.new()
	fx._pool = pool
	SpaceNav.space_root(ctx).add_child(fx)
	return fx


## The shared quad and the two materials (WarpVisuals' drive ring uses the ring one).
static func quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	return _quad


static func ring_material() -> ShaderMaterial:
	if _ring_mat == null:
		_ring_mat = ShaderMaterial.new()
		_ring_mat.shader = RING_SHADER
	return _ring_mat


static func _flash_material() -> ShaderMaterial:
	if _flash_mat == null:
		_flash_mat = ShaderMaterial.new()
		_flash_mat.shader = FLASH_SHADER
	return _flash_mat


func _ready() -> void:
	_flash = _quad_instance(_flash_material())
	_ring = _quad_instance(ring_material())
	_light = OmniLight3D.new()
	_light.light_cull_mask = Ship.RENDER_LAYER
	_light.shadow_enabled = false
	add_child(_light)


func _quad_instance(mat: ShaderMaterial) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = quad()
	mi.material_override = mat
	mi.custom_aabb = CULL
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = Ship.RENDER_LAYER
	add_child(mi)
	return mi


func _start(pos: Vector3, size: float, color: Color, life: float, axis: Vector3) -> void:
	_age = 0.0
	_size = size
	_color = color
	_life = life
	_ring_life = maxf(life * RING_LIFE, RING_MIN_LIFE)
	_axis = axis.normalized() if axis.length_squared() > 1e-6 else Vector3.ZERO
	global_position = pos
	_flash.set_instance_shader_parameter(&"fx_tint", color)
	_ring.set_instance_shader_parameter(&"ring_tint", color)
	_ring.set_instance_shader_parameter(&"ring_normal", _axis)
	_light.light_color = color
	_light.omni_range = size * 5.0
	visible = true
	set_process(true)
	_apply()


func _process(delta: float) -> void:
	if SimClock.paused:
		return
	_age += delta * SimClock.speed
	if _age >= maxf(_life, _ring_life):
		_idle()
		return
	_apply()


## Hidden and back in the pool. The quads stay in the tree (alpha 0) so
## their pipelines stay warm.
func _idle() -> void:
	_silent = false
	_flash.set_instance_shader_parameter(&"fx_alpha", 0.0)
	_ring.set_instance_shader_parameter(&"ring_alpha", 0.0)
	_light.light_energy = 0.0
	visible = false
	set_process(false)
	_pool.append(self)


func _apply() -> void:
	if _silent:
		_flash.set_instance_shader_parameter(&"fx_alpha", 0.0)
		_ring.set_instance_shader_parameter(&"ring_alpha", 0.0)
		_light.light_energy = 0.0
		return
	# Flash: a near-instant rise, then a fast fall.
	var k := clampf(_age / _life, 0.0, 1.0)
	var e := smoothstep(0.0, 0.07, k) * pow(1.0 - k, 2.2)
	_flash.visible = k < 1.0
	_flash.set_instance_shader_parameter(&"fx_radius", _size * lerpf(0.8, 1.1, sqrt(k)))
	_flash.set_instance_shader_parameter(&"fx_alpha", e)
	_light.light_energy = 5.0 * e
	# Ring: eases out from the flash, thinning as it goes.
	var kr := clampf(_age / _ring_life, 0.0, 1.0)
	var grow := 1.0 - pow(1.0 - kr, 3.0)
	_ring.set_instance_shader_parameter(&"ring_radius", _size * lerpf(0.35, RING_SPREAD, grow))
	_ring.set_instance_shader_parameter(&"ring_grow", lerpf(0.25, 1.0, grow))
	_ring.set_instance_shader_parameter(&"ring_width", lerpf(0.05, 0.012, grow))
	_ring.set_instance_shader_parameter(&"ring_alpha", smoothstep(0.0, 0.05, kr) * pow(1.0 - kr, 2.6) * 0.8)

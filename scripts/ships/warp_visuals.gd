class_name WarpVisuals
extends Node3D
## The look of one ship's warp hops (visuals only; ShipMover owns the hop).
## Made by Ship on the first warp (never headless), fed
## [method on_warp_changed] and [method update] from Ship's visuals.
## - Spool: a thin charging ring across the drive fades in and pulses, a few
##   drive sparks, and [method glow_boost] brightens and pulses the engines.
## - Jump-out: a flash and shock ring at the drive (WarpFx), the hull
##   stretches along its heading for [constant STRETCH_OUT] s, then hides.
## - In the hop: a thin tapered light trail (shaders/warp_trail.gdshader)
##   from the ship back along its 3D line, as long as the camera distance
##   allows ([constant TRAIL_MIN]..[constant TRAIL_MAX]), never past the
##   jump point.
## - Drop-in: a flash and ring at the arrival point, the hull relaxes from
##   stretched over [constant STRETCH_IN] s, a short engine flare, and the
##   trail's tail runs in to the drop point at warp speed and fades.
## Shared meshes and materials (instance uniforms), no per-frame allocations.

const TRAIL_SHADER := preload("res://shaders/warp_trail.gdshader")
const GLOW_SHADER := preload("res://shaders/fx_glow.gdshader")
const STRETCH_OUT := 0.16
const STRETCH_IN := 0.42
## Hull scale at full stretch: length, width.
const STRETCH_LEN := 3.2
const STRETCH_WIDTH := 0.5
const FLARE_TIME := 0.9
const TRAIL_MIN := 500.0
const TRAIL_MAX := 4000.0
## Trail length per metre of camera distance.
const TRAIL_PER_CAM := 0.45
const TRAIL_CULL := AABB(Vector3(-4500.0, -4500.0, -4500.0), Vector3(9000.0, 9000.0, 9000.0))

static var _trail_mat: ShaderMaterial
static var _spark_mat: ShaderMaterial
static var _spark_mesh: QuadMesh
static var _spark_ramp: Gradient

var ship: Ship
## Faction/role tint (the white core is mixed in by the shaders).
var tint: Color = HudStyle.HOLO

var _model: Node3D
var _drive: Node3D
var _trail: MeshInstance3D
var _charge: MeshInstance3D
var _sparks: CPUParticles3D
var _state: ShipMover.Warp = ShipMover.Warp.IDLE
var _pulse := 0.0
var _charge_k := 0.0
var _flare := 0.0
## Hull stretch: -1 idle, else seconds into it; _stretch_in false = jumping out.
var _stretch_t := -1.0
var _stretch_in := false
var _base_scale := Vector3.ONE
var _hidden := false
## Trail: where the hop began, its head and axis (head to tail), fading after drop-out.
var _jump_from := Vector3.ZERO
var _trail_len := 0.0
var _trail_alpha := 0.0
var _trail_fading := false
var _last_pos := Vector3.ZERO


## [param model] is the hull node to stretch and hide; [param drive] the
## engine glow node (null: the drive sits behind the hull).
func setup(owner_ship: Ship, model: Node3D, drive: Node3D, color: Color) -> void:
	ship = owner_ship
	_model = model
	_drive = drive
	tint = color
	name = "WarpVisuals"


func _ready() -> void:
	if _trail_mat == null:
		_trail_mat = ShaderMaterial.new()
		_trail_mat.shader = TRAIL_SHADER
		_spark_mat = ShaderMaterial.new()
		_spark_mat.shader = GLOW_SHADER
		_spark_mat.set_shader_parameter(&"glow_color", Color(0.8, 0.93, 1.0))
		_spark_mat.set_shader_parameter(&"size", 1.0)
		_spark_mat.set_shader_parameter(&"min_px", 1.5)
		_spark_mat.set_shader_parameter(&"energy", 3.0)
		_spark_mesh = QuadMesh.new()
		_spark_mesh.size = Vector2.ONE
		_spark_mesh.material = _spark_mat
		_spark_ramp = Gradient.new()
		_spark_ramp.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		_spark_ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	_trail = MeshInstance3D.new()
	_trail.name = "WarpTrail"
	_trail.mesh = WarpFx.quad()
	_trail.material_override = _trail_mat
	_trail.custom_aabb = TRAIL_CULL
	_trail.top_level = true
	_trail.visible = false
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail.layers = Ship.RENDER_LAYER
	_trail.set_instance_shader_parameter(&"trail_tint", tint)
	_trail.set_instance_shader_parameter(&"trail_width", 0.8 + ship.hit_radius * 0.07)
	add_child(_trail)
	_charge = MeshInstance3D.new()
	_charge.name = "DriveRing"
	_charge.mesh = WarpFx.quad()
	_charge.material_override = WarpFx.ring_material()
	_charge.custom_aabb = WarpFx.CULL
	_charge.visible = false
	_charge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_charge.layers = Ship.RENDER_LAYER
	_charge.set_instance_shader_parameter(&"ring_tint", tint.lerp(Color.WHITE, 0.3))
	_charge.set_instance_shader_parameter(&"ring_grow", 0.3)
	add_child(_charge)
	_sparks = CPUParticles3D.new()
	_sparks.name = "DriveSparks"
	_sparks.emitting = false
	_sparks.amount = 14
	_sparks.lifetime = 0.7
	_sparks.local_coords = false
	_sparks.mesh = _spark_mesh
	_sparks.direction = Vector3(0.0, 0.0, 1.0)
	_sparks.spread = 28.0
	_sparks.gravity = Vector3.ZERO
	_sparks.initial_velocity_min = 4.0 + ship.hit_radius * 0.6
	_sparks.initial_velocity_max = 10.0 + ship.hit_radius * 1.6
	_sparks.damping_min = 6.0
	_sparks.damping_max = 12.0
	_sparks.scale_amount_min = 0.35 + ship.hit_radius * 0.03
	_sparks.scale_amount_max = 0.7 + ship.hit_radius * 0.06
	_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_sparks.emission_sphere_radius = ship.hit_radius * 0.15
	_sparks.color = tint.lerp(Color.WHITE, 0.55)
	_sparks.color_ramp = _spark_ramp
	_sparks.layers = Ship.RENDER_LAYER
	_sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sparks)
	_last_pos = ship.global_position
	WarpFx.prewarm(ship)


## Engine emission multiplier: charging pulse while spooling, a flare after drop-in.
func glow_boost() -> float:
	var b := 1.0
	if _state == ShipMover.Warp.SPOOL:
		b = (1.0 + 1.4 * _charge_k) * (1.0 + 0.3 * _charge_k * sin(_pulse))
	if _flare > 0.0:
		var f := _flare / FLARE_TIME
		b = maxf(b, 1.0 + 2.2 * f * f)
	return b


func on_warp_changed(state: ShipMover.Warp) -> void:
	var prev := _state
	_state = state
	if state == ShipMover.Warp.SPOOL:
		_pulse = 0.0
		_charge_k = 0.0
	elif state == ShipMover.Warp.WARP:
		_jump_out()
	elif prev == ShipMover.Warp.WARP:
		_drop_in()
	if state != ShipMover.Warp.SPOOL:
		_charge.visible = false
		_sparks.emitting = false


func _jump_out() -> void:
	var fwd := -ship.global_basis.z
	WarpFx.flash(ship, _drive_pos(), _burst_size(), tint.lerp(Color.WHITE, 0.25), 0.26, fwd)
	_jump_from = ship.global_position
	_last_pos = _jump_from
	_trail_len = 0.0
	_trail_alpha = 0.0
	_trail_fading = false
	_begin_stretch(false)


func _drop_in() -> void:
	var fwd := -ship.global_basis.z
	WarpFx.flash(ship, ship.global_position + fwd * ship.hit_radius * 0.5, _burst_size(), tint.lerp(Color.WHITE, 0.25), 0.3, fwd)
	_show_model()
	_begin_stretch(true)
	_flare = FLARE_TIME
	_trail_fading = true


func _burst_size() -> float:
	return 6.0 + ship.hit_radius * 1.4


func _drive_pos() -> Vector3:
	if _drive and is_instance_valid(_drive):
		return _drive.global_position
	return ship.global_position + ship.global_basis.z * ship.hit_radius * 0.7


## Called every visual frame by Ship with the sim step (0 while paused).
func update(dt: float) -> void:
	if ship.mover.warp_state != _state:
		# A state the signal did not bring (a restored or followed hop).
		on_warp_changed(ship.mover.warp_state)
	_update_spool(dt)
	_update_stretch(dt)
	_update_trail(dt)
	if _flare > 0.0:
		_flare = maxf(_flare - dt, 0.0)


func _update_spool(dt: float) -> void:
	if _state != ShipMover.Warp.SPOOL:
		return
	_charge_k = 1.0 - clampf(ship.mover.warp_timer / SpaceNav.WARP_SPOOL, 0.0, 1.0)
	_pulse += dt * TAU * lerpf(1.5, 6.0, _charge_k)
	var k := _charge_k
	_charge.visible = true
	_charge.global_position = _drive_pos()
	_charge.set_instance_shader_parameter(&"ring_normal", ship.global_basis.z)
	_charge.set_instance_shader_parameter(&"ring_radius", ship.hit_radius * (0.32 + 0.14 * k) * (1.0 + 0.04 * sin(_pulse)))
	_charge.set_instance_shader_parameter(&"ring_width", lerpf(0.08, 0.04, k))
	_charge.set_instance_shader_parameter(&"ring_alpha", (0.06 + 0.45 * k * k) * (0.8 + 0.2 * sin(_pulse)))
	_sparks.global_position = _drive_pos()
	_sparks.emitting = k > 0.3


func _begin_stretch(arriving: bool) -> void:
	if _model == null or not is_instance_valid(_model):
		return
	if _stretch_t < 0.0:
		_base_scale = _model.scale
	_stretch_in = arriving
	_stretch_t = 0.0
	_apply_stretch()


func _update_stretch(dt: float) -> void:
	if _stretch_t < 0.0 or _model == null or not is_instance_valid(_model):
		return
	_stretch_t += dt
	var done := _stretch_t >= (STRETCH_IN if _stretch_in else STRETCH_OUT)
	if done:
		_stretch_t = -1.0
		_model.scale = _base_scale
		if not _stretch_in and _state == ShipMover.Warp.WARP:
			_model.visible = false
			_hidden = true
		return
	_apply_stretch()


func _apply_stretch() -> void:
	var k: float
	if _stretch_in:
		var a := clampf(_stretch_t / STRETCH_IN, 0.0, 1.0)
		k = pow(1.0 - a, 3.0)
	else:
		var a := clampf(_stretch_t / STRETCH_OUT, 0.0, 1.0)
		k = a * a
	var w := lerpf(1.0, STRETCH_WIDTH, k)
	_model.scale = Vector3(_base_scale.x * w, _base_scale.y * w, _base_scale.z * lerpf(1.0, STRETCH_LEN, k))


func _show_model() -> void:
	if _hidden and _model and is_instance_valid(_model):
		_model.visible = true
	_hidden = false


func _update_trail(dt: float) -> void:
	var pos := ship.global_position
	if _state == ShipMover.Warp.WARP:
		if _trail_fading or not _trail.visible:
			# Into a hop without the jump-out (restored mid-hop).
			if not _trail.visible:
				_jump_from = pos
			_trail_fading = false
		var moved := _last_pos - pos
		if moved.length_squared() > 0.01:
			_trail.set_instance_shader_parameter(&"trail_axis", moved.normalized())
		_trail_len = minf(_jump_from.distance_to(pos), _max_trail())
		_trail_alpha = minf(_trail_alpha + dt / 0.12, 1.0)
		_trail.global_position = pos
		_trail.visible = true
	elif _trail.visible:
		if not _trail_fading:
			_trail_fading = true
		_trail_len -= SpaceNav.WARP_SPEED * dt
		_trail_alpha = maxf(_trail_alpha - dt / 0.6, 0.0)
		if _trail_len <= 1.0 or _trail_alpha <= 0.0:
			_trail.visible = false
	if _trail.visible:
		_trail.set_instance_shader_parameter(&"trail_len", maxf(_trail_len, 1.0))
		_trail.set_instance_shader_parameter(&"trail_alpha", _trail_alpha)
	_last_pos = pos


func _max_trail() -> float:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return TRAIL_MIN
	return clampf(cam.global_position.distance_to(ship.global_position) * TRAIL_PER_CAM, TRAIL_MIN, TRAIL_MAX)

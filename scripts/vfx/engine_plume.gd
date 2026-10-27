class_name EnginePlume
extends MeshInstance3D
## A ship's drive plume (shaders/vfx_plume.gdshader): a thin hot exhaust
## cone from the model's "engine_glow" nozzle plane back along +Z, on top of
## the model's own flame mesh. Its length and brightness follow thrust the
## way Ship's glow does (idle: a short soft tongue, full burn: about two hull
## lengths, warp: brighter and longer); parked it is off. Pixel floors in the
## shader keep a burning drive readable as a small tick at system zoom.
## Child of the model (banks, pitches and hides with it). Never headless.

const SHADER := preload("res://shaders/vfx_plume.gdshader")
const PLAYER_TINT := Color(0.55, 0.75, 1.0)
const HOSTILE_TINT := Color(1.0, 0.62, 0.36)
## Hidden beyond this camera distance, metres.
const MAX_CAM := 12000.0

static var _quad: QuadMesh
static var _mat: ShaderMaterial

var ship: Ship
var _level := 0.0
var _width := 1.2
var _full := 16.0


## Adds a plume to [param s] at its engine glow node (no glow: nothing).
static func attach(s: Ship, model: Node3D, glow: Node3D) -> void:
	if s == null or model == null or glow == null or Vfx.headless():
		return
	var p := EnginePlume.new()
	p.ship = s
	p.name = "EnginePlume"
	model.add_child(p)
	var rel := model.global_transform.affine_inverse() * glow.global_transform
	p.transform = Transform3D(rel.basis.orthonormalized(), rel.origin)
	var w := 0.0
	for mi in ModelLoader.meshes_of(glow):
		var box := mi.get_aabb()
		var sc := mi.global_basis.get_scale()
		w = maxf(w, maxf(box.size.x * sc.x, box.size.y * sc.y))
	p._width = clampf(w * 0.7, 0.5, 6.0) if w > 0.0 else 1.2
	p._full = clampf(s.hit_radius * 2.2, 6.0, 60.0)


func _ready() -> void:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
	mesh = _quad
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	layers = Ship.RENDER_LAYER
	# The shader places the vertices: cull on the plume's reach.
	custom_aabb = AABB(Vector3(-80.0, -80.0, -10.0), Vector3(160.0, 160.0, 160.0))
	set_instance_shader_parameter(&"pl_tint", HOSTILE_TINT if ship and ship.faction == Combat.Faction.SCAVENGER else PLAYER_TINT)
	set_instance_shader_parameter(&"pl_width", _width)


func _process(delta: float) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	var m := ship.mover
	var parked := ship.is_docked() and m.path_done() and m.velocity.length() < 0.5
	var want := 0.0
	var boost := 1.0
	if not parked:
		var speed_part := clampf(m.relative_speed() / maxf(ship.max_speed, 1.0), 0.0, 1.0)
		want = clampf(maxf(m.thrust, speed_part * 0.4) + 0.08, 0.0, 1.0)
		if m.warp_state != ShipMover.Warp.IDLE:
			want = 1.0
			boost = 1.6
	_level = lerpf(_level, want, clampf(delta * 6.0, 0.0, 1.0))
	var cam := get_viewport().get_camera_3d()
	var far := cam != null and cam.global_position.distance_to(global_position) > MAX_CAM
	visible = _level > 0.03 and not far
	if not visible:
		return
	var flick := 0.93 + 0.07 * sin(Time.get_ticks_msec() * 0.047 + float(get_instance_id() % 97))
	set_instance_shader_parameter(&"pl_len", _full * lerpf(0.15, 1.0, _level) * boost * flick)
	set_instance_shader_parameter(&"pl_alpha", lerpf(0.25, 1.0, _level) * minf(boost, 1.3))

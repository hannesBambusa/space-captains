class_name TargetMarker
extends Control
## Screen overlay: corner brackets around the object under a hovered overview
## row (dim) and around the selected building (accent). Ignores the mouse.

const HOVER_COLOR := Color(0.85, 0.9, 1.0, 0.75)
const SELECT_COLOR := Color(1.0, 0.62, 0.26, 0.95)

@export var min_px: float = 12.0
@export var max_px: float = 160.0
## The selected building already has a ring on the plane; brackets only help
## once it is smaller than this on screen (pixels, radius).
@export var select_bracket_below_px: float = 28.0

var hover_target: Node3D:
	set(v):
		hover_target = v
		queue_redraw()
var select_target: Node3D:
	set(v):
		select_target = v
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	if is_instance_valid(hover_target) or is_instance_valid(select_target):
		queue_redraw()


func _draw() -> void:
	if is_instance_valid(select_target) and select_target != hover_target:
		_bracket(select_target, SELECT_COLOR, select_bracket_below_px)
	if is_instance_valid(hover_target):
		_bracket(hover_target, SELECT_COLOR if hover_target == select_target else HOVER_COLOR)


func _bracket(target: Node3D, color: Color, only_below_px: float = INF) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or not target.is_inside_tree():
		return
	var p := target.global_position
	if cam.is_position_behind(p):
		return
	var px_per_rad := get_viewport_rect().size.y / (2.0 * tan(deg_to_rad(cam.fov) * 0.5))
	var d := maxf(cam.global_position.distance_to(p), 1.0)
	var raw := float(target.get_meta(&"focus_radius", 40.0)) / d * px_per_rad
	if raw >= only_below_px:
		return
	var r := clampf(raw * 1.15, min_px, max_px)
	var c := cam.unproject_position(p)
	var arm := clampf(r * 0.45, 5.0, 18.0)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := c + Vector2(sx, sy) * r
			draw_line(corner, corner - Vector2(sx * arm, 0.0), color, 1.5, true)
			draw_line(corner, corner - Vector2(0.0, sy * arm), color, 1.5, true)

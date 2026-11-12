class_name EdgeShade
extends Control
## Soft dark gradients along the screen edges, under every HUD widget, so the
## nearly clear flight ops panels and text stay readable over a bright star or
## planet (ongoing-implementations/hud-flight-ops.md). Full rect, never takes
## input. Sizes are in HUD pixels (the 1920x1080 layout).

## Width of the left shade (the overview column).
const LEFT := 560.0
## Height of the bottom shade (the timeline and the feed).
const BOTTOM := 260.0
## Height of the top shade (title, resources, time).
const TOP := 150.0
## Width of the right shade (the minimap and the pilot column).
const RIGHT := 440.0

var _tex: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex["left"] = _ramp(Vector2(0, 0), Vector2(1, 0), 0.72)
	_tex["right"] = _ramp(Vector2(1, 0), Vector2(0, 0), 0.5)
	_tex["bottom"] = _ramp(Vector2(0, 1), Vector2(0, 0), 0.78)
	_tex["top"] = _ramp(Vector2(0, 0), Vector2(0, 1), 0.6)
	resized.connect(queue_redraw)


func _draw() -> void:
	var s := size
	draw_texture_rect(_tex["left"], Rect2(0, 0, LEFT, s.y), false)
	draw_texture_rect(_tex["right"], Rect2(s.x - RIGHT, 0, RIGHT, s.y), false)
	draw_texture_rect(_tex["bottom"], Rect2(0, s.y - BOTTOM, s.x, BOTTOM), false)
	draw_texture_rect(_tex["top"], Rect2(0, 0, s.x, TOP), false)


## Black at [param alpha] at [param from], clear at [param to], eased so the
## fade has no visible edge.
static func _ramp(from: Vector2, to: Vector2, alpha: float) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, alpha), Color(0, 0, 0, alpha * 0.45), Color(0, 0, 0, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = from
	t.fill_to = to
	t.width = 64
	t.height = 64
	return t

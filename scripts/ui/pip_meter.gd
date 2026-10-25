class_name PipMeter
extends Control
## Small drawn meter. PIPS: [member max_value] squares with [member value]
## lit. BAR: a thin bar filled to value / max_value. Lit colour is fixed, or
## runs green -> amber -> red with the value when [member graded] is on.

enum Style { PIPS, BAR }

const GOOD := Color(0.35, 0.9, 0.5)
const MID := Color(1.0, 0.78, 0.25)
const BAD := Color(1.0, 0.32, 0.26)
const OFF := Color(0.62, 0.72, 0.86, 0.16)

@export var style: Style = Style.PIPS
@export var max_value: float = 5.0
@export var value: float = 0.0:
	set(v):
		value = v
		queue_redraw()
@export var graded: bool = false
@export var color: Color = Color(1.0, 0.6, 0.24)
@export var pip_size: float = 7.0
@export var pip_gap: float = 3.0
## PIPS stacked bottom to top (signal bars, each a bit taller) instead of in a row.
@export var vertical: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if style == Style.PIPS and vertical:
		custom_minimum_size = Vector2(max_value * (pip_size + 1.0) - 1.0, pip_size * 3.0)
	elif style == Style.PIPS:
		custom_minimum_size = Vector2(max_value * (pip_size + pip_gap) - pip_gap, pip_size)
	elif custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(44.0, 5.0)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


## Green at 0, amber halfway, red at 1.
static func grade(t: float) -> Color:
	t = clampf(t, 0.0, 1.0)
	return GOOD.lerp(MID, t * 2.0) if t < 0.5 else MID.lerp(BAD, (t - 0.5) * 2.0)


func _lit_color() -> Color:
	if not graded:
		return color
	return grade((value - 1.0) / maxf(max_value - 1.0, 1.0)) if style == Style.PIPS else grade(value / maxf(max_value, 0.001))


func _draw() -> void:
	var lit := _lit_color()
	if style == Style.PIPS and vertical:
		var n := int(max_value)
		var base := (size.y + pip_size * 3.0) * 0.5
		for i in n:
			var hgt := pip_size * 3.0 * float(i + 1) / float(n)
			var r := Rect2(Vector2(float(i) * (pip_size + 1.0), base - hgt), Vector2(pip_size, hgt))
			draw_rect(r, lit if float(i) < value else OFF)
	elif style == Style.PIPS:
		var n := int(max_value)
		var y := (size.y - pip_size) * 0.5
		for i in n:
			var r := Rect2(Vector2(float(i) * (pip_size + pip_gap), y), Vector2(pip_size, pip_size))
			draw_rect(r, lit if float(i) < value else OFF)
	else:
		var h := minf(size.y, custom_minimum_size.y)
		var y := (size.y - h) * 0.5
		draw_rect(Rect2(0.0, y, size.x, h), OFF)
		var f := clampf(value / maxf(max_value, 0.001), 0.0, 1.0)
		draw_rect(Rect2(0.0, y, size.x * f, h), lit)

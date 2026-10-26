class_name TutorialPulse
extends Control
## Pulsing amber frame drawn over the build bar tile the current tutorial
## step needs ([member target]; null = nothing drawn). Full-rect overlay that
## ignores the mouse, so the tile stays clickable.

const H := preload("res://scripts/ui/theme/hud_style.gd")

## Pulses per second.
@export var speed: float = 1.4
@export var grow_px: float = 3.0

var target: Control:
	set(v):
		target = v
		set_process(v != null)
		queue_redraw()

var _t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(target != null)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if target == null or not is_instance_valid(target) or not target.is_visible_in_tree():
		return
	var r := target.get_global_rect()
	r.position -= get_global_rect().position
	var k := 0.5 + 0.5 * sin(_t * TAU * speed)
	var g := grow_px * (1.0 + k)
	r = r.grow(g)
	draw_rect(r, Color(H.ACCENT, 0.35 + 0.55 * k), false, 2.0)
	draw_rect(r.grow(3.0), Color(H.ACCENT, 0.15 * k), false, 4.0)

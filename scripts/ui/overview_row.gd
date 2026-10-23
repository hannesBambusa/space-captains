class_name OverviewRow
extends Button
## One clickable line in the system overview: title, dim subtitle and an
## optional widget on the right (meters). Pressed state = the camera is
## following this row's target.

signal hovered(row: OverviewRow, on: bool)

const INDENT_PX := 18.0

var target: Node3D
var title_label: Label
var subtitle_label: Label
var right_box: HBoxContainer


func _init(row_target: Node3D, title: String, subtitle: String = "", depth: int = 0) -> void:
	target = row_target
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	theme_type_variation = &"RowButton"
	custom_minimum_size = Vector2(0.0, 26.0)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 8.0 + INDENT_PX * float(depth)
	h.offset_right = -8.0
	h.add_theme_constant_override("separation", 8)
	add_child(h)
	if depth > 0:
		var tick := UIUtil.label("·", &"DimLabel")
		h.add_child(tick)
	title_label = UIUtil.label(title)
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.size_flags_stretch_ratio = 1.4
	h.add_child(title_label)
	subtitle_label = UIUtil.label(subtitle, &"DimLabel")
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	subtitle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subtitle_label.clip_text = true
	subtitle_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(subtitle_label)
	right_box = HBoxContainer.new()
	right_box.add_theme_constant_override("separation", 6)
	right_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_box.visible = false
	h.add_child(right_box)
	UIUtil.ignore_mouse(self)
	mouse_entered.connect(func() -> void: hovered.emit(self, true))
	mouse_exited.connect(func() -> void: hovered.emit(self, false))


func set_subtitle(text: String) -> void:
	if subtitle_label.text != text:
		subtitle_label.text = text


## Adds a widget on the right edge (meter, value label).
func add_right(widget: Control) -> void:
	widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_box.add_child(widget)
	right_box.visible = true

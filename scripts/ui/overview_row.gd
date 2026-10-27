class_name OverviewRow
extends Button
## One clickable line in a list: a name cell (indent, an optional lead chip
## or icon, the title), a dim detail, an optional mono value and widgets on
## the right (meters, badges). Pressed state = the camera is following this
## row's target (or it is selected).
## [method make_dense] gives the left panel's look: fixed height, aligned
## columns (the name cell carries the indent, so the detail and value
## columns line up under each other), a hairline under the row and a live
## [RichTooltip] (full name, details) that stays open while the row's text
## changes.

signal hovered(row: OverviewRow, on: bool)

const INDENT_PX := 18.0

var target: Node3D
var depth := 0
var title_label: Label
var subtitle_label: Label
## Mono value column (distance, hires, percent); hidden until [method set_value].
var value_label: Label
var right_box: HBoxContainer
## RichTooltip content: builder.call(tip). Without one the tooltip shows the
## title and the lines of tooltip_text.
var tip_builder: Callable
## On: the tooltip is a live RichTooltip under a stable key.
var rich_tip := false
## The tooltip's accent bar colour.
var tip_accent: Color = HudStyle.HOLO

var _name_box: HBoxContainer
var _lead: Control
var _lead_color := Color.WHITE
var _lead_round := false
var _hairline: ColorRect
var _badge: Label
var _badge_color := Color.TRANSPARENT


func _init(row_target: Node3D, title: String, subtitle: String = "", row_depth: int = 0) -> void:
	target = row_target
	depth = row_depth
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	theme_type_variation = &"RowButton"
	custom_minimum_size = Vector2(0.0, 26.0)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var h := HBoxContainer.new()
	h.name = "Cells"
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 8.0
	h.offset_right = -8.0
	h.add_theme_constant_override("separation", 8)
	add_child(h)
	_name_box = HBoxContainer.new()
	_name_box.add_theme_constant_override("separation", 6)
	_name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_box.size_flags_stretch_ratio = 1.4
	h.add_child(_name_box)
	if depth > 0:
		_name_box.add_child(_tree_mark())
	title_label = UIUtil.label(title)
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.size_flags_stretch_ratio = 1.4
	# Owners set the title's stretch ratio; the name cell is what stretches.
	title_label.size_flags_changed.connect(func() -> void: _name_box.size_flags_stretch_ratio = title_label.size_flags_stretch_ratio)
	_name_box.add_child(title_label)
	subtitle_label = UIUtil.label(subtitle, &"DimLabel")
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	subtitle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subtitle_label.clip_text = true
	subtitle_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(subtitle_label)
	value_label = UIUtil.label("", &"NumberLabel")
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.visible = false
	h.add_child(value_label)
	right_box = HBoxContainer.new()
	right_box.add_theme_constant_override("separation", 6)
	right_box.alignment = BoxContainer.ALIGNMENT_END
	right_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_box.visible = false
	h.add_child(right_box)
	UIUtil.ignore_mouse(self)
	mouse_entered.connect(func() -> void: hovered.emit(self, true))
	mouse_exited.connect(func() -> void: hovered.emit(self, false))


## The left panel's look: [param font_size] for the title (detail one
## smaller, value two), [param row_height] px, the detail left-aligned in
## its column, the value column [param value_width] px wide (0 = none),
## the right column [param right_width] px (0 = as wide as its widgets),
## a hairline under the row and the live rich tooltip.
func make_dense(font_size: int, row_height: float, value_width: float = 0.0, right_width: float = 0.0) -> void:
	custom_minimum_size.y = row_height
	var h := get_node(^"Cells") as HBoxContainer
	h.offset_left = 6.0
	h.offset_right = -6.0
	h.add_theme_constant_override("separation", 6)
	title_label.add_theme_font_size_override("font_size", font_size)
	subtitle_label.add_theme_font_size_override("font_size", font_size - 1)
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	value_label.add_theme_font_override("font", HudStyle.mono("Regular"))
	value_label.add_theme_font_size_override("font_size", font_size - 2)
	value_label.add_theme_color_override("font_color", HudStyle.TEXT)
	value_label.custom_minimum_size.x = value_width
	value_label.visible = value_width > 0.0
	if right_width > 0.0:
		right_box.custom_minimum_size.x = right_width
		right_box.visible = true
	if _hairline == null:
		_hairline = ColorRect.new()
		_hairline.color = Color(HudStyle.HAIRLINE, 0.75)
		_hairline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hairline.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		_hairline.offset_top = -1.0
		_hairline.offset_left = 6.0 + (INDENT_PX if depth > 0 else 0.0)
		_hairline.offset_right = -6.0
		add_child(_hairline)
	rich_tip = true


func set_subtitle(text: String) -> void:
	if subtitle_label.text != text:
		subtitle_label.text = text


## The value column's text (mono), in [param color].
func set_value(text: String, color: Color = HudStyle.TEXT) -> void:
	if value_label.text != text:
		value_label.text = text
	value_label.add_theme_color_override("font_color", color)


## Adds a widget on the right edge (meter, value label).
func add_right(widget: Control) -> void:
	widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_box.add_child(widget)
	right_box.visible = true


## A small coloured square (or dot with [param rounded]) before the title.
func set_lead_chip(color: Color, rounded: bool = false, px: float = 8.0) -> void:
	_lead_color = color
	_lead_round = rounded
	if _lead == null or _lead is TextureRect:
		if _lead:
			_lead.queue_free()
		var c := Control.new()
		c.custom_minimum_size = Vector2(px, px)
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.draw.connect(func() -> void:
			var s := c.size
			if _lead_round:
				c.draw_circle(s * 0.5, s.x * 0.5, _lead_color)
				c.draw_arc(s * 0.5, s.x * 0.5, 0.0, TAU, 16, Color(_lead_color.lerp(Color.WHITE, 0.45), 0.6), 1.0, true)
			else:
				c.draw_rect(Rect2(Vector2.ZERO, s), _lead_color)
				c.draw_rect(Rect2(Vector2.ZERO, s), Color(_lead_color.lerp(Color.WHITE, 0.45), 0.6), false, 1.0))
		_put_lead(c)
	_lead.queue_redraw()


## A tinted icon before the title.
func set_lead_icon(icon_name: StringName, tint: Color, px: float = 14.0) -> void:
	if _lead is TextureRect:
		var r := _lead as TextureRect
		r.texture = HudStyle.icon(icon_name)
		r.modulate = tint
		return
	if _lead:
		_lead.queue_free()
	_put_lead(HudStyle.icon_rect(icon_name, px, tint))


## A small outlined state tag on the right ("RAID", "FLEE"); empty hides it.
func set_badge(text: String, color: Color) -> void:
	if _badge == null:
		_badge = Label.new()
		_badge.add_theme_font_override("font", HudStyle.font("SemiBold", true, false, 1))
		_badge.add_theme_font_size_override("font_size", 11)
		_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_badge.custom_minimum_size.x = 50.0
		add_right(_badge)
	_badge.visible = not text.is_empty()
	if _badge.text != text:
		_badge.text = text
	if color != _badge_color:
		_badge_color = color
		_badge.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.15))
		_badge.add_theme_stylebox_override("normal", HudThemeBuilder.box(Color(color, 0.13), Color(color, 0.6), Vector4.ZERO, Vector4(4, 0, 4, 0)))


func _put_lead(c: Control) -> void:
	_lead = c
	_name_box.add_child(c)
	_name_box.move_child(c, title_label.get_index())


## The "└" before a nested row.
func _tree_mark() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(INDENT_PX - 6.0, 0.0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		var x := 5.0
		var y := c.size.y * 0.5
		var col := Color(HudStyle.HOLO_DIM, 0.9)
		c.draw_line(Vector2(x, -2.0), Vector2(x, y), col, 1.0)
		c.draw_line(Vector2(x, y), Vector2(c.size.x, y), col, 1.0))
	return c


# --- Tooltip ------------------------------------------------------------------

func _get_tooltip(_at_position: Vector2) -> String:
	if not rich_tip:
		return tooltip_text
	# A stable key: the live text changes must not close the tooltip.
	return "row:%d" % get_instance_id()


func _make_custom_tooltip(_for_text: String) -> Object:
	if not rich_tip:
		return null
	return RichTooltip.make(tip_builder if tip_builder.is_valid() else _default_tip, tip_accent)


## The first line of tooltip_text as the title (else the row's title),
## then its other lines (or the detail).
func _default_tip(tip: RichTooltip) -> void:
	var lines := tooltip_text.split("\n", false)
	var head := title_label.text
	if not lines.is_empty():
		head = lines[0]
		lines.remove_at(0)
	tip.title(head)
	if lines.is_empty() and not subtitle_label.text.is_empty():
		tip.text(subtitle_label.text, HudStyle.TEXT_DIM)
	for l in lines:
		tip.text(l)

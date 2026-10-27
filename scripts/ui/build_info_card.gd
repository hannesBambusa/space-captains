class_name BuildInfoCard
extends PanelContainer
## The build bar's rich tooltip, shown above the hovered [BuildTile] (the
## tiles are icon only, so this is where the words are): name and group,
## how many are built of the limit, what it does, the cost per resource
## (red where you are short, with what you have), build time, the hire
## terms, the defence numbers (DefenseStats) and why it cannot be built
## right now. Looks like the [RichTooltip] (its panel, the accent bar amber,
## red while it cannot be built). A refresh with the same content keeps the
## nodes, so the card stays still while the mouse rests on a tile.

const H := preload("res://scripts/ui/theme/hud_style.gd")
const WIDTH := 340.0

var _title: Label
var _group: Label
var _count: Label
var _desc: Label
var _costs: HBoxContainer
var _time: Label
var _hire: Label
var _stats_box: PanelContainer
var _stats: Label
var _block: Label
var _hint: Label
var _style: ChamferBox
## The last content shown ([method show_info] skips a repeat).
var _shown_key := ""


func _ready() -> void:
	_style = RichTooltip.panel_style(H.ACCENT)
	add_theme_stylebox_override("panel", _style)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.x = WIDTH
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	_title = UIUtil.label("", &"TitleLabel")
	_title.add_theme_font_override("font", H.font("SemiBold", true))
	_title.add_theme_font_size_override("font_size", 19)
	top.add_child(_title)
	top.add_child(UIUtil.spacer())
	_group = UIUtil.label("", &"HeaderLabel")
	top.add_child(_group)
	_count = UIUtil.label("", &"SubHeaderLabel")
	v.add_child(_count)
	_desc = _wrap(UIUtil.label("", &"DimLabel"))
	_desc.add_theme_color_override("font_color", H.TEXT)
	v.add_child(_desc)
	v.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	_costs = HBoxContainer.new()
	_costs.add_theme_constant_override("separation", 12)
	row.add_child(_costs)
	row.add_child(UIUtil.spacer())
	var tb := HBoxContainer.new()
	tb.add_theme_constant_override("separation", 4)
	tb.add_child(H.icon_rect(&"clock", 14.0, H.TEXT_DIM))
	_time = UIUtil.label("", &"NumberLabel")
	tb.add_child(_time)
	row.add_child(tb)
	_hire = _wrap(UIUtil.label("", &"DimLabel"))
	v.add_child(_hire)
	_stats_box = PanelContainer.new()
	_stats_box.theme_type_variation = &"InsetPanel"
	v.add_child(_stats_box)
	_stats = _wrap(UIUtil.label("", &"SmallLabel"))
	_stats.add_theme_color_override("font_color", HudStyle.TEXT)
	_stats_box.add_child(_stats)
	_block = _wrap(UIUtil.label("", &"WarnLabel"))
	v.add_child(_block)
	_hint = UIUtil.label("", &"SmallLabel")
	_hint.add_theme_color_override("font_color", H.TEXT_FAINT)
	v.add_child(_hint)


func _wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WIDTH - 2.0 * RichTooltip.MARGIN_X - 3.0
	return l


## Fills the card. [param info] keys: title, group, count, desc, costs
## (Array of {icon, text, short, have}), time, hire, stats, block, hint.
func show_info(info: Dictionary, above: Rect2) -> void:
	var key := var_to_str(info) + str(above)
	if visible and key == _shown_key:
		return
	_shown_key = key
	_style.accent_color = H.BAD if not String(info.get("block", "")).is_empty() else H.ACCENT
	_title.text = String(info.get("title", ""))
	_group.text = String(info.get("group", ""))
	_count.text = String(info.get("count", ""))
	_count.visible = not _count.text.is_empty()
	_desc.text = String(info.get("desc", ""))
	for c in _costs.get_children():
		c.queue_free()
	var costs: Array = info.get("costs", [])
	for c: Dictionary in costs:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 4)
		var short := bool(c.get("short", false))
		var col: Color = H.BAD if short else (c.get("color", H.TEXT) as Color)
		h.add_child(H.icon_rect(StringName(c["icon"]), 15.0, col))
		var l := UIUtil.label(String(c["text"]), &"NumberLabel")
		l.add_theme_color_override("font_color", col.lerp(Color.WHITE, 0.25) if not short else H.BAD)
		h.add_child(l)
		if short and c.has("have"):
			var hv := UIUtil.label("(have %s)" % String(c["have"]), &"SmallLabel")
			hv.add_theme_color_override("font_color", Color(H.BAD, 0.8))
			h.add_child(hv)
		_costs.add_child(h)
	if costs.is_empty():
		var free := UIUtil.label("Free", &"ValueLabel")
		free.add_theme_color_override("font_color", H.GOOD)
		_costs.add_child(free)
	_time.text = String(info.get("time", ""))
	_time.get_parent().visible = not _time.text.is_empty()
	_hire.text = String(info.get("hire", ""))
	_hire.visible = not _hire.text.is_empty()
	_stats.text = String(info.get("stats", ""))
	_stats_box.visible = not _stats.text.is_empty()
	_block.text = String(info.get("block", ""))
	_block.visible = not _block.text.is_empty()
	_hint.text = String(info.get("hint", ""))
	_hint.visible = not _hint.text.is_empty()
	visible = true
	reset_size()
	_place.call_deferred(above)


## Bottom edge pinned above the bar, growing upward: wrapped labels settle
## their height a frame late and the card must never cover the tiles.
func _place(above: Rect2) -> void:
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	var vp := get_viewport_rect().size
	var parent_pos := (get_parent() as Control).global_position if get_parent() is Control else Vector2.ZERO
	var w := WIDTH
	var x := clampf(above.get_center().x - w * 0.5, 8.0, vp.x - w - 8.0) - parent_pos.x
	var bottom := above.position.y - 8.0 - parent_pos.y
	offset_left = x
	offset_right = x + w
	offset_bottom = bottom
	offset_top = bottom - get_combined_minimum_size().y

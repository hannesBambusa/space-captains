class_name PilotColumn
extends PanelContainer
## Right-hand pilot list, under the minimap, floating over space (no panel,
## outlined text): a title row (PILOTS, count, collapse) with a rule line
## over a compact [PilotRoster] (summary line, small role chips, sort,
## one-row pilots). The HUD sets its height (HUD._layout_right) so it ends
## above an open selection panel; with too little room only the title row
## stays.

const H := preload("res://scripts/ui/theme/hud_style.gd")
## Below this body height only the title row shows.
const MIN_BODY := 120.0

var roster: PilotRoster
var is_open := true

var _count: Label
var _alert: Label
var _toggle: Button
var _body_room := true
var _rule: ColorRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	v.add_child(top)
	top.add_child(H.icon_rect(&"tab_pilots", 14.0, H.ACCENT))
	top.add_child(UIUtil.label("PILOTS", &"HeaderLabel"))
	_count = UIUtil.label("0", &"ValueLabel")
	_count.add_theme_font_size_override("font_size", 14)
	top.add_child(_count)
	_alert = UIUtil.label("", &"SubHeaderLabel")
	_alert.add_theme_color_override("font_color", H.BAD)
	top.add_child(_alert)
	top.add_child(UIUtil.spacer())
	_toggle = UIUtil.button("", &"IconButton")
	_toggle.icon = H.icon(&"collapse")
	_toggle.custom_minimum_size = Vector2(20.0, 16.0)
	_toggle.tooltip_text = "Collapse the pilot list"
	_toggle.pressed.connect(func() -> void:
		is_open = not is_open
		_toggle.icon = H.icon(&"collapse" if is_open else &"expand")
		_toggle.tooltip_text = ("Collapse" if is_open else "Expand") + " the pilot list"
		_sync_body())
	top.add_child(_toggle)
	_rule = ColorRect.new()
	_rule.color = H.HAIRLINE_STRONG
	_rule.custom_minimum_size.y = 1.0
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_rule)
	roster = PilotRoster.new()
	roster.compact = true
	roster.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(roster)
	H.outline_labels(self)


func setup(hud: HUD) -> void:
	roster.setup(hud)
	roster.count_changed.connect(func(total: int, fighting: int) -> void:
		_count.text = str(total)
		_alert.text = ("%d IN COMBAT" % fighting) if fighting > 0 else "")


## Height of the title row plus the panel margins (the collapsed size).
func header_height() -> float:
	var sb := get_theme_stylebox(&"panel")
	return _toggle.get_parent().get_combined_minimum_size().y + 6.0 + (sb.get_minimum_size().y if sb else 0.0)


## Places the column in [param rect] (Root coordinates).
func place(rect: Rect2) -> void:
	_body_room = rect.size.y - header_height() >= MIN_BODY
	_sync_body()
	var h := rect.size.y if (is_open and _body_room) else header_height()
	position = rect.position
	size = Vector2(rect.size.x, h)


func _sync_body() -> void:
	roster.visible = is_open and _body_room

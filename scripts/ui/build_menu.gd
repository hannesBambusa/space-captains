class_name BuildMenu
extends VBoxContainer
## Bottom build bar: one button per BuildingDef (name and cost), greyed out
## with the reason as tooltip when unaffordable. Clicking arms placement;
## while placing, a hint line above shows the controls and why a spot is
## invalid.

const VALID_COLOR := Color(0.45, 1.0, 0.6)
const INVALID_COLOR := Color(1.0, 0.45, 0.38)
const HINT := "Click: place    Shift-click: place more    Drag: orbit    Right-click / Esc: cancel"

var hud: HUD

var _bar: PanelContainer
var _buttons: Dictionary = {}
var _hint: PanelContainer
var _hint_title: Label
var _hint_status: Label


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_END
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	_hint = PanelContainer.new()
	_hint.visible = false
	_hint.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(_hint)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 2)
	_hint.add_child(hv)
	_hint_title = UIUtil.label("")
	_hint_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hv.add_child(_hint_title)
	_hint_status = UIUtil.label("", &"DimLabel")
	_hint_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hv.add_child(_hint_status)

	_bar = PanelContainer.new()
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(_bar)


func setup(owner_hud: HUD) -> void:
	hud = owner_hud
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	_bar.add_child(h)
	var title := UIUtil.label("BUILD", &"HeaderLabel")
	title.custom_minimum_size.x = 44.0
	h.add_child(title)
	if hud.manager:
		for def in hud.manager.building_defs:
			var b := _make_button(def)
			h.add_child(b)
			_buttons[def] = b
	Economy.changed.connect(func(_c: int, _m: int) -> void: _refresh())
	if hud.manager:
		hud.manager.building_added.connect(func(_b: Building) -> void: _refresh())
	if hud.placement:
		hud.placement.armed_changed.connect(_on_armed)
		hud.placement.validity_changed.connect(_on_validity)
	_refresh()


func get_button(def: BuildingDef) -> Button:
	return _buttons.get(def) as Button


func _make_button(def: BuildingDef) -> Button:
	var b := UIUtil.button("")
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(190.0, 50.0)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12.0
	v.offset_right = -12.0
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	b.add_child(v)
	v.add_child(UIUtil.label(def.short_label if not def.short_label.is_empty() else def.display_name))
	var cost := UIUtil.label("%s cr   %s mat   %ds" % [Economy.format_amount(def.cost_credits), Economy.format_amount(def.cost_materials), roundi(def.build_time)], &"DimLabel")
	v.add_child(cost)
	UIUtil.ignore_mouse(b)
	b.pressed.connect(_on_pressed.bind(def))
	return b


func _refresh() -> void:
	for def: BuildingDef in _buttons:
		var b: Button = _buttons[def]
		var why := Economy.shortfall_text(def.cost_credits, def.cost_materials)
		if hud.manager and not hud.manager.limit_reason(def).is_empty():
			why = hud.manager.limit_reason(def)
		var armed := hud.placement != null and hud.placement.def == def
		b.disabled = not why.is_empty() and not armed
		b.modulate = Color(1, 1, 1, 0.5) if b.disabled else Color.WHITE
		b.set_pressed_no_signal(armed)
		var tip := "%s\n%s\nCost: %d credits, %d materials\nBuild time: %d s" % [def.display_name, def.description, def.cost_credits, def.cost_materials, roundi(def.build_time)]
		b.tooltip_text = tip + ("\n\nCannot build: " + why if not why.is_empty() else "")


func _on_pressed(def: BuildingDef) -> void:
	if hud.placement == null:
		return
	if hud.placement.def == def:
		hud.placement.cancel()
	else:
		hud.placement.arm(def)
	_refresh()


func _on_armed(def: BuildingDef) -> void:
	_hint.visible = def != null
	if def:
		_hint_title.text = "Placing %s" % def.display_name
		_hint_status.text = HINT
	_refresh()


func _on_validity(valid: bool, reason: String) -> void:
	if hud.placement == null or hud.placement.def == null:
		return
	if valid:
		_hint_status.text = HINT
		_hint_status.add_theme_color_override("font_color", Color(0.6, 0.66, 0.74))
	else:
		_hint_status.text = reason
		_hint_status.add_theme_color_override("font_color", INVALID_COLOR)

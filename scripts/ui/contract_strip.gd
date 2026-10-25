class_name ContractStrip
extends VBoxContainer
## Bottom-left list of posted contracts, above the event feed, floating over
## space like the pilot list: one outlined row per contract (type icon,
## target, reward or budget, takers or the bounty's fleet, "paused, station
## can't pay"). Click = camera flies to the contract's beacon and its target
## is selected (as ContractRow); hovering a row shows its cancel button
## (tooltip says what happens to a bounty's escrow). At most
## [member max_rows] rows; "+N more" opens the CONTRACTS tab. The HUD
## places it (HUD._layout_left).

const H := preload("res://scripts/ui/theme/hud_style.gd")
const ROW_H := 22.0

@export var max_rows: int = 6
@export var width: float = 420.0

var hud: HUD

var _title: Label
var _escrow: Label
var _rows_box: VBoxContainer
var _more: Button
var _lines: Array[ContractLine] = []
var _dirty := true
var _refresh_left := 0.0


## One contract row (drawn).
class ContractLine:
	extends Control

	var contract: Contract
	var strip: ContractStrip
	var cancel: Button
	var hover := false
	var _d: Dictionary = {}

	func _init(c: Contract, owner: ContractStrip) -> void:
		contract = c
		strip = owner
		custom_minimum_size = Vector2(0, ROW_H)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		cancel = UIUtil.button("x", &"IconButton")
		cancel.custom_minimum_size = Vector2(20, 16)
		cancel.visible = false
		cancel.pressed.connect(func() -> void: ContractBoard.cancel(contract))
		add_child(cancel)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED and cancel:
			cancel.position = Vector2(size.x - 22, (size.y - 16) * 0.5)
			cancel.size = Vector2(20, 16)

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			strip.open(contract)
			accept_event()

	func refresh() -> void:
		var c := contract
		var d := {}
		d["icon"] = ContractStrip.type_icon(c)
		d["target"] = c.get_target_name()
		d["reward"] = c.get_reward_text()
		var n := c.takers.size()
		var team := (c as BountyContract).get_team_text() if c is BountyContract else ""
		d["takers"] = team if not team.is_empty() else ("%d on it" % n if n > 0 else c.get_status_name().to_lower())
		d["busy"] = n > 0
		d["paused"] = c.is_paused()
		d["hover"] = hover
		if d != _d:
			_d = d
			var tip := "%s\n%s\nPaid out: %s cr" % [c.get_title(), c.get_reward_text(), Economy.format_amount(c.credits_paid)]
			if c is BountyContract:
				tip += "\nReserved: %s cr" % Economy.format_amount((c as BountyContract).escrow)
			if c.is_paused():
				tip += "\nPaused: the station can't pay one %s cr payment, captains won't take it until credits come in" % Economy.format_amount(c.reward)
			tooltip_text = tip + "\nClick: show it    Hover: cancel"
			cancel.tooltip_text = ContractBoard.cancel_text(c)
			queue_redraw()

	func _draw() -> void:
		if _d.is_empty():
			return
		var w := size.x
		var mid := size.y * 0.5
		var base := mid + 4.5
		if hover:
			draw_rect(Rect2(0, 0, w, size.y), Color(1, 1, 1, 0.07))
		var paused := bool(_d["paused"])
		var col := H.WARN if paused else (H.ACCENT_SOFT if bool(_d["busy"]) else H.TEXT_DIM)
		draw_rect(Rect2(0, 3, 2, size.y - 6), Color(col, 0.9))
		var ic := H.icon(StringName(_d["icon"]))
		if ic:
			draw_texture_rect(ic, Rect2(7, mid - 6, 12, 12), false, col)
		var x := 25.0
		var right := w - (26.0 if hover else 4.0)
		var f_name := H.font("SemiBold")
		var f_num := H.font("SemiBold", true, true)
		var f_dim := H.font("Medium")
		var status := String(_d["takers"]) + ("  ·  paused, station can't pay" if paused else "")
		var sw := minf(f_dim.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, 170.0)
		var reward := String(_d["reward"])
		var rw := f_num.get_string_size(reward, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var name_w := right - x - sw - rw - 20.0
		var nm := PilotCard._fit(f_name, String(_d["target"]), 13, name_w)
		_text(f_name, Vector2(x, base), nm, 13, H.TEXT_BRIGHT)
		var rx := x + f_name.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 10.0
		_text(f_num, Vector2(rx, base - 0.5), reward, 12, H.CREDITS)
		var st := PilotCard._fit(f_dim, status, 12, sw + 1.0)
		var stw := f_dim.get_string_size(st, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		_text(f_dim, Vector2(right - stw, base - 0.5), st, 12, H.WARN if paused else H.TEXT_DIM)

	func _text(f: Font, at: Vector2, text: String, fsize: int, color: Color) -> void:
		draw_string_outline(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 3, Color(0, 0, 0, 0.75))
		draw_string(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)


func _ready() -> void:
	custom_minimum_size.x = width
	add_theme_constant_override("separation", 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	top.add_child(H.icon_rect(&"tab_contracts", 13.0, H.ACCENT))
	_title = UIUtil.label("CONTRACTS", &"HeaderLabel")
	_title.add_theme_font_size_override("font_size", 13)
	top.add_child(_title)
	top.add_child(UIUtil.spacer())
	_escrow = UIUtil.label("", &"SmallLabel")
	_escrow.add_theme_font_size_override("font_size", 11)
	top.add_child(_escrow)
	var rule := ColorRect.new()
	rule.color = H.HAIRLINE_STRONG
	rule.custom_minimum_size.y = 1.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rule)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 0)
	add_child(_rows_box)
	_more = UIUtil.button("", &"RowButton")
	_more.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_more.add_theme_font_size_override("font_size", 12)
	_more.custom_minimum_size.y = 18.0
	_more.pressed.connect(func() -> void:
		if hud:
			hud.overview.show_tab(OverviewPanel.Tab.CONTRACTS))
	add_child(_more)
	H.outline_labels(self)


func setup(owner_hud: HUD) -> void:
	hud = owner_hud
	ContractBoard.contract_posted.connect(func(_c: Contract) -> void: _dirty = true)
	ContractBoard.contract_removed.connect(func(_c: Contract) -> void: _dirty = true)
	ContractBoard.contract_changed.connect(func(_c: Contract) -> void: _refresh())
	_rebuild()


static func type_icon(c: Contract) -> StringName:
	if c is MiningContract:
		return &"st_mining"
	if c is BountyContract:
		return &"st_hunt"
	if c is EscortContract:
		return &"st_escort"
	if c is SalvageContract:
		return &"scrap"
	return &"tab_contracts"


func open(c: Contract) -> void:
	if hud == null:
		return
	var t := ContractRow._focus_target(c, hud)
	if hud.camera and is_instance_valid(t):
		hud.camera.focus_on(t)
	if hud.selection and is_instance_valid(c.target) and (c.target is SystemBelt or c.target is Ship or c.target is ScavengerDen or c.target is ScrapField):
		hud.selection.select(c.target)


func _process(delta: float) -> void:
	if _dirty:
		_dirty = false
		_rebuild()
	# Hover: the row under the mouse shows its cancel button.
	var mp := get_global_mouse_position()
	for l in _lines:
		var on := l.get_global_rect().has_point(mp)
		if on != l.hover:
			l.hover = on
			l.cancel.visible = on
			l.refresh()
			l.queue_redraw()
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = 0.5
		_refresh()


func _rebuild() -> void:
	for l in _lines:
		l.queue_free()
	_lines.clear()
	var list := ContractBoard.get_listed()
	visible = not list.is_empty()
	_title.text = "CONTRACTS %d" % list.size()
	for i in mini(list.size(), max_rows):
		var l := ContractLine.new(list[i], self)
		_rows_box.add_child(l)
		_lines.append(l)
	_more.visible = list.size() > max_rows
	_more.text = "+%d more: open the contracts tab" % (list.size() - max_rows)
	_refresh()


func _refresh() -> void:
	for l in _lines:
		if is_instance_valid(l.contract):
			l.refresh()
	var held := ContractBoard.escrow_total()
	_escrow.text = ("RESERVED %s CR" % UIUtil.amount(held)) if held > 0 else ""
	_escrow.tooltip_text = "Reserved for bounties and zone budgets (held by the contract board)"

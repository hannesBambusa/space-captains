class_name ZonePanel
extends PanelContainer
## Bottom-right panel for the selected defence zone (DefenseZone): where it
## sits, mercenaries patrolling it, raiders inside, the radius stepper, the
## kill bounty (credits per raider killed inside) and its budget (reserved
## from the player's credits; add or take back), what it paid so far, and
## the remove button (the budget left comes back).

const BUDGET_STEPS: Array[int] = [100, 500]

@export var panel_width: float = 380.0

var hud: HUD
var zone: DefenseZone

var _title: Label
var _anchor: Label
var _distance: Label
var _mercs: Label
var _raiders: Label
var _radius_value: Label
var _radius_minus: Button
var _radius_plus: Button
var _bounty_value: Label
var _bounty_minus: Button
var _bounty_plus: Button
var _budget_value: Label
var _add_buttons: Array[Button] = []
var _take_back: Button
var _bounty_hint: Label
var _stats: Label
var _remove: Button
var _refresh_timer := 0.0


func _ready() -> void:
	custom_minimum_size.x = panel_width
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	top.add_child(UIUtil.label("DEFENCE ZONE", &"HeaderLabel"))
	top.add_child(UIUtil.spacer())
	var close := UIUtil.button("x", &"IconButton")
	close.custom_minimum_size = Vector2(26.0, 22.0)
	close.tooltip_text = "Deselect (Esc)"
	close.pressed.connect(func() -> void:
		if hud and hud.selection:
			hud.selection.deselect())
	top.add_child(close)
	_title = UIUtil.label("", &"TitleLabel")
	v.add_child(_title)
	var info := UIUtil.label("Mercenaries on patrol roam here and engage raiders that come in. Mercenaries nearby answer too.", &"DimLabel")
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = panel_width - 24.0
	v.add_child(info)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	_anchor = _grid_row(grid, "Position")
	_distance = _grid_row(grid, "From home")
	_mercs = _grid_row(grid, "Mercenaries")
	_raiders = _grid_row(grid, "Raiders inside")

	var rrow := HBoxContainer.new()
	v.add_child(rrow)
	rrow.add_child(UIUtil.label("Radius", &"DimLabel"))
	rrow.add_child(UIUtil.spacer())
	_radius_minus = UIUtil.step_button("-", "Smaller (Shift: 1 km)")
	_radius_minus.pressed.connect(_step_radius.bind(-1))
	rrow.add_child(_radius_minus)
	_radius_value = _value_label()
	rrow.add_child(_radius_value)
	_radius_plus = UIUtil.step_button("+", "Larger (Shift: 1 km)")
	_radius_plus.pressed.connect(_step_radius.bind(1))
	rrow.add_child(_radius_plus)

	v.add_child(HSeparator.new())
	v.add_child(UIUtil.label("KILL BOUNTY", &"HeaderLabel"))
	var brow := HBoxContainer.new()
	v.add_child(brow)
	brow.add_child(UIUtil.label("Per raider killed inside", &"DimLabel"))
	brow.add_child(UIUtil.spacer())
	_bounty_minus = UIUtil.step_button("-", "Lower (Shift: 50)")
	_bounty_minus.pressed.connect(_step_bounty.bind(-1))
	brow.add_child(_bounty_minus)
	_bounty_value = _value_label()
	brow.add_child(_bounty_value)
	_bounty_plus = UIUtil.step_button("+", "Raise (Shift: 50)")
	_bounty_plus.pressed.connect(_step_bounty.bind(1))
	brow.add_child(_bounty_plus)
	var grow := HBoxContainer.new()
	v.add_child(grow)
	grow.add_child(UIUtil.label("Budget", &"DimLabel"))
	grow.add_child(UIUtil.spacer())
	_budget_value = UIUtil.label("", &"ValueLabel")
	grow.add_child(_budget_value)
	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 6)
	v.add_child(arow)
	for step in BUDGET_STEPS:
		var b := UIUtil.button("Add %d cr" % step)
		b.pressed.connect(_add_budget.bind(step))
		arow.add_child(b)
		_add_buttons.append(b)
	arow.add_child(UIUtil.spacer())
	_take_back = UIUtil.button("Take back")
	_take_back.pressed.connect(_take_back_all)
	arow.add_child(_take_back)
	_bounty_hint = UIUtil.label("", &"DimLabel")
	_bounty_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bounty_hint.custom_minimum_size.x = panel_width - 24.0
	v.add_child(_bounty_hint)
	_stats = UIUtil.label("", &"DimLabel")
	v.add_child(_stats)

	v.add_child(HSeparator.new())
	_remove = UIUtil.button("Remove zone")
	_remove.pressed.connect(_on_remove)
	v.add_child(_remove)
	Economy.changed.connect(func(_c: int, _m: int) -> void:
		if is_visible_in_tree():
			refresh())


func setup(owner_hud: HUD) -> void:
	hud = owner_hud
	if hud.selection:
		hud.selection.selection_changed.connect(func(t: Node3D) -> void: show_zone(t as DefenseZone))
	var zones := DefenseZones.of(get_tree())
	if zones:
		zones.zone_changed.connect(func(z: DefenseZone) -> void:
			if z == zone:
				refresh())


func show_zone(z: DefenseZone) -> void:
	zone = z
	visible = z != null
	refresh()


func get_remove_button() -> Button:
	return _remove


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 0.5
		refresh()


func refresh() -> void:
	if zone == null or not is_instance_valid(zone):
		return
	var z := zone
	_title.text = z.zone_name
	_anchor.text = z.anchor_text()
	var sys := hud.solar_system if hud else null
	if sys and sys.home_station:
		_distance.text = "%.1f km" % (SpaceNav.flat_distance(z.global_position, sys.home_station.global_position) / 1000.0)
	var patrolling := 0
	for n in get_tree().get_nodes_in_group(Ship.GROUP):
		var s := n as Ship
		var mb := s.brain as MercenaryBrain if s else null
		if mb and not s.dead and mb.patrol_zone() == z:
			patrolling += 1
	_mercs.text = "%d patrolling here" % patrolling if patrolling > 0 else "None patrolling here now"
	_raiders.text = "None" if z.raiders_inside <= 0 else "%d" % z.raiders_inside
	_raiders.add_theme_color_override("font_color", Color(1.0, 0.45, 0.38) if z.raiders_inside > 0 else Color(0.85, 0.9, 1.0))
	_radius_value.text = "%.1f km" % (z.radius / 1000.0)
	_radius_minus.disabled = z.radius <= DefenseZones.RADIUS_RANGE.x
	_radius_plus.disabled = z.radius >= DefenseZones.RADIUS_RANGE.y
	_bounty_value.text = "None" if z.kill_bounty <= 0 else "%d cr" % z.kill_bounty
	_bounty_minus.disabled = z.kill_bounty <= 0
	_bounty_plus.disabled = z.kill_bounty >= DefenseZones.BOUNTY_MAX
	_budget_value.text = "%s cr" % UIUtil.amount(z.budget) + (" (%d kill%s)" % [z.kills_left(), "" if z.kills_left() == 1 else "s"] if z.kill_bounty > 0 else "")
	for i in _add_buttons.size():
		var step := BUDGET_STEPS[i]
		var why := ContractBoard.post_problem(step, true)
		_add_buttons[i].disabled = not why.is_empty()
		_add_buttons[i].tooltip_text = why if not why.is_empty() else "Reserve %d cr more from your credits for this zone's kill bounty" % step
	_take_back.disabled = z.budget <= 0
	_take_back.tooltip_text = "Take the %s cr left in the budget back into your credits" % UIUtil.amount(z.budget)
	if z.kill_bounty <= 0:
		_bounty_hint.text = "No kill bounty: mercenaries still patrol here. Set one to draw more of them (the greedy most) and pay per raider killed inside."
	elif z.budget < z.kill_bounty:
		_bounty_hint.text = "Add a budget to pay it. The budget is reserved from your credits; what is left comes back when you take it back or remove the zone."
	else:
		_bounty_hint.text = "Paid from the budget to the mercenaries who hit a raider killed inside, split evenly. Turret kills pay nothing."
	_stats.text = "Paid kills: %d, paid out %s cr" % [z.kills, UIUtil.amount(z.paid_total)]
	_remove.tooltip_text = "Remove this zone%s" % (": the %s cr left in its budget comes back" % UIUtil.amount(z.budget) if z.budget > 0 else "")


func _step_radius(dir: int) -> void:
	var zones := DefenseZones.of(get_tree())
	if zones and zone:
		var step := DefenseZones.RADIUS_STEP * (5.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		zones.set_radius(zone, zone.radius + dir * step)


func _step_bounty(dir: int) -> void:
	var zones := DefenseZones.of(get_tree())
	if zones and zone:
		var step := DefenseZones.BOUNTY_STEP * (5 if Input.is_key_pressed(KEY_SHIFT) else 1)
		zones.set_kill_bounty(zone, zone.kill_bounty + dir * step)


func _add_budget(credits: int) -> void:
	var zones := DefenseZones.of(get_tree())
	if zones and zone:
		zones.add_budget(zone, credits)
		refresh()


func _take_back_all() -> void:
	var zones := DefenseZones.of(get_tree())
	if zones and zone:
		zones.withdraw_budget(zone, zone.budget)
		refresh()


func _on_remove() -> void:
	var zones := DefenseZones.of(get_tree())
	if zones and zone:
		var z := zone
		if hud and hud.selection:
			hud.selection.deselect()
		zones.remove(z)


func _grid_row(grid: GridContainer, title: String) -> Label:
	grid.add_child(UIUtil.label(title, &"DimLabel"))
	var l := UIUtil.label("", &"ValueLabel")
	grid.add_child(l)
	return l


func _value_label() -> Label:
	var l := UIUtil.label("", &"ValueLabel")
	l.custom_minimum_size.x = 74.0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


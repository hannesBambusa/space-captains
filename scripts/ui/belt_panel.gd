class_name BeltPanel
extends PanelContainer
## Bottom-right panel for the selected asteroid belt: ore, richness, danger,
## distance from home, the contracts posted on it (with cancel), and the
## "Post mining contract" form: reward per load stepper, a load limit and
## the "Escorted" option (pay per escorted trip), which posts a linked
## EscortContract so mercenaries fly with every miner on it.

const ORE_NAMES: PackedStringArray = ["Rock", "Iron", "Titanium", "Crystal"]

@export var panel_width: float = 380.0

var hud: HUD
var belt: SystemBelt
var reward: int = 50
var load_limit_index: int = 0

var _title: Label
var _ore: Label
var _richness: PipMeter
var _richness_pct: Label
var _danger: PipMeter
var _danger_text: Label
var _distance: Label
var _contracts_header: Label
var _contracts: VBoxContainer
var _reward_value: Label
var _reward_minus: Button
var _reward_plus: Button
var _fair: Label
var _limit_value: Label
var _limit_minus: Button
var _limit_plus: Button
var _post: Button
var _post_hint: Label
var escorted: bool = false
var escort_pay: int = 35
var _escorted: CheckButton
var _escort_row: HBoxContainer
var _escort_value: Label
var _refresh_timer := 0.0


func _ready() -> void:
	custom_minimum_size.x = panel_width
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	top.add_child(UIUtil.label("ASTEROID BELT", &"HeaderLabel"))
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

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	grid.add_child(UIUtil.label("Ore", &"DimLabel"))
	_ore = UIUtil.label("", &"ValueLabel")
	grid.add_child(_ore)
	grid.add_child(UIUtil.label("Richness", &"DimLabel"))
	var rh := HBoxContainer.new()
	_richness = PipMeter.new()
	_richness.style = PipMeter.Style.BAR
	_richness.max_value = 1.0
	_richness.custom_minimum_size = Vector2(90.0, 5.0)
	_richness.color = Color(0.85, 0.88, 0.95)
	rh.add_child(_richness)
	_richness_pct = UIUtil.label("", &"ValueLabel")
	rh.add_child(_richness_pct)
	grid.add_child(rh)
	grid.add_child(UIUtil.label("Danger", &"DimLabel"))
	var dh := HBoxContainer.new()
	_danger = PipMeter.new()
	_danger.style = PipMeter.Style.PIPS
	_danger.max_value = 5.0
	_danger.graded = true
	_danger.pip_size = 8.0
	_danger.pip_gap = 3.0
	dh.add_child(_danger)
	_danger_text = UIUtil.label("", &"DimLabel")
	dh.add_child(_danger_text)
	grid.add_child(dh)
	grid.add_child(UIUtil.label("From home", &"DimLabel"))
	_distance = UIUtil.label("", &"ValueLabel")
	grid.add_child(_distance)

	v.add_child(HSeparator.new())
	_contracts_header = UIUtil.label("CONTRACTS", &"HeaderLabel")
	v.add_child(_contracts_header)
	_contracts = VBoxContainer.new()
	_contracts.add_theme_constant_override("separation", 1)
	v.add_child(_contracts)

	v.add_child(HSeparator.new())
	v.add_child(UIUtil.label("POST MINING CONTRACT", &"HeaderLabel"))
	var row := HBoxContainer.new()
	v.add_child(row)
	row.add_child(UIUtil.label("Pay per load", &"DimLabel"))
	row.add_child(UIUtil.spacer())
	_reward_minus = _step_button("-", "Lower the pay (Shift: 50)")
	_reward_minus.pressed.connect(_step_reward.bind(-1))
	row.add_child(_reward_minus)
	_reward_value = UIUtil.label("", &"ValueLabel")
	_reward_value.custom_minimum_size.x = 74.0
	_reward_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_reward_value)
	_reward_plus = _step_button("+", "Raise the pay (Shift: 50)")
	_reward_plus.pressed.connect(_step_reward.bind(1))
	row.add_child(_reward_plus)
	_fair = UIUtil.label("", &"DimLabel")
	_fair.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fair.custom_minimum_size.x = panel_width - 24.0
	v.add_child(_fair)
	var lrow := HBoxContainer.new()
	v.add_child(lrow)
	lrow.add_child(UIUtil.label("Load limit", &"DimLabel"))
	lrow.add_child(UIUtil.spacer())
	_limit_minus = _step_button("-", "Fewer loads")
	_limit_minus.pressed.connect(_step_limit.bind(-1))
	lrow.add_child(_limit_minus)
	_limit_value = UIUtil.label("", &"ValueLabel")
	_limit_value.custom_minimum_size.x = 74.0
	_limit_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lrow.add_child(_limit_value)
	_limit_plus = _step_button("+", "More loads")
	_limit_plus.pressed.connect(_step_limit.bind(1))
	lrow.add_child(_limit_plus)
	_escorted = CheckButton.new()
	_escorted.text = "Escorted"
	_escorted.focus_mode = Control.FOCUS_NONE
	_escorted.tooltip_text = "Also post an escort contract: mercenaries fly with every miner on this contract, paid per trip. Miners take dangerous belts more readily."
	_escorted.toggled.connect(func(on: bool) -> void:
		escorted = on
		_refresh_form())
	v.add_child(_escorted)
	_escort_row = HBoxContainer.new()
	v.add_child(_escort_row)
	_escort_row.add_child(UIUtil.label("Escort pay per trip", &"DimLabel"))
	_escort_row.add_child(UIUtil.spacer())
	var em := _step_button("-", "Lower the escort pay")
	em.pressed.connect(_step_escort.bind(-1))
	_escort_row.add_child(em)
	_escort_value = UIUtil.label("", &"ValueLabel")
	_escort_value.custom_minimum_size.x = 74.0
	_escort_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_escort_row.add_child(_escort_value)
	var ep := _step_button("+", "Raise the escort pay")
	ep.pressed.connect(_step_escort.bind(1))
	_escort_row.add_child(ep)
	_post = UIUtil.button("Post mining contract", &"AccentButton")
	_post.pressed.connect(_on_post)
	v.add_child(_post)
	_post_hint = UIUtil.label("", &"DimLabel")
	_post_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_post_hint.custom_minimum_size.x = panel_width - 24.0
	v.add_child(_post_hint)


func setup(owner_hud: HUD) -> void:
	hud = owner_hud
	if hud.selection:
		hud.selection.selection_changed.connect(func(t: Node3D) -> void: show_belt(t as SystemBelt))
	ContractBoard.contract_posted.connect(func(_c: Contract) -> void: _rebuild_contracts())
	ContractBoard.contract_changed.connect(func(_c: Contract) -> void: _rebuild_contracts())
	ContractBoard.contract_removed.connect(func(_c: Contract) -> void: _rebuild_contracts())


func show_belt(b: SystemBelt) -> void:
	var changed := b != belt
	belt = b
	visible = b != null
	if b == null:
		return
	if changed:
		reward = ContractBoard.mining_rules.default_reward(b)
		load_limit_index = 0
		escorted = false
	var d := b.def
	_title.text = d.name
	var ores := ORE_NAMES[d.ore_type]
	if d.secondary_ore != AsteroidBelt.OreType.ROCK and d.secondary_ore != d.ore_type:
		ores += ", some " + ORE_NAMES[d.secondary_ore].to_lower()
	_ore.text = ores
	_richness.value = d.richness
	_richness_pct.text = "%d%%" % roundi(d.richness * 100.0)
	_danger.value = float(b.danger)
	_danger_text.text = "%d of 5" % b.danger
	if hud and hud.solar_system:
		for den in hud.solar_system.dens:
			if den.belt == b:
				_danger_text.text += ", %s %s" % [den.get_display_name(), "nearby" if den.is_alive() else "destroyed"]
	_update_distance()
	_rebuild_contracts()
	_refresh_form()


func get_post_button() -> Button:
	return _post


func set_reward(value: int) -> void:
	reward = ContractBoard.mining_rules.clamp_reward(value)
	_refresh_form()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 0.5
		_update_distance()
		for c in _contracts.get_children():
			if c is ContractRow:
				(c as ContractRow).refresh()


func _update_distance() -> void:
	if belt == null or hud == null or hud.solar_system == null or hud.solar_system.home_station == null:
		_distance.text = "-"
		return
	var km := SpaceNav.distance_to_belt(belt, hud.solar_system.home_station.global_position) / 1000.0
	var minutes := km * 1000.0 / 150.0 / 60.0
	_distance.text = "%.1f km  (~%s by miner)" % [km, "%d s" % roundi(minutes * 60.0) if minutes < 1.0 else "%.1f min" % minutes]


func _rebuild_contracts() -> void:
	if belt == null:
		return
	for c in _contracts.get_children():
		_contracts.remove_child(c)
		c.queue_free()
	var list := ContractBoard.get_for_target(belt)
	_contracts_header.text = "CONTRACTS  %d" % list.size()
	if list.is_empty():
		_contracts.add_child(UIUtil.label("None posted. Miners only work belts with a contract.", &"DimLabel"))
		return
	for c in list:
		var row := ContractRow.new(c, hud, false)
		_contracts.add_child(row)


func _refresh_form() -> void:
	if belt == null:
		return
	var rules := ContractBoard.mining_rules
	_reward_value.text = "%d cr" % reward
	_reward_minus.disabled = reward <= rules.reward_min
	_reward_plus.disabled = reward >= rules.reward_max
	var fair := rules.default_reward(belt)
	var mats := rules.materials_for(belt.ore_type)
	var verdict := "fair"
	if reward >= fair * 1.6:
		verdict = "generous"
	elif reward > fair:
		verdict = "above fair"
	elif reward < fair * 0.7:
		verdict = "low"
	elif reward < fair:
		verdict = "below fair"
	_fair.text = "Fair pay here is about %d cr (%s). One load = %d materials." % [fair, verdict, mats]
	var limit := rules.load_limit_options[load_limit_index]
	_limit_value.text = "No limit" if limit <= 0 else "%d loads" % limit
	_limit_minus.disabled = load_limit_index <= 0
	_limit_plus.disabled = load_limit_index >= rules.load_limit_options.size() - 1
	var max_cost := "" if limit <= 0 else " Up to %s cr in total." % Economy.format_amount(limit * reward)
	_post_hint.text = "Paid on delivery, %d cr per load.%s" % [reward, max_cost]
	_escorted.set_pressed_no_signal(escorted)
	_escort_row.visible = escorted
	_escort_value.text = "%d cr" % escort_pay
	_post.text = "Post escorted mining contract" if escorted else "Post mining contract"
	if escorted:
		_post_hint.text += " Escorts: %d cr each per trip." % escort_pay


func _step_reward(dir: int) -> void:
	var rules := ContractBoard.mining_rules
	var step := rules.reward_step * (5 if Input.is_key_pressed(KEY_SHIFT) else 1)
	set_reward(reward + dir * step)


func _step_limit(dir: int) -> void:
	var n := ContractBoard.mining_rules.load_limit_options.size()
	load_limit_index = clampi(load_limit_index + dir, 0, n - 1)
	_refresh_form()


func _step_escort(dir: int) -> void:
	escort_pay = clampi(escort_pay + dir * 5 * (5 if Input.is_key_pressed(KEY_SHIFT) else 1), 10, 200)
	_refresh_form()


func _on_post() -> void:
	if belt == null:
		return
	var mc := ContractBoard.post_mining(belt, reward, ContractBoard.mining_rules.load_limit_options[load_limit_index])
	if mc and escorted:
		ContractBoard.post_escort_for_mining(mc, escort_pay, 2)


func _step_button(text: String, tip: String) -> Button:
	var b := UIUtil.button(text, &"IconButton")
	b.custom_minimum_size = Vector2(28.0, 24.0)
	b.tooltip_text = tip
	return b

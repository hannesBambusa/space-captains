class_name BeltPanel
extends PanelContainer
## Bottom-right panel for the selected asteroid cluster: ore, richness,
## what is left in it, danger (with the hostile bases in reach), distance
## from home, the contracts posted on it (with cancel), and the
## "Post mining contract" form: reward per load stepper, a load limit and
## the "Escorted" option (pay per escorted trip), which posts a linked
## EscortContract so mercenaries fly with every miner on it.

const ORE_NAMES: PackedStringArray = ["Rock", "Iron", "Titanium", "Crystal"]

@export var panel_width: float = 380.0

var hud: HUD
var belt: AsteroidCluster

var _title: Label
var _ore: Label
var _richness: PipMeter
var _richness_pct: Label
var _danger: PipMeter
var _danger_text: Label
var _distance: Label
var _left: PipMeter
var _left_text: Label
var _contracts_header: Label
var _contracts: VBoxContainer
var _form: PostContractForm
var escorted: bool = false
var escort_pay: int = 35
var _escorted: CheckButton
var _profit: Label
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
	top.add_child(UIUtil.label("ASTEROID CLUSTER", &"HeaderLabel"))
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
	_richness = UIUtil.bar(HudStyle.HOLO, Vector2(90.0, 5.0))
	rh.add_child(_richness)
	_richness_pct = UIUtil.label("", &"NumberLabel")
	rh.add_child(_richness_pct)
	grid.add_child(rh)
	grid.add_child(UIUtil.label("Ore left", &"DimLabel"))
	var lh := HBoxContainer.new()
	_left = UIUtil.bar(HudStyle.GOOD, Vector2(90.0, 5.0))
	lh.add_child(_left)
	_left_text = UIUtil.label("", &"ValueLabel")
	lh.add_child(_left_text)
	grid.add_child(lh)
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
	_distance = UIUtil.label("", &"NumberLabel")
	grid.add_child(_distance)

	v.add_child(HSeparator.new())
	_contracts_header = UIUtil.label("CONTRACTS", &"HeaderLabel")
	v.add_child(_contracts_header)
	_contracts = VBoxContainer.new()
	_contracts.add_theme_constant_override("separation", 1)
	v.add_child(_contracts)

	v.add_child(HSeparator.new())
	_form = PostContractForm.new("POST MINING CONTRACT", "Post mining contract", ContractBoard.mining_rules, panel_width)
	_form.changed.connect(_refresh_form)
	_form.post_pressed.connect(_on_post)
	v.add_child(_form)
	_escorted = CheckButton.new()
	_escorted.text = "Escorted"
	_escorted.focus_mode = Control.FOCUS_NONE
	_escorted.tooltip_text = "Also post an escort contract: mercenaries fly with every miner on this contract, paid per trip. Miners take dangerous clusters more readily."
	_escorted.toggled.connect(func(on: bool) -> void:
		escorted = on
		_refresh_form())
	_profit = UIUtil.label("", &"ValueLabel")
	_form.add_row(_profit)
	_form.add_row(_escorted)
	var er := UIUtil.stepper_row(_form, "Escort pay per trip", _step_escort, "Lower the escort pay", "Raise the escort pay")
	_escort_value = er[0]
	_escort_row = _escort_value.get_parent() as HBoxContainer
	_form.move_child(_escort_row, _form.post.get_index())


func setup(owner_hud: HUD) -> void:
	hud = owner_hud
	if hud.selection:
		hud.selection.selection_changed.connect(func(t: Node3D) -> void: show_belt(t as AsteroidCluster))
	ContractBoard.contract_posted.connect(func(_c: Contract) -> void: _rebuild_contracts())
	ContractBoard.contract_changed.connect(func(_c: Contract) -> void: _rebuild_contracts())
	ContractBoard.contract_removed.connect(func(_c: Contract) -> void: _rebuild_contracts())


func show_belt(b: AsteroidCluster) -> void:
	var changed := b != belt
	belt = b
	visible = b != null
	if b == null:
		return
	if changed:
		_form.reward = ContractBoard.mining_rules.default_reward(b)
		_form.load_limit_index = 0
		escorted = false
	var d := b.def
	_title.text = d.name
	var ores := ORE_NAMES[d.ore_type]
	if d.secondary_ore != AsteroidBelt.OreType.ROCK and d.secondary_ore != d.ore_type:
		ores += ", some " + ORE_NAMES[d.secondary_ore].to_lower()
	_ore.text = ores
	_richness.value = d.richness
	_richness_pct.text = "%d%%" % roundi(d.richness * 100.0)
	_update_live()
	_rebuild_contracts()
	_refresh_form()


func get_post_button() -> Button:
	return _form.post


func set_reward(value: int) -> void:
	_form.set_reward(value)


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 0.5
		_update_live()
		for c in _contracts.get_children():
			if c is ContractRow:
				(c as ContractRow).refresh()


## Parts that change while it is shown: what is left, danger (clusters
## drift past hostile bases), distance from home.
func _update_live() -> void:
	if belt == null or not is_instance_valid(belt):
		return
	_left.value = belt.fill_fraction()
	_left_text.text = "mined out" if belt.is_depleted else "%d of %d loads" % [belt.loads_left, belt.reserve]
	_danger.value = float(belt.danger)
	_danger_text.text = "%d of 5" % belt.danger
	for den in belt.nearby_dens():
		_danger_text.text += ", %s %s" % [den.get_display_name(), "nearby" if den.is_alive() else "destroyed"]
	_update_distance()
	if belt.is_depleted and not _form.post.disabled:
		_refresh_form()


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
		_contracts.add_child(UIUtil.label("None posted. Miners only work clusters with a contract.", &"DimLabel"))
		return
	for c in list:
		var row := ContractRow.new(c, hud, false)
		_contracts.add_child(row)


func _refresh_form() -> void:
	if belt == null:
		return
	var rules := ContractBoard.mining_rules
	var reward := _form.reward
	_form.refresh()
	var fair := rules.default_reward(belt)
	var mats := rules.materials_for(belt.ore_type)
	var ore := Economy.ore_of_belt(belt.ore_type)
	var worth := ""
	var f := Factory.find(self)
	_profit.visible = f != null
	if f:
		var load_value := roundi(float(mats) * f.market.willing_price(ore))
		worth = " The Factory pays about %d cr for it now." % load_value
		var margin := load_value - _form.reward
		_profit.text = "Factory pays ~%d / load, you pay %d: %s%d" % [load_value, _form.reward, "+" if margin >= 0 else "", margin]
		_profit.add_theme_color_override("font_color", HudStyle.GOOD if margin >= 0 else HudStyle.BAD)
	_form.fair.text = "Fair pay here is about %d cr (%s). One load = %d %s.%s" % [fair, PostContractForm.fair_verdict(reward, fair), mats, Economy.ore_name(ore), worth]
	_escorted.set_pressed_no_signal(escorted)
	_escort_row.visible = escorted
	_escort_value.text = "%d cr" % escort_pay
	_form.post.text = "Post escorted mining contract" if escorted else "Post mining contract"
	if escorted:
		_form.hint.text += " Escorts: %d cr each per trip." % escort_pay
	var why := ContractBoard.post_problem(reward)
	if why.is_empty() and belt.is_depleted:
		why = "Mined out, nothing left to post on"
	_form.set_problem(why)


func _step_escort(dir: int) -> void:
	escort_pay = clampi(escort_pay + dir * 5 * (5 if Input.is_key_pressed(KEY_SHIFT) else 1), 10, 200)
	_refresh_form()


func _on_post() -> void:
	if belt == null or belt.is_depleted:
		return
	var mc := ContractBoard.post_mining(belt, _form.reward, _form.load_limit())
	if mc and escorted:
		ContractBoard.post_escort_for_mining(mc, escort_pay, 2)

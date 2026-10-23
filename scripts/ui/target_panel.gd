class_name TargetPanel
extends PanelContainer
## Bottom-right panel for a selected hostile (scavenger ship or Scavenger
## Den) or a scrap field. Hostiles: name, status, hull and shield bars, the
## bounties posted on them (with cancel) and the "Post bounty" form with a
## reward stepper. Scrap fields: scrap amount and time left, the salvage
## contracts on it and the "Post salvage contract" form (a per-load bonus on
## top of the yard's pay; salvagers also work fields without one).

@export var panel_width: float = 380.0
@export var reward_min: int = 50
@export var reward_max: int = 2000
@export var reward_step: int = 25
## Default bounty for a scavenger ship / a den.
@export var ship_reward: int = 150
@export var den_reward: int = 800
## Salvage pay per load: default and stepper range.
@export var salvage_reward: int = 20
@export var salvage_min: int = 10
@export var salvage_max: int = 200
@export var salvage_step: int = 5

var hud: HUD
var target: Node3D
var reward: int = 150

var _header: Label
var _title: Label
var _status: Label
var _info: Label
var _bars: GridContainer
var _hull: PipMeter
var _hull_text: Label
var _shield: PipMeter
var _shield_text: Label
var _bounty_box: VBoxContainer
var _contracts_header: Label
var _reward_title: Label
var _bounties: VBoxContainer
var _reward_value: Label
var _post: Button
var _post_hint: Label
var _refresh_timer := 0.0


func _ready() -> void:
	custom_minimum_size.x = panel_width
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	_header = UIUtil.label("HOSTILE", &"HeaderLabel")
	top.add_child(_header)
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
	_status = UIUtil.label("", &"ValueLabel")
	v.add_child(_status)
	_info = UIUtil.label("", &"DimLabel")
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size.x = panel_width - 24.0
	v.add_child(_info)
	_bars = GridContainer.new()
	_bars.columns = 3
	_bars.add_theme_constant_override("h_separation", 10)
	_bars.add_theme_constant_override("v_separation", 3)
	v.add_child(_bars)
	var hb := _bar_row("Hull", Combat.HOSTILE_COLOR)
	_hull = hb[0]
	_hull_text = hb[1]
	var sb := _bar_row("Shields", Color(1.0, 0.6, 0.35))
	_shield = sb[0]
	_shield_text = sb[1]

	_bounty_box = VBoxContainer.new()
	_bounty_box.add_theme_constant_override("separation", 5)
	v.add_child(_bounty_box)
	_bounty_box.add_child(HSeparator.new())
	_contracts_header = UIUtil.label("BOUNTIES", &"HeaderLabel")
	_bounty_box.add_child(_contracts_header)
	_bounties = VBoxContainer.new()
	_bounties.add_theme_constant_override("separation", 1)
	_bounty_box.add_child(_bounties)
	var row := HBoxContainer.new()
	_bounty_box.add_child(row)
	_reward_title = UIUtil.label("Reward", &"DimLabel")
	row.add_child(_reward_title)
	row.add_child(UIUtil.spacer())
	var minus := UIUtil.button("-", &"IconButton")
	minus.custom_minimum_size = Vector2(28.0, 24.0)
	minus.tooltip_text = "Lower the reward (Shift: x5)"
	minus.pressed.connect(_step_reward.bind(-1))
	row.add_child(minus)
	_reward_value = UIUtil.label("", &"ValueLabel")
	_reward_value.custom_minimum_size.x = 84.0
	_reward_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_reward_value)
	var plus := UIUtil.button("+", &"IconButton")
	plus.custom_minimum_size = Vector2(28.0, 24.0)
	plus.tooltip_text = "Raise the reward (Shift: x5)"
	plus.pressed.connect(_step_reward.bind(1))
	row.add_child(plus)
	_post = UIUtil.button("Post bounty", &"AccentButton")
	_post.pressed.connect(_on_post)
	_bounty_box.add_child(_post)
	_post_hint = UIUtil.label("", &"DimLabel")
	_post_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_post_hint.custom_minimum_size.x = panel_width - 24.0
	_bounty_box.add_child(_post_hint)


func setup(owner_hud: HUD) -> void:
	hud = owner_hud
	if hud.selection:
		hud.selection.selection_changed.connect(_on_selection)
	ContractBoard.contract_posted.connect(func(_c: Contract) -> void: _rebuild_bounties())
	ContractBoard.contract_removed.connect(func(_c: Contract) -> void: _rebuild_bounties())


func get_post_button() -> Button:
	return _post


func show_target(t: Node3D) -> void:
	var changed := t != target
	target = t
	visible = t != null
	if t == null:
		return
	var hostile := t is ScavengerDen or t is ScavengerShip
	_bounty_box.visible = hostile or t is ScrapField
	_bars.visible = hostile
	if changed:
		reward = den_reward if t is ScavengerDen else (salvage_reward if t is ScrapField else ship_reward)
	_contracts_header.text = "SALVAGE CONTRACTS" if t is ScrapField else "BOUNTIES"
	_reward_title.text = "Bonus per load" if t is ScrapField else "Reward"
	_post.text = "Post salvage contract" if t is ScrapField else "Post bounty"
	if t is ScavengerDen:
		var d := t as ScavengerDen
		_header.text = "SCAVENGER HIDEOUT"
		_info.text = "Raider base dug into an asteroid, claiming %s. Launches scavengers up to %d at a time. Destroy it to stop them and lower the belt's danger." % [d.belt.def.name if d.belt else "?", d.def.spawn_cap]
	elif t is ScavengerShip:
		var sc := t as ScavengerShip
		_header.text = "SCAVENGER"
		_info.text = "Junk raider from %s. Hunts loaded miners and steals cargo." % (sc.den.get_display_name() if is_instance_valid(sc.den) else "a destroyed hideout")
	elif t is ScrapField:
		_header.text = "SCRAP FIELD"
		var sf := t as ScrapField
		_info.text = "Wreckage drifting apart. Salvagers from a Salvage Yard strip it on their own: %d scrap is about %d loads, which the yard reprocesses into ore (mostly iron, some titanium, a little crystal) and sells to you. It stops fading while salvagers work it or a contract is open. Danger here: %d of 5." % [
				sf.amount, ceili(float(sf.amount) / SalvageContract.LOAD_SCRAP), SalvageContract.danger_at(get_tree(), sf.global_position)]
	_title.text = String(t.call(&"get_display_name"))
	_title.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5) if hostile else Color(0.95, 0.9, 0.78))
	_rebuild_bounties()
	_refresh()


func _on_selection(t: Node3D) -> void:
	if t is ScavengerDen or t is ScavengerShip or t is ScrapField:
		show_target(t)
	else:
		show_target(null)


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 0.2
		_refresh()


func _refresh() -> void:
	if not is_instance_valid(target):
		return
	_status.text = String(target.call(&"get_status_text"))
	var d := target.get(&"durability") as Durability
	if d and _bars.visible:
		_hull.value = d.fraction()
		_hull_text.text = "%d / %d" % [roundi(d.hull), roundi(d.max_hull)]
		_shield.value = d.shield_fraction()
		_shield_text.text = "%d / %d" % [roundi(d.shields), roundi(d.max_shields)]
	_reward_value.text = "%s cr" % UIUtil.amount(reward)
	if target is ScrapField:
		var sf := target as ScrapField
		_post.disabled = sf.amount <= 0
		var yard := hud.manager.find_active(&"salvage_yard") if hud and hud.manager else null
		_post_hint.text = "Optional bonus, paid by you on delivery: %d cr per load on top of the yard's %d. It draws salvagers here first and makes dangerous wrecks worth it. %s" % [reward, SalvageContract.FAIR_REWARD,
				"Salvagers decide by pay, distance, danger and field size." if yard else "Build a Salvage Yard and hire salvagers to work it."]
	else:
		var alive := (target is ScavengerDen or target is ScavengerShip) and Combat.is_live(target)
		_post.disabled = not alive
		if not alive:
			_post_hint.text = "Destroyed."
		else:
			_post_hint.text = "Paid on destruction to the mercenaries who fought it, split between them. Nothing is reserved now."
	for c in _bounties.get_children():
		if c is ContractRow:
			(c as ContractRow).refresh()


func _rebuild_bounties() -> void:
	if _bounties == null:
		return
	for c in _bounties.get_children():
		_bounties.remove_child(c)
		c.queue_free()
	if not is_instance_valid(target):
		return
	var list := ContractBoard.get_for_target(target)
	if list.is_empty():
		_bounties.add_child(UIUtil.label("None posted. Salvagers work it anyway when it is worth the trip; a contract adds a bonus." if target is ScrapField else "None posted. Mercenaries only hunt it for a bounty, or when it comes near home.", &"DimLabel"))
		(_bounties.get_child(0) as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		(_bounties.get_child(0) as Label).custom_minimum_size.x = panel_width - 24.0
	for c in list:
		_bounties.add_child(ContractRow.new(c, hud, false))


func _step_reward(dir: int) -> void:
	var salvage := target is ScrapField
	var step := (salvage_step if salvage else reward_step) * (5 if Input.is_key_pressed(KEY_SHIFT) else 1)
	reward = clampi(reward + dir * step, salvage_min if salvage else reward_min, salvage_max if salvage else reward_max)
	_refresh()


func _on_post() -> void:
	if target is ScrapField:
		ContractBoard.post_salvage(target as ScrapField, reward)
	elif (target is ScavengerDen or target is ScavengerShip) and Combat.is_live(target):
		ContractBoard.post_bounty(target, reward, 4 if target is ScavengerDen else 2)


func _bar_row(title: String, color: Color) -> Array:
	var l := UIUtil.label(title, &"DimLabel")
	l.custom_minimum_size.x = 70.0
	_bars.add_child(l)
	var bar := PipMeter.new()
	bar.style = PipMeter.Style.BAR
	bar.max_value = 1.0
	bar.color = color
	bar.custom_minimum_size = Vector2(180.0, 6.0)
	_bars.add_child(bar)
	var t := UIUtil.label("", &"DimLabel")
	t.custom_minimum_size.x = 80.0
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_bars.add_child(t)
	return [bar, t]

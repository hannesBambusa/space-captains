class_name TopBar
extends PanelContainer
## Compact top bar: credits, iron / titanium / crystal (in ore colours, each
## with a small Factory demand meter: 1 to 3 pips, tooltip with its price),
## sim time and speed/pause state. Deliveries flash a short "-credits / +ore"
## delta next to the values; income (station fees, the corporate grant,
## Factory ore sales) flashes a green "+credits" beside it. Deltas landing
## within one flash add up. Ore on its way by cargo shuttle (waiting at an
## outpost or aboard, CargoDepot.pending_all) shows as a small dim "+40"
## after each ore. The credits tooltip shows what is reserved for bounties
## (ContractBoard escrow). With a Shield Generator built, a SHIELD bar
## shows the station bubble's charge (and the countdown while it is down).

## Emitted by the HOME button (the HUD flies the camera to the station).
signal home_pressed

## Seconds a delta stays visible before it fades.
@export var flash_hold: float = 1.6
@export var flash_fade: float = 0.8

var _credits: Label
## Per ore: count label, delta label, demand pips.
var _ore_labels: Array[Label] = []
var _ore_deltas: Array[Label] = []
var _ore_demand: Array[PipMeter] = []
## Per ore: the pending cargo hint ("+40").
var _ore_pending: Array[Label] = []
var _demand_timer := 0.0
var _time: Label
var _system: Label
var _speed_icon: TextureRect
var _speed: Label
var _speed_pips: PipMeter
var _credits_delta: Label
var _income_delta: Label
var _shield_box: HBoxContainer
var _shield_bar: PipMeter
var _shield_value: Label
var _shield_timer := 0.0
var _tweens: Dictionary = {}
## Running sums while a delta is still showing: label -> int.
var _sums: Dictionary = {}


func _ready() -> void:
	theme_type_variation = &"TopBarPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	add_child(h)
	# Left: the system name.
	var sys_box := HBoxContainer.new()
	sys_box.add_theme_constant_override("separation", 8)
	sys_box.custom_minimum_size.x = 300.0
	h.add_child(sys_box)
	sys_box.add_child(HudStyle.icon_rect(&"tab_system", 18.0, HudStyle.ACCENT))
	_system = UIUtil.label("", &"BigValueLabel")
	_system.add_theme_font_override("font", HudStyle.font("Bold", true, false, 2))
	sys_box.add_child(_system)
	var sl := UIUtil.label("SYSTEM", &"SubHeaderLabel")
	sys_box.add_child(sl)
	var home := UIUtil.button("HOME", &"ChipButton")
	home.icon = HudStyle.icon(&"station")
	home.custom_minimum_size.y = 24.0
	home.tooltip_text = "Fly to the home station (H)"
	home.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	home.pressed.connect(func() -> void: home_pressed.emit())
	sys_box.add_child(UIUtil.spacer(6.0))
	sys_box.add_child(home)
	h.add_child(UIUtil.spacer())
	# Centre: resources.
	var res := HBoxContainer.new()
	res.add_theme_constant_override("separation", 4)
	h.add_child(res)
	_credits = _add_resource(res, &"credits", HudStyle.CREDITS, "CREDITS")
	_credits_delta = _add_delta(res, PipMeter.BAD)
	_income_delta = _add_delta(res, PipMeter.GOOD)
	for i in Economy.ORE_NAMES.size():
		_add_divider(res)
		var v := _add_resource(res, [&"iron", &"titanium", &"crystal"][i], Economy.ORE_COLORS[i], Economy.ORE_NAMES[i].to_upper())
		v.add_theme_color_override("font_color", Economy.ORE_COLORS[i].lerp(Color.WHITE, 0.55))
		var pend := UIUtil.label("", &"SmallLabel")
		pend.add_theme_font_override("font", HudStyle.font("Medium", false, true))
		pend.add_theme_color_override("font_color", Economy.ORE_COLORS[i].lerp(HudStyle.TEXT_DIM, 0.45))
		pend.mouse_filter = Control.MOUSE_FILTER_PASS
		pend.visible = false
		res.add_child(pend)
		var pips := PipMeter.new()
		pips.style = PipMeter.Style.PIPS
		pips.max_value = 3.0
		pips.pip_size = 4.0
		pips.pip_gap = 2.0
		pips.vertical = true
		res.add_child(pips)
		_ore_pending.append(pend)
		_ore_labels.append(v)
		_ore_demand.append(pips)
		_ore_deltas.append(_add_delta(res, PipMeter.GOOD))
	_shield_box = HBoxContainer.new()
	_shield_box.add_theme_constant_override("separation", 6)
	_shield_box.visible = false
	_shield_box.mouse_filter = Control.MOUSE_FILTER_PASS
	res.add_child(_shield_box)
	_add_divider(_shield_box)
	var si := HudStyle.icon_rect(&"shield", 18.0, DefenseSection.SHIELD_COLOR)
	_shield_box.add_child(si)
	_shield_bar = PipMeter.new()
	_shield_bar.style = PipMeter.Style.BAR
	_shield_bar.max_value = 1.0
	_shield_bar.color = DefenseSection.SHIELD_COLOR
	_shield_bar.custom_minimum_size = Vector2(64.0, 5.0)
	_shield_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_shield_box.add_child(_shield_bar)
	_shield_value = UIUtil.label("", &"ValueLabel")
	_shield_value.custom_minimum_size.x = 64.0
	_shield_box.add_child(_shield_value)
	h.add_child(UIUtil.spacer())
	# Right: sim clock and speed.
	var clock_box := HBoxContainer.new()
	clock_box.add_theme_constant_override("separation", 8)
	clock_box.custom_minimum_size.x = 300.0
	clock_box.alignment = BoxContainer.ALIGNMENT_END
	h.add_child(clock_box)
	clock_box.add_child(HudStyle.icon_rect(&"clock", 16.0, HudStyle.TEXT_DIM))
	_time = UIUtil.label("", &"BigValueLabel")
	_time.custom_minimum_size.x = 76.0
	clock_box.add_child(_time)
	_speed_icon = HudStyle.icon_rect(&"speed", 14.0, HudStyle.ACCENT)
	clock_box.add_child(_speed_icon)
	_speed_pips = PipMeter.new()
	_speed_pips.style = PipMeter.Style.PIPS
	_speed_pips.max_value = 3.0
	_speed_pips.pip_size = 6.0
	_speed_pips.pip_gap = 2.0
	_speed_pips.color = HudStyle.ACCENT
	clock_box.add_child(_speed_pips)
	_speed = UIUtil.label("", &"ValueLabel")
	_speed.custom_minimum_size.x = 58.0
	clock_box.add_child(_speed)
	tooltip_text = "Space: pause    1 / 2 / 3: sim speed"
	Economy.changed.connect(_on_economy)
	ContractBoard.delivery_made.connect(_on_delivery)
	Economy.cargo_received.connect(_on_cargo)
	# Bounties and zone kill bounties (no contract) are paid from their
	# escrow (reserved when posted), not from the credits.
	ContractBoard.payout_made.connect(func(c: Contract, _s: Node, credits: int) -> void:
		if c != null and not (c is BountyContract):
			_flash_sum(_credits_delta, -credits))
	Economy.income.connect(func(amount: int, source: String) -> void:
		_flash_sum(_income_delta, amount)
		_income_delta.tooltip_text = "Last income: %s" % source)
	SimClock.paused_changed.connect(func(_p: bool) -> void: _update_speed())
	SimClock.speed_changed.connect(func(_s: float) -> void: _update_speed())
	_on_economy(Economy.credits, Economy.materials)
	_update_speed()


## The system name on the left (set by the HUD once the system is built).
func set_system_name(text: String) -> void:
	_system.text = text.to_upper()


func _process(delta: float) -> void:
	_demand_timer -= delta
	if _demand_timer <= 0.0:
		_demand_timer = 0.5
		_update_demand()
	_shield_timer -= delta
	if _shield_timer <= 0.0:
		_shield_timer = 0.2
		_update_shield()
	var t := int(SimClock.time)
	var text := "%02d:%02d:%02d" % [floori(t / 3600.0), floori(t / 60.0) % 60, t % 60]
	if _time.text != text:
		_time.text = text


## Icon (tinted) and value label; the value label carries the tooltip.
func _add_resource(parent: HBoxContainer, icon_name: StringName, tint: Color, title: String) -> Label:
	var ic := HudStyle.icon_rect(icon_name, 18.0, tint)
	ic.tooltip_text = title.capitalize()
	ic.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(ic)
	var v := UIUtil.label("", &"BigValueLabel")
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(v)
	return v


func _add_delta(parent: HBoxContainer, color: Color) -> Label:
	var l := UIUtil.label("", &"ValueLabel")
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 13)
	l.custom_minimum_size.x = 44.0
	l.modulate.a = 0.0
	parent.add_child(l)
	return l


## Shows a delta next to a value and fades it out.
func flash(label: Label, text: String) -> void:
	label.text = text
	var old := _tweens.get(label) as Tween
	if old and old.is_valid():
		old.kill()
	label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(flash_hold)
	tw.tween_property(label, "modulate:a", 0.0, flash_fade)
	_tweens[label] = tw


## Adds [param amount] to the delta shown on [param label] (or starts a new one).
func _flash_sum(label: Label, amount: int) -> void:
	if amount == 0:
		return
	var tw := _tweens.get(label) as Tween
	var sum: int = _sums.get(label, 0) if tw and tw.is_valid() and label.modulate.a > 0.05 else 0
	sum += amount
	_sums[label] = sum
	flash(label, ("+%s" if sum > 0 else "-%s") % UIUtil.amount(absi(sum)))


## [param ore] is the AsteroidBelt.OreType, -1 for salvage (mostly iron).
func _on_delivery(_contract: Contract, ship: Node, credits: int, materials: int, ore: int) -> void:
	if credits != 0:
		_flash_sum(_credits_delta, -credits)
	# Ore left at an outpost depot shows when its shuttle lands (_on_cargo).
	if materials != 0 and CargoDepot.of_ship(ship) == null:
		_flash_sum(_ore_deltas[Economy.ore_of_belt(ore)], materials)


## A cargo shuttle landed ore at the station.
func _on_cargo(cargo: PackedInt32Array, _source: String) -> void:
	for i in mini(cargo.size(), _ore_deltas.size()):
		if cargo[i] > 0:
			_flash_sum(_ore_deltas[i], cargo[i])


## Factory demand pips (Low 1, Normal 2, High 3) and the price tooltip,
## the pending cargo hints and the reserved credits.
func _update_demand() -> void:
	_update_pending()
	var reserved := ContractBoard.escrow_total()
	var zones := ContractBoard.zone_escrow_total()
	_credits.tooltip_text = "Credits %s. Reserved for bounties: %s cr (held by the contract board, paid out on the kill; the rest comes back)." % [
			UIUtil.amount(Economy.credits), UIUtil.amount(reserved - zones)] if reserved > 0 else "Credits %s. Nothing reserved for bounties." % UIUtil.amount(Economy.credits)
	if zones > 0:
		_credits.tooltip_text += " Defence zone budgets: %s cr (paid per raider killed inside, the rest comes back when a zone is removed)." % UIUtil.amount(zones)
	var f := Factory.find(get_tree())
	for i in _ore_demand.size():
		var pips := _ore_demand[i]
		pips.visible = f != null
		if f == null:
			continue
		var m := f.market
		var lvl := m.demand_level(i)
		pips.value = float(lvl + 1)
		pips.color = FactoryPanel.DEMAND_COLORS[lvl]
		_ore_labels[i].tooltip_text = "%s %d. Factory demand %s, pays %.1f cr (%s). Auto-sell %s at %.1f cr, keeping %d." % [
				Economy.ORE_NAMES[i], Economy.ore[i], m.demand_name(i).to_lower(), m.willing_price(i), m.trend_text(i),
				"on" if m.auto_sell else "off", m.ask[i], m.reserve[i]] + (" Ask follows the market." if m.is_following(i) else "")


## "+40" after each ore while cargo shuttles have some on the way.
func _update_pending() -> void:
	var pending := CargoDepot.pending_all(get_tree())
	for i in _ore_pending.size():
		var l := _ore_pending[i]
		var n := pending[i] if i < pending.size() else 0
		l.visible = n > 0
		if n > 0:
			l.text = "+%s" % UIUtil.amount(n)
			l.tooltip_text = "%s %s on the way by cargo shuttle (waiting at an outpost or aboard). It counts as yours when it lands at the station." % [
					UIUtil.amount(n), Economy.ORE_NAMES[i].to_lower()]


func _update_shield() -> void:
	var b := StationShield.find(get_tree())
	_shield_box.visible = b != null
	if b == null:
		return
	_shield_bar.value = b.charge()
	_shield_bar.color = DefenseSection.SHIELD_COLOR if b.charge() > 0.25 else PipMeter.BAD
	var text := "%d%%" % roundi(b.charge() * 100.0)
	match b.state:
		StationShield.State.OFFLINE:
			text = "offline"
		StationShield.State.COLLAPSING:
			text = "DOWN"
		StationShield.State.DOWN:
			text = "DOWN %ds" % ceili(b.cooldown_left)
	_shield_value.text = text
	_shield_value.add_theme_color_override("font_color", PipMeter.BAD if not b.is_up() else Color(0.85, 0.93, 1.0))
	_shield_box.tooltip_text = "Station shield: %s, %d / %d HP, radius %d m" % [b.get_state_name().to_lower(), roundi(b.hp), roundi(b.max_hp), roundi(b.radius)]


func _add_divider(parent: HBoxContainer) -> void:
	var d := VSeparator.new()
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.add_theme_constant_override("separation", 14)
	parent.add_child(d)


func _on_economy(credits: int, _materials: int) -> void:
	_credits.text = Economy.format_amount(credits)
	for i in _ore_labels.size():
		_ore_labels[i].text = Economy.format_amount(Economy.ore[i])


func _update_speed() -> void:
	var idx := SimClock.SPEEDS.find(SimClock.speed)
	_speed_pips.value = 0.0 if SimClock.paused else float(idx + 1)
	_speed_icon.texture = HudStyle.icon(&"pause" if SimClock.paused else &"speed")
	_speed_icon.modulate = PipMeter.BAD if SimClock.paused else HudStyle.ACCENT
	if SimClock.paused:
		_speed.text = "PAUSED"
		_speed.add_theme_color_override("font_color", PipMeter.BAD)
	else:
		_speed.text = "%dx" % int(SimClock.speed) if SimClock.speed >= 1.0 else "%.2fx" % SimClock.speed
		_speed.remove_theme_color_override("font_color")

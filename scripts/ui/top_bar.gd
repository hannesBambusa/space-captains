class_name TopBar
extends PanelContainer
## Compact top bar: credits, iron / titanium / crystal (in ore colours, each
## with a small Factory demand meter: 1 to 3 pips, tooltip with its price),
## then the planet goods as one compact group (see [method _make_goods_box]),
## sim time and speed/pause state (one pip per SimClock speed, click to
## cycle). Deliveries flash a short "-credits / +ore" delta next to the
## values; income (station fees, the corporate grant, Factory ore sales)
## flashes a green "+credits" beside it. Deltas landing within one flash add
## up. Ore on its way by cargo shuttle (waiting at an
## outpost or aboard, CargoDepot.pending_all) shows as a small dim "+40"
## after each ore. The credits tooltip shows what is reserved for bounties
## (ContractBoard escrow). With a Shield Generator built, a SHIELD bar
## shows the station bubble's charge (and the countdown while it is down).
## With a Science Lab built, a RESEARCH box shows the projects at work and
## the lead one's progress (tooltip: every funded project, live, from
## ResearchTip; click: select the lab). The credits tooltip also shows what is reserved for research.
## The system name on the left is a menu: the systems the view may switch
## to (ViewManager.viewable_ids; the HUD fills it as it opens), stations
## marked with the station icon.
## Water: with forward stations the water cell always shows, its tooltip
## lists each station's use and how long the stock lasts
## (StationSupply.water_text), and a red "WATER n MIN" warning shows while
## it lasts less than StationSupply.WATER_WARN_MINUTES.
## A click on the credits opens the ledger (L).

## Emitted by the HOME button (the HUD flies the camera to the station).
signal home_pressed
## Emitted by the MAP button (the HUD opens the cluster map).
signal map_pressed
## Emitted by a click on the credits (the HUD opens the ledger).
signal ledger_pressed
## Emitted by a click on the research box (the HUD selects the Science Lab).
signal research_pressed
## The system menu is about to open (the HUD fills it, [method set_system_list]).
signal system_menu_opening
## A system was picked in the system menu.
signal system_picked(id: StringName)

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
## Planet goods group: per good (fuel .. heavy ore) a cell and its count.
var _goods_box: HBoxContainer
var _goods_icon: TextureRect
var _goods_none: Label
var _goods_cells: Array[HBoxContainer] = []
var _goods_labels: Array[Label] = []
## "WATER 3 MIN": the forward stations' water runs out soon.
var _water_warn: Label
var _demand_timer := 0.0
var _time: Label
var _system: MenuButton
var _system_ids: Array[StringName] = []
var _speed_icon: TextureRect
var _speed: Label
var _speed_pips: PipMeter
var _credits_delta: Label
var _income_delta: Label
var _shield_box: HBoxContainer
var _shield_bar: PipMeter
var _shield_value: Label
var _shield_timer := 0.0
var _research_box: ResearchBox
var _research_bar: PipMeter
var _research_value: Label
var _tweens: Dictionary = {}
## Running sums while a delta is still showing: label -> int.
var _sums: Dictionary = {}


## The research box: its tooltip is the live ResearchTip summary.
class ResearchBox:
	extends HBoxContainer

	func _make_custom_tooltip(_for_text: String) -> Object:
		return ResearchTip.make_summary()


## A box with a live rich tooltip: [member tip] fills it (called with the
## RichTooltip). tooltip_text stays a fixed key so the tooltip never closes.
class TipBox:
	extends HBoxContainer

	var tip: Callable
	var accent: Color = HudStyle.HOLO

	func _init(key: String = "tip") -> void:
		tooltip_text = key
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _make_custom_tooltip(_for_text: String) -> Object:
		return RichTooltip.make(tip, accent, 340.0)


## Same for a single label.
class TipLabel:
	extends Label

	var tip: Callable
	var accent: Color = HudStyle.HOLO

	func _init(key: String = "tip") -> void:
		tooltip_text = key

	func _make_custom_tooltip(_for_text: String) -> Object:
		return RichTooltip.make(tip, accent, 340.0)


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
	sys_box.add_child(HudStyle.icon_rect(&"tab_system", 18.0, HudStyle.HOLO))
	_system = MenuButton.new()
	_system.name = "SystemMenu"
	_system.flat = true
	_system.focus_mode = Control.FOCUS_NONE
	_system.add_theme_font_size_override("font_size", 18)
	_system.add_theme_constant_override("h_separation", 0)
	_system.add_theme_font_override("font", HudStyle.font("Bold", true, false, 2))
	_system.add_theme_color_override("font_color", HudStyle.TEXT_BRIGHT)
	_system.add_theme_color_override("font_hover_color", HudStyle.ACCENT)
	_system.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_system.tooltip_text = "View another system (H: back home)"
	_system.about_to_popup.connect(func() -> void: system_menu_opening.emit())
	_system.get_popup().id_pressed.connect(func(i: int) -> void:
		if i >= 0 and i < _system_ids.size():
			system_picked.emit(_system_ids[i]))
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
	var map := UIUtil.button("MAP", &"ChipButton")
	map.icon = HudStyle.icon(&"tab_system")
	map.custom_minimum_size.y = 24.0
	map.tooltip_text = "Cluster map: the gate network you know (M)"
	map.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	map.pressed.connect(func() -> void: map_pressed.emit())
	sys_box.add_child(UIUtil.spacer(4.0))
	sys_box.add_child(map)
	h.add_child(UIUtil.spacer())
	# Centre: resources.
	var res := HBoxContainer.new()
	res.add_theme_constant_override("separation", 4)
	h.add_child(res)
	var credits_box := TipBox.new("Credits")
	credits_box.add_theme_constant_override("separation", 4)
	credits_box.tip = _fill_credits
	credits_box.accent = HudStyle.CREDITS
	credits_box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	res.add_child(credits_box)
	_credits = _add_resource(credits_box, &"credits", HudStyle.CREDITS)
	credits_box.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			ledger_pressed.emit())
	_credits_delta = _add_delta(res, PipMeter.BAD)
	_income_delta = _add_delta(res, PipMeter.GOOD)
	for i in Economy.BASE_COUNT:
		_add_divider(res)
		var box := TipBox.new(Economy.ORE_NAMES[i])
		box.add_theme_constant_override("separation", 4)
		box.tip = _fill_ore.bind(i)
		box.accent = Economy.ORE_COLORS[i]
		res.add_child(box)
		var v := _add_resource(box, Economy.ORE_ICONS[i], Economy.ORE_COLORS[i])
		v.add_theme_color_override("font_color", Economy.ORE_COLORS[i].lerp(Color.WHITE, 0.55))
		var pend := UIUtil.label("", &"SmallLabel")
		pend.add_theme_font_override("font", HudStyle.mono("Regular"))
		pend.add_theme_color_override("font_color", Economy.ORE_COLORS[i].lerp(HudStyle.TEXT_DIM, 0.45))
		pend.mouse_filter = Control.MOUSE_FILTER_PASS
		pend.visible = false
		box.add_child(pend)
		var pips := PipMeter.new()
		pips.style = PipMeter.Style.PIPS
		pips.max_value = 3.0
		pips.pip_size = 4.0
		pips.pip_gap = 2.0
		pips.vertical = true
		box.add_child(pips)
		_ore_pending.append(pend)
		_ore_labels.append(v)
		_ore_demand.append(pips)
		_ore_deltas.append(_add_delta(res, PipMeter.GOOD))
	_make_goods_box(res)
	_shield_box = HBoxContainer.new()
	_shield_box.add_theme_constant_override("separation", 6)
	_shield_box.visible = false
	_shield_box.mouse_filter = Control.MOUSE_FILTER_PASS
	res.add_child(_shield_box)
	_add_divider(_shield_box)
	var si := HudStyle.icon_rect(&"shield", 18.0, DefenseSection.SHIELD_COLOR)
	_shield_box.add_child(si)
	_shield_bar = UIUtil.bar(DefenseSection.SHIELD_COLOR, Vector2(64.0, 5.0))
	_shield_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_shield_box.add_child(_shield_bar)
	_shield_value = UIUtil.label("", &"NumberLabel")
	_shield_value.custom_minimum_size.x = 64.0
	_shield_box.add_child(_shield_value)
	_research_box = ResearchBox.new()
	# A stable key; the live content is the box's custom tooltip.
	_research_box.tooltip_text = "Research"
	_research_box.add_theme_constant_override("separation", 6)
	_research_box.visible = false
	_research_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_research_box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_research_box.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			research_pressed.emit())
	res.add_child(_research_box)
	_add_divider(_research_box)
	_research_box.add_child(HudStyle.icon_rect(&"research", 18.0, ScienceLabPanel.FIELD_COLORS[0]))
	_research_bar = UIUtil.bar(ScienceLabPanel.FIELD_COLORS[0], Vector2(48.0, 5.0))
	_research_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_research_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_research_box.add_child(_research_bar)
	_research_value = UIUtil.label("", &"NumberLabel")
	_research_value.custom_minimum_size.x = 58.0
	_research_box.add_child(_research_value)
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
	# Speed: icon, one pip per SimClock.SPEEDS entry, "24x". Left click =
	# faster (wraps to 1x), right click = slower; either unpauses.
	var speed_box := HBoxContainer.new()
	speed_box.add_theme_constant_override("separation", 8)
	speed_box.mouse_filter = Control.MOUSE_FILTER_STOP
	speed_box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	speed_box.tooltip_text = "Click: faster    Right click: slower\nSpace: pause    1 to 6: 1x to 24x    + / -: faster / slower"
	speed_box.gui_input.connect(_on_speed_input)
	clock_box.add_child(speed_box)
	_speed_icon = HudStyle.icon_rect(&"speed", 14.0, HudStyle.ACCENT)
	speed_box.add_child(_speed_icon)
	_speed_pips = PipMeter.new()
	_speed_pips.style = PipMeter.Style.PIPS
	_speed_pips.max_value = float(SimClock.SPEEDS.size())
	_speed_pips.pip_size = 5.0
	_speed_pips.pip_gap = 2.0
	_speed_pips.color = HudStyle.ACCENT
	speed_box.add_child(_speed_pips)
	_speed = UIUtil.label("", &"NumberLabel")
	_speed.custom_minimum_size.x = 58.0
	speed_box.add_child(_speed)
	tooltip_text = "Space: pause    1 to 6: sim speed 1x to 24x    + / -: faster / slower"
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
	_system.text = text.to_upper() + "  \u25BE"


## The system menu: [param items] = [{id, name, note, current, station}].
func set_system_list(items: Array) -> void:
	var pop := _system.get_popup()
	pop.clear()
	_system_ids.clear()
	for it: Dictionary in items:
		var label := String(it.get("name", "?"))
		var note := String(it.get("note", ""))
		if not note.is_empty():
			label += "   " + note
		if bool(it.get("station", false)):
			pop.add_icon_radio_check_item(HudStyle.icon(&"station"), label, _system_ids.size())
			pop.set_item_icon_max_width(pop.get_item_count() - 1, 16)
			pop.set_item_icon_modulate(pop.get_item_count() - 1, HudStyle.HOLO)
		else:
			pop.add_radio_check_item(label, _system_ids.size())
		pop.set_item_checked(pop.get_item_count() - 1, bool(it.get("current", false)))
		_system_ids.append(StringName(it.get("id", "")))


func _process(delta: float) -> void:
	_demand_timer -= delta
	if _demand_timer <= 0.0:
		_demand_timer = 0.5
		_update_demand()
	_shield_timer -= delta
	if _shield_timer <= 0.0:
		_shield_timer = 0.2
		_update_shield()
		_update_research()
	var t := int(SimClock.time)
	var text := "%02d:%02d:%02d" % [floori(t / 3600.0), floori(t / 60.0) % 60, t % 60]
	if _time.text != text:
		_time.text = text


## Planet goods (phase C2): one compact group after the asteroid ore, a
## small icon and count per good you hold or have on the way, hidden until
## a Raider Dock stands or a good is in stock. The planet icon carries the
## whole list in its tooltip.
func _make_goods_box(res: HBoxContainer) -> void:
	var gb := TipBox.new("Planet goods")
	gb.tip = _fill_goods
	gb.accent = HudStyle.TEXT_DIM
	_goods_box = gb
	_goods_box.add_theme_constant_override("separation", 3)
	_goods_box.visible = false
	res.add_child(_goods_box)
	_add_divider(_goods_box)
	_goods_icon = HudStyle.icon_rect(&"planet", 16.0, HudStyle.TEXT_DIM)
	_goods_icon.mouse_filter = Control.MOUSE_FILTER_PASS
	_goods_box.add_child(_goods_icon)
	_goods_none = UIUtil.label("none", &"SmallLabel")
	_goods_none.add_theme_color_override("font_color", HudStyle.TEXT_FAINT)
	_goods_box.add_child(_goods_none)
	for i in range(Economy.BASE_COUNT, Economy.COUNT):
		var cell: HBoxContainer = HBoxContainer.new()
		if i == Economy.Ore.WATER:
			# Its own tooltip: the forward stations' water.
			var wc := TipBox.new("Water")
			wc.tip = _fill_water
			wc.accent = Economy.ORE_COLORS[i]
			cell = wc
		else:
			cell.mouse_filter = Control.MOUSE_FILTER_PASS
		cell.add_theme_constant_override("separation", 1)
		_goods_box.add_child(cell)
		var ic := HudStyle.icon_rect(Economy.ORE_ICONS[i], 14.0, Economy.ORE_COLORS[i])
		ic.mouse_filter = Control.MOUSE_FILTER_PASS
		cell.add_child(ic)
		var v := UIUtil.label("", &"NumberLabel")
		v.add_theme_color_override("font_color", Economy.ORE_COLORS[i].lerp(Color.WHITE, 0.5))
		v.mouse_filter = Control.MOUSE_FILTER_PASS
		cell.add_child(v)
		_goods_cells.append(cell)
		_goods_labels.append(v)
	var ww := TipLabel.new("Water")
	ww.theme_type_variation = &"SmallLabel"
	ww.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ww.tip = _fill_water
	ww.accent = Economy.ORE_COLORS[Economy.Ore.WATER]
	_water_warn = ww
	_water_warn.add_theme_color_override("font_color", PipMeter.BAD)
	_water_warn.visible = false
	_goods_box.add_child(_water_warn)


## Counts, tooltips and which goods show (held or on the way).
func _update_goods() -> void:
	var pending := CargoDepot.pending_all(self)
	var mgr := BuildingManager.of(self)
	var dock_def := mgr.def_by_id(&"raider_dock") if mgr else null
	var dock := dock_def != null and mgr.count_of(dock_def) > 0
	var any := false
	var stations := not StationSupply.all(get_tree()).is_empty()
	for k in _goods_cells.size():
		var i := Economy.BASE_COUNT + k
		var n := Economy.ore[i]
		var p := pending[i] if i < pending.size() else 0
		var water := i == Economy.Ore.WATER
		var show := n > 0 or p > 0 or (water and stations)
		_goods_cells[k].visible = show
		any = any or show
		_goods_labels[k].text = UIUtil.amount(n) + ("+%s" % UIUtil.amount(p) if p > 0 else "")
		if water and stations:
			var low := StationSupply.water_low(get_tree())
			_goods_labels[k].add_theme_color_override("font_color", PipMeter.BAD if low else Economy.ORE_COLORS[i].lerp(Color.WHITE, 0.5))
			_water_warn.visible = low
			if low:
				var left := StationSupply.water_minutes_left(get_tree())
				_water_warn.text = "WATER OUT" if n <= 0 else "WATER %d MIN" % maxi(floori(left), 0)
	if not stations:
		_water_warn.visible = false
	_goods_box.visible = any or dock
	_goods_none.visible = not any


## Icon (tinted) and value label; the value label carries the tooltip.
func _add_resource(parent: HBoxContainer, icon_name: StringName, tint: Color) -> Label:
	var ic := HudStyle.icon_rect(icon_name, 18.0, tint)
	ic.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(ic)
	var v := UIUtil.label("", &"BigValueLabel")
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(v)
	return v


func _add_delta(parent: HBoxContainer, color: Color) -> Label:
	var l := UIUtil.label("", &"NumberLabel")
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
	# Ore left at an outpost depot shows when its shuttle lands (_on_cargo);
	# planet goods show in their own group.
	if materials != 0 and CargoDepot.of_ship(ship) == null and not (_contract is PlanetRaidContract):
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
	_update_goods()
	var f := Factory.find(self)
	for i in _ore_demand.size():
		var pips := _ore_demand[i]
		pips.visible = f != null
		if f == null:
			continue
		var m := f.market
		var lvl := m.demand_level(i)
		pips.value = float(lvl + 1)
		pips.color = FactoryPanel.DEMAND_COLORS[lvl]


## "+40" after each ore while cargo shuttles have some on the way.
func _update_pending() -> void:
	var pending := CargoDepot.pending_all(self)
	for i in _ore_pending.size():
		var l := _ore_pending[i]
		var n := pending[i] if i < pending.size() else 0
		l.visible = n > 0
		if n > 0:
			l.text = "+%s" % UIUtil.amount(n)


# --- Tooltips -----------------------------------------------------------------------

const USES: PackedStringArray = [
	"Buildings and Mk I parts.",
	"Mk II parts and tooling.",
	"Mk III parts and research. Sells high.",
	"Mk III drives (6 fuel each).",
	"Forward stations drink 2 a minute each.",
	"Mk III parts (4 each).",
	"Mk III shields (8 each). Refine into crystal.",
	"Refine into iron and titanium.",
]
const LEDGER_WINDOW := 600.0


static func _cr(v: float) -> String:
	return "%.1f cr" % v


static func _signed(v: int) -> String:
	if v == 0:
		return "0"
	return ("+%s" if v > 0 else "-%s") % UIUtil.amount(absi(v))


func _fill_credits(t: RichTooltip) -> void:
	t.title("Credits", HudStyle.CREDITS)
	t.stat("In the bank", "%s cr" % UIUtil.amount(Economy.credits))
	var span := clampf(SimClock.time / 60.0, 1.0, LEDGER_WINDOW / 60.0)
	var sum := Economy.ledger.summary(SimClock.time - LEDGER_WINDOW)
	var cats: Dictionary = sum["cats"]
	var esc: Array = cats.get(Ledger.ESCROW, [0, 0])
	# Reserving and returning escrow is churn, not income or spending.
	var got: int = int(sum["in"]) - int(esc[0])
	var spent: int = int(sum["out"]) - int(esc[1])
	t.section("Last %d min" % roundi(span))
	t.stat("Income", "%s  (%s/min)" % [_signed(got), UIUtil.amount(roundi(got / span))], HudStyle.GOOD)
	t.stat("Spending", "%s  (%s/min)" % [_signed(-spent), UIUtil.amount(roundi(spent / span))], HudStyle.BAD if spent > got else HudStyle.TEXT_BRIGHT)
	var net := got - spent
	t.stat("Net", "%s  (%s/min)" % [_signed(net), UIUtil.amount(roundi(net / span))], HudStyle.GOOD if net >= 0 else HudStyle.BAD)
	var zones := ContractBoard.zone_escrow_total()
	var explore := ContractBoard.explore_escrow_total()
	var bounty := ContractBoard.bounty_escrow_total()
	var research := Research.escrow_total()
	var held := bounty + explore + zones + research
	t.section("Reserved")
	if held <= 0:
		t.text("Nothing reserved.", HudStyle.TEXT_DIM)
	else:
		t.stat("Total", "%s cr" % UIUtil.amount(held), HudStyle.WARN)
		if bounty > 0:
			t.stat("Bounties", "%s cr" % UIUtil.amount(bounty))
		if explore > 0:
			t.stat("Exploring", "%s cr" % UIUtil.amount(explore))
		if zones > 0:
			t.stat("Defence zones", "%s cr" % UIUtil.amount(zones))
		if research > 0:
			t.stat("Research", "%s cr" % UIUtil.amount(research))
		t.text("Already out of your credits. What is not paid out comes back.", HudStyle.TEXT_DIM)
	t.hint("Click or L: transaction log")


func _fill_ore(t: RichTooltip, i: int) -> void:
	var col: Color = Economy.ORE_COLORS[i]
	t.title(Economy.ORE_NAMES[i], col.lerp(Color.WHITE, 0.4))
	t.stat("In stock", UIUtil.amount(Economy.ore[i]))
	var pending := CargoDepot.pending_all(self)
	var p := pending[i] if i < pending.size() else 0
	t.stat("On the way", "+%s" % UIUtil.amount(p) if p > 0 else "none", HudStyle.TEXT_BRIGHT if p > 0 else HudStyle.TEXT_DIM)
	if p > 0:
		t.text("In shuttles and outpost depots. Yours once it lands.", HudStyle.TEXT_DIM, 12)
	t.text(USES[i], HudStyle.TEXT)
	var f := Factory.find(self)
	if f == null:
		return
	var m := f.market
	t.section("Factory")
	var lvl := m.demand_level(i)
	var dcol: Color = HudStyle.GOOD if lvl == 2 else (HudStyle.TEXT_BRIGHT if lvl == 1 else HudStyle.WARN)
	t.stat("Pays now", _cr(m.willing_price(i)), dcol)
	t.stat("Range", "%s to %s" % [_cr(m.price_floor[i]), _cr(m.price_ceiling[i])], HudStyle.TEXT_DIM)
	t.stat("Demand", "%s, %s" % [m.demand_name(i).to_lower(), m.trend_text(i)], dcol, false)
	t.stat("Keeps", UIUtil.amount(m.kept(i)))
	var rate := m.expected_rate(i)
	var sell := "off"
	var scol := HudStyle.TEXT_DIM
	if m.auto_sell:
		if m.surplus(i) <= 0:
			sell = "keeping all"
		elif rate >= 0.5:
			sell = "selling %d/min at %s" % [roundi(rate), _cr(m.ask[i])]
			scol = HudStyle.GOOD
		else:
			sell = "not selling, ask %s is too high" % _cr(m.ask[i])
			scol = HudStyle.WARN
	t.stat("Auto-sell", sell, scol, false)


func _fill_goods(t: RichTooltip) -> void:
	t.title("Planet goods", HudStyle.TEXT_BRIGHT)
	var pending := CargoDepot.pending_all(self)
	var f := Factory.find(self)
	for i in range(Economy.BASE_COUNT, Economy.COUNT):
		var p := pending[i] if i < pending.size() else 0
		var v := "%s" % UIUtil.amount(Economy.ore[i])
		if p > 0:
			v += " (+%s)" % UIUtil.amount(p)
		if f:
			v += "   %s" % _cr(f.market.willing_price(i))
		t.stat(Economy.ORE_NAMES[i], v, (Economy.ORE_COLORS[i] as Color).lerp(Color.WHITE, 0.5))
		t.text(USES[i], HudStyle.TEXT_DIM, 12)
	t.section("How to get them")
	t.text("Send landers on planet raids. Each world gives one good: gas giants fuel, ice and ocean water, lava rare metals, desert silicates, rocky heavy ore.", HudStyle.TEXT, 12)
	t.hint("Stock, price per unit, use")


func _fill_water(t: RichTooltip) -> void:
	var tree := get_tree()
	var list := StationSupply.all(tree)
	if list.is_empty():
		_fill_goods(t)
		return
	var i := int(Economy.Ore.WATER)
	t.title("Water", (Economy.ORE_COLORS[i] as Color).lerp(Color.WHITE, 0.4))
	t.stat("In stock", UIUtil.amount(Economy.ore[i]))
	var p := CargoDepot.pending_all(self)[i]
	if p > 0:
		t.stat("On the way", "+%s" % UIUtil.amount(p))
	t.section("Forward stations")
	for s in list:
		t.stat(s.station_name(), "%s/min%s" % [UIUtil.amount(roundi(s.water_per_minute)), ", DRY" if s.dry else ""],
				HudStyle.BAD if s.dry else HudStyle.TEXT_BRIGHT)
	t.stat("Total use", "%s/min" % UIUtil.amount(roundi(StationSupply.water_use_per_minute(tree))))
	var left := StationSupply.water_minutes_left(tree)
	var low := StationSupply.water_low(tree)
	t.stat("Lasts", "about %d min" % floori(left) if left != INF else "for ever", HudStyle.BAD if low else HudStyle.GOOD)
	var f := Factory.find(self)
	if f:
		t.section("Factory")
		t.text("Keeps %s water for the stations (%d min of use). Auto-sell never goes below it." % [
				UIUtil.amount(f.market.kept(i)), roundi(StationSupply.WATER_RESERVE_MINUTES)], HudStyle.TEXT, 12)
		t.stat("Pays now", _cr(f.market.willing_price(i)))
	t.hint("Get more from ice and ocean world raids")


func _update_shield() -> void:
	var b := StationShield.find(self)
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
	_shield_value.add_theme_color_override("font_color", PipMeter.BAD if not b.is_up() else HudStyle.TEXT_BRIGHT)
	_shield_box.tooltip_text = "Station shield: %s, %d / %d HP, radius %d m" % [b.get_state_name().to_lower(), roundi(b.hp), roundi(b.max_hp), roundi(b.radius)]


## Research box: lab built (or projects funded), projects at work, the lead's progress.
func _update_research() -> void:
	var lab := ScienceLab.find(self)
	var active := Research.active_projects()
	_research_box.visible = lab != null or not active.is_empty()
	if not _research_box.visible:
		return
	var working := 0
	for a in active:
		if a["researcher"] != null:
			working += 1
	if active.is_empty():
		_research_bar.value = 0.0
		_research_value.text = "idle"
		_research_value.add_theme_color_override("font_color", HudStyle.TEXT_DIM)
	else:
		var lead: Dictionary = active[0]
		_research_bar.value = float(lead["progress"])
		_research_value.text = "%d  %d%%" % [active.size(), roundi(float(lead["progress"]) * 100.0)]
		_research_value.add_theme_color_override("font_color", HudStyle.TEXT_BRIGHT if working > 0 else HudStyle.WARN)


func _add_divider(parent: HBoxContainer) -> void:
	var d := VSeparator.new()
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.add_theme_constant_override("separation", 14)
	parent.add_child(d)


func _on_economy(credits: int, _materials: int) -> void:
	_credits.text = Economy.format_amount(credits)
	for i in _ore_labels.size():
		_ore_labels[i].text = Economy.format_amount(Economy.ore[i])


func _on_speed_input(e: InputEvent) -> void:
	var mb := e as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		SimClock.step_speed(1, true)
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		SimClock.step_speed(-1)
	else:
		return
	SimClock.set_paused(false)
	accept_event()


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

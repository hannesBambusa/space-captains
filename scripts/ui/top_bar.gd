class_name TopBar
extends PanelContainer
## Top of the flight ops HUD, no bar: the system title block on the left
## (crumb row with HOME / MAP / RIVAL, the system name large and thin as the
## system menu, a summary line), on the right a dark strip with credits,
## iron / titanium / crystal (in ore colours, each
## with a small Factory demand meter: 1 to 3 pips, tooltip with its price),
## then the planet goods as one compact group (see [method _make_goods_box]),
## and under it sim time with the pause mark and the speed steps (click one
## to set it). Deliveries flash a short "-credits / +ore" delta next to the
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
## Emitted by the RIVAL button (the HUD opens the Rival panel).
signal rival_pressed
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
## One line under the system name: kind, star, planets, gates.
var _summary: Label
var _speed_icon: TextureRect
## The speed steps (1x .. 24x), the current one bright.
var _speed_steps: Array[Label] = []
## The clock's speed readout (click faster, right click slower): the
## tutorial's time step pulses it.
var speed_control: Control
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


## The RIVAL button (hidden without a rival); tinted red at war.
var _rival: Button

func _ready() -> void:
	# Flight ops: no bar, the edge shading behind carries the contrast; only
	# the controls take the mouse, the rest passes to the camera.
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = 32.0
	pad.content_margin_top = 16.0
	pad.content_margin_right = 24.0
	add_theme_stylebox_override("panel", pad)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(h)
	_build_title(h)
	h.add_child(_pass(UIUtil.spacer()))
	var right := VBoxContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_theme_constant_override("separation", 6)
	h.add_child(right)
	# Resources on a dark frosted strip (the star often sits up here).
	var strip := PanelContainer.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.size_flags_horizontal = Control.SIZE_SHRINK_END
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(HudStyle.VOID, 0.72)
	sb.content_margin_left = 22.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 6.0
	strip.add_theme_stylebox_override("panel", sb)
	right.add_child(strip)
	var res := HBoxContainer.new()
	res.add_theme_constant_override("separation", 30)
	res.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(res)
	var credits_cell := _resource_cell(res, "Credits", &"credits", HudStyle.CREDITS)
	var credits_box := credits_cell[0] as TipBox
	credits_box.tip = _fill_credits
	credits_box.accent = HudStyle.CREDITS
	credits_box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_credits = credits_cell[1]
	_credits.add_theme_color_override("font_color", HudStyle.CREDITS)
	credits_box.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			ledger_pressed.emit())
	var deltas := credits_cell[2] as HBoxContainer
	_credits_delta = _add_delta(deltas, PipMeter.BAD)
	_income_delta = _add_delta(deltas, PipMeter.GOOD)
	for i in Economy.BASE_COUNT:
		var cell := _resource_cell(res, Economy.ORE_NAMES[i], Economy.ORE_ICONS[i], Economy.ORE_COLORS[i])
		var box := cell[0] as TipBox
		box.tip = _fill_ore.bind(i)
		box.accent = Economy.ORE_COLORS[i]
		var v := cell[1] as Label
		v.add_theme_color_override("font_color", Economy.ORE_COLORS[i].lerp(Color.WHITE, 0.7))
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
		pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(pips)
		_ore_pending.append(pend)
		_ore_labels.append(v)
		_ore_demand.append(pips)
		_ore_deltas.append(_add_delta(cell[2] as HBoxContainer, PipMeter.GOOD))
	_make_goods_box(res)
	_shield_box = HBoxContainer.new()
	_shield_box.add_theme_constant_override("separation", 6)
	_shield_box.visible = false
	_shield_box.mouse_filter = Control.MOUSE_FILTER_PASS
	res.add_child(_shield_box)
	var si := HudStyle.icon_rect(&"shield", 18.0, DefenseSection.SHIELD_COLOR)
	_shield_box.add_child(si)
	_shield_bar = UIUtil.bar(DefenseSection.SHIELD_COLOR, Vector2(64.0, 4.0))
	_shield_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_shield_box.add_child(_shield_bar)
	_shield_value = UIUtil.label("", &"NumberLabel")
	_shield_value.custom_minimum_size.x = 64.0
	_shield_box.add_child(_shield_value)
	# Right: sim time, the speed steps and research, on the row under the strip.
	var clock_row := HBoxContainer.new()
	clock_row.add_theme_constant_override("separation", 16)
	clock_row.alignment = BoxContainer.ALIGNMENT_END
	clock_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(clock_row)
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
	clock_row.add_child(_research_box)
	_research_box.add_child(HudStyle.icon_rect(&"research", 16.0, ScienceLabPanel.FIELD_COLORS[0]))
	_research_bar = UIUtil.bar(ScienceLabPanel.FIELD_COLORS[0], Vector2(48.0, 4.0))
	_research_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_research_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_research_box.add_child(_research_bar)
	_research_value = UIUtil.label("", &"NumberLabel")
	_research_value.custom_minimum_size.x = 58.0
	_research_box.add_child(_research_value)
	var clock := PanelContainer.new()
	clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cb := sb.duplicate() as StyleBoxFlat
	cb.content_margin_top = 4.0
	cb.content_margin_bottom = 4.0
	clock.add_theme_stylebox_override("panel", cb)
	clock_row.add_child(clock)
	var clock_box := HBoxContainer.new()
	clock_box.add_theme_constant_override("separation", 18)
	clock_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock.add_child(clock_box)
	_time = UIUtil.label("", &"BigValueLabel")
	_time.add_theme_font_override("font", HudStyle.mono("Regular"))
	_time.add_theme_font_size_override("font_size", 22)
	_time.custom_minimum_size.x = 150.0
	clock_box.add_child(_time)
	# Speed: pause and one step per SimClock.SPEEDS entry; click a step to
	# set it. Left click elsewhere on the row = faster (wraps to 1x), right
	# click = slower; either unpauses.
	var speed_box := HBoxContainer.new()
	speed_box.add_theme_constant_override("separation", 12)
	speed_box.mouse_filter = Control.MOUSE_FILTER_STOP
	speed_box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	speed_box.tooltip_text = "Click: set speed    Right click: slower\nSpace: pause    1 to 6: 1x to 24x    + / -: faster / slower"
	speed_box.gui_input.connect(_on_speed_input)
	speed_control = speed_box
	clock_box.add_child(speed_box)
	_speed_icon = HudStyle.icon_rect(&"pause", 14.0, HudStyle.TEXT_FAINT)
	_speed_icon.mouse_filter = Control.MOUSE_FILTER_PASS
	speed_box.add_child(_speed_icon)
	for i in SimClock.SPEEDS.size():
		var step := UIUtil.label("%dx" % int(SimClock.SPEEDS[i]), &"SmallLabel")
		step.add_theme_font_override("font", HudStyle.mono("Regular"))
		step.mouse_filter = Control.MOUSE_FILTER_PASS
		step.set_meta(&"speed", SimClock.SPEEDS[i])
		speed_box.add_child(step)
		_speed_steps.append(step)
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


## The system name on the left (set by the HUD once the system is built),
## with the summary line under it from the viewed system.
func set_system_name(text: String) -> void:
	_system.text = text
	var w := SystemWorld.of(self)
	var ss := SolarSystem.of(self)
	var def := ss.system_def if ss else null
	var parts: PackedStringArray = []
	if w:
		parts.append("Home system" if w.is_home else ("Station system" if w.has_station else "No station"))
	if def:
		parts.append("class %s star" % def.star_class)
		parts.append("%d planets" % def.planets.size())
		if def.gates.size() > 0:
			parts.append("%d gate%s" % [def.gates.size(), "" if def.gates.size() == 1 else "s"])
	_summary.text = ", ".join(parts)


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
		_update_rival()
	var t := int(SimClock.time)
	var text := "T+ %02d:%02d:%02d" % [floori(t / 3600.0), floori(t / 60.0) % 60, t % 60]
	if _time.text != text:
		_time.text = text


## Left: a crumb row (SYSTEM, the HOME / MAP / RIVAL chips), the system name
## large and thin (the system menu), and a one-line summary.
func _build_title(h: HBoxContainer) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(col)
	var crumb := HBoxContainer.new()
	crumb.add_theme_constant_override("separation", 6)
	crumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(crumb)
	crumb.add_child(_pass(UIUtil.label("SYSTEM", &"SubHeaderLabel")))
	crumb.add_child(_pass(UIUtil.spacer(6.0)))
	var home := _chip("HOME", "Fly to the home station (H)")
	home.pressed.connect(func() -> void: home_pressed.emit())
	crumb.add_child(home)
	var map := _chip("MAP", "Cluster map: the gate network you know (M)")
	map.pressed.connect(func() -> void: map_pressed.emit())
	crumb.add_child(map)
	# The rival corporation (only in games with one).
	_rival = _chip("RIVAL", "The rival corporation: diplomacy, war and intel (R)")
	_rival.pressed.connect(func() -> void: rival_pressed.emit())
	_rival.visible = Corps.has_rival()
	crumb.add_child(_rival)
	_system = MenuButton.new()
	_system.name = "SystemMenu"
	_system.flat = true
	_system.focus_mode = Control.FOCUS_NONE
	_system.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_system.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_system.add_theme_font_size_override("font_size", 46)
	_system.add_theme_constant_override("h_separation", 0)
	_system.add_theme_font_override("font", HudStyle.font("Thin", false, false, 1))
	_system.add_theme_color_override("font_color", HudStyle.TEXT_BRIGHT)
	_system.add_theme_color_override("font_hover_color", HudStyle.ACCENT_SOFT)
	_system.add_theme_color_override("font_pressed_color", HudStyle.ACCENT)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var e := StyleBoxEmpty.new()
		e.content_margin_left = 0.0
		e.content_margin_top = 0.0
		e.content_margin_bottom = 0.0
		_system.add_theme_stylebox_override(st, e)
	_system.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_system.tooltip_text = "View another system (H: back home)"
	_system.about_to_popup.connect(func() -> void: system_menu_opening.emit())
	_system.get_popup().id_pressed.connect(func(i: int) -> void:
		if i >= 0 and i < _system_ids.size():
			system_picked.emit(_system_ids[i]))
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_row)
	name_row.add_child(_system)
	var arrow := UIUtil.label("\u25BE", &"DimLabel")
	arrow.add_theme_font_size_override("font_size", 18)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(arrow)
	_summary = UIUtil.label("", &"DimLabel")
	_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_summary)


## A small flat chip for the crumb row.
func _chip(text: String, tip: String) -> Button:
	var b := UIUtil.button(text, &"ChipButton")
	b.custom_minimum_size.y = 22.0
	b.tooltip_text = tip
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


## [param c] with the mouse passing through (layout pieces of the bar).
static func _pass(c: Control) -> Control:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## One resource: a small caption with its icon, the value large and thin
## (in a [TipBox] that carries the tooltip), a row for the deltas under it.
## Returns [box, value label, delta row].
func _resource_cell(parent: HBoxContainer, caption: String, icon_name: StringName, tint: Color) -> Array:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(col)
	var cap := HBoxContainer.new()
	cap.add_theme_constant_override("separation", 5)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(cap)
	cap.add_child(HudStyle.icon_rect(icon_name, 12.0, tint))
	cap.add_child(_pass(UIUtil.label(caption.to_upper(), &"SubHeaderLabel")))
	var box := TipBox.new(caption)
	box.add_theme_constant_override("separation", 4)
	col.add_child(box)
	var v := UIUtil.label("", &"BigValueLabel")
	v.add_theme_font_override("font", HudStyle.font("Thin", false, true))
	v.add_theme_font_size_override("font_size", 34)
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(v)
	var deltas := HBoxContainer.new()
	deltas.add_theme_constant_override("separation", 4)
	deltas.custom_minimum_size.y = 16.0
	deltas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(deltas)
	return [box, v, deltas]


## Planet goods (phase C2): one compact group after the asteroid ore, a
## small icon and count per good you hold or have on the way, hidden until
## Surface operations is researched or a good is in stock. The planet icon carries the
## whole list in its tooltip.
func _make_goods_box(res: HBoxContainer) -> void:
	var gb := TipBox.new("Planet goods")
	gb.tip = _fill_goods
	gb.accent = HudStyle.TEXT_DIM
	_goods_box = gb
	_goods_box.add_theme_constant_override("separation", 3)
	_goods_box.visible = false
	res.add_child(_goods_box)
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
	var dock := Research.is_done(OutpostState.TECH)
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


func _add_delta(parent: Container, color: Color) -> Label:
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
	t.text("Found planet outposts (research Surface operations): harvesters gather one good per world and shuttles lift it up. Ice and ocean worlds give water, lava rare metals, desert silicates, rocky heavy ore, and gas giants fuel (from a floating platform).", HudStyle.TEXT, 12)
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


## Research box: shown only while a Science Lab stands idle (nothing funded);
## with projects funded the HUD's research list under the clock shows them.
func _update_research() -> void:
	var lab := ScienceLab.find(self)
	var active := Research.active_projects()
	_research_box.visible = lab != null and active.is_empty()
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


func _on_economy(credits: int, _materials: int) -> void:
	_credits.text = Economy.format_amount(credits)
	for i in _ore_labels.size():
		_ore_labels[i].text = Economy.format_amount(Economy.ore[i])


func _on_speed_input(e: InputEvent) -> void:
	var mb := e as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		var hit := _speed_step_at(mb.position)
		if hit:
			SimClock.set_speed(float(hit.get_meta(&"speed")))
		elif _speed_icon.get_rect().has_point(mb.position):
			SimClock.set_paused(not SimClock.paused)
			accept_event()
			return
		else:
			SimClock.step_speed(1, true)
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		SimClock.step_speed(-1)
	else:
		return
	SimClock.set_paused(false)
	accept_event()


## The speed step under [param pos] (the speed row's local position), or null.
func _speed_step_at(pos: Vector2) -> Label:
	for step in _speed_steps:
		if step.get_rect().grow(6.0).has_point(pos):
			return step
	return null


func _update_speed() -> void:
	_speed_icon.texture = HudStyle.icon(&"pause")
	_speed_icon.modulate = PipMeter.BAD if SimClock.paused else HudStyle.TEXT_DIM
	for step in _speed_steps:
		var on := not SimClock.paused and is_equal_approx(float(step.get_meta(&"speed")), SimClock.speed)
		step.add_theme_color_override("font_color", HudStyle.ACCENT if on else HudStyle.TEXT_DIM)
		step.queue_redraw()
	if _time:
		_time.add_theme_color_override("font_color", PipMeter.BAD if SimClock.paused else HudStyle.TEXT_BRIGHT)


## The RIVALS button: shown with rivals; one rival's stance after contact,
## with several the count met and at war; red while any is at war with you.
func _update_rival() -> void:
	if _rival == null:
		return
	_rival.visible = Corps.has_rival()
	if not Corps.has_rival():
		return
	var war := 0
	var met := 0
	var gone := 0
	for r in Corps.rivals:
		if r.mind.eliminated:
			gone += 1
		elif Corps.corps_at_war(r.id, Corps.PLAYER):
			war += 1
		if r.mind.tie(Corps.PLAYER).contact:
			met += 1
	var text := "RIVALS"
	if Corps.rivals.size() == 1:
		var r := Corps.rivals[0]
		var t := r.mind.tie(Corps.PLAYER)
		text = "RIVAL: GONE" if gone > 0 else "RIVAL: WAR" if war > 0 else "RIVAL" if not t.contact else "RIVAL: %s" % t.stance_name().to_upper()
	else:
		text = "RIVALS %d" % Corps.rivals.size()
		if met > 0:
			text += ": %d MET" % met
		if war > 0:
			text += ", %d AT WAR" % war
	if _rival.text != text:
		_rival.text = text
	_rival.add_theme_color_override("font_color", HudStyle.BAD if war > 0 else HudStyle.TEXT_BRIGHT)

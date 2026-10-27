class_name FactoryPanel
extends PanelContainer
## Bottom-right panel for the selected Factory (BuildingPanel makes it and
## hands Factory selections over). Ore market per type: Factory stock bar,
## demand meter, what it pays now and the trend, the player's asking price
## with the expected sales rate ("auto" while it follows the market), and
## the "keep at least" reserve; auto-sell
## on/off. Production: current item and progress, backorders, warehouse
## counts by slot and tier, tooling upgrades, and recent sales and output.
## Tabs (the CaptainPanel idiom): "Production" (current job with progress
## and ETA, the open buy orders in production order with captain, deposit
## and state, the equipment demand table, the warehouse grid) and "Market"
## (ore market, auto-sell, tooling, recent). Warehouse cells and demand rows
## show what each module does in numbers and the research it still needs. The hidden tab keeps the
## height of the taller one, so the panel does not jump when switching.

const DEMAND_COLORS: Array[Color] = [HudStyle.TEXT_DIM, Color(1.0, 0.78, 0.25), Color(0.35, 0.9, 0.5)]
const MAX_RECENT := 6
const MAX_ORDERS := 6
const MAX_DEMAND := 10
const STATE_COLORS := {
	"ready": Color(0.35, 0.9, 0.5), "making": Color(0.55, 0.85, 1.0), "next": HudStyle.TEXT_BRIGHT,
	"queued": HudStyle.TEXT_DIM, "ore": Color(1.0, 0.78, 0.25), "tooling": Color(1.0, 0.6, 0.4),
}

@export var panel_width: float = 400.0

var hud: HUD
var building: Building
var factory: Factory

var _title: Label
var _status: Label
var _job_name: Label
var _job_bar: ProgressBar
var _job_eta: Label
var _orders_header: Label
var _orders_list: VBoxContainer
var _demand_list: GridContainer
var _production: VBoxContainer
var _market_tab: VBoxContainer
var _tab_buttons: Array[Button] = []
## 0 = Production, 1 = Market.
var _tab: int = 0
var _tab_height: float = 0.0
var _auto: CheckButton
## Per ore: {stock_bar, stock, demand_meter, demand, price, ask, rate, keep}.
var _ore_rows: Array[Dictionary] = []
var _goods_header: Label
var _orders: Label
var _ware_header: Label
## [slot][tier - 1] -> Label.
var _ware_cells: Array = []
var _tool_label: Label
var _tool_button: Button
var _tool_reason: Label
var _recent: VBoxContainer
var _tick := 0.0


func _ready() -> void:
	custom_minimum_size.x = panel_width
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	top.add_child(UIUtil.label("STRUCTURE", &"HeaderLabel"))
	top.add_child(UIUtil.spacer(6.0))
	var tabs := ButtonGroup.new()
	for i in 2:
		var tb := UIUtil.button("Production" if i == 0 else "Market", &"IconButton")
		tb.toggle_mode = true
		tb.button_group = tabs
		tb.button_pressed = i == 0
		tb.custom_minimum_size = Vector2(84.0, 22.0)
		tb.tooltip_text = "What is being made, buy orders and equipment demand" if i == 0 else "Ore market, auto-sell and tooling"
		tb.pressed.connect(set_tab.bind(i))
		top.add_child(tb)
		_tab_buttons.append(tb)
	top.add_child(UIUtil.spacer())
	var close := UIUtil.button("x", &"IconButton")
	close.custom_minimum_size = Vector2(26.0, 22.0)
	close.tooltip_text = "Deselect (Esc)"
	close.pressed.connect(func() -> void:
		if hud and hud.selection:
			hud.selection.deselect())
	top.add_child(close)
	_title = UIUtil.label("Factory", &"TitleLabel")
	v.add_child(_title)
	_status = UIUtil.label("", &"ValueLabel")
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.custom_minimum_size.x = panel_width - 24.0
	v.add_child(_status)
	var root := v
	_production = VBoxContainer.new()
	_production.add_theme_constant_override("separation", 5)
	root.add_child(_production)
	_market_tab = VBoxContainer.new()
	_market_tab.add_theme_constant_override("separation", 5)
	_market_tab.visible = false
	root.add_child(_market_tab)
	_build_production(_production)

	v = _market_tab
	v.add_child(HSeparator.new())
	var mh := HBoxContainer.new()
	v.add_child(mh)
	mh.add_child(UIUtil.label("ORE MARKET", &"HeaderLabel"))
	mh.add_child(UIUtil.spacer())
	_auto = CheckButton.new()
	_auto.text = "Auto-sell"
	_auto.focus_mode = Control.FOCUS_NONE
	_auto.tooltip_text = "The Factory buys your ore above the reserve over time at your asking price. Off: you keep everything."
	_auto.toggled.connect(func(on: bool) -> void:
		if factory:
			factory.market.set_auto_sell(on))
	mh.add_child(_auto)
	for i in FactoryMarket.TYPES:
		if i == Economy.BASE_COUNT:
			_goods_header = UIUtil.label("PLANET GOODS", &"SubHeaderLabel")
			_goods_header.tooltip_text = "Brought back from planet raids (Raider Dock). Shown once raids are researched or you hold some."
			v.add_child(_goods_header)
		_ore_rows.append(_make_ore_row(v, i))

	v.add_child(HSeparator.new())
	_tool_label = UIUtil.label("", &"DimLabel")
	_tool_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tool_label.custom_minimum_size.x = panel_width - 24.0
	v.add_child(_tool_label)
	_tool_button = UIUtil.button("", &"AccentButton")
	_tool_button.pressed.connect(func() -> void:
		if factory:
			factory.upgrade_tooling())
	v.add_child(_tool_button)
	_tool_reason = UIUtil.label("", &"WarnLabel")
	v.add_child(_tool_reason)

	v.add_child(UIUtil.label("RECENT", &"HeaderLabel"))
	_recent = VBoxContainer.new()
	_recent.add_theme_constant_override("separation", 0)
	v.add_child(_recent)


## Production tab: job, orders, equipment demand, warehouse.
func _build_production(v: VBoxContainer) -> void:
	v.add_child(HSeparator.new())
	v.add_child(UIUtil.label("NOW MAKING", &"HeaderLabel"))
	var jr := HBoxContainer.new()
	jr.add_theme_constant_override("separation", 8)
	v.add_child(jr)
	_job_name = UIUtil.label("", &"ValueLabel")
	_job_name.custom_minimum_size.x = 170.0
	_job_name.clip_text = true
	_job_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	jr.add_child(_job_name)
	_job_bar = ProgressBar.new()
	_job_bar.show_percentage = false
	_job_bar.max_value = 1.0
	_job_bar.custom_minimum_size = Vector2(80.0, 6.0)
	_job_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_job_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_job_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	jr.add_child(_job_bar)
	_job_eta = UIUtil.label("", &"DimLabel")
	_job_eta.custom_minimum_size.x = 64.0
	_job_eta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	jr.add_child(_job_eta)

	v.add_child(HSeparator.new())
	_orders_header = UIUtil.label("", &"HeaderLabel")
	_orders_header.mouse_filter = Control.MOUSE_FILTER_PASS
	_orders_header.tooltip_text = "Captains pay up front when they order. They pick the part up at the Outfitter; a cancelled or lapsed order is refunded."
	v.add_child(_orders_header)
	_orders_list = VBoxContainer.new()
	_orders_list.add_theme_constant_override("separation", 0)
	v.add_child(_orders_list)
	_orders = UIUtil.label("", &"DimLabel")
	_orders.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_orders.custom_minimum_size.x = panel_width - 24.0
	v.add_child(_orders)

	v.add_child(HSeparator.new())
	var dh := UIUtil.label("EQUIPMENT DEMAND", &"HeaderLabel")
	dh.mouse_filter = Control.MOUSE_FILTER_PASS
	dh.tooltip_text = "Parts captains want: open orders, recent misses (wanted it, none in stock) and parts your hired captains could use that the warehouse has none of."
	v.add_child(dh)
	_demand_list = GridContainer.new()
	_demand_list.columns = 5
	_demand_list.add_theme_constant_override("h_separation", 10)
	_demand_list.add_theme_constant_override("v_separation", 0)
	v.add_child(_demand_list)

	v.add_child(HSeparator.new())
	_ware_header = UIUtil.label("", &"HeaderLabel")
	v.add_child(_ware_header)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 0)
	v.add_child(grid)
	grid.add_child(UIUtil.label("", &"DimLabel"))
	for t in range(1, 4):
		var th := UIUtil.label(ShipModule.TIER_NAMES[t], &"DimLabel")
		th.add_theme_color_override("font_color", CaptainPanel.TIER_COLORS[t])
		th.custom_minimum_size.x = 56.0
		th.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		th.mouse_filter = Control.MOUSE_FILTER_PASS
		th.tooltip_text = "%s: %s, %d s each" % [ShipModule.TIER_NAMES[t], Economy.cost_text(Factory.ore_cost_tier(t)), roundi(Factory.TIER_TIME[t])]
		grid.add_child(th)
	for slot in ShipModule.SLOT_NAMES.size():
		var name_l := UIUtil.label(ShipModule.SLOT_NAMES[slot], &"DimLabel")
		name_l.custom_minimum_size.x = 120.0
		grid.add_child(name_l)
		var row: Array[Label] = []
		for t in 3:
			var cell := UIUtil.label("", &"NumberLabel")
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			cell.custom_minimum_size.x = 56.0
			cell.mouse_filter = Control.MOUSE_FILTER_PASS
			grid.add_child(cell)
			row.append(cell)
		_ware_cells.append(row)


func _make_ore_row(parent: VBoxContainer, ore: int) -> Dictionary:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	parent.add_child(box)
	var a := HBoxContainer.new()
	a.add_theme_constant_override("separation", 6)
	box.add_child(a)
	var name_l := UIUtil.label(Economy.ORE_NAMES[ore], &"ValueLabel")
	name_l.add_theme_color_override("font_color", Economy.ORE_COLORS[ore])
	name_l.custom_minimum_size.x = 70.0
	a.add_child(name_l)
	var bar := PipMeter.new()
	bar.style = PipMeter.Style.BAR
	bar.color = Economy.ORE_COLORS[ore].darkened(0.15)
	bar.custom_minimum_size = Vector2(70.0, 5.0)
	a.add_child(bar)
	var stock := UIUtil.label("", &"DimLabel")
	stock.custom_minimum_size.x = 64.0
	a.add_child(stock)
	var meter := PipMeter.new()
	meter.style = PipMeter.Style.PIPS
	meter.max_value = 3.0
	meter.pip_size = 6.0
	meter.pip_gap = 2.0
	a.add_child(meter)
	var demand := UIUtil.label("", &"DimLabel")
	demand.custom_minimum_size.x = 52.0
	a.add_child(demand)
	a.add_child(UIUtil.spacer())
	var price := UIUtil.label("", &"NumberLabel")
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	a.add_child(price)
	a.mouse_filter = Control.MOUSE_FILTER_PASS

	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", 3)
	box.add_child(b)
	b.add_child(UIUtil.spacer(16.0))
	b.add_child(UIUtil.label("Ask", &"DimLabel"))
	var minus := UIUtil.step_button("-", "Lower the asking price: sells faster. Turns follow market off.", Vector2(22.0, 22.0))
	minus.pressed.connect(func() -> void:
		if factory:
			factory.market.step_ask(ore, -1))
	b.add_child(minus)
	var ask := UIUtil.label("", &"NumberLabel")
	ask.custom_minimum_size.x = 64.0
	ask.mouse_filter = Control.MOUSE_FILTER_PASS
	ask.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_child(ask)
	var plus := UIUtil.step_button("+", "Raise the asking price: more per unit, slower sales. Turns follow market off.", Vector2(22.0, 22.0))
	plus.pressed.connect(func() -> void:
		if factory:
			factory.market.step_ask(ore, 1))
	b.add_child(plus)
	var match_b := UIUtil.step_button("=", "Follow market: the ask tracks just under what the Factory pays", Vector2(22.0, 22.0))
	match_b.custom_minimum_size.x = 24.0
	match_b.pressed.connect(func() -> void:
		if factory:
			factory.market.match_market(ore))
	b.add_child(match_b)
	var rate := UIUtil.label("", &"DimLabel")
	rate.custom_minimum_size.x = 76.0
	rate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_child(rate)
	b.add_child(UIUtil.spacer())
	var keep_l := UIUtil.label("Keep", &"DimLabel")
	keep_l.mouse_filter = Control.MOUSE_FILTER_PASS
	b.add_child(keep_l)
	var kminus := UIUtil.step_button("-", "Keep less %s back from auto-sell" % Economy.ore_name(ore), Vector2(22.0, 22.0))
	kminus.pressed.connect(func() -> void:
		if factory:
			var m := factory.market
			m.set_reserve(ore, m.reserve[ore] - m.reserve_step[ore]))
	b.add_child(kminus)
	var keep := UIUtil.label("", &"NumberLabel")
	keep.custom_minimum_size.x = 38.0
	keep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keep.mouse_filter = Control.MOUSE_FILTER_PASS
	b.add_child(keep)
	var kplus := UIUtil.step_button("+", "Keep more %s back from auto-sell, for building" % Economy.ore_name(ore), Vector2(22.0, 22.0))
	kplus.pressed.connect(func() -> void:
		if factory:
			var m := factory.market
			m.set_reserve(ore, m.reserve[ore] + m.reserve_step[ore]))
	b.add_child(kplus)
	var refine: Button = null
	if FactoryMarket.REFINE.has(ore):
		refine = UIUtil.button("Refine", &"IconButton")
		refine.custom_minimum_size = Vector2(56.0, 22.0)
		refine.pressed.connect(func() -> void:
			if factory:
				factory.market.refine(ore, 10 if Input.is_key_pressed(KEY_SHIFT) else 1))
		a.add_child(refine)
	return {"box": box, "row": a, "stock_bar": bar, "stock": stock, "meter": meter, "demand": demand, "price": price, "ask": ask, "rate": rate, "keep": keep, "keep_label": keep_l, "refine": refine}



func setup(owner_hud: HUD) -> void:
	hud = owner_hud
	if hud.selection:
		hud.selection.selection_changed.connect(func(t: Node3D) -> void: show_building(t as Building))


func show_building(b: Building) -> void:
	var f := b.get_service() as Factory if b else null
	if factory and is_instance_valid(factory) and factory.changed.is_connected(_refresh):
		factory.changed.disconnect(_refresh)
	building = b if f else null
	factory = f
	visible = f != null
	if f == null:
		return
	f.changed.connect(_refresh)
	_title.text = b.display_name
	_refresh()


## 0 = Production, 1 = Market. The hidden tab keeps the taller one's height.
func set_tab(index: int) -> void:
	var cur := _production if _tab == 0 else _market_tab
	if cur.visible and cur.size.y > 0.0:
		_tab_height = maxf(_tab_height, cur.size.y)
	_tab = index
	_tab_buttons[index].set_pressed_no_signal(true)
	_tab_buttons[1 - index].set_pressed_no_signal(false)
	_production.visible = index == 0
	_market_tab.visible = index == 1
	_production.custom_minimum_size.y = _tab_height
	_market_tab.custom_minimum_size.y = _tab_height
	_refresh()


func get_tab() -> int:
	return _tab


func _process(delta: float) -> void:
	if not visible or factory == null or not is_instance_valid(factory):
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.25
		_refresh_live()


## Status, prices and rates (they move every frame of sim time).
func _refresh_live() -> void:
	var f := factory
	_status.text = f.status_text()
	_job_bar.value = f.job_progress()
	_job_bar.visible = f.job != null
	_status.visible = _tab == 1 or f.job == null
	if f.job:
		_job_name.text = f.job.display_name
		_job_name.add_theme_color_override("font_color", CaptainPanel.TIER_COLORS[f.job.tier])
		_job_eta.text = "%d s left" % ceili(f.job_eta())
	else:
		_job_name.text = "Nothing" if f.building.is_active() else "-"
		_job_name.remove_theme_color_override("font_color")
		_job_eta.text = ""
	if _tab != 1:
		return
	var m := f.market
	var goods_on := Research.is_building_unlocked(&"raider_dock")
	for i in range(Economy.BASE_COUNT, _ore_rows.size()):
		goods_on = goods_on or Economy.ore[i] > 0 or m.stock[i] >= 1.0
	if _goods_header:
		_goods_header.visible = goods_on
	for i in _ore_rows.size():
		var r := _ore_rows[i]
		(r["box"] as Control).visible = i < Economy.BASE_COUNT or goods_on
		var rb := r["refine"] as Button
		if rb:
			rb.disabled = m.refine_batches(i) <= 0
			rb.tooltip_text = "Refine %s (Shift: ten at once). You have %d %s." % [m.refine_text(i), Economy.ore[i], Economy.ore_name(i)]
		var bar := r["stock_bar"] as PipMeter
		bar.max_value = m.target_stock[i] * 2.0
		bar.value = m.stock[i]
		(r["stock"] as Label).text = "%d / %d" % [roundi(m.stock[i]), roundi(m.target_stock[i])]
		var lvl := m.demand_level(i)
		var meter := r["meter"] as PipMeter
		meter.value = float(lvl + 1)
		meter.color = DEMAND_COLORS[lvl]
		var dl := r["demand"] as Label
		dl.text = m.demand_name(i)
		dl.add_theme_color_override("font_color", DEMAND_COLORS[lvl])
		var trend := m.trend_text(i)
		(r["price"] as Label).text = "pays %.1f cr" % m.willing_price(i) + ("  %+.1f" % m.trend(i) if trend != "steady" else "")
		var al := r["ask"] as Label
		al.text = "%.1f auto" % m.ask[i] if m.is_following(i) else "%.1f" % m.ask[i]
		al.tooltip_text = ("Follows the market at %d%% of what the Factory pays. +/- set it by hand." % roundi(m.follow_margin * 100.0)) \
				if m.is_following(i) else "Set by hand. = follows the market again."
		var rate := m.buy_rate_at(i, m.ask[i])
		var rl := r["rate"] as Label
		if not m.auto_sell:
			rl.text = "auto-sell off"
		elif m.surplus(i) <= 0:
			rl.text = "keeping all" if Economy.ore[i] > 0 else "none to sell"
		else:
			rl.text = "~%d/min" % roundi(rate)
		rl.add_theme_color_override("font_color", PipMeter.GOOD if rate >= m.max_buy_per_min[i] * 0.5 else (PipMeter.MID if rate > 0.0 else PipMeter.BAD))
		var stations := m.station_water(i)
		(r["keep"] as Label).text = str(m.kept(i)) + ("*" if stations > m.reserve[i] else "")
		var keep_tip := "Keep %d %s (selling stops below this; building, research and tooling still use it). You have %d." % [
				m.reserve[i], Economy.ore_name(i), Economy.ore[i]]
		if stations > 0:
			keep_tip += "\nForward stations: at least %d kept (%d min of their water use)." % [stations, roundi(StationSupply.WATER_RESERVE_MINUTES)]
		(r["keep"] as Label).tooltip_text = keep_tip
		(r["keep_label"] as Label).tooltip_text = keep_tip
		var tip := "%s: Factory stock %d (target %d), demand %s, pays %.1f cr (%s). Your ask %.1f cr sells ~%.0f/min above %d kept. Export draws %.0f + %d%%/min." % [
				Economy.ORE_NAMES[i], roundi(m.stock[i]), roundi(m.target_stock[i]), m.demand_name(i).to_lower(), m.willing_price(i), trend,
				m.ask[i], rate, m.kept(i), m.export_base_per_min[i], roundi(m.export_share_per_min[i] * 100.0)]
		(r["row"] as Control).tooltip_text = tip
		rl.tooltip_text = "At or below %d%% of what the Factory pays it buys at full pace; past %d%% it stops." % [roundi(m.eager_ratio * 100.0), roundi(m.refuse_ratio * 100.0)]


func _refresh() -> void:
	if factory == null or not is_instance_valid(factory):
		return
	var f := factory
	_auto.set_pressed_no_signal(f.market.auto_sell)
	_refresh_live()
	# Warehouse by slot and tier.
	# counts[slot * 3 + tier - 1]
	var counts := PackedInt32Array()
	counts.resize(ShipModule.SLOT_NAMES.size() * 3)
	var catalog := ModuleCatalog.shared()
	for id: StringName in f.warehouse:
		var mod := catalog.find(id)
		if mod and mod.tier >= 1:
			counts[mod.slot * 3 + mod.tier - 1] += int(f.warehouse[id])
	for s in _ware_cells.size():
		var row: Array[Label] = _ware_cells[s]
		for t in 3:
			var n := counts[s * 3 + t]
			var can := f.tooling_tier >= t + 1
			row[t].tooltip_text = ModuleTips.cell_tip(s, t + 1, f)
			row[t].text = str(n) if n > 0 else ("0" if can else "-")
			row[t].add_theme_color_override("font_color", CaptainPanel.TIER_COLORS[t + 1] if n > 0 else HudStyle.TEXT_FAINT)
	_ware_header.text = "WAREHOUSE  %d / %d   (%d made)" % [f.warehouse_total(), f.warehouse_cap, f.total_built]
	_rebuild_orders()
	_rebuild_demand()
	# Tooling.
	var rare: PackedStringArray = []
	for id: StringName in f.rare_parts:
		var rm := catalog.find(id)
		if rm:
			rare.append("%s %s" % [rm.display_name, "early" if f.rare_parts[id] == "stocked" else "-%d%%" % roundi(Factory.RARE_DISCOUNT * 100.0)])
	_tool_label.text = "Tooled for %s. Mk I needs iron, Mk II titanium, Mk III crystal and rare metals; Mk III drives burn fuel.%s" % [
			ShipModule.TIER_NAMES[f.tooling_tier], "  Rare parts: " + ", ".join(rare) if not rare.is_empty() else ""]
	var cost := f.next_tooling_cost()
	_tool_button.visible = not cost.is_empty()
	var why := f.tooling_block_reason() if not cost.is_empty() else ""
	if not cost.is_empty():
		var next := ShipModule.TIER_NAMES[mini(f.tooling_tier + 1, 3)]
		_tool_button.text = "Tool for %s - %s" % [next, Economy.cost_text(cost)]
		_tool_button.tooltip_text = why if not why.is_empty() else "Lets the Factory make %s modules (from your ore stock)." % next
	_tool_button.disabled = not why.is_empty()
	_tool_reason.text = why
	_tool_reason.visible = not why.is_empty()
	_rebuild_recent()


## Open buy orders in production order: part, captain, deposit, state.
func _rebuild_orders() -> void:
	for c in _orders_list.get_children():
		_orders_list.remove_child(c)
		c.queue_free()
	var f := factory
	var orders := f.orders_in_production_order()
	_orders_header.text = "BUY ORDERS  %d open, %s cr paid" % [orders.size(), UIUtil.amount(f.deposits_total())] if not orders.is_empty() else "BUY ORDERS"
	_orders.visible = orders.is_empty() or orders.size() > MAX_ORDERS
	if orders.is_empty():
		_orders.text = "No open orders. Spare capacity goes to a spread of parts for the captains you hired."
		return
	_orders.text = "and %d more" % (orders.size() - MAX_ORDERS)
	for i in mini(orders.size(), MAX_ORDERS):
		var o := orders[i]
		var m := o["module"] as ShipModule
		var cap := o["captain"] as Captain
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", -2)
		box.mouse_filter = Control.MOUSE_FILTER_PASS
		_orders_list.add_child(box)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		var part := UIUtil.label(m.display_name, &"ValueLabel")
		part.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		part.clip_text = true
		part.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		part.add_theme_color_override("font_color", CaptainPanel.TIER_COLORS[m.tier])
		row.add_child(part)
		var state := f.order_state(o)
		var st := UIUtil.label(f.order_state_text(o), &"ValueLabel")
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		st.add_theme_color_override("font_color", STATE_COLORS.get(state, HudStyle.TEXT_DIM))
		row.add_child(st)
		var sub := UIUtil.label("   %s, paid %s cr" % [cap.captain_name if cap else "-", UIUtil.amount(int(o.get("paid", 0)))], &"DimLabel")
		sub.clip_text = true
		sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		sub.custom_minimum_size.x = panel_width - 24.0
		box.add_child(sub)
		box.tooltip_text = "Ordered %s ago, %s" % [UIUtil.clock(SimClock.time - float(o["time"])),
				"blocked %s of %s before it lapses" % [UIUtil.clock(float(o.get("blocked", 0.0))), UIUtil.clock(f.backorder_timeout)] if float(o.get("blocked", 0.0)) > 0.0 else "never blocked"]


## Parts in demand: part, tier, in stock, orders, misses.
func _rebuild_demand() -> void:
	for c in _demand_list.get_children():
		_demand_list.remove_child(c)
		c.queue_free()
	var rows := factory.demand_rows(MAX_DEMAND)
	if rows.is_empty():
		_demand_list.columns = 1
		_demand_list.add_child(UIUtil.label("No demand: every part your captains want is in stock.", &"DimLabel"))
		return
	_demand_list.columns = 5
	var widths: PackedFloat32Array = [158.0, 40.0, 52.0, 44.0, 44.0]
	var heads: PackedStringArray = ["Part", "Tier", "In stock", "Orders", "Misses"]
	for i in heads.size():
		var h := UIUtil.label(heads[i], &"DimLabel")
		h.custom_minimum_size.x = widths[i]
		if i >= 2:
			h.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_demand_list.add_child(h)
	for r in rows:
		var m := r["module"] as ShipModule
		var name_l := UIUtil.label(m.display_name.trim_suffix(" " + ShipModule.TIER_NAMES[m.tier]), &"ValueLabel")
		name_l.custom_minimum_size.x = widths[0]
		name_l.clip_text = true
		name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_l.mouse_filter = Control.MOUSE_FILTER_PASS
		name_l.tooltip_text = ModuleTips.tip(m, factory) + ("\nNone in stock, a hired captain could use it" if bool(r["wanted"]) else "")
		_demand_list.add_child(name_l)
		var tier := UIUtil.label(ShipModule.TIER_NAMES[m.tier], &"DimLabel")
		tier.add_theme_color_override("font_color", CaptainPanel.TIER_COLORS[m.tier])
		_demand_list.add_child(tier)
		var stock := int(r["stock"])
		var cells: Array[String] = [str(stock), str(int(r["orders"])), str(ceili(float(r["misses"]))) if float(r["misses"]) >= 0.05 else "-"]
		for i in cells.size():
			var l := UIUtil.label(cells[i], &"NumberLabel")
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			if i == 0 and stock <= 0:
				l.add_theme_color_override("font_color", PipMeter.BAD)
			elif i == 1 and int(r["orders"]) > 0:
				l.add_theme_color_override("font_color", PipMeter.MID)
			_demand_list.add_child(l)


## Newest first: market sales and production lines, merged by time.
func _rebuild_recent() -> void:
	for c in _recent.get_children():
		_recent.remove_child(c)
		c.queue_free()
	var lines: Array[Dictionary] = []
	for h in factory.market.history:
		lines.append({"time": h["time"], "text": "Bought %d %s" % [int(h["units"]), Economy.ORE_NAMES[int(h["ore"])].to_lower()], "credits": int(h["credits"])})
	for l in factory.log_lines:
		lines.append({"time": l["time"], "text": l["text"], "credits": 0})
	lines.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["time"]) > float(y["time"]))
	if lines.is_empty():
		_recent.add_child(UIUtil.label("Nothing yet.", &"DimLabel"))
		return
	for i in mini(lines.size(), MAX_RECENT):
		var e := lines[i]
		var row := HBoxContainer.new()
		_recent.add_child(row)
		var t := UIUtil.label("%s  %s" % [UIUtil.clock(float(e["time"])), e["text"]], &"DimLabel")
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.clip_text = true
		t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(t)
		if int(e["credits"]) > 0:
			var cr := UIUtil.label("+%s cr" % UIUtil.amount(int(e["credits"])), &"DimLabel")
			cr.add_theme_color_override("font_color", PipMeter.GOOD)
			row.add_child(cr)

class_name FactoryPanel
extends PanelContainer
## Bottom-right panel for the selected Factory (BuildingPanel makes it and
## hands Factory selections over). Ore market per type: Factory stock bar,
## demand meter, what it pays now and the trend, the player's asking price
## with the expected sales rate ("auto" while it follows the market), and
## the "keep at least" reserve; auto-sell
## on/off. Production: current item and progress, backorders, warehouse
## counts by slot and tier, tooling upgrades, and recent sales and output.

const DEMAND_COLORS: Array[Color] = [Color(0.6, 0.66, 0.74), Color(1.0, 0.78, 0.25), Color(0.35, 0.9, 0.5)]
const MAX_RECENT := 6

@export var panel_width: float = 400.0

var hud: HUD
var building: Building
var factory: Factory

var _title: Label
var _status: Label
var _job_bar: ProgressBar
var _auto: CheckButton
## Per ore: {stock_bar, stock, demand_meter, demand, price, ask, rate, keep}.
var _ore_rows: Array[Dictionary] = []
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
	var sh := HBoxContainer.new()
	v.add_child(sh)
	_status = UIUtil.label("", &"ValueLabel")
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sh.add_child(_status)
	_job_bar = ProgressBar.new()
	_job_bar.show_percentage = false
	_job_bar.max_value = 1.0
	_job_bar.custom_minimum_size = Vector2(80.0, 6.0)
	_job_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_job_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sh.add_child(_job_bar)

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
		_ore_rows.append(_make_ore_row(v, i))

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
			var cell := UIUtil.label("", &"ValueLabel")
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			cell.custom_minimum_size.x = 56.0
			grid.add_child(cell)
			row.append(cell)
		_ware_cells.append(row)
	_orders = UIUtil.label("", &"DimLabel")
	_orders.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_orders.custom_minimum_size.x = panel_width - 24.0
	v.add_child(_orders)

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
	var price := UIUtil.label("", &"ValueLabel")
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	a.add_child(price)
	a.mouse_filter = Control.MOUSE_FILTER_PASS

	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", 3)
	box.add_child(b)
	b.add_child(UIUtil.spacer(16.0))
	b.add_child(UIUtil.label("Ask", &"DimLabel"))
	var minus := _step_button("-", "Lower the asking price: sells faster. Turns follow market off.")
	minus.pressed.connect(func() -> void:
		if factory:
			factory.market.step_ask(ore, -1))
	b.add_child(minus)
	var ask := UIUtil.label("", &"ValueLabel")
	ask.custom_minimum_size.x = 64.0
	ask.mouse_filter = Control.MOUSE_FILTER_PASS
	ask.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_child(ask)
	var plus := _step_button("+", "Raise the asking price: more per unit, slower sales. Turns follow market off.")
	plus.pressed.connect(func() -> void:
		if factory:
			factory.market.step_ask(ore, 1))
	b.add_child(plus)
	var match_b := _step_button("=", "Follow market: the ask tracks just under what the Factory pays")
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
	b.add_child(UIUtil.label("Keep", &"DimLabel"))
	var kminus := _step_button("-", "Keep less %s back" % Economy.ORE_NAMES[ore].to_lower())
	kminus.pressed.connect(func() -> void:
		if factory:
			var m := factory.market
			m.set_reserve(ore, m.reserve[ore] - m.reserve_step[ore]))
	b.add_child(kminus)
	var keep := UIUtil.label("", &"ValueLabel")
	keep.custom_minimum_size.x = 38.0
	keep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_child(keep)
	var kplus := _step_button("+", "Keep more %s back for building" % Economy.ORE_NAMES[ore].to_lower())
	kplus.pressed.connect(func() -> void:
		if factory:
			var m := factory.market
			m.set_reserve(ore, m.reserve[ore] + m.reserve_step[ore]))
	b.add_child(kplus)
	return {"row": a, "stock_bar": bar, "stock": stock, "meter": meter, "demand": demand, "price": price, "ask": ask, "rate": rate, "keep": keep}


func _step_button(text: String, tip: String) -> Button:
	var b := UIUtil.button(text, &"IconButton")
	b.custom_minimum_size = Vector2(22.0, 22.0)
	b.tooltip_text = tip
	return b


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
	var m := f.market
	for i in _ore_rows.size():
		var r := _ore_rows[i]
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
			rl.text = "none to sell"
		else:
			rl.text = "~%d/min" % roundi(rate)
		rl.add_theme_color_override("font_color", PipMeter.GOOD if rate >= m.max_buy_per_min[i] * 0.5 else (PipMeter.MID if rate > 0.0 else PipMeter.BAD))
		(r["keep"] as Label).text = str(m.reserve[i])
		var tip := "%s: Factory stock %d (target %d), demand %s, pays %.1f cr (%s). Your ask %.1f cr sells ~%.0f/min above %d kept. Export draws %.0f + %d%%/min." % [
				Economy.ORE_NAMES[i], roundi(m.stock[i]), roundi(m.target_stock[i]), m.demand_name(i).to_lower(), m.willing_price(i), trend,
				m.ask[i], rate, m.reserve[i], m.export_base_per_min[i], roundi(m.export_share_per_min[i] * 100.0)]
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
			row[t].text = str(n) if n > 0 else ("0" if can else "-")
			row[t].add_theme_color_override("font_color", CaptainPanel.TIER_COLORS[t + 1] if n > 0 else Color(0.5, 0.55, 0.62))
	_ware_header.text = "WAREHOUSE  %d / %d   (%d made)" % [f.warehouse_total(), f.warehouse_cap, f.total_built]
	if f.backorders.is_empty():
		_orders.text = "No backorders. Spare capacity goes to a spread of parts for the captains you hired."
	else:
		var names: PackedStringArray = []
		for o in f.backorders:
			names.append("%s (%s)" % [(o["module"] as ShipModule).display_name, (o["captain"] as Captain).captain_name])
			if names.size() >= 3:
				break
		_orders.text = "Backorders first: " + ", ".join(names) + (" and %d more" % (f.backorders.size() - 3) if f.backorders.size() > 3 else "")
	# Tooling.
	var rare: PackedStringArray = []
	for id: StringName in f.rare_parts:
		var rm := catalog.find(id)
		if rm:
			rare.append("%s %s" % [rm.display_name, "early" if f.rare_parts[id] == "stocked" else "-%d%%" % roundi(Factory.RARE_DISCOUNT * 100.0)])
	_tool_label.text = "Tooled for %s. Mk I needs iron, Mk II titanium, Mk III crystal.%s" % [
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

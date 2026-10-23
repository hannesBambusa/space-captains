class_name SalvageYardSection
extends VBoxContainer
## Building panel section for the Salvage Yard's business ([SalvageYard]):
## scrap in stock and reprocessing, the reprocessed ore per type with the
## yard's ask against the Factory's bid (your margin) and Buy 10 / Buy all
## buttons, the auto-buy toggle with its credit floor, the yard's funds and
## debts, and the recent deliveries. Refreshes a few times a second.

const REFRESH := 0.25
const BUY_STEP := 10

@export var width: float = 356.0

var yard: SalvageYard

var _scrap: Label
var _scrap_bar: PipMeter
var _funds: Label
var _auto: Button
## Per ore: {stock, price, buy10, buy_all}.
var _rows: Array[Dictionary] = []
var _deliveries: VBoxContainer
var _shown_deliveries := -1
var _timer := 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	add_child(HSeparator.new())
	add_child(UIUtil.label("SALVAGE YARD", &"HeaderLabel"))
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 8)
	add_child(sh)
	_scrap = UIUtil.label("", &"ValueLabel")
	_scrap.custom_minimum_size.x = 210.0
	sh.add_child(_scrap)
	_scrap_bar = PipMeter.new()
	_scrap_bar.style = PipMeter.Style.BAR
	_scrap_bar.max_value = 1.0
	_scrap_bar.color = Color(1.0, 0.6, 0.24)
	_scrap_bar.custom_minimum_size = Vector2(110.0, 6.0)
	_scrap_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_scrap_bar.tooltip_text = "Scrap waiting to be reprocessed, against what the yard handles in a minute"
	sh.add_child(_scrap_bar)
	_funds = _wrapped(&"DimLabel")
	add_child(_funds)

	var oh := HBoxContainer.new()
	add_child(oh)
	oh.add_child(UIUtil.label("ORE FOR SALE", &"HeaderLabel"))
	oh.add_child(UIUtil.spacer())
	var cols := UIUtil.label("cr per unit: yard / Factory, margin", &"DimLabel")
	cols.add_theme_font_size_override("font_size", 12)
	oh.add_child(cols)
	for i in SalvageYard.TYPES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		add_child(row)
		var name_l := UIUtil.label(Economy.ORE_NAMES[i], &"ValueLabel")
		name_l.add_theme_color_override("font_color", Economy.ORE_COLORS[i])
		name_l.custom_minimum_size.x = 64.0
		row.add_child(name_l)
		var stock := UIUtil.label("", &"ValueLabel")
		stock.custom_minimum_size.x = 30.0
		stock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(stock)
		var price := UIUtil.label("", &"DimLabel")
		price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		price.clip_text = true
		price.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(price)
		var buy10 := UIUtil.button("Buy %d" % BUY_STEP)
		buy10.custom_minimum_size = Vector2(54.0, 22.0)
		buy10.pressed.connect(func() -> void: _buy(i, BUY_STEP))
		row.add_child(buy10)
		var buy_all := UIUtil.button("All")
		buy_all.custom_minimum_size = Vector2(44.0, 22.0)
		buy_all.pressed.connect(func() -> void: _buy(i, 1 << 30))
		row.add_child(buy_all)
		_rows.append({"stock": stock, "price": price, "buy10": buy10, "buy_all": buy_all})
	_auto = UIUtil.button("", &"AccentButton")
	_auto.toggle_mode = true
	_auto.toggled.connect(func(on: bool) -> void:
		if is_instance_valid(yard):
			yard.set_auto_buy(on)
		_refresh())
	add_child(_auto)

	add_child(UIUtil.label("RECENT DELIVERIES", &"HeaderLabel"))
	_deliveries = VBoxContainer.new()
	_deliveries.add_theme_constant_override("separation", 1)
	add_child(_deliveries)


func show_yard(y: SalvageYard) -> void:
	yard = y
	visible = y != null
	_shown_deliveries = -1
	_refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH
		_refresh()


func _refresh() -> void:
	if not is_instance_valid(yard):
		return
	var y := yard
	_scrap.text = "Scrap %d   %s" % [ceili(y.scrap), "reprocessing %.1f/s" % y.reprocess_rate if y.scrap > 0.0 else "idle"]
	_scrap_bar.value = clampf(y.scrap / maxf(y.reprocess_rate * 60.0, 1.0), 0.0, 1.0)
	var debt := y.owed_total()
	_funds.text = "Yard funds %s cr, pays %d cr per load%s. Sold you %s cr of ore so far." % [UIUtil.amount(y.funds), SalvageContract.FAIR_REWARD,
			", owes salvagers %s cr" % UIUtil.amount(debt) if debt > 0 else "", UIUtil.amount(y.total_sales)]
	for i in _rows.size():
		var r := _rows[i]
		var bid := y.factory_bid(i)
		var ask := y.ask(i)
		(r["stock"] as Label).text = str(y.stock[i])
		var price := r["price"] as Label
		price.text = "%.1f / %.1f  +%.1f" % [ask, bid, bid - ask]
		price.mouse_filter = Control.MOUSE_FILTER_PASS
		price.tooltip_text = "The yard asks %d%% of what the Factory pays now. Bought ore goes into your stock; the Factory market sells it on." % roundi(y.discount * 100.0)
		var can := y.affordable(i) > 0
		for key in ["buy10", "buy_all"]:
			var b := r[key] as Button
			b.disabled = not can
			b.tooltip_text = "Nothing in stock" if y.stock[i] <= 0 else ("Not enough credits" if not can else
					"%d %s for %s cr" % [mini(y.stock[i], BUY_STEP) if key == "buy10" else y.affordable(i), Economy.ORE_NAMES[i].to_lower(),
					UIUtil.amount(y.price_of(i, mini(y.stock[i], BUY_STEP) if key == "buy10" else y.affordable(i)))])
	_auto.set_pressed_no_signal(y.auto_buy)
	_auto.text = "Auto-buy on, keeps %s cr (click: off)" % UIUtil.amount(y.credit_floor) if y.auto_buy else "Auto-buy off (click: on)"
	_auto.tooltip_text = "Buys all reprocessed ore as it comes in, as long as you keep at least %s credits." % UIUtil.amount(y.credit_floor)
	if _shown_deliveries != y.delivery_count:
		_shown_deliveries = y.delivery_count
		_rebuild_deliveries()


func _rebuild_deliveries() -> void:
	for c in _deliveries.get_children():
		_deliveries.remove_child(c)
		c.queue_free()
	if yard.deliveries.is_empty():
		_deliveries.add_child(_wrapped(&"DimLabel", "No deliveries yet. Salvagers fly out to wrecks on their own."))
		return
	var n := 0
	for i in range(yard.deliveries.size() - 1, -1, -1):
		var d := yard.deliveries[i]
		var row := HBoxContainer.new()
		_deliveries.add_child(row)
		var who := UIUtil.label("%s  %s" % [UIUtil.clock(float(d["time"])), d["captain"]], &"DimLabel")
		who.custom_minimum_size.x = 150.0
		who.clip_text = true
		row.add_child(who)
		var what := UIUtil.label("%d scrap%s" % [int(d["scrap"]), ", rare %s" % d["rare"] if not String(d["rare"]).is_empty() else ""], &"DimLabel")
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		what.clip_text = true
		what.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(what)
		var paid := UIUtil.label("%d cr%s" % [int(d["paid"]), " (+%d owed)" % int(d["owed"]) if int(d["owed"]) > 0 else ""], &"DimLabel")
		paid.add_theme_color_override("font_color", PipMeter.GOOD if int(d["owed"]) <= 0 else Color(1.0, 0.75, 0.3))
		row.add_child(paid)
		n += 1
		if n >= 4:
			break


func _buy(ore: int, units: int) -> void:
	if is_instance_valid(yard):
		yard.buy(ore, units)
	_refresh()


func _wrapped(variation: StringName, text: String = "") -> Label:
	var l := UIUtil.label(text, variation)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	return l

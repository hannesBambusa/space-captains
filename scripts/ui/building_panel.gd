class_name BuildingPanel
extends PanelContainer
## Bottom-right panel for the selected building: name, status, description
## and, for buildings with hire options, the hire button and hired captains.
## Stage 3: captains without a ship (ejected, waiting here or still in their
## pod) with a "Buy ship" button (the player pays), and for the Outfitter the
## Factory warehouse stock it sells from, what the Factory is making,
## open buy orders and recent sales. The Factory has its own panel (FactoryPanel).
## Defense Turrets and the Shield Generator get a DefenseSection, the
## Salvage Yard a SalvageYardSection (its scrap, ore for sale, auto-buy).

const PERSONALITY_COLORS: Array[Color] = [
	Color(1.0, 0.55, 0.35), Color(0.5, 0.8, 1.0), Color(1.0, 0.82, 0.3), Color(0.7, 0.7, 0.78),
]

@export var panel_width: float = 380.0

var hud: HUD
var building: Building

var _title: Label
var _status: Label
var _progress: ProgressBar
var _desc: Label
var _hire_section: VBoxContainer
var _hire_header: Label
var _crew: VBoxContainer
var _hire_button: Button
var _hire_reason: Label
var _crew_timer := 0.0
## Per crew entry: {ship, row, reason}.
var _crew_rows: Array[Dictionary] = []
## Per waiting captain: {captain, status, button}.
var _wait_rows: Array[Dictionary] = []
var _outfit_section: VBoxContainer
var _outfit_tier: Label
var _outfit_stock: Label
var _outfit_making: Label
var _rare: Label
var _sales: VBoxContainer
var _outfitter: Outfitter
var _factory: Factory
var _defense: DefenseSection
var _salvage: SalvageYardSection
## Sibling panel for Factory selections (made in [method setup]).
var factory_panel: FactoryPanel


func _ready() -> void:
	custom_minimum_size.x = panel_width
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
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
	_title = UIUtil.label("", &"TitleLabel")
	v.add_child(_title)
	var sh := HBoxContainer.new()
	v.add_child(sh)
	_status = UIUtil.label("", &"ValueLabel")
	sh.add_child(_status)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.max_value = 1.0
	_progress.custom_minimum_size = Vector2(120.0, 6.0)
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sh.add_child(_progress)
	_desc = UIUtil.label("", &"DimLabel")
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size.x = panel_width - 24.0
	v.add_child(_desc)

	_hire_section = VBoxContainer.new()
	_hire_section.add_theme_constant_override("separation", 4)
	v.add_child(_hire_section)
	_hire_section.add_child(HSeparator.new())
	_hire_header = UIUtil.label("", &"HeaderLabel")
	_hire_section.add_child(_hire_header)
	_crew = VBoxContainer.new()
	_crew.add_theme_constant_override("separation", 1)
	_hire_section.add_child(_crew)
	_hire_button = UIUtil.button("", &"AccentButton")
	_hire_button.pressed.connect(_on_hire)
	_hire_section.add_child(_hire_button)
	_hire_reason = UIUtil.label("", &"WarnLabel")
	_hire_section.add_child(_hire_reason)

	_outfit_section = VBoxContainer.new()
	_outfit_section.add_theme_constant_override("separation", 4)
	v.add_child(_outfit_section)
	_outfit_section.add_child(HSeparator.new())
	_outfit_section.add_child(UIUtil.label("STOCK FROM THE FACTORY", &"HeaderLabel"))
	_outfit_stock = UIUtil.label("", &"ValueLabel")
	_outfit_section.add_child(_outfit_stock)
	_outfit_making = UIUtil.label("", &"DimLabel")
	_outfit_making.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_outfit_making.custom_minimum_size.x = panel_width - 24.0
	_outfit_section.add_child(_outfit_making)
	_outfit_tier = UIUtil.label("", &"DimLabel")
	_outfit_tier.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_outfit_tier.custom_minimum_size.x = panel_width - 24.0
	_outfit_section.add_child(_outfit_tier)
	_rare = UIUtil.label("", &"DimLabel")
	_rare.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rare.custom_minimum_size.x = panel_width - 24.0
	_outfit_section.add_child(_rare)
	_outfit_section.add_child(UIUtil.label("RECENT SALES", &"HeaderLabel"))
	_sales = VBoxContainer.new()
	_sales.add_theme_constant_override("separation", 1)
	_outfit_section.add_child(_sales)

	_defense = DefenseSection.new()
	_defense.width = panel_width - 24.0
	_defense.visible = false
	v.add_child(_defense)

	_salvage = SalvageYardSection.new()
	_salvage.width = panel_width - 24.0
	_salvage.visible = false
	v.add_child(_salvage)


func setup(owner_hud: HUD) -> void:
	hud = owner_hud
	factory_panel = FactoryPanel.new()
	factory_panel.name = "FactoryPanel"
	factory_panel.layout_mode = layout_mode
	factory_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	factory_panel.offset_left = offset_left - (factory_panel.panel_width - panel_width)
	factory_panel.offset_top = offset_top
	factory_panel.offset_right = offset_right
	factory_panel.offset_bottom = offset_bottom
	factory_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	factory_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	get_parent().add_child.call_deferred(factory_panel)
	_setup_factory_panel.call_deferred()
	if hud.selection:
		hud.selection.selection_changed.connect(func(t: Node3D) -> void: show_building(t as Building))
	Economy.changed.connect(func(_c: int, _m: int) -> void: _refresh())


func _setup_factory_panel() -> void:
	UIUtil.no_focus(factory_panel)
	factory_panel.setup(hud)


func show_building(b: Building) -> void:
	if b and b.get_service() is Factory:
		b = null
	if building and is_instance_valid(building):
		if building.state_changed.is_connected(_on_building_event):
			building.state_changed.disconnect(_on_building_event)
			building.hires_changed.disconnect(_on_building_event)
	if _outfitter and is_instance_valid(_outfitter) and _outfitter.changed.is_connected(_refresh_outfitter):
		_outfitter.changed.disconnect(_refresh_outfitter)
	if _factory and is_instance_valid(_factory) and _factory.changed.is_connected(_refresh_outfitter):
		_factory.changed.disconnect(_refresh_outfitter)
	_factory = null
	building = b
	visible = b != null
	_outfitter = null
	_defense.show_structure(b.get_service() as DefenseStructure if b else null)
	_salvage.show_yard(b.get_service() as SalvageYard if b else null)
	if b == null:
		return
	b.state_changed.connect(_on_building_event)
	b.hires_changed.connect(_on_building_event)
	_outfitter = b.get_service() as Outfitter
	if _outfitter:
		_outfitter.changed.connect(_refresh_outfitter)
		_factory = _outfitter.factory()
		if _factory:
			_factory.changed.connect(_refresh_outfitter)
	_title.text = b.display_name
	_desc.text = b.def.description
	_refresh()
	_rebuild_crew()


func get_hire_button() -> Button:
	return _hire_button


func _process(delta: float) -> void:
	if not visible or not is_instance_valid(building):
		return
	if not building.is_active():
		_status.text = building.get_status_text()
		_progress.value = building.get_progress()
	_crew_timer -= delta
	if _crew_timer <= 0.0:
		_crew_timer = 0.25
		_refresh_crew_status()
		if building.is_active() and building.get_service() is DefenseStructure:
			_status.text = building.get_status_text()


func _on_building_event(_b: Building) -> void:
	_refresh()
	_rebuild_crew()


func _refresh() -> void:
	if not is_instance_valid(building):
		return
	var b := building
	_status.text = b.get_status_text()
	_status.add_theme_color_override("font_color", PipMeter.GOOD if b.is_active() else Color(1.0, 0.75, 0.45))
	_progress.visible = not b.is_active()
	_progress.value = b.get_progress()
	_refresh_outfitter()
	_hire_section.visible = b.def.can_hire()
	if not b.def.can_hire():
		return
	_hire_header.text = "%s  %d / %d" % [UIUtil.plural(b.def.hire_role).to_upper(), b.captains.size(), b.def.max_hires]
	_hire_button.text = "Hire %s - %d credits" % [b.def.hire_role.to_lower(), b.def.hire_cost_credits]
	var why := b.hire_block_reason()
	_hire_button.disabled = not why.is_empty()
	_hire_button.tooltip_text = why if not why.is_empty() else "Hire a %s captain. Their ship docks here." % b.def.hire_role.to_lower()
	_hire_reason.text = why
	_hire_reason.visible = not why.is_empty()


func _refresh_outfitter() -> void:
	_outfit_section.visible = _outfitter != null
	if _outfitter == null:
		return
	var o := _outfitter
	var f := _factory if is_instance_valid(_factory) else null
	if f == null:
		_outfit_stock.text = "No Factory: nothing to sell"
		_outfit_making.text = ""
	else:
		_outfit_stock.text = "%d parts in stock  (%s)" % [f.warehouse_total(), stock_summary(f)]
		var orders := f.backorders.size()
		_outfit_making.text = "Factory: %s.%s" % [f.status_text(), "  %d open order%s." % [orders, "" if orders == 1 else "s"] if orders > 0 else ""]
	_outfit_tier.text = "Factory tooled to %s. Captains also need the rank: Mk II from Veteran, Mk III from Ace. You get %d%% of each sale (%s cr so far)." % [
			ShipModule.TIER_NAMES[o.supplied_tier()] if f else "none", roundi(o.sale_share * 100.0), UIUtil.amount(o.total_income)]
	var rare: PackedStringArray = []
	var catalog := ModuleCatalog.shared()
	if f:
		for id: StringName in f.rare_parts:
			var m := catalog.find(id)
			if m:
				rare.append("%s (%s)" % [m.display_name, "made early" if f.rare_parts[id] == "stocked" else "%d%% off" % roundi(Factory.RARE_DISCOUNT * 100.0)])
	_rare.text = "Rare parts: " + ", ".join(rare) if not rare.is_empty() else "Rare parts from salvage show up here."
	for c in _sales.get_children():
		_sales.remove_child(c)
		c.queue_free()
	if o.sales.is_empty():
		_sales.add_child(UIUtil.label("No sales yet. Captains shop when docked with money to spare.", &"DimLabel"))
		(_sales.get_child(0) as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		(_sales.get_child(0) as Label).custom_minimum_size.x = panel_width - 24.0
		return
	var n := 0
	for i in range(o.sales.size() - 1, -1, -1):
		var sale := o.sales[i]
		var row := HBoxContainer.new()
		_sales.add_child(row)
		var who := UIUtil.label("%s  %s" % [UIUtil.clock(float(sale["time"])), sale["captain"]], &"DimLabel")
		who.custom_minimum_size.x = 140.0
		who.clip_text = true
		row.add_child(who)
		var what := UIUtil.label(String(sale["module"]), &"DimLabel")
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		what.clip_text = true
		what.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		what.add_theme_color_override("font_color", CaptainPanel.TIER_COLORS[int(sale["tier"])])
		row.add_child(what)
		var price := UIUtil.label("+%d cr" % int(sale["income"]), &"DimLabel")
		price.add_theme_color_override("font_color", PipMeter.GOOD)
		price.tooltip_text = "Price %d cr" % int(sale["price"])
		row.add_child(price)
		n += 1
		if n >= 6:
			break


## "Mk I 7, Mk II 2" from the Factory warehouse.
static func stock_summary(f: Factory) -> String:
	var per := PackedInt32Array([0, 0, 0, 0])
	var catalog := ModuleCatalog.shared()
	for id: StringName in f.warehouse:
		var m := catalog.find(id)
		if m:
			per[m.tier] += int(f.warehouse[id])
	var parts: PackedStringArray = []
	for t in range(1, 4):
		if per[t] > 0:
			parts.append("%s %d" % [ShipModule.TIER_NAMES[t], per[t]])
	return ", ".join(parts) if not parts.is_empty() else "empty"


func _rebuild_crew() -> void:
	_crew_rows.clear()
	_wait_rows.clear()
	for c in _crew.get_children():
		_crew.remove_child(c)
		c.queue_free()
	if not is_instance_valid(building):
		return
	if building.captains.is_empty():
		var none := UIUtil.label("No %s hired yet." % UIUtil.plural(building.def.hire_role).to_lower(), &"DimLabel")
		_crew.add_child(none)
		return
	for s in building.ships:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		_crew.add_child(box)
		var row := OverviewRow.new(s, s.captain.captain_name, "")
		row.toggle_mode = false
		row.title_label.size_flags_stretch_ratio = 0.8
		row.tooltip_text = "%s: %s" % [s.captain.get_personality_name(), s.captain.get_personality_hint()]
		var tag := UIUtil.label(s.captain.get_personality_name(), &"DimLabel")
		tag.add_theme_color_override("font_color", PERSONALITY_COLORS[s.captain.personality])
		tag.custom_minimum_size.x = 58.0
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_right(tag)
		row.pressed.connect(func() -> void:
			if is_instance_valid(s):
				if hud.camera:
					hud.camera.focus_on(s)
				if hud.selection:
					hud.selection.select(s))
		row.hovered.connect(func(r: OverviewRow, on: bool) -> void:
			hud.marker.hover_target = r.target if on else null)
		box.add_child(row)
		var reason := UIUtil.label("", &"WarnLabel")
		reason.add_theme_font_size_override("font_size", 12)
		reason.clip_text = true
		reason.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		reason.custom_minimum_size.x = panel_width - 60.0
		reason.visible = false
		var indent := MarginContainer.new()
		indent.add_theme_constant_override("margin_left", 16)
		indent.mouse_filter = Control.MOUSE_FILTER_IGNORE
		indent.add_child(reason)
		box.add_child(indent)
		_crew_rows.append({"ship": s, "row": row, "reason": reason})
	for c in building.captains:
		if is_instance_valid(c.ship) and building.ships.has(c.ship):
			continue
		var wr := HBoxContainer.new()
		wr.add_theme_constant_override("separation", 8)
		_crew.add_child(wr)
		wr.add_child(UIUtil.spacer(8.0))
		var nl := UIUtil.label(c.captain_name)
		nl.custom_minimum_size.x = 120.0
		nl.add_theme_color_override("font_color", PERSONALITY_COLORS[c.personality].lerp(Color.WHITE, 0.4))
		wr.add_child(nl)
		var st := UIUtil.label("", &"DimLabel")
		st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		st.clip_text = true
		st.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		wr.add_child(st)
		var buy := UIUtil.button("Buy ship %s cr" % UIUtil.amount(building.def.ship_cost))
		buy.custom_minimum_size = Vector2(120.0, 22.0)
		buy.pressed.connect(func() -> void:
			if is_instance_valid(building):
				building.buy_replacement(c, true))
		wr.add_child(buy)
		_wait_rows.append({"captain": c, "status": st, "button": buy})
	_refresh_crew_status()


## Live status per miner and the reason for its last refusal.
func _refresh_crew_status() -> void:
	for e in _crew_rows:
		var s := e["ship"] as Ship
		if not is_instance_valid(s):
			continue
		(e["row"] as OverviewRow).set_subtitle(s.get_status_text())
		var reason := e["reason"] as Label
		var why := ""
		if s.brain and not s.brain.last_refusal.is_empty():
			why = "Refused %s: %s" % [s.brain.last_refusal_target, s.brain.last_refusal.to_lower()]
		if reason.text != why:
			reason.text = why
		reason.visible = not why.is_empty()
	for e in _wait_rows:
		var c := e["captain"] as Captain
		var st := e["status"] as Label
		var buy := e["button"] as Button
		var waiting := building.waiting.has(c)
		st.text = "waiting, wallet %s cr" % UIUtil.amount(c.wallet) if waiting else "in escape pod"
		buy.visible = waiting
		var why := building.replacement_block_reason(c, true) if waiting else ""
		buy.disabled = not why.is_empty()
		buy.tooltip_text = why if not why.is_empty() else "Pay for a new ship from your credits. Otherwise they buy one once their wallet holds %s cr." % UIUtil.amount(building.def.ship_cost)


func _on_hire() -> void:
	if is_instance_valid(building):
		building.hire()

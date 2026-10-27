class_name StationPanel
extends PanelContainer
## Bottom-right panel for the selected station (a click on its hub,
## SelectionController picks the [HomeStation] node; home's shows without
## the supply rows): name and system, hull, addon bays, upkeep (per minute,
## paid so far, owed, the free start), water (use, used so far, how long
## the stock lasts, dry), the hauling fee so far, and the buildings there
## (a click selects one). Refreshed on a timer.
## A selected [MobileStation] (F6) shows here too: its state, hull,
## destination, the escort contract (escorts joined, the warning when
## nobody takes it) with the escort pay, "Set destination" (opens the
## cluster map: "Set destination here" there) and "Cancel destination".

@export var panel_width: float = 380.0

var hud: HUD
var station: HomeStation

var _head: Label
var _title: Label
var _where: Label
var _hull: Label
var _bays: Label
var _upkeep: Label
var _water: Label
var _hauling: Label
var _note: Label
var _list: VBoxContainer
var _list_key := ""
var _refresh_left := 0.0
## F6: the mobile station shown instead of a station, and its part.
var mobile: MobileStation
var _grid: GridContainer
var _list_head: Control
var _mobile_box: VBoxContainer
var _m_dest: Label
var _m_escort: Label
var _m_warn: Label
var _m_pay: Label
var _m_set: Button
var _m_cancel: Button


func _ready() -> void:
	custom_minimum_size.x = panel_width
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	_head = UIUtil.label("FORWARD STATION", &"HeaderLabel")
	top.add_child(_head)
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
	_where = UIUtil.label("", &"DimLabel")
	v.add_child(_where)
	var grid := GridContainer.new()
	_grid = grid
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	_hull = _grid_row(grid, "Hull")
	_bays = _grid_row(grid, "Addon bays")
	_upkeep = _grid_row(grid, "Upkeep")
	_water = _grid_row(grid, "Water")
	_hauling = _grid_row(grid, "Hauling fee")
	_note = UIUtil.label("", &"DimLabel")
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size.x = panel_width - 24.0
	v.add_child(_note)
	_build_mobile(v)
	var sep := HSeparator.new()
	v.add_child(sep)
	var head := UIUtil.label("BUILDINGS", &"HeaderLabel")
	v.add_child(head)
	_list_head = head
	head.set_meta(&"sep", sep)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 1)
	v.add_child(_list)


func _grid_row(grid: GridContainer, title: String) -> Label:
	grid.add_child(UIUtil.label(title, &"DimLabel"))
	var l := UIUtil.label("", &"ValueLabel")
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = panel_width - 130.0
	grid.add_child(l)
	return l


func _build_mobile(v: VBoxContainer) -> void:
	_mobile_box = VBoxContainer.new()
	_mobile_box.add_theme_constant_override("separation", 5)
	_mobile_box.visible = false
	v.add_child(_mobile_box)
	_m_dest = _wrap_label(&"ValueLabel")
	_mobile_box.add_child(HSeparator.new())
	_mobile_box.add_child(UIUtil.label("ESCORT CONTRACT", &"HeaderLabel"))
	_m_escort = _wrap_label(&"ValueLabel")
	_m_warn = _wrap_label(&"DimLabel")
	_m_warn.add_theme_color_override("font_color", HudStyle.BAD)
	var row := HBoxContainer.new()
	_mobile_box.add_child(row)
	row.add_child(UIUtil.label("Escort pay", &"DimLabel"))
	row.add_child(UIUtil.spacer())
	var minus := UIUtil.button("-", &"IconButton")
	minus.custom_minimum_size = Vector2(28.0, 24.0)
	minus.tooltip_text = "Lower the pay per escort (25 cr)"
	minus.pressed.connect(func() -> void:
		if is_instance_valid(mobile):
			mobile.set_escort_pay(maxi(mobile.escort_pay - 25, 25))
			_refresh())
	row.add_child(minus)
	_m_pay = UIUtil.label("", &"NumberLabel")
	_m_pay.custom_minimum_size.x = 84.0
	_m_pay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_m_pay)
	var plus := UIUtil.button("+", &"IconButton")
	plus.custom_minimum_size = Vector2(28.0, 24.0)
	plus.tooltip_text = "Raise the pay per escort (25 cr): paid to each escort when the station is founded"
	plus.pressed.connect(func() -> void:
		if is_instance_valid(mobile):
			mobile.set_escort_pay(mobile.escort_pay + 25)
			_refresh())
	row.add_child(plus)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	_mobile_box.add_child(buttons)
	_m_set = UIUtil.button("Set destination", &"AccentButton")
	_m_set.tooltip_text = "Open the cluster map and pick a system (\"Set destination here\"), then click a planet there"
	_m_set.pressed.connect(func() -> void:
		if hud and hud.cluster_map:
			hud.cluster_map.open_map())
	buttons.add_child(_m_set)
	_m_cancel = UIUtil.button("Cancel destination", &"")
	_m_cancel.tooltip_text = "Stay parked; the escort contract is cancelled (nothing is reserved)"
	_m_cancel.pressed.connect(func() -> void:
		if is_instance_valid(mobile):
			mobile.cancel_destination()
			_refresh())
	buttons.add_child(_m_cancel)


func _wrap_label(variation: StringName) -> Label:
	var l := UIUtil.label("", variation)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = panel_width - 24.0
	_mobile_box.add_child(l)
	return l


func setup(owner_hud: HUD) -> void:
	hud = owner_hud
	if hud.selection:
		hud.selection.selection_changed.connect(func(t: Node3D) -> void:
			if t is MobileStation:
				show_mobile(t as MobileStation)
			else:
				show_station(t as HomeStation))


func show_station(s: HomeStation) -> void:
	mobile = null
	station = s
	visible = station != null
	_list_key = ""
	_set_mobile_look(false)
	if station:
		_refresh()


## The selected mobile station (F6).
func show_mobile(ms: MobileStation) -> void:
	station = null
	mobile = ms
	visible = ms != null
	_set_mobile_look(ms != null)
	if ms:
		_refresh()


## The selected mobile station, else the first one parked or waiting; null when none.
static func pick_mobile(tree: SceneTree, selected: Node) -> MobileStation:
	if selected is MobileStation and not (selected as MobileStation).dead:
		return selected as MobileStation
	for n in tree.get_nodes_in_group(MobileStation.MOBILE_GROUP):
		var ms := n as MobileStation
		if not ms.dead and (ms.state == MobileStation.State.PARKED or ms.state == MobileStation.State.WAITING):
			return ms
	return null


func _set_mobile_look(on: bool) -> void:
	if on:
		_head.text = "FORWARD STATION (MOBILE)"
	_mobile_box.visible = on
	for row: Label in [_bays, _upkeep, _water, _hauling]:
		row.visible = not on
		(_grid.get_child(row.get_index() - 1) as Control).visible = not on
	_note.visible = not on
	_list_head.visible = not on
	(_list_head.get_meta(&"sep") as Control).visible = not on
	_list.visible = not on


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = 0.5
		_refresh()


func _refresh() -> void:
	if mobile != null:
		_refresh_mobile()
		return
	if not is_instance_valid(station) or not station.is_inside_tree():
		visible = false
		return
	var supply := StationSupply.of(station)
	var mgr := BuildingManager.of(station)
	if mgr == null:
		return
	var host := station.get_parent().get_parent() as PlanetBody if station.get_parent() else null
	var hull := mgr.station_hull
	if hull and hull.durability:
		var status := hull.get_status_text()
		_hull.text = "%s / %s%s" % [Fmt.amount(roundi(hull.durability.hull)), Fmt.amount(roundi(hull.durability.max_hull)),
				"  (%s)" % status.to_lower() if not status.is_empty() else ""]
	else:
		_hull.text = "-"
	_bays.text = "%d of %d used" % [mgr.used_bays(), mgr.bay_count]
	# Home: the same panel without upkeep, water and the hauling fee.
	_head.text = "FORWARD STATION" if supply else "HOME STATION"
	for l: Label in [_upkeep, _water, _hauling]:
		l.visible = supply != null
		(l.get_parent().get_child(l.get_index() - 1) as Control).visible = supply != null
	if supply == null:
		var sys := SolarSystem.of(station)
		_title.text = station.station_name
		_where.text = "%s system%s, home" % [sys.system_def.system_name if sys and sys.system_def else "Home", ", %s orbit" % host.def.name if host and host.def else ""]
		_note.text = "Your home station: builds every structure in the build bar. Its captains work this system's contracts."
		_note.add_theme_color_override("font_color", HudStyle.TEXT_DIM)
		_fill_list(mgr)
		return
	_title.text = supply.station_name()
	_where.text = "%s system%s, founded %s" % [supply.system_name(), ", %s orbit" % host.def.name if host and host.def else "",
			Fmt.clock(supply.founded_at())]
	var up := "%d cr/min, paid %s cr" % [roundi(supply.upkeep_per_minute), Fmt.amount(supply.upkeep_paid)]
	if supply.owed > 0:
		up += ", %s cr owed" % Fmt.amount(supply.owed)
	elif supply.upkeep_free():
		up += ", free for %s" % Fmt.clock(supply.founded_at() + supply.free_upkeep_time - SimClock.time)
	_upkeep.text = up
	var left := StationSupply.water_minutes_left(get_tree())
	_water.text = "%s/min, used %s; stock %s, %s" % [Fmt.amount(roundi(supply.water_per_minute)), Fmt.amount(supply.water_used),
			Fmt.amount(Economy.ore[Economy.Ore.WATER]), "DRY" if supply.dry else ("lasts %d min" % floori(left) if left != INF else "ok")]
	_water.add_theme_color_override("font_color", HudStyle.BAD if supply.dry or StationSupply.water_low(get_tree()) else HudStyle.TEXT_BRIGHT)
	var fee := Economy.cost_text(supply.hauled_fee)
	_hauling.text = "%d%% of the ore landed: %s" % [roundi(supply.hauling_fee * 100.0),
			"%s (about %s cr)" % [fee, Fmt.amount(supply.hauled_fee_value)] if not fee.is_empty() else "none yet"]
	var why := supply.hire_problem()
	_note.text = why if not why.is_empty() else "Builds here: outposts, defences and the Outfitter (sells from home's Factory). Its captains work this system's contracts."
	_note.add_theme_color_override("font_color", HudStyle.BAD if not why.is_empty() else HudStyle.TEXT_DIM)
	_fill_list(mgr)


func _fill_list(mgr: BuildingManager) -> void:
	var parts: PackedStringArray = []
	for b in mgr.buildings:
		if is_instance_valid(b):
			parts.append("%d:%s" % [b.get_instance_id(), b.get_status_text()])
	var key := ",".join(parts)
	if key == _list_key:
		return
	_list_key = key
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	if parts.is_empty():
		_list.add_child(UIUtil.label("None yet: pick one in the build bar.", &"DimLabel"))
		return
	for b in mgr.buildings:
		if not is_instance_valid(b):
			continue
		var row := UIUtil.button("", &"RowButton")
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var st := b.get_status_text()
		row.text = "%s  ·  %s" % [b.display_name, st.to_lower() if not st.is_empty() else "active"]
		row.tooltip_text = "Select %s" % b.display_name
		row.pressed.connect(func() -> void:
			if hud and hud.selection and is_instance_valid(b):
				hud.selection.select(b))
		_list.add_child(row)


func _refresh_mobile() -> void:
	if not is_instance_valid(mobile) or mobile.dead or not mobile.is_inside_tree():
		visible = false
		mobile = null
		return
	_title.text = mobile.get_display_name()
	_where.text = mobile.get_status_text()
	var d := mobile.durability
	_hull.text = "%s / %s" % [Fmt.amount(roundi(d.hull)), Fmt.amount(roundi(d.max_hull))] if d else "-"
	var st := mobile.state
	if mobile.dest.is_empty():
		_m_dest.text = "No destination. Pick a planet in a charted system of danger %d or less without a station; it leaves with its escorts and orbits that planet." % ForwardStations.MAX_DANGER
	else:
		var def := Sector.system_def(mobile.dest)
		_m_dest.text = "Destination: %s in %s (danger %d). %s" % [String(mobile.site.get("planet", "?")), def.system_name if def else "?", mobile.route_danger(),
				"Leaves once an escort has joined." if st == MobileStation.State.WAITING else ""]
	var c := mobile.contract
	if c and not c.is_finished():
		var n := c.escorts_of(mobile).size()
		_m_escort.text = "%s: %d of %d escort%s joined, %s cr each when the station is founded" % [c.get_title(), n, c.max_escorts, "" if c.max_escorts == 1 else "s", Fmt.amount(c.reward)]
		var w := c.get_warning_text()
		_m_warn.text = w + (". " + c.get_warning_hint() if not w.is_empty() else "")
	else:
		_m_escort.text = "None yet: setting a destination posts it."
		_m_warn.text = ""
	_m_warn.visible = not _m_warn.text.is_empty()
	_m_pay.text = "%s cr" % Fmt.amount(mobile.escort_pay)
	var can_set := st == MobileStation.State.PARKED or st == MobileStation.State.WAITING
	_m_set.disabled = not can_set
	_m_set.text = "Change destination" if st == MobileStation.State.WAITING else "Set destination"
	_m_cancel.visible = st == MobileStation.State.WAITING

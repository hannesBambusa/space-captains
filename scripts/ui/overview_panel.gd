class_name OverviewPanel
extends VBoxContainer
## Left panel, tabbed (the tab row stays when collapsed with its button or
## Tab). The pilots have their own list on the right ([PilotColumn]).
## - ALL (default): contracts, threats and the system in one scrolling view.
## - SYSTEM: star, planets (moons nested), asteroid clusters (live: new
##   ones appear, mined-out ones go), jump gates,
##   stations and structures (player buildings with live status), scrap fields.
## - CONTRACTS: posted contracts (with cancel) and what is reserved for
##   bounties and zone budgets.
## - THREATS: the bases that have arrived, grouped by faction, with their
##   status and the ships out, raiders included; a base being announced as
##   "arriving in m:ss"; a vague "Next: unknown signals, ~6 min" outlook line
##   from the ThreatDirector.
## Each tab shows a live count. Click a list row = camera flies to it and
## follows; the row stays highlighted while the camera follows that target
## or while it is selected.

enum Tab { ALL, SYSTEM, CONTRACTS, THREATS }

const TAB_NAMES: PackedStringArray = ["ALL", "SYSTEM", "CONTRACTS", "THREATS"]
const TAB_ICONS: Array[StringName] = [&"station", &"tab_system", &"tab_contracts", &"tab_threats"]
const PLANET_TYPES: PackedStringArray = ["Rocky world", "Ocean world", "Desert world", "Ice world", "Lava world", "Gas giant"]
const MOON_TYPES: PackedStringArray = ["Rocky moon", "Ocean moon", "Desert moon", "Ice moon", "Lava moon", "Gas moon"]
const ORE_NAMES: PackedStringArray = ["Rock", "Iron", "Titanium", "Crystal"]

@export var panel_width: float = 400.0
## Space kept free below the panel, pixels.
@export var bottom_margin: float = 172.0

var hud: HUD
var is_open := true
var rows: Array[OverviewRow] = []
var tab: Tab = Tab.ALL

var _toggle_button: Button
var _frame: PanelContainer
var _tab_buttons: Array[Button] = []
var _tab_counts: Array[Label] = []
var _body: VBoxContainer
## Fades the row cut by the scroll's bottom edge while more rows follow.
var _fade: TextureRect
var _scroll: ScrollContainer
var _list: VBoxContainer
var _structures: VBoxContainer
var _contracts: VBoxContainer
var _contracts_box: VBoxContainer
var _contracts_header: Label
var _contract_rows: Array[ContractRow] = []
## "Reserved for bounties: 1,600 cr" (bounty escrow), above the contract rows.
var _escrow_label: Label
var _structure_rows: Array[OverviewRow] = []
var _threats: VBoxContainer
var _threats_box: VBoxContainer
var _threats_header: Label
var _threat_rows: Array[OverviewRow] = []
var _scrap: VBoxContainer
var _scrap_header: Label
var _scrap_rows: Array[OverviewRow] = []
var _clusters: VBoxContainer
var _clusters_header: Label
var _cluster_rows: Array[OverviewRow] = []
var _threats_dirty := false
var _outlook: Label
var _refresh_timer := 0.0


func _ready() -> void:
	custom_minimum_size.x = panel_width
	add_theme_constant_override("separation", 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame = PanelContainer.new()
	_frame.name = "Frame"
	_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_frame)
	var fv := VBoxContainer.new()
	fv.add_theme_constant_override("separation", 8)
	_frame.add_child(fv)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 2)
	fv.add_child(tabs)
	for i in TAB_NAMES.size():
		var b := UIUtil.button("", &"TabButton")
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 50.0
		b.tooltip_text = TAB_NAMES[i].capitalize() + " (Tab collapses the panel)"
		var v := VBoxContainer.new()
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", 1)
		b.add_child(v)
		var top := HBoxContainer.new()
		top.alignment = BoxContainer.ALIGNMENT_CENTER
		top.add_theme_constant_override("separation", 5)
		v.add_child(top)
		var ic := HudStyle.icon_rect(TAB_ICONS[i], 16.0, HudStyle.TEXT_DIM)
		ic.name = "Icon"
		top.add_child(ic)
		var cnt := UIUtil.label("", &"NumberLabel")
		cnt.add_theme_font_size_override("font_size", 14)
		top.add_child(cnt)
		_tab_counts.append(cnt)
		var name_l := UIUtil.label(TAB_NAMES[i], &"SubHeaderLabel")
		name_l.name = "Name"
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.add_theme_font_size_override("font_size", 12)
		v.add_child(name_l)
		UIUtil.ignore_mouse(b)
		b.pressed.connect(_on_tab_pressed.bind(i))
		tabs.add_child(b)
		_tab_buttons.append(b)
	_toggle_button = UIUtil.button("", &"IconButton")
	_toggle_button.icon = HudStyle.icon(&"collapse")
	_toggle_button.custom_minimum_size = Vector2(26.0, 50.0)
	_toggle_button.tooltip_text = "Collapse the panel (Tab)"
	_toggle_button.pressed.connect(toggle)
	tabs.add_child(_toggle_button)

	# One scroll; each tab shows its group, ALL shows the three.
	_body = VBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fv.add_child(_body)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.focus_mode = Control.FOCUS_NONE
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The scroll and its bottom fade share a plain holder.
	var holder := Control.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(holder)
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(_scroll)
	_fade = _make_fade()
	holder.add_child(_fade)
	var vbar := _scroll.get_v_scroll_bar()
	vbar.value_changed.connect(func(_v: float) -> void: _sync_fade())
	vbar.changed.connect(_sync_fade)
	var groups := VBoxContainer.new()
	groups.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	groups.add_theme_constant_override("separation", 14)
	_scroll.add_child(groups)
	_contracts = _make_group(groups)
	_threats = _make_group(groups)
	_list = _make_group(groups)
	# Room under the last row, so scrolled to the end it clears the frame.
	var end_pad := Control.new()
	end_pad.custom_minimum_size.y = 6.0
	end_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	groups.add_child(end_pad)
	_set_tab(Tab.ALL)
	get_viewport().size_changed.connect(_fit_height)
	_fit_height.call_deferred()


## A strip along the scroll's bottom edge that fades the cut row into the
## panel, so a part row reads as "more below" (the scroll bar is thin).
func _make_fade() -> TextureRect:
	var grad := Gradient.new()
	grad.set_color(0, Color(HudStyle.PANEL_BG_BOTTOM, 0.0))
	grad.set_color(1, Color(HudStyle.PANEL_BG_BOTTOM, 0.97))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	tex.width = 4
	tex.height = 32
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	r.offset_top = -30.0
	# Leaves the scroll bar unfaded.
	r.offset_right = -10.0
	r.visible = false
	return r


func _sync_fade() -> void:
	var vb := _scroll.get_v_scroll_bar()
	_fade.visible = vb.max_value - vb.page - vb.value > 2.0


## A group of sections in the shared scroll.
func _make_group(parent: VBoxContainer) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 1)
	parent.add_child(v)
	return v


func _on_tab_pressed(i: int) -> void:
	if not is_open:
		set_open(true)
	_set_tab(i as Tab)


func _set_tab(t: Tab) -> void:
	tab = t
	_list.visible = t == Tab.ALL or t == Tab.SYSTEM
	_contracts.visible = t == Tab.ALL or t == Tab.CONTRACTS
	_threats.visible = t == Tab.ALL or t == Tab.THREATS
	_scroll.scroll_vertical = 0
	for i in _tab_buttons.size():
		var on := i == int(t)
		_tab_buttons[i].set_pressed_no_signal(on and is_open)
		var ic := _tab_buttons[i].find_child("Icon", true, false) as TextureRect
		ic.modulate = HudStyle.ACCENT if on and is_open else HudStyle.TEXT_DIM
		var nl := _tab_buttons[i].find_child("Name", true, false) as Label
		nl.add_theme_color_override("font_color", HudStyle.TEXT_BRIGHT if on and is_open else HudStyle.TEXT_DIM)


## Opens the panel on [param t] (probes, hotkeys).
func show_tab(t: Tab) -> void:
	set_open(true)
	_set_tab(t)


func setup(owner_hud: HUD) -> void:
	hud = owner_hud
	if hud.camera:
		hud.camera.follow_changed.connect(_sync_pressed)
	if hud.selection:
		hud.selection.selection_changed.connect(func(_t: Node3D) -> void: _sync_pressed(hud.camera.get_follow_target() if hud.camera else null))
	if hud.manager:
		hud.manager.building_added.connect(func(_b: Building) -> void: _rebuild_structures())
		hud.manager.building_changed.connect(func(_b: Building) -> void: _rebuild_structures())
	ContractBoard.contract_posted.connect(func(_c: Contract) -> void: _rebuild_contracts())
	ContractBoard.contract_removed.connect(func(_c: Contract) -> void: _rebuild_contracts())
	ContractBoard.contract_changed.connect(func(_c: Contract) -> void: _refresh_contracts())
	var world := CombatWorld.of(get_tree())
	if world:
		world.combatant_spawned.connect(func(_n: Node3D) -> void: _threats_dirty = true)
		world.combatant_destroyed.connect(func(_n: Node3D, _k: Node3D) -> void: _threats_dirty = true)
		world.scrap_changed.connect(func() -> void: _rebuild_scrap.call_deferred())
		if world.threats:
			world.threats.changed.connect(func() -> void: _threats_dirty = true)
	if hud.solar_system:
		hud.solar_system.den_added.connect(func(_d: ScavengerDen) -> void: _threats_dirty = true)
		hud.solar_system.cluster_added.connect(func(_b: AsteroidCluster) -> void: _rebuild_clusters.call_deferred())
		hud.solar_system.cluster_removed.connect(func(_b: AsteroidCluster) -> void: _rebuild_clusters.call_deferred())
	_rebuild()


func toggle() -> void:
	set_open(not is_open)


func set_open(open: bool) -> void:
	is_open = open
	_body.visible = open
	_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL if open else Control.SIZE_SHRINK_BEGIN
	_toggle_button.icon = HudStyle.icon(&"collapse" if open else &"expand")
	_toggle_button.tooltip_text = ("Collapse" if open else "Expand") + " the panel (Tab)"
	_set_tab(tab)
	_fit_height()
	if not open and hud:
		hud.marker.hover_target = null


func find_row(target: Node) -> OverviewRow:
	for r in rows:
		if r.target == target:
			return r
	return null


func _process(delta: float) -> void:
	_refresh_timer -= delta
	if _refresh_timer > 0.0:
		return
	_refresh_timer = 0.25
	for r in _structure_rows:
		if not is_instance_valid(r.target):
			continue
		if r.target is Building:
			r.set_subtitle(_building_subtitle(r.target as Building))
	_refresh_contracts()
	if _threats_dirty:
		_threats_dirty = false
		_rebuild_threats()
	else:
		_refresh_threats()
	for r in _scrap_rows:
		if is_instance_valid(r.target):
			r.set_subtitle((r.target as ScrapField).get_status_text())
	_refresh_planet_rows()
	for r in _cluster_rows:
		if is_instance_valid(r.target):
			_refresh_cluster_row(r)


## Planet and moon rows: type, plus the claim (phase C3).
func _refresh_planet_rows() -> void:
	var sys := hud.solar_system if hud else null
	if sys == null:
		return
	var claims := PlanetClaims.of(get_tree())
	for p in sys.planets:
		for b in [p] + p.get_children().filter(func(n: Node) -> bool: return n is PlanetBody):
			var body := b as PlanetBody
			var r := find_row(body)
			if r == null:
				continue
			var kind: String = (MOON_TYPES if body != p else PLANET_TYPES)[body.def.type]
			var g := claims.garrison_of(body) if claims else null
			r.set_subtitle("%s, held by %s" % [kind, g.gang if not g.gang.is_empty() else g.faction_def.display_name] if g else kind)


# --- Build the list -----------------------------------------------------------

func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	rows.clear()
	_structure_rows.clear()
	var sys := hud.solar_system
	if sys == null:
		return
	if hud.top_bar:
		hud.top_bar.set_system_name(sys.system_def.system_name if sys.system_def else "")

	if sys.star:
		_section(_list, "STAR", -1, &"star")
		var temp := int(sys.system_def.star_temperature) if sys.system_def else 0
		_add_row(_list, sys.star, sys.system_def.system_name if sys.system_def else "Star", "%d K" % temp)

	_section(_list, "PLANETS", sys.planets.size(), &"planet")
	for p in sys.planets:
		_add_row(_list, p, p.def.name, PLANET_TYPES[p.def.type])
		for c in p.get_children():
			if c is PlanetBody:
				var m := c as PlanetBody
				_add_row(_list, m, m.def.name, MOON_TYPES[m.def.type], 1)

	_clusters_header = _section(_list, "ASTEROID CLUSTERS", sys.belts.size(), &"belt")
	_clusters = VBoxContainer.new()
	_clusters.add_theme_constant_override("separation", 1)
	_list.add_child(_clusters)
	_rebuild_clusters()

	_section(_list, "STATIONS AND STRUCTURES", -1, &"station")
	_structures = VBoxContainer.new()
	_structures.add_theme_constant_override("separation", 1)
	_list.add_child(_structures)
	_rebuild_structures()

	if not sys.gates.is_empty():
		_section(_list, "JUMP GATES", sys.gates.size(), &"gate")
		for g in sys.gates:
			_add_row(_list, g, g.def.name, "to %s" % g.def.target_system)

	_scrap_header = _section(_list, "SCRAP FIELDS", 0, &"scrap")
	_scrap = VBoxContainer.new()
	_scrap.add_theme_constant_override("separation", 1)
	_list.add_child(_scrap)
	_rebuild_scrap()

	_contracts_header = _section(_contracts, "POSTED CONTRACTS", 0, &"tab_contracts")
	_contracts_box = VBoxContainer.new()
	_contracts_box.add_theme_constant_override("separation", 1)
	_contracts.add_child(_contracts_box)
	_rebuild_contracts()

	_threats_header = _section(_threats, "HOSTILES OUT", 0, &"tab_threats")
	_threats_box = VBoxContainer.new()
	_threats_box.add_theme_constant_override("separation", 1)
	_threats.add_child(_threats_box)
	_rebuild_threats()


# --- Threats and scrap ----------------------------------------------------------

func _rebuild_threats() -> void:
	if _threats_box == null:
		return
	_clear_rows(_threats_box, _threat_rows)
	var dens: Array[ScavengerDen] = []
	if hud.solar_system:
		dens = hud.solar_system.dens
	# Grouped by faction, in the order their first base appears.
	var groups: Array[FactionDef] = []
	var by_faction: Dictionary = {}
	for d in dens:
		if not is_instance_valid(d):
			continue
		if not by_faction.has(d.faction_def):
			by_faction[d.faction_def] = [] as Array[ScavengerDen]
			groups.append(d.faction_def)
		(by_faction[d.faction_def] as Array[ScavengerDen]).append(d)
	var world := CombatWorld.of(get_tree())
	var threats := world.threats if world else null
	var site: DenArrivalSite = threats.site if threats and is_instance_valid(threats.site) else null
	if site and not by_faction.has(site.faction_def):
		by_faction[site.faction_def] = [] as Array[ScavengerDen]
		groups.append(site.faction_def)
	var count := 0
	for f in groups:
		var group: Array[ScavengerDen] = by_faction[f]
		var head := _faction_header(f)
		var live := 0
		var out := 0
		for d in group:
			if d.is_alive():
				live += 1
			count += _add_den_rows(d, f)
			out += _live_ships(d).size()
		var arriving := ""
		if site and site.faction_def == f:
			_add_site_row(site, f)
			arriving = ", 1 arriving"
		(head.get_node(^"Count") as Label).text = "%d/%d bases, %d ships%s" % [live, group.size(), out, arriving]
	if _threats_header:
		_threats_header.text = str(count)
	var live_bases := 0
	var raiders := 0
	for d in dens:
		if is_instance_valid(d) and d.is_alive():
			live_bases += 1
			for sc in d.raiders:
				if is_instance_valid(sc) and not sc.dead:
					raiders += 1
	_set_count(Tab.THREATS, str(live_bases), raiders > 0)
	_tab_buttons[Tab.THREATS].tooltip_text = "Threats: %d hostile bases, %d ships out%s" % [live_bases, count, (", %d raiding" % raiders) if raiders > 0 else ""]
	if count == 0 and groups.is_empty():
		var none := UIUtil.label("No hostile bases detected.", &"DimLabel")
		none.name = "None"
		_threats_box.add_child(none)
	_outlook = UIUtil.label("", &"DimLabel")
	_outlook.name = "Outlook"
	_threats_box.add_child(_outlook)
	_update_outlook()
	_sync_pressed(hud.camera.get_follow_target() if hud.camera else null)
	_fit_height.call_deferred()


## A small coloured faction line above its bases in the threats list.
func _faction_header(f: FactionDef) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(UIUtil.spacer(8.0))
	var swatch := ColorRect.new()
	swatch.color = f.color
	swatch.custom_minimum_size = Vector2(8.0, 8.0)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(swatch)
	var l := UIUtil.label(f.display_name.to_upper(), &"DimLabel")
	l.add_theme_color_override("font_color", f.color.lerp(Color.WHITE, 0.2))
	h.add_child(l)
	var c := UIUtil.label("", &"DimLabel")
	c.name = "Count"
	h.add_child(c)
	_threats_box.add_child(h)
	return h


## The base's row and one per ship it has out. Returns the ships listed.
func _add_den_rows(d: ScavengerDen, f: FactionDef) -> int:
	var row := _add_row(_threats_box, d, d.get_display_name(), _den_subtitle(d))
	row.title_label.add_theme_color_override("font_color", f.color.lerp(Color.WHITE, 0.3) if d.is_alive() else Color(0.55, 0.55, 0.58))
	var bar := UIUtil.bar(f.color, Vector2(36.0, 4.0))
	bar.value = d.hull_fraction()
	bar.name = "Hull"
	row.add_right(bar)
	row.tooltip_text = "%s\n%s %s, %s\nSelect it to post a bounty." % [d.get_display_name(), f.display_name, d.kind_name(), d.claim_text()]
	_threat_rows.append(row)
	var ships := _live_ships(d)
	for sc in ships:
		var sr := _add_row(_threats_box, sc, sc.callsign + (" (raider)" if sc.is_raider else ""), sc.get_status_text().to_lower(), 1)
		sr.title_label.add_theme_color_override("font_color", f.color.lerp(Color.WHITE, 0.4))
		_threat_rows.append(sr)
	return ships.size()


## A base being announced: no hull, a countdown.
func _add_site_row(site: DenArrivalSite, f: FactionDef) -> void:
	var row := _add_row(_threats_box, site, site.get_display_name(), site.get_status_text().to_lower())
	row.title_label.add_theme_color_override("font_color", Color(f.color.lerp(Color.WHITE, 0.3), 0.75))
	row.tooltip_text = "%s\nLong-range scans: %s ships gathering near %s.\nArrives in %s." % [site.get_display_name(), f.unit_name, site.def.belt_name, site.countdown_text()]
	_threat_rows.append(row)


func _update_outlook() -> void:
	if not is_instance_valid(_outlook):
		return
	var world := CombatWorld.of(get_tree())
	var text := world.threats.outlook_text() if world and world.threats else ""
	_outlook.text = "   " + text
	_outlook.visible = not text.is_empty()


func _live_ships(d: ScavengerDen) -> Array[ScavengerShip]:
	var out: Array[ScavengerShip] = []
	for sc in d.spawns + d.raiders:
		if is_instance_valid(sc) and not sc.dead:
			out.append(sc)
	return out


func _refresh_threats() -> void:
	_update_outlook()
	for r in _threat_rows:
		if not is_instance_valid(r.target):
			_threats_dirty = true
			continue
		if r.target is DenArrivalSite:
			r.set_subtitle((r.target as DenArrivalSite).get_status_text().to_lower())
		elif r.target is ScavengerDen:
			var d := r.target as ScavengerDen
			r.set_subtitle(_den_subtitle(d))
			var bar := r.right_box.get_node_or_null(^"Hull") as PipMeter
			if bar:
				bar.value = d.hull_fraction()
		elif r.target is ScavengerShip:
			var sc := r.target as ScavengerShip
			if sc.dead:
				_threats_dirty = true
			else:
				r.set_subtitle(sc.get_status_text().to_lower())


func _den_subtitle(d: ScavengerDen) -> String:
	if not d.is_alive():
		return "destroyed"
	return "%d/%d out, hull %d%%" % [d.spawns.size(), d.def.spawn_cap, roundi(d.hull_fraction() * 100.0)]


func _rebuild_scrap() -> void:
	if _scrap == null:
		return
	_clear_rows(_scrap, _scrap_rows)
	var world := CombatWorld.of(get_tree())
	var fields: Array[ScrapField] = []
	if world:
		fields = world.get_scrap_fields()
	if _scrap_header:
		_scrap_header.text = str(fields.size())
	for f in fields:
		var row := _add_row(_scrap, f, f.display_name, f.get_status_text())
		row.title_label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.68))
		_scrap_rows.append(row)
	_fit_height.call_deferred()


# --- Tab counts ---------------------------------------------------------------------

## The count on a tab; [param alert] tints it red (fighting, raiders out).
func _set_count(t: Tab, text: String, alert: bool = false) -> void:
	var l := _tab_counts[int(t)]
	l.text = text
	l.add_theme_color_override("font_color", HudStyle.BAD if alert else HudStyle.TEXT_BRIGHT)
	var ic := _tab_buttons[int(t)].find_child("Icon", true, false) as TextureRect
	if alert:
		ic.modulate = HudStyle.BAD
	elif int(t) != int(tab) or not is_open:
		ic.modulate = HudStyle.TEXT_DIM


func _clear_rows(box: Container, list: Array[OverviewRow]) -> void:
	for r in list:
		rows.erase(r)
	list.clear()
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _rebuild_structures() -> void:
	if _structures == null:
		return
	for r in _structure_rows:
		rows.erase(r)
	_structure_rows.clear()
	for c in _structures.get_children():
		_structures.remove_child(c)
		c.queue_free()
	var sys := hud.solar_system
	if sys.home_station:
		var host := sys.home_station.get_parent() as PlanetBody
		var sub := "%s orbit" % host.def.name if host else ""
		var station_row := _add_row(_structures, sys.home_station, "Home Station", sub)
		if hud.manager:
			var bays := "Addon bays: %d/%d used" % [hud.manager.used_bays(), BuildingManager.BAY_COUNT]
			station_row.set_subtitle("%s, bays %d/%d" % [sub, hud.manager.used_bays(), BuildingManager.BAY_COUNT] if not sub.is_empty() else bays)
			station_row.tooltip_text = bays
		_structure_rows.append(station_row)
	if hud.manager:
		for b in hud.manager.buildings:
			if not is_instance_valid(b):
				continue
			_structure_rows.append(_add_row(_structures, b, b.display_name, _building_subtitle(b), 1))
	_sync_pressed(hud.camera.get_follow_target() if hud.camera else null)
	_fit_height.call_deferred()


func _building_subtitle(b: Building) -> String:
	if not b.is_active():
		return b.get_status_text().to_lower()
	if b.def.can_hire():
		var rep := b.repairing_count()
		return "active, %d/%d %s%s" % [b.ships.size(), b.def.max_hires, UIUtil.plural(b.def.hire_role).to_lower(), ", %d repairing" % rep if rep > 0 else ""]
	var ds := b.get_service() as DefenseStructure
	if ds:
		return ds.get_status_text().to_lower()
	var f := b.get_service() as Factory
	if f:
		return "%s, %d parts" % [f.status_text().to_lower(), f.warehouse_total()]
	return "active"


func _rebuild_contracts() -> void:
	if _contracts_box == null:
		return
	for r in _contract_rows:
		rows.erase(r)
	_contract_rows.clear()
	for c in _contracts_box.get_children():
		_contracts_box.remove_child(c)
		c.queue_free()
	var list := ContractBoard.get_listed()
	if _contracts_header:
		_contracts_header.text = str(list.size())
	_set_count(Tab.CONTRACTS, str(list.size()))
	if list.is_empty():
		var none := UIUtil.label("None. Select a cluster, ship or scrap field to post one.", &"DimLabel")
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_left", 8)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_child(none)
		_contracts_box.add_child(m)
	_escrow_label = UIUtil.label("", &"DimLabel")
	_escrow_label.add_theme_font_size_override("font_size", 12)
	var em := MarginContainer.new()
	em.add_theme_constant_override("margin_left", 8)
	em.mouse_filter = Control.MOUSE_FILTER_IGNORE
	em.add_child(_escrow_label)
	_contracts_box.add_child(em)
	_update_escrow()
	for c in list:
		var row := ContractRow.new(c, hud, true)
		_contracts_box.add_child(row)
		_contract_rows.append(row)
		rows.append(row)
	_fit_height.call_deferred()


func _refresh_contracts() -> void:
	_update_escrow()
	for r in _contract_rows:
		if is_instance_valid(r):
			r.refresh()


func _update_escrow() -> void:
	if not is_instance_valid(_escrow_label):
		return
	var held := ContractBoard.escrow_total()
	var zones := ContractBoard.zone_escrow_total()
	_escrow_label.text = "Reserved for bounties: %s cr" % UIUtil.amount(held - zones)
	if zones > 0:
		_escrow_label.text += ", zone budgets: %s cr" % UIUtil.amount(zones)
	(_escrow_label.get_parent() as Control).visible = held > 0


## Adds a section header strip to [param parent]; returns its count label
## (null without a count).
func _section(parent: VBoxContainer, title: String, count: int = -1, icon_name: StringName = &"") -> Label:
	if parent.get_child_count() > 0:
		var spacer := Control.new()
		spacer.custom_minimum_size.y = 8.0
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(spacer)
	var strip := PanelContainer.new()
	strip.theme_type_variation = &"SectionPanel"
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(strip)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(h)
	if not icon_name.is_empty():
		h.add_child(HudStyle.icon_rect(icon_name, 14.0, HudStyle.HOLO))
	h.add_child(UIUtil.label(title, &"HeaderLabel"))
	h.add_child(UIUtil.spacer())
	var count_label: Label = null
	if count >= 0:
		count_label = UIUtil.label(str(count), &"NumberLabel")
		count_label.add_theme_font_size_override("font_size", 13)
		count_label.add_theme_color_override("font_color", HudStyle.TEXT_DIM)
		h.add_child(count_label)
	var gap := Control.new()
	gap.custom_minimum_size.y = 3.0
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(gap)
	return count_label


func _add_row(parent: Container, target: Node3D, title: String, subtitle: String, depth: int = 0) -> OverviewRow:
	var row := OverviewRow.new(target, title, subtitle, depth)
	row.pressed.connect(_on_row_pressed.bind(row))
	row.hovered.connect(_on_row_hovered)
	parent.add_child(row)
	rows.append(row)
	return row


func _rebuild_clusters() -> void:
	if _clusters == null or hud == null or hud.solar_system == null:
		return
	_clear_rows(_clusters, _cluster_rows)
	var sys := hud.solar_system
	if _clusters_header:
		_clusters_header.text = str(sys.belts.size())
	for b in sys.belts:
		if is_instance_valid(b):
			_add_belt_row(b)
	_fit_height.call_deferred()


func _add_belt_row(belt: AsteroidCluster) -> void:
	var d := belt.def
	var ore := ORE_NAMES[d.ore_type]
	var row := _add_row(_clusters, belt, d.name, ore)
	_cluster_rows.append(row)
	var bar := UIUtil.bar(HudStyle.TEXT, Vector2(36.0, 4.0))
	bar.value = d.richness
	row.add_right(bar)
	var pct := UIUtil.label("%d%%" % roundi(d.richness * 100.0), &"DimLabel")
	pct.custom_minimum_size.x = 32.0
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_right(pct)
	var pips := PipMeter.new()
	pips.name = "Danger"
	pips.style = PipMeter.Style.PIPS
	pips.max_value = 5.0
	pips.graded = true
	pips.pip_size = 6.0
	pips.pip_gap = 2.0
	row.add_right(pips)
	row.set_meta(&"danger_pips", pips)
	_refresh_cluster_row(row)


## Live parts of a cluster row: what is left, the danger (bases drift in and out of reach).
func _refresh_cluster_row(row: OverviewRow) -> void:
	var belt := row.target as AsteroidCluster
	if belt == null:
		return
	var d := belt.def
	var ores := ORE_NAMES[d.ore_type]
	if d.secondary_ore != AsteroidBelt.OreType.ROCK and d.secondary_ore != d.ore_type:
		ores += ", " + ORE_NAMES[d.secondary_ore]
	var left := "mined out" if belt.is_depleted else "%d%% left" % roundi(belt.fill_fraction() * 100.0)
	row.set_subtitle("%s, %s" % [ORE_NAMES[d.ore_type], left])
	var pips := row.get_meta(&"danger_pips", null) as PipMeter
	if pips:
		pips.value = float(belt.danger)
	row.tooltip_text = "%s\nOre: %s\nRichness %d%%\n%d of %d loads left\nDanger %d of 5" % [d.name, ores, roundi(d.richness * 100.0), belt.loads_left, belt.reserve, belt.danger]


# --- Interaction --------------------------------------------------------------

func _on_row_pressed(row: OverviewRow) -> void:
	if not is_instance_valid(row.target):
		return
	if hud.camera:
		hud.camera.focus_on(row.target)
	if hud.selection:
		if row.target is Building or row.target is Ship or row.target is ScavengerDen or row.target is ScrapField or row.target is PlanetBody:
			hud.selection.select(row.target)
		elif row.target.get_meta(&"belt", null) is AsteroidCluster:
			hud.selection.select(row.target.get_meta(&"belt") as AsteroidCluster)
	_sync_pressed(hud.camera.get_follow_target() if hud.camera else null)


func _on_row_hovered(row: OverviewRow, on: bool) -> void:
	if on:
		hud.marker.hover_target = row.target
	elif hud.marker.hover_target == row.target:
		hud.marker.hover_target = null


## Highlights the rows of the followed target and the selection.
func _sync_pressed(target: Node3D) -> void:
	var sel: Node3D = hud.selection.selected if hud and hud.selection else null
	for r in rows:
		if is_instance_valid(r):
			r.set_pressed_no_signal(r.target != null and (r.target == target or r.target == sel))


## The panel runs from its top down to [member bottom_margin] above the
## screen bottom (the event feed lives below it).
func _fit_height() -> void:
	if _frame == null:
		return
	var vp := get_viewport_rect().size
	var h := vp.y - position.y - bottom_margin
	if is_open:
		custom_minimum_size.y = maxf(h, 200.0)
		size.y = custom_minimum_size.y
	else:
		custom_minimum_size.y = 0.0
		size.y = 0.0

class_name OverviewPanel
extends VBoxContainer
## Left-side system overview. Lists everything in the SolarSystem, grouped:
## star, planets (moons nested), asteroid belts, posted contracts (with
## cancel), jump gates, stations and structures (player buildings and their
## hired ships with live status, updated live), threats (the bases that
## have arrived, grouped by faction, with their status and the ships out,
## raiders included; a base being announced as "arriving in m:ss"; a vague
## "Next: unknown signals, ~6 min" outlook line from the ThreatDirector), scrap
## fields and the captain roster (grouped by role, rank badge, live status;
## captains without a ship included). Mercenaries flying in a fleet are
## grouped under a fleet line (leader first).
## Click a row = camera flies to it and follows; the row stays highlighted
## while the camera follows that target or while it is selected. Collapses
## with its button or Tab.

const PLANET_TYPES: PackedStringArray = ["Rocky world", "Ocean world", "Desert world", "Ice world", "Lava world", "Gas giant"]
const MOON_TYPES: PackedStringArray = ["Rocky moon", "Ocean moon", "Desert moon", "Ice moon", "Lava moon", "Gas moon"]
const ORE_NAMES: PackedStringArray = ["Rock", "Iron", "Titanium", "Crystal"]

@export var panel_width: float = 380.0
## Space kept free below the panel, pixels.
@export var bottom_margin: float = 160.0

var hud: HUD
var is_open := true
var rows: Array[OverviewRow] = []

var _toggle_button: Button
var _body: PanelContainer
var _scroll: ScrollContainer
var _list: VBoxContainer
var _structures: VBoxContainer
var _contracts: VBoxContainer
var _contracts_header: Label
var _contract_rows: Array[ContractRow] = []
var _system_label: Label
var _structure_rows: Array[OverviewRow] = []
var _threats: VBoxContainer
var _threats_header: Label
var _threat_rows: Array[OverviewRow] = []
var _scrap: VBoxContainer
var _scrap_header: Label
var _scrap_rows: Array[OverviewRow] = []
var _threats_dirty := false
var _outlook: Label
var _roster: VBoxContainer
var _roster_header: Label
var _roster_rows: Array[OverviewRow] = []
var _roster_key := ""
var _refresh_timer := 0.0


func _ready() -> void:
	custom_minimum_size.x = panel_width
	add_theme_constant_override("separation", 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var header := PanelContainer.new()
	header.name = "Header"
	add_child(header)
	var hh := HBoxContainer.new()
	header.add_child(hh)
	hh.add_child(UIUtil.label("SYSTEM", &"HeaderLabel"))
	_system_label = UIUtil.label("")
	hh.add_child(_system_label)
	hh.add_child(UIUtil.spacer())
	hh.add_child(UIUtil.label("Tab", &"DimLabel"))
	_toggle_button = UIUtil.button("-", &"IconButton")
	_toggle_button.custom_minimum_size = Vector2(26.0, 22.0)
	_toggle_button.tooltip_text = "Collapse the overview (Tab)"
	_toggle_button.pressed.connect(toggle)
	hh.add_child(_toggle_button)

	_body = PanelContainer.new()
	_body.name = "Body"
	add_child(_body)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.focus_mode = Control.FOCUS_NONE
	_body.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 1)
	_scroll.add_child(_list)
	get_viewport().size_changed.connect(_fit_height)


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
	_rebuild()


func toggle() -> void:
	set_open(not is_open)


func set_open(open: bool) -> void:
	is_open = open
	_body.visible = open
	_toggle_button.text = "-" if open else "+"
	_toggle_button.tooltip_text = ("Collapse" if open else "Expand") + " the overview (Tab)"
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
		elif r.target is Ship:
			r.set_subtitle(_ship_subtitle(r.target as Ship))
	_refresh_contracts()
	if _threats_dirty:
		_threats_dirty = false
		_rebuild_threats()
	else:
		_refresh_threats()
	for r in _scrap_rows:
		if is_instance_valid(r.target):
			r.set_subtitle((r.target as ScrapField).get_status_text())
	if _roster_signature() != _roster_key:
		_rebuild_roster()
	else:
		for r in _roster_rows:
			var c := r.get_meta(&"captain") as Captain
			if c:
				r.set_subtitle(_captain_subtitle(c))


# --- Build the list -----------------------------------------------------------

func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	rows.clear()
	_structure_rows.clear()
	var sys := hud.solar_system
	if sys == null:
		return
	_system_label.text = sys.system_def.system_name if sys.system_def else ""

	if sys.star:
		_section("STAR")
		var temp := int(sys.system_def.star_temperature) if sys.system_def else 0
		_add_row(_list, sys.star, sys.system_def.system_name if sys.system_def else "Star", "%d K" % temp)

	_section("PLANETS", sys.planets.size())
	for p in sys.planets:
		_add_row(_list, p, p.def.name, PLANET_TYPES[p.def.type])
		for c in p.get_children():
			if c is PlanetBody:
				var m := c as PlanetBody
				_add_row(_list, m, m.def.name, MOON_TYPES[m.def.type], 1)

	if not sys.belts.is_empty():
		_section("ASTEROID BELTS", sys.belts.size())
		for i in sys.belts.size():
			_add_belt_row(sys.belts[i], sys.belt_anchors[i] if i < sys.belt_anchors.size() else null)

	_contracts_header = _section("CONTRACTS", 0)
	_contracts = VBoxContainer.new()
	_contracts.add_theme_constant_override("separation", 1)
	_list.add_child(_contracts)
	_rebuild_contracts()

	_roster_header = _section("CAPTAINS", 0)
	_roster = VBoxContainer.new()
	_roster.add_theme_constant_override("separation", 1)
	_list.add_child(_roster)
	_rebuild_roster()

	_threats_header = _section("THREATS", 0)
	_threats = VBoxContainer.new()
	_threats.add_theme_constant_override("separation", 1)
	_list.add_child(_threats)
	_rebuild_threats()

	if not sys.gates.is_empty():
		_section("JUMP GATES", sys.gates.size())
		for g in sys.gates:
			_add_row(_list, g, g.def.name, "to %s" % g.def.target_system)

	_section("STATIONS & STRUCTURES")
	_structures = VBoxContainer.new()
	_structures.add_theme_constant_override("separation", 1)
	_list.add_child(_structures)
	_rebuild_structures()

	_scrap_header = _section("SCRAP FIELDS", 0)
	_scrap = VBoxContainer.new()
	_scrap.add_theme_constant_override("separation", 1)
	_list.add_child(_scrap)
	_rebuild_scrap()


# --- Threats and scrap ----------------------------------------------------------

func _rebuild_threats() -> void:
	if _threats == null:
		return
	_clear_rows(_threats, _threat_rows)
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
	_outlook = UIUtil.label("", &"DimLabel")
	_outlook.name = "Outlook"
	_threats.add_child(_outlook)
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
	_threats.add_child(h)
	return h


## The base's row and one per ship it has out. Returns the ships listed.
func _add_den_rows(d: ScavengerDen, f: FactionDef) -> int:
	var row := _add_row(_threats, d, d.get_display_name(), _den_subtitle(d))
	row.title_label.add_theme_color_override("font_color", f.color.lerp(Color.WHITE, 0.3) if d.is_alive() else Color(0.55, 0.55, 0.58))
	var bar := PipMeter.new()
	bar.style = PipMeter.Style.BAR
	bar.max_value = 1.0
	bar.value = d.hull_fraction()
	bar.custom_minimum_size = Vector2(36.0, 4.0)
	bar.color = f.color
	bar.name = "Hull"
	row.add_right(bar)
	row.tooltip_text = "%s\n%s %s, claims %s\nSelect it to post a bounty." % [d.get_display_name(), f.display_name, f.den_kind, d.belt.def.name if d.belt else "?"]
	_threat_rows.append(row)
	var ships := _live_ships(d)
	for sc in ships:
		var sr := _add_row(_threats, sc, sc.callsign + (" (raider)" if sc.is_raider else ""), sc.get_status_text().to_lower(), 1)
		sr.title_label.add_theme_color_override("font_color", f.color.lerp(Color.WHITE, 0.4))
		_threat_rows.append(sr)
	return ships.size()


## A base being announced: no hull, a countdown.
func _add_site_row(site: DenArrivalSite, f: FactionDef) -> void:
	var row := _add_row(_threats, site, site.get_display_name(), site.get_status_text().to_lower())
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


# --- Captain roster --------------------------------------------------------------

## Every hired captain still alive, grouped by role.
func _captains_by_role() -> Dictionary:
	var out: Dictionary = {}
	if hud.manager == null:
		return out
	for b in hud.manager.buildings:
		if not is_instance_valid(b):
			continue
		for c in b.captains:
			if not c.alive:
				continue
			if not out.has(c.role):
				out[c.role] = []
			(out[c.role] as Array).append({"captain": c, "building": b})
	return out


func _roster_signature() -> String:
	var parts: PackedStringArray = []
	var by := _captains_by_role()
	for role: String in by:
		for e: Dictionary in by[role]:
			var c := e["captain"] as Captain
			var f := _fleet_of(c)
			parts.append("%s:%s:%d:%d:%d:%d" % [role, c.captain_name, c.rank, (c.ship.get_instance_id() if is_instance_valid(c.ship) else 0),
					f.get_instance_id() if f else 0, f.members.size() if f else 0])
	return ",".join(parts)


func _rebuild_roster() -> void:
	if _roster == null:
		return
	_roster_key = _roster_signature()
	_clear_rows(_roster, _roster_rows)
	var by := _captains_by_role()
	var total := 0
	for role in ["Miner", "Mercenary", "Salvager"]:
		if not by.has(role):
			continue
		var list: Array = _group_fleets(by[role])
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(UIUtil.spacer(14.0))
		h.add_child(UIUtil.label(UIUtil.plural(role), &"DimLabel"))
		h.add_child(UIUtil.label(str(list.size()), &"DimLabel"))
		_roster.add_child(h)
		var shown_fleet: MercFleet = null
		for e: Dictionary in list:
			var c := e["captain"] as Captain
			var t: Node3D = c.ship if is_instance_valid(c.ship) else e["building"] as Building
			var f := _fleet_of(c)
			if f and f != shown_fleet:
				shown_fleet = f
				var fh := HBoxContainer.new()
				fh.mouse_filter = Control.MOUSE_FILTER_IGNORE
				fh.add_child(UIUtil.spacer(26.0))
				var fl := UIUtil.label("%s's fleet (%d) for %s" % [f.leader_name, f.members.size(), f.contract.get_target_name()], &"DimLabel")
				fl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
				fh.add_child(fl)
				_roster.add_child(fh)
			var row := _add_row(_roster, t, c.captain_name, _captain_subtitle(c), 2 if f else 1)
			row.set_meta(&"captain", c)
			row.title_label.add_theme_color_override("font_color", BuildingPanel.PERSONALITY_COLORS[c.personality].lerp(Color.WHITE, 0.55))
			row.title_label.size_flags_stretch_ratio = 0.9
			var names: PackedStringArray = []
			for id in c.trait_ids():
				names.append(CaptainTraits.trait_name(id))
			row.tooltip_text = "%s %s, %s\n%d reputation%s" % [c.get_rank_name(), c.role.to_lower(), c.get_personality_name(), roundi(c.reputation),
					("\n" + ", ".join(names)) if not names.is_empty() else ""]
			row.add_right(UIUtil.rank_badge(c.rank))
			_roster_rows.append(row)
			total += 1
	if total == 0:
		var none := UIUtil.label("None hired yet. Build an outpost to hire captains.", &"DimLabel")
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_left", 8)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_child(none)
		_roster.add_child(m)
	if _roster_header:
		_roster_header.text = str(total)
	_sync_pressed(hud.camera.get_follow_target() if hud.camera else null)
	_fit_height.call_deferred()


## The fleet [param c]'s ship flies in, or null.
static func _fleet_of(c: Captain) -> MercFleet:
	if not is_instance_valid(c.ship):
		return null
	var mb := c.ship.brain as MercenaryBrain
	return mb.fleet if mb and mb.fleet and mb.fleet.state != MercFleet.State.DONE else null


## Roster entries with each fleet's members together, leader first, in
## the place of the fleet's first member.
static func _group_fleets(list: Array) -> Array:
	var out: Array = []
	var done: Dictionary = {}
	for e: Dictionary in list:
		var f := _fleet_of(e["captain"] as Captain)
		if f == null:
			out.append(e)
			continue
		if done.has(f):
			continue
		done[f] = true
		var group: Array = []
		for g: Dictionary in list:
			if _fleet_of(g["captain"] as Captain) == f:
				group.append(g)
		group.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return f.members.find((a["captain"] as Captain).ship) < f.members.find((b["captain"] as Captain).ship))
		out.append_array(group)
	return out


func _captain_subtitle(c: Captain) -> String:
	if c.stranded:
		return "waiting for a ship"
	if is_instance_valid(c.ship):
		return c.ship.get_status_text().to_lower()
	return ""


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
			for s in b.ships:
				var cap := s.captain
				var row := _add_row(_structures, s, cap.captain_name, _ship_subtitle(s), 2)
				row.title_label.add_theme_color_override("font_color", BuildingPanel.PERSONALITY_COLORS[cap.personality].lerp(Color.WHITE, 0.55))
				row.title_label.size_flags_stretch_ratio = 0.9
				row.tooltip_text = "%s, %s: %s" % [cap.role, cap.get_personality_name(), cap.get_personality_hint()]
				_structure_rows.append(row)
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


## Live status, plus the last refusal while waiting at home.
func _ship_subtitle(s: Ship) -> String:
	var text := s.get_status_text()
	var br := s.brain
	if br and not br.last_refusal.is_empty() and (br.state == CaptainBrain.State.DOCKED or br.state == CaptainBrain.State.EVALUATING):
		text += ": " + br.last_refusal.to_lower()
	return text


func _rebuild_contracts() -> void:
	if _contracts == null:
		return
	for r in _contract_rows:
		rows.erase(r)
	_contract_rows.clear()
	for c in _contracts.get_children():
		_contracts.remove_child(c)
		c.queue_free()
	var list := ContractBoard.get_listed()
	if _contracts_header:
		_contracts_header.text = str(list.size())
	if list.is_empty():
		var none := UIUtil.label("None. Select a belt, ship or scrap field to post one.", &"DimLabel")
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_left", 8)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_child(none)
		_contracts.add_child(m)
	for c in list:
		var row := ContractRow.new(c, hud, true)
		_contracts.add_child(row)
		_contract_rows.append(row)
		rows.append(row)
	_fit_height.call_deferred()


func _refresh_contracts() -> void:
	for r in _contract_rows:
		if is_instance_valid(r):
			r.refresh()


## Adds a section header; returns its count label (null without a count).
func _section(title: String, count: int = -1) -> Label:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 6.0 if _list.get_child_count() > 0 else 0.0
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_child(spacer)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UIUtil.label(title, &"HeaderLabel")
	h.add_child(UIUtil.spacer(8.0))
	h.add_child(l)
	var count_label: Label = null
	if count >= 0:
		count_label = UIUtil.label(str(count), &"DimLabel")
		h.add_child(count_label)
	_list.add_child(h)
	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sep.add_theme_constant_override("separation", 4)
	_list.add_child(sep)
	return count_label


func _add_row(parent: Container, target: Node3D, title: String, subtitle: String, depth: int = 0) -> OverviewRow:
	var row := OverviewRow.new(target, title, subtitle, depth)
	row.pressed.connect(_on_row_pressed.bind(row))
	row.hovered.connect(_on_row_hovered)
	parent.add_child(row)
	rows.append(row)
	return row


func _add_belt_row(belt: SystemBelt, anchor: Node3D) -> void:
	var d := belt.def
	var ore := ORE_NAMES[d.ore_type]
	var ores := ore
	if d.secondary_ore != AsteroidBelt.OreType.ROCK and d.secondary_ore != d.ore_type:
		ores += ", " + ORE_NAMES[d.secondary_ore]
	var row := _add_row(_list, anchor if anchor else belt, d.name, ore)
	var bar := PipMeter.new()
	bar.style = PipMeter.Style.BAR
	bar.max_value = 1.0
	bar.value = d.richness
	bar.custom_minimum_size = Vector2(36.0, 4.0)
	bar.color = Color(0.85, 0.88, 0.95)
	row.add_right(bar)
	var pct := UIUtil.label("%d%%" % roundi(d.richness * 100.0), &"DimLabel")
	pct.custom_minimum_size.x = 32.0
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_right(pct)
	var pips := PipMeter.new()
	pips.style = PipMeter.Style.PIPS
	pips.max_value = 5.0
	pips.value = float(d.danger)
	pips.graded = true
	pips.pip_size = 6.0
	pips.pip_gap = 2.0
	row.add_right(pips)
	row.tooltip_text = "%s\nOre: %s\nRichness %d%%\nDanger %d of 5" % [d.name, ores, roundi(d.richness * 100.0), d.danger]


# --- Interaction --------------------------------------------------------------

func _on_row_pressed(row: OverviewRow) -> void:
	if not is_instance_valid(row.target):
		return
	if hud.camera:
		hud.camera.focus_on(row.target)
	if hud.selection:
		if row.target is Building or row.target is Ship or row.target is ScavengerDen or row.target is ScrapField:
			hud.selection.select(row.target)
		elif row.target.get_meta(&"belt", null) is SystemBelt:
			hud.selection.select(row.target.get_meta(&"belt") as SystemBelt)
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


func _fit_height() -> void:
	if _list == null:
		return
	var max_h := get_viewport_rect().size.y - global_position.y - bottom_margin - 40.0
	var want := _list.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = clampf(want, 60.0, maxf(max_h, 60.0))

class_name PlanetPanel
extends PanelContainer
## Bottom-right panel for the selected planet or moon: type, what a surface
## outpost there would harvest, danger, distance from the station, owner (a
## faction claim of C3 in its colour, or "Unclaimed"), the claim's garrison
## strength and patrols with a button that selects the garrison (to post a
## bounty), a pending re-claim, and the outpost (planet outposts plan): its
## state with Go to surface, or Found outpost with its cost and why not.

const OWNER_TEXT := "Unclaimed"

@export var panel_width: float = 380.0

var hud: HUD
var planet: PlanetBody

var _kind: Label
var _title: Label
var _type: Label
var _loot: Label
var _danger: PipMeter
var _danger_text: Label
var _distance: Label
var _owner: Label
var _garrison_title: Label
var _garrison: Label
var _patrols_title: Label
var _patrols: Label
var _claim_note: Label
var _select_garrison: Button
var _outpost_head: Label
var _outpost_text: Label
var _outpost_button: Button
var _refresh_timer := 0.0


func _ready() -> void:
	custom_minimum_size.x = panel_width
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	_kind = UIUtil.label("PLANET", &"HeaderLabel")
	top.add_child(_kind)
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

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	_type = _grid_row(grid, "Type")
	_loot = _grid_row(grid, "Surface")
	grid.add_child(UIUtil.label("Danger", &"DimLabel"))
	var dh := HBoxContainer.new()
	_danger = PipMeter.new()
	_danger.style = PipMeter.Style.PIPS
	_danger.max_value = 5.0
	_danger.graded = true
	_danger.pip_size = 8.0
	_danger.pip_gap = 3.0
	dh.add_child(_danger)
	_danger_text = UIUtil.label("", &"DimLabel")
	dh.add_child(_danger_text)
	grid.add_child(dh)
	_distance = _grid_row(grid, "From home")
	_owner = _grid_row(grid, "Owner")
	_garrison_title = UIUtil.label("Garrison", &"DimLabel")
	grid.add_child(_garrison_title)
	_garrison = UIUtil.label("", &"ValueLabel")
	_garrison.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(_garrison)
	_patrols_title = UIUtil.label("Patrols", &"DimLabel")
	grid.add_child(_patrols_title)
	_patrols = UIUtil.label("", &"ValueLabel")
	_patrols.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(_patrols)
	_claim_note = UIUtil.label("", &"DimLabel")
	_claim_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_claim_note.custom_minimum_size.x = panel_width - 24.0
	v.add_child(_claim_note)
	_select_garrison = UIUtil.button("Select garrison", &"")
	_select_garrison.tooltip_text = "Select the garrison to post a bounty on it. Mercenaries take it on as a fleet."
	_select_garrison.pressed.connect(_on_select_garrison)
	v.add_child(_select_garrison)

	v.add_child(HSeparator.new())
	_outpost_head = UIUtil.label("OUTPOST", &"HeaderLabel")
	v.add_child(_outpost_head)
	_outpost_text = UIUtil.label("", &"DimLabel")
	_outpost_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_outpost_text.custom_minimum_size.x = panel_width - 24.0
	v.add_child(_outpost_text)
	_outpost_button = UIUtil.button("", &"ChipButton")
	_outpost_button.custom_minimum_size.y = 28.0
	_outpost_button.pressed.connect(_on_outpost)
	v.add_child(_outpost_button)


func _grid_row(grid: GridContainer, title: String) -> Label:
	grid.add_child(UIUtil.label(title, &"DimLabel"))
	var l := UIUtil.label("", &"ValueLabel")
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(l)
	return l


func setup(owner_hud: HUD) -> void:
	hud = owner_hud
	if hud.selection:
		hud.selection.selection_changed.connect(func(t: Node3D) -> void: show_planet(t as PlanetBody))
	var outs := Outposts.of(get_tree())
	if outs:
		outs.changed.connect(func(_o: OutpostState) -> void:
			if visible:
				_refresh_outpost())


func is_moon(b: PlanetBody) -> bool:
	return b != null and b.get_parent() is PlanetBody


func show_planet(b: PlanetBody) -> void:
	var changed := b != planet
	planet = b
	visible = b != null
	if b == null:
		return
	_kind.text = "MOON" if is_moon(b) else "PLANET"
	_title.text = b.def.name if not is_moon(b) else "%s, moon of %s" % [b.def.name, (b.get_parent() as PlanetBody).def.name]
	_refresh_info()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 0.5
		_refresh_info()


func _refresh_info() -> void:
	if planet == null or not is_instance_valid(planet):
		return
	var d := planet.def
	var names := OverviewPanel.MOON_TYPES if is_moon(planet) else OverviewPanel.PLANET_TYPES
	_type.text = names[clampi(d.type, 0, names.size() - 1)]
	var good := OutpostState.good_of(d.type)
	if good < 0:
		_loot.text = "Nothing to harvest"
		_loot.remove_theme_color_override("font_color")
		_loot.tooltip_text = ""
	else:
		_loot.text = "%s (%d a harvester load)" % [Economy.ORE_NAMES[good], int(OutpostState.LOAD_UNITS[good])]
		_loot.add_theme_color_override("font_color", Economy.ORE_COLORS[good].lerp(Color.WHITE, 0.35))
		_loot.tooltip_text = _loot_use(good)
	var danger := PlanetInfo.danger_for(planet)
	_danger.value = float(danger)
	var claimed := not PlanetClaims.claim_reason(planet).is_empty()
	_danger_text.text = "%d of 5%s" % [danger, ", garrison in orbit" if claimed else (", no planet defences yet" if danger <= 2 else ", raiders about on the way")]
	_refresh_claim()
	if hud and hud.solar_system and is_instance_valid(hud.solar_system.home_station):
		var km := SpaceNav.flat_distance(planet.global_position, hud.solar_system.home_station.global_position) / 1000.0
		_distance.text = "%.1f km from the station" % km
	else:
		_distance.text = "-"
	_refresh_outpost()


## Owner, garrison, patrols and the re-claim line (phase C3).
func _refresh_claim() -> void:
	var pc := PlanetClaims.of(self)
	var g := pc.garrison_of(planet) if pc else null
	var claimed := g != null
	_garrison_title.visible = claimed
	_garrison.visible = claimed
	_patrols_title.visible = claimed
	_patrols.visible = claimed
	_select_garrison.visible = claimed
	if claimed:
		var f := g.faction_def
		_owner.text = PlanetClaims.owner_name(g)
		_owner.add_theme_color_override("font_color", f.color.lerp(Color.WHITE, 0.3))
		_owner.tooltip_text = "Claimed by %s since %s. A garrison holds it from orbit: no outpost can be founded here until it is destroyed." % [PlanetClaims.owner_name(g), UIUtil.clock(g.claimed_at)]
		_garrison.text = g.strength_text()
		_garrison.tooltip_text = "%s: %d / %d hull, %d / %d shields, four flak turrets (%d dps at %d m)" % [g.get_display_name(), roundi(g.durability.hull), roundi(g.durability.max_hull),
				roundi(g.durability.shields), roundi(g.durability.max_shields), roundi(f.garrison_gun_dps()), roundi(f.garrison_turret_range)]
		_patrols.text = "%d of %d out, guarding %.1f km" % [g.patrols_out(), g.def.spawn_cap, g.guard_radius / 1000.0]
		_patrols.tooltip_text = "Patrol ships attack any of your ships within %.1f km of the planet's centre." % (g.guard_radius / 1000.0)
		_claim_note.text = "Claimed: no outpost here while the garrison stands. Post a bounty on the garrison to break the claim; the faction will try to re-claim it later."
		_claim_note.visible = true
		return
	_owner.text = OWNER_TEXT
	_owner.remove_theme_color_override("font_color")
	_owner.tooltip_text = "No faction holds this world. Factions claim planets with an orbital garrison; a claimed world takes no outpost."
	var line := pc.reclaim_text(planet) if pc else ""
	_claim_note.text = ("Re-claim: %s. Defence zones and mercenaries near the planet can stop the constructor." % line) if not line.is_empty() else ""
	_claim_note.visible = not line.is_empty()


func _on_select_garrison() -> void:
	var pc := PlanetClaims.of(self)
	var g := pc.garrison_of(planet) if pc and planet else null
	if g and hud and hud.selection:
		hud.selection.select(g)


static func _loot_use(loot: int) -> String:
	match loot:
		Economy.Ore.FUEL:
			return "Fuel: the Factory needs it for Mk III drives. Sells well."
		Economy.Ore.WATER:
			return "Water: every forward station uses 2 a minute. Sell the rest to the Factory."
		Economy.Ore.RARE_METALS:
			return "Rare metals: every Mk III module needs them. The best price per unit."
		Economy.Ore.SILICATES:
			return "Silicates: Mk III shields need them, and the Factory refines them into crystal."
		Economy.Ore.HEAVY_ORE:
			return "Heavy ore: the Factory refines it into iron and titanium, or buys it."
	return ""


## The outpost section: the state of this world's outpost, or why one cannot be founded.
func _refresh_outpost() -> void:
	if planet == null or not is_instance_valid(planet):
		return
	var outs := Outposts.of(get_tree())
	if outs == null:
		return
	var o := outs.outpost_of(planet)
	if o != null:
		var hs := o.crew_of(OutpostState.HARVESTER).size()
		var ss := o.crew_of(OutpostState.SOLDIER).size()
		if not o.is_founded():
			_outpost_text.text = "The lander is on its way down: founded in %d s." % maxi(roundi(OutpostState.FOUND_TIME - (SimClock.time - o.ordered_at)), 0)
			_outpost_button.text = "Lander descending"
			_outpost_button.disabled = true
		else:
			_outpost_text.text = "%d buildings, %d harvester%s, %d soldier%s. %d %s at the pad, %d delivered. Upkeep %d cr a minute%s." % [o.buildings.size(), hs, "" if hs == 1 else "s", ss,
					"" if ss == 1 else "s", o.stock[o.good], o.good_name(), o.delivered[o.good], roundi(OutpostState.UPKEEP), ", %d cr owed" % o.upkeep_owed if o.upkeep_owed > 0 else ""]
			_outpost_button.text = "Go to surface"
			_outpost_button.disabled = false
			_outpost_button.tooltip_text = "Planet mode: build, hire harvesters and soldiers, post harvest contracts (double-click the planet too)"
		return
	var why := outs.found_problem(planet)
	_outpost_text.text = "Found an outpost: %s cr + %d iron + %d titanium. A lander flies down from the station (%d s); then build a Harvester Bay, hire harvesters and post harvest contracts on the deposits. Upkeep %d cr a minute." % [
			Fmt.amount(OutpostState.FOUND_CREDITS), OutpostState.FOUND_IRON, OutpostState.FOUND_TITANIUM, roundi(OutpostState.FOUND_TIME), roundi(OutpostState.UPKEEP)]
	if not why.is_empty():
		_outpost_text.text += " " + why + "."
	_outpost_button.text = "Found outpost"
	_outpost_button.disabled = not why.is_empty()
	_outpost_button.tooltip_text = why


func _on_outpost() -> void:
	var outs := Outposts.of(get_tree())
	if outs == null or planet == null:
		return
	var o := outs.outpost_of(planet)
	if o == null:
		outs.found(planet)
	elif o.is_founded():
		SurfaceMode.enter(get_tree(), o)
	_refresh_outpost()

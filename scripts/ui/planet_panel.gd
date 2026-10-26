class_name PlanetPanel
extends PanelContainer
## Bottom-right panel for the selected planet or moon (phase C2): type, the
## loot a raid brings back and its base yield (with what the Factory pays
## for one load now), danger, distance from home, owner (a faction claim of
## C3 in its colour, or "Unclaimed"), the claim's garrison strength and
## patrols with a button that selects the garrison (to post a bounty), a
## pending re-claim, the raids so far, the planet raid contracts posted on
## it (with cancel) and the "Post planet raid" form: pay per load and a load
## limit. Room is left for C4 (depletion, defences).

const OWNER_TEXT := "Unclaimed"

@export var panel_width: float = 380.0

var hud: HUD
var planet: PlanetBody

var _kind: Label
var _title: Label
var _type: Label
var _loot: Label
var _yield: Label
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
var _raids: Label
var _contracts_header: Label
var _contracts: VBoxContainer
var _form: PostContractForm
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
	_loot = _grid_row(grid, "Loot")
	_yield = _grid_row(grid, "Base yield")
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
	_raids = _grid_row(grid, "Raids so far")
	_claim_note = UIUtil.label("", &"DimLabel")
	_claim_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_claim_note.custom_minimum_size.x = panel_width - 24.0
	v.add_child(_claim_note)
	_select_garrison = UIUtil.button("Select garrison", &"")
	_select_garrison.tooltip_text = "Select the garrison to post a bounty on it. Mercenaries take it on as a fleet."
	_select_garrison.pressed.connect(_on_select_garrison)
	v.add_child(_select_garrison)

	v.add_child(HSeparator.new())
	_contracts_header = UIUtil.label("CONTRACTS", &"HeaderLabel")
	v.add_child(_contracts_header)
	_contracts = VBoxContainer.new()
	_contracts.add_theme_constant_override("separation", 1)
	v.add_child(_contracts)

	v.add_child(HSeparator.new())
	_form = PostContractForm.new("POST PLANET RAID", "Post planet raid", PlanetRaidContract.rules(), panel_width)
	_form.changed.connect(_refresh_form)
	_form.post_pressed.connect(_on_post)
	v.add_child(_form)


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
	ContractBoard.contract_posted.connect(func(_c: Contract) -> void: _rebuild_contracts())
	ContractBoard.contract_changed.connect(func(_c: Contract) -> void: _rebuild_contracts())
	ContractBoard.contract_removed.connect(func(_c: Contract) -> void: _rebuild_contracts())
	ContractBoard.delivery_made.connect(func(c: Contract, _s: Node, _cr: int, _m: int, _o: int) -> void:
		if c is PlanetRaidContract and (c as PlanetRaidContract).planet == planet:
			_refresh_info())


func is_moon(b: PlanetBody) -> bool:
	return b != null and b.get_parent() is PlanetBody


func show_planet(b: PlanetBody) -> void:
	var changed := b != planet
	planet = b
	visible = b != null
	if b == null:
		return
	if changed:
		_form.reward = fair_reward()
		_form.load_limit_index = 0
	_kind.text = "MOON" if is_moon(b) else "PLANET"
	_title.text = b.def.name if not is_moon(b) else "%s, moon of %s" % [b.def.name, (b.get_parent() as PlanetBody).def.name]
	_refresh_info()
	_rebuild_contracts()
	_refresh_form()


func fair_reward() -> int:
	if planet == null:
		return PlanetRaidContract.rules().reward_min
	return PlanetRaidContract.rules().fair_reward(planet.def, PlanetRaidContract.danger_for(planet))


func get_post_button() -> Button:
	return _form.post


func set_reward(value: int) -> void:
	_form.set_reward(value)


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 0.5
		_refresh_info()
		for c in _contracts.get_children():
			if c is ContractRow:
				(c as ContractRow).refresh()


func _refresh_info() -> void:
	if planet == null or not is_instance_valid(planet):
		return
	var rules := PlanetRaidContract.rules()
	var d := planet.def
	var names := OverviewPanel.MOON_TYPES if is_moon(planet) else OverviewPanel.PLANET_TYPES
	_type.text = names[clampi(d.type, 0, names.size() - 1)]
	var loot := rules.loot_of(d)
	_loot.text = Economy.ORE_NAMES[loot]
	_loot.add_theme_color_override("font_color", Economy.ORE_COLORS[loot].lerp(Color.WHITE, 0.35))
	_loot.tooltip_text = _loot_use(loot)
	var units := rules.base_yield(d)
	var f := Factory.find(self)
	var worth := " (~%s cr)" % UIUtil.amount(roundi(float(units) * f.market.willing_price(loot))) if f else ""
	_yield.text = "%d %s a load%s" % [units, Economy.ore_name(loot), worth]
	_yield.tooltip_text = "Per dropship load before cargo upgrades: %d by type, x%.2f for its size, x%.2f richness." % [
			rules.units_per_load[d.type], rules.size_factor(d), rules.richness_of(d)]
	var danger := PlanetRaidContract.danger_for(planet)
	_danger.value = float(danger)
	var claimed := not PlanetClaims.claim_reason(planet).is_empty()
	_danger_text.text = "%d of 5%s" % [danger, ", garrison in orbit" if claimed else (", no planet defences yet" if danger <= 2 else ", raiders about on the way")]
	_refresh_claim()
	var rec := PlanetRaidContract.record_of(planet)
	if rec.is_empty():
		_raids.text = "None yet"
	else:
		_raids.text = "%d load%s, %s %s" % [int(rec["raids"]), "" if int(rec["raids"]) == 1 else "s", UIUtil.amount(int(rec["units"])), Economy.ore_name(loot)]
		_raids.tooltip_text = "Last raid at %s, %s cr paid in total" % [UIUtil.clock(float(rec.get("last", 0.0))), UIUtil.amount(int(rec.get("credits", 0)))]
	if hud and hud.solar_system and is_instance_valid(hud.solar_system.home_station):
		var km := SpaceNav.flat_distance(planet.global_position, hud.solar_system.home_station.global_position) / 1000.0
		var t := SpaceNav.travel_estimate(km * 1000.0, 140.0)
		_distance.text = "%.1f km  (%s by dropship)" % [km, SpaceNav.travel_text(t)]
	else:
		_distance.text = "-"


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
		_owner.tooltip_text = "Claimed by %s since %s. A garrison holds it from orbit: landers refuse planet raids here until it is destroyed." % [PlanetClaims.owner_name(g), UIUtil.clock(g.claimed_at)]
		_garrison.text = g.strength_text()
		_garrison.tooltip_text = "%s: %d / %d hull, %d / %d shields, four flak turrets (%d dps at %d m)" % [g.get_display_name(), roundi(g.durability.hull), roundi(g.durability.max_hull),
				roundi(g.durability.shields), roundi(g.durability.max_shields), roundi(f.garrison_gun_dps()), roundi(f.garrison_turret_range)]
		_patrols.text = "%d of %d out, guarding %.1f km" % [g.patrols_out(), g.def.spawn_cap, g.guard_radius / 1000.0]
		_patrols.tooltip_text = "Patrol ships attack any of your ships within %.1f km of the planet's centre." % (g.guard_radius / 1000.0)
		_claim_note.text = "Claimed: landers refuse raids here. Post a bounty on the garrison to break the claim; the faction will try to re-claim it later."
		_claim_note.visible = true
		return
	_owner.text = OWNER_TEXT
	_owner.remove_theme_color_override("font_color")
	_owner.tooltip_text = "No faction holds this world. Factions claim planets with an orbital garrison; landers will not raid a claimed world."
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
			return "Water: kept for a future colony. Sell it to the Factory for now."
		Economy.Ore.RARE_METALS:
			return "Rare metals: every Mk III module needs them. The best price per unit."
		Economy.Ore.SILICATES:
			return "Silicates: Mk III shields need them, and the Factory refines them into crystal."
		Economy.Ore.HEAVY_ORE:
			return "Heavy ore: the Factory refines it into iron and titanium, or buys it."
	return ""


func _rebuild_contracts() -> void:
	if planet == null:
		return
	for c in _contracts.get_children():
		_contracts.remove_child(c)
		c.queue_free()
	var list := ContractBoard.get_for_target(planet)
	_contracts_header.text = "CONTRACTS  %d" % list.size()
	if list.is_empty():
		_contracts.add_child(UIUtil.label("None posted. Landers only raid worlds with a contract.", &"DimLabel"))
		return
	for c in list:
		_contracts.add_child(ContractRow.new(c, hud, false))


func _dock_problem() -> String:
	var mgr := BuildingManager.of(self)
	var def := mgr.def_by_id(&"raider_dock") if mgr else null
	if def == null or mgr.count_of(def) == 0:
		if not Research.is_building_unlocked(&"raider_dock"):
			return "No landers yet: research Planetary assault doctrine, then build a Raider Dock and hire landers."
		return "No landers yet: build a Raider Dock and hire landers there."
	for b in mgr.buildings:
		if is_instance_valid(b) and b.def == def and not b.ships.is_empty():
			return ""
	return "No landers yet: hire some at the Raider Dock."


func _refresh_form() -> void:
	if planet == null:
		return
	var reward := _form.reward
	_form.refresh()
	var fair := fair_reward()
	_form.fair.text = "Fair pay here is about %d cr (%s). Greedy pilots like rich worlds, cautious ones stay away from danger." % [fair, PostContractForm.fair_verdict(reward, fair)]
	var dock := _dock_problem()
	if not dock.is_empty():
		_form.hint.text += " " + dock
	var claim := PlanetClaims.claim_reason(planet)
	if not claim.is_empty():
		_form.hint.text += " %s: landers refuse until the claim is broken." % claim
	_form.set_problem(ContractBoard.post_problem(reward))


func _on_post() -> void:
	if planet == null:
		return
	ContractBoard.post_planet_raid(planet, _form.reward, _form.load_limit())

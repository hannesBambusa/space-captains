class_name CaptainPanel
extends PanelContainer
## Bottom-right panel for the selected player ship: captain name, role and
## personality, hull and shield bars, live status with a progress bar
## (drilling / hold / repairs), current contract, home, career stats, the six
## attributes (pips), the loadout and the last decision (refusal reason).
## Miners also get the "Request escort" form (pay per trip, max escorts) and
## the escort contracts already on them.
## Stage 3: rank with a progress bar to the next one, traits (tooltip each,
## fading ones with time left), wallet, modules by slot with tier and the
## free slots, the career history, and "Offer transfer" buttons (the
## captain decides; the answer shows below them).
## Fleets: the fleet the merc flies in and its role (leader or wingman), or
## a solo run. Repairs: the bill for the missing hull, and whether the wallet
## covers it (RepairBay). Teamwork is the seventh attribute.
## Tabs: "Details" (all of the above, with the latest decision under the
## status) and "Log" (CaptainLogView: every decision and why). The Log tab
## takes the height the Details tab had, so the panel keeps its size.
## An open Factory buy order shows as one line under the wallet: the part,
## the deposit and its state ("waiting for titanium", "ready for pickup").

const ATTR_COLOR := Color(0.55, 0.85, 1.0)
const HULL_COLOR := Color(0.45, 0.95, 0.55)
const SHIELD_COLOR := Color(0.45, 0.75, 1.0)
const TIER_COLORS: Array[Color] = [HudStyle.TEXT_DIM, Color(0.75, 0.9, 1.0), Color(0.6, 1.0, 0.68), Color(1.0, 0.82, 0.35)]
const GOOD_TRAIT := Color(0.6, 1.0, 0.7)
const BAD_TRAIT := Color(1.0, 0.68, 0.4)
## Career lines shown (the tooltip has them all).
const HISTORY_LINES := 2

@export var panel_width: float = 380.0
## Escort pay stepper: range and step, credits per trip.
@export var escort_pay_min: int = 10
@export var escort_pay_max: int = 200
@export var escort_pay_step: int = 5
@export var escort_pay_default: int = 35

var hud: HUD
var ship: Ship
var escort_pay: int = 35
var escort_max: int = 2

var _title: Label
var _role: Label
var _hint: Label
var _hull: PipMeter
var _hull_text: Label
var _shield: PipMeter
var _shield_text: Label
var _status: Label
var _progress: ProgressBar
var _contract: Label
var _home: Label
var _loads_title: Label
var _loads: Label
var _earned: Label
var _spent: Label
var _attr_pips: Array[PipMeter] = []
var _attr_values: Array[Label] = []
var _attr_names: Array[Label] = []
var _decision: Label
var _escort_box: VBoxContainer
var _escort_list: VBoxContainer
var _pay_value: Label
var _max_value: Label
var _request: Button
var _refresh_timer := 0.0
var _rank: Label
var _rank_bar: PipMeter
var _rank_text: Label
var _traits: HFlowContainer
var _traits_key := ""
var _wallet: Label
var _order: Label
var _order_title: Label
var _fleet: Label
var _fleet_title: Label
var _repairs: Label
var _modules_box: VBoxContainer
var _modules_header: Label
## Why nothing is being bought (Outfitter.shop_status), hidden when empty.
var _modules_status: Label
var _module_names: Array[Label] = []
var _module_tiers: Array[Label] = []
var _career_box: VBoxContainer
var _history: Label
var _transfer_row: HBoxContainer
var _transfer_buttons: Dictionary = {}
var _transfer_answer: Label
var _loadout_key := ""
var _details: VBoxContainer
var _log_view: CaptainLogView
var _tab_buttons: Array[Button] = []
## 0 = Details, 1 = Log.
var _tab: int = 0
var _details_height: float = 0.0


func _ready() -> void:
	custom_minimum_size.x = panel_width
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	top.add_child(UIUtil.label("CAPTAIN", &"HeaderLabel"))
	top.add_child(UIUtil.spacer(6.0))
	var tabs := ButtonGroup.new()
	for i in 2:
		var tb := UIUtil.button("Details" if i == 0 else "Log", &"IconButton")
		tb.toggle_mode = true
		tb.button_group = tabs
		tb.button_pressed = i == 0
		tb.custom_minimum_size = Vector2(70.0, 22.0)
		tb.tooltip_text = "Captain details" if i == 0 else "Every decision this captain made, and why"
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
	_title = UIUtil.label("", &"TitleLabel")
	v.add_child(_title)
	_role = UIUtil.label("", &"ValueLabel")
	v.add_child(_role)
	var root := v
	_log_view = CaptainLogView.new()
	_log_view.row_width = panel_width - 40.0
	_log_view.visible = false
	_details = VBoxContainer.new()
	_details.add_theme_constant_override("separation", 5)
	root.add_child(_details)
	root.add_child(_log_view)
	v = _details
	_hint = UIUtil.label("", &"DimLabel")
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = panel_width - 24.0
	v.add_child(_hint)
	var rr := HBoxContainer.new()
	rr.add_theme_constant_override("separation", 10)
	v.add_child(rr)
	_rank = UIUtil.label("", &"ValueLabel")
	_rank.custom_minimum_size.x = 80.0
	_rank.mouse_filter = Control.MOUSE_FILTER_PASS
	rr.add_child(_rank)
	_rank_bar = PipMeter.new()
	_rank_bar.style = PipMeter.Style.BAR
	_rank_bar.max_value = 1.0
	_rank_bar.custom_minimum_size = Vector2(150.0, 6.0)
	_rank_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rank_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rr.add_child(_rank_bar)
	_rank_text = UIUtil.label("", &"DimLabel")
	_rank_text.custom_minimum_size.x = 96.0
	_rank_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rr.add_child(_rank_text)
	_traits = HFlowContainer.new()
	_traits.add_theme_constant_override("h_separation", 6)
	_traits.add_theme_constant_override("v_separation", 2)
	v.add_child(_traits)

	var bars := GridContainer.new()
	bars.columns = 3
	bars.add_theme_constant_override("h_separation", 10)
	bars.add_theme_constant_override("v_separation", 3)
	v.add_child(bars)
	var hb := UIUtil.bar_row(bars, "Hull", HULL_COLOR, 80.0, Vector2(170.0, 6.0))
	_hull = hb[0]
	_hull_text = hb[1]
	var sb := UIUtil.bar_row(bars, "Shields", SHIELD_COLOR, 80.0, Vector2(170.0, 6.0))
	_shield = sb[0]
	_shield_text = sb[1]

	v.add_child(HSeparator.new())
	var sh := HBoxContainer.new()
	v.add_child(sh)
	_status = UIUtil.label("", &"ValueLabel")
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.custom_minimum_size.x = 210.0
	sh.add_child(_status)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.max_value = 1.0
	_progress.custom_minimum_size = Vector2(90.0, 6.0)
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sh.add_child(_progress)
	_decision = UIUtil.label("", &"DimLabel")
	_decision.clip_text = true
	_decision.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_decision.custom_minimum_size.x = panel_width - 24.0
	_decision.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(_decision)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 3)
	v.add_child(grid)
	_contract = _add_stat(grid, "Contract")
	_home = _add_stat(grid, "Home")
	_loads = _add_stat(grid, "Loads delivered")
	_loads_title = grid.get_child(grid.get_child_count() - 2) as Label
	_earned = _add_stat(grid, "Credits earned")
	_spent = _add_stat(grid, "Spent at station")
	_wallet = _add_stat(grid, "Wallet")
	_order = _add_stat(grid, "Order")
	_order_title = grid.get_child(grid.get_child_count() - 2) as Label
	_repairs = _add_stat(grid, "Repairs")
	_fleet = _add_stat(grid, "Fleet")
	_fleet_title = grid.get_child(grid.get_child_count() - 2) as Label

	v.add_child(HSeparator.new())
	v.add_child(UIUtil.label("ATTRIBUTES", &"HeaderLabel"))
	var ag := GridContainer.new()
	ag.columns = 3
	ag.add_theme_constant_override("h_separation", 10)
	ag.add_theme_constant_override("v_separation", 2)
	v.add_child(ag)
	for i in Captain.ATTRIBUTE_NAMES.size():
		var n := UIUtil.label(Captain.ATTRIBUTE_NAMES[i], &"DimLabel")
		n.custom_minimum_size.x = 80.0
		n.mouse_filter = Control.MOUSE_FILTER_PASS
		n.tooltip_text = Captain.ATTRIBUTE_HINTS[i]
		ag.add_child(n)
		_attr_names.append(n)
		var pips := PipMeter.new()
		pips.style = PipMeter.Style.PIPS
		pips.max_value = 10.0
		pips.pip_size = 7.0
		pips.pip_gap = 3.0
		pips.color = ATTR_COLOR
		ag.add_child(pips)
		_attr_pips.append(pips)
		var val := UIUtil.label("", &"ValueLabel")
		val.custom_minimum_size.x = 22.0
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		ag.add_child(val)
		_attr_values.append(val)
	_modules_box = VBoxContainer.new()
	_modules_box.add_theme_constant_override("separation", 5)
	v.add_child(_modules_box)
	_modules_box.add_child(HSeparator.new())
	var mh := HBoxContainer.new()
	_modules_box.add_child(mh)
	mh.add_child(UIUtil.label("MODULES", &"HeaderLabel"))
	mh.add_child(UIUtil.spacer())
	_modules_header = UIUtil.label("", &"DimLabel")
	_modules_header.mouse_filter = Control.MOUSE_FILTER_PASS
	mh.add_child(_modules_header)
	_modules_status = UIUtil.label("", &"DimLabel")
	_modules_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_modules_status.custom_minimum_size.x = panel_width - 24.0
	_modules_status.visible = false
	_modules_box.add_child(_modules_status)
	var mg := GridContainer.new()
	mg.columns = 3
	mg.add_theme_constant_override("h_separation", 10)
	mg.add_theme_constant_override("v_separation", 1)
	_modules_box.add_child(mg)
	for i in ShipModule.SLOT_NAMES.size():
		var sl := UIUtil.label(ShipModule.SLOT_NAMES[i], &"DimLabel")
		sl.custom_minimum_size.x = 64.0
		mg.add_child(sl)
		var mn := UIUtil.label("", &"ValueLabel")
		mn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mn.clip_text = true
		mn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		mn.mouse_filter = Control.MOUSE_FILTER_PASS
		mg.add_child(mn)
		_module_names.append(mn)
		var mt := UIUtil.label("", &"DimLabel")
		mt.custom_minimum_size.x = 48.0
		mt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		mg.add_child(mt)
		_module_tiers.append(mt)

	_career_box = VBoxContainer.new()
	_career_box.add_theme_constant_override("separation", 3)
	v.add_child(_career_box)
	_career_box.add_child(HSeparator.new())
	_career_box.add_child(UIUtil.label("CAREER", &"HeaderLabel"))
	_history = UIUtil.label("", &"DimLabel")
	_history.mouse_filter = Control.MOUSE_FILTER_PASS
	_history.clip_text = true
	_history.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_history.custom_minimum_size.x = panel_width - 24.0
	_career_box.add_child(_history)
	_transfer_row = HBoxContainer.new()
	_transfer_row.add_theme_constant_override("separation", 6)
	_career_box.add_child(_transfer_row)
	_transfer_row.add_child(UIUtil.label("Offer transfer", &"DimLabel"))
	_transfer_row.add_child(UIUtil.spacer())
	for role in ["Mercenary", "Salvager"]:
		var tb := UIUtil.button(role)
		tb.custom_minimum_size = Vector2(96.0, 24.0)
		tb.pressed.connect(_on_offer.bind(role))
		_transfer_row.add_child(tb)
		_transfer_buttons[role] = tb
	_transfer_answer = UIUtil.label("", &"WarnLabel")
	_transfer_answer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_transfer_answer.custom_minimum_size.x = panel_width - 24.0
	_transfer_answer.visible = false
	_career_box.add_child(_transfer_answer)

	_escort_box = VBoxContainer.new()
	_escort_box.add_theme_constant_override("separation", 4)
	v.add_child(_escort_box)
	_escort_box.add_child(HSeparator.new())
	_escort_box.add_child(UIUtil.label("REQUEST ESCORT", &"HeaderLabel"))
	_escort_list = VBoxContainer.new()
	_escort_list.add_theme_constant_override("separation", 1)
	_escort_box.add_child(_escort_list)
	var pr: Label = UIUtil.stepper_row(_escort_box, "Pay per trip", _step_pay)[0]
	_pay_value = pr
	var mr: Label = UIUtil.stepper_row(_escort_box, "Max escorts", _step_max)[0]
	_max_value = mr
	Economy.changed.connect(func(_c: int, _m: int) -> void:
		if is_visible_in_tree():
			_refresh_form())
	_request = UIUtil.button("Request escort", &"AccentButton")
	_request.pressed.connect(_on_request)
	_escort_box.add_child(_request)


func setup(owner_hud: HUD) -> void:
	hud = owner_hud
	if hud.selection:
		hud.selection.selection_changed.connect(func(t: Node3D) -> void:
			var s := t as Ship
			show_ship(s if s and not s.is_hostile() and not (s is CargoShuttle) and not (s is MobileStation) else null))
	ContractBoard.contract_posted.connect(func(_c: Contract) -> void: _rebuild_escorts())
	ContractBoard.contract_removed.connect(func(_c: Contract) -> void: _rebuild_escorts())


func show_ship(s: Ship) -> void:
	var changed := s != ship
	ship = s
	visible = s != null
	if s == null:
		return
	if changed:
		escort_pay = escort_pay_default
		escort_max = 2
		_transfer_answer.visible = false
		_traits_key = "-"
		_loadout_key = "-"
	var cap := s.captain
	_title.text = cap.captain_name if cap else s.get_display_name()
	if cap:
		_role.text = "%s  ·  %s  ·  %s" % [cap.role, cap.get_personality_name(), cap.get_specialty_name()]
		_role.add_theme_color_override("font_color", BuildingPanel.PERSONALITY_COLORS[cap.personality])
		_hint.text = cap.get_personality_hint()
		var vals := cap.get_attributes()
		for i in vals.size():
			_attr_pips[i].value = float(vals[i])
			_attr_values[i].text = str(vals[i])
		_attr_names[4].text = cap.get_specialty_name()
	_modules_box.visible = not (s is EscapePod)
	_refresh_modules()
	_loads_title.text = ("Salvage loads" if s is SalvagerShip else ("Raid loads" if s is LanderShip else "Loads delivered")) if s is MinerShip else ("Surveys / finds" if s is ExplorerShip else "Kills / escorts")
	_escort_box.visible = s is MinerShip
	_log_view.show_captain(cap)
	_rebuild_escorts()
	_refresh_form()
	_refresh()


func get_request_button() -> Button:
	return _request


## 0 = Details, 1 = Log. The Log tab keeps the Details tab's height.
func set_tab(index: int) -> void:
	if _tab == 0 and _details.visible and _details.size.y > 0.0:
		_details_height = _details.size.y
	_tab = index
	_tab_buttons[index].set_pressed_no_signal(true)
	_tab_buttons[1 - index].set_pressed_no_signal(false)
	_details.visible = index == 0
	_log_view.visible = index == 1
	_log_view.custom_minimum_size.y = maxf(_details_height, 320.0)
	if index == 0:
		_refresh()


func get_tab() -> int:
	return _tab


func get_log_view() -> CaptainLogView:
	return _log_view


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 0.2
		_refresh()


func _refresh() -> void:
	if not is_instance_valid(ship) or ship.dead or _tab != 0:
		return
	var brain := ship.brain
	_status.text = ship.get_status_text()
	_hull.value = ship.hull_fraction()
	_hull.color = HULL_COLOR if ship.hull_fraction() > 0.5 else (PipMeter.MID if ship.hull_fraction() > 0.25 else PipMeter.BAD)
	_hull_text.text = "%d / %d" % [roundi(ship.durability.hull), roundi(ship.durability.max_hull)]
	_shield.value = ship.shield_fraction()
	_shield_text.text = "%d / %d" % [roundi(ship.durability.shields), roundi(ship.durability.max_shields)]
	var p := -1.0
	var miner := ship as MinerShip
	if brain and brain.trip and brain.state == CaptainBrain.State.MINING:
		p = brain.trip.progress
	elif brain and brain.state == CaptainBrain.State.REPAIRING:
		p = ship.hull_fraction()
	elif miner and miner.hold_fill > 0.0:
		p = miner.hold_fill
	_progress.visible = p >= 0.0
	_progress.value = maxf(p, 0.0)
	if brain and brain.trip and brain.trip.contract:
		var c := brain.trip.contract
		_contract.text = "%s, %s" % [c.get_target_name(), c.get_reward_text()]
	else:
		_contract.text = "None"
	_home.text = ship.home.display_name if is_instance_valid(ship.home) else "-"
	var cap := ship.captain
	if cap:
		if ship is SalvagerShip:
			_loads.text = str(cap.salvage_loads)
		elif ship is ExplorerShip:
			_loads.text = "%d / %d" % [cap.surveys, cap.discoveries]
		else:
			_loads.text = str(cap.loads_delivered) if ship is MinerShip else "%d / %d" % [cap.kills, cap.escorts_completed]
		_earned.text = "%s cr" % UIUtil.amount(cap.credits_earned)
		_spent.text = "%s cr" % UIUtil.amount(cap.credits_spent)
		_wallet.text = "%s cr" % UIUtil.amount(cap.wallet)
		_refresh_order(cap)
		_refresh_fleet_and_repairs(cap)
		_refresh_career(cap)
	_refresh_modules()
	_refresh_last(brain)


## "Last: refused Talon Reach mining, too dangerous for that pay" under the status.
func _refresh_last(brain: CaptainBrain) -> void:
	var e := ship.captain.flight_log.latest() if ship.captain else null
	var text := ""
	var refused := false
	if e:
		text = e.headline.replace(": ", ", ")
		text = text.left(1).to_lower() + text.substr(1)
		refused = e.outcome == CaptainLog.Outcome.REFUSED or e.outcome == CaptainLog.Outcome.FAILED
		_decision.tooltip_text = e.why
	elif brain and not brain.last_decision.is_empty():
		text = brain.last_decision.left(1).to_lower() + brain.last_decision.substr(1)
		_decision.tooltip_text = ""
	_decision.text = "Last: " + text
	_decision.visible = not text.is_empty()
	_decision.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45) if refused else HudStyle.TEXT_DIM)


# --- Escort request -------------------------------------------------------------

func _rebuild_escorts() -> void:
	if _escort_list == null:
		return
	for c in _escort_list.get_children():
		_escort_list.remove_child(c)
		c.queue_free()
	if not is_instance_valid(ship) or not (ship is MinerShip):
		return
	var list := ContractBoard.escorts_for_ship(ship)
	if list.is_empty():
		_escort_list.add_child(UIUtil.label("Mercenaries fly with this miner on every trip.", &"DimLabel"))
	for c in list:
		_escort_list.add_child(ContractRow.new(c, hud, false))


func _refresh_form() -> void:
	_pay_value.text = "%d cr" % escort_pay
	_max_value.text = str(escort_max)
	_request.tooltip_text = "Pays %d cr to each escort per completed trip, from your credits on delivery." % escort_pay
	var why := ContractBoard.post_problem(escort_pay)
	_request.disabled = not why.is_empty()
	if not why.is_empty():
		_request.tooltip_text = why


func _step_pay(dir: int) -> void:
	var step := escort_pay_step * (5 if Input.is_key_pressed(KEY_SHIFT) else 1)
	escort_pay = clampi(escort_pay + dir * step, escort_pay_min, escort_pay_max)
	_refresh_form()


func _step_max(dir: int) -> void:
	escort_max = clampi(escort_max + dir, 1, 4)
	_refresh_form()


func _on_request() -> void:
	if is_instance_valid(ship):
		ContractBoard.post_escort(ship, escort_pay, escort_max)


# --- Builders -------------------------------------------------------------------



## "Ore Hold Mk II, paid 400 cr, waiting for titanium"; hidden without an order.
func _refresh_order(cap: Captain) -> void:
	var f := Factory.find(self)
	var o := f.order_of(cap) if f else {}
	_order.visible = not o.is_empty()
	_order_title.visible = not o.is_empty()
	if o.is_empty():
		return
	var state := f.order_state(o)
	_order.text = "%s, paid %s cr, %s" % [(o["module"] as ShipModule).display_name, UIUtil.amount(int(o.get("paid", 0))), f.order_state_text(o)]
	_order.add_theme_color_override("font_color", PipMeter.GOOD if state == "ready" else (PipMeter.MID if state == "ore" or state == "tooling" else HudStyle.TEXT_BRIGHT))


func _refresh_fleet_and_repairs(cap: Captain) -> void:
	var bill := RepairBay.cost_to_repair(ship)
	if ship.repairing:
		_repairs.text = "Repairing, %d cr to go" % bill
		_repairs.add_theme_color_override("font_color", PipMeter.MID)
	elif bill <= 0:
		_repairs.text = "Hull fine"
		_repairs.remove_theme_color_override("font_color")
	else:
		var short := cap.wallet < bill
		_repairs.text = "Needs repairs, %d cr%s" % [bill, " (wallet short)" if short else ""]
		_repairs.add_theme_color_override("font_color", PipMeter.BAD if short else PipMeter.MID)
	var mb := ship.brain as MercenaryBrain
	_fleet.visible = mb != null
	_fleet_title.visible = mb != null
	if mb == null:
		return
	if mb.fleet:
		var f := mb.fleet
		_fleet.text = "%s's fleet (%d), %s, %s" % [f.leader_name, f.members.size(), f.role_of(ship), MercFleet.STATE_NAMES[f.state]]
	elif mb.solo_brave:
		_fleet.text = "Alone, above their weight"
	else:
		_fleet.text = "None (Teamwork %d)" % cap.effective_teamwork()


func _add_stat(grid: GridContainer, title: String) -> Label:
	grid.add_child(UIUtil.label(title, &"DimLabel"))
	var l := UIUtil.label("", &"ValueLabel")
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.custom_minimum_size.x = 200.0
	grid.add_child(l)
	return l


# --- Career, traits, modules ----------------------------------------------------

func _refresh_career(cap: Captain) -> void:
	_rank.text = cap.get_rank_name()
	_rank.add_theme_color_override("font_color", Reputation.RANK_COLORS[cap.rank])
	_rank.tooltip_text = "Rank %s: %d module slots, up to %s modules. Earned with deeds, not levels." % [cap.get_rank_name(), Reputation.slots_for(cap.rank), ShipModule.TIER_NAMES[Reputation.max_tier_for(cap.rank)]]
	_rank_bar.value = Reputation.progress(cap.reputation)
	_rank_bar.color = Reputation.RANK_COLORS[mini(cap.rank + 1, Reputation.RANK_COLORS.size() - 1)]
	var nxt := Reputation.next_threshold(cap.rank)
	_rank_text.text = "%d rep" % roundi(cap.reputation) if is_inf(nxt) else "%d / %d rep" % [roundi(cap.reputation), roundi(nxt)]
	var key := ""
	for t in cap.traits:
		key += "%s:%d," % [t["id"], int(cap.trait_time_left(t["id"]) / 10.0)]
	if key != _traits_key:
		_traits_key = key
		_rebuild_traits(cap)
	var lines := cap.history.slice(maxi(cap.history.size() - HISTORY_LINES, 0))
	_history.text = "\n".join(lines) if not lines.is_empty() else "No career moves yet."
	_history.tooltip_text = "\n".join(cap.history)
	var targets := Career.targets_for(cap) if ship.brain else PackedStringArray()
	_career_box.visible = true
	_transfer_row.visible = not targets.is_empty()
	for role: String in _transfer_buttons:
		var tb := _transfer_buttons[role] as Button
		tb.visible = targets.has(role)
		if tb.visible:
			var why := Career.block_reason(ship, role, true)
			tb.tooltip_text = "Suggest a move to %s work. The captain decides.%s" % [role.to_lower(), "" if why.is_empty() else "\nLikely answer: " + why]


func _rebuild_traits(cap: Captain) -> void:
	for c in _traits.get_children():
		_traits.remove_child(c)
		c.queue_free()
	if cap.traits.is_empty():
		_traits.add_child(UIUtil.label("No traits yet", &"DimLabel"))
		return
	for t in cap.traits:
		var id := t["id"] as StringName
		if _traits.get_child_count() > 0:
			_traits.add_child(UIUtil.label("·", &"DimLabel"))
		var text := CaptainTraits.trait_name(id)
		var left := cap.trait_time_left(id)
		if not is_inf(left):
			text += " %s" % UIUtil.clock(left)
		var l := UIUtil.label(text, &"ValueLabel")
		l.add_theme_color_override("font_color", GOOD_TRAIT if CaptainTraits.is_good(id) else BAD_TRAIT)
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		l.tooltip_text = CaptainTraits.tip(id) + ("" if is_inf(left) else " Fades in %s." % UIUtil.clock(left))
		_traits.add_child(l)


func _refresh_modules() -> void:
	if not is_instance_valid(ship) or ship.loadout == null:
		return
	var l := ship.loadout
	var status := Outfitter.shop_status(ship)
	var key := "%d:%s:" % [l.unlocked_slots, status]
	for m in l.modules():
		key += String(m.id) + ","
	if key == _loadout_key:
		return
	_loadout_key = key
	_modules_header.text = "%d / %d slots fitted" % [l.upgrades_fitted(), l.unlocked_slots]
	_modules_header.tooltip_text = _loadout_tooltip(ship)
	_modules_status.text = status
	_modules_status.visible = not status.is_empty()
	for i in ShipModule.SLOT_NAMES.size():
		var m := l.get_module(i as ShipModule.Slot)
		var n := _module_names[i]
		var t := _module_tiers[i]
		n.text = m.display_name if m else "empty"
		n.tooltip_text = (ModuleTips.tip(m) if m.tier > 0 else (m.blurb if not m.blurb.is_empty() else "Stock fitting of this hull.")) if m else ""
		n.add_theme_color_override("font_color", HudStyle.TEXT_BRIGHT if m and m.tier > 0 else HudStyle.TEXT_DIM)
		var tier := m.tier if m else 0
		t.text = ShipModule.TIER_NAMES[tier]
		t.add_theme_color_override("font_color", TIER_COLORS[tier])


func _on_offer(role: String) -> void:
	if not is_instance_valid(ship) or ship.dead:
		return
	var cap := ship.captain
	var why := Career.offer(ship, role)
	_transfer_answer.visible = true
	if why.is_empty():
		_transfer_answer.text = "%s accepted: now a %s." % [cap.captain_name, role.to_lower()]
		_transfer_answer.add_theme_color_override("font_color", PipMeter.GOOD)
		if is_instance_valid(cap.ship) and hud and hud.selection:
			hud.selection.select(cap.ship)
	else:
		_transfer_answer.text = "%s declined: %s." % [cap.captain_name, why.to_lower()]
		_transfer_answer.remove_theme_color_override("font_color")


static func _loadout_tooltip(s: Ship) -> String:
	var st := s.stats
	if st == null:
		return ""
	var lines: PackedStringArray = []
	for slot in ShipModule.Slot.values():
		var m := s.loadout.get_module(slot)
		lines.append("%s: %s" % [ShipModule.SLOT_NAMES[slot], m.display_name if m else "empty"])
	lines.append("")
	lines.append("Hull %d, shields %d (+%d/s)" % [roundi(st.max_hull), roundi(st.max_shields), roundi(st.shield_regen)])
	lines.append("Speed %d m/s, turn %d deg/s, dodge %d%%" % [roundi(st.max_speed), roundi(st.turn_rate_deg), roundi(st.dodge * 100.0)])
	if st.has_weapon():
		lines.append("Guns %.0f dmg x %.1f/s, range %d m, accuracy %d%%" % [st.weapon_damage, st.fire_rate, roundi(st.weapon_range), roundi(st.accuracy * 100.0)])
	else:
		lines.append("Drill time x%.2f" % st.drill_mult)
	return "\n".join(lines)

class_name PilotRoster
extends VBoxContainer
## PILOTS tab of the left panel: every hired captain still alive (captains
## waiting for a ship included) as a [PilotCard]. A summary line counts who
## is fighting, damaged, working and docked; role chips filter (All, Miners,
## Mercs, Salvagers: the roles hired so far) and the sort button cycles role,
## status, hull, wallet and rank. In role order the fleets come first: a
## [FleetRow] (target, state, mean hull) in the fleet's accent colour with
## its members indented under it on a tree line, leader first with a crown;
## escorts hang under the miner they cover. Cards and fleet rows are pooled
## and refreshed on a timer, never every frame; a new order moves the rows
## in place (open tooltips stay). Click: captain panel (fleet row: the
## target), right click: camera to the ship (the fleet), zoom kept.
## Every station's captains: home's first, then each forward station's
## (cards tagged "[Ostra]"); the sort works inside each system. A click on
## a card from another system switches the view there (HUD.focus).

signal count_changed(total: int, in_combat: int)

enum Sort { ROLE, STATUS, HULL, WALLET, RANK }

const SORT_NAMES: PackedStringArray = ["Role", "Status", "Hull", "Wallet", "Rank"]
const ROLE_ORDER: PackedStringArray = ["Miner", "Mercenary", "Salvager", "Lander", "Explorer"]
const H := preload("res://scripts/ui/theme/hud_style.gd")
## Fleet accents, handed out in turn (each fleet keeps its own).
const FLEET_COLORS: Array[Color] = [Color(1.0, 0.85, 0.42), Color(0.55, 0.9, 1.0), Color(0.95, 0.6, 1.0), Color(0.6, 1.0, 0.65)]

@export var refresh_interval: float = 0.25
@export var layout_interval: float = 1.0

var hud: HUD
## Two-row cards and a slimmer header (the right-hand list).
var compact := false
var filter_role := ""
var sort_mode: Sort = Sort.ROLE

var _summary: HBoxContainer
var _sum_labels: Dictionary = {}
var _chips: HBoxContainer
var _chip_buttons: Dictionary = {}
var _sort_button: Button
var _scroll: ScrollContainer
var _list: VBoxContainer
var _empty: Label
## Captain -> PilotCard.
var _cards: Dictionary = {}
## Fleet -> FleetRow (pooled).
var _fleet_heads: Dictionary = {}
## Fleet -> accent Color (kept for the fleet's life).
var _fleet_colors: Dictionary = {}
var _next_color := 0
var _refresh_left := 0.0
var _layout_left := 0.0
var _layout_key := ""


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_summary = HBoxContainer.new()
	_summary.add_theme_constant_override("separation", 12)
	_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_summary)
	_add_summary(&"combat", &"st_combat", H.BAD, "COMBAT", "In combat or under fire")
	_add_summary(&"damaged", &"hull", H.WARN, "DAMAGED", "Hull below 50%")
	_add_summary(&"working", &"st_travel", Color(0.7, 0.85, 1.0), "OUT", "Out working: flying, mining, patrolling, escorting, hunting")
	_add_summary(&"docked", &"st_docked", H.TEXT_DIM, "HOME", "Docked, resting or repairing at home, or waiting for a ship")

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	add_child(bar)
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 4)
	_chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_chips)
	_add_chip("", "ALL")
	for r in ROLE_ORDER:
		_add_chip(r, String(H.ROLE_SHORT.get(r, UIUtil.plural(r))).to_upper())
	_sort_button = UIUtil.button("", &"ChipButton")
	_sort_button.icon = H.icon(&"sort")
	_sort_button.custom_minimum_size.y = 18.0 if compact else 22.0
	if compact:
		_sort_button.add_theme_font_size_override("font_size", 11)
	_sort_button.tooltip_text = "Sort the pilots: role, status, hull, wallet, rank"
	_sort_button.pressed.connect(func() -> void:
		sort_mode = ((int(sort_mode) + 1) % SORT_NAMES.size()) as Sort
		_update_sort_label()
		_relayout(true))
	bar.add_child(_sort_button)
	_update_sort_label()

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.focus_mode = Control.FOCUS_NONE
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 0 if compact else 3)
	_scroll.add_child(_list)
	_empty = UIUtil.label("No pilots yet. Build a Mining or Mercenary Outpost and hire captains there.", &"DimLabel")
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(_empty)


func setup(owner_hud: HUD) -> void:
	hud = owner_hud
	if hud.selection:
		hud.selection.selection_changed.connect(func(_t: Node3D) -> void: _sync_selected())
	_relayout(true)


func _add_summary(key: StringName, icon_name: StringName, color: Color, title: String, tip: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	h.tooltip_text = tip
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(H.icon_rect(icon_name, 14.0, color))
	var l := UIUtil.label("0", &"NumberLabel")
	l.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.3))
	h.add_child(l)
	var t := UIUtil.label(title, &"SubHeaderLabel")
	# 12 px: at 11 the thin first stroke ("C" of COMBAT) vanished into the
	# outline once the HUD scales down (1600 px wide and less).
	t.add_theme_font_size_override("font_size", 12)
	h.add_child(t)
	_summary.add_child(h)
	_sum_labels[key] = l


func _add_chip(role: String, text: String) -> void:
	var b := UIUtil.button(text, &"ChipButton")
	b.toggle_mode = true
	b.custom_minimum_size.y = 18.0 if compact else 22.0
	if compact:
		b.add_theme_font_size_override("font_size", 11)
	if not role.is_empty():
		b.icon = H.icon(H.role_icon(role))
		b.add_theme_color_override("icon_normal_color", H.role_color(role))
		b.add_theme_color_override("icon_pressed_color", H.role_color(role).lerp(Color.WHITE, 0.3))
		b.add_theme_color_override("icon_hover_color", H.role_color(role).lerp(Color.WHITE, 0.2))
		b.add_theme_color_override("icon_hover_pressed_color", H.role_color(role).lerp(Color.WHITE, 0.3))
	b.set_pressed_no_signal(role == filter_role)
	b.pressed.connect(func() -> void:
		filter_role = role
		for k: String in _chip_buttons:
			(_chip_buttons[k] as Button).set_pressed_no_signal(k == filter_role)
		_relayout(true))
	_chips.add_child(b)
	_chip_buttons[role] = b


func _update_sort_label() -> void:
	_sort_button.text = "Sort: %s" % SORT_NAMES[sort_mode]


func _process(delta: float) -> void:
	if hud == null or not is_visible_in_tree():
		# The counts on the tab still update while hidden.
		_layout_left -= delta
		if _layout_left <= 0.0 and hud:
			_layout_left = layout_interval
			_count_only()
		return
	_layout_left -= delta
	if _layout_left <= 0.0:
		_layout_left = layout_interval
		_relayout(false)
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = refresh_interval
		_refresh_cards()


# --- Data -----------------------------------------------------------------------

## {captain, target, system (id), rank (HUD.system_rank)} for every hired
## captain still alive, at every station.
func _entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if hud == null:
		return out
	for m in managers():
		var w := SystemWorld.of(m)
		var sys := w.system_id if w else ClusterNetwork.HOME_ID
		var rank := hud.system_rank(sys)
		for b in m.buildings:
			if not is_instance_valid(b):
				continue
			for c in b.captains:
				if not c.alive:
					continue
				var t: Node3D = c.ship if is_instance_valid(c.ship) else b
				out.append({"captain": c, "target": t, "system": sys, "rank": rank})
	return out


## Home's manager, then each forward station's (live, pinned).
func managers() -> Array[BuildingManager]:
	var out: Array[BuildingManager] = []
	if hud == null:
		return out
	if hud.manager:
		out.append(hud.manager)
	var vm := hud.view_manager
	if vm == null:
		return out
	for id in hud.station_ids():
		if id == ClusterNetwork.HOME_ID:
			continue
		var w := vm.world(id)
		if w and w.buildings:
			out.append(w.buildings)
	return out


static func fleet_of(c: Captain) -> MercFleet:
	if not is_instance_valid(c.ship) or c.ship.brain == null:
		return null
	var mb := c.ship.brain as MercenaryBrain
	return mb.fleet if mb and mb.fleet and mb.fleet.state != MercFleet.State.DONE else null


## System first (home, then the forward stations), then the sort mode.
func _sort_key(e: Dictionary) -> Array:
	var c := e["captain"] as Captain
	var ship := c.ship if is_instance_valid(c.ship) else null
	var role_i := ROLE_ORDER.find(c.role)
	var rank := int(e.get("rank", 0))
	match sort_mode:
		Sort.STATUS:
			var st := int(ship.brain.state) if ship and ship.brain else 99
			return [rank, st, role_i, c.captain_name]
		Sort.HULL:
			return [rank, ship.hull_fraction() if ship else 2.0, c.captain_name]
		Sort.WALLET:
			return [rank, -c.wallet, c.captain_name]
		Sort.RANK:
			return [rank, -c.rank, -c.reputation, c.captain_name]
	return [rank, role_i, c.captain_name]


static func _less(a: Array, b: Array) -> bool:
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return a[i] < b[i]
	return false


## Rebuilds the order (and adds or drops cards) when the roster changed.
func _relayout(force: bool) -> void:
	var all := _entries()
	var counts := {}
	for e: Dictionary in all:
		var r := (e["captain"] as Captain).role
		counts[r] = int(counts.get(r, 0)) + 1
	for role: String in _chip_buttons:
		var b := _chip_buttons[role] as Button
		if role.is_empty():
			b.text = "ALL %d" % all.size()
		else:
			b.visible = counts.has(role)
			var short := String(H.ROLE_SHORT.get(role, role)).to_upper()
			b.text = ("%d" if compact else short + " %d") % int(counts.get(role, 0))
			b.tooltip_text = "Show only %s" % UIUtil.plural(role).to_lower()
	if not filter_role.is_empty() and not counts.has(filter_role):
		filter_role = ""
		for k: String in _chip_buttons:
			(_chip_buttons[k] as Button).set_pressed_no_signal(k == "")
	var shown: Array[Dictionary] = []
	for e in all:
		if filter_role.is_empty() or (e["captain"] as Captain).role == filter_role:
			shown.append(e)
	shown.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _less(_sort_key(a), _sort_key(b)))
	if sort_mode == Sort.ROLE:
		shown = _group(shown)
	# Signature: order, targets, fleets and the tree.
	var parts: PackedStringArray = []
	for e in shown:
		var c := e["captain"] as Captain
		var f := e.get("fleet") as MercFleet
		parts.append("%d:%d:%d:%d:%d" % [c.get_instance_id(), (e["target"] as Node).get_instance_id(), f.get_instance_id() if f else 0,
				int(e.get("branch", 0)), 1 if e.get("leader", false) else 0])
	var key := ",".join(parts)
	if key == _layout_key and not force:
		_count_only(all)
		return
	_layout_key = key
	# Drop cards of captains gone.
	var live := {}
	for e in all:
		live[e["captain"]] = true
	for c: Captain in _cards.keys():
		if not live.has(c):
			(_cards[c] as PilotCard).queue_free()
			_cards.erase(c)
	var rows: Array[Control] = []
	var used_heads := {}
	var last_fleet: MercFleet = null
	for e in shown:
		var c := e["captain"] as Captain
		var f := e.get("fleet") as MercFleet
		var tag := HUD.system_tag(StringName(e.get("system", ClusterNetwork.HOME_ID)))
		if f and f != last_fleet:
			rows.append(_fleet_row(f, tag))
			used_heads[f] = true
		last_fleet = f
		var card := _cards.get(c) as PilotCard
		if card == null:
			card = PilotCard.new()
			card.compact = compact
			card.clicked.connect(_on_card_clicked)
			card.double_clicked.connect(_on_card_double)
			card.right_clicked.connect(_on_card_right)
			_cards[c] = card
		var cf := fleet_of(c)
		card.fleet_tag = ("%s's fleet (%d) for %s, %s" % [cf.leader_name, cf.members.size(), cf.contract.get_target_name() if cf.contract else "?",
				"leader" if cf.members.find(c.ship) == 0 else "wingman"]) if cf else ""
		card.branch = int(e.get("branch", 0)) as PilotCard.Branch
		card.branch_color = e.get("accent", H.TEXT_DIM)
		card.leader = bool(e.get("leader", false))
		card.system_tag = tag
		if card.captain != c or card.target != e["target"]:
			card.bind(c, e["target"] as Node3D)
		else:
			card.refresh()
		rows.append(card)
	_empty.visible = shown.is_empty()
	_empty.text = "No pilots yet. Build a Mining or Mercenary Outpost and hire captains there." if all.is_empty() else "No pilots in this role."
	rows.append(_empty)
	_place_rows(rows)
	for f: MercFleet in _fleet_heads.keys():
		if not used_heads.has(f):
			(_fleet_heads[f] as Control).queue_free()
			_fleet_heads.erase(f)
	for f: MercFleet in _fleet_colors.keys():
		if f.state == MercFleet.State.DONE:
			_fleet_colors.erase(f)
	_sync_selected()
	_count_only(all)


## Puts [param rows] in the list in that order: rows already there are moved
## (never taken out, so a hovered row keeps its tooltip), the rest dropped.
func _place_rows(rows: Array[Control]) -> void:
	var keep := {}
	for r in rows:
		keep[r] = true
	for child in _list.get_children():
		if not keep.has(child):
			_list.remove_child(child)
	for i in rows.size():
		var r := rows[i]
		if r.get_parent() != _list:
			_list.add_child(r)
		if r.get_index() != i:
			_list.move_child(r, i)


func _fleet_row(f: MercFleet, tag: String) -> FleetRow:
	var row := _fleet_heads.get(f) as FleetRow
	if row == null:
		row = FleetRow.new()
		row.clicked.connect(_on_fleet_clicked)
		row.right_clicked.connect(_on_fleet_right)
		_fleet_heads[f] = row
		row.accent = fleet_color(f)
		row.system_tag = tag
		row.bind(f)
	return row


## The accent of [param f]: the next of [constant FLEET_COLORS] when first seen.
func fleet_color(f: MercFleet) -> Color:
	if not _fleet_colors.has(f):
		_fleet_colors[f] = FLEET_COLORS[_next_color % FLEET_COLORS.size()]
		_next_color += 1
	return _fleet_colors[f]


## Role order with the tree: every fleet first (by system, then leader
## name), its members under it, leader first; then the rest, each escort
## under the miner it covers (when that miner is shown). Adds "fleet",
## "branch" (PilotCard.Branch), "leader" and "accent" to the entries.
func _group(list: Array[Dictionary]) -> Array[Dictionary]:
	var fleets: Dictionary = {}
	var by_ship := {}
	for e in list:
		var c := e["captain"] as Captain
		var f := fleet_of(c)
		if f:
			if not fleets.has(f):
				fleets[f] = []
			(fleets[f] as Array).append(e)
		elif is_instance_valid(c.ship):
			by_ship[c.ship] = e
	var order: Array = fleets.keys()
	order.sort_custom(func(a: MercFleet, b: MercFleet) -> bool:
		var ra := int((fleets[a] as Array)[0].get("rank", 0))
		var rb := int((fleets[b] as Array)[0].get("rank", 0))
		return ra < rb if ra != rb else a.leader_name < b.leader_name)
	var out: Array[Dictionary] = []
	for f: MercFleet in order:
		var group: Array = fleets[f]
		group.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return f.members.find((a["captain"] as Captain).ship) < f.members.find((b["captain"] as Captain).ship))
		var col := fleet_color(f)
		for i in group.size():
			var g: Dictionary = group[i]
			g["fleet"] = f
			g["accent"] = col
			g["branch"] = PilotCard.Branch.LAST if i == group.size() - 1 else PilotCard.Branch.MID
			g["leader"] = (g["captain"] as Captain).ship == f.leader
			out.append(g)
	# Escorts: miner ship -> its escorts' entries, in list order (hung:
	# by captain; a Dictionary key would change with the entry).
	var under := {}
	var hung := {}
	for e in list:
		var ward := escorted_miner(e["captain"] as Captain)
		if ward and by_ship.has(ward) and not fleets.has(fleet_of(e["captain"] as Captain)):
			if not under.has(ward):
				under[ward] = []
			(under[ward] as Array).append(e)
			hung[e["captain"]] = true
	for e in list:
		if fleet_of(e["captain"] as Captain) or hung.has(e["captain"]):
			continue
		e["branch"] = PilotCard.Branch.NONE
		e["leader"] = false
		out.append(e)
		var c := e["captain"] as Captain
		if is_instance_valid(c.ship) and under.has(c.ship):
			var esc: Array = under[c.ship]
			for i in esc.size():
				var g: Dictionary = esc[i]
				g["branch"] = PilotCard.Branch.LAST if i == esc.size() - 1 else PilotCard.Branch.MID
				g["accent"] = H.role_color("Mercenary")
				g["leader"] = false
				out.append(g)
	return out


## The miner [param c]'s ship escorts on an escort contract, or null.
static func escorted_miner(c: Captain) -> Ship:
	if not is_instance_valid(c.ship) or c.ship.brain == null or c.ship.brain.trip == null:
		return null
	var ec := c.ship.brain.trip.contract as EscortContract
	if ec == null:
		return null
	var m := ec.miner_of(c.ship)
	return m if is_instance_valid(m) and not m.dead else null


func _refresh_cards() -> void:
	for c: Captain in _cards:
		var card := _cards[c] as PilotCard
		if card.is_inside_tree():
			card.refresh()
	for f: MercFleet in _fleet_heads:
		var row := _fleet_heads[f] as FleetRow
		if row.is_inside_tree():
			row.refresh()
	_count_only()


## The summary line and the tab count, from the cards' last refresh.
func _count_only(all: Array[Dictionary] = []) -> void:
	if all.is_empty():
		all = _entries()
	var fighting := 0
	var damaged := 0
	var working := 0
	var docked := 0
	for e in all:
		var c := e["captain"] as Captain
		var ship := c.ship if is_instance_valid(c.ship) and not c.ship.dead else null
		if ship == null:
			docked += 1
			continue
		var st := ship.brain.state if ship.brain else CaptainBrain.State.DOCKED
		if st == CaptainBrain.State.ENGAGING or st == CaptainBrain.State.FLEEING or ship.durability.seconds_since_hit() < PilotCard.HIT_WINDOW:
			fighting += 1
		if ship.hull_fraction() < 0.5:
			damaged += 1
		if st in [CaptainBrain.State.DOCKED, CaptainBrain.State.RESTING, CaptainBrain.State.REPAIRING, CaptainBrain.State.IDLE, CaptainBrain.State.EVALUATING] \
				or (st == CaptainBrain.State.WAITING_ESCORT and ship.is_docked()):
			docked += 1
		else:
			working += 1
	(_sum_labels[&"combat"] as Label).text = str(fighting)
	(_sum_labels[&"damaged"] as Label).text = str(damaged)
	(_sum_labels[&"working"] as Label).text = str(working)
	(_sum_labels[&"docked"] as Label).text = str(docked)
	count_changed.emit(all.size(), fighting)


# --- Interaction ----------------------------------------------------------------

func _on_card_clicked(card: PilotCard) -> void:
	if hud == null or not is_instance_valid(card.target):
		return
	# A pilot of another system: the view goes there first (it clears the selection).
	if SystemWorld.of(card.target) != (hud.view_manager.viewed if hud.view_manager else null):
		hud.focus(card.target)
	if hud.selection:
		hud.selection.select(card.target)
	_sync_selected()


func _on_card_double(card: PilotCard) -> void:
	if hud == null or not is_instance_valid(card.target):
		return
	# Focus first: it may switch the view to the ship's system (which clears the selection).
	hud.focus(card.target)
	if hud.selection:
		hud.selection.select(card.target)
	_sync_selected()


## Right click: the camera to the ship (its system first), at the zoom it has now.
func _on_card_right(card: PilotCard) -> void:
	if hud == null or not is_instance_valid(card.target):
		return
	hud.focus(card.target, _zoom())


## Click on a fleet line: selects the fleet's target and centres the camera
## on it (zoom kept); without a target in reach, the leader.
func _on_fleet_clicked(row: FleetRow) -> void:
	if hud == null:
		return
	var t := row.target()
	if t == null or not t.is_visible_in_tree():
		_on_fleet_right(row)
		return
	if hud.focus(t, _zoom()) and hud.selection:
		hud.selection.select(t)


## Right click on a fleet line: the camera to the leader, zoom kept.
func _on_fleet_right(row: FleetRow) -> void:
	var lead := row.leader_ship()
	if hud and lead:
		hud.focus(lead, _zoom())


## The viewed camera's distance now (-1: the target's own focus distance).
func _zoom() -> float:
	return hud.camera.get_distance() if hud and hud.camera else -1.0


func _sync_selected() -> void:
	var sel: Node3D = hud.selection.selected if hud and hud.selection else null
	for c: Captain in _cards:
		var card := _cards[c] as PilotCard
		var on := sel != null and card.target == sel and sel is Ship
		if on and not card.selected and card.is_inside_tree():
			_scroll.ensure_control_visible.call_deferred(card)
		card.selected = on


## The card of [param c] (tests, probes).
func card_of(c: Captain) -> PilotCard:
	return _cards.get(c) as PilotCard

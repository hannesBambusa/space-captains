class_name PilotRoster
extends VBoxContainer
## PILOTS tab of the left panel: every hired captain still alive (captains
## waiting for a ship included) as a [PilotCard]. A summary line counts who
## is fighting, damaged, working and docked; role chips filter (All, Miners,
## Mercs, Salvagers: the roles hired so far) and the sort button cycles role,
## status, hull, wallet and rank. In role order mercenaries flying together
## sit under one fleet line, leader first. Cards are pooled per captain and
## refreshed on a timer, never every frame.

signal count_changed(total: int, in_combat: int)

enum Sort { ROLE, STATUS, HULL, WALLET, RANK }

const SORT_NAMES: PackedStringArray = ["Role", "Status", "Hull", "Wallet", "Rank"]
const ROLE_ORDER: PackedStringArray = ["Miner", "Mercenary", "Salvager", "Lander", "Explorer"]
const H := preload("res://scripts/ui/theme/hud_style.gd")

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
## Fleet -> header Label (pooled).
var _fleet_heads: Dictionary = {}
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

## {captain, target} for every hired captain still alive.
func _entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if hud == null or hud.manager == null:
		return out
	for b in hud.manager.buildings:
		if not is_instance_valid(b):
			continue
		for c in b.captains:
			if not c.alive:
				continue
			var t: Node3D = c.ship if is_instance_valid(c.ship) else b
			out.append({"captain": c, "target": t})
	return out


static func fleet_of(c: Captain) -> MercFleet:
	if not is_instance_valid(c.ship) or c.ship.brain == null:
		return null
	var mb := c.ship.brain as MercenaryBrain
	return mb.fleet if mb and mb.fleet and mb.fleet.state != MercFleet.State.DONE else null


func _sort_key(e: Dictionary) -> Array:
	var c := e["captain"] as Captain
	var ship := c.ship if is_instance_valid(c.ship) else null
	var role_i := ROLE_ORDER.find(c.role)
	match sort_mode:
		Sort.STATUS:
			var st := int(ship.brain.state) if ship and ship.brain else 99
			return [st, role_i, c.captain_name]
		Sort.HULL:
			return [ship.hull_fraction() if ship else 2.0, c.captain_name]
		Sort.WALLET:
			return [-c.wallet, c.captain_name]
		Sort.RANK:
			return [-c.rank, -c.reputation, c.captain_name]
	return [role_i, c.captain_name]


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
		shown = _group_fleets(shown)
	# Signature: order, targets and fleets.
	var parts: PackedStringArray = []
	for e in shown:
		var c := e["captain"] as Captain
		var f := fleet_of(c)
		parts.append("%d:%d:%d:%d" % [c.get_instance_id(), (e["target"] as Node).get_instance_id(), f.get_instance_id() if f else 0, f.members.size() if f else 0])
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
	for c in _list.get_children():
		_list.remove_child(c)
	var used_heads := {}
	var last_fleet: MercFleet = null
	for e in shown:
		var c := e["captain"] as Captain
		var f := fleet_of(c)
		if sort_mode == Sort.ROLE and f and f != last_fleet:
			_list.add_child(_fleet_head(f))
			used_heads[f] = true
		last_fleet = f
		var card := _cards.get(c) as PilotCard
		if card == null:
			card = PilotCard.new()
			card.compact = compact
			card.clicked.connect(_on_card_clicked)
			card.double_clicked.connect(_on_card_double)
			_cards[c] = card
		card.fleet_tag = ("%s's fleet (%d) for %s, %s" % [f.leader_name, f.members.size(), f.contract.get_target_name() if f.contract else "?",
				"leader" if f.members.find(c.ship) == 0 else "wingman"]) if f else ""
		card.bind(c, e["target"] as Node3D)
		_list.add_child(card)
	for f: MercFleet in _fleet_heads.keys():
		if not used_heads.has(f):
			(_fleet_heads[f] as Control).queue_free()
			_fleet_heads.erase(f)
	_empty.visible = shown.is_empty()
	_empty.text = "No pilots yet. Build a Mining or Mercenary Outpost and hire captains there." if all.is_empty() else "No pilots in this role."
	_list.add_child(_empty)
	_sync_selected()
	_count_only(all)


func _fleet_head(f: MercFleet) -> Control:
	var head := _fleet_heads.get(f) as PanelContainer
	if head == null:
		head = PanelContainer.new()
		head.theme_type_variation = &"SectionPanel"
		if compact:
			var flat := StyleBoxEmpty.new()
			flat.content_margin_left = 6
			flat.content_margin_top = 3
			head.add_theme_stylebox_override("panel", flat)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		head.add_child(h)
		h.add_child(H.icon_rect(&"fleet", 14.0, Color(1.0, 0.85, 0.42)))
		var l := UIUtil.label("", &"SubHeaderLabel")
		l.name = "Text"
		l.add_theme_color_override("font_color", Color(1.0, 0.88, 0.5))
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		_fleet_heads[f] = head
		if compact:
			H.outline_labels(head)
	var label := head.find_child("Text", true, false) as Label
	label.text = ("%s's fleet (%d) for %s" % [f.leader_name, f.members.size(), f.contract.get_target_name() if f.contract else "?"]).to_upper()
	return head


## Roster entries with each fleet's members together, leader first, in the
## place of the fleet's first member.
static func _group_fleets(list: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var done := {}
	for e in list:
		var f := fleet_of(e["captain"] as Captain)
		if f == null:
			out.append(e)
			continue
		if done.has(f):
			continue
		done[f] = true
		var group: Array[Dictionary] = []
		for g in list:
			if fleet_of(g["captain"] as Captain) == f:
				group.append(g)
		group.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return f.members.find((a["captain"] as Captain).ship) < f.members.find((b["captain"] as Captain).ship))
		out.append_array(group)
	return out


func _refresh_cards() -> void:
	for c: Captain in _cards:
		var card := _cards[c] as PilotCard
		if card.is_inside_tree():
			card.refresh()
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

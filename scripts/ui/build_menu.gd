class_name BuildMenu
extends VBoxContainer
## Bottom build bar, centred: small icon-only [BuildTile]s (rendered
## structure icon, a tiny hotkey badge F1.., the built count "0/2") in groups
## ECONOMY, DEFENCE (with the "Defence zone" tool, ZonePlacement) and ADDONS
## (station addons, BuildingDef.station_addon: picking one enters bay-pick
## mode), each group named by a small vertical tag on its left. Tiles dim
## (the short resource's icon in red) when unaffordable, show a lock at the
## limit or with no free addon bay, and light up while placing. Hovering a
## tile shows the [BuildInfoCard] (name, what it does, cost, build time,
## the limit, the DefenseStats numbers, why it cannot be built, e.g. "Needs
## research: X"). Clicking or the hotkey arms placement; while placing, a
## hint line above the bar shows the controls and why a spot is invalid.
##
## Shown only while a station is selected (its hub, its row in the left
## panel, HOME / H: a [HomeStation] in [member SelectionController.selected])
## or while placing; the F keys only work while it shows. The bar is that
## station's, the viewed system's ([method HUD.local_manager]): at a forward
## station only the defs it allows (BuildingDef.allowed_forward) show, their
## counts and limits are that station's (BuildingManager.max_count_for),
## the addon bays are its station's, and the hotkeys number the shown tiles.

const VALID_COLOR := Color(0.45, 1.0, 0.6)
const INVALID_COLOR := Color(1.0, 0.45, 0.38)
const HINT := "Click: place    Shift-click: place more    Drag: orbit    Right-click / Esc: cancel"
const ADDON_HINT := "Click a free bay: install    Drag: orbit    Right-click / Esc: cancel"
const ZONE_HINT := "Click: place the zone centre (set the radius in its panel)    Drag: orbit    Right-click / Esc: cancel"
const ZONE_ID := &"defense_zone"
const H := preload("res://scripts/ui/theme/hud_style.gd")
const GROUPS: PackedStringArray = ["ECONOMY", "DEFENCE", "ADDONS"]
const GROUP_ICONS: Array[StringName] = [&"econ", &"defence", &"addon"]
const GROUP_TIPS: PackedStringArray = [
	"Outposts that hire captains and bring in ore",
	"Turrets, the shield bubble and defence zones mercenaries patrol",
	"Station addons: built onto one of the station's %d addon bays",
]

var hud: HUD

var _bar: PanelContainer
var _buttons: Dictionary = {}
## Tiles in hotkey order (F1, F2, ...).
var _order: Array[BuildTile] = []
var _zone_button: BuildTile
var _hint: PanelContainer
var _hint_title: Label
var _hint_status: Label
var _info: BuildInfoCard
var _hovered: BuildTile
var _icon_check := 0.0
## Group column -> its tiles (hidden when none shows).
var _columns: Dictionary = {}
var _heads: Array[Control] = []
## The selected station the bar is for (null: hidden unless placing).
var _station: HomeStation
## The manager and zones whose signals are linked ([method _bind_view]).
var _mgr: BuildingManager
var _zones: DefenseZones


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_END
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 8)
	_hint = PanelContainer.new()
	_hint.theme_type_variation = &"HintPanel"
	_hint.visible = false
	_hint.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(_hint)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 2)
	_hint.add_child(hv)
	_hint_title = UIUtil.label("", &"HeaderLabel")
	_hint_title.add_theme_font_size_override("font_size", 16)
	_hint_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hv.add_child(_hint_title)
	_hint_status = UIUtil.label("", &"DimLabel")
	_hint_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hv.add_child(_hint_status)

	_bar = PanelContainer.new()
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(_bar)
	visible = false


func setup(owner_hud: HUD) -> void:
	hud = owner_hud
	_info = BuildInfoCard.new()
	_info.name = "BuildInfo"
	hud.get_node(^"Root").add_child.call_deferred(_info)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	_bar.add_child(h)
	var groups: Array[Array] = [[], [], []]
	if hud.manager:
		for def in hud.manager.building_defs:
			groups[group_of(def)].append(def)
	var key := 1
	for gi in GROUPS.size():
		var defs: Array = groups[gi]
		var has_zone := gi == 1 and hud.zone_placement != null
		if defs.is_empty() and not has_zone:
			continue
		if h.get_child_count() > 0:
			h.add_child(VSeparator.new())
		var col := HBoxContainer.new()
		col.add_theme_constant_override("separation", 3)
		h.add_child(col)
		var head := GroupTag.new()
		head.text = GROUPS[gi]
		head.set_meta(&"group", gi)
		_heads.append(head)
		col.add_child(head)
		var tiles := HBoxContainer.new()
		tiles.add_theme_constant_override("separation", 4)
		col.add_child(tiles)
		_columns[col] = tiles
		for def: BuildingDef in defs:
			var t := BuildTile.new()
			t.setup_def(def, "F%d" % key, GROUP_ICONS[gi])
			key += 1
			t.pressed.connect(_on_pressed.bind(def))
			_wire_hover(t)
			tiles.add_child(t)
			_buttons[def] = t
			_order.append(t)
		if has_zone:
			_zone_button = BuildTile.new()
			_zone_button.setup_tool(ZONE_ID, "Defence zone", "F%d" % key, &"zone")
			key += 1
			_zone_button.pressed.connect(func() -> void:
				if hud.zone_placement.is_armed():
					hud.zone_placement.cancel()
				else:
					hud.zone_placement.arm()
				_refresh())
			_wire_hover(_zone_button)
			tiles.add_child(_zone_button)
			_order.append(_zone_button)
	if hud.zone_placement:
		hud.zone_placement.armed_changed.connect(_on_zone_armed)
		hud.zone_placement.validity_changed.connect(_on_zone_validity)
	Economy.changed.connect(func(_c: int, _m: int) -> void: _refresh())
	Research.changed.connect(_refresh)
	hud.view_rebound.connect(func(_w: SystemWorld) -> void: _bind_view())
	if hud.placement:
		hud.placement.armed_changed.connect(_on_armed)
		hud.placement.validity_changed.connect(_on_validity)
	if hud.selection:
		hud.selection.selection_changed.connect(func(t: Node3D) -> void:
			_station = t as HomeStation
			_sync_visible())
	_bind_view()
	_sync_visible()


## Shown while a station is selected, or while placing (the hint line
## lives in the bar).
func _sync_visible() -> void:
	var placing := (hud.placement != null and hud.placement.def != null) or (hud.zone_placement != null and hud.zone_placement.is_armed())
	var show := placing or (is_instance_valid(_station) and hud.local_manager() != null)
	if visible != show:
		visible = show
		if not show and is_instance_valid(_info):
			_hovered = null
			_info.visible = false


## The viewed system's manager and zones: signals moved over, tiles it
## does not allow hidden, hotkeys renumbered.
func _bind_view() -> void:
	var mgr := hud.local_manager()
	if mgr != _mgr:
		if is_instance_valid(_mgr):
			if _mgr.building_added.is_connected(_on_building):
				_mgr.building_added.disconnect(_on_building)
			if _mgr.building_changed.is_connected(_on_building):
				_mgr.building_changed.disconnect(_on_building)
		_mgr = mgr
		if _mgr:
			_mgr.building_added.connect(_on_building)
			_mgr.building_changed.connect(_on_building)
	var zones := DefenseZones.of(self) if mgr else null
	if zones != _zones:
		if is_instance_valid(_zones) and _zones.zones_changed.is_connected(_refresh):
			_zones.zones_changed.disconnect(_refresh)
		_zones = zones
		if _zones:
			_zones.zones_changed.connect(_refresh)
	var key := 1
	for t in _order:
		var shown := t == _zone_button or (mgr != null and mgr.allows(t.def))
		t.visible = shown
		if shown:
			t.hotkey = "F%d" % key
			key += 1
			t.queue_redraw()
	for col: Control in _columns:
		var any := false
		for t in (_columns[col] as Control).get_children():
			any = any or (t as Control).visible
		col.visible = any
	# Separators sit between shown columns only.
	var row := _bar.get_child(0) as HBoxContainer if _bar.get_child_count() > 0 else null
	if row:
		var seen := false
		var kids := row.get_children()
		for i in kids.size():
			var sep := kids[i] as VSeparator
			if sep == null:
				seen = seen or (kids[i] as Control).visible
				continue
			var next := i + 1 < kids.size() and (kids[i + 1] as Control).visible
			sep.visible = seen and next
	for head in _heads:
		var gi := int(head.get_meta(&"group"))
		head.tooltip_text = GROUP_TIPS[gi] % (mgr.bay_count if mgr else 0) if gi == 2 else GROUP_TIPS[gi]
	_refresh()


func _on_building(_b: Building) -> void:
	_refresh()


## The shown tiles in hotkey order.
func shown_tiles() -> Array[BuildTile]:
	var out: Array[BuildTile] = []
	for t in _order:
		if t.visible:
			out.append(t)
	return out


## 0 economy, 1 defence, 2 station addons.
static func group_of(def: BuildingDef) -> int:
	if def.station_addon:
		return 2
	if not DefenseStats.describe(def).is_empty():
		return 1
	return 0


func get_button(def: BuildingDef) -> Button:
	return _buttons.get(def) as Button


func get_zone_button() -> Button:
	return _zone_button


func get_info_card() -> BuildInfoCard:
	return _info


func _wire_hover(t: BuildTile) -> void:
	t.mouse_entered.connect(func() -> void: show_info(t))
	t.mouse_exited.connect(func() -> void:
		if _hovered == t:
			_hovered = null
			if is_instance_valid(_info):
				_info.visible = false)


## Shows the info card for [param t] above it (hover, probes).
func show_info(t: BuildTile) -> void:
	_hovered = t
	if is_instance_valid(_info):
		_info.show_info(_info_for(t), _anchor_rect(t))


## The tile's column, lifted to the top of the bar (the card sits above it).
func _anchor_rect(t: BuildTile) -> Rect2:
	var r := t.get_global_rect()
	var top := _bar.get_global_rect().position.y
	return Rect2(Vector2(r.position.x, top), Vector2(r.size.x, r.end.y - top))


func _process(delta: float) -> void:
	# Rendered icons may land while the game runs (they are made elsewhere).
	_icon_check -= delta
	if _icon_check <= 0.0:
		_icon_check = 5.0
		for t in _order:
			if t._icon == null:
				t.reload_icon()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or k.ctrl_pressed or k.meta_pressed or k.alt_pressed:
		return
	# Hidden unless a station is selected (or while placing).
	if not is_visible_in_tree():
		return
	var shown := shown_tiles()
	var i := k.keycode - KEY_F1
	if i < 0 or i >= shown.size() or k.keycode > KEY_F12:
		return
	var t := shown[i]
	if t.disabled and t.state != BuildTile.State.PLACING:
		return
	t.pressed.emit()
	get_viewport().set_input_as_handled()


# --- State ------------------------------------------------------------------------

func _block_reason(def: BuildingDef) -> String:
	var why := Economy.shortfall_text(def.cost_credits, def.cost_ore())
	if _mgr:
		var block := _mgr.addon_block_reason(def) if def.station_addon else _mgr.limit_reason(def)
		if not block.is_empty():
			why = block
	return why


func _locked(def: BuildingDef) -> bool:
	if _mgr == null:
		return false
	var block := _mgr.addon_block_reason(def) if def.station_addon else _mgr.limit_reason(def)
	return not block.is_empty()


## Compact cost entries for a tile: credits, then the ores it needs.
static func cost_entries(def: BuildingDef) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({"icon": &"credits", "text": _short_num(def.cost_credits), "short": Economy.credits < def.cost_credits,
			"color": H.CREDITS, "have": UIUtil.amount(Economy.credits), "full": "%s credits" % UIUtil.amount(def.cost_credits)})
	var ore := def.cost_ore()
	# Every resource the def needs (the Forward Station also takes water).
	for i in mini(ore.size(), Economy.COUNT):
		if ore[i] > 0:
			out.append({"icon": Economy.ORE_ICONS[i], "text": str(ore[i]), "short": Economy.ore[i] < ore[i], "color": Economy.ORE_COLORS[i],
					"have": UIUtil.amount(Economy.ore[i]), "full": "%d %s" % [ore[i], Economy.ore_name(i)]})
	return out


## "1.2k" past 999, so the tile line stays short.
static func _short_num(n: int) -> String:
	if n >= 1000:
		return ("%.1fk" % (n / 1000.0)).replace(".0k", "k")
	return str(n)


func _refresh() -> void:
	for def: BuildingDef in _buttons:
		var t: BuildTile = _buttons[def]
		var why := _block_reason(def)
		var armed := hud.placement != null and hud.placement.def == def
		t.disabled = not why.is_empty() and not armed
		t.set_pressed_no_signal(armed)
		t.state = BuildTile.State.PLACING if armed else (BuildTile.State.LOCKED if _locked(def) else (BuildTile.State.UNAFFORDABLE if not why.is_empty() else BuildTile.State.READY))
		var n := _mgr.count_of(def) if _mgr else 0
		var most := _mgr.max_count_for(def) if _mgr else def.max_count
		t.count_text = "%d/%d" % [n, most] if most > 0 else ""
		t.set_costs(cost_entries(def))
		# Keyboard users and screen readers still get the plain text.
		t.tooltip_text = ""
	if _zone_button:
		var n := _zones.count() if is_instance_valid(_zones) else 0
		var zarmed := hud.zone_placement.is_armed()
		_zone_button.disabled = n >= DefenseZones.MAX_ZONES and not zarmed
		_zone_button.set_pressed_no_signal(zarmed)
		_zone_button.state = BuildTile.State.PLACING if zarmed else (BuildTile.State.LOCKED if _zone_button.disabled else BuildTile.State.READY)
		_zone_button.count_text = "%d/%d" % [n, DefenseZones.MAX_ZONES]
		_zone_button.set_costs([{"icon": &"credits", "text": "FREE", "short": false, "color": H.GOOD}] as Array[Dictionary])
	if _hovered and is_instance_valid(_info) and _info.visible:
		_info.show_info(_info_for(_hovered), _anchor_rect(_hovered))


## Everything the info card shows for [param t].
func _info_for(t: BuildTile) -> Dictionary:
	if t == _zone_button:
		var zones := DefenseZones.of(self)
		var n := zones.count() if zones else 0
		return {
			"title": "Defence zone", "group": "DEFENCE",
			"count": "%d of %d placed" % [n, DefenseZones.MAX_ZONES],
			"desc": "An area of %.1f to %.0f km mercenaries patrol and defend: idle mercenaries roam inside, and raiders that come in get engaged by every free mercenary nearby. Optional kill bounty per raider killed inside, paid from a budget you reserve." % [
					DefenseZones.RADIUS_RANGE.x / 1000.0, DefenseZones.RADIUS_RANGE.y / 1000.0],
			"costs": [], "time": "",
			"block": ("All %d placed: remove one first." % DefenseZones.MAX_ZONES) if n >= DefenseZones.MAX_ZONES else "",
			"hint": "Click or %s: place the zone centre" % t.hotkey,
		}
	var def := t.def
	var n := _mgr.count_of(def) if _mgr else 0
	var most := _mgr.max_count_for(def) if _mgr else def.max_count
	var count := ""
	if def.station_addon:
		count = "Station addon: %d of %d bays used" % [_mgr.used_bays() if _mgr else 0, _mgr.bay_count if _mgr else 0]
		if most > 0:
			count += ", %d of %d built" % [n, most]
	elif most > 0:
		count = "%d of %d built" % [n, most]
	else:
		count = "%d built, no limit" % n
	var hire := ""
	if def.can_hire():
		hire = "Hires %s: %s cr each, up to %d berths." % [UIUtil.plural(def.hire_role).to_lower(), UIUtil.amount(def.hire_cost_credits), def.max_hires]
	if def.structure_hull > 0.0:
		hire += (" " if not hire.is_empty() else "") + "Hull %d." % roundi(def.structure_hull)
	var why := _block_reason(def)
	var costs: Array = []
	for c in cost_entries(def):
		costs.append({"icon": c["icon"], "text": c["full"], "short": c["short"], "have": c["have"], "color": c["color"]})
	return {
		"title": def.display_name,
		"group": GROUPS[group_of(def)],
		"count": count,
		"desc": def.description,
		"costs": costs,
		"time": "%d s" % roundi(def.build_time),
		"hire": hire,
		"stats": DefenseStats.describe(def),
		"block": ("Cannot build: " + why) if not why.is_empty() else "",
		"hint": ("Click or %s: pick a free bay" if def.station_addon else "Click or %s: place    Shift-click: place more") % t.hotkey,
	}


# --- Placement feedback ----------------------------------------------------------

func _on_zone_armed(on: bool) -> void:
	_hint.visible = on or (hud.placement != null and hud.placement.def != null)
	_sync_visible()
	if on:
		_hint_title.text = "PLACING A DEFENCE ZONE"
		_hint_status.text = ZONE_HINT
	_refresh()


func _on_zone_validity(valid: bool, reason: String) -> void:
	if not hud.zone_placement.is_armed():
		return
	_hint_status.text = ZONE_HINT + "\n" + reason if valid else reason
	_hint_status.add_theme_color_override("font_color", H.TEXT_DIM if valid else INVALID_COLOR)


func _on_pressed(def: BuildingDef) -> void:
	if hud.placement == null:
		return
	if hud.placement.def == def:
		hud.placement.cancel()
	else:
		hud.placement.arm(def)
	_refresh()


func _on_armed(def: BuildingDef) -> void:
	_hint.visible = def != null or (hud.zone_placement != null and hud.zone_placement.is_armed())
	_sync_visible()
	if def:
		_hint_title.text = (("Installing %s" if def.station_addon else "Placing %s") % def.display_name).to_upper()
		_hint_status.text = _hint_for(def)
		_hint_status.add_theme_color_override("font_color", H.TEXT_DIM)
	_refresh()


func _on_validity(valid: bool, reason: String) -> void:
	if hud.placement == null or hud.placement.def == null:
		return
	if valid:
		_hint_status.text = _hint_for(hud.placement.def)
		_hint_status.add_theme_color_override("font_color", H.TEXT_DIM)
	else:
		_hint_status.text = reason
		_hint_status.add_theme_color_override("font_color", INVALID_COLOR)


static func _hint_for(def: BuildingDef) -> String:
	return ADDON_HINT if def and def.station_addon else HINT


## A group's name, small and vertical, left of its tiles (its tooltip says
## what the group holds).
class GroupTag:
	extends Control

	const FONT_SIZE := 11

	var text := ""
	var _font: Font

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size = Vector2(14.0, BuildTile.SIZE.y)
		_font = HudStyle.font("SemiBold", true, false, 1)

	func _draw() -> void:
		draw_line(Vector2(size.x - 1.0, 4.0), Vector2(size.x - 1.0, size.y - 4.0), HudStyle.HAIRLINE_STRONG, 1.0)
		var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		# Reads bottom to top, centred on the tiles.
		draw_set_transform(Vector2(size.x * 0.5 + _font.get_ascent(FONT_SIZE) * 0.5 - 1.0, (size.y + w) * 0.5), -PI * 0.5)
		draw_string(_font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, HudStyle.HOLO)
		draw_set_transform(Vector2.ZERO)

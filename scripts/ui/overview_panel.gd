class_name OverviewPanel
extends VBoxContainer
## Left panel, tabbed (the tab row stays when collapsed with its button or
## Tab). The pilots have their own list on the right ([PilotColumn]).
## - ALL (default): contracts, threats and the system in one scrolling view.
## - SYSTEM: star, planets (moons nested), asteroid clusters (live: new
##   ones appear, mined-out ones go), stations and structures (player
##   buildings with live status; a forward station's upkeep and water),
##   jump gates, scrap fields.
## - CONTRACTS: posted contracts (with cancel) and what is reserved for
##   bounties and zone budgets.
## - THREATS: the bases that have arrived, grouped by faction, with their
##   hull and the ships out (raiders included) with a state badge (RAID,
##   ATTACK, FLEE...); a base being announced; gate raids; a vague "Next:
##   unknown signals, ~6 min" outlook line from the ThreatDirector.
## Each tab shows a live count. Every list is an [OverviewSection]
## (foldable, the folds kept in the settings file) of dense
## [OverviewRow]s in aligned columns: lead chip or icon | name | detail |
## distance from the viewed station (mono) | meters or badge. Long names
## end in an ellipsis; the row's RichTooltip has the full text and the
## details, live.
## Rows are kept: every 0.25 s each section is matched against what should
## be listed (rows found by key are kept and moved, new ones made, gone ones
## freed) and the rows update their text in place, so a hovered row and its
## tooltip survive. Click a row = the view switches to its system if needed
## (HUD.focus), the camera flies to it and follows, and it is selected; the
## row stays highlighted while the camera follows that target or while it is
## selected.
## Size: the width follows the window (wider, with larger text, when the
## window has fewer pixels than the 1920x1080 canvas); the height fits the
## content, at most down to [member bottom_margin] above the screen bottom
## (the research list, contract strip and event feed live below it). The
## list scrolls with an eased wheel.

enum Tab { ALL, SYSTEM, CONTRACTS, THREATS }

const TAB_NAMES: PackedStringArray = ["ALL", "SYSTEM", "CONTRACTS", "THREATS"]
const TAB_ICONS: Array[StringName] = [&"station", &"tab_system", &"tab_contracts", &"tab_threats"]
const PLANET_TYPES: PackedStringArray = ["Rocky world", "Ocean world", "Desert world", "Ice world", "Lava world", "Gas giant"]
const MOON_TYPES: PackedStringArray = ["Rocky moon", "Ocean moon", "Desert moon", "Ice moon", "Lava moon", "Gas moon"]
## Type dots, by PlanetDef type (rocky, ocean, desert, ice, lava, gas).
const PLANET_COLORS: Array[Color] = [Color(0.66, 0.58, 0.5), Color(0.34, 0.6, 0.96), Color(0.92, 0.75, 0.46),
		Color(0.78, 0.92, 0.98), Color(0.98, 0.42, 0.22), Color(0.74, 0.62, 0.92)]
const ORE_NAMES: PackedStringArray = ["Rock", "Iron", "Titanium", "Crystal"]
const ROCK_COLOR := Color(0.6, 0.6, 0.62)
const SCRAP_COLOR := Color(0.85, 0.8, 0.68)
## Sections in list order: id, title, icon, tab.
const SECTIONS := [
	[&"contracts", "POSTED CONTRACTS", &"tab_contracts", Tab.CONTRACTS],
	[&"threats", "HOSTILES OUT", &"tab_threats", Tab.THREATS],
	[&"star", "STAR", &"star", Tab.SYSTEM],
	[&"planets", "PLANETS", &"planet", Tab.SYSTEM],
	[&"clusters", "ASTEROID CLUSTERS", &"belt", Tab.SYSTEM],
	[&"structures", "STATIONS AND STRUCTURES", &"station", Tab.SYSTEM],
	[&"gates", "JUMP GATES", &"gate", Tab.SYSTEM],
	[&"scrap", "SCRAP FIELDS", &"scrap", Tab.SYSTEM],
]
## Widths of the right column per section, px at the base text size.
const RIGHT_WIDTHS := {&"contracts": 22.0, &"threats": 50.0, &"clusters": 66.0}

## Width at the full 1920x1080 window and on small windows, logical px.
@export var min_width: float = 344.0
@export var max_width: float = 380.0
## Space kept free below the panel, pixels (set by the HUD).
@export var bottom_margin: float = 172.0

var hud: HUD
var is_open := true
var rows: Array[OverviewRow] = []
var tab: Tab = Tab.ALL
## The width in use (follows the window).
var panel_width: float = 360.0

# Sizes for the window: row text, row and header heights.
var _fs := 14
var _row_h := 24.0
var _head_h := 24.0
var _tab_h := 40.0
var _value_w := 52.0

var _toggle_button: Button
var _frame: PanelContainer
var _tabs: HBoxContainer
var _tab_buttons: Array[Button] = []
var _tab_counts: Array[Label] = []
var _body: Control
var _scroll: ScrollContainer
## Fades the row cut by the scroll's bottom edge while more rows follow.
var _fade: TextureRect
var _groups: VBoxContainer
var _sections: Dictionary = {}
## Per section: key -> Control (rows, sub-headers, notes).
var _cache: Dictionary = {}
## Row -> Callable that updates its text in place.
var _updaters: Dictionary = {}
## [signal, callable] links to the viewed system ([method _bind_view]).
var _view_links: Array = []
var _refresh_timer := 0.0
## Eased wheel scrolling: where the list is heading (-1 = not moving).
var _scroll_to := -1.0


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_metrics()
	_frame = PanelContainer.new()
	_frame.name = "Frame"
	var sb := get_theme_stylebox(&"panel", &"PanelContainer").duplicate() as StyleBox
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	_frame.add_theme_stylebox_override(&"panel", sb)
	add_child(_frame)
	var fv := VBoxContainer.new()
	fv.add_theme_constant_override("separation", 6)
	_frame.add_child(fv)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 2)
	fv.add_child(_tabs)
	_build_tabs()

	_body = Control.new()
	_body.name = "Body"
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fv.add_child(_body)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.focus_mode = Control.FOCUS_NONE
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.gui_input.connect(_on_scroll_input)
	_body.add_child(_scroll)
	_fade = _make_fade()
	_body.add_child(_fade)
	var vbar := _scroll.get_v_scroll_bar()
	vbar.value_changed.connect(func(_v: float) -> void: _sync_fade())
	vbar.changed.connect(_sync_fade)
	_groups = VBoxContainer.new()
	_groups.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_groups.add_theme_constant_override("separation", 6)
	_groups.minimum_size_changed.connect(_fit_height, CONNECT_DEFERRED)
	_scroll.add_child(_groups)
	_build_sections()
	_set_tab(Tab.ALL)
	get_viewport().size_changed.connect(_on_resized)
	_fit_height.call_deferred()


## Text size, row heights and width for the window. The canvas is a fixed
## 1920x1080 (or taller/wider) stretched to the window, so a small window
## shows it with fewer pixels: rows get larger text and the panel more width.
func _metrics() -> void:
	var logical := get_viewport_rect().size
	var px := Vector2(get_tree().root.size) if get_tree() else logical
	var ratio := minf(px.x / maxf(logical.x, 1.0), px.y / maxf(logical.y, 1.0))
	# 0 at 95% or more of the canvas pixels, 1 at 70% or less.
	var t := clampf((0.95 - ratio) / 0.25, 0.0, 1.0)
	_fs = 14 + roundi(t * 2.0)
	_row_h = roundf(24.0 + t * 4.0)
	_head_h = roundf(24.0 + t * 3.0)
	_tab_h = roundf(40.0 + t * 4.0)
	_value_w = 52.0 + float(_fs - 14) * 4.0
	panel_width = minf(lerpf(min_width, max_width, t), maxf(logical.x * 0.24, 300.0))


func _on_resized() -> void:
	var fs := _fs
	_metrics()
	if fs != _fs:
		_build_tabs()
		_build_sections()
		_set_tab(tab)
		_sync_all()
	_fit_height()


func _build_tabs() -> void:
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	_tab_buttons.clear()
	_tab_counts.clear()
	for i in TAB_NAMES.size():
		var b := UIUtil.button("", &"TabButton")
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = _tab_h
		b.tooltip_text = TAB_NAMES[i].capitalize() + " (Tab collapses the panel)"
		var v := VBoxContainer.new()
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", 0)
		b.add_child(v)
		var top := HBoxContainer.new()
		top.alignment = BoxContainer.ALIGNMENT_CENTER
		top.add_theme_constant_override("separation", 5)
		v.add_child(top)
		var ic := HudStyle.icon_rect(TAB_ICONS[i], float(_fs), HudStyle.TEXT_DIM)
		ic.name = "Icon"
		top.add_child(ic)
		var cnt := UIUtil.label("", &"NumberLabel")
		cnt.add_theme_font_size_override("font_size", _fs - 1)
		cnt.visible = false
		top.add_child(cnt)
		_tab_counts.append(cnt)
		var name_l := UIUtil.label(TAB_NAMES[i], &"SubHeaderLabel")
		name_l.name = "Name"
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.add_theme_font_size_override("font_size", _fs - 3)
		v.add_child(name_l)
		UIUtil.ignore_mouse(b)
		b.pressed.connect(_on_tab_pressed.bind(i))
		_tabs.add_child(b)
		_tab_buttons.append(b)
	_toggle_button = UIUtil.button("", &"IconButton")
	_toggle_button.icon = HudStyle.icon(&"collapse" if is_open else &"expand")
	_toggle_button.custom_minimum_size = Vector2(24.0, _tab_h)
	_toggle_button.tooltip_text = ("Collapse" if is_open else "Expand") + " the panel (Tab)"
	_toggle_button.pressed.connect(toggle)
	_tabs.add_child(_toggle_button)


## The sections, empty; [method _sync_all] fills them.
func _build_sections() -> void:
	for c in _groups.get_children():
		_groups.remove_child(c)
		c.queue_free()
	rows.clear()
	_updaters.clear()
	_sections.clear()
	_cache.clear()
	for s: Array in SECTIONS:
		var sec := OverviewSection.new(s[0], s[1], s[2], _fs - 1, _head_h)
		sec.set_meta(&"tab", s[3])
		sec.toggled.connect(func(_s: OverviewSection) -> void: _fit_height.call_deferred())
		_groups.add_child(sec)
		_sections[s[0]] = sec
		_cache[s[0]] = {}
	# Room under the last row, so scrolled to the end it clears the frame.
	var end_pad := Control.new()
	end_pad.custom_minimum_size.y = 4.0
	end_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_groups.add_child(end_pad)


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
	r.offset_top = -26.0
	# Leaves the scroll bar unfaded.
	r.offset_right = -10.0
	r.visible = false
	return r


func _sync_fade() -> void:
	var vb := _scroll.get_v_scroll_bar()
	_fade.visible = vb.max_value - vb.page - vb.value > 2.0


## Mouse wheel: eases the list to the next few rows instead of jumping.
func _on_scroll_input(e: InputEvent) -> void:
	var mb := e as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index != MOUSE_BUTTON_WHEEL_UP and mb.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return
	var vb := _scroll.get_v_scroll_bar()
	var from := _scroll_to if _scroll_to >= 0.0 else vb.value
	var dir := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
	_scroll_to = clampf(from + dir * _row_h * 3.0 * maxf(mb.factor, 1.0), 0.0, maxf(vb.max_value - vb.page, 0.0))
	_scroll.accept_event()


func _on_tab_pressed(i: int) -> void:
	if not is_open:
		set_open(true)
	_set_tab(i as Tab)


func _set_tab(t: Tab) -> void:
	tab = t
	_scroll.scroll_vertical = 0
	_scroll_to = -1.0
	_sync_section_visibility()
	for i in _tab_buttons.size():
		var on := i == int(t) and is_open
		_tab_buttons[i].set_pressed_no_signal(on)
		var ic := _tab_buttons[i].find_child("Icon", true, false) as TextureRect
		if not bool(ic.get_meta(&"alert", false)):
			ic.modulate = HudStyle.ACCENT if on else HudStyle.TEXT_DIM
		var nl := _tab_buttons[i].find_child("Name", true, false) as Label
		nl.add_theme_color_override("font_color", HudStyle.TEXT_BRIGHT if on else HudStyle.TEXT_DIM)
	_fit_height.call_deferred()


## A section shows on its tab and on ALL; the system ones only while they
## list something (contracts and threats show their empty line).
func _sync_section_visibility() -> void:
	for id: StringName in _sections:
		var sec: OverviewSection = _sections[id]
		var on_tab := tab == Tab.ALL or int(sec.get_meta(&"tab")) == int(tab)
		var has := sec.body.get_child_count() > 0 or id == &"contracts" or id == &"threats"
		var want := on_tab and has
		if sec.visible != want:
			sec.visible = want


## Opens the panel on [param t] (probes, hotkeys).
func show_tab(t: Tab) -> void:
	set_open(true)
	_set_tab(t)


func setup(owner_hud: HUD) -> void:
	hud = owner_hud
	if hud.selection:
		hud.selection.selection_changed.connect(func(_t: Node3D) -> void: _sync_pressed(_followed()))
	ContractBoard.contract_posted.connect(func(_c: Contract) -> void: _queue_sync())
	ContractBoard.contract_removed.connect(func(_c: Contract) -> void: _queue_sync())
	hud.view_rebound.connect(func(_w: SystemWorld) -> void:
		_bind_view()
		if hud.top_bar and hud.solar_system and hud.solar_system.system_def:
			hud.top_bar.set_system_name(hud.solar_system.system_def.system_name)
		_scroll.scroll_vertical = 0
		_scroll_to = -1.0
		_sync_all())
	Sector.revealed.connect(func(id: StringName, _n: PackedStringArray) -> void:
		var w := SystemWorld.of(self)
		if w and w.system_id == id:
			_queue_sync())
	_bind_view()
	if hud.top_bar and hud.solar_system and hud.solar_system.system_def:
		hud.top_bar.set_system_name(hud.solar_system.system_def.system_name)
	_sync_all()


## Signal links to the viewed system (its camera, buildings, combat world
## and solar system); the old system's are dropped first. They only bring
## the next list check forward; the 0.25 s check catches the rest.
func _bind_view() -> void:
	for link: Array in _view_links:
		var sig := link[0] as Signal
		if not sig.is_null() and is_instance_valid(sig.get_object()) and sig.is_connected(link[1]):
			sig.disconnect(link[1])
	_view_links.clear()
	if hud.camera:
		_link(hud.camera.follow_changed, _sync_pressed)
	var mgr := hud.local_manager()
	if mgr:
		_link(mgr.building_added, func(_b: Building) -> void: _queue_sync())
	var world := CombatWorld.of(self)
	if world:
		_link(world.combatant_spawned, func(_n: Node3D) -> void: _queue_sync())
		_link(world.combatant_destroyed, func(_n: Node3D, _k: Node3D) -> void: _queue_sync())
		_link(world.scrap_changed, _queue_sync)
	if hud.solar_system:
		_link(hud.solar_system.cluster_added, func(_b: AsteroidCluster) -> void: _queue_sync())
		_link(hud.solar_system.cluster_removed, func(_b: AsteroidCluster) -> void: _queue_sync())


func _link(sig: Signal, c: Callable) -> void:
	sig.connect(c)
	_view_links.append([sig, c])


func _queue_sync() -> void:
	_refresh_timer = 0.0


func toggle() -> void:
	set_open(not is_open)


func set_open(open: bool) -> void:
	is_open = open
	_body.visible = open
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
	if _scroll_to >= 0.0:
		var vb := _scroll.get_v_scroll_bar()
		var v := lerpf(vb.value, _scroll_to, 1.0 - exp(-16.0 * delta))
		if absf(v - _scroll_to) < 0.75:
			v = _scroll_to
			_scroll_to = -1.0
		vb.value = v
	_refresh_timer -= delta
	if _refresh_timer > 0.0:
		return
	_refresh_timer = 0.25
	if hud:
		_sync_all()


# --- Keeping the rows ---------------------------------------------------------

## Matches every section to what the viewed system has, then updates the
## rows' text in place.
func _sync_all() -> void:
	if hud == null:
		return
	_sync_contracts()
	_sync_threats()
	_sync_system()
	_sync_section_visibility()
	for row: Variant in _updaters.keys():
		if is_instance_valid(row):
			(_updaters[row] as Callable).call()
	_sync_pressed(_followed())


## Puts [param items] ([key, make Callable] pairs, in list order) into the
## section's body: what is there under the same key is kept (and moved),
## new keys are made, the rest freed.
func _sync(sec_id: StringName, items: Array) -> void:
	var sec: OverviewSection = _sections[sec_id]
	var cache: Dictionary = _cache[sec_id]
	var keep := {}
	var i := 0
	for it: Array in items:
		var key: String = it[0]
		var c: Control = cache.get(key)
		if c == null or not is_instance_valid(c):
			c = (it[1] as Callable).call()
			cache[key] = c
			sec.body.add_child(c)
			if c is OverviewRow:
				rows.append(c)
		keep[key] = true
		if c.get_index() != i:
			sec.body.move_child(c, i)
		i += 1
	for key: String in cache.keys():
		if keep.has(key):
			continue
		var c: Control = cache[key]
		cache.erase(key)
		if not is_instance_valid(c):
			continue
		if c is OverviewRow:
			var r := c as OverviewRow
			rows.erase(r)
			if hud.marker.hover_target == r.target:
				hud.marker.hover_target = null
		_updaters.erase(c)
		sec.body.remove_child(c)
		c.queue_free()


func _key(prefix: String, n: Object) -> String:
	return "%s:%d" % [prefix, n.get_instance_id()]


func _cached(sec_id: StringName, key: String) -> Control:
	var c: Control = (_cache[sec_id] as Dictionary).get(key)
	return c if is_instance_valid(c) else null


## A dense row for the panel, wired to focus and hover.
func _new_row(sec_id: StringName, target: Node3D, title: String, depth: int = 0, with_value: bool = true) -> OverviewRow:
	var row := OverviewRow.new(target, title, "", depth)
	var right: float = RIGHT_WIDTHS.get(sec_id, 0.0)
	row.make_dense(_fs, _row_h, _value_w if with_value else 0.0, right + float(_fs - 14) * 3.0 if right > 0.0 else 0.0)
	# Names get most of the room; details are short.
	row.title_label.size_flags_stretch_ratio = 1.9
	row.pressed.connect(_on_row_pressed.bind(row))
	row.hovered.connect(_on_row_hovered)
	return row


## A dim line in a section (empty state, escrow, outlook), with an icon.
func _make_note(text: String, icon_name: StringName = &"") -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.custom_minimum_size.y = _row_h
	h.add_child(UIUtil.spacer(6.0))
	if not icon_name.is_empty():
		h.add_child(HudStyle.icon_rect(icon_name, float(_fs - 2), HudStyle.TEXT_DIM))
	var l := UIUtil.label(text, &"DimLabel")
	l.name = "Text"
	l.add_theme_font_size_override("font_size", _fs - 1)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(l)
	h.visible = not text.is_empty()
	return h


func _note_text(note: Control, text: String) -> void:
	if note == null:
		return
	var l := note.get_node(^"Text") as Label
	if l.text != text:
		l.text = text
	note.visible = not text.is_empty()


## A small sub-heading inside a section (a faction, "THROUGH THE GATES"):
## colour tick, name, counts on the right.
func _make_subhead(text: String, color: Color) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.custom_minimum_size.y = _row_h - 2.0
	h.add_child(UIUtil.spacer(6.0))
	var chip := ColorRect.new()
	chip.color = color
	chip.custom_minimum_size = Vector2(3.0, 12.0)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(chip)
	var l := UIUtil.label(text.to_upper(), &"SubHeaderLabel")
	l.add_theme_font_size_override("font_size", _fs - 2)
	l.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.2))
	h.add_child(l)
	h.add_child(UIUtil.spacer())
	var c := UIUtil.label("", &"NumberLabel")
	c.name = "Count"
	c.add_theme_font_override("font", HudStyle.mono("Regular"))
	c.add_theme_font_size_override("font_size", _fs - 3)
	c.add_theme_color_override("font_color", HudStyle.TEXT_DIM)
	h.add_child(c)
	h.add_child(UIUtil.spacer(6.0))
	return h


## "12.4 km" from the viewed station to [param n] ("" without a station).
func _km(n: Node3D) -> String:
	var st: Node3D = hud.solar_system.home_station if hud and hud.solar_system else null
	if st == null or not is_instance_valid(st) or not is_instance_valid(n) or n == st or not n.is_inside_tree():
		return ""
	var d := st.global_position.distance_to(n.global_position) / 1000.0
	return "%.1f km" % d if d < 100.0 else "%d km" % roundi(d)


## A stat line for the distance in a tooltip.
func _tip_distance(tip: RichTooltip, n: Node3D) -> void:
	var km := _km(n)
	if not km.is_empty():
		tip.stat("From the station", km)


func _followed() -> Node3D:
	return hud.camera.get_follow_target() if hud and hud.camera else null


# --- Contracts ------------------------------------------------------------------

func _sync_contracts() -> void:
	var list := hud.contracts_by_system(ContractBoard.get_listed())
	var items := []
	if list.is_empty():
		items.append(["none", _make_note.bind("None. Select a cluster, ship or scrap field to post one.")])
	items.append(["escrow", _make_note.bind("", &"credits_small")])
	for c in list:
		items.append([_key("c", c), _make_contract_row.bind(c)])
	_sync(&"contracts", items)
	_note_text(_cached(&"contracts", "escrow"), _escrow_text())
	(_sections[&"contracts"] as OverviewSection).set_count(list.size())
	_set_count(Tab.CONTRACTS, str(list.size()))


func _make_contract_row(c: Contract) -> Control:
	var row := ContractRow.new(c, hud, true)
	row.make_dense(_fs, _row_h, 0.0, RIGHT_WIDTHS[&"contracts"])
	row.title_label.size_flags_stretch_ratio = 1.0
	row.set_lead_icon(_contract_icon(c), HudStyle.ACCENT, float(_fs - 2))
	row.tip_accent = HudStyle.ACCENT
	_updaters[row] = row.refresh
	return row


func _contract_icon(c: Contract) -> StringName:
	var t: Variant = c.target
	if c is ExploreContract or t is JumpGate:
		return &"gate"
	if t is AsteroidCluster:
		return &"belt"
	if t is ScrapField:
		return &"scrap"
	if t is PlanetBody:
		return &"planet"
	if t is ScavengerDen or t is ScavengerShip or c is BountyContract:
		return &"tab_threats"
	return &"tab_contracts"


func _escrow_text() -> String:
	var held := ContractBoard.escrow_total()
	if held <= 0:
		return ""
	var zones := ContractBoard.zone_escrow_total()
	var explore := ContractBoard.explore_escrow_total()
	var bounties := held - zones - explore
	var s := ""
	if explore <= 0:
		s = "Reserved for bounties: %s cr" % UIUtil.amount(bounties)
	elif bounties <= 0:
		s = "Reserved for explore contracts: %s cr" % UIUtil.amount(explore)
	else:
		s = "Reserved: %s cr (bounties %s, explore %s)" % [UIUtil.amount(held - zones), UIUtil.amount(bounties), UIUtil.amount(explore)]
	if zones > 0:
		s += ", zone budgets: %s cr" % UIUtil.amount(zones)
	return s


# --- Threats ----------------------------------------------------------------------

func _sync_threats() -> void:
	var dens: Array[ScavengerDen] = []
	if hud.solar_system:
		dens = hud.solar_system.dens
	# Grouped by faction, in the order their first base appears.
	var groups: Array[FactionDef] = []
	var by_faction: Dictionary = {}
	for d in dens:
		if not is_instance_valid(d) or not FogOfWar.is_revealed(d):
			continue
		if not by_faction.has(d.faction_def):
			by_faction[d.faction_def] = [] as Array[ScavengerDen]
			groups.append(d.faction_def)
		(by_faction[d.faction_def] as Array[ScavengerDen]).append(d)
	var world := CombatWorld.of(self)
	var threats := world.threats if world else null
	var site: DenArrivalSite = threats.site if threats and is_instance_valid(threats.site) else null
	if site and not by_faction.has(site.faction_def):
		by_faction[site.faction_def] = [] as Array[ScavengerDen]
		groups.append(site.faction_def)
	var items := []
	var heads := []
	var ships := 0
	var raiders := 0
	var live_bases := 0
	for f in groups:
		var group: Array[ScavengerDen] = by_faction[f]
		var key := _key("f", f)
		items.append([key, _make_subhead.bind(f.display_name, f.color)])
		var live := 0
		var out := 0
		for d in group:
			if d.is_alive():
				live += 1
			items.append([_key("den", d), _make_den_row.bind(d)])
			for sc in _live_ships(d):
				items.append([_key("ship", sc), _make_ship_row.bind(sc, f)])
				out += 1
				if sc.is_raider:
					raiders += 1
		var arriving := site != null and site.faction_def == f
		if arriving:
			items.append([_key("site", site), _make_site_row.bind(site)])
		live_bases += live
		ships += out
		heads.append([key, "%d/%d bases · %d ships%s" % [live, group.size(), out, " · 1 inbound" if arriving else ""]])
	var g := world.gate_raids if world else null
	if g and (g.is_warned() or not g.dens.is_empty()):
		items.append(["gates", _make_subhead.bind("Through the gates", HudStyle.BAD)])
		if g.is_warned():
			var gate := g.home_gate(String(g.pending["gate"]))
			if gate:
				items.append([_key("gwarn", gate), _make_gate_warn_row.bind(gate, g)])
		for d in g.dens:
			if not is_instance_valid(d) or not is_instance_valid(d.gate):
				continue
			items.append([_key("gden", d), _make_gate_den_row.bind(d)])
			for sc in d.live_raiders():
				if sc.is_visible_in_tree():
					items.append([_key("ship", sc), _make_ship_row.bind(sc, d.faction_def)])
					ships += 1
					raiders += 1
	if items.is_empty():
		items.append(["none", _make_note.bind("No hostile bases detected.")])
	items.append(["outlook", _make_note.bind("", &"clock")])
	_sync(&"threats", items)
	for h: Array in heads:
		var head := _cached(&"threats", h[0])
		if head:
			(head.get_node(^"Count") as Label).text = h[1]
	_note_text(_cached(&"threats", "outlook"), threats.outlook_text() if threats else "")
	var sec: OverviewSection = _sections[&"threats"]
	sec.set_count(ships)
	sec.set_note("%d raiding" % raiders if raiders > 0 else "", HudStyle.BAD)
	_set_count(Tab.THREATS, str(live_bases), raiders > 0)
	var tip := "Threats: %d hostile bases, %d ships out%s" % [live_bases, ships, (", %d raiding" % raiders) if raiders > 0 else ""]
	if _tab_buttons[Tab.THREATS].tooltip_text != tip:
		_tab_buttons[Tab.THREATS].tooltip_text = tip


func _live_ships(d: ScavengerDen) -> Array[ScavengerShip]:
	var out: Array[ScavengerShip] = []
	for sc in d.spawns + d.raiders:
		# In a remote system only the ones a player's ship can see (FogOfWar).
		if is_instance_valid(sc) and not sc.dead and sc.is_visible_in_tree():
			out.append(sc)
	return out


## The base: faction chip, name, ships out, distance, hull bar.
func _make_den_row(d: ScavengerDen) -> Control:
	var f := d.faction_def
	var row := _new_row(&"threats", d, d.get_display_name())
	row.set_lead_chip(f.color)
	row.tip_accent = f.color
	var bar := UIUtil.bar(HudStyle.HULL, Vector2(RIGHT_WIDTHS[&"threats"] - 4.0, 4.0))
	bar.name = "Hull"
	row.add_right(bar)
	row.tip_builder = func(tip: RichTooltip) -> void:
		if not is_instance_valid(d):
			return
		var hull := d.hull_fraction()
		tip.title(d.get_display_name(), f.color.lerp(Color.WHITE, 0.4))
		tip.chips([{"text": f.display_name, "color": f.color}, {"text": d.kind_name(), "color": HudStyle.TEXT_DIM}])
		tip.text("It %s." % d.claim_text())
		tip.stat("Hull", "%d%%" % roundi(hull * 100.0), HudStyle.hull_color(hull))
		tip.bar(hull, HudStyle.hull_color(hull))
		tip.stat("Ships out", "%d/%d" % [d.spawns.size(), d.def.spawn_cap])
		_tip_distance(tip, d)
		tip.hint("Click: fly to it and select it to post a bounty.")
	_updaters[row] = func() -> void:
		if not is_instance_valid(d):
			return
		var alive := d.is_alive()
		row.title_label.add_theme_color_override("font_color", f.color.lerp(Color.WHITE, 0.3) if alive else HudStyle.TEXT_FAINT)
		row.set_subtitle(_den_subtitle(d))
		row.set_value(_km(d))
		bar.value = d.hull_fraction()
		bar.color = HudStyle.hull_color(d.hull_fraction())
	return row


func _den_subtitle(d: ScavengerDen) -> String:
	if not d.is_alive():
		return "destroyed"
	return "%s%d/%d out" % ["arriving, " if d.is_arriving() else "", d.spawns.size(), d.def.spawn_cap]


## A ship out: faction dot, callsign, what it does, distance, state badge.
func _make_ship_row(sc: ScavengerShip, f: FactionDef) -> Control:
	var row := _new_row(&"threats", sc, sc.callsign, 1)
	row.set_lead_chip(f.color, true, 6.0)
	row.tip_accent = f.color
	row.title_label.add_theme_color_override("font_color", f.color.lerp(Color.WHITE, 0.45))
	row.tip_builder = func(tip: RichTooltip) -> void:
		if not is_instance_valid(sc):
			return
		tip.title(sc.callsign, f.color.lerp(Color.WHITE, 0.45))
		var chips: Array[Dictionary] = [{"text": f.display_name, "color": f.color}]
		if sc.is_raider:
			chips.append({"text": "Raider", "color": HudStyle.BAD})
		tip.chips(chips)
		tip.text(sc.get_status_text())
		_tip_distance(tip, sc)
		tip.hint("Click: fly to it and select it.")
	_updaters[row] = func() -> void:
		if not is_instance_valid(sc) or sc.dead:
			return
		row.set_subtitle(("raider, " if sc.is_raider else "") + sc.get_status_text().to_lower())
		row.set_value(_km(sc))
		var b := _ship_badge(sc)
		row.set_badge(b[0], b[1])
	return row


## State tag of a hostile ship: [text, colour].
func _ship_badge(sc: ScavengerShip) -> Array:
	if sc.ai == null:
		return ["", HudStyle.TEXT_DIM]
	if sc.get_status_text().to_lower().contains("warp"):
		return ["WARP", HudStyle.HOLO]
	match sc.ai.state:
		ScavengerBrain.State.LAUNCHING:
			return ["LAUNCH", HudStyle.TEXT_DIM]
		ScavengerBrain.State.ROAMING:
			return ["ROAM", HudStyle.TEXT_DIM]
		ScavengerBrain.State.HUNTING:
			return ["HUNT", HudStyle.WARN]
		ScavengerBrain.State.ATTACKING:
			return ["ATTACK", HudStyle.BAD]
		ScavengerBrain.State.FLEEING:
			return ["FLEE", HudStyle.HOLO]
		ScavengerBrain.State.RAIDING:
			return ["RAID", HudStyle.BAD]
		ScavengerBrain.State.RETURNING:
			return ["RETURN", HudStyle.TEXT_DIM]
		ScavengerBrain.State.DEFENDING:
			return ["DEFEND", HudStyle.WARN]
	return ["", HudStyle.TEXT_DIM]


## A base being announced: no hull, a countdown.
func _make_site_row(site: DenArrivalSite) -> Control:
	var f := site.faction_def
	var row := _new_row(&"threats", site, site.get_display_name())
	row.set_lead_chip(Color(f.color, 0.45))
	row.tip_accent = f.color
	row.title_label.add_theme_color_override("font_color", Color(f.color.lerp(Color.WHITE, 0.3), 0.75))
	row.set_badge("INBOUND", HudStyle.WARN)
	row.tip_builder = func(tip: RichTooltip) -> void:
		if not is_instance_valid(site):
			return
		tip.title(site.get_display_name(), f.color.lerp(Color.WHITE, 0.4))
		tip.chips([{"text": f.display_name, "color": f.color}, {"text": "Inbound", "color": HudStyle.WARN}])
		tip.text("Long-range scans: %s ships gathering near %s." % [f.unit_name, site.def.belt_name])
		tip.stat("Arrives in", site.countdown_text(), HudStyle.WARN)
		_tip_distance(tip, site)
	_updaters[row] = func() -> void:
		if is_instance_valid(site):
			row.set_subtitle(site.get_status_text().to_lower())
			row.set_value(_km(site))
	return row


## A raid forming behind a home gate (the player was warned).
func _make_gate_warn_row(gate: JumpGate, g: GateRaidSource) -> Control:
	var row := _new_row(&"threats", gate, "Raid forming in %s" % GateRaidSource._system_name(StringName(g.pending["source"])))
	row.set_lead_icon(&"warning", HudStyle.BAD, float(_fs - 2))
	row.tip_accent = HudStyle.BAD
	row.title_label.add_theme_color_override("font_color", HudStyle.BAD.lerp(Color.WHITE, 0.25))
	row.set_badge("FORMING", HudStyle.BAD)
	row.tip_builder = func(tip: RichTooltip) -> void:
		tip.title(row.title_label.text, HudStyle.BAD.lerp(Color.WHITE, 0.25))
		if is_instance_valid(g) and g.is_warned():
			tip.text(g.warning_text())
		tip.hint("Your scouts saw them gather. Select the gate to see where they come out.")
	_updaters[row] = func() -> void:
		if is_instance_valid(g) and g.is_warned():
			row.set_subtitle("through %s %s" % [String(g.pending.get("gate", "")), g.eta_text()])
			row.set_value(_km(gate))
	return row


## A raid in progress through a gate (its stand-in base sits at the gate).
func _make_gate_den_row(d: GateRaidDen) -> Control:
	var f := d.faction_def
	var row := _new_row(&"threats", d.gate, d.get_display_name())
	row.set_lead_chip(f.color)
	row.tip_accent = f.color
	row.title_label.add_theme_color_override("font_color", f.color.lerp(Color.WHITE, 0.3))
	row.set_badge("RAID", HudStyle.BAD)
	_updaters[row] = func() -> void:
		if is_instance_valid(d):
			row.set_subtitle(d.get_status_text())
			row.set_value(_km(d.gate))
	return row


# --- System ---------------------------------------------------------------------

func _sync_system() -> void:
	var sys := hud.solar_system
	var star_items := []
	var planet_items := []
	var cluster_items := []
	var structure_items := []
	var gate_items := []
	var scrap_items := []
	if sys:
		if sys.star:
			star_items.append([_key("star", sys.star), _make_star_row.bind(sys)])
		# Remote systems list only what explorers revealed (FogOfWar).
		for p: PlanetBody in sys.planets:
			if not FogOfWar.is_revealed(p):
				continue
			planet_items.append([_key("pl", p), _make_body_row.bind(p, 0)])
			for c in p.get_children():
				if c is PlanetBody:
					planet_items.append([_key("pl", c), _make_body_row.bind(c, 1)])
		for b: AsteroidCluster in _shown_belts(sys):
			cluster_items.append([_key("cl", b), _make_cluster_row.bind(b)])
		structure_items = _structure_items(sys)
		for g: JumpGate in sys.gates:
			if FogOfWar.is_revealed(g):
				gate_items.append([_key("gate", g), _make_gate_row.bind(g)])
		var world := CombatWorld.of(self)
		if world:
			for f in world.get_scrap_fields():
				scrap_items.append([_key("scrap", f), _make_scrap_row.bind(f)])
	_sync(&"star", star_items)
	_sync(&"planets", planet_items)
	_sync(&"clusters", cluster_items)
	_sync(&"structures", structure_items)
	_sync(&"gates", gate_items)
	_sync(&"scrap", scrap_items)
	(_sections[&"star"] as OverviewSection).set_count(-1)
	(_sections[&"planets"] as OverviewSection).set_count(planet_items.size())
	(_sections[&"clusters"] as OverviewSection).set_count(cluster_items.size())
	(_sections[&"structures"] as OverviewSection).set_count(structure_items.size())
	(_sections[&"gates"] as OverviewSection).set_count(gate_items.size())
	(_sections[&"scrap"] as OverviewSection).set_count(scrap_items.size())
	_set_count(Tab.SYSTEM, str(cluster_items.size()))
	var tip := "System: %d asteroid clusters (Tab collapses the panel)" % cluster_items.size()
	if _tab_buttons[Tab.SYSTEM].tooltip_text != tip:
		_tab_buttons[Tab.SYSTEM].tooltip_text = tip


func _make_star_row(sys: SolarSystem) -> Control:
	var star := sys.star
	var row := _new_row(&"star", star, sys.system_def.system_name if sys.system_def else "Star")
	var col: Color = star.color if star is Star else HudStyle.WARN
	row.set_lead_icon(&"star", col.lerp(Color(1.0, 0.85, 0.5), 0.4), float(_fs - 1))
	var temp := int(sys.system_def.star_temperature) if sys.system_def else 0
	row.set_value("%d K" % temp)
	return row


func _make_body_row(body: PlanetBody, depth: int) -> Control:
	var moon := depth > 0
	var row := _new_row(&"planets", body, body.def.name, depth)
	var col := PLANET_COLORS[clampi(body.def.type, 0, PLANET_COLORS.size() - 1)]
	row.set_lead_chip(col, true, 6.0 if moon else 8.0)
	if moon:
		row.title_label.add_theme_color_override("font_color", HudStyle.TEXT)
	var kind: String = (MOON_TYPES if moon else PLANET_TYPES)[body.def.type]
	row.tip_builder = func(tip: RichTooltip) -> void:
		if not is_instance_valid(body):
			return
		tip.title(body.def.name)
		tip.chips([{"text": kind, "color": col}])
		var g: Variant = _garrison(body)
		if g:
			tip.text("Held by %s." % _holder(g), HudStyle.BAD)
		_tip_distance(tip, body)
		tip.hint("Click: fly to it and select it.")
	_updaters[row] = func() -> void:
		if not is_instance_valid(body):
			return
		var g: Variant = _garrison(body)
		row.set_subtitle("held by %s" % _holder(g) if g else kind)
		if g:
			row.subtitle_label.add_theme_color_override("font_color", HudStyle.BAD)
		else:
			row.subtitle_label.remove_theme_color_override("font_color")
		row.set_value(_km(body))
	return row


func _garrison(body: PlanetBody) -> Variant:
	var claims := PlanetClaims.of(self)
	return claims.garrison_of(body) if claims else null


func _holder(g: Variant) -> String:
	return g.gang if not g.gang.is_empty() else g.faction_def.display_name


## The clusters the fog of war lets the list show (all of them at home).
func _shown_belts(sys: SolarSystem) -> Array:
	return sys.belts.filter(func(b: AsteroidCluster) -> bool: return is_instance_valid(b) and FogOfWar.is_revealed(b))


## UI colour of an AsteroidBelt.OreType (rock grey).
static func ore_color(ore_type: int) -> Color:
	return Economy.ORE_COLORS[ore_type - 1] if ore_type >= 1 and ore_type <= Economy.BASE_COUNT else ROCK_COLOR


## Ore chip, name, what is left, distance, richness bar, danger pips.
func _make_cluster_row(belt: AsteroidCluster) -> Control:
	var d := belt.def
	var row := _new_row(&"clusters", belt, d.name)
	var col := ore_color(d.ore_type)
	row.set_lead_chip(col)
	row.tip_accent = col
	var bar := UIUtil.bar(HudStyle.TEXT, Vector2(22.0, 4.0))
	bar.name = "Richness"
	bar.value = d.richness
	row.add_right(bar)
	var pips := PipMeter.new()
	pips.name = "Danger"
	pips.style = PipMeter.Style.PIPS
	pips.max_value = 5.0
	pips.graded = true
	pips.pip_size = 6.0
	pips.pip_gap = 2.0
	row.add_right(pips)
	row.tip_builder = func(tip: RichTooltip) -> void:
		if not is_instance_valid(belt):
			return
		tip.title(d.name)
		var chips: Array[Dictionary] = [{"text": ORE_NAMES[d.ore_type], "color": col}]
		if d.secondary_ore != AsteroidBelt.OreType.ROCK and d.secondary_ore != d.ore_type:
			chips.append({"text": ORE_NAMES[d.secondary_ore], "color": ore_color(d.secondary_ore)})
		tip.chips(chips)
		tip.stat("Richness", "%d%%" % roundi(d.richness * 100.0))
		tip.stat("Ore left", "mined out" if belt.is_depleted else "%d of %d loads" % [belt.loads_left, belt.reserve])
		tip.bar(belt.fill_fraction(), col)
		tip.stat("Danger", "%d of 5" % belt.danger, PipMeter.grade((float(belt.danger) - 1.0) / 4.0))
		_tip_distance(tip, belt)
		tip.hint("Click: fly to it and select it. Rich clusters draw more raiders.")
	_updaters[row] = func() -> void:
		if not is_instance_valid(belt):
			return
		row.set_subtitle("mined out" if belt.is_depleted else "%d%% left" % roundi(belt.fill_fraction() * 100.0))
		row.title_label.add_theme_color_override("font_color", HudStyle.TEXT_FAINT if belt.is_depleted else HudStyle.TEXT)
		row.set_value(_km(belt))
		pips.value = float(belt.danger)
	return row


## The station, a forward station's upkeep and water, then the structures.
func _structure_items(sys: SolarSystem) -> Array:
	var items := []
	var mgr := hud.local_manager()
	if sys.home_station:
		items.append([_key("st", sys.home_station), _make_station_row])
		if StationSupply.of(self):
			# A forward station: upkeep and water rows under it (F4).
			items.append(["upkeep", _make_supply_row.bind(&"upkeep")])
			items.append(["water", _make_supply_row.bind(&"water")])
	if mgr:
		for b in mgr.buildings:
			if is_instance_valid(b):
				items.append([_key("b", b), _make_building_row.bind(b)])
	return items


## The station row: "bays 1/2"; the tooltip has the orbit and, at a forward
## station, the upkeep, water and hauling fee (StationSupply.tooltip_text).
func _make_station_row() -> Control:
	var station := hud.solar_system.home_station
	var mgr := hud.local_manager()
	var st := mgr.station_node() if mgr else null
	var row := _new_row(&"structures", station, st.station_name if st else "Station")
	row.set_lead_icon(&"station", HudStyle.HOLO, float(_fs - 1))
	row.tip_builder = func(tip: RichTooltip) -> void:
		if not is_instance_valid(station):
			return
		tip.title(row.title_label.text)
		var host := station.get_parent() as PlanetBody
		if host:
			tip.stat("Orbit", host.def.name, HudStyle.TEXT_BRIGHT, false)
		var m := hud.local_manager()
		if m:
			tip.stat("Addon bays", "%d/%d used" % [m.used_bays(), m.bay_count])
		var supply := StationSupply.of(self)
		if supply:
			for l in supply.tooltip_text().split("\n", false):
				tip.text(l)
		tip.hint("Click: fly to the station and select it.")
	_updaters[row] = func() -> void:
		var m := hud.local_manager()
		row.set_subtitle("bays %d/%d" % [m.used_bays(), m.bay_count] if m else "")
	return row


func _make_supply_row(kind: StringName) -> Control:
	var station := hud.solar_system.home_station
	var water := kind == &"water"
	var row := _new_row(&"structures", station, "Water" if water else "Upkeep", 1, false)
	# Short names, long readouts.
	row.title_label.size_flags_stretch_ratio = 0.7
	row.set_lead_icon(&"water" if water else &"credits_small", Economy.ORE_COLORS[Economy.Ore.WATER] if water else HudStyle.CREDITS, float(_fs - 2))
	row.set_meta(&"supply", kind)
	row.tip_builder = func(tip: RichTooltip) -> void:
		var supply := StationSupply.of(self)
		tip.title("Water" if water else "Upkeep")
		if supply:
			for l in supply.tooltip_text().split("\n", false):
				tip.text(l)
	_updaters[row] = func() -> void:
		var supply := StationSupply.of(self)
		if supply == null:
			return
		row.set_subtitle(supply.water_short() if water else supply.upkeep_short())
		if supply.dry if water else supply.owed > 0:
			row.subtitle_label.add_theme_color_override("font_color", HudStyle.BAD)
		else:
			row.subtitle_label.remove_theme_color_override("font_color")
	return row


## Status dot, name, status, hires.
func _make_building_row(b: Building) -> Control:
	var row := _new_row(&"structures", b, b.display_name, 1)
	row.set_lead_chip(HudStyle.GOOD, true, 6.0)
	row.tip_builder = func(tip: RichTooltip) -> void:
		if not is_instance_valid(b):
			return
		tip.title(b.display_name)
		tip.text(b.get_status_text())
		if b.def.can_hire():
			tip.stat(UIUtil.plural(b.def.hire_role), "%d/%d" % [b.ships.size(), b.def.max_hires])
			var rep := b.repairing_count()
			if rep > 0:
				tip.stat("Repairing", str(rep), HudStyle.WARN)
		tip.hint("Click: fly to it and select it.")
	_updaters[row] = func() -> void:
		if not is_instance_valid(b):
			return
		row.set_subtitle(_building_subtitle(b))
		row.set_lead_chip(HudStyle.GOOD if b.is_active() else HudStyle.WARN, true, 6.0)
		row.set_value("%d/%d" % [b.ships.size(), b.def.max_hires] if b.def.can_hire() else "")
	return row


func _building_subtitle(b: Building) -> String:
	if not b.is_active():
		return b.get_status_text().to_lower()
	if b.def.can_hire():
		var rep := b.repairing_count()
		return "active, %d repairing" % rep if rep > 0 else "active"
	var ds := b.get_service() as DefenseStructure
	if ds:
		return ds.get_status_text().to_lower()
	var f := b.get_service() as Factory
	if f:
		return "%s, %d parts" % [f.status_text().to_lower(), f.warehouse_total()]
	return "active"


func _make_gate_row(g: JumpGate) -> Control:
	var row := _new_row(&"gates", g, g.def.name)
	row.set_lead_icon(&"gate", HudStyle.HOLO, float(_fs - 1))
	var w := SystemWorld.of(g)
	var to: StringName = Sector.network.gate_target(w.system_id, g.def.name).get("system", &"") if Sector.network and w else &""
	row.set_subtitle("to %s" % g.def.target_system)
	row.tip_builder = func(tip: RichTooltip) -> void:
		if not is_instance_valid(g):
			return
		tip.title(g.def.name)
		tip.stat("Leads to", String(g.def.target_system), HudStyle.TEXT_BRIGHT, false)
		var note := Sector.danger_text(to) if not to.is_empty() and to != ClusterNetwork.HOME_ID else ""
		if not note.is_empty():
			tip.stat("Beyond", note, HudStyle.TEXT_BRIGHT, false)
		_tip_distance(tip, g)
		tip.hint("Click: fly to it and select it.")
	_updaters[row] = func() -> void:
		if is_instance_valid(g):
			row.set_value(_km(g))
	return row


func _make_scrap_row(f: ScrapField) -> Control:
	var row := _new_row(&"scrap", f, f.display_name)
	row.set_lead_icon(&"scrap", SCRAP_COLOR, float(_fs - 1))
	row.title_label.add_theme_color_override("font_color", SCRAP_COLOR)
	row.tip_builder = func(tip: RichTooltip) -> void:
		if not is_instance_valid(f):
			return
		tip.title(f.display_name, SCRAP_COLOR)
		tip.text(f.get_status_text())
		_tip_distance(tip, f)
		tip.hint("Click: fly to it and select it. Salvagers bring scrap home.")
	_updaters[row] = func() -> void:
		if is_instance_valid(f):
			row.set_subtitle(f.get_status_text().replace(", ", " · "))
			row.set_value(_km(f))
	return row


# --- Tab counts ---------------------------------------------------------------------

## The count on a tab; [param alert] tints it red (fighting, raiders out).
func _set_count(t: Tab, text: String, alert: bool = false) -> void:
	var l := _tab_counts[int(t)]
	if l.text != text:
		l.text = text
	l.visible = not text.is_empty()
	l.add_theme_color_override("font_color", HudStyle.BAD if alert else HudStyle.TEXT_BRIGHT)
	var ic := _tab_buttons[int(t)].find_child("Icon", true, false) as TextureRect
	ic.set_meta(&"alert", alert)
	if alert:
		ic.modulate = HudStyle.BAD
	else:
		ic.modulate = HudStyle.ACCENT if int(t) == int(tab) and is_open else HudStyle.TEXT_DIM


# --- Interaction --------------------------------------------------------------

func _on_row_pressed(row: OverviewRow) -> void:
	if not is_instance_valid(row.target):
		return
	hud.focus(row.target)
	if hud.selection:
		if row.target is Building or row.target is Ship or row.target is ScavengerDen or row.target is ScrapField or row.target is PlanetBody:
			hud.selection.select(row.target)
		elif hud.solar_system and row.target == hud.solar_system.home_station:
			# The station row: selects the station (its panel, the build bar).
			hud.select_station()
		elif row.target.get_meta(&"belt", null) is AsteroidCluster:
			hud.selection.select(row.target.get_meta(&"belt") as AsteroidCluster)
	_sync_pressed(_followed())


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
			var on := r.target != null and (r.target == target or r.target == sel) and not r.has_meta(&"supply")
			if r.button_pressed != on:
				r.set_pressed_no_signal(on)


## Width from the window; the height fits the rows, at most down to
## [member bottom_margin] above the screen bottom.
func _fit_height() -> void:
	if _frame == null:
		return
	custom_minimum_size.x = panel_width
	if not is_open:
		custom_minimum_size.y = 0.0
		size = Vector2(panel_width, 0.0)
		return
	var avail := get_viewport_rect().size.y - position.y - bottom_margin
	var sb := _frame.get_theme_stylebox(&"panel")
	var chrome := (sb.get_minimum_size().y if sb else 0.0) + _tab_h + 6.0
	var room := maxf(avail - chrome, 120.0)
	var h := minf(_groups.get_combined_minimum_size().y, room)
	if absf(_body.custom_minimum_size.y - h) > 0.5:
		_body.custom_minimum_size.y = h
	custom_minimum_size.y = 0.0
	size = Vector2(panel_width, 0.0)
	_sync_fade.call_deferred()

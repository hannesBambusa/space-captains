class_name ClusterMap
extends Control
## Full-screen cluster map (P4; M or the top bar's MAP button, Esc or M
## closes; nothing pauses). The gate network as far as the player knows
## it: home and every charted system, and behind each charted gate the
## system it leads to, as a "?" node until surveyed. Columns by jumps from
## home. A node shows the danger colour (grey "?" uncharted), the name, the
## danger and survey age ("seen 12 min ago"; stale surveys dimmed), what was
## charted (clusters by ore, bases, derelicts left), your ships there and in
## the jump there (cyan count) and an open explore contract (amber flag).
## Double-click a node: view it (like "View system").
## Click a node: the info panel on the right with "View system" (when the
## view may switch there, ViewManager.can_view) and "Post explore contract"
## at fair pay (on the charted gate that leads there, when the board allows
## it: ContractBoard.explore_problem). A gate raid forming there that the
## player was warned of shows too. A system with a station (home or a
## forward one) has the station icon above its node, the forward station's
## name under it, and a station line in the info panel ([method station_text]).
## Layout and drawing live in [ClusterGraph] (shared with the minimap's
## CLUSTER mode, which opens this map on a node with [method open_on]).

const H := preload("res://scripts/ui/theme/hud_style.gd")
const COL_W := 300.0
const PANEL_W := 400.0
const REFRESH := 0.5

var hud: HUD
var selected: StringName = ClusterNetwork.HOME_ID

## Layout and drawing, shared with the minimap's CLUSTER mode.
var _graph := ClusterGraph.new()
## Shown nodes (the graph's): id -> {pos, known (bool), via: [from id, gate name] or []}.
var _nodes: Dictionary = {}
var _info: VBoxContainer
var _title: Label
var _body: Label
var _view: Button
var _post: Button
## F6: "Set destination here" for a mobile station (StationPanel.pick_mobile).
var _dest: Button
var _post_from: StringName = &""
var _post_gate := ""
var _post_reward := 0
var _timer := 0.0


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var head := HBoxContainer.new()
	head.position = Vector2(28.0, 22.0)
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(head)
	head.add_child(H.icon_rect(&"tab_system", 18.0, H.HOLO))
	var t := UIUtil.label("CLUSTER MAP", &"HeaderLabel")
	t.add_theme_font_size_override("font_size", 20)
	head.add_child(t)
	head.add_child(UIUtil.label("   Click a system for details.  M or Esc: close", &"DimLabel"))
	var panel := PanelContainer.new()
	panel.name = "Info"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -PANEL_W - 24.0
	panel.offset_right = -24.0
	panel.offset_top = 70.0
	panel.custom_minimum_size.x = PANEL_W
	add_child(panel)
	_info = VBoxContainer.new()
	_info.add_theme_constant_override("separation", 8)
	panel.add_child(_info)
	var top := HBoxContainer.new()
	_info.add_child(top)
	top.add_child(UIUtil.label("SYSTEM", &"HeaderLabel"))
	top.add_child(UIUtil.spacer())
	var close := UIUtil.button("x", &"IconButton")
	close.custom_minimum_size = Vector2(26.0, 22.0)
	close.tooltip_text = "Close the map (M, Esc)"
	close.pressed.connect(close_map)
	top.add_child(close)
	_title = UIUtil.label("", &"TitleLabel")
	_info.add_child(_title)
	_body = UIUtil.label("", &"")
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = PANEL_W - 24.0
	_info.add_child(_body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_info.add_child(row)
	_view = UIUtil.button("View system", &"")
	_view.pressed.connect(_on_view)
	row.add_child(_view)
	_post = UIUtil.button("Post explore contract", &"")
	_post.pressed.connect(_on_post)
	row.add_child(_post)
	_dest = UIUtil.button("Set destination here", &"AccentButton")
	_dest.pressed.connect(_on_dest)
	_info.add_child(_dest)
	UIUtil.no_focus(self)


func setup(owner_hud: HUD) -> void:
	hud = owner_hud
	_graph.hud = hud
	Sector.surveyed.connect(func(_id: StringName) -> void: _rebuild())
	Sector.revealed.connect(func(_id: StringName, _n: PackedStringArray) -> void: _rebuild())
	ContractBoard.contract_posted.connect(func(_c: Contract) -> void: _refresh())
	ContractBoard.contract_removed.connect(func(_c: Contract) -> void: _refresh())


func toggle() -> void:
	if visible:
		close_map()
	else:
		open_map()


func open_map() -> void:
	visible = true
	if not _nodes.has(selected):
		selected = ClusterNetwork.HOME_ID
	_rebuild()


## Opens the map with [param id] selected (the minimap's right click).
func open_on(id: StringName) -> void:
	visible = true
	_rebuild()
	if _nodes.has(id):
		selected = id
		_refresh()


func close_map() -> void:
	visible = false


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		close_map()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH
		_refresh()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		accept_event()
		return
	var id := _graph.node_at(mb.position)
	if not id.is_empty():
		selected = id
		_refresh()
		# Double click: same as "View system".
		if mb.double_click:
			_on_view()
	accept_event()


# --- Graph ---------------------------------------------------------------------------

## True when [param id] has been surveyed (home always).
static func is_charted(id: StringName) -> bool:
	return ClusterGraph.is_charted(id)


## What the player knows of the network ([method ClusterGraph.rebuild]),
## left of the info panel.
func _rebuild() -> void:
	var area := Rect2(Vector2(110.0, 120.0), Vector2(size.x - PANEL_W - 260.0, size.y - 240.0))
	_graph.rebuild(area, COL_W)
	_nodes = _graph.nodes
	if not _nodes.has(selected):
		selected = ClusterNetwork.HOME_ID
	_refresh()


func _refresh() -> void:
	if not visible:
		return
	queue_redraw()
	_fill_info()


# --- Data per node ---------------------------------------------------------------------

func _ships_in(id: StringName) -> PackedStringArray:
	return _graph.ships_in(id)


func _in_transit(id: StringName) -> int:
	return ClusterGraph.in_transit(id)


func _contracts_for(id: StringName) -> Array[ExploreContract]:
	return ClusterGraph.contracts_for(id)


## "3 clusters (2 titanium, 1 crystal), 1 base, 2 derelicts left".
static func contents_text(id: StringName, short: bool = false) -> String:
	var def := Sector.system_def(id)
	var st := Sector.state(id)
	if def == null or st == null:
		return ""
	var ores: Dictionary = {}
	var nc := 0
	for c in def.belts:
		if st.revealed.has(c.name):
			nc += 1
			var w := String(Survey.ORE_WORDS[clampi(c.ore_type, 0, 3)])
			ores[w] = int(ores.get(w, 0)) + 1
	var nb := 0
	for d in def.dens:
		if st.revealed.has(d.name) and not bool((st.dens.get(d.name, {}) as Dictionary).get("dead", false)):
			nb += 1
	var nx := Sector.derelicts_left(id)
	if short:
		return "%d cl · %d base%s · %d wreck%s" % [nc, nb, "" if nb == 1 else "s", nx, "" if nx == 1 else "s"]
	var bits: PackedStringArray = []
	var ob: PackedStringArray = []
	for w in ["crystal", "titanium", "iron", "rock"]:
		if ores.has(w):
			ob.append("%d %s" % [int(ores[w]), w])
	bits.append("%d cluster%s%s" % [nc, "" if nc == 1 else "s", (" (%s)" % ", ".join(ob)) if not ob.is_empty() else ""])
	bits.append("%d base%s" % [nb, "" if nb == 1 else "s"])
	bits.append("%d derelict%s left" % [nx, "" if nx == 1 else "s"])
	return ", ".join(bits)


static func danger_color(danger: int) -> Color:
	return ClusterGraph.danger_color(danger)


func _name_of(id: StringName) -> String:
	return _graph.name_of(id)


# --- Draw ---------------------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(H.VOID, 0.97))
	# Faint grid.
	var step := 60.0
	var x := fmod(size.x * 0.5, step)
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(H.HOLO, 0.035), 1.0)
		x += step
	var y := fmod(size.y * 0.5, step)
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(H.HOLO, 0.035), 1.0)
		y += step
	_graph.draw(self, selected)


## The forward station site in [param id] ({} at home and without one).
static func _station_site(id: StringName) -> Dictionary:
	return ClusterGraph.station_site(id)


## "Station: Eris Station (founded 1:00), bays 1/2, 3 structures; upkeep 40
## cr/min, water 2/min (ok)", "" without a station.
func station_text(id: StringName) -> String:
	var vm := hud.view_manager if hud else null
	var w := vm.world(id) if vm else null
	var site := _station_site(id)
	if id != ClusterNetwork.HOME_ID and site.is_empty():
		return ""
	var mgr := w.buildings if w else null
	var st := mgr.station_node() if mgr else null
	var text := "Station: %s" % (st.station_name if st else String(site.get("name", "Station")))
	if not site.is_empty():
		text += " (founded %s)" % Fmt.clock(float(site.get("founded_at", 0.0)))
	if mgr:
		text += ", bays %d/%d, %d structure%s" % [mgr.used_bays(), mgr.bay_count, mgr.buildings.size(), "" if mgr.buildings.size() == 1 else "s"]
	var supply := w.supply if w else null
	if supply:
		text += "; " + supply.status_text()
	return text + "."


func _gate_raids() -> GateRaidSource:
	return _graph.gate_raids()


# --- Info panel ---------------------------------------------------------------------------

func _fill_info() -> void:
	var id := selected
	if not _nodes.has(id):
		return
	var n: Dictionary = _nodes[id]
	var known := bool(n["known"])
	var home := id == ClusterNetwork.HOME_ID
	var e := Sector.network.entry(id)
	_title.text = _name_of(id) + ("  (home)" if home else "")
	var lines: PackedStringArray = []
	var via: Array = n.get("via", [])
	if home:
		lines.append("Your home system. %d gates." % Sector.system_def(id).gates.size() if Sector.system_def(id) else "Your home system.")
	else:
		if not via.is_empty():
			lines.append("Behind %s in %s, %d jump%s from home." % [via[1], _name_of(via[0]), e.depth, "" if e.depth == 1 else "s"])
		if known:
			var seen := Sector.seen_text(id)
			lines.append("Danger %d of 5. Surveyed, %s%s." % [e.danger, seen, " (stale)" if Sector.is_stale(id) else ""])
			lines.append("Charted: " + contents_text(id) + ".")
		else:
			lines.append("Uncharted: danger unknown, about %d this far out." % ExploreContract.danger_guess(id))
			var st := Sector.state(id)
			if st and not st.revealed.is_empty():
				lines.append("Partly charted: " + contents_text(id) + ".")
	var station := station_text(id)
	if not station.is_empty():
		lines.append(station)
	var ships := _ships_in(id) if not home else PackedStringArray()
	if not ships.is_empty():
		lines.append("Your ships there: " + ", ".join(ships) + ".")
	var tr := _in_transit(id)
	if tr > 0:
		lines.append("In the jump there: %d." % tr)
	for c in _contracts_for(id):
		var act := c.get_activity_text()
		lines.append("Explore contract, %s%s." % [c.get_reward_text(), (": " + act) if not act.is_empty() else ", open"])
	var g := _gate_raids()
	if g and g.is_warned() and StringName(g.pending["source"]) == id:
		lines.append(g.warning_text() + ".")
	_body.text = "\n".join(lines)
	var vm := hud.view_manager if hud else null
	_view.disabled = vm == null or not vm.can_view(id) or vm.viewed_id() == id
	_view.tooltip_text = "Switch the view to %s" % _name_of(id) if not _view.disabled else (
			"You are viewing it" if vm and vm.viewed_id() == id else "Only charted systems, or one your ship is in, can be viewed")
	_fill_post(id, via)
	_fill_dest(id)


## The shortcut: an explore contract on the charted gate that leads to
## [param id], at fair pay.
func _fill_post(id: StringName, via: Array) -> void:
	_post_from = &""
	_post_gate = ""
	_post.visible = id != ClusterNetwork.HOME_ID
	if not _post.visible:
		return
	var why := ""
	if via.is_empty():
		why = "No charted gate leads there"
	else:
		_post_from = via[0]
		_post_gate = via[1]
		var e := Sector.network.entry(id)
		_post_reward = ExploreContract.fair_for(maxi(e.depth if e else 1, 1), ExploreContract.danger_guess(id))
		why = ContractBoard.explore_problem(_post_from, _post_gate)
		if why.is_empty():
			why = ContractBoard.post_problem(_post_reward, true)
	_post.text = "Post explore contract (%s cr)" % Fmt.amount(_post_reward) if not via.is_empty() else "Post explore contract"
	_post.disabled = not why.is_empty()
	_post.tooltip_text = why if not why.is_empty() else "On %s in %s, fair pay, reserved now, paid when the explorer brings the survey home." % [_post_gate, _name_of(_post_from)]


func _on_view() -> void:
	var vm := hud.view_manager if hud else null
	if vm and vm.can_view(selected):
		vm.view(selected)
		close_map()


func _on_post() -> void:
	if _post_from.is_empty():
		return
	ContractBoard.post_explore(_post_from, _post_gate, _post_reward)
	_refresh()


## A mobile station (the selected one, or one parked or waiting at home)
## may fly to [param id]: the button views it and starts the site picker.
func _fill_dest(id: StringName) -> void:
	var ms := StationPanel.pick_mobile(get_tree(), hud.selection.selected if hud and hud.selection else null)
	_dest.visible = ms != null and id != ClusterNetwork.HOME_ID
	if not _dest.visible:
		return
	var why := ForwardStations.target_problem(get_tree(), id, ms)
	_dest.disabled = not why.is_empty()
	_dest.tooltip_text = why if not why.is_empty() else "View %s and click a planet there for %s" % [_name_of(id), ms.get_display_name()]


func _on_dest() -> void:
	var ms := StationPanel.pick_mobile(get_tree(), hud.selection.selected if hud and hud.selection else null)
	if ms == null or hud == null or hud.placement == null:
		return
	close_map()
	hud.placement.arm_site(ms, selected)

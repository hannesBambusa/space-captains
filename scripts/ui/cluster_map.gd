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
## Click a node: the info panel on the right with "View system" (when the
## view may switch there, ViewManager.can_view) and "Post explore contract"
## at fair pay (on the charted gate that leads there, when the board allows
## it: ContractBoard.explore_problem). A gate raid forming there that the
## player was warned of shows too.

const H := preload("res://scripts/ui/theme/hud_style.gd")
const NODE_R := 22.0
const HOME_R := 27.0
const COL_W := 300.0
const PANEL_W := 400.0
const REFRESH := 0.5
const STALE_ALPHA := 0.5

var hud: HUD
var selected: StringName = ClusterNetwork.HOME_ID

## Shown nodes: id -> {pos, known (bool), via: [from id, gate name] or []}.
var _nodes: Dictionary = {}
## [a, b, charted both ways (bool)].
var _links: Array = []
var _info: VBoxContainer
var _title: Label
var _body: Label
var _view: Button
var _post: Button
var _post_from: StringName = &""
var _post_gate := ""
var _post_reward := 0
var _timer := 0.0
var _f_name: Font
var _f_small: Font
var _f_mono: Font


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_f_name = H.font("SemiBold", true, false, 1)
	_f_small = H.font("Regular", false)
	_f_mono = H.mono("Medium")
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
	UIUtil.no_focus(self)


func setup(owner_hud: HUD) -> void:
	hud = owner_hud
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
	for id: StringName in _nodes:
		var r := HOME_R if id == ClusterNetwork.HOME_ID else NODE_R
		if mb.position.distance_to(_nodes[id]["pos"]) <= r + 8.0:
			selected = id
			_refresh()
			break
	accept_event()


# --- Graph ---------------------------------------------------------------------------

## True when [param id] has been surveyed (home always).
static func is_charted(id: StringName) -> bool:
	if id == ClusterNetwork.HOME_ID:
		return true
	var st := Sector.state(id)
	return st != null and st.known


## What the player knows of the network: charted systems and the systems
## behind their charted gates.
func _rebuild() -> void:
	_nodes.clear()
	_links.clear()
	var net := Sector.network
	if net == null:
		return
	var shown := {ClusterNetwork.HOME_ID: {"known": true, "via": []}}
	var ids: Array[StringName] = [ClusterNetwork.HOME_ID]
	ids.append_array(net.remote_ids())
	for id in ids:
		if not is_charted(id):
			continue
		shown[id] = {"known": true, "via": shown.get(id, {}).get("via", [])}
		var def := Sector.system_def(id)
		if def == null:
			continue
		for g in def.gates:
			if not Sector.is_revealed(id, g.name):
				continue
			var to: StringName = net.gate_target(id, g.name).get("system", &"")
			if to.is_empty():
				continue
			if not shown.has(to):
				shown[to] = {"known": is_charted(to), "via": [id, g.name]}
			elif (shown[to]["via"] as Array).is_empty() and to != ClusterNetwork.HOME_ID:
				shown[to]["via"] = [id, g.name]
			var dup := false
			for l in _links:
				if (l[0] == id and l[1] == to) or (l[0] == to and l[1] == id):
					l[2] = true
					dup = true
			if not dup:
				_links.append([id, to, false])
	# Columns by depth, rows in parent order.
	var cols: Dictionary = {}
	for id: StringName in shown:
		var d := net.depth(id) if id != ClusterNetwork.HOME_ID else 0
		if not cols.has(d):
			cols[d] = []
		(cols[d] as Array).append(id)
	var area := Rect2(Vector2(110.0, 120.0), Vector2(size.x - PANEL_W - 260.0, size.y - 240.0))
	var depths := cols.keys()
	depths.sort()
	var col_w := minf(COL_W, area.size.x / maxf(float(depths.size() - 1), 1.0))
	# Centred in the room left of the info panel.
	area.position.x += (area.size.x - col_w * float(depths.size() - 1)) * 0.5
	var row_of: Dictionary = {}
	for d: int in depths:
		var list: Array = cols[d]
		list.sort_custom(func(a: StringName, b: StringName) -> bool:
			var pa := float(row_of.get(_parent_in(a, shown), 0.0))
			var pb := float(row_of.get(_parent_in(b, shown), 0.0))
			return pa < pb if pa != pb else String(a) < String(b))
		for i in list.size():
			var y := area.position.y + area.size.y * (float(i) + 0.5) / float(list.size())
			row_of[list[i]] = y
			shown[list[i]]["pos"] = Vector2(area.position.x + col_w * float(d), y)
	_nodes = shown
	if not _nodes.has(selected):
		selected = ClusterNetwork.HOME_ID
	_refresh()


func _parent_in(id: StringName, shown: Dictionary) -> StringName:
	var e := Sector.network.entry(id)
	if e and shown.has(e.parent):
		return e.parent
	var via: Array = shown[id].get("via", [])
	return via[0] if not via.is_empty() else &""


func _refresh() -> void:
	if not visible:
		return
	queue_redraw()
	_fill_info()


# --- Data per node ---------------------------------------------------------------------

func _ships_in(id: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	var vm := hud.view_manager if hud else null
	var w := vm.world(id) if vm else null
	if w and id != ClusterNetwork.HOME_ID:
		for n in SystemWorld.nodes_in(w, Ship.GROUP):
			var s := n as Ship
			if s and not s.dead and s.faction == Combat.Faction.PLAYER and s.captain:
				out.append(s.captain.captain_name)
		return out
	var st := Sector.state(id)
	if st == null:
		return out
	var refs := SystemHost.known_refs(get_tree())
	for d: Dictionary in st.ships:
		if String(d.get("kind", "")) == ShipCodec.KIND_HIRED:
			var c := refs.captain(int(d.get("captain", 0)))
			out.append(c.captain_name if c else "a pilot")
	return out


func _in_transit(id: StringName) -> int:
	var n := 0
	for t: Dictionary in Sector.transits:
		if t["to"] == id and String((t["ship"] as Dictionary).get("kind", "")) == ShipCodec.KIND_HIRED:
			n += 1
	return n


func _contracts_for(id: StringName) -> Array[ExploreContract]:
	var out: Array[ExploreContract] = []
	for c in ContractBoard.contracts:
		var ec := c as ExploreContract
		if ec and ec.target_system == id:
			out.append(ec)
	return out


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
	var k := clampf(float(danger - 1) / 4.0, 0.0, 1.0)
	return H.HOLO.lerp(H.WARN, k * 2.0) if k < 0.5 else H.WARN.lerp(H.BAD, (k - 0.5) * 2.0)


func _name_of(id: StringName) -> String:
	if id == ClusterNetwork.HOME_ID:
		var w := hud.view_manager.home if hud and hud.view_manager else null
		return w.sys.system_def.system_name if w and w.sys and w.sys.system_def else "Home"
	var known: bool = _nodes.get(id, {}).get("known", false)
	var def := Sector.system_def(id)
	return def.system_name if def and known else "Unknown"


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
	for l in _links:
		if not _nodes.has(l[0]) or not _nodes.has(l[1]):
			continue
		var a: Vector2 = _nodes[l[0]]["pos"]
		var b: Vector2 = _nodes[l[1]]["pos"]
		var known := bool(_nodes[l[0]]["known"]) and bool(_nodes[l[1]]["known"])
		if known:
			draw_line(a, b, Color(H.HOLO, 0.55), 2.0, true)
		else:
			draw_dashed_line(a, b, Color(H.HOLO_DIM, 0.9), 1.5, 8.0)
		var n := _in_transit(l[1]) + _in_transit(l[0])
		if n > 0:
			draw_circle(a.lerp(b, 0.5), 5.0, H.role_color("Explorer"))
	for id: StringName in _nodes:
		_draw_node(id)


func _draw_node(id: StringName) -> void:
	var n: Dictionary = _nodes[id]
	var p: Vector2 = n["pos"]
	var home := id == ClusterNetwork.HOME_ID
	var r := HOME_R if home else NODE_R
	var known := bool(n["known"])
	var e := Sector.network.entry(id) if Sector.network else null
	var stale := not home and known and Sector.is_stale(id)
	var a := STALE_ALPHA if stale else 1.0
	var col := H.ACCENT if home else (danger_color(e.danger) if known and e else H.TEXT_FAINT)
	draw_circle(p, r + 6.0, Color(col, 0.08 * a))
	draw_circle(p, r, Color(H.PANEL_BG, 0.95))
	draw_arc(p, r, 0.0, TAU, 48, Color(col, 0.9 * a), 2.0, true)
	if id == selected:
		draw_arc(p, r + 6.0, 0.0, TAU, 48, H.ACCENT_SOFT, 2.0, true)
	var mid := "?" if not known else ("H" if home else str(e.danger if e else 0))
	var fs := 20
	var ms := _f_mono.get_string_size(mid, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(_f_mono, p + Vector2(-ms.x * 0.5, ms.y * 0.32), mid, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.lerp(Color.WHITE, 0.3), a))
	var lines: Array = []
	lines.append([_name_of(id).to_upper(), _f_name, 16, Color(H.TEXT_BRIGHT, a)])
	if not home:
		lines.append([Sector.danger_text(id), _f_small, 13, Color(H.TEXT_DIM, a)])
		if known or not (Sector.state(id).revealed.is_empty()):
			lines.append([contents_text(id, true), _f_small, 13, Color(H.TEXT_DIM, a)])
	var ly := p.y + r + 18.0
	for ln in lines:
		var f: Font = ln[1]
		var w := f.get_string_size(String(ln[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(ln[2])).x
		draw_string(f, Vector2(p.x - w * 0.5, ly), String(ln[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(ln[2]), ln[3])
		ly += float(ln[2]) + 4.0
	# Your ships there: a cyan badge.
	var ships := _ships_in(id).size() if not home else 0
	if ships > 0:
		var bp := p + Vector2(r * 0.75, -r * 0.75)
		draw_circle(bp, 9.0, H.role_color("Explorer"))
		var t := str(ships)
		var ts := _f_mono.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		draw_string(_f_mono, bp + Vector2(-ts.x * 0.5, 4.5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, H.VOID)
	# An open explore contract: an amber flag.
	if not _contracts_for(id).is_empty():
		var fp := p + Vector2(-r * 0.95, -r * 0.7)
		draw_line(fp, fp + Vector2(0, -26), H.ACCENT, 2.0)
		draw_colored_polygon(PackedVector2Array([fp + Vector2(0, -26), fp + Vector2(16, -20), fp + Vector2(0, -14)]), H.ACCENT)
	# A gate raid forming there (warned).
	var g := _gate_raids()
	if g and g.is_warned() and StringName(g.pending["source"]) == id:
		draw_arc(p, r + 11.0, 0.0, TAU, 48, Color(H.BAD, 0.6 + 0.4 * sin(Time.get_ticks_msec() / 200.0)), 2.0, true)


func _gate_raids() -> GateRaidSource:
	var w := hud.view_manager.home if hud and hud.view_manager else null
	return w.combat.gate_raids if w and w.combat else null


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

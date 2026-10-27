class_name ClusterGraph
extends RefCounted
## The gate network as far as the player knows it, laid out and drawn: the
## shared part of the full cluster map ([ClusterMap], M) and the minimap's
## CLUSTER mode ([Minimap]). Home and every charted system, and behind each
## charted gate the system it leads to ("?" until surveyed). Columns by
## jumps from home, rows in parent order. [member compact] draws the small
## version (smaller nodes, the name only, smaller badges).

const H := preload("res://scripts/ui/theme/hud_style.gd")
const STALE_ALPHA := 0.5

var hud: HUD
## Small nodes and labels for the minimap.
var compact := false
## Node radius (home, others), from [member compact].
var node_r := 22.0
var home_r := 27.0

## Shown nodes: id -> {pos, known (bool), via: [from id, gate name] or []}.
var nodes: Dictionary = {}
## [a, b, charted both ways (bool)].
var links: Array = []

var _f_name: Font
var _f_small: Font
var _f_mono: Font


func _init(owner_hud: HUD = null, small: bool = false) -> void:
	hud = owner_hud
	compact = small
	node_r = 9.0 if compact else 22.0
	home_r = 11.0 if compact else 27.0
	_f_name = H.font("SemiBold", true, false, 1)
	_f_small = H.font("Regular", false)
	_f_mono = H.mono("Medium")


func radius_of(id: StringName) -> float:
	return home_r if id == ClusterNetwork.HOME_ID else node_r


## The node within [param slack] px of its rim at [param pos], &"" if none.
func node_at(pos: Vector2, slack: float = 8.0) -> StringName:
	var best: StringName = &""
	var best_d := INF
	for id: StringName in nodes:
		var d := pos.distance_to(nodes[id]["pos"])
		if d <= radius_of(id) + slack and d < best_d:
			best_d = d
			best = id
	return best


# --- Graph ---------------------------------------------------------------------------

## True when [param id] has been surveyed (home always).
static func is_charted(id: StringName) -> bool:
	if id == ClusterNetwork.HOME_ID:
		return true
	var st := Sector.state(id)
	return st != null and st.known


## Rebuilds [member nodes] and [member links] from what the player knows,
## laid out in [param area]: columns at most [param max_col_w] apart,
## centred horizontally.
func rebuild(area: Rect2, max_col_w: float) -> void:
	nodes.clear()
	links.clear()
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
			for l in links:
				if (l[0] == id and l[1] == to) or (l[0] == to and l[1] == id):
					l[2] = true
					dup = true
			if not dup:
				links.append([id, to, false])
	# Columns by depth, rows in parent order.
	var cols: Dictionary = {}
	for id: StringName in shown:
		var d := net.depth(id) if id != ClusterNetwork.HOME_ID else 0
		if not cols.has(d):
			cols[d] = []
		(cols[d] as Array).append(id)
	var depths := cols.keys()
	depths.sort()
	var col_w := minf(max_col_w, area.size.x / maxf(float(depths.size() - 1), 1.0))
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
	nodes = shown


func _parent_in(id: StringName, shown: Dictionary) -> StringName:
	var e := Sector.network.entry(id)
	if e and shown.has(e.parent):
		return e.parent
	var via: Array = shown[id].get("via", [])
	return via[0] if not via.is_empty() else &""


# --- Data per node ---------------------------------------------------------------------

## Your pilots in [param id] (names; not counted at home).
func ships_in(id: StringName) -> PackedStringArray:
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
	if st == null or hud == null:
		return out
	var refs := SystemHost.known_refs(hud.get_tree())
	for d: Dictionary in st.ships:
		if String(d.get("kind", "")) == ShipCodec.KIND_HIRED:
			var c := refs.captain(int(d.get("captain", 0)))
			out.append(c.captain_name if c else "a pilot")
	return out


static func in_transit(id: StringName) -> int:
	var n := 0
	for t: Dictionary in Sector.transits:
		if t["to"] == id and String((t["ship"] as Dictionary).get("kind", "")) == ShipCodec.KIND_HIRED:
			n += 1
	return n


static func contracts_for(id: StringName) -> Array[ExploreContract]:
	var out: Array[ExploreContract] = []
	for c in ContractBoard.contracts:
		var ec := c as ExploreContract
		if ec and ec.target_system == id:
			out.append(ec)
	return out


## The forward station site in [param id] ({} at home and without one).
static func station_site(id: StringName) -> Dictionary:
	if id == ClusterNetwork.HOME_ID:
		return {}
	var st := Sector.state(id)
	return st.station if st else {}


func gate_raids() -> GateRaidSource:
	var w := hud.view_manager.home if hud and hud.view_manager else null
	return w.combat.gate_raids if w and w.combat else null


static func danger_color(danger: int) -> Color:
	var k := clampf(float(danger - 1) / 4.0, 0.0, 1.0)
	return H.HOLO.lerp(H.WARN, k * 2.0) if k < 0.5 else H.WARN.lerp(H.BAD, (k - 0.5) * 2.0)


func name_of(id: StringName) -> String:
	if id == ClusterNetwork.HOME_ID:
		var w := hud.view_manager.home if hud and hud.view_manager else null
		return w.sys.system_def.system_name if w and w.sys and w.sys.system_def else "Home"
	var known: bool = nodes.get(id, {}).get("known", false)
	var def := Sector.system_def(id)
	return def.system_name if def and known else "Unknown"


# --- Draw ---------------------------------------------------------------------------------

## Links, then every node, on [param ci]. [param selected] gets the amber
## ring, [param hovered] (compact) a faint one.
func draw(ci: CanvasItem, selected: StringName, hovered: StringName = &"") -> void:
	for l in links:
		if not nodes.has(l[0]) or not nodes.has(l[1]):
			continue
		var a: Vector2 = nodes[l[0]]["pos"]
		var b: Vector2 = nodes[l[1]]["pos"]
		var known := bool(nodes[l[0]]["known"]) and bool(nodes[l[1]]["known"])
		if known:
			ci.draw_line(a, b, Color(H.HOLO, 0.55), 1.0 if compact else 2.0, true)
		else:
			ci.draw_dashed_line(a, b, Color(H.HOLO_DIM, 0.9), 1.0 if compact else 1.5, 4.0 if compact else 8.0)
		var n := in_transit(l[1]) + in_transit(l[0])
		if n > 0:
			ci.draw_circle(a.lerp(b, 0.5), 2.5 if compact else 5.0, H.role_color("Explorer"))
	for id: StringName in nodes:
		_draw_node(ci, id, id == selected, id == hovered)


func _draw_node(ci: CanvasItem, id: StringName, is_selected: bool, is_hovered: bool) -> void:
	var n: Dictionary = nodes[id]
	var p: Vector2 = n["pos"]
	var home := id == ClusterNetwork.HOME_ID
	var r := radius_of(id)
	var known := bool(n["known"])
	var e := Sector.network.entry(id) if Sector.network else null
	var stale := not home and known and Sector.is_stale(id)
	var a := STALE_ALPHA if stale else 1.0
	var col := H.ACCENT if home else (danger_color(e.danger) if known and e else H.TEXT_FAINT)
	var halo := 3.0 if compact else 6.0
	ci.draw_circle(p, r + halo, Color(col, 0.08 * a))
	ci.draw_circle(p, r, Color(H.PANEL_BG, 0.95))
	ci.draw_arc(p, r, 0.0, TAU, 32 if compact else 48, Color(col, 0.9 * a), 1.5 if compact else 2.0, true)
	if is_selected:
		ci.draw_arc(p, r + halo, 0.0, TAU, 48, H.ACCENT_SOFT, 1.5 if compact else 2.0, true)
	elif is_hovered:
		ci.draw_arc(p, r + halo, 0.0, TAU, 48, Color(H.HOLO_SOFT, 0.7), 1.0, true)
	var mid := "?" if not known else ("H" if home else str(e.danger if e else 0))
	var fs := 12 if compact else 20
	var ms := _f_mono.get_string_size(mid, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	ci.draw_string(_f_mono, p + Vector2(-ms.x * 0.5, ms.y * 0.32), mid, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.lerp(Color.WHITE, 0.3), a))
	var site := station_site(id)
	if home or not site.is_empty():
		var ic := H.icon(&"station")
		if ic:
			var isz := 12.0 if compact else 20.0
			ci.draw_texture_rect(ic, Rect2(p + Vector2(-isz * 0.5, -r - isz - (2.0 if compact else 6.0)), Vector2(isz, isz)), false, H.HOLO)
	var lines: Array = []
	if compact:
		lines.append([name_of(id).to_upper(), _f_name, 12, Color(H.TEXT_BRIGHT if known else H.TEXT_DIM, a)])
	else:
		lines.append([name_of(id).to_upper(), _f_name, 16, Color(H.TEXT_BRIGHT, a)])
		if not site.is_empty():
			lines.append([String(site.get("name", "Station")), _f_small, 13, H.HOLO])
		if not home:
			lines.append([Sector.danger_text(id), _f_small, 13, Color(H.TEXT_DIM, a)])
			if known or not (Sector.state(id).revealed.is_empty()):
				lines.append([ClusterMap.contents_text(id, true), _f_small, 13, Color(H.TEXT_DIM, a)])
	var ly := p.y + r + (13.0 if compact else 18.0)
	for ln in lines:
		var f: Font = ln[1]
		var w := f.get_string_size(String(ln[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(ln[2])).x
		ci.draw_string(f, Vector2(p.x - w * 0.5, ly), String(ln[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(ln[2]), ln[3])
		ly += float(ln[2]) + 4.0
	# Your ships there: a cyan badge.
	var ships := ships_in(id).size() if not home else 0
	if ships > 0:
		var bp := p + Vector2(r * 0.75, -r * 0.75)
		var br := 6.0 if compact else 9.0
		var bfs := 10 if compact else 12
		ci.draw_circle(bp, br, H.role_color("Explorer"))
		var t := str(ships)
		var ts := _f_mono.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, bfs)
		ci.draw_string(_f_mono, bp + Vector2(-ts.x * 0.5, br * 0.5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, bfs, H.VOID)
	# An open explore contract: an amber flag.
	if not contracts_for(id).is_empty():
		var fp := p + Vector2(-r * 0.95, -r * 0.7)
		var fh := 12.0 if compact else 26.0
		ci.draw_line(fp, fp + Vector2(0, -fh), H.ACCENT, 1.0 if compact else 2.0)
		ci.draw_colored_polygon(PackedVector2Array([fp + Vector2(0, -fh), fp + Vector2(fh * 0.6, -fh * 0.77), fp + Vector2(0, -fh * 0.54)]), H.ACCENT)
	# A gate raid forming there (warned).
	var g := gate_raids()
	if g and g.is_warned() and StringName(g.pending["source"]) == id:
		ci.draw_arc(p, r + (6.0 if compact else 11.0), 0.0, TAU, 48, Color(H.BAD, 0.6 + 0.4 * sin(Time.get_ticks_msec() / 200.0)), 1.5 if compact else 2.0, true)

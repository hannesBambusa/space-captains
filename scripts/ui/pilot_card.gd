class_name PilotCard
extends Control
## One pilot in the roster (PilotRoster): a role-coloured initials emblem,
## the name, rank, wallet, the state as icon and text (with the last refusal
## while docked), the fitted modules (Mk I x3, 3/5 slots), and hull, shield
## and work bars (drilling, hold, repairs). Drawn in [method _draw] so 30+
## cards stay cheap; [method refresh] is called on a timer and only redraws
## when something shown changed. Red edge while in combat or just hit, amber
## edge when the hull is low. Click selects, double click also centres the
## camera.

signal clicked(card: PilotCard)
signal double_clicked(card: PilotCard)

const HEIGHT := 68.0
## Two-row card for the right-hand pilot list.
const COMPACT_HEIGHT := 22.0
const BADGE := 42.0
const H := preload("res://scripts/ui/theme/hud_style.gd")
## Seconds after a hit the card still counts as "in combat".
const HIT_WINDOW := 5.0

var captain: Captain
## The ship, or the home building for a captain waiting for a ship.
var target: Node3D
var fleet_tag := ""
## Two rows: badge, name, wallet; state, tiny hull and shield bars.
var compact := false:
	set(v):
		compact = v
		custom_minimum_size.y = COMPACT_HEIGHT if v else HEIGHT
		queue_redraw()
var selected := false:
	set(v):
		if selected != v:
			selected = v
			queue_redraw()

var _hover := false
var _data: Dictionary = {}
var _combat := false
var _pulse := 0.0

static var _f_name: Font
static var _f_small: Font
static var _f_num: Font
static var _f_badge: Font
static var _f_tag: Font


func _init() -> void:
	custom_minimum_size = Vector2(0.0, HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE
	set_process(false)
	if _f_name == null:
		_f_name = H.font("SemiBold")
		_f_small = H.font("Medium")
		_f_num = H.mono("Medium")
		_f_badge = H.font("Bold", true, false, 1)
		_f_tag = H.font("SemiBold", true, false, 1)
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())


func bind(c: Captain, t: Node3D) -> void:
	captain = c
	target = t
	_data.clear()
	refresh()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		if mb.double_click:
			double_clicked.emit(self)
		else:
			clicked.emit(self)
		accept_event()


func _process(delta: float) -> void:
	_pulse += delta
	queue_redraw()


## Reads the captain and ship; redraws when anything shown changed.
func refresh() -> void:
	if captain == null:
		return
	var ship := captain.ship if is_instance_valid(captain.ship) and not captain.ship.dead else null
	var d := {}
	d["name"] = captain.captain_name
	d["role"] = captain.role
	d["rank"] = captain.rank
	d["wallet"] = captain.wallet
	d["fleet"] = fleet_tag
	var look := state_look(ship)
	d["icon"] = look["icon"]
	d["scol"] = look["color"]
	d["state"] = status_text(captain, ship)
	d["refused"] = ship != null and ship.brain != null and not ship.brain.last_refusal.is_empty() and \
			(ship.brain.state == CaptainBrain.State.DOCKED or ship.brain.state == CaptainBrain.State.EVALUATING)
	if ship:
		d["hull"] = snappedf(ship.hull_fraction(), 0.01)
		d["shield"] = snappedf(ship.shield_fraction(), 0.01) if ship.durability.max_shields > 0.0 else -1.0
		var w := work_progress(ship)
		d["work"] = snappedf(w.x, 0.01)
		d["work_kind"] = int(w.y)
		var lo := ship.loadout
		d["mods"] = _modules_text(lo)
		d["slots"] = "%d/%d" % [lo.upgrades_fitted(), lo.unlocked_slots] if lo else ""
	else:
		d["hull"] = -1.0
		d["shield"] = -1.0
		d["work"] = -1.0
		d["work_kind"] = 0
		d["mods"] = ""
		d["slots"] = ""
	var combat := ship != null and ship.brain != null and (ship.brain.state == CaptainBrain.State.ENGAGING or ship.brain.state == CaptainBrain.State.FLEEING \
			or ship.durability.seconds_since_hit() < HIT_WINDOW)
	d["combat"] = combat
	if combat != _combat:
		_combat = combat
		set_process(combat)
	if d != _data:
		_data = d
		tooltip_text = _tooltip(ship)
		queue_redraw()


func in_combat() -> bool:
	return _combat


func is_damaged() -> bool:
	return float(_data.get("hull", 1.0)) >= 0.0 and float(_data.get("hull", 1.0)) < 0.5


# --- Text ---------------------------------------------------------------------

## Live status for the card: the ship's own text, the belt while mining,
## "Waiting for a ship" while stranded, "In Ostra" while away as data, the
## refusal while docked.
static func status_text(c: Captain, ship: Ship) -> String:
	if ship == null:
		# On a gate trip, as data (GateTransit): where it is.
		if not c.away_in.is_empty() and not c.stranded and c.alive:
			return "In %s" % c.away_in
		return "Waiting for a ship" if c.stranded or not is_instance_valid(c.ship) else "Lost"
	var br := ship.brain
	var text := ship.get_status_text()
	if br and br.state == CaptainBrain.State.MINING and br.trip and br.trip.contract and ship.warp_status_text().is_empty() and not (ship is LanderShip):
		text = "Mining at %s" % br.trip.contract.get_target_name()
	if br and not br.last_refusal.is_empty() and (br.state == CaptainBrain.State.DOCKED or br.state == CaptainBrain.State.EVALUATING):
		text += ": " + br.last_refusal.to_lower()
	return text


## (progress 0..1 or -1, kind) kind: 1 drilling, 2 hold, 3 repairs.
static func work_progress(ship: Ship) -> Vector2:
	var br := ship.brain
	if br and br.trip and br.state == CaptainBrain.State.MINING:
		return Vector2(br.trip.progress, 1)
	if br and br.state == CaptainBrain.State.REPAIRING:
		return Vector2(ship.hull_fraction(), 3)
	var miner := ship as MinerShip
	if miner and miner.hold_fill > 0.0:
		return Vector2(miner.hold_fill, 2)
	return Vector2(-1.0, 0)


## "Mk II x1  Mk I x2" (bought modules by tier), "Stock" when none.
static func _modules_text(lo: ShipLoadout) -> String:
	if lo == null:
		return ""
	var counts := [0, 0, 0, 0]
	for m in lo.modules():
		counts[clampi(m.tier, 0, 3)] += 1
	var parts: PackedStringArray = []
	for tier in [3, 2, 1]:
		if counts[tier] > 0:
			parts.append("%s x%d" % [ShipModule.TIER_NAMES[tier].to_upper(), counts[tier]])
	return "  ".join(parts) if not parts.is_empty() else "STOCK"


func _tooltip(ship: Ship) -> String:
	var c := captain
	var names: PackedStringArray = []
	for id in c.trait_ids():
		names.append(CaptainTraits.trait_name(id))
	var lines: PackedStringArray = []
	lines.append("%s, %s %s" % [c.captain_name, c.get_rank_name(), c.role.to_lower()])
	lines.append("%s: %s" % [c.get_personality_name(), c.get_personality_hint()])
	lines.append("%d reputation, wallet %s cr" % [roundi(c.reputation), UIUtil.amount(c.wallet)])
	if not names.is_empty():
		lines.append("Traits: " + ", ".join(names))
	if ship:
		lines.append("Hull %d / %d, shields %d / %d" % [roundi(ship.durability.hull), roundi(ship.durability.max_hull),
				roundi(ship.durability.shields), roundi(ship.durability.max_shields)])
		if ship.loadout:
			var mods: PackedStringArray = []
			for m in ship.loadout.modules():
				if m.tier >= 1:
					mods.append("%s %s" % [m.get_tier_name(), m.display_name])
			lines.append("Modules: %s (%d of %d slots)" % [", ".join(mods) if not mods.is_empty() else "stock fittings", ship.loadout.upgrades_fitted(), ship.loadout.unlocked_slots])
		if is_instance_valid(ship.home):
			lines.append("Home: %s" % ship.home.display_name)
		if ship.brain and ship.brain.trip and ship.brain.trip.contract:
			lines.append("Contract: %s, %s" % [ship.brain.trip.contract.get_target_name(), ship.brain.trip.contract.get_reward_text()])
	if not fleet_tag.is_empty():
		lines.append(fleet_tag)
	lines.append("Click: select    Double click: centre the camera")
	return "\n".join(lines)


# --- Look -----------------------------------------------------------------------

## Icon and colour for a pilot's state (CaptainBrain.State), with the
## overrides that matter more than the state (warping, refusing).
static func state_look(ship: Ship) -> Dictionary:
	if ship == null or not is_instance_valid(ship) or ship.brain == null:
		return {"icon": &"st_waiting", "color": H.TEXT_DIM}
	if not ship.warp_status_text().is_empty():
		return {"icon": &"st_warp", "color": H.SHIELD}
	var travel := Color(0.7, 0.85, 1.0)
	match ship.brain.state:
		CaptainBrain.State.DOCKED:
			if not ship.brain.last_refusal.is_empty():
				return {"icon": &"st_refuse", "color": H.WARN}
			return {"icon": &"st_docked", "color": H.TEXT_DIM}
		CaptainBrain.State.IDLE:
			return {"icon": &"st_idle", "color": H.TEXT_DIM}
		CaptainBrain.State.EVALUATING:
			return {"icon": &"st_think", "color": H.TEXT}
		CaptainBrain.State.UNDOCKING:
			return {"icon": &"st_undock", "color": H.TEXT}
		CaptainBrain.State.TRAVELING_TO_JOB:
			return {"icon": &"st_travel", "color": travel}
		CaptainBrain.State.MINING:
			return {"icon": &"st_mining", "color": H.ROLE_COLORS["Miner"]}
		CaptainBrain.State.RETURNING:
			return {"icon": &"st_return", "color": travel}
		CaptainBrain.State.DOCKING:
			return {"icon": &"st_docked", "color": H.TEXT}
		CaptainBrain.State.UNLOADING:
			return {"icon": &"st_unload", "color": H.GOOD}
		CaptainBrain.State.RESTING:
			return {"icon": &"st_rest", "color": H.TEXT_DIM}
		CaptainBrain.State.FLEEING:
			return {"icon": &"st_flee", "color": H.BAD}
		CaptainBrain.State.PATROLLING:
			return {"icon": &"st_patrol", "color": Color(0.62, 0.8, 1.0)}
		CaptainBrain.State.ENGAGING:
			return {"icon": &"st_combat", "color": H.BAD}
		CaptainBrain.State.ESCORTING:
			return {"icon": &"st_escort", "color": Color(0.62, 0.8, 1.0)}
		CaptainBrain.State.HUNTING:
			return {"icon": &"st_hunt", "color": H.WARN}
		CaptainBrain.State.REPAIRING:
			return {"icon": &"st_repair", "color": H.WARN}
		CaptainBrain.State.DESTROYED:
			return {"icon": &"st_lost", "color": H.BAD}
		CaptainBrain.State.SURVEYING:
			return {"icon": &"role_explorer", "color": H.ROLE_COLORS["Explorer"]}
		CaptainBrain.State.WAITING_ESCORT:
			return {"icon": &"st_waiting", "color": H.WARN}
	return {"icon": &"st_idle", "color": H.TEXT_DIM}


func _draw() -> void:
	if _data.is_empty():
		return
	if compact:
		_draw_compact()
		return
	var w := size.x
	var role_col := H.role_color(String(_data["role"]))
	var style := get_theme_stylebox(&"pressed" if selected else (&"hover" if _hover else &"normal"), &"CardButton")
	draw_style_box(style, Rect2(Vector2.ZERO, size))
	# Left edge: role colour, red while fighting (pulsing), amber when damaged.
	var edge := role_col
	if _combat:
		edge = H.BAD.lerp(Color(1, 0.75, 0.6), 0.5 + 0.5 * sin(_pulse * 7.0))
		draw_rect(Rect2(1, 1, w - 2, size.y - 2), Color(H.BAD, 0.06 + 0.04 * sin(_pulse * 7.0)))
		draw_rect(Rect2(0.5, 0.5, w - 9, size.y - 1), Color(H.BAD, 0.55), false, 1.0)
	elif is_damaged():
		edge = H.WARN
	draw_rect(Rect2(0, 0, 3, size.y), edge)

	# Emblem: chamfered square with initials.
	var b := Rect2(12, (size.y - BADGE) * 0.5, BADGE, BADGE)
	var cutv := 9.0
	var pts := PackedVector2Array([b.position, Vector2(b.end.x - cutv, b.position.y), Vector2(b.end.x, b.position.y + cutv), b.end, Vector2(b.position.x, b.end.y)])
	draw_colored_polygon(pts, Color(role_col.darkened(0.72), 0.95))
	var loop := pts.duplicate()
	loop.append(pts[0])
	draw_polyline(loop, Color(role_col, 0.85), 1.0)
	var ini := H.initials(String(_data["name"]))
	var isz := _f_badge.get_string_size(ini, HORIZONTAL_ALIGNMENT_LEFT, -1, 19)
	draw_string(_f_badge, Vector2(b.position.x + (BADGE - isz.x) * 0.5, b.position.y + 26), ini, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, role_col.lerp(Color.WHITE, 0.35))
	var ric := H.icon(H.role_icon(String(_data["role"])))
	if ric:
		draw_texture_rect(ric, Rect2(b.position.x + 3, b.end.y - 14, 11, 11), false, Color(role_col, 0.9))
	# Rank tag under the initials.
	var rank := int(_data["rank"])
	var rtxt := Reputation.RANK_BADGES[clampi(rank, 0, Reputation.RANK_BADGES.size() - 1)]
	var rcol: Color = Reputation.RANK_COLORS[clampi(rank, 0, Reputation.RANK_COLORS.size() - 1)]
	draw_string(_f_tag, Vector2(b.end.x - 20, b.end.y - 3), rtxt, HORIZONTAL_ALIGNMENT_RIGHT, 18, 10, Color(rcol, 0.95))

	var x0 := b.end.x + 12.0
	var right := w - 12.0
	# Row 1: name, fleet tag, wallet.
	var wallet := UIUtil.amount(int(_data["wallet"]))
	var wsz := _f_num.get_string_size(wallet, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	var wx := right - wsz.x
	draw_string(_f_num, Vector2(wx, 21), wallet, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, H.CREDITS)
	var wic := H.icon(&"credits")
	if wic:
		draw_texture_rect(wic, Rect2(wx - 16, 9, 13, 13), false, Color(H.CREDITS, 0.8))
	var name_right := wx - 22.0
	if not String(_data["fleet"]).is_empty():
		var ftxt := "FLEET"
		var fsz := _f_tag.get_string_size(ftxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
		var fr := Rect2(name_right - fsz.x - 10, 9, fsz.x + 8, 14)
		draw_rect(fr, Color(1.0, 0.85, 0.42, 0.16))
		draw_rect(fr, Color(1.0, 0.85, 0.42, 0.7), false, 1.0)
		draw_string(_f_tag, Vector2(fr.position.x + 4, 20), ftxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.88, 0.5))
		name_right = fr.position.x - 6
	draw_string(_f_name, Vector2(x0, 21), _fit(_f_name, String(_data["name"]), 16, name_right - x0), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, H.TEXT_BRIGHT)

	# Row 2: state icon and text, modules on the right.
	var mods := String(_data["mods"])
	var slots := String(_data["slots"])
	var mods_w := 0.0
	if not mods.is_empty():
		var stxt := slots
		var ssz := _f_tag.get_string_size(stxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		var msz := _f_tag.get_string_size(mods, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		var mx := right - ssz.x - msz.x - 7.0
		draw_string(_f_tag, Vector2(mx, 40), mods, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, H.TEXT if mods != "STOCK" else H.TEXT_FAINT)
		draw_string(_f_tag, Vector2(right - ssz.x, 40), stxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, H.TEXT_FAINT)
		var mic := H.icon(&"module")
		if mic:
			draw_texture_rect(mic, Rect2(mx - 15, 29, 12, 12), false, Color(H.TEXT_DIM, 0.8))
		mods_w = ssz.x + msz.x + 22.0
	var scol: Color = _data["scol"]
	var sic := H.icon(StringName(_data["icon"]))
	if sic:
		draw_texture_rect(sic, Rect2(x0, 28, 14, 14), false, scol)
	var tcol := H.WARN if bool(_data["refused"]) else scol.lerp(H.TEXT, 0.45)
	var text_w := right - mods_w - x0 - 19
	var work := float(_data["work"])
	var pct := ""
	if work >= 0.0:
		pct = "%s %d%%" % [["", "DRILL", "HOLD", "REPAIR"][int(_data["work_kind"])], roundi(work * 100.0)]
		text_w -= _f_tag.get_string_size(pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 8.0
	var st := _fit(_f_small, String(_data["state"]), 14, text_w)
	draw_string(_f_small, Vector2(x0 + 19, 40), st, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, tcol)
	if not pct.is_empty():
		var wcol := H.ACCENT_SOFT if int(_data["work_kind"]) != 3 else H.WARN
		var sx := x0 + 19 + _f_small.get_string_size(st, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 8.0
		draw_string(_f_tag, Vector2(sx, 40), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, wcol)
		# Thin progress line under the state.
		var lw := right - mods_w - x0
		draw_rect(Rect2(x0, 44, lw, 2), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(x0, 44, lw * clampf(work, 0.0, 1.0), 2), wcol)

	# Row 3: hull and shield bars.
	var by := 52.0
	var avail := right - x0
	var hull := float(_data["hull"])
	if hull < 0.0:
		draw_string(_f_tag, Vector2(x0, by + 7), "NO SHIP", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, H.TEXT_FAINT)
		return
	var seg := (avail - 12.0) / 2.0
	_bar(Vector2(x0, by), seg, "HULL", hull, H.hull_color(hull))
	var sh := float(_data["shield"])
	_bar(Vector2(x0 + seg + 12, by), seg, "SHLD", maxf(sh, 0.0), H.SHIELD, sh < 0.0)


func _bar(at: Vector2, width: float, label: String, value: float, color: Color, empty: bool = false) -> void:
	var lw := 32.0
	draw_string(_f_tag, Vector2(at.x, at.y + 8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, H.TEXT_FAINT)
	var r := Rect2(at.x + lw, at.y + 2, width - lw, 5)
	draw_rect(r, Color(0, 0, 0, 0.55))
	if not empty:
		draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(value, 0.0, 1.0), r.size.y)), color)
	# Tick marks every quarter: reads like a gauge.
	for i in range(1, 4):
		var tx := r.position.x + r.size.x * float(i) * 0.25
		draw_line(Vector2(tx, r.position.y), Vector2(tx, r.end.y), Color(0, 0, 0, 0.6), 1.0)


## [param text] cut to [param max_w] pixels with an ellipsis.
static func _fit(f: Font, text: String, fsize: int, max_w: float) -> String:
	if max_w <= 8.0:
		return ""
	if f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x <= max_w:
		return text
	var lo := 0
	var hi := text.length()
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if f.get_string_size(text.left(mid) + "...", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x <= max_w:
			lo = mid
		else:
			hi = mid - 1
	return text.left(lo).strip_edges() + "..."


## One row over open space: no box, outlined text. Left tick: red
## (pulsing) in combat, amber when damaged. Hover lifts a faint strip,
## selection an amber one.
func _draw_compact() -> void:
	var w := size.x
	var hgt := size.y
	var mid := hgt * 0.5
	var role_col := H.role_color(String(_data["role"]))
	if selected:
		draw_rect(Rect2(0, 0, w, hgt), Color(H.ACCENT, 0.16))
		draw_rect(Rect2(0, hgt - 1, w, 1), Color(H.ACCENT, 0.7))
	elif _hover:
		draw_rect(Rect2(0, 0, w, hgt), Color(H.HOLO, 0.08))
	if _combat:
		draw_rect(Rect2(0, 2, 2, hgt - 4), H.BAD.lerp(Color(1, 0.8, 0.7), 0.5 + 0.5 * sin(_pulse * 7.0)))
	elif is_damaged():
		draw_rect(Rect2(0, 2, 2, hgt - 4), H.WARN)
	# Small role badge.
	var bs := 15.0
	var b := Rect2(6, mid - bs * 0.5, bs, bs)
	var pts := PackedVector2Array([b.position, Vector2(b.end.x - 4, b.position.y), Vector2(b.end.x, b.position.y + 4), b.end, Vector2(b.position.x, b.end.y)])
	draw_colored_polygon(pts, Color(role_col.darkened(0.6), 0.85))
	var ric := H.icon(H.role_icon(String(_data["role"])))
	if ric:
		draw_texture_rect(ric, b.grow(-2.5), false, role_col.lerp(Color.WHITE, 0.25))
	var base := mid + 4.5
	var x := b.end.x + 6.0
	var right := w - 4.0
	# Wallet, right, dim.
	var wallet := UIUtil.amount(int(_data["wallet"]))
	var wsz := _f_num.get_string_size(wallet, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	_text(_f_num, Vector2(right - wsz.x, base - 0.5), wallet, 11, Color(H.CREDITS, 0.7))
	var coin := H.icon(&"credits_small")
	if coin:
		draw_texture_rect(coin, Rect2(right - wsz.x - 11.0, base - 9.0, 9.0, 9.0), false, Color(H.CREDITS, 0.7))
	right -= 52.0
	# Hull over shield, tiny, inline.
	var bar_w := 30.0
	var bx := right - bar_w
	var hull := float(_data["hull"])
	if hull >= 0.0:
		draw_rect(Rect2(bx - 1, mid - 3, bar_w + 2, 7), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(bx, mid - 2, bar_w * clampf(hull, 0.0, 1.0), 2), H.hull_color(hull))
		var sh := float(_data["shield"])
		if sh > 0.0:
			draw_rect(Rect2(bx, mid + 1, bar_w * clampf(sh, 0.0, 1.0), 2), H.SHIELD)
	right = bx - 8.0
	# Name: tinted when fighting or damaged.
	var name_col := H.TEXT_BRIGHT
	if _combat:
		name_col = Color(1.0, 0.72, 0.66)
	elif is_damaged():
		name_col = Color(1.0, 0.88, 0.6)
	var name_w := minf(_f_name.get_string_size(String(_data["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, 112.0)
	var nm := _fit(_f_name, String(_data["name"]), 13, name_w + 1.0)
	_text(_f_name, Vector2(x, base), nm, 13, name_col)
	x += 116.0
	if not String(_data["fleet"]).is_empty():
		var fic := H.icon(&"fleet")
		if fic:
			draw_texture_rect(fic, Rect2(x - 14, mid - 5, 10, 10), false, Color(1.0, 0.85, 0.42))
	# State icon and short text.
	var scol: Color = _data["scol"]
	var sic := H.icon(StringName(_data["icon"]))
	if sic:
		draw_texture_rect(sic, Rect2(x, mid - 5.5, 11, 11), false, scol)
	x += 15.0
	var work := float(_data["work"])
	var pct := " %d%%" % roundi(work * 100.0) if work >= 0.0 else ""
	var pw := _f_tag.get_string_size(pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x if not pct.is_empty() else 0.0
	var tcol := H.WARN if bool(_data["refused"]) else scol.lerp(H.TEXT, 0.5)
	var st := _fit(_f_small, String(_data["state"]), 12, right - x - pw)
	_text(_f_small, Vector2(x, base - 0.5), st, 12, tcol)
	if not pct.is_empty():
		var px := x + _f_small.get_string_size(st, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		_text(_f_tag, Vector2(px, base - 0.5), pct, 11, H.ACCENT_SOFT if int(_data["work_kind"]) != 3 else H.WARN)


## Text with a soft dark outline, legible over space.
func _text(f: Font, at: Vector2, text: String, fsize: int, color: Color) -> void:
	if text.is_empty():
		return
	draw_string_outline(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 3, Color(0, 0, 0, 0.75))
	draw_string(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)

class_name FleetRow
extends Control
## A fleet line in the compact pilot list (PilotRoster): the fleet icon and
## "FLEET" in the fleet's accent, the bounty target, the state ("forming 3/5",
## "en route", "engaging", "breaking off") and the fleet's mean hull on the
## right. Its members hang under it as indented [PilotCard]s with a tree line
## in the same colour. Drawn in [method _draw]; [method refresh] runs on the
## roster's timer and redraws only when something shown changed, so the row
## (and its tooltip) stays put while the fleet changes. Click selects the
## target and centres the camera on it, right click centres it on the
## leader; both keep the zoom.

signal clicked(row: FleetRow)
signal right_clicked(row: FleetRow)

const HEIGHT := 22.0
const H := preload("res://scripts/ui/theme/hud_style.gd")

var fleet: MercFleet
var accent := Color(1.0, 0.85, 0.42)
## "[Ostra]" for a fleet of a forward station.
var system_tag := ""

var _hover := false
var _data: Dictionary = {}

static var _f_name: Font
static var _f_small: Font
static var _f_tag: Font


func _init() -> void:
	custom_minimum_size = Vector2(0.0, HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE
	if _f_name == null:
		_f_name = H.font("SemiBold")
		_f_small = H.font("Medium")
		_f_tag = H.font("SemiBold", true, false, 1)
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())


func bind(f: MercFleet) -> void:
	fleet = f
	_data.clear()
	refresh()


## The leader ship (the first member), or null.
func leader_ship() -> Ship:
	if fleet == null:
		return null
	if is_instance_valid(fleet.leader) and not fleet.leader.dead:
		return fleet.leader
	for m in fleet.members:
		if is_instance_valid(m) and not m.dead:
			return m
	return null


## The bounty target while it is still there, or null.
func target() -> Node3D:
	if fleet == null or fleet.contract == null:
		return null
	var t := fleet.contract.target
	return t if is_instance_valid(t) and t.is_inside_tree() else null


## "forming 3/5", "en route", "engaging", "breaking off".
static func state_text(f: MercFleet) -> String:
	var s := MercFleet.STATE_NAMES[int(f.state)]
	if f.state == MercFleet.State.FORMING:
		s += " %d/%d" % [f.members.size(), f.wanted]
	return s


static func state_color(f: MercFleet) -> Color:
	match f.state:
		MercFleet.State.FORMING:
			return Color(1.0, 0.88, 0.5)
		MercFleet.State.EN_ROUTE:
			return Color(0.7, 0.85, 1.0)
		MercFleet.State.ENGAGING:
			return H.BAD
		MercFleet.State.RETREATING:
			return H.WARN
	return H.TEXT_DIM


## Mean hull fraction of the living members (-1 without any).
func mean_hull() -> float:
	var sum := 0.0
	var n := 0
	for m in fleet.members:
		if is_instance_valid(m) and not m.dead:
			sum += m.hull_fraction()
			n += 1
	return sum / float(n) if n > 0 else -1.0


func refresh() -> void:
	if fleet == null:
		return
	var d := {}
	d["target"] = fleet.contract.get_target_name() if fleet.contract else "?"
	d["state"] = state_text(fleet)
	d["scol"] = state_color(fleet)
	d["n"] = fleet.members.size()
	d["hull"] = snappedf(mean_hull(), 0.01)
	d["tag"] = system_tag
	d["accent"] = accent
	if d != _data:
		_data = d
		# Stable key: the text is read live (see PilotCard.refresh).
		tooltip_text = "fleet"
		queue_redraw()


func _make_custom_tooltip(_for_text: String) -> Object:
	return RichTooltip.live_label(_tooltip)


func _tooltip() -> String:
	if fleet == null:
		return ""
	var lines: PackedStringArray = []
	lines.append("%s's fleet for %s%s" % [fleet.leader_name, fleet.contract.get_target_name() if fleet.contract else "?",
			(" " + system_tag) if not system_tag.is_empty() else ""])
	lines.append("%s, %d ship%s (%d wanted)" % [MercFleet.STATE_NAMES[int(fleet.state)].capitalize(), fleet.members.size(),
			"" if fleet.members.size() == 1 else "s", fleet.wanted])
	if fleet.contract:
		lines.append("Bounty %s" % fleet.contract.get_reward_text())
	var names: PackedStringArray = []
	for m in fleet.members:
		if is_instance_valid(m):
			names.append(m.get_display_name() + (" (leader)" if m == fleet.leader else ""))
	if not names.is_empty():
		lines.append("Members: " + ", ".join(names))
	lines.append("Click: select the target    Right click: camera to the fleet")
	return "\n".join(lines)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or (mb.button_index != MOUSE_BUTTON_LEFT and mb.button_index != MOUSE_BUTTON_RIGHT):
		return
	accept_event()
	if not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		right_clicked.emit(self)
	else:
		clicked.emit(self)


func _draw() -> void:
	if _data.is_empty():
		return
	var w := size.x
	var hgt := size.y
	var mid := hgt * 0.5
	var base := mid + 4.5
	if _hover:
		draw_rect(Rect2(0, 0, w, hgt), Color(H.HOLO, 0.08))
	# Accent strip and a faint wash: the fleet's colour.
	draw_rect(Rect2(0, 0, w, hgt), Color(accent, 0.07))
	draw_rect(Rect2(0, 2, 2, hgt - 4), accent)
	# Tree root: the line the members hang from.
	draw_line(Vector2(10, mid + 6.0), Vector2(10, hgt), Color(accent, 0.55), 1.0)
	var fic := H.icon(&"fleet")
	if fic:
		draw_texture_rect(fic, Rect2(4, mid - 6, 12, 12), false, accent)
	var x := 22.0
	var right := w - 4.0
	# Mean hull, where the cards have theirs.
	var hull := float(_data["hull"])
	var bar_w := 30.0
	var bx := right - 52.0 - bar_w
	if hull >= 0.0:
		draw_rect(Rect2(bx - 1, mid - 2, bar_w + 2, 4), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(bx, mid - 1, bar_w * clampf(hull, 0.0, 1.0), 2), H.hull_color(hull))
	var n := "%d SHIP%s" % [int(_data["n"]), "" if int(_data["n"]) == 1 else "S"]
	var nsz := _f_tag.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	_text(_f_tag, Vector2(right - nsz.x, base - 0.5), n, 11, Color(accent, 0.8))
	right = bx - 8.0
	_text(_f_tag, Vector2(x, base), "FLEET", 11, accent)
	x += _f_tag.get_string_size("FLEET", HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 7.0
	var tag := String(_data["tag"])
	if not tag.is_empty():
		_text(_f_tag, Vector2(x, base), tag, 11, H.ACCENT_SOFT)
		x += _f_tag.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 4.0
	# The state always shows, the target name gives way. The separator dot
	# is drawn (the UI font has no middle dot).
	var st := String(_data["state"])
	var ssz := _f_small.get_string_size(st, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var tname := PilotCard._fit(_f_name, String(_data["target"]), 13, right - x - ssz - 14.0)
	_text(_f_name, Vector2(x, base), tname, 13, H.TEXT_BRIGHT)
	x += _f_name.get_string_size(tname, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 6.0
	draw_circle(Vector2(x + 1.5, mid + 0.5), 2.2, Color(0, 0, 0, 0.75))
	draw_circle(Vector2(x + 1.5, mid + 0.5), 1.3, H.TEXT_DIM)
	x += 8.0
	_text(_f_small, Vector2(x, base - 0.5), PilotCard._fit(_f_small, st, 12, right - x), 12, _data["scol"])


func _text(f: Font, at: Vector2, text: String, fsize: int, color: Color) -> void:
	if text.is_empty():
		return
	draw_string_outline(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 3, Color(0, 0, 0, 0.75))
	draw_string(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)

class_name BuildTile
extends Button
## One square build bar tile: the structure's rendered icon
## (assets/ui/icons/build/<id>.png, a drawn placeholder glyph while it is
## missing), its name, a hotkey badge, the built count against the limit
## and a compact cost line. States: ready, unaffordable (dimmed, the short
## resource in red), locked (limit reached or no free bay: a lock), placing
## (lit amber, pulsing edge). The rich tooltip is [BuildInfoCard], shown by
## the [BuildMenu] on hover.

enum State { READY, UNAFFORDABLE, LOCKED, PLACING }

const SIZE := Vector2(100.0, 118.0)
const ICON_PX := 62.0
const H := preload("res://scripts/ui/theme/hud_style.gd")

var def: BuildingDef
## Set for the defence zone tool (no BuildingDef).
var tool_id: StringName = &""
var title := ""
var hotkey := ""
var glyph: StringName = &"build"
var state: State = State.READY:
	set(v):
		if state != v:
			state = v
			set_process(v == State.PLACING)
			queue_redraw()
## "2/4" (built of the limit), "" without a limit.
var count_text := "":
	set(v):
		if count_text != v:
			count_text = v
			queue_redraw()
## Per cost entry: {icon, text, short (bool)}.
var costs: Array[Dictionary] = []

var _icon: Texture2D
var _pulse := 0.0

static var _f_name: Font
static var _f_cost: Font
static var _f_key: Font


func _init() -> void:
	custom_minimum_size = SIZE
	focus_mode = Control.FOCUS_NONE
	toggle_mode = true
	theme_type_variation = &"BuildTile"
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	set_process(false)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if _f_name == null:
		_f_name = H.font("SemiBold", true, false, 0)
		_f_cost = H.font("SemiBold", true, true)
		_f_key = H.mono("Medium")
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func setup_def(d: BuildingDef, key: String, fallback_glyph: StringName) -> void:
	def = d
	title = d.short_label if not d.short_label.is_empty() else d.display_name
	hotkey = key
	glyph = fallback_glyph
	reload_icon()


func setup_tool(id: StringName, label: String, key: String, fallback_glyph: StringName) -> void:
	tool_id = id
	title = label
	hotkey = key
	glyph = fallback_glyph
	reload_icon()


## Picks up a rendered icon that landed after the bar was built.
func reload_icon() -> void:
	var id := def.id if def else tool_id
	_icon = H.build_icon(id)
	queue_redraw()


func set_costs(list: Array[Dictionary]) -> void:
	if list != costs:
		costs = list
		queue_redraw()


func _process(delta: float) -> void:
	_pulse += delta
	queue_redraw()


func _draw() -> void:
	var dim := state == State.UNAFFORDABLE or state == State.LOCKED
	var w := size.x
	# Icon well.
	var well := Rect2((w - ICON_PX - 8.0) * 0.5, 9.0, ICON_PX + 8.0, ICON_PX + 4.0)
	draw_rect(well, Color(H.VOID, 0.45))
	var hovered := is_hovered() and not disabled
	var tint := Color(1, 1, 1, 0.42) if dim else Color.WHITE
	if _icon:
		var ir := Rect2((w - ICON_PX) * 0.5, 10.0, ICON_PX, ICON_PX)
		if hovered or state == State.PLACING:
			ir = ir.grow(3.0)
		draw_texture_rect(_icon, ir, false, tint)
	else:
		_draw_placeholder(Rect2((w - ICON_PX) * 0.5, 10.0, ICON_PX, ICON_PX), dim)
	if state == State.LOCKED:
		var lk := H.icon(&"lock")
		if lk:
			draw_texture_rect(lk, Rect2(w * 0.5 - 11, 30, 22, 22), false, Color(H.BAD, 0.9))
	# Hotkey badge, top left.
	if not hotkey.is_empty():
		var ks := _f_key.get_string_size(hotkey, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		var kr := Rect2(5, 5, maxf(ks.x + 8, 18), 17)
		draw_rect(kr, Color(0.086, 0.059, 0.024, 0.9))
		draw_rect(kr, Color(H.ACCENT, 0.75 if not dim else 0.35), false, 1.0)
		draw_string(_f_key, Vector2(kr.position.x + (kr.size.x - ks.x) * 0.5, 18), hotkey, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, H.ACCENT_SOFT if not dim else H.TEXT_FAINT)
	# Built count, top right.
	if not count_text.is_empty():
		var cs := _f_key.get_string_size(count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		draw_string(_f_key, Vector2(w - cs.x - 12, 18), count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, H.BAD if state == State.LOCKED else H.TEXT_DIM)
	# Name.
	var name_col := H.TEXT_BRIGHT if not dim else H.TEXT_DIM
	if state == State.PLACING:
		name_col = H.ACCENT_SOFT
	var lines := _name_lines(title.to_upper(), w - 10)
	var ny := 91.0 if lines.size() == 1 else 84.0
	for line in lines:
		var ns := _f_name.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
		draw_string(_f_name, Vector2((w - ns.x) * 0.5, ny), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, name_col)
		ny += 12.0
	# Cost line: up to three entries, centred.
	_draw_costs(Vector2(0, 110), w, dim)
	# Placing: pulsing amber frame.
	if state == State.PLACING:
		var a := 0.55 + 0.45 * sin(_pulse * 6.0)
		draw_rect(Rect2(1.5, 1.5, w - 3, size.y - 3), Color(H.ACCENT_SOFT, a), false, 2.0)


## The name on one line, or split over two at the space nearest the middle.
func _name_lines(text: String, max_w: float) -> PackedStringArray:
	if _f_name.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x <= max_w or not text.contains(" "):
		return PackedStringArray([PilotCard._fit(_f_name, text, 13, max_w)])
	var best := -1
	for i in text.length():
		if text[i] == " " and (best < 0 or absi(i - text.length() / 2) < absi(best - text.length() / 2)):
			best = i
	return PackedStringArray([PilotCard._fit(_f_name, text.left(best), 13, max_w), PilotCard._fit(_f_name, text.substr(best + 1), 13, max_w)])


func _draw_costs(at: Vector2, w: float, dim: bool) -> void:
	if costs.is_empty():
		return
	var parts: Array[Dictionary] = []
	var total := 0.0
	for c in costs:
		var t := String(c["text"])
		var tw := _f_cost.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		parts.append({"w": tw, "text": t, "icon": c["icon"], "short": c["short"], "color": c.get("color", H.TEXT)})
		total += tw + 12.0
	total += 4.0 * float(parts.size() - 1)
	var x := (w - total) * 0.5
	for p in parts:
		var ic := H.icon(StringName(p["icon"]))
		var col: Color = H.BAD if bool(p["short"]) else (p["color"] as Color)
		if dim and not bool(p["short"]):
			col = Color(col, 0.5)
		if ic:
			draw_texture_rect(ic, Rect2(x, at.y - 10, 10, 10), false, col)
		draw_string(_f_cost, Vector2(x + 12, at.y), String(p["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col.lerp(Color.WHITE, 0.2) if not bool(p["short"]) else H.BAD)
		x += float(p["w"]) + 16.0


## A neat stand-in while the rendered icon is missing: a chamfered plate
## with the group glyph.
func _draw_placeholder(r: Rect2, dim: bool) -> void:
	var c := 12.0
	var pts := PackedVector2Array([Vector2(r.position.x + c, r.position.y), Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y - c),
			Vector2(r.end.x - c, r.end.y), Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.position.y + c)])
	var g := r.grow(-8.0)
	draw_colored_polygon(pts, H.RAISED_BG)
	var loop := pts.duplicate()
	loop.append(pts[0])
	draw_polyline(loop, Color(H.HOLO, 0.35 if dim else 0.7), 1.0)
	var ic := H.icon(glyph)
	if ic:
		draw_texture_rect(ic, g, false, Color(H.HOLO_SOFT, 0.4 if dim else 0.9))

class_name BuildTile
extends Button
## One small square build bar tile, icon only: the structure's rendered
## icon (assets/ui/icons/build/<id>.png, a drawn placeholder glyph while it
## is missing), a tiny hotkey badge (top left) and the built count against
## the limit (bottom right, "0/2"). No name or cost text: the [BuildMenu]
## shows the [BuildInfoCard] on hover with all of that. States: ready,
## unaffordable (dimmed, a small red mark of the short resource bottom
## left), locked (limit reached, no free bay, not allowed: a lock), placing
## (lit amber, pulsing edge).

enum State { READY, UNAFFORDABLE, LOCKED, PLACING }

const SIZE := Vector2(62.0, 62.0)
const ICON_PX := 46.0
const BADGE_FONT := 11
const H := preload("res://scripts/ui/theme/hud_style.gd")

var def: BuildingDef
## Set for the defence zone tool (no BuildingDef).
var tool_id: StringName = &""
## The name, for the info card and the tutorial (not drawn).
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
## Per cost entry: {icon, text, short (bool)}; only the short ones are drawn.
var costs: Array[Dictionary] = []

var _icon: Texture2D
var _pulse := 0.0

static var _f_key: Font


func _init() -> void:
	custom_minimum_size = SIZE
	focus_mode = Control.FOCUS_NONE
	toggle_mode = true
	theme_type_variation = &"BuildTile"
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	set_process(false)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if _f_key == null:
		_f_key = H.mono("Medium")
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func setup_def(d: BuildingDef, key: String, fallback_glyph: StringName) -> void:
	def = d
	title = d.display_name
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
	var hovered := is_hovered() and not disabled
	var tint := Color(1, 1, 1, 0.42) if dim else Color.WHITE
	var ir := Rect2((w - ICON_PX) * 0.5, (size.y - ICON_PX) * 0.5, ICON_PX, ICON_PX)
	if _icon:
		if hovered or state == State.PLACING:
			ir = ir.grow(3.0)
		draw_texture_rect(_icon, ir, false, tint)
	else:
		_draw_placeholder(ir.grow(-2.0), dim)
	if state == State.LOCKED:
		var lk := H.icon(&"lock")
		if lk:
			draw_texture_rect(lk, Rect2(w * 0.5 - 9, size.y * 0.5 - 9, 18, 18), false, Color(H.BAD, 0.9))
	# Hotkey badge, top left.
	if not hotkey.is_empty():
		var ks := _f_key.get_string_size(hotkey, HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_FONT)
		var kr := Rect2(3, 3, maxf(ks.x + 6, 15), 14)
		draw_rect(kr, Color(0.086, 0.059, 0.024, 0.9))
		draw_rect(kr, Color(H.ACCENT, 0.75 if not dim else 0.35), false, 1.0)
		draw_string(_f_key, Vector2(kr.position.x + (kr.size.x - ks.x) * 0.5, kr.position.y + 11), hotkey, HORIZONTAL_ALIGNMENT_LEFT, -1,
				BADGE_FONT, H.ACCENT_SOFT if not dim else H.TEXT_FAINT)
	# Built count, bottom right.
	if not count_text.is_empty():
		var cs := _f_key.get_string_size(count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_FONT)
		var cr := Rect2(w - cs.x - 9, size.y - 17, cs.x + 6, 14)
		draw_rect(cr, Color(H.VOID, 0.8))
		draw_string(_f_key, Vector2(cr.position.x + 3, cr.position.y + 11), count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_FONT,
				H.BAD if state == State.LOCKED else H.TEXT)
	# Short of a resource: its icon in red, bottom left.
	if state == State.UNAFFORDABLE:
		for c in costs:
			if bool(c.get("short", false)):
				var ic := H.icon(StringName(c["icon"]))
				if ic:
					draw_rect(Rect2(3, size.y - 17, 14, 14), Color(H.VOID, 0.8))
					draw_texture_rect(ic, Rect2(5, size.y - 15, 10, 10), false, H.BAD)
				break
	# Placing: pulsing amber frame.
	if state == State.PLACING:
		var a := 0.55 + 0.45 * sin(_pulse * 6.0)
		draw_rect(Rect2(1.5, 1.5, w - 3, size.y - 3), Color(H.ACCENT_SOFT, a), false, 2.0)


## A neat stand-in while the rendered icon is missing: a chamfered plate
## with the group glyph.
func _draw_placeholder(r: Rect2, dim: bool) -> void:
	var c := 9.0
	var pts := PackedVector2Array([Vector2(r.position.x + c, r.position.y), Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y - c),
			Vector2(r.end.x - c, r.end.y), Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.position.y + c)])
	var g := r.grow(-7.0)
	draw_colored_polygon(pts, H.RAISED_BG)
	var loop := pts.duplicate()
	loop.append(pts[0])
	draw_polyline(loop, Color(H.HOLO, 0.35 if dim else 0.7), 1.0)
	var ic := H.icon(glyph)
	if ic:
		draw_texture_rect(ic, g, false, Color(H.HOLO_SOFT, 0.4 if dim else 0.9))

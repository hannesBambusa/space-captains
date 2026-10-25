@tool
class_name ChamferBox
extends StyleBox
## The HUD's panel and button style ("Industrial Expanse"): a flat fill with
## cut (45 degree) corners, a hairline border, an optional accent stripe on
## one edge, faint horizontal scanlines and a soft drop shadow. Drawn with
## RenderingServer polygons, so it stays crisp at every UI scale.
## Built by [HudThemeBuilder]; every HUD panel shares these through the theme.

enum Accent { NONE, TOP, LEFT, BOTTOM }

@export var bg_color: Color = Color(0.055, 0.065, 0.08, 0.9):
	set(v):
		bg_color = v
		emit_changed()
## Second fill colour at the bottom edge (vertical gradient). Alpha 0 = flat.
@export var bg_bottom: Color = Color(0, 0, 0, 0):
	set(v):
		bg_bottom = v
		emit_changed()
@export var border_color: Color = Color(0.55, 0.62, 0.7, 0.22):
	set(v):
		border_color = v
		emit_changed()
@export var border_width: float = 1.0:
	set(v):
		border_width = v
		emit_changed()
## Cut size per corner, px: top left, top right, bottom right, bottom left.
@export var cut: Vector4 = Vector4(0, 8, 0, 8):
	set(v):
		cut = v
		emit_changed()
@export var accent: Accent = Accent.NONE:
	set(v):
		accent = v
		emit_changed()
@export var accent_color: Color = Color(1.0, 0.55, 0.15):
	set(v):
		accent_color = v
		emit_changed()
@export var accent_width: float = 2.0:
	set(v):
		accent_width = v
		emit_changed()
## Accent stripe length, px (0 = the whole edge).
@export var accent_length: float = 0.0:
	set(v):
		accent_length = v
		emit_changed()
## Scanline alpha (0 = none) and spacing, px.
@export var scanlines: float = 0.0:
	set(v):
		scanlines = v
		emit_changed()
@export var scanline_step: float = 3.0:
	set(v):
		scanline_step = v
		emit_changed()
@export var shadow_size: float = 0.0:
	set(v):
		shadow_size = v
		emit_changed()
@export var shadow_color: Color = Color(0, 0, 0, 0.35):
	set(v):
		shadow_color = v
		emit_changed()
## Small corner ticks in the accent colour on the uncut corners.
@export var corner_ticks: bool = false:
	set(v):
		corner_ticks = v
		emit_changed()


func _draw(ci: RID, rect: Rect2) -> void:
	if shadow_size > 0.0 and shadow_color.a > 0.0:
		var sr := rect.grow(shadow_size * 0.5)
		sr.position.y += shadow_size * 0.5
		var sc := Color(shadow_color, shadow_color.a * 0.5)
		RenderingServer.canvas_item_add_polygon(ci, _outline(sr, shadow_size * 0.5), PackedColorArray([sc]))
	var pts := _outline(rect, 0.0)
	if bg_color.a > 0.0:
		if bg_bottom.a > 0.0:
			var cols := PackedColorArray()
			for p in pts:
				var t := clampf((p.y - rect.position.y) / maxf(rect.size.y, 1.0), 0.0, 1.0)
				cols.append(bg_color.lerp(bg_bottom, t))
			RenderingServer.canvas_item_add_polygon(ci, pts, cols)
		else:
			RenderingServer.canvas_item_add_polygon(ci, pts, PackedColorArray([bg_color]))
	if scanlines > 0.0 and rect.size.y > 6.0:
		var c := Color(1, 1, 1, scanlines)
		var y := rect.position.y + 2.0
		var ml := maxf(cut.x, cut.w)
		var mr := maxf(cut.y, cut.z)
		while y < rect.end.y - 2.0:
			RenderingServer.canvas_item_add_line(ci, Vector2(rect.position.x + ml * 0.5 + 2.0, y), Vector2(rect.end.x - mr * 0.5 - 2.0, y), c, 1.0)
			y += scanline_step
	if border_width > 0.0 and border_color.a > 0.0:
		var loop := pts.duplicate()
		loop.append(pts[0])
		RenderingServer.canvas_item_add_polyline(ci, _inset(loop, rect, border_width * 0.5), PackedColorArray([border_color]), border_width)
	if accent != Accent.NONE and accent_color.a > 0.0:
		_draw_accent(ci, rect)
	if corner_ticks:
		_draw_ticks(ci, rect)


## Corner polygon of [param r] grown by [param grow], clockwise from top left.
func _outline(r: Rect2, grow: float) -> PackedVector2Array:
	var a := r.grow(grow)
	var p := PackedVector2Array()
	var tl := minf(cut.x, minf(a.size.x, a.size.y) * 0.5)
	var tr := minf(cut.y, minf(a.size.x, a.size.y) * 0.5)
	var br := minf(cut.z, minf(a.size.x, a.size.y) * 0.5)
	var bl := minf(cut.w, minf(a.size.x, a.size.y) * 0.5)
	if tl > 0.0:
		p.append(Vector2(a.position.x, a.position.y + tl))
		p.append(Vector2(a.position.x + tl, a.position.y))
	else:
		p.append(a.position)
	if tr > 0.0:
		p.append(Vector2(a.end.x - tr, a.position.y))
		p.append(Vector2(a.end.x, a.position.y + tr))
	else:
		p.append(Vector2(a.end.x, a.position.y))
	if br > 0.0:
		p.append(Vector2(a.end.x, a.end.y - br))
		p.append(Vector2(a.end.x - br, a.end.y))
	else:
		p.append(a.end)
	if bl > 0.0:
		p.append(Vector2(a.position.x + bl, a.end.y))
		p.append(Vector2(a.position.x, a.end.y - bl))
	else:
		p.append(Vector2(a.position.x, a.end.y))
	return p


## Pulls the outline points toward the centre by [param d] so the stroke sits inside.
func _inset(pts: PackedVector2Array, r: Rect2, d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(clampf(p.x, r.position.x + d, r.end.x - d), clampf(p.y, r.position.y + d, r.end.y - d)))
	return out


func _draw_accent(ci: RID, r: Rect2) -> void:
	var w := accent_width
	match accent:
		Accent.TOP:
			var x0 := r.position.x + cut.x
			var x1 := r.end.x - cut.y
			if accent_length > 0.0:
				x1 = minf(x1, x0 + accent_length)
			RenderingServer.canvas_item_add_rect(ci, Rect2(x0, r.position.y, x1 - x0, w), accent_color)
		Accent.BOTTOM:
			var x0 := r.position.x + cut.w
			var x1 := r.end.x - cut.z
			if accent_length > 0.0:
				x0 = (x0 + x1 - accent_length) * 0.5
				x1 = x0 + accent_length
			RenderingServer.canvas_item_add_rect(ci, Rect2(x0, r.end.y - w, x1 - x0, w), accent_color)
		Accent.LEFT:
			var y0 := r.position.y + cut.x
			var y1 := r.end.y - cut.w
			if accent_length > 0.0:
				y1 = minf(y1, y0 + accent_length)
			RenderingServer.canvas_item_add_rect(ci, Rect2(r.position.x, y0, w, y1 - y0), accent_color)


func _draw_ticks(ci: RID, r: Rect2) -> void:
	var c := Color(accent_color, accent_color.a * 0.8)
	var l := 6.0
	if cut.x <= 0.0:
		RenderingServer.canvas_item_add_rect(ci, Rect2(r.position, Vector2(l, 1)), c)
		RenderingServer.canvas_item_add_rect(ci, Rect2(r.position, Vector2(1, l)), c)
	if cut.y <= 0.0:
		RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(r.end.x - l, r.position.y), Vector2(l, 1)), c)
		RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(r.end.x - 1, r.position.y), Vector2(1, l)), c)
	if cut.z <= 0.0:
		RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(r.end.x - l, r.end.y - 1), Vector2(l, 1)), c)
		RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(r.end.x - 1, r.end.y - l), Vector2(1, l)), c)
	if cut.w <= 0.0:
		RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(r.position.x, r.end.y - 1), Vector2(l, 1)), c)
		RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(r.position.x, r.end.y - l), Vector2(1, l)), c)

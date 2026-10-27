class_name RichTooltip
extends PanelContainer
## The HUD's rich tooltip, returned from Control._make_custom_tooltip: a dark
## chamfered panel with a holo hairline frame and corner brackets (like the
## other HUD panels), an accent bar on the left edge, a Saira Condensed title,
## chips, section headings, bullet lines, stat rows with mono numbers and a
## progress bar. At most [constant WIDTH] px wide, text wraps.
##
## The content comes from a builder Callable (builder.call(tip)) that adds
## rows with the methods below. It runs again every [member interval]
## seconds while the tooltip is open, so the numbers stay live without the
## owner touching its tooltip_text (a changed tooltip_text makes Godot close
## the tooltip on the next mouse move). Owners keep tooltip_text set to a
## stable, non-empty key; Godot only calls _make_custom_tooltip when it is.
##
## [method live_label] is the plain variant: Godot's own tooltip look
## (TooltipLabel) with live text, for tooltips that keep the old design.

const H := preload("res://scripts/ui/theme/hud_style.gd")
const WIDTH := 360.0
const MARGIN_X := 14.0
const MARGIN_Y := 10.0

## Seconds between live rebuilds (0 = built once).
@export var interval: float = 0.25

var accent: Color = H.HOLO
## Width of the text column, px.
var content_width: float = WIDTH - 2.0 * MARGIN_X - 3.0

var _box: VBoxContainer
var _builder: Callable
var _left := 0.0
## Text of the last build (rebuilds that change nothing keep the nodes).
var _sig := ""
var _rows: PackedStringArray = []


## A tooltip filled by [param builder] (called with the tip), with a
## [param accent_color] bar on its left edge.
static func make(builder: Callable, accent_color: Color = H.HOLO, width: float = WIDTH) -> RichTooltip:
	var tip := RichTooltip.new()
	tip.accent = accent_color
	tip.content_width = width - 2.0 * MARGIN_X - 3.0
	tip._builder = builder
	return tip


## Godot's plain tooltip label, its text read from [param source] (returns a
## String) every 0.25 s while it is open.
static func live_label(source: Callable) -> Label:
	var l := LiveLabel.new()
	l.theme_type_variation = &"TooltipLabel"
	l.source = source
	l.text = String(source.call())
	return l


## Godot's tooltip label with its text re-read every 0.25 s.
class LiveLabel:
	extends Label

	var source: Callable
	var _left := 0.25

	func _process(delta: float) -> void:
		_left -= delta
		if _left > 0.0 or not source.is_valid():
			return
		_left = 0.25
		var s := String(source.call())
		if not s.is_empty() and s != text:
			text = s


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The tooltip's panel: chamfered, holo hairline and brackets, a
## [param accent_color] bar on the left (also used by [BuildInfoCard]).
static func panel_style(accent_color: Color) -> ChamferBox:
	var sb := HudThemeBuilder.box(Color(0.027, 0.05, 0.07, 0.97), Color(H.HOLO_DIM, 0.9), Vector4(0, 10, 0, 10),
			Vector4(MARGIN_X + 3.0, MARGIN_Y, MARGIN_X, MARGIN_Y))
	sb.bg_bottom = Color(H.VOID, 0.97)
	sb.scanlines = 0.03
	sb.brackets = true
	sb.bracket_color = H.HOLO
	sb.bracket_size = 10.0
	sb.bracket_width = 2.0
	sb.accent = ChamferBox.Accent.LEFT
	sb.accent_color = accent_color
	sb.accent_width = 3.0
	return sb


func _ready() -> void:
	add_theme_stylebox_override("panel", panel_style(accent))
	custom_minimum_size.x = content_width + 2.0 * MARGIN_X + 3.0
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 3)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	_build()
	set_process(interval > 0.0 and _builder.is_valid())


func _notification(what: int) -> void:
	# Godot wraps the tooltip in its own TooltipPanel popup: drop that frame,
	# this one draws its own.
	if what == NOTIFICATION_PARENTED:
		var w := get_parent() as Window
		if w:
			w.add_theme_stylebox_override("panel", StyleBoxEmpty.new())


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		_left = interval
		_build()


func _build() -> void:
	if not _builder.is_valid():
		return
	_rows.clear()
	var old := _box.get_children()
	for c in old:
		_box.remove_child(c)
	_builder.call(self)
	var sig := "\n".join(_rows)
	if sig == _sig and not old.is_empty():
		# Nothing changed: keep the old nodes, drop the new ones.
		for c in _box.get_children():
			_box.remove_child(c)
			c.queue_free()
		for c in old:
			_box.add_child(c)
		return
	_sig = sig
	for c in old:
		c.queue_free()
	reset_size()


# --- Rows ---------------------------------------------------------------------------

## The title, in Saira Condensed.
func title(text: String, color: Color = H.TEXT_BRIGHT) -> Label:
	var l := _label(text, H.font("SemiBold", true), 19, color)
	_rows.append("T" + text)
	return l


## A row of small outlined chips, [param chips]: [{text, color}].
func chips(list: Array[Dictionary]) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in list:
		var col: Color = c.get("color", H.TEXT_DIM)
		var p := PanelContainer.new()
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := HudThemeBuilder.box(Color(col, 0.1), Color(col, 0.55), Vector4(0, 4, 0, 0), Vector4(6, 1, 6, 1))
		p.add_theme_stylebox_override("panel", sb)
		var l := Label.new()
		l.text = String(c.get("text", "")).to_upper()
		l.add_theme_font_override("font", H.font("SemiBold", true, false, 1))
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", col)
		p.add_child(l)
		row.add_child(p)
		_rows.append("C" + l.text)
	_box.add_child(row)


## A wrapped line of body text.
func text(s: String, color: Color = H.TEXT, size: int = 13) -> Label:
	var l := _label(s, H.font("Regular"), size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = content_width
	_rows.append("X" + s)
	return l


## A section heading (spaced capitals in holo cyan) over a hairline.
func section(heading: String, color: Color = H.HOLO) -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = 3.0
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(gap)
	_label(heading.to_upper(), H.font("SemiBold", true, false, 1), 13, color)
	var rule := ColorRect.new()
	rule.color = H.HAIRLINE_STRONG
	rule.custom_minimum_size.y = 1.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(rule)
	_rows.append("S" + heading)


## A bullet line: a small square in [param mark] and wrapped text.
func bullet(s: String, mark: Color = H.HOLO, color: Color = H.TEXT) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := Control.new()
	dot.custom_minimum_size = Vector2(5.0, 16.0)
	dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.draw.connect(func() -> void: dot.draw_rect(Rect2(0, 7, 5, 5), mark))
	row.add_child(dot)
	var l := Label.new()
	l.text = s
	l.add_theme_font_override("font", H.font("Regular"))
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = content_width - 12.0
	row.add_child(l)
	_box.add_child(row)
	_rows.append("B" + s)


## A stat row: a dim label on the left, the value (mono) on the right.
func stat(label: String, value: String, value_color: Color = H.TEXT_BRIGHT, mono: bool = true) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var k := Label.new()
	k.text = label
	k.add_theme_font_override("font", H.font("Medium", true))
	k.add_theme_font_size_override("font_size", 14)
	k.add_theme_color_override("font_color", H.TEXT_DIM)
	k.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(k)
	var v := Label.new()
	v.text = value
	v.add_theme_font_override("font", H.mono("Medium") if mono else H.font("Medium"))
	v.add_theme_font_size_override("font_size", 13)
	v.add_theme_color_override("font_color", value_color)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.custom_minimum_size.x = maxf(content_width - k.get_minimum_size().x - 10.0, 40.0)
	row.add_child(v)
	_box.add_child(row)
	_rows.append("V%s=%s" % [label, value])


## A thin progress bar, [param fraction] 0..1.
func bar(fraction: float, color: Color = H.HOLO) -> void:
	var b := Control.new()
	b.custom_minimum_size = Vector2(content_width, 6.0)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f := clampf(fraction, 0.0, 1.0)
	b.draw.connect(func() -> void:
		var r := Rect2(0, 1.5, b.size.x, 3.0)
		b.draw_rect(r, Color(H.HAIRLINE_STRONG, 0.7))
		r.size.x *= f
		b.draw_rect(r, color))
	_box.add_child(b)
	_rows.append("P%.3f" % f)


## A faint footer line (what a click does).
func hint(s: String) -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = 2.0
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(gap)
	var l := _label(s, H.font("Medium", true), 13, H.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = content_width
	_rows.append("H" + s)


func _label(s: String, f: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = s
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(l)
	return l

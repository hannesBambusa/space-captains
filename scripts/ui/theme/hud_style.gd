class_name HudStyle
extends RefCounted
## Shared look of the HUD ("Industrial Expanse"): the palette, the fonts
## (Barlow and Barlow Condensed, SIL OFL, assets/ui/fonts), the small
## monochrome icons (assets/ui/icons/*.svg, tinted in code) and a few
## widget helpers. [HudThemeBuilder] turns the palette into ui/theme.tres;
## widgets use these constants for the colours they set themselves.

const ACCENT := Color(1.0, 0.55, 0.15)
const ACCENT_SOFT := Color(1.0, 0.64, 0.3)
const ACCENT_DIM := Color(1.0, 0.55, 0.15, 0.35)
const PANEL_BG := Color(0.047, 0.056, 0.07, 0.88)
const PANEL_BG_BOTTOM := Color(0.035, 0.04, 0.05, 0.92)
const RAISED_BG := Color(0.09, 0.105, 0.125, 0.92)
const INSET_BG := Color(0.02, 0.025, 0.035, 0.6)
const HAIRLINE := Color(0.6, 0.67, 0.76, 0.2)
const HAIRLINE_STRONG := Color(0.6, 0.67, 0.76, 0.36)
const TEXT := Color(0.87, 0.9, 0.94)
const TEXT_BRIGHT := Color(1.0, 1.0, 1.0)
const TEXT_DIM := Color(0.58, 0.63, 0.7)
const TEXT_FAINT := Color(0.42, 0.46, 0.52)
const GOOD := Color(0.42, 0.92, 0.56)
const WARN := Color(1.0, 0.76, 0.28)
const BAD := Color(1.0, 0.36, 0.3)
const SHIELD := Color(0.45, 0.75, 1.0)
const HULL := Color(0.42, 0.92, 0.56)
const CREDITS := Color(1.0, 0.84, 0.45)

## Pilot roles: colour of the emblem badge and the role icon.
const ROLE_COLORS := {
	"Miner": Color(0.98, 0.74, 0.3),
	"Mercenary": Color(0.55, 0.72, 1.0),
	"Salvager": Color(0.42, 0.88, 0.74),
	"Lander": Color(0.78, 0.58, 1.0),
}
const ROLE_ICONS := {"Miner": &"role_miner", "Mercenary": &"role_mercenary", "Salvager": &"role_salvager", "Lander": &"role_lander"}
## Short role names for chips and badges.
const ROLE_SHORT := {"Miner": "Miners", "Mercenary": "Mercs", "Salvager": "Salvagers", "Lander": "Landers"}

const FONT_DIR := "res://assets/ui/fonts/"
const ICON_DIR := "res://assets/ui/icons/"
const BUILD_ICON_DIR := "res://assets/ui/icons/build/"

static var _fonts: Dictionary = {}
static var _icons: Dictionary = {}


## Barlow at [param weight] ("Regular", "Medium", "SemiBold", "Bold"),
## condensed with [param condensed]. Tabular figures with [param tabular].
static func font(weight: String = "Regular", condensed: bool = false, tabular: bool = false, spacing: int = 0) -> Font:
	var key := "%s|%s|%s|%d" % [weight, condensed, tabular, spacing]
	if _fonts.has(key):
		return _fonts[key]
	var path := FONT_DIR + ("BarlowCondensed-" if condensed else "Barlow-") + weight + ".ttf"
	var out: Font
	if ResourceLoader.exists(path):
		var base := load(path) as FontFile
		var fv := FontVariation.new()
		fv.base_font = base
		if tabular:
			fv.opentype_features = {"tnum": 1}
		if spacing != 0:
			fv.spacing_glyph = spacing
		out = fv
	else:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Avenir Next Condensed", "Helvetica Neue", "Arial"] if condensed else ["Avenir Next", "Helvetica Neue", "Arial"])
		sf.font_weight = {"Regular": 400, "Medium": 500, "SemiBold": 600, "Bold": 700}.get(weight, 400)
		out = sf
	_fonts[key] = out
	return out


## Icon [param icon_name] from assets/ui/icons (null when missing).
static func icon(icon_name: StringName) -> Texture2D:
	if _icons.has(icon_name):
		return _icons[icon_name]
	var path := ICON_DIR + String(icon_name) + ".svg"
	var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_icons[icon_name] = tex
	return tex


## Rendered 3D icon of a structure (assets/ui/icons/build/<id>.png), or null.
static func build_icon(id: StringName) -> Texture2D:
	var key := StringName("build/" + String(id))
	if _icons.has(key):
		return _icons[key]
	var path := BUILD_ICON_DIR + String(id) + ".png"
	var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_icons[key] = tex
	return tex


## A tinted icon of [param px] logical pixels.
static func icon_rect(icon_name: StringName, px: float = 16.0, tint: Color = TEXT) -> TextureRect:
	var r := TextureRect.new()
	r.texture = icon(icon_name)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(px, px)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.modulate = tint
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return r


static func role_color(role: String) -> Color:
	return ROLE_COLORS.get(role, Color(0.7, 0.74, 0.8))


static func role_icon(role: String) -> StringName:
	return ROLE_ICONS.get(role, &"role_other")


## Colour of a hull bar at fraction [param f].
static func hull_color(f: float) -> Color:
	return HULL if f > 0.6 else (WARN if f > 0.3 else BAD)


## Two-letter initials ("Idris Reyes" -> "IR").
static func initials(full_name: String) -> String:
	var parts := full_name.strip_edges().split(" ", false)
	if parts.is_empty():
		return "?"
	if parts.size() == 1:
		return parts[0].left(2).to_upper()
	return (parts[0].left(1) + parts[parts.size() - 1].left(1)).to_upper()


## Gives every Label under [param node] a soft dark outline (lists that float
## over space without a panel).
static func outline_labels(node: Node) -> void:
	if node is Label:
		var l := node as Label
		l.add_theme_constant_override("outline_size", 4)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	for c in node.get_children():
		outline_labels(c)

class_name HudStyle
extends RefCounted
## Shared look of the HUD, "flight ops" (ongoing-implementations/hud-flight-ops.md):
## mission-control readouts set straight on the scene, ice-white type, faint
## white hairlines, nearly clear panels over edge shading ([EdgeShade]), amber
## for actions, selection and credits, a cool ice blue for secondary info.
## Fonts (SIL OFL, assets/ui/fonts): Saira (thin weights for big readouts and
## titles, Light for body text), Saira Condensed for buttons and tabs, IBM Plex
## Mono for numbers. Small monochrome icons (assets/ui/icons/*.svg, tinted in
## code) and a few widget helpers. [HudThemeBuilder] turns the palette into
## ui/theme.tres; widgets use these constants for the colours they set.

## Secondary info (ice blue): section icons, progress fills, hover frames.
const HOLO := Color(0.6, 0.82, 0.93)
const HOLO_SOFT := Color(0.8, 0.91, 0.97)
const HOLO_DIM := Color(0.42, 0.55, 0.62)
const VOID := Color(0.012, 0.018, 0.024)
const ACCENT := Color(1.0, 0.702, 0.278)
const ACCENT_SOFT := Color(1.0, 0.8, 0.5)
const ACCENT_DIM := Color(1.0, 0.702, 0.278, 0.35)
## Panels with reading text (selection panels, the tutorial card): dark
## enough to read over a planet; the lists on the scene clear theirs.
const PANEL_BG := Color(0.012, 0.02, 0.028, 0.86)
const PANEL_BG_BOTTOM := Color(0.012, 0.02, 0.028, 0.9)
const RAISED_BG := Color(0.05, 0.065, 0.08, 0.62)
const INSET_BG := Color(0.0, 0.0, 0.0, 0.32)
const HAIRLINE := Color(0.93, 0.95, 0.96, 0.14)
const HAIRLINE_STRONG := Color(0.93, 0.95, 0.96, 0.32)
const TEXT := Color(0.89, 0.92, 0.94)
const TEXT_BRIGHT := Color(0.96, 0.975, 0.985)
const TEXT_DIM := Color(0.58, 0.63, 0.67)
const TEXT_FAINT := Color(0.37, 0.41, 0.44)
const GOOD := Color(0.494, 0.886, 0.659)
const WARN := Color(1.0, 0.82, 0.36)
const BAD := Color(1.0, 0.416, 0.361)
const SHIELD := Color(0.5, 0.7, 1.0)
const HULL := Color(0.494, 0.886, 0.659)
const CREDITS := Color(1.0, 0.702, 0.278)

## Pilot roles: colour of the emblem badge and the role icon. Kept apart
## from each other and from the holo cyan of the frames.
const ROLE_COLORS := {
	"Miner": Color(0.95, 0.78, 0.32),
	"Mercenary": Color(0.55, 0.6, 1.0),
	"Salvager": Color(0.66, 0.86, 0.32),
	"Lander": Color(0.8, 0.56, 1.0),
	"Explorer": Color(0.36, 0.86, 0.95),
}
const ROLE_ICONS := {"Miner": &"role_miner", "Mercenary": &"role_mercenary", "Salvager": &"role_salvager", "Lander": &"role_lander", "Explorer": &"role_explorer"}
## Short role names for chips and badges.
const ROLE_SHORT := {"Miner": "Miners", "Mercenary": "Mercs", "Salvager": "Salvagers", "Lander": "Landers", "Explorer": "Explorers"}

const FONT_DIR := "res://assets/ui/fonts/"
const ICON_DIR := "res://assets/ui/icons/"
const BUILD_ICON_DIR := "res://assets/ui/icons/build/"
const WEIGHTS := {"Thin": 200, "Light": 300, "Regular": 400, "Medium": 500, "SemiBold": 600, "Bold": 700}

static var _fonts: Dictionary = {}
static var _icons: Dictionary = {}


## Saira at [param weight] ("Thin", "Light", "Regular", "Medium", "SemiBold", "Bold"),
## Saira Condensed with [param condensed] (Thin to Regular fall back to Medium).
## Tabular figures with [param tabular]; [param spacing] adds px per glyph.
static func font(weight: String = "Regular", condensed: bool = false, tabular: bool = false, spacing: int = 0) -> Font:
	var key := "%s|%s|%s|%d" % [weight, condensed, tabular, spacing]
	if _fonts.has(key):
		return _fonts[key]
	var wght: int = WEIGHTS.get(weight, 400)
	var out: Font
	if condensed:
		out = _variant(FONT_DIR + "SairaCondensed-" + ("Medium" if weight in ["Thin", "Light", "Regular"] else weight) + ".ttf", 0, tabular, spacing)
	else:
		out = _variant(FONT_DIR + "Saira-Variable.ttf", wght, tabular, spacing)
	if out == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Arial Narrow", "Helvetica Neue", "Arial"] if condensed else ["Helvetica Neue", "Arial"])
		sf.font_weight = wght
		out = sf
	_fonts[key] = out
	return out


## IBM Plex Mono for numeric readouts (credits, distances, prices, timers).
## [param weight] "Regular" or "Medium" (heavier weights use Medium).
static func mono(weight: String = "Medium", spacing: int = 0) -> Font:
	var key := "mono|%s|%d" % [weight, spacing]
	if _fonts.has(key):
		return _fonts[key]
	var out: Font = _variant(FONT_DIR + "IBMPlexMono-" + ("Regular" if weight == "Regular" else "Medium") + ".ttf", 0, false, spacing)
	if out == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Menlo", "Consolas", "Courier New"])
		out = sf
	_fonts[key] = out
	return out


## A FontVariation of the font file at [param path] (null when missing).
## [param wght] sets the variable weight axis (0 = static file).
static func _variant(path: String, wght: int, tabular: bool, spacing: int) -> FontVariation:
	if not ResourceLoader.exists(path):
		return null
	var fv := FontVariation.new()
	fv.base_font = load(path) as FontFile
	if wght > 0:
		var ts := TextServerManager.get_primary_interface()
		fv.variation_opentype = {ts.name_to_tag("wght"): wght, ts.name_to_tag("wdth"): 100}
	if tabular:
		fv.opentype_features = {"tnum": 1}
	if spacing != 0:
		fv.spacing_glyph = spacing
	if path.get_file().begins_with("Saira"):
		# Saira's line box is tall (ascent + descent ~1.5 em); trim it so
		# rows keep roughly the height they had with the old face.
		fv.spacing_top = -2
		fv.spacing_bottom = -2
	return fv


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
	return ROLE_COLORS.get(role, TEXT_DIM)


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
		# Thin: the flight ops weights smear under a thick outline; the edge
		# shading behind does most of the work.
		l.add_theme_constant_override("outline_size", 2)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	for c in node.get_children():
		outline_labels(c)


## The guide's amber hazard stripe (diagonal bands), [param px] in size.
static func hazard_stripe(px: Vector2 = Vector2(240, 8)) -> TextureRect:
	var key := StringName("hazard")
	if not _icons.has(key):
		var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
		var dark := Color(0.071, 0.051, 0.02)
		for y in 20:
			for x in 20:
				img.set_pixel(x, y, ACCENT if (x + y) % 20 < 10 else dark)
		_icons[key] = ImageTexture.create_from_image(img)
	var r := TextureRect.new()
	r.texture = _icons[key]
	r.stretch_mode = TextureRect.STRETCH_TILE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.custom_minimum_size = px
	r.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

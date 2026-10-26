class_name HudThemeBuilder
extends RefCounted
## Builds the one HUD theme (ui/theme.tres) from [HudStyle]: base controls
## plus named type variations every panel shares. Regenerate the file after
## a change here:
##   Godot --headless --path . --script res://scripts/ui/theme/generate_theme.gd
##
## Variations: labels HeaderLabel, SubHeaderLabel, TitleLabel, ValueLabel,
## NumberLabel, BigValueLabel, DimLabel, SmallLabel, WarnLabel, BadgeLabel; buttons
## AccentButton, IconButton, RowButton, TabButton, ChipButton, CardButton,
## BuildTile, FeedRow, MainMenuButton; panels (PanelContainer) TopBarPanel,
## InsetPanel, SectionPanel, ToastPanel, HintPanel, MenuPanel, TooltipPanel.

const H := preload("res://scripts/ui/theme/hud_style.gd")


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = H.font("Regular")
	t.default_font_size = 15
	_labels(t)
	_buttons(t)
	_panels(t)
	_misc(t)
	return t


# --- Styles ---------------------------------------------------------------------

static func box(bg: Color, border: Color = H.HAIRLINE, cut: Vector4 = Vector4.ZERO, margins: Vector4 = Vector4(10, 6, 10, 6)) -> ChamferBox:
	var b := ChamferBox.new()
	b.bg_color = bg
	b.border_color = border
	b.border_width = 1.0 if border.a > 0.0 else 0.0
	b.cut = cut
	b.content_margin_left = margins.x
	b.content_margin_top = margins.y
	b.content_margin_right = margins.z
	b.content_margin_bottom = margins.w
	return b


static func _accented(b: ChamferBox, side: ChamferBox.Accent, color: Color = H.ACCENT, length: float = 0.0, width: float = 2.0) -> ChamferBox:
	b.accent = side
	b.accent_color = color
	b.accent_length = length
	b.accent_width = width
	return b


## Adds the guide's corner brackets (top left, bottom right) to [param b].
static func _bracketed(b: ChamferBox, color: Color = H.HOLO, length: float = 14.0, width: float = 2.0) -> ChamferBox:
	b.brackets = true
	b.bracket_color = color
	b.bracket_size = length
	b.bracket_width = width
	return b


static func _empty() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


# --- Labels ---------------------------------------------------------------------

static func _labels(t: Theme) -> void:
	t.set_color("font_color", "Label", H.TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.0))

	# Section labels: condensed caps, letter-spaced, holo (guide h3 / .code).
	_label_var(t, "HeaderLabel", H.font("SemiBold", true, false, 2), 14, H.HOLO)
	_label_var(t, "SubHeaderLabel", H.font("SemiBold", true, false, 1), 13, H.TEXT_DIM)
	_label_var(t, "TitleLabel", H.font("Bold", true, false, 2), 24, H.TEXT_BRIGHT)
	_label_var(t, "ValueLabel", H.font("Medium", false, true), 15, H.TEXT_BRIGHT)
	# Numeric readouts (credits, km, prices, timers): IBM Plex Mono.
	_label_var(t, "NumberLabel", H.mono("Medium"), 14, H.TEXT_BRIGHT)
	_label_var(t, "BigValueLabel", H.mono("Medium"), 18, H.TEXT_BRIGHT)
	_label_var(t, "DimLabel", H.font("Regular"), 14, H.TEXT_DIM)
	_label_var(t, "SmallLabel", H.font("Regular"), 13, H.TEXT_DIM)
	_label_var(t, "WarnLabel", H.font("Medium"), 14, H.BAD)
	_label_var(t, "TooltipLabel", H.font("Regular"), 14, H.TEXT)
	t.set_type_variation("TooltipLabel", "Label")
	# A small boxed tag: hotkeys, rank, counts (guide kbd).
	_label_var(t, "BadgeLabel", H.mono("Medium"), 11, H.TEXT)
	var badge := box(Color(H.VOID, 0.8), H.HAIRLINE_STRONG, Vector4.ZERO, Vector4(4, 0, 4, 0))
	t.set_stylebox("normal", "BadgeLabel", badge)


static func _label_var(t: Theme, type: String, f: Font, size: int, color: Color) -> void:
	t.set_type_variation(type, "Label")
	t.set_font("font", type, f)
	t.set_font_size("font_size", type, size)
	t.set_color("font_color", type, color)


# --- Buttons --------------------------------------------------------------------

static func _button_colors(t: Theme, type: String, normal: Color, hover: Color, pressed: Color, disabled: Color) -> void:
	t.set_color("font_color", type, normal)
	t.set_color("font_hover_color", type, hover)
	t.set_color("font_pressed_color", type, pressed)
	t.set_color("font_hover_pressed_color", type, pressed)
	t.set_color("font_focus_color", type, normal)
	t.set_color("font_disabled_color", type, disabled)
	t.set_color("icon_normal_color", type, normal)
	t.set_color("icon_hover_color", type, hover)
	t.set_color("icon_pressed_color", type, pressed)
	t.set_color("icon_hover_pressed_color", type, pressed)
	t.set_color("icon_disabled_color", type, disabled)


static func _button_styles(t: Theme, type: String, normal: StyleBox, hover: StyleBox, pressed: StyleBox, disabled: StyleBox, hover_pressed: StyleBox = null) -> void:
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("hover_pressed", type, hover_pressed if hover_pressed else pressed)
	t.set_stylebox("disabled", type, disabled)
	t.set_stylebox("focus", type, _empty())


## Holo wash for hover states (guide: rgba(95,208,226,0.05..0.08)).
static func _holo(a: float) -> Color:
	return Color(H.HOLO, a)


## Amber wash for pressed / selected states.
static func _amber(a: float) -> Color:
	return Color(H.ACCENT, a)


static func _buttons(t: Theme) -> void:
	var m := Vector4(14, 6, 14, 6)
	var z := Vector4.ZERO
	var none := Color(0, 0, 0, 0)
	var off_border := Color(H.HAIRLINE, 0.6)
	# Default: dark console key with a holo-dim frame, holo on hover, amber when pressed.
	_button_styles(t, "Button",
			box(H.RAISED_BG, H.HAIRLINE_STRONG, z, m),
			box(Color(0.075, 0.16, 0.2, 0.96), H.HOLO, z, m),
			_accented(box(Color(0.2, 0.135, 0.05, 0.96), H.ACCENT, z, m), ChamferBox.Accent.LEFT, H.ACCENT, 0.0, 2.0),
			box(Color(H.VOID, 0.7), off_border, z, m))
	_button_colors(t, "Button", H.TEXT, H.TEXT_BRIGHT, H.ACCENT_SOFT, H.TEXT_FAINT)
	t.set_font("font", "Button", H.font("SemiBold", true, false, 1))
	t.set_font_size("font_size", "Button", 15)
	t.set_constant("h_separation", "Button", 8)
	t.set_constant("icon_max_width", "Button", 18)

	# Accent (primary action): a solid amber block with void text (guide .dl).
	t.set_type_variation("AccentButton", "Button")
	_button_styles(t, "AccentButton",
			box(H.ACCENT, none, z, m),
			box(H.ACCENT_SOFT, none, z, m),
			box(Color(0.85, 0.55, 0.17), none, z, m),
			box(Color(0.12, 0.1, 0.07, 0.85), Color(H.ACCENT, 0.25), z, m))
	_button_colors(t, "AccentButton", H.VOID, H.VOID, H.VOID, Color(H.ACCENT, 0.45))
	t.set_font("font", "AccentButton", H.font("Bold", true, false, 2))
	t.set_font_size("font_size", "AccentButton", 16)

	# Small square tool buttons (close, collapse, steppers).
	t.set_type_variation("IconButton", "Button")
	var im := Vector4(6, 2, 6, 2)
	_button_styles(t, "IconButton",
			box(H.INSET_BG, H.HAIRLINE_STRONG, z, im),
			box(_holo(0.14), H.HOLO, z, im),
			box(_amber(0.3), H.ACCENT, z, im),
			box(Color(H.VOID, 0.5), off_border, z, im))
	_button_colors(t, "IconButton", H.TEXT, H.TEXT_BRIGHT, H.ACCENT_SOFT, H.TEXT_FAINT)
	t.set_font("font", "IconButton", H.font("SemiBold", true, false, 1))
	t.set_font_size("font_size", "IconButton", 14)
	t.set_constant("icon_max_width", "IconButton", 14)

	# List rows: flat, a holo wash on hover, amber stripe when pressed.
	t.set_type_variation("RowButton", "Button")
	var rm := Vector4(8, 3, 8, 3)
	_button_styles(t, "RowButton",
			box(none, none, z, rm),
			box(_holo(0.07), none, z, rm),
			_accented(box(_amber(0.13), none, z, rm), ChamferBox.Accent.LEFT, H.ACCENT, 0.0, 2.0),
			box(none, none, z, rm),
			_accented(box(_amber(0.2), none, z, rm), ChamferBox.Accent.LEFT, H.ACCENT, 0.0, 2.0))

	# Left panel tabs.
	t.set_type_variation("TabButton", "Button")
	var tm := Vector4(8, 6, 8, 6)
	_button_styles(t, "TabButton",
			_accented(box(Color(H.VOID, 0.55), none, z, tm), ChamferBox.Accent.BOTTOM, H.HAIRLINE, 0.0, 1.0),
			_accented(box(_holo(0.07), none, z, tm), ChamferBox.Accent.BOTTOM, H.HOLO_DIM, 0.0, 1.0),
			_accented(box(_amber(0.1), none, z, tm), ChamferBox.Accent.TOP, H.ACCENT, 0.0, 2.0),
			box(Color(0, 0, 0, 0.3), none, z, tm))
	_button_colors(t, "TabButton", H.TEXT_DIM, H.TEXT, H.TEXT_BRIGHT, H.TEXT_FAINT)
	t.set_font("font", "TabButton", H.font("SemiBold", true, false, 2))
	t.set_font_size("font_size", "TabButton", 13)
	t.set_constant("icon_max_width", "TabButton", 16)
	t.set_constant("h_separation", "TabButton", 5)

	# Filter chips.
	t.set_type_variation("ChipButton", "Button")
	var cm := Vector4(6, 1, 6, 1)
	_button_styles(t, "ChipButton",
			box(Color(H.VOID, 0.6), H.HAIRLINE, z, cm),
			box(_holo(0.1), H.HOLO_DIM, z, cm),
			box(_amber(0.2), H.ACCENT, z, cm),
			box(Color(0, 0, 0, 0.2), off_border, z, cm))
	_button_colors(t, "ChipButton", H.TEXT_DIM, H.TEXT, H.ACCENT_SOFT, H.TEXT_FAINT)
	t.set_font("font", "ChipButton", H.font("SemiBold", true, false, 1))
	t.set_font_size("font_size", "ChipButton", 13)
	t.set_constant("icon_max_width", "ChipButton", 12)
	t.set_constant("h_separation", "ChipButton", 4)

	# Pilot cards (content drawn by PilotCard).
	t.set_type_variation("CardButton", "Button")
	var km := Vector4(0, 0, 0, 0)
	_button_styles(t, "CardButton",
			box(Color(0.051, 0.09, 0.122, 0.88), H.HAIRLINE, z, km),
			box(Color(0.066, 0.13, 0.165, 0.94), H.HOLO_DIM, z, km),
			_bracketed(box(Color(0.12, 0.095, 0.06, 0.96), H.ACCENT, z, km), H.ACCENT, 8.0, 2.0),
			box(Color(H.VOID, 0.7), off_border, z, km),
			_bracketed(box(Color(0.15, 0.115, 0.07, 0.98), H.ACCENT_SOFT, z, km), H.ACCENT_SOFT, 8.0, 2.0))

	# Build bar tiles (content drawn by BuildTile): framed like the guide's figures.
	t.set_type_variation("BuildTile", "Button")
	var bm := Vector4(0, 0, 0, 0)
	var bn := _bracketed(box(Color(0.051, 0.09, 0.122, 0.94), H.HAIRLINE, z, bm), H.HOLO_DIM, 9.0, 2.0)
	bn.bg_bottom = Color(0.02, 0.035, 0.051, 0.96)
	var bh := _bracketed(box(Color(0.066, 0.14, 0.176, 0.97), H.HOLO_DIM, z, bm), H.HOLO, 11.0, 2.0)
	bh.bg_bottom = Color(0.03, 0.06, 0.08, 0.97)
	var bp := _bracketed(_accented(box(Color(0.2, 0.135, 0.05, 0.98), H.ACCENT, z, bm), ChamferBox.Accent.BOTTOM, H.ACCENT, 0.0, 3.0), H.ACCENT, 11.0, 2.0)
	bp.bg_bottom = Color(0.1, 0.065, 0.025, 0.98)
	var bd := box(Color(H.VOID, 0.85), off_border, z, bm)
	_button_styles(t, "BuildTile", bn, bh, bp, bd)

	# Event feed lines.
	t.set_type_variation("FeedRow", "Button")
	var fm := Vector4(8, 2, 8, 2)
	_button_styles(t, "FeedRow",
			box(Color(H.VOID, 0.72), none, z, fm),
			box(Color(0.06, 0.12, 0.15, 0.9), H.HOLO_DIM, z, fm),
			box(Color(0.16, 0.11, 0.05, 0.92), H.ACCENT, z, fm),
			box(none, none, z, fm))

	# Main menu and pause menu.
	t.set_type_variation("MainMenuButton", "Button")
	var mm := Vector4(22, 10, 22, 10)
	var mn := box(Color(H.VOID, 0.78), H.HOLO_DIM, z, mm)
	var mh := _accented(box(_holo(0.1), H.HOLO, z, mm), ChamferBox.Accent.LEFT, H.HOLO, 0.0, 4.0)
	var mp := _accented(box(_amber(0.24), H.ACCENT, z, mm), ChamferBox.Accent.LEFT, H.ACCENT, 0.0, 4.0)
	var md := box(Color(H.VOID, 0.5), off_border, z, mm)
	_button_styles(t, "MainMenuButton", mn, mh, mp, md)
	_button_colors(t, "MainMenuButton", H.TEXT, H.TEXT_BRIGHT, H.ACCENT_SOFT, H.TEXT_FAINT)
	t.set_font("font", "MainMenuButton", H.font("SemiBold", true, false, 3))
	t.set_font_size("font_size", "MainMenuButton", 20)

	# CheckButton (settings, panels).
	t.set_color("font_color", "CheckButton", H.TEXT)
	t.set_color("font_hover_color", "CheckButton", H.TEXT_BRIGHT)
	t.set_color("font_pressed_color", "CheckButton", H.TEXT)
	for s in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(s, "CheckButton", box(none, none, z, Vector4(4, 2, 4, 2)))
	t.set_stylebox("focus", "CheckButton", _empty())


# --- Panels ---------------------------------------------------------------------

## The guide's panel: blue-black fill, hairline frame, holo corner brackets,
## faint holo scanlines.
static func _panel_box(margins: Vector4 = Vector4(14, 12, 14, 12)) -> ChamferBox:
	var p := box(H.PANEL_BG, H.HAIRLINE, Vector4.ZERO, margins)
	p.bg_bottom = H.PANEL_BG_BOTTOM
	p.scanlines = 0.03
	p.shadow_size = 6.0
	return _bracketed(p, H.HOLO, 14.0, 2.0)


static func _panels(t: Theme) -> void:
	var p := _panel_box()
	t.set_stylebox("panel", "PanelContainer", p)
	t.set_stylebox("panel", "Panel", p)

	t.set_type_variation("TopBarPanel", "PanelContainer")
	var tb := box(H.PANEL_BG, H.HAIRLINE, Vector4.ZERO, Vector4(18, 4, 18, 4))
	tb.bg_bottom = Color(H.VOID, 0.94)
	tb.scanlines = 0.03
	tb.shadow_size = 6.0
	t.set_stylebox("panel", "TopBarPanel", _accented(tb, ChamferBox.Accent.BOTTOM, H.HOLO, 220.0, 2.0))

	t.set_type_variation("InsetPanel", "PanelContainer")
	t.set_stylebox("panel", "InsetPanel", box(H.INSET_BG, H.HAIRLINE, Vector4.ZERO, Vector4(8, 6, 8, 6)))

	t.set_type_variation("SectionPanel", "PanelContainer")
	t.set_stylebox("panel", "SectionPanel", _accented(box(_holo(0.045), Color(0, 0, 0, 0), Vector4.ZERO, Vector4(10, 3, 8, 3)),
			ChamferBox.Accent.LEFT, H.HOLO, 0.0, 2.0))

	t.set_type_variation("ToastPanel", "PanelContainer")
	var to := box(Color(0.04, 0.075, 0.1, 0.95), H.HOLO_DIM, Vector4.ZERO, Vector4(20, 8, 22, 8))
	to.shadow_size = 10.0
	t.set_stylebox("panel", "ToastPanel", _accented(to, ChamferBox.Accent.LEFT, H.GOOD, 0.0, 4.0))

	t.set_type_variation("HintPanel", "PanelContainer")
	var hp := box(Color(0.04, 0.075, 0.1, 0.92), Color(H.ACCENT, 0.55), Vector4.ZERO, Vector4(16, 6, 16, 6))
	t.set_stylebox("panel", "HintPanel", _bracketed(hp, H.ACCENT, 10.0, 2.0))

	t.set_type_variation("MenuPanel", "PanelContainer")
	var mp := box(Color(0.039, 0.071, 0.094, 0.88), H.HAIRLINE, Vector4.ZERO, Vector4(28, 26, 28, 26))
	mp.bg_bottom = Color(H.VOID, 0.92)
	mp.scanlines = 0.035
	t.set_stylebox("panel", "MenuPanel", _bracketed(mp, H.HOLO, 22.0, 2.0))

	t.set_type_variation("TooltipPanel", "PanelContainer")
	var tp := box(Color(0.03, 0.055, 0.075, 0.97), H.HOLO_DIM, Vector4.ZERO, Vector4(12, 8, 12, 8))
	tp.shadow_size = 8.0
	t.set_stylebox("panel", "TooltipPanel", _bracketed(tp, H.HOLO, 10.0, 2.0))


# --- Bars, separators, scroll -------------------------------------------------

static func _misc(t: Theme) -> void:
	t.set_constant("separation", "HBoxContainer", 8)
	t.set_constant("separation", "VBoxContainer", 4)
	var line := StyleBoxLine.new()
	line.color = H.HAIRLINE
	line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)
	t.set_constant("separation", "HSeparator", 9)
	var vline := StyleBoxLine.new()
	vline.color = H.HAIRLINE
	vline.vertical = true
	vline.thickness = 1
	t.set_stylebox("separator", "VSeparator", vline)
	t.set_constant("separation", "VSeparator", 9)

	t.set_stylebox("background", "ProgressBar", box(Color(H.VOID, 0.7), H.HAIRLINE, Vector4.ZERO, Vector4.ZERO))
	t.set_stylebox("fill", "ProgressBar", box(H.HOLO, Color(0, 0, 0, 0), Vector4.ZERO, Vector4.ZERO))
	t.set_color("font_color", "ProgressBar", H.TEXT)
	t.set_font("font", "ProgressBar", H.mono("Medium"))

	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(H.HOLO_DIM, 0.7)
	grab.content_margin_left = 2
	grab.content_margin_right = 2
	var grab_hi := grab.duplicate() as StyleBoxFlat
	grab_hi.bg_color = Color(H.HOLO, 0.85)
	var track := StyleBoxFlat.new()
	track.bg_color = _holo(0.04)
	track.content_margin_left = 2
	track.content_margin_right = 2
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_hi)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_hi)
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("scroll_focus", "VScrollBar", track)

	# Godot's own tooltips (everything with tooltip_text).
	t.set_stylebox("panel", "TooltipPanel", t.get_stylebox("panel", "TooltipPanel"))
	t.set_color("font_color", "TooltipLabel", H.TEXT)
	t.set_font_size("font_size", "TooltipLabel", 14)

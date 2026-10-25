class_name HudThemeBuilder
extends RefCounted
## Builds the one HUD theme (ui/theme.tres) from [HudStyle]: base controls
## plus named type variations every panel shares. Regenerate the file after
## a change here:
##   Godot --headless --path . --script res://scripts/ui/theme/generate_theme.gd
##
## Variations: labels HeaderLabel, SubHeaderLabel, TitleLabel, ValueLabel,
## BigValueLabel, DimLabel, SmallLabel, WarnLabel, BadgeLabel; buttons
## AccentButton, IconButton, RowButton, TabButton, ChipButton, CardButton,
## BuildTile, FeedRow, MainMenuButton; panels (PanelContainer) TopBarPanel,
## InsetPanel, SectionPanel, ToastPanel, HintPanel, MenuPanel, TooltipPanel.

const H := preload("res://scripts/ui/theme/hud_style.gd")


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = H.font("Medium")
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


static func _empty() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


# --- Labels ---------------------------------------------------------------------

static func _labels(t: Theme) -> void:
	t.set_color("font_color", "Label", H.TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.0))

	_label_var(t, "HeaderLabel", H.font("SemiBold", true, false, 1), 14, H.ACCENT)
	_label_var(t, "SubHeaderLabel", H.font("SemiBold", true, false, 1), 13, H.TEXT_DIM)
	_label_var(t, "TitleLabel", H.font("Bold", true), 24, H.TEXT_BRIGHT)
	_label_var(t, "ValueLabel", H.font("SemiBold", false, true), 15, H.TEXT_BRIGHT)
	_label_var(t, "BigValueLabel", H.font("SemiBold", true, true), 19, H.TEXT_BRIGHT)
	_label_var(t, "DimLabel", H.font("Regular"), 14, H.TEXT_DIM)
	_label_var(t, "SmallLabel", H.font("Medium"), 13, H.TEXT_DIM)
	_label_var(t, "WarnLabel", H.font("Medium"), 14, H.BAD)
	_label_var(t, "TooltipLabel", H.font("Regular"), 14, H.TEXT)
	t.set_type_variation("TooltipLabel", "Label")
	# A small boxed tag: hotkeys, rank, counts.
	_label_var(t, "BadgeLabel", H.font("Bold", true, true), 12, H.TEXT)
	var badge := box(Color(0.0, 0.0, 0.0, 0.55), H.HAIRLINE_STRONG, Vector4.ZERO, Vector4(4, 0, 4, 0))
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


static func _buttons(t: Theme) -> void:
	var m := Vector4(14, 7, 14, 7)
	var cut := Vector4(0, 0, 7, 0)
	# Default: raised gunmetal, amber on hover, amber-lit when pressed.
	_button_styles(t, "Button",
			box(H.RAISED_BG, H.HAIRLINE_STRONG, cut, m),
			_accented(box(Color(0.13, 0.15, 0.18, 0.96), Color(1.0, 0.6, 0.24, 0.7), cut, m), ChamferBox.Accent.LEFT, H.ACCENT, 0.0, 2.0),
			_accented(box(Color(0.24, 0.13, 0.05, 0.96), H.ACCENT, cut, m), ChamferBox.Accent.LEFT, H.ACCENT, 0.0, 2.0),
			box(Color(0.06, 0.07, 0.085, 0.8), Color(0.6, 0.67, 0.76, 0.1), cut, m))
	_button_colors(t, "Button", H.TEXT, H.TEXT_BRIGHT, Color(1.0, 0.86, 0.7), Color(0.42, 0.46, 0.52))
	t.set_font("font", "Button", H.font("SemiBold"))
	t.set_font_size("font_size", "Button", 15)
	t.set_constant("h_separation", "Button", 8)
	t.set_constant("icon_max_width", "Button", 18)

	# Accent (primary action).
	t.set_type_variation("AccentButton", "Button")
	var acut := Vector4(7, 0, 7, 0)
	_button_styles(t, "AccentButton",
			_accented(box(Color(0.2, 0.105, 0.04, 0.95), Color(1.0, 0.6, 0.24, 0.8), acut, m), ChamferBox.Accent.BOTTOM, H.ACCENT, 0.0, 2.0),
			_accented(box(Color(0.32, 0.17, 0.06, 0.98), H.ACCENT_SOFT, acut, m), ChamferBox.Accent.BOTTOM, H.ACCENT_SOFT, 0.0, 2.0),
			_accented(box(Color(0.42, 0.22, 0.07, 1.0), H.ACCENT_SOFT, acut, m), ChamferBox.Accent.BOTTOM, Color(1, 0.8, 0.5), 0.0, 2.0),
			box(Color(0.07, 0.07, 0.08, 0.8), Color(0.6, 0.67, 0.76, 0.12), acut, m))
	_button_colors(t, "AccentButton", Color(1.0, 0.9, 0.78), H.TEXT_BRIGHT, H.TEXT_BRIGHT, Color(0.45, 0.47, 0.5))
	t.set_font("font", "AccentButton", H.font("Bold", true, false, 1))
	t.set_font_size("font_size", "AccentButton", 16)

	# Small square tool buttons (close, collapse, steppers).
	t.set_type_variation("IconButton", "Button")
	var im := Vector4(6, 2, 6, 2)
	_button_styles(t, "IconButton",
			box(H.INSET_BG, H.HAIRLINE_STRONG, Vector4.ZERO, im),
			box(Color(0.16, 0.12, 0.08, 0.96), Color(1.0, 0.6, 0.24, 0.75), Vector4.ZERO, im),
			box(Color(0.3, 0.16, 0.06, 0.96), H.ACCENT, Vector4.ZERO, im),
			box(Color(0.03, 0.035, 0.045, 0.5), Color(0.6, 0.67, 0.76, 0.1), Vector4.ZERO, im))
	_button_colors(t, "IconButton", H.TEXT, H.TEXT_BRIGHT, Color(1.0, 0.86, 0.7), Color(0.4, 0.44, 0.5))
	t.set_font("font", "IconButton", H.font("SemiBold", true, true))
	t.set_font_size("font_size", "IconButton", 14)
	t.set_constant("icon_max_width", "IconButton", 14)

	# List rows: flat, a faint lift on hover, amber stripe when pressed.
	t.set_type_variation("RowButton", "Button")
	var rm := Vector4(8, 3, 8, 3)
	_button_styles(t, "RowButton",
			box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), Vector4.ZERO, rm),
			box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), Vector4.ZERO, rm),
			_accented(box(Color(1.0, 0.55, 0.15, 0.13), Color(0, 0, 0, 0), Vector4.ZERO, rm), ChamferBox.Accent.LEFT, H.ACCENT, 0.0, 2.0),
			box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), Vector4.ZERO, rm),
			_accented(box(Color(1.0, 0.55, 0.15, 0.2), Color(0, 0, 0, 0), Vector4.ZERO, rm), ChamferBox.Accent.LEFT, H.ACCENT, 0.0, 2.0))

	# Left panel tabs.
	t.set_type_variation("TabButton", "Button")
	var tm := Vector4(8, 6, 8, 6)
	_button_styles(t, "TabButton",
			_accented(box(Color(0.03, 0.035, 0.045, 0.55), Color(0, 0, 0, 0), Vector4.ZERO, tm), ChamferBox.Accent.BOTTOM, H.HAIRLINE, 0.0, 1.0),
			_accented(box(Color(0.1, 0.11, 0.13, 0.85), Color(0, 0, 0, 0), Vector4.ZERO, tm), ChamferBox.Accent.BOTTOM, H.HAIRLINE_STRONG, 0.0, 1.0),
			_accented(box(Color(0.12, 0.1, 0.08, 0.95), Color(0, 0, 0, 0), Vector4(0, 6, 0, 0), tm), ChamferBox.Accent.TOP, H.ACCENT, 0.0, 2.0),
			box(Color(0, 0, 0, 0.3), Color(0, 0, 0, 0), Vector4.ZERO, tm))
	_button_colors(t, "TabButton", H.TEXT_DIM, H.TEXT, H.TEXT_BRIGHT, H.TEXT_FAINT)
	t.set_font("font", "TabButton", H.font("SemiBold", true, false, 1))
	t.set_font_size("font_size", "TabButton", 14)
	t.set_constant("icon_max_width", "TabButton", 16)
	t.set_constant("h_separation", "TabButton", 5)

	# Filter chips.
	t.set_type_variation("ChipButton", "Button")
	var cm := Vector4(6, 1, 6, 1)
	var ccut := Vector4(0, 0, 4, 0)
	_button_styles(t, "ChipButton",
			box(Color(0.03, 0.035, 0.045, 0.6), H.HAIRLINE, ccut, cm),
			box(Color(0.1, 0.11, 0.13, 0.9), H.HAIRLINE_STRONG, ccut, cm),
			box(Color(0.26, 0.14, 0.05, 0.95), Color(1.0, 0.6, 0.24, 0.9), ccut, cm),
			box(Color(0, 0, 0, 0.2), Color(0.6, 0.67, 0.76, 0.08), ccut, cm))
	_button_colors(t, "ChipButton", H.TEXT_DIM, H.TEXT, Color(1.0, 0.86, 0.7), H.TEXT_FAINT)
	t.set_font("font", "ChipButton", H.font("SemiBold", true, false, 1))
	t.set_font_size("font_size", "ChipButton", 13)
	t.set_constant("icon_max_width", "ChipButton", 12)
	t.set_constant("h_separation", "ChipButton", 4)

	# Pilot cards (content drawn by PilotCard).
	t.set_type_variation("CardButton", "Button")
	var km := Vector4(0, 0, 0, 0)
	var kcut := Vector4(0, 0, 8, 0)
	_button_styles(t, "CardButton",
			box(Color(0.075, 0.087, 0.105, 0.88), Color(0.6, 0.67, 0.76, 0.14), kcut, km),
			box(Color(0.1, 0.115, 0.14, 0.94), Color(0.6, 0.67, 0.76, 0.34), kcut, km),
			box(Color(0.14, 0.1, 0.07, 0.96), H.ACCENT, kcut, km),
			box(Color(0.06, 0.065, 0.075, 0.7), Color(0.6, 0.67, 0.76, 0.1), kcut, km),
			box(Color(0.16, 0.115, 0.08, 0.98), H.ACCENT_SOFT, kcut, km))

	# Build bar tiles (content drawn by BuildTile).
	t.set_type_variation("BuildTile", "Button")
	var bcut := Vector4(0, 10, 0, 10)
	var bm := Vector4(0, 0, 0, 0)
	var bn := box(Color(0.08, 0.092, 0.11, 0.94), Color(0.6, 0.67, 0.76, 0.26), bcut, bm)
	bn.bg_bottom = Color(0.04, 0.045, 0.055, 0.96)
	var bh := box(Color(0.13, 0.14, 0.16, 0.97), Color(1.0, 0.62, 0.28, 0.85), bcut, bm)
	bh.bg_bottom = Color(0.07, 0.075, 0.085, 0.97)
	var bp := _accented(box(Color(0.3, 0.16, 0.05, 0.98), H.ACCENT_SOFT, bcut, bm), ChamferBox.Accent.BOTTOM, H.ACCENT_SOFT, 0.0, 3.0)
	bp.bg_bottom = Color(0.16, 0.08, 0.03, 0.98)
	var bd := box(Color(0.05, 0.055, 0.065, 0.9), Color(0.6, 0.67, 0.76, 0.12), bcut, bm)
	_button_styles(t, "BuildTile", bn, bh, bp, bd)

	# Event feed lines.
	t.set_type_variation("FeedRow", "Button")
	var fm := Vector4(8, 2, 8, 2)
	_button_styles(t, "FeedRow",
			box(Color(0.03, 0.035, 0.045, 0.72), Color(0, 0, 0, 0), Vector4(0, 0, 6, 0), fm),
			box(Color(0.1, 0.11, 0.13, 0.9), H.HAIRLINE_STRONG, Vector4(0, 0, 6, 0), fm),
			box(Color(0.18, 0.11, 0.06, 0.92), H.ACCENT, Vector4(0, 0, 6, 0), fm),
			box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), Vector4.ZERO, fm))

	# Main menu and pause menu.
	t.set_type_variation("MainMenuButton", "Button")
	var mm := Vector4(22, 10, 22, 10)
	var mcut := Vector4(0, 0, 10, 0)
	var mn := box(Color(0.07, 0.08, 0.1, 0.85), H.HAIRLINE_STRONG, mcut, mm)
	var mh := _accented(box(Color(0.15, 0.12, 0.09, 0.95), Color(1.0, 0.6, 0.24, 0.8), mcut, mm), ChamferBox.Accent.LEFT, H.ACCENT, 0.0, 4.0)
	var mp := _accented(box(Color(0.3, 0.16, 0.06, 0.98), H.ACCENT, mcut, mm), ChamferBox.Accent.LEFT, Color(1, 0.8, 0.5), 0.0, 4.0)
	var md := box(Color(0.04, 0.045, 0.055, 0.6), Color(0.6, 0.67, 0.76, 0.08), mcut, mm)
	_button_styles(t, "MainMenuButton", mn, mh, mp, md)
	_button_colors(t, "MainMenuButton", H.TEXT, H.TEXT_BRIGHT, Color(1.0, 0.86, 0.7), Color(0.4, 0.43, 0.48))
	t.set_font("font", "MainMenuButton", H.font("SemiBold", true, false, 2))
	t.set_font_size("font_size", "MainMenuButton", 20)

	# CheckButton (settings, panels).
	t.set_color("font_color", "CheckButton", H.TEXT)
	t.set_color("font_hover_color", "CheckButton", H.TEXT_BRIGHT)
	t.set_color("font_pressed_color", "CheckButton", H.TEXT)
	for s in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(s, "CheckButton", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), Vector4.ZERO, Vector4(4, 2, 4, 2)))
	t.set_stylebox("focus", "CheckButton", _empty())


# --- Panels ---------------------------------------------------------------------

static func _panel_box(margins: Vector4 = Vector4(14, 12, 14, 12)) -> ChamferBox:
	var p := box(H.PANEL_BG, H.HAIRLINE, Vector4(0, 12, 0, 12), margins)
	p.bg_bottom = H.PANEL_BG_BOTTOM
	p.scanlines = 0.014
	p.shadow_size = 6.0
	p.corner_ticks = true
	p.accent_color = H.ACCENT
	return _accented(p, ChamferBox.Accent.TOP, H.ACCENT, 56.0, 2.0)


static func _panels(t: Theme) -> void:
	var p := _panel_box()
	t.set_stylebox("panel", "PanelContainer", p)
	t.set_stylebox("panel", "Panel", p)

	t.set_type_variation("TopBarPanel", "PanelContainer")
	var tb := box(H.PANEL_BG, H.HAIRLINE, Vector4(0, 0, 14, 14), Vector4(18, 4, 18, 4))
	tb.bg_bottom = Color(0.03, 0.035, 0.045, 0.94)
	tb.scanlines = 0.012
	tb.shadow_size = 6.0
	t.set_stylebox("panel", "TopBarPanel", _accented(tb, ChamferBox.Accent.BOTTOM, H.ACCENT, 160.0, 2.0))

	t.set_type_variation("InsetPanel", "PanelContainer")
	t.set_stylebox("panel", "InsetPanel", box(H.INSET_BG, Color(0.6, 0.67, 0.76, 0.12), Vector4.ZERO, Vector4(8, 6, 8, 6)))

	t.set_type_variation("SectionPanel", "PanelContainer")
	t.set_stylebox("panel", "SectionPanel", _accented(box(Color(1, 1, 1, 0.035), Color(0, 0, 0, 0), Vector4(0, 0, 6, 0), Vector4(10, 3, 8, 3)),
			ChamferBox.Accent.LEFT, H.ACCENT, 0.0, 2.0))

	t.set_type_variation("ToastPanel", "PanelContainer")
	var to := box(Color(0.05, 0.06, 0.075, 0.94), H.HAIRLINE_STRONG, Vector4(12, 0, 12, 0), Vector4(20, 8, 22, 8))
	to.shadow_size = 10.0
	t.set_stylebox("panel", "ToastPanel", _accented(to, ChamferBox.Accent.LEFT, H.GOOD, 0.0, 4.0))

	t.set_type_variation("HintPanel", "PanelContainer")
	var hp := box(Color(0.05, 0.06, 0.075, 0.9), Color(1.0, 0.6, 0.24, 0.5), Vector4(8, 0, 8, 0), Vector4(16, 6, 16, 6))
	t.set_stylebox("panel", "HintPanel", hp)

	t.set_type_variation("MenuPanel", "PanelContainer")
	var mp := box(Color(0.035, 0.042, 0.055, 0.86), H.HAIRLINE, Vector4(0, 18, 0, 18), Vector4(28, 26, 28, 26))
	mp.bg_bottom = Color(0.02, 0.025, 0.035, 0.9)
	mp.scanlines = 0.016
	mp.shadow_size = 14.0
	mp.corner_ticks = true
	t.set_stylebox("panel", "MenuPanel", _accented(mp, ChamferBox.Accent.TOP, H.ACCENT, 90.0, 3.0))

	t.set_type_variation("TooltipPanel", "PanelContainer")
	var tp := box(Color(0.03, 0.036, 0.047, 0.97), H.HAIRLINE_STRONG, Vector4(0, 8, 0, 8), Vector4(12, 8, 12, 8))
	tp.shadow_size = 8.0
	t.set_stylebox("panel", "TooltipPanel", _accented(tp, ChamferBox.Accent.TOP, H.ACCENT, 40.0, 2.0))


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

	t.set_stylebox("background", "ProgressBar", box(Color(0, 0, 0, 0.55), Color(0.6, 0.67, 0.76, 0.2), Vector4.ZERO, Vector4.ZERO))
	t.set_stylebox("fill", "ProgressBar", box(H.ACCENT, Color(0, 0, 0, 0), Vector4.ZERO, Vector4.ZERO))
	t.set_color("font_color", "ProgressBar", H.TEXT)

	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(0.6, 0.67, 0.76, 0.3)
	grab.content_margin_left = 2
	grab.content_margin_right = 2
	var grab_hi := grab.duplicate() as StyleBoxFlat
	grab_hi.bg_color = Color(1.0, 0.6, 0.24, 0.75)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.03)
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

class_name UIUtil
extends RefCounted
## Small helpers shared by the HUD widgets.


static func label(text: String, variation: StringName = &"") -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


static func spacer(width: float = 0.0) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if width > 0.0:
		c.custom_minimum_size.x = width
	else:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


## Buttons never take keyboard focus, so WASD keeps panning after a click.
static func button(text: String, variation: StringName = &"") -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.focus_mode = Control.FOCUS_NONE
	return b


## Makes every Control under [param node] ignore keyboard focus.
static func no_focus(node: Node) -> void:
	if node is Control:
		(node as Control).focus_mode = Control.FOCUS_NONE
	for c in node.get_children():
		no_focus(c)


## Children of a custom-content button must not swallow its mouse events.
static func ignore_mouse(node: Node) -> void:
	for c in node.get_children():
		if c is Control:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		ignore_mouse(c)


## Small coloured rank badge ("VET") with the rank name as tooltip.
static func rank_badge(rank: int) -> Label:
	var l := label(Reputation.RANK_BADGES[clampi(rank, 0, Reputation.RANK_BADGES.size() - 1)], &"DimLabel")
	l.add_theme_color_override("font_color", Reputation.RANK_COLORS[clampi(rank, 0, Reputation.RANK_COLORS.size() - 1)])
	l.add_theme_font_size_override("font_size", 12)
	l.custom_minimum_size.x = 30.0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.tooltip_text = Reputation.rank_name(rank)
	return l


## "3:05" from sim seconds.
static func clock(t: float) -> String:
	var s := int(t)
	return "%d:%02d" % [floori(s / 60.0), s % 60]


## "2,000" style thousands separators.
static func amount(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if value < 0 else "") + s + out


## "Miner" -> "Miners", "Mercenary" -> "Mercenaries".
static func plural(word: String) -> String:
	if word.ends_with("y") and word.length() > 1 and not "aeiou".contains(word[word.length() - 2]):
		return word.left(word.length() - 1) + "ies"
	return word + "s"

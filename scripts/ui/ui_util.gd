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
## An "x" IconButton (close, cancel) gets the close icon instead of the letter.
static func button(text: String, variation: StringName = &"") -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.focus_mode = Control.FOCUS_NONE
	if text == "x" and variation == &"IconButton":
		b.text = ""
		b.icon = HudStyle.icon(&"close")
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return b


## A small "-" / "+" IconButton for steppers.
static func step_button(text: String, tip: String = "", size: Vector2 = Vector2(28.0, 24.0)) -> Button:
	var b := button(text, &"IconButton")
	b.custom_minimum_size = size
	b.tooltip_text = tip
	return b


## "Title ... [-] value [+]" row added to [param parent]; [param step] gets
## -1 or 1. Returns [value Label, minus Button, plus Button].
static func stepper_row(parent: Container, title: String, step: Callable, minus_tip: String = "", plus_tip: String = "") -> Array:
	var row := HBoxContainer.new()
	parent.add_child(row)
	row.add_child(label(title, &"DimLabel"))
	row.add_child(spacer())
	var minus := step_button("-", minus_tip)
	minus.pressed.connect(step.bind(-1))
	row.add_child(minus)
	var value := label("", &"ValueLabel")
	value.custom_minimum_size.x = 74.0
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(value)
	var plus := step_button("+", plus_tip)
	plus.pressed.connect(step.bind(1))
	row.add_child(plus)
	return [value, minus, plus]


## A thin bar meter (PipMeter BAR, 0..1).
static func bar(color: Color, size: Vector2) -> PipMeter:
	var b := PipMeter.new()
	b.style = PipMeter.Style.BAR
	b.max_value = 1.0
	b.color = color
	b.custom_minimum_size = size
	return b


## "Title [bar] text" in a 3-column [param grid]. Returns [PipMeter, Label].
static func bar_row(grid: GridContainer, title: String, color: Color, title_width: float, bar_size: Vector2) -> Array:
	var l := label(title, &"DimLabel")
	l.custom_minimum_size.x = title_width
	grid.add_child(l)
	var b := bar(color, bar_size)
	grid.add_child(b)
	var t := label("", &"DimLabel")
	t.custom_minimum_size.x = 80.0
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(t)
	return [b, t]


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


## "3:05" from sim seconds (Fmt.clock).
static func clock(t: float) -> String:
	return Fmt.clock(t)


## "2,000" style thousands separators (Fmt.amount).
static func amount(value: int) -> String:
	return Fmt.amount(value)


## "Miner" -> "Miners", "Mercenary" -> "Mercenaries" (Fmt.plural).
static func plural(word: String) -> String:
	return Fmt.plural(word)

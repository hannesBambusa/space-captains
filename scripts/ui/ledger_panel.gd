class_name LedgerPanel
extends PanelContainer
## The credit log (Economy.ledger, see [Ledger]): L or a click on the
## credits in the top bar opens it, L, Esc or the close button shuts it;
## nothing pauses. A centred overlay between the left panel and the right
## column, from under the top bar down to the build bar: the list needs
## more width than the 380 px right column, and the right column already
## shares its room between the minimap, the pilot list and the selection
## panels. Header: credits now, the last 10 sim minutes in / out / net and
## the rate per minute; a bar per category for those 10 minutes (in green
## to the right, out red to the left); then every entry newest first (time,
## category, label, amount, balance after), filtered All / In / Out. Escrow
## payouts are note lines (amount in brackets, already reserved). Refreshes
## live while open, at most [constant REFRESH] times a second.

const H := preload("res://scripts/ui/theme/hud_style.gd")
const WIDTH := 780.0
## Sim seconds the header and the breakdown look back.
const WINDOW := 600.0
const REFRESH := 0.25
const TOP := 64.0
const GAP := 10.0
const BAR_ROW := 18.0
const NAME_W := 120.0
const AMOUNT_W := 70.0

enum Filter { ALL, IN, OUT }

var hud: HUD
var filter := Filter.ALL

var _credits: Label
var _in: Label
var _out: Label
var _net: Label
var _rate: Label
var _window_note: Label
var _bars: Control
var _bars_data: Array = []
var _list: VBoxContainer
var _empty: Label
var _scroll: ScrollContainer
var _rows: Array[HBoxContainer] = []
var _dirty := true
var _timer := 0.0
var _f_name: Font
var _f_mono: Font


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.x = WIDTH
	_f_name = H.font("Medium", true)
	_f_mono = H.mono("Medium")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	# Title row.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	v.add_child(top)
	top.add_child(H.icon_rect(&"credits", 18.0, H.CREDITS))
	var t := UIUtil.label("LEDGER", &"HeaderLabel")
	t.add_theme_font_size_override("font_size", 18)
	top.add_child(t)
	top.add_child(UIUtil.label("Credits in and out", &"DimLabel"))
	top.add_child(UIUtil.spacer())
	top.add_child(UIUtil.label("L or Esc: close", &"SmallLabel"))
	var close := UIUtil.button("x", &"IconButton")
	close.custom_minimum_size = Vector2(26.0, 22.0)
	close.tooltip_text = "Close the ledger (L, Esc)"
	close.pressed.connect(close_panel)
	top.add_child(close)
	# Summary row.
	var sum := HBoxContainer.new()
	sum.add_theme_constant_override("separation", 18)
	v.add_child(sum)
	_credits = _stat(sum, "CREDITS", &"BigValueLabel", H.CREDITS)
	_in = _stat(sum, "IN", &"BigValueLabel", H.GOOD)
	_out = _stat(sum, "OUT", &"BigValueLabel", H.BAD)
	_net = _stat(sum, "NET", &"BigValueLabel", H.TEXT_BRIGHT)
	_rate = _stat(sum, "PER MIN", &"BigValueLabel", H.TEXT_BRIGHT)
	# Breakdown.
	var bh := HBoxContainer.new()
	v.add_child(bh)
	bh.add_child(UIUtil.label("BY CATEGORY", &"SubHeaderLabel"))
	bh.add_child(UIUtil.spacer())
	_window_note = UIUtil.label("", &"SmallLabel")
	bh.add_child(_window_note)
	_bars = Control.new()
	_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars.draw.connect(_draw_bars)
	v.add_child(_bars)
	v.add_child(HSeparator.new())
	# Filter chips and the column heads.
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 4)
	v.add_child(chips)
	chips.add_child(UIUtil.label("ENTRIES", &"SubHeaderLabel"))
	chips.add_child(UIUtil.spacer(10.0))
	var group := ButtonGroup.new()
	for f: int in [Filter.ALL, Filter.IN, Filter.OUT]:
		var b := UIUtil.button(["ALL", "IN", "OUT"][f], &"ChipButton")
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = f == filter
		b.custom_minimum_size = Vector2(48.0, 22.0)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.tooltip_text = ["Every entry", "Credits that came in", "Credits that went out (and payouts from escrow)"][f]
		b.pressed.connect(func() -> void:
			filter = f as Filter
			_dirty = true
			_scroll.scroll_vertical = 0)
		chips.add_child(b)
	v.add_child(_row_cells(["TIME", "CATEGORY", "ENTRY", "AMOUNT", "BALANCE"], &"SubHeaderLabel"))
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.focus_mode = Control.FOCUS_NONE
	v.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 1)
	_scroll.add_child(_list)
	_empty = UIUtil.label("Nothing yet.", &"DimLabel")
	_list.add_child(_empty)
	UIUtil.no_focus(self)
	Economy.ledger.recorded.connect(func() -> void: _dirty = true)


func setup(owner_hud: HUD) -> void:
	hud = owner_hud


func toggle() -> void:
	if visible:
		close_panel()
	else:
		open_panel()


func open_panel() -> void:
	visible = true
	_dirty = true
	_place()
	_refresh()
	_scroll.scroll_vertical = 0


func close_panel() -> void:
	visible = false


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel") and not event.is_echo():
		close_panel()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH
	_place()
	_refresh()


## Centred, from under the top bar to just above the build bar.
func _place() -> void:
	var root := get_parent() as Control
	if root == null:
		return
	var vp := root.size
	var bottom := vp.y - 12.0
	if hud and hud.build_menu and hud.build_menu.visible:
		bottom = hud.build_menu.get_global_rect().position.y - root.get_global_rect().position.y - GAP
	var r := Rect2(Vector2(roundf((vp.x - WIDTH) * 0.5), TOP), Vector2(WIDTH, maxf(bottom - TOP, 240.0)))
	if position != r.position:
		position = r.position
	if size != r.size:
		size = r.size


func _refresh() -> void:
	var lg := Economy.ledger
	_credits.text = Fmt.amount(Economy.credits)
	var since := SimClock.time - WINDOW
	var s := lg.summary(since)
	var net := int(s["in"]) - int(s["out"])
	_in.text = "+" + Fmt.amount(int(s["in"]))
	_out.text = "-" + Fmt.amount(int(s["out"]))
	_net.text = _signed(net)
	_net.add_theme_color_override("font_color", H.GOOD if net > 0 else (H.BAD if net < 0 else H.TEXT_BRIGHT))
	var minutes := clampf(SimClock.time, 60.0, WINDOW) / 60.0
	var rate := roundi(float(net) / minutes)
	_rate.text = _signed(rate)
	_rate.add_theme_color_override("font_color", H.GOOD if rate > 0 else (H.BAD if rate < 0 else H.TEXT_BRIGHT))
	_window_note.text = "last %d sim min" % roundi(minutes)
	_bars_data.clear()
	var cats: Dictionary = s["cats"]
	for c in Ledger.CATEGORIES:
		if cats.has(c):
			_bars_data.append([c, int(cats[c][0]), int(cats[c][1])])
	for c: String in cats:
		if not Ledger.CATEGORIES.has(c):
			_bars_data.append([c, int(cats[c][0]), int(cats[c][1])])
	_bars.custom_minimum_size.y = maxf(float(_bars_data.size()), 1.0) * BAR_ROW
	_bars.queue_redraw()
	if _dirty:
		_dirty = false
		_fill_list()


func _fill_list() -> void:
	var shown := 0
	var entries := Economy.ledger.entries
	for i in range(entries.size() - 1, -1, -1):
		var e := entries[i]
		var a := int(e["amt"])
		var held := int(e.get("held", 0))
		if filter == Filter.IN and a <= 0:
			continue
		if filter == Filter.OUT and a >= 0 and held <= 0:
			continue
		if shown >= _rows.size():
			var row := _row_cells(["", "", "", "", ""], &"")
			_list.add_child(row)
			_rows.append(row)
		_fill_row(_rows[shown], e)
		shown += 1
	for k in range(shown, _rows.size()):
		_rows[k].visible = false
	_empty.visible = shown == 0
	_empty.text = "Nothing yet." if entries.is_empty() else "No entries for this filter."


func _fill_row(row: HBoxContainer, e: Dictionary) -> void:
	row.visible = true
	var a := int(e["amt"])
	var held := int(e.get("held", 0))
	var n := int(e.get("n", 1))
	var cells := row.get_children()
	(cells[0] as Label).text = _time_text(float(e["t"]))
	(cells[1] as Label).text = String(e["cat"])
	var entry := cells[2] as Label
	# Lines about a forward station's system: "[Ostra] Upkeep: Eris Station".
	var tag := EventLog.tag(StringName(e.get("sys", "")))
	var label := (tag + " " if not tag.is_empty() else "") + String(e["label"])
	entry.text = label + ("  x%d" % n if n > 1 else "")
	var tip := "%s, %s" % [String(e["cat"]), label]
	if n > 1:
		tip += "\n%d changes from %s to %s" % [n, _time_text(float(e["t0"])), _time_text(float(e["t"]))]
	if held > 0 and String(e["cat"]) == Ledger.HAULING:
		tip += "\nOre the haulers kept, worth about %s cr at the Factory price: your credits did not change." % Fmt.amount(held)
	elif held > 0:
		tip += "\nPaid %s cr out of credits reserved earlier (the Escrow line when it was posted): your credits did not change now." % Fmt.amount(held)
	entry.tooltip_text = tip
	var amt := cells[3] as Label
	if held > 0 and a == 0:
		amt.text = "(%s)" % Fmt.amount(held)
		amt.add_theme_color_override("font_color", H.TEXT_DIM)
	else:
		amt.text = _signed(a)
		amt.add_theme_color_override("font_color", H.GOOD if a > 0 else H.BAD)
	(cells[4] as Label).text = Fmt.amount(int(e["bal"]))


## One list row (or the column heads with [param variation]).
func _row_cells(texts: Array, variation: StringName) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var widths := [70.0, 110.0, 0.0, 96.0, 90.0]
	for i in 5:
		var heads := variation != &""
		var l := UIUtil.label(texts[i], variation if heads else (&"NumberLabel" if i in [0, 3, 4] else (&"SmallLabel" if i == 1 else &"")))
		if widths[i] > 0.0:
			l.custom_minimum_size.x = widths[i]
		else:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.clip_text = true
			l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			l.mouse_filter = Control.MOUSE_FILTER_PASS
		if i >= 3:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if not heads and i == 0:
			l.add_theme_color_override("font_color", H.TEXT_DIM)
			l.add_theme_font_size_override("font_size", 13)
		if not heads and i == 4:
			l.add_theme_color_override("font_color", H.TEXT_DIM)
		row.add_child(l)
	if variation != &"":
		# Room for the list's scroll bar, so the heads line up.
		row.add_child(UIUtil.spacer(12.0))
	return row


func _stat(parent: HBoxContainer, title: String, variation: StringName, color: Color) -> Label:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	parent.add_child(box)
	box.add_child(UIUtil.label(title, &"SubHeaderLabel"))
	var l := UIUtil.label("", variation)
	l.add_theme_color_override("font_color", color)
	box.add_child(l)
	return l


## Out bars grow left from the centre line, in bars right; amounts at the
## bar ends. Scaled to the biggest single amount.
func _draw_bars() -> void:
	var w := _bars.size.x
	if _bars_data.is_empty():
		_bars.draw_string(_f_name, Vector2(0.0, 13.0), "Nothing in the last 10 minutes.", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, H.TEXT_DIM)
		return
	var peak := 1
	for d: Array in _bars_data:
		peak = maxi(peak, maxi(int(d[1]), int(d[2])))
	var mid := NAME_W + (w - NAME_W) * 0.5
	var half := (w - NAME_W) * 0.5 - AMOUNT_W
	_bars.draw_line(Vector2(mid, 0.0), Vector2(mid, _bars_data.size() * BAR_ROW), Color(H.HAIRLINE_STRONG, 0.8), 1.0)
	for k in _bars_data.size():
		var d: Array = _bars_data[k]
		var y := float(k) * BAR_ROW
		_bars.draw_string(_f_name, Vector2(0.0, y + 13.0), String(d[0]), HORIZONTAL_ALIGNMENT_LEFT, NAME_W - 6.0, 13, H.TEXT)
		var a_in := int(d[1])
		var a_out := int(d[2])
		if a_in > 0:
			var bw := maxf(half * float(a_in) / float(peak), 2.0)
			_bars.draw_rect(Rect2(mid + 1.0, y + 4.0, bw, BAR_ROW - 8.0), Color(H.GOOD, 0.8))
			_bars.draw_string(_f_mono, Vector2(mid + bw + 6.0, y + 13.0), "+" + Fmt.amount(a_in), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, H.GOOD)
		if a_out > 0:
			var bw := maxf(half * float(a_out) / float(peak), 2.0)
			_bars.draw_rect(Rect2(mid - 1.0 - bw, y + 4.0, bw, BAR_ROW - 8.0), Color(H.BAD, 0.8))
			_bars.draw_string(_f_mono, Vector2(mid - bw - 6.0 - AMOUNT_W, y + 13.0), "-" + Fmt.amount(a_out), HORIZONTAL_ALIGNMENT_RIGHT, AMOUNT_W, 12, H.BAD)


static func _signed(v: int) -> String:
	if v > 0:
		return "+" + Fmt.amount(v)
	if v < 0:
		return "-" + Fmt.amount(-v)
	return "0"


static func _time_text(t: float) -> String:
	var s := int(t)
	return "%02d:%02d:%02d" % [floori(s / 3600.0), floori(s / 60.0) % 60, s % 60]

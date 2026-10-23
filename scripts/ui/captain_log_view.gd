class_name CaptainLogView
extends VBoxContainer
## The captain panel's Log tab: the captain's decision log (CaptainLog),
## newest first. Each row: time, an outcome badge (green accepted, red
## refused or failed, amber combat and retreats, blue money, gold career),
## the headline and the reason in muted text; click a row for the numbers.
## A filter row picks All / Contracts / Combat / Money / Career. New entries
## are added as rows when written (no rebuild); a coalesced repeat updates
## its row and moves it to the top.

const ACCEPTED_COLOR := Color(0.42, 0.9, 0.52)
const REFUSED_COLOR := Color(1.0, 0.42, 0.36)
const COMBAT_COLOR := Color(1.0, 0.7, 0.3)
const MONEY_COLOR := Color(0.45, 0.72, 1.0)
const CAREER_COLOR := Color(1.0, 0.84, 0.35)
const REST_COLOR := Color(0.6, 0.66, 0.74)
const WHY_COLOR := Color(0.58, 0.64, 0.72)
const DETAIL_COLOR := Color(0.72, 0.78, 0.86)

## Width of the text column, pixels (the panel's content width).
@export var row_width: float = 340.0

var captain: Captain
var filter: CaptainLog.Filter = CaptainLog.Filter.ALL

var _filters: Array[Button] = []
var _scroll: ScrollContainer
var _list: VBoxContainer
var _empty: Label
## Entry serial -> row.
var _rows: Dictionary = {}
var _expanded: Dictionary = {}


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var fr := HBoxContainer.new()
	fr.add_theme_constant_override("separation", 4)
	add_child(fr)
	var group := ButtonGroup.new()
	for i in CaptainLog.FILTER_NAMES.size():
		var b := UIUtil.button(CaptainLog.FILTER_NAMES[i], &"IconButton")
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == filter
		b.custom_minimum_size = Vector2(0.0, 24.0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_set_filter.bind(i))
		fr.add_child(b)
		_filters.append(b)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_empty = UIUtil.label("No decisions logged yet.", &"DimLabel")
	_list.add_child(_empty)


## Shows [param c]'s log (rebuilds once; later entries are appended).
func show_captain(c: Captain) -> void:
	if c == captain:
		return
	if captain and captain.flight_log.written.is_connected(_on_written):
		captain.flight_log.written.disconnect(_on_written)
	captain = c
	_expanded.clear()
	_rebuild()
	if captain:
		captain.flight_log.written.connect(_on_written)


func row_count() -> int:
	return _rows.size()


## Shown rows top to bottom (tests).
func visible_headlines() -> PackedStringArray:
	var out: PackedStringArray = []
	for r in _list.get_children():
		if r != _empty and (r as Control).visible:
			out.append(String(r.get_meta(&"headline", "")))
	return out


func _set_filter(f: int) -> void:
	filter = f as CaptainLog.Filter
	for r in _list.get_children():
		if r != _empty:
			r.visible = CaptainLog.matches(r.get_meta(&"entry") as CaptainLog.Entry, filter)
	_update_empty()


func _rebuild() -> void:
	for r in _list.get_children():
		if r != _empty:
			_list.remove_child(r)
			r.queue_free()
	_rows.clear()
	if captain:
		for e in captain.flight_log.entries:
			_add_row(e)
	_update_empty()
	_scroll.scroll_vertical = 0


func _on_written(e: CaptainLog.Entry) -> void:
	var r := _rows.get(e.serial) as Control
	if r:
		_fill_row(r, e)
		_list.move_child(r, 1)
	else:
		_add_row(e)
		_prune()
	_update_empty()


## Drops rows of entries that fell out of the capped log.
func _prune() -> void:
	if captain == null or _rows.size() <= CaptainLog.MAX_ENTRIES:
		return
	var alive := {}
	for e in captain.flight_log.entries:
		alive[e.serial] = true
	for serial: int in _rows.keys():
		if not alive.has(serial):
			var r := _rows[serial] as Control
			_rows.erase(serial)
			_list.remove_child(r)
			r.queue_free()


func _update_empty() -> void:
	var any := false
	for r in _list.get_children():
		if r != _empty and (r as Control).visible:
			any = true
			break
	_empty.visible = not any
	_empty.text = "No decisions logged yet." if _rows.is_empty() else "Nothing under this filter."


func _add_row(e: CaptainLog.Entry) -> void:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.add_theme_stylebox_override("panel", _row_style(false))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	row.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	v.add_child(top)
	var time := UIUtil.label("", &"DimLabel")
	time.name = "Time"
	time.custom_minimum_size.x = 38.0
	time.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	time.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(time)
	var badge := PanelContainer.new()
	badge.name = "Badge"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var bl := UIUtil.label("", &"HeaderLabel")
	bl.name = "Tag"
	bl.custom_minimum_size.x = 30.0
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.add_theme_font_size_override("font_size", 10)
	badge.add_child(bl)
	top.add_child(badge)
	var head := UIUtil.label("", &"")
	head.name = "Headline"
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.custom_minimum_size.x = row_width - 100.0
	head.add_theme_font_size_override("font_size", 13)
	top.add_child(head)
	var why := UIUtil.label("", &"DimLabel")
	why.name = "Why"
	why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	why.add_theme_font_size_override("font_size", 12)
	why.add_theme_color_override("font_color", WHY_COLOR)
	var det := UIUtil.label("", &"DimLabel")
	det.name = "Detail"
	det.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	det.add_theme_font_size_override("font_size", 11)
	det.add_theme_color_override("font_color", DETAIL_COLOR)
	for l: Label in [why, det]:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size.x = row_width - 60.0
	var ind := UIUtil.spacer(44.0)
	var wr := HBoxContainer.new()
	wr.add_theme_constant_override("separation", 0)
	wr.add_child(ind)
	var wv := VBoxContainer.new()
	wv.add_theme_constant_override("separation", 2)
	wv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wv.add_child(why)
	wv.add_child(det)
	wr.add_child(wv)
	v.add_child(wr)
	row.set_meta(&"why", why)
	row.set_meta(&"detail", det)
	row.set_meta(&"time", time)
	row.set_meta(&"tag", bl)
	row.set_meta(&"badge", badge)
	row.set_meta(&"head", head)
	row.gui_input.connect(_on_row_input.bind(row))
	row.mouse_entered.connect(func() -> void: row.add_theme_stylebox_override("panel", _row_style(true)))
	row.mouse_exited.connect(func() -> void: row.add_theme_stylebox_override("panel", _row_style(false)))
	_list.add_child(row)
	_list.move_child(row, 1)
	_rows[e.serial] = row
	_fill_row(row, e)


func _fill_row(row: Control, e: CaptainLog.Entry) -> void:
	row.set_meta(&"entry", e)
	row.set_meta(&"headline", e.headline)
	var color := badge_color(e)
	(row.get_meta(&"time") as Label).text = UIUtil.clock(e.last_time)
	var tag := row.get_meta(&"tag") as Label
	tag.text = badge_text(e)
	tag.add_theme_color_override("font_color", Color(0.05, 0.07, 0.1))
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 3.0
	sb.content_margin_right = 3.0
	sb.content_margin_top = 1.0
	sb.content_margin_bottom = 1.0
	(row.get_meta(&"badge") as PanelContainer).add_theme_stylebox_override("panel", sb)
	var head := row.get_meta(&"head") as Label
	head.text = e.headline + (" (x%d since %s)" % [e.count, UIUtil.clock(e.time)] if e.count > 1 else "")
	var why := row.get_meta(&"why") as Label
	why.text = e.why
	why.visible = not e.why.is_empty()
	var det := row.get_meta(&"detail") as Label
	det.text = e.detail
	det.visible = _expanded.has(e.serial) and not e.detail.is_empty()
	row.tooltip_text = "" if e.detail.is_empty() else ("Click to hide the numbers." if det.visible else "Click for the numbers.")
	row.visible = CaptainLog.matches(e, filter)


func _on_row_input(event: InputEvent, row: Control) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var e := row.get_meta(&"entry") as CaptainLog.Entry
	if _expanded.has(e.serial):
		_expanded.erase(e.serial)
	else:
		_expanded[e.serial] = true
	_fill_row(row, e)
	accept_event()


## Shows or hides the numbers of the row for entry [param serial].
func expand(serial: int, on: bool) -> void:
	var r := _rows.get(serial) as Control
	if r == null:
		return
	if on:
		_expanded[serial] = true
	else:
		_expanded.erase(serial)
	_fill_row(r, r.get_meta(&"entry") as CaptainLog.Entry)


static func badge_color(e: CaptainLog.Entry) -> Color:
	match e.outcome:
		CaptainLog.Outcome.ACCEPTED:
			return ACCEPTED_COLOR
		CaptainLog.Outcome.REFUSED, CaptainLog.Outcome.FAILED:
			return REFUSED_COLOR
	match e.kind:
		CaptainLog.Kind.COMBAT, CaptainLog.Kind.RETREAT, CaptainLog.Kind.FLEET, CaptainLog.Kind.LOSS:
			return COMBAT_COLOR
		CaptainLog.Kind.REPAIR, CaptainLog.Kind.PURCHASE:
			return MONEY_COLOR
		CaptainLog.Kind.CAREER, CaptainLog.Kind.TRAIT, CaptainLog.Kind.RANK:
			return CAREER_COLOR
	return REST_COLOR


static func badge_text(e: CaptainLog.Entry) -> String:
	match e.outcome:
		CaptainLog.Outcome.ACCEPTED:
			return "YES"
		CaptainLog.Outcome.REFUSED:
			return "NO"
		CaptainLog.Outcome.FAILED:
			return "FAIL"
	match e.kind:
		CaptainLog.Kind.COMBAT:
			return "CMBT"
		CaptainLog.Kind.RETREAT:
			return "RUN"
		CaptainLog.Kind.FLEET:
			return "FLT"
		CaptainLog.Kind.LOSS:
			return "EJCT"
		CaptainLog.Kind.REPAIR:
			return "FIX"
		CaptainLog.Kind.PURCHASE:
			return "BUY"
		CaptainLog.Kind.CAREER:
			return "JOB"
		CaptainLog.Kind.TRAIT:
			return "TRT"
		CaptainLog.Kind.RANK:
			return "RANK"
		CaptainLog.Kind.REST:
			return "REST"
	return "INFO"


static var _styles: Array[StyleBoxFlat] = []


static func _row_style(hover: bool) -> StyleBoxFlat:
	if _styles.is_empty():
		_styles = [_make_row_style(false), _make_row_style(true)]
	return _styles[1 if hover else 0]


static func _make_row_style(hover: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.2, 0.27, 0.55) if hover else Color(0.1, 0.13, 0.18, 0.45)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 6.0
	sb.content_margin_right = 6.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	return sb

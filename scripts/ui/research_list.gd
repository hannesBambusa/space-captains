class_name ResearchList
extends VBoxContainer
## Bottom-left list of the funded research, above the contract list, floating
## over space like the pilot and contract lists: a title row (RESEARCH, the
## count, the researchers and their wages, collapse) over a rule line, then
## one outlined row per project that is worked on or was started (field
## coloured icon, name, thin progress bar, % and time left, "1 res"). A
## started project nobody works on, or one whose researcher is unpaid, is
## dimmed with the reason. Funded projects not started yet are one dim
## "+N queued" line. Hidden while nothing is funded or no Science Lab stands
## (research is global, so it also shows while another system is viewed).
## Click a row: the Science Lab is selected with that project in view; hover:
## the project's rich tooltip (ResearchTip: benefits, cost, progress). A
## finished project flashes for [member flash_time] seconds and posts a
## "Research done" toast. The HUD places it (HUD._layout_bottom_left).

const H := preload("res://scripts/ui/theme/hud_style.gd")
const ROW_H := 22.0

@export var max_rows: int = 4
@export var width: float = 420.0
## Seconds a finished project stays on the list, flashing.
@export var flash_time: float = 3.0

var hud: HUD
var is_open := true

var _title: Label
var _staff: Label
var _toggle: Button
var _rows_box: VBoxContainer
var _queued: Button
var _lines: Array[ResearchLine] = []
## Tech id -> msec it was finished (rows that flash).
var _finished: Dictionary = {}
var _dirty := true
var _refresh_left := 0.0
## A Science Lab stood at the last rebuild (built or lost without a Research signal).
var _had_lab := false


## One project row (drawn).
class ResearchLine:
	extends Control

	var tech: TechDef
	var list: ResearchList
	var hover := false
	## Finished: flashes until it is dropped.
	var done := false
	var _d: Dictionary = {}

	func _init(t: TechDef, owner: ResearchList) -> void:
		tech = t
		list = owner
		custom_minimum_size = Vector2(0, ROW_H)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		# A stable key: the live content is the custom tooltip's job (a
		# changed tooltip_text makes Godot close the tooltip on a mouse move).
		tooltip_text = t.display_name

	func _make_custom_tooltip(_for_text: String) -> Object:
		return ResearchTip.make(tech, "Click: open it at the Science Lab")

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			list.open(tech)
			accept_event()

	func refresh() -> void:
		var t := tech
		var d := {"hover": hover, "done": done}
		if done:
			d["progress"] = 1.0
			d["pct"] = "100%"
			d["eta"] = ""
			d["res"] = ""
			d["reason"] = "done"
		else:
			var r := Research.researcher_on(t.id)
			var p := Research.progress_of(t)
			d["progress"] = p
			d["pct"] = "%d%%" % floori(p * 100.0)
			d["eta"] = UIUtil.clock(Research.eta_of(t)) if r and not r.unpaid else ""
			d["res"] = "1 res" if r else ""
			d["reason"] = ResearchList.pause_reason(t)
		if d != _d:
			_d = d
			queue_redraw()

	func _draw() -> void:
		if _d.is_empty():
			return
		var w := size.x
		var mid := size.y * 0.5
		var base := mid + 4.5
		var why := String(_d["reason"])
		var paused := not done and not why.is_empty()
		var a := 1.0
		if done:
			# Flash: a soft green pulse.
			a = 0.55 + 0.45 * absf(sin(float(Time.get_ticks_msec()) / 1000.0 * TAU * 1.5))
			draw_rect(Rect2(0, 0, w, size.y), Color(H.GOOD, 0.14 * a))
		elif hover:
			draw_rect(Rect2(0, 0, w, size.y), Color(H.HOLO, 0.08))
		var field_col: Color = ScienceLabPanel.FIELD_COLORS[tech.field]
		var col := H.GOOD if done else (field_col.lerp(H.TEXT_FAINT, 0.55) if paused else field_col)
		draw_rect(Rect2(0, 3, 2, size.y - 6), Color(H.WARN if paused else col, 0.9 * a))
		var ic := H.icon(&"research")
		if ic:
			draw_texture_rect(ic, Rect2(7, mid - 6, 12, 12), false, Color(col, a))
		var x := 25.0
		var right := w - 4.0
		var f_name := H.font("SemiBold")
		var f_num := H.mono("Medium")
		var f_dim := H.font("Medium")
		var text_col := H.TEXT_BRIGHT if not paused else H.TEXT_DIM
		# Right to left: researchers or the reason, time left, %, bar.
		var tail := why if paused or done else String(_d["res"])
		var tail_font := f_dim if paused or done else f_num
		var tail_col := H.GOOD if done else (H.WARN if paused else H.TEXT_DIM)
		var tw := minf(tail_font.get_string_size(tail, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, 170.0)
		var tail_fit := PilotCard._fit(tail_font, tail, 12, tw + 1.0)
		tw = tail_font.get_string_size(tail_fit, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		_text(tail_font, Vector2(right - tw, base - 0.5), tail_fit, 12, Color(tail_col, a))
		right -= (tw + 10.0) if tw > 0.0 else 0.0
		var eta := String(_d["eta"])
		if not eta.is_empty():
			var ew := f_num.get_string_size(eta, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			_text(f_num, Vector2(right - ew, base - 0.5), eta, 12, H.TEXT)
			right -= ew + 8.0
		var pct := String(_d["pct"])
		var pw := f_num.get_string_size("100%", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var pcw := f_num.get_string_size(pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		_text(f_num, Vector2(right - pcw, base - 0.5), pct, 12, Color(text_col, a))
		right -= pw + 6.0
		var bar_w := 56.0
		var bar := Rect2(right - bar_w, mid - 1.5, bar_w, 3.0)
		draw_rect(bar, Color(H.HAIRLINE_STRONG, 0.7))
		var fill := bar
		fill.size.x = bar_w * clampf(float(_d["progress"]), 0.0, 1.0)
		draw_rect(fill, Color(col, a))
		right -= bar_w + 10.0
		var nm := PilotCard._fit(f_name, tech.display_name, 13, right - x)
		_text(f_name, Vector2(x, base), nm, 13, Color(text_col, a))

	func _text(f: Font, at: Vector2, text: String, fsize: int, color: Color) -> void:
		draw_string_outline(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 3, Color(0, 0, 0, 0.75 * color.a))
		draw_string(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)


func _ready() -> void:
	custom_minimum_size.x = width
	add_theme_constant_override("separation", 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	top.add_child(H.icon_rect(&"research", 13.0, H.HOLO))
	_title = UIUtil.label("RESEARCH", &"HeaderLabel")
	_title.add_theme_font_size_override("font_size", 13)
	top.add_child(_title)
	top.add_child(UIUtil.spacer())
	_staff = UIUtil.label("", &"SmallLabel")
	_staff.add_theme_font_size_override("font_size", 11)
	_staff.mouse_filter = Control.MOUSE_FILTER_PASS
	top.add_child(_staff)
	_toggle = UIUtil.button("", &"IconButton")
	_toggle.icon = H.icon(&"collapse")
	_toggle.custom_minimum_size = Vector2(20.0, 16.0)
	_toggle.tooltip_text = "Collapse the research list"
	_toggle.pressed.connect(func() -> void:
		is_open = not is_open
		_toggle.icon = H.icon(&"collapse" if is_open else &"expand")
		_toggle.tooltip_text = ("Collapse" if is_open else "Expand") + " the research list"
		_rows_box.visible = is_open
		_queued.visible = is_open and not _queued.text.is_empty())
	top.add_child(_toggle)
	var rule := ColorRect.new()
	rule.color = H.HAIRLINE_STRONG
	rule.custom_minimum_size.y = 1.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rule)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 0)
	add_child(_rows_box)
	_queued = UIUtil.button("", &"RowButton")
	_queued.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_queued.add_theme_font_size_override("font_size", 12)
	_queued.add_theme_color_override("font_color", H.TEXT_DIM)
	_queued.custom_minimum_size.y = 18.0
	_queued.pressed.connect(func() -> void: open(null))
	add_child(_queued)
	H.outline_labels(self)


func setup(owner_hud: HUD) -> void:
	hud = owner_hud
	Research.changed.connect(func() -> void: _dirty = true)
	Research.tech_completed.connect(_on_completed)
	_rebuild()


## Why [param t] (funded) makes no progress now, or "".
static func pause_reason(t: TechDef) -> String:
	var r := Research.researcher_on(t.id)
	if r:
		return "Out of credits for wages" if r.unpaid else ""
	return "No researchers" if Research.researchers.is_empty() else "Waiting for a researcher"


## The home system's Science Lab, from any view (research is global).
func _lab() -> ScienceLab:
	var home := SystemWorld.home(get_tree()) if is_inside_tree() else null
	return ScienceLab.find(home) if home else null


## Selects the Science Lab (switching the view home first) and shows
## [param t] in its Projects tab (null: just the lab).
func open(t: TechDef) -> void:
	if hud == null:
		return
	hud.select_lab()
	var panel := hud.building_panel.lab_panel if hud.building_panel else null
	if t and is_instance_valid(panel) and panel.visible:
		panel.show_tech(t)


func _on_completed(t: TechDef) -> void:
	_finished[t.id] = Time.get_ticks_msec()
	_dirty = true
	var pm := get_tree().root.get_node_or_null(^"PauseMenu") if is_inside_tree() else null
	if pm and pm.has_method(&"toast"):
		pm.call(&"toast", "Research done: %s" % t.display_name)


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	for id: StringName in _finished.keys():
		if float(now - int(_finished[id])) / 1000.0 > flash_time:
			_finished.erase(id)
			_dirty = true
	if _dirty:
		_dirty = false
		_rebuild()
	var mp := get_global_mouse_position()
	for l in _lines:
		var on := l.get_global_rect().has_point(mp) and is_visible_in_tree()
		if on != l.hover:
			l.hover = on
			l.refresh()
		if l.done:
			l.queue_redraw()
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = 0.25
		_refresh()


## Rows: projects in work or started (and the lead one while nobody is
## hired), then the finished ones still flashing; the rest is "+N queued".
## Rows are kept across rebuilds (only added, dropped or moved), so a row
## under the mouse keeps its tooltip open.
func _rebuild() -> void:
	var active := Research.active_projects()
	var shown: Array[TechDef] = []
	var queued := 0
	for a in active:
		var t := a["tech"] as TechDef
		var started := a["researcher"] != null or float(a["progress"]) > 0.0
		if (started or shown.is_empty()) and shown.size() < max_rows:
			shown.append(t)
		else:
			queued += 1
	var cat := Research.catalog()
	var flashing: Array[TechDef] = []
	for id: StringName in _finished:
		var ft := cat.find(id)
		if ft:
			flashing.append(ft)
	_had_lab = _lab() != null
	visible = _had_lab and (not active.is_empty() or not flashing.is_empty())
	_title.text = "RESEARCH %d" % active.size()
	var old := {}
	for l in _lines:
		old[l.tech.id] = l
	_lines.clear()
	for t in flashing + shown:
		var l := old.get(t.id) as ResearchLine
		old.erase(t.id)
		if l == null:
			l = ResearchLine.new(t, self)
			_rows_box.add_child(l)
		l.done = _finished.has(t.id)
		_rows_box.move_child(l, _lines.size())
		_lines.append(l)
	for id: StringName in old:
		(old[id] as ResearchLine).queue_free()
	_queued.text = ("+%d queued" % queued) if queued > 0 else ""
	_queued.tooltip_text = "Funded, not started: a researcher picks one up when free. Click: open the Science Lab"
	_queued.visible = is_open and queued > 0
	_rows_box.visible = is_open
	_refresh()


func _refresh() -> void:
	if (_lab() != null) != _had_lab:
		_dirty = true
	for l in _lines:
		l.refresh()
	var n := Research.researchers.size()
	_staff.text = "%d RES  %s CR/MIN" % [n, UIUtil.amount(ceili(Research.wages_per_min()))] if n > 0 else "NO RESEARCHERS"
	_staff.add_theme_color_override("font_color", H.WARN if n == 0 or Research.any_unpaid() else H.TEXT_DIM)
	_staff.tooltip_text = "%d of %d researchers hired, wages %s cr per minute%s" % [n, Research.MAX_RESEARCHERS,
			UIUtil.amount(ceili(Research.wages_per_min())), ". Some are unpaid: research is paused until credits come in" if Research.any_unpaid() else ""]


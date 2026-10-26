class_name ScienceLabPanel
extends PanelContainer
## Bottom-right panel for the selected Science Lab (BuildingPanel makes it
## and hands lab selections over). Two tabs:
## - Projects: every listed tech grouped by field (Engineering, Weapons,
##   Planetary) with its state (locked by a prerequisite, available, funded
##   and waiting for a researcher, in progress with who and how far, done),
##   cost and time, and a Fund or Cancel button (the cancel tooltip says what
##   comes back). Hover a project: what it unlocks with the module numbers.
## - Staff: hired researchers (field, skill, personality, project and
##   progress, why they picked it, Let go), the applicants you can hire, and
##   the lab log (choices with their reasons, completions).

const FIELD_COLORS: Array[Color] = [Color(0.55, 0.8, 1.0), Color(1.0, 0.56, 0.42), Color(0.6, 0.95, 0.62)]
const STATE_COLORS := {
	"done": HudStyle.GOOD, "in_progress": HudStyle.SHIELD, "funded": HudStyle.WARN,
	"available": HudStyle.TEXT, "locked": HudStyle.TEXT_FAINT,
}
const STATE_NAMES := {
	"done": "done", "in_progress": "in progress", "funded": "funded, waiting", "available": "available", "locked": "locked",
}
const PERSONALITY_COLORS: Array[Color] = [Color(1.0, 0.7, 0.35), Color(0.5, 0.8, 1.0), Color(0.6, 0.95, 0.62), Color(0.78, 0.78, 0.86)]
const MAX_LOG := 6

@export var panel_width: float = 430.0

var hud: HUD
var building: Building
var lab: ScienceLab

var _title: Label
var _status: Label
var _reserved: Label
var _projects: VBoxContainer
var _staff: VBoxContainer
var _tab_buttons: Array[Button] = []
## 0 = Projects, 1 = Staff.
var _tab: int = 0
## Rows updated live: {tech, bar, sub}.
var _live: Array[Dictionary] = []
## Researcher rows updated live: {researcher, sub}.
var _live_staff: Array[Dictionary] = []
var _applicant_header: Label
var _tick := 0.0
var _dirty := false


func _ready() -> void:
	custom_minimum_size.x = panel_width
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	top.add_child(UIUtil.label("STRUCTURE", &"HeaderLabel"))
	top.add_child(UIUtil.spacer(6.0))
	var tabs := ButtonGroup.new()
	for i in 2:
		var tb := UIUtil.button("Projects" if i == 0 else "Staff", &"IconButton")
		tb.toggle_mode = true
		tb.button_group = tabs
		tb.button_pressed = i == 0
		tb.custom_minimum_size = Vector2(84.0, 22.0)
		tb.tooltip_text = "Fund research projects by field" if i == 0 else "Hire researchers, see what they work on and why"
		tb.pressed.connect(set_tab.bind(i))
		top.add_child(tb)
		_tab_buttons.append(tb)
	top.add_child(UIUtil.spacer())
	var close := UIUtil.button("x", &"IconButton")
	close.custom_minimum_size = Vector2(26.0, 22.0)
	close.tooltip_text = "Deselect (Esc)"
	close.pressed.connect(func() -> void:
		if hud and hud.selection:
			hud.selection.deselect())
	top.add_child(close)
	_title = UIUtil.label("Science Lab", &"TitleLabel")
	v.add_child(_title)
	_status = UIUtil.label("", &"ValueLabel")
	v.add_child(_status)
	_reserved = UIUtil.label("", &"DimLabel")
	_reserved.mouse_filter = Control.MOUSE_FILTER_PASS
	_reserved.tooltip_text = "Funding a project reserves its credits at once (the ore is spent). Cancel: all of it back while nobody has worked on it, half once started."
	v.add_child(_reserved)
	_projects = VBoxContainer.new()
	_projects.add_theme_constant_override("separation", 3)
	v.add_child(_projects)
	_staff = VBoxContainer.new()
	_staff.add_theme_constant_override("separation", 3)
	_staff.visible = false
	v.add_child(_staff)


func setup(owner_hud: HUD) -> void:
	hud = owner_hud
	if hud.selection:
		hud.selection.selection_changed.connect(func(t: Node3D) -> void: show_building(t as Building))
	Research.changed.connect(func() -> void: _dirty = true)
	Economy.changed.connect(func(_c: int, _m: int) -> void: _dirty = true)


func show_building(b: Building) -> void:
	var l := b.get_service() as ScienceLab if b else null
	building = b if l else null
	lab = l
	visible = l != null
	if l == null:
		return
	_title.text = b.display_name
	_rebuild()


## 0 = Projects, 1 = Staff.
func set_tab(index: int) -> void:
	_tab = index
	_tab_buttons[index].set_pressed_no_signal(true)
	_tab_buttons[1 - index].set_pressed_no_signal(false)
	_rebuild()


func get_tab() -> int:
	return _tab


func _process(delta: float) -> void:
	if not visible or lab == null or not is_instance_valid(lab):
		return
	_tick -= delta
	if _dirty:
		_dirty = false
		_rebuild()
	elif _tick <= 0.0:
		_tick = 0.25
		_refresh_live()


func _rebuild() -> void:
	if lab == null or not is_instance_valid(lab):
		return
	_projects.visible = _tab == 0
	_staff.visible = _tab == 1
	_status.text = lab.status_text()
	_status.add_theme_color_override("font_color", PipMeter.GOOD if building.is_active() else Color(1.0, 0.75, 0.45))
	var held := Research.escrow_total()
	_reserved.text = "Reserved for research: %s cr" % UIUtil.amount(held) if held > 0 else "Nothing reserved for research"
	if _tab == 0:
		_rebuild_projects()
	else:
		_rebuild_staff()
	_refresh_live()


func _clear(box: Container) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


# --- Projects -----------------------------------------------------------------------

func _rebuild_projects() -> void:
	_clear(_projects)
	_live.clear()
	var cat := Research.catalog()
	for field in TechDef.FIELD_NAMES.size():
		var techs := cat.of_field(field)
		if techs.is_empty():
			continue
		_projects.add_child(HSeparator.new())
		var head := HBoxContainer.new()
		head.mouse_filter = Control.MOUSE_FILTER_PASS
		_projects.add_child(head)
		var hl := UIUtil.label(TechDef.FIELD_NAMES[field].to_upper(), &"HeaderLabel")
		hl.add_theme_color_override("font_color", FIELD_COLORS[field])
		head.add_child(hl)
		head.add_child(UIUtil.spacer())
		var n_done := 0
		var done_names: PackedStringArray = []
		for t in techs:
			if Research.is_done(t.id):
				n_done += 1
				done_names.append(t.display_name)
		var staff := 0
		for r in Research.researchers:
			if r.field == field:
				staff += 1
		head.add_child(UIUtil.label("%d of %d done, %d researcher%s" % [n_done, techs.size(), staff, "" if staff == 1 else "s"], &"DimLabel"))
		head.tooltip_text = "%s researchers work at full speed on %s projects, at %d%% on the others." % [TechDef.FIELD_NAMES[field], TechDef.FIELD_NAMES[field], roundi(Researcher.OFF_FIELD_SPEED * 100.0)]
		for t in techs:
			if not Research.is_done(t.id):
				_add_tech_row(t)
		if not done_names.is_empty():
			var dl := UIUtil.label("Done: " + ", ".join(done_names), &"DimLabel")
			dl.add_theme_color_override("font_color", HudStyle.GOOD.lerp(HudStyle.TEXT_DIM, 0.4))
			dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			dl.custom_minimum_size.x = panel_width - 24.0
			_projects.add_child(dl)


func _add_tech_row(t: TechDef) -> void:
	var state := Research.state_of(t)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.tooltip_text = tech_tip(t)
	_projects.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(row)
	var tier := UIUtil.label(["", "I", "II", "III"][t.tier], &"DimLabel")
	tier.custom_minimum_size.x = 22.0
	tier.add_theme_color_override("font_color", CaptainPanel.TIER_COLORS[t.tier])
	row.add_child(tier)
	var name_l := UIUtil.label(t.display_name, &"ValueLabel")
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if state == "locked":
		name_l.add_theme_color_override("font_color", HudStyle.TEXT_DIM)
	row.add_child(name_l)
	var st := UIUtil.label(STATE_NAMES[state], &"DimLabel")
	st.add_theme_color_override("font_color", STATE_COLORS[state])
	row.add_child(st)
	var btn: Button
	if state == "funded" or state == "in_progress":
		btn = UIUtil.button("Cancel", &"IconButton")
		btn.tooltip_text = Research.cancel_text(t)
		btn.pressed.connect(func() -> void: Research.cancel(t))
	else:
		btn = UIUtil.button("Fund", &"AccentButton")
		var why := Research.fund_problem(t)
		btn.disabled = not why.is_empty()
		btn.tooltip_text = why if not why.is_empty() else "Fund it: %s reserved now. A researcher picks it up when free." % t.cost_text()
		btn.pressed.connect(func() -> void: Research.fund(t))
	btn.custom_minimum_size = Vector2(64.0, 22.0)
	row.add_child(btn)
	var sub := UIUtil.label("", &"DimLabel")
	sub.clip_text = true
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub.custom_minimum_size.x = panel_width - 24.0
	box.add_child(sub)
	var bar: ProgressBar = null
	if state == "funded" or state == "in_progress":
		bar = ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.custom_minimum_size = Vector2(panel_width - 24.0, 4.0)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(bar)
	_live.append({"tech": t, "bar": bar, "sub": sub})


## Sub line of a project row: cost and time, or who works on it and how far.
static func tech_line(t: TechDef) -> String:
	var state := Research.state_of(t)
	match state:
		"locked":
			var miss: PackedStringArray = []
			for m in Research.missing_prereqs(t):
				miss.append(m.display_name)
			return "Needs research: %s.  %s, %s" % [", ".join(miss), t.cost_text(), UIUtil.clock(t.research_time)]
		"funded":
			return "Waiting for a researcher, %d%% done. Reserved %s cr" % [roundi(Research.progress_of(t) * 100.0), UIUtil.amount(int(Research.projects[t.id]["credits"]))]
		"in_progress":
			var r := Research.researcher_on(t.id)
			return "%s, %d%%, %s left" % [r.researcher_name, roundi(Research.progress_of(t) * 100.0), UIUtil.clock(Research.eta_of(t))]
	return "%s, %s at skill 5 in the field" % [t.cost_text(), UIUtil.clock(t.research_time)]


## Description, unlocks with their numbers, prerequisites, cost and time.
static func tech_tip(t: TechDef) -> String:
	var lines: PackedStringArray = ["%s (%s, %s)" % [t.display_name, t.field_name(), TechDef.TIER_NAMES[t.tier]], t.description, ""]
	for id in t.unlock_modules:
		var m := ModuleCatalog.shared().find(id)
		if m:
			lines.append("%s: %s" % [m.display_name, m.effect_text()])
	var mgr := BuildingManager.of(SystemWorld.home(Engine.get_main_loop() as SceneTree))
	for id in t.unlock_buildings:
		var def := mgr.def_by_id(id) if mgr else null
		lines.append("Unlocks the %s%s" % [def.display_name if def else String(id).capitalize(), " (in service in a later update)" if def and not def.in_service else ""])
	if not t.prerequisites.is_empty():
		var pre: PackedStringArray = []
		for p in t.prerequisites:
			var pt := Research.catalog().find(p)
			if pt:
				pre.append(pt.display_name + (" (done)" if Research.is_done(p) else ""))
		lines.append("Needs: " + ", ".join(pre))
	lines.append("Cost %s. Time %s for a skill 5 researcher in the field, %s outside it." % [t.cost_text(), UIUtil.clock(t.research_time),
			UIUtil.clock(t.research_time / Researcher.OFF_FIELD_SPEED)])
	return "\n".join(lines)


# --- Staff ------------------------------------------------------------------------

func _rebuild_staff() -> void:
	_clear(_staff)
	_live_staff.clear()
	_staff.add_child(HSeparator.new())
	var rh := UIUtil.label("RESEARCHERS  %d / %d" % [Research.researchers.size(), Research.MAX_RESEARCHERS], &"HeaderLabel")
	rh.tooltip_text = "Each researcher draws a wage from your credits: %s cr per minute for skill 1, %s for skill 10. When the station cannot pay, they stop working (Unpaid)." % [
			String.num(Researcher.WAGE_BASE + Researcher.WAGE_PER_SKILL, 1), String.num(Researcher.WAGE_BASE + Researcher.WAGE_PER_SKILL * 10.0, 1)]
	rh.mouse_filter = Control.MOUSE_FILTER_PASS
	_staff.add_child(rh)
	if not Research.researchers.is_empty():
		_staff.add_child(UIUtil.label("Wages %s cr per minute, paid from your credits" % String.num(Research.wages_per_min(), 1).trim_suffix(".0"), &"DimLabel"))
	if Research.researchers.is_empty():
		var e := UIUtil.label("Nobody hired yet. Hire a researcher below; they pick funded projects on their own.", &"DimLabel")
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		e.custom_minimum_size.x = panel_width - 24.0
		_staff.add_child(e)
	for r in Research.researchers:
		var box := _person_row(r, false)
		var sub := UIUtil.label("", &"DimLabel")
		sub.clip_text = true
		sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		sub.custom_minimum_size.x = panel_width - 24.0
		box.add_child(sub)
		_live_staff.append({"researcher": r, "sub": sub})

	_staff.add_child(HSeparator.new())
	_applicant_header = UIUtil.label("", &"HeaderLabel")
	_staff.add_child(_applicant_header)
	for a in Research.applicants:
		_person_row(a, true)

	_staff.add_child(HSeparator.new())
	_staff.add_child(UIUtil.label("LAB LOG", &"HeaderLabel"))
	if Research.log_lines.is_empty():
		_staff.add_child(UIUtil.label("Nothing yet.", &"DimLabel"))
	var n := 0
	for i in range(Research.log_lines.size() - 1, -1, -1):
		var e: Dictionary = Research.log_lines[i]
		var l := UIUtil.label("%s  %s" % [UIUtil.clock(float(e["time"])), e["text"]], &"DimLabel")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = panel_width - 24.0
		_staff.add_child(l)
		n += 1
		if n >= MAX_LOG:
			break


## Name, field, skill, personality and the hire or let go button.
func _person_row(r: Researcher, applicant: bool) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -2)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.tooltip_text = "%s, %s researcher, skill %d (works at %d%% speed in the field, %d%% outside it).\nWage %s cr per minute, paid from your credits; unpaid researchers stop working.\n%s: %s%s" % [
			r.researcher_name, r.field_name(), r.skill, roundi(r.skill_speed() * 100.0), roundi(r.skill_speed() * Researcher.OFF_FIELD_SPEED * 100.0),
			wage_text(r), r.personality_name(), Researcher.PERSONALITY_HINTS[r.personality],
			"\nLast choice: " + r.reason if not r.reason.is_empty() else ""]
	_staff.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(row)
	var name_l := UIUtil.label(r.researcher_name, &"ValueLabel")
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name_l)
	var fl := UIUtil.label(r.field_name(), &"DimLabel")
	fl.add_theme_color_override("font_color", FIELD_COLORS[r.field])
	row.add_child(fl)
	var pips := PipMeter.new()
	pips.style = PipMeter.Style.PIPS
	pips.max_value = 10.0
	pips.value = float(r.skill)
	pips.pip_size = 4.0
	pips.pip_gap = 1.0
	pips.color = HudStyle.ACCENT
	pips.custom_minimum_size = Vector2(50.0, 8.0)
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pips)
	var wl := UIUtil.label("%s cr/min" % wage_text(r), &"DimLabel")
	wl.add_theme_color_override("font_color", HudStyle.CREDITS)
	row.add_child(wl)
	var pl := UIUtil.label(r.personality_name(), &"DimLabel")
	pl.add_theme_color_override("font_color", PERSONALITY_COLORS[r.personality])
	pl.custom_minimum_size.x = 76.0
	row.add_child(pl)
	var btn: Button
	if applicant:
		btn = UIUtil.button("Hire %s cr" % UIUtil.amount(r.hire_cost), &"AccentButton")
		var why := Research.hire_problem(r)
		btn.disabled = not why.is_empty()
		btn.tooltip_text = why if not why.is_empty() else "Hire %s for %s cr, then a wage of %s cr per minute from your credits." % [r.researcher_name, UIUtil.amount(r.hire_cost), wage_text(r)]
		btn.pressed.connect(func() -> void: Research.hire(r))
	else:
		btn = UIUtil.button("Let go", &"IconButton")
		btn.tooltip_text = "Let %s go (no refund). Their project stays funded with its progress." % r.researcher_name
		btn.pressed.connect(func() -> void: Research.fire(r))
	btn.custom_minimum_size = Vector2(76.0, 22.0)
	row.add_child(btn)
	return box


## "3.5", "4".
static func wage_text(r: Researcher) -> String:
	return String.num(r.wage_per_min(), 1).trim_suffix(".0")


static func researcher_line(r: Researcher) -> String:
	if r.unpaid:
		return "Unpaid: the station cannot pay %s cr/min, research paused" % wage_text(r)
	if r.is_idle():
		return "Idle: fund a project to start" if Research.projects.is_empty() else "Idle: every funded project is taken"
	var t := Research.catalog().find(r.project)
	if t == null:
		return "Idle"
	return "On %s, %d%%, %s left%s" % [t.display_name, roundi(Research.progress_of(t) * 100.0), UIUtil.clock(Research.eta_of(t)),
			"" if t.field == r.field else " (outside their field)"]


func _refresh_live() -> void:
	_status.text = lab.status_text() if lab else ""
	for e in _live:
		var t := e["tech"] as TechDef
		(e["sub"] as Label).text = tech_line(t)
		var bar := e["bar"] as ProgressBar
		if bar:
			bar.value = Research.progress_of(t)
	for e in _live_staff:
		(e["sub"] as Label).text = researcher_line(e["researcher"] as Researcher)
	if is_instance_valid(_applicant_header) and _tab == 1:
		_applicant_header.text = "APPLICANTS  (new ones in %s)" % UIUtil.clock(maxf(Research.applicants_at - SimClock.time, 0.0))

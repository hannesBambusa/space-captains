class_name SurfaceHud
extends Control
## The HUD of planet mode (planet outposts plan, [SurfaceMode]): a top bar
## (outpost, the goods at the pad and the shuttles, credits, sim time, UP),
## a build column (Harvester Bay, Garrison, Ground Turret, Shield Dome with
## their costs), the selection panel (a building: hull, crew and Hire; a
## deposit: loads left and its harvest contract, pay - / +, Post or Cancel;
## a nest: hull, agitation and a bounty; a vehicle: its crew member) and the
## last feed lines. Placing: pick a building, a ghost ring follows the mouse
## (green where it may stand), left click builds, right click cancels.

const THEME_PATH := "res://ui/theme.tres"
const H := preload("res://scripts/ui/theme/hud_style.gd")
const BOUNTY := 500
const PANEL_W := 360.0

var mode: SurfaceMode
## The building kind being placed, &"" when not placing.
var placing: StringName = &""
var _sel: Dictionary = {}
var _title: Label
var _offer: Button
var _stock: Label
var _credits: Label
var _time: Label
var _panel: PanelContainer
var _panel_box: VBoxContainer
var _feed: VBoxContainer
var _feed_panel: PanelContainer
var _build_buttons: Dictionary = {}
var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _refresh := 0.0
var _pay := 0


func setup(m: SurfaceMode) -> void:
	mode = m


func _ready() -> void:
	theme = load(THEME_PATH)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Top bar.
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 44.0
	add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	top.add_child(row)
	var up := UIUtil.button("UP", &"ChipButton")
	up.tooltip_text = "Back to orbit (Backspace)"
	up.custom_minimum_size = Vector2(64, 28)
	up.pressed.connect(func() -> void: mode.leave())
	row.add_child(up)
	_title = UIUtil.label("", &"HeaderLabel")
	row.add_child(_title)
	_offer = UIUtil.button("RIVAL OFFER WAITING: GO UP", &"ChipButton")
	_offer.tooltip_text = "A rival corp sent an offer. It waits while you are on the surface; answer it in orbit."
	_offer.visible = false
	_offer.pressed.connect(func() -> void: mode.leave())
	row.add_child(_offer)
	row.add_child(UIUtil.spacer())
	_stock = UIUtil.label("", &"ValueLabel")
	row.add_child(_stock)
	_credits = UIUtil.label("", &"BigValueLabel")
	row.add_child(_credits)
	_time = UIUtil.label("", &"NumberLabel")
	row.add_child(_time)
	# Build column.
	var build := PanelContainer.new()
	build.position = Vector2(12, 60)
	add_child(build)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 6)
	build.add_child(bv)
	bv.add_child(UIUtil.label("BUILD", &"SubHeaderLabel"))
	for kind in OutpostState.BUILD_ORDER:
		var d: Dictionary = OutpostState.BUILDINGS[kind]
		var b := UIUtil.button(String(d["name"]).to_upper(), &"ChipButton")
		b.custom_minimum_size = Vector2(190, 30)
		b.pressed.connect(func() -> void: _start_placing(kind))
		bv.add_child(b)
		_build_buttons[kind] = b
	bv.add_child(UIUtil.label("Right click: cancel", &"SmallLabel"))
	# Selection panel.
	_panel = PanelContainer.new()
	_panel.custom_minimum_size.x = PANEL_W
	_panel.visible = false
	add_child(_panel)
	_panel_box = VBoxContainer.new()
	_panel_box.add_theme_constant_override("separation", 6)
	_panel.add_child(_panel_box)
	# Feed.
	_feed_panel = PanelContainer.new()
	add_child(_feed_panel)
	_feed = VBoxContainer.new()
	_feed_panel.add_child(_feed)
	UIUtil.no_focus(self)
	_make_ghost()
	_refresh_all()


func _make_ghost() -> void:
	_ghost = MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 1.0
	c.bottom_radius = 1.0
	c.height = 4.0
	c.radial_segments = 32
	_ghost.mesh = c
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(0.3, 1.0, 0.5, 0.35)
	_ghost.material_override = _ghost_mat
	_ghost.visible = false
	mode.world.add_child(_ghost)


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = 0.25
	# A held button would lose its click if the panel were rebuilt under it.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	_refresh_all()


func _refresh_all() -> void:
	var o := mode.outpost
	var p := Sector.system_def(o.system_id)
	_title.text = "%s SURFACE  ·  %s%s" % [o.planet.to_upper(), p.system_name if p else "Solace", "  ·  upkeep owed %d cr" % o.upkeep_owed if o.upkeep_owed > 0 else ""]
	_stock.text = "%s at the pad: %d  ·  %d shuttle%s, %d in the air" % [o.good_name().capitalize(), o.stock[o.good], o.shuttles, "" if o.shuttles == 1 else "s", o.lifts.size()]
	var vm := ViewManager.of(get_tree())
	_offer.visible = vm != null and vm.rival != null and not vm.rival.first_offer().is_empty()
	_credits.text = "%s cr" % Fmt.amount(Economy.credits)
	_time.text = "%s  %s" % [Fmt.clock(SimClock.time), "PAUSED" if SimClock.paused else "%dx" % roundi(SimClock.speed)]
	var outs := Outposts.of(get_tree())
	for kind: StringName in _build_buttons:
		var b: Button = _build_buttons[kind]
		var d: Dictionary = OutpostState.BUILDINGS[kind]
		var why := outs.build_problem(o, kind) if outs else ""
		b.disabled = not why.is_empty()
		b.tooltip_text = "%s: %s cr%s%s, %d s\n%s" % [d["name"], Fmt.amount(int(d["credits"])), " + %d iron" % int(d["iron"]) if int(d["iron"]) > 0 else "",
				" + %d titanium" % int(d["ti"]) if int(d["ti"]) > 0 else "", roundi(float(d["time"])), why if not why.is_empty() else _build_hint(kind)]
	_layout()
	_fill_feed()
	_fill_panel()


func _build_hint(kind: StringName) -> String:
	match kind:
		OutpostState.BAY:
			return "Hires harvesters (%d cr). They harvest the deposits you post contracts on." % int(OutpostState.BUILDINGS[kind]["hire"])
		OutpostState.GARRISON:
			return "Hires soldiers in hover tanks (%d cr). They guard the base and clear nests with a bounty." % int(OutpostState.BUILDINGS[kind]["hire"])
		OutpostState.TURRET:
			return "Shoots critters and raiders within %d m." % roundi(SurfaceWorld.TURRET_RANGE)
		OutpostState.DOME:
			return "Takes the hits on every building within %d m while its shield holds." % roundi(SurfaceWorld.DOME_REACH)
	return ""


func _layout() -> void:
	var s := get_viewport_rect().size
	_panel.position = Vector2(s.x - PANEL_W - 12.0, 60.0)
	_feed_panel.position = Vector2(12.0, s.y - _feed_panel.size.y - 12.0)


func _fill_feed() -> void:
	for c in _feed.get_children():
		c.queue_free()
	var lines := EventLog.entries.slice(maxi(EventLog.entries.size() - 6, 0))
	for e: Dictionary in lines:
		var l := UIUtil.label("%s  %s" % [Fmt.clock(float(e["time"])), e["text"]], &"SmallLabel")
		_feed.add_child(l)


# --- Selection --------------------------------------------------------------------

func clicked(p: Vector3) -> void:
	if not placing.is_empty():
		var outs := Outposts.of(get_tree())
		if outs and outs.build(mode.outpost, placing, p.x, p.z):
			mode.world.add_building(mode.outpost.buildings.back())
			placing = &""
			_ghost.visible = false
		_refresh_all()
		return
	_sel = mode.world.pick(p)
	_pay = 0
	_refresh_all()


func has_selection() -> bool:
	return not _sel.is_empty()


func cancel() -> void:
	placing = &""
	_ghost.visible = false
	_sel = {}
	_refresh_all()


func hover(sp: Vector2) -> void:
	if placing.is_empty():
		return
	var p := mode.ground_under(sp)
	if p == Vector3.INF:
		_ghost.visible = false
		return
	var r := float(OutpostState.BUILDINGS[placing]["radius"])
	_ghost.visible = true
	_ghost.scale = Vector3(r, 1.0, r)
	_ghost.global_position = mode.world.deck_at(p.x, p.z) + Vector3.UP * 2.0
	var outs := Outposts.of(get_tree())
	var ok := outs != null and outs.spot_problem(mode.outpost, placing, p.x, p.z).is_empty()
	_ghost_mat.albedo_color = Color(0.3, 1.0, 0.5, 0.35) if ok else Color(1.0, 0.3, 0.25, 0.35)


func _start_placing(kind: StringName) -> void:
	placing = kind
	_sel = {}
	_refresh_all()


func _fill_panel() -> void:
	for c in _panel_box.get_children():
		c.queue_free()
	_panel.visible = not _sel.is_empty() or not placing.is_empty()
	if not placing.is_empty():
		_panel_box.add_child(UIUtil.label("PLACING %s" % String(OutpostState.BUILDINGS[placing]["name"]).to_upper(), &"HeaderLabel"))
		_panel_box.add_child(_wrap("Click within %d m of the landing pad, clear of the other buildings and the deposits. Right click cancels." % roundi(OutpostState.BASE_RADIUS)))
		return
	if _sel.is_empty():
		return
	var o := mode.outpost
	var outs := Outposts.of(get_tree())
	match String(_sel["kind"]):
		"building":
			var b: Dictionary = _sel["ref"]
			var d: Dictionary = OutpostState.BUILDINGS[StringName(b["kind"])]
			_panel_box.add_child(UIUtil.label(String(d["name"]).to_upper(), &"HeaderLabel"))
			var status := "Building %d%%" % roundi(float(b.get("built", 1.0)) * 100.0) if float(b.get("built", 1.0)) < 1.0 else "Disabled: repairing" if bool(b.get("disabled", false)) else "Active"
			_panel_box.add_child(UIUtil.label("%s  ·  hull %d / %d" % [status, roundi(float(b["hull"])), roundi(float(d["hull"]))], &"ValueLabel"))
			if StringName(b["kind"]) == OutpostState.DOME:
				_panel_box.add_child(UIUtil.label("Shield %d / %d" % [roundi(float(b.get("shield", SurfaceWorld.DOME_SHIELD))), roundi(SurfaceWorld.DOME_SHIELD)], &"ValueLabel"))
			if StringName(b["kind"]) == OutpostState.PAD:
				_panel_box.add_child(_wrap("%s at the pad, %d delivered so far, %d loads harvested. A shuttle lifts %d units to the station (%d s)." % [o.good_name().capitalize(),
						o.stock[o.good], o.delivered[o.good], o.loads_total, OutpostState.shuttle_load(), roundi(o.lift_seconds)]))
				_panel_box.add_child(_wrap("Losing the landing pad loses the outpost."))
			if d.has("role"):
				var role := String(d["role"])
				var crew := o.crew_of(role)
				_panel_box.add_child(UIUtil.label("%sS  %d / %d" % [role.to_upper(), crew.size(), o.berths(role)], &"SubHeaderLabel"))
				for c in crew:
					_panel_box.add_child(UIUtil.label("%s (%s)  hull %d%%  loads %d  kills %d  %d cr" % [c["name"], Captain.PERSONALITY_NAMES[int(c["personality"])],
							roundi(float(c["hull"]) / OutpostState.max_hull(role) * 100.0),
							int(c.get("loads", 0)), int(c.get("kills", 0)), int(c.get("wallet", 0))], &"SmallLabel"))
				var hire := UIUtil.button("Hire a %s (%d cr)" % [role.to_lower(), int(d["hire"])], &"ChipButton")
				var why := outs.hire_problem(o, role)
				hire.disabled = not why.is_empty()
				hire.tooltip_text = why
				hire.pressed.connect(func() -> void:
					var c := outs.hire(o, role)
					if not c.is_empty():
						mode.world.add_crew(c)
					_refresh_all())
				_panel_box.add_child(hire)
				if not why.is_empty():
					# Shown, not only a tooltip: the panel is rebuilt 4 times a second.
					_panel_box.add_child(_wrap(why + "."))
		"deposit":
			var i: int = _sel["ref"]
			var dp: Dictionary = o.deposits[i]
			_panel_box.add_child(UIUtil.label(String(dp["name"]).to_upper(), &"HeaderLabel"))
			_panel_box.add_child(UIUtil.label("%d of %d loads left  ·  %d %s a load  ·  %.1f km from the pad" % [int(dp["loads"]), int(dp["total"]), o.load_units(), o.good_name(),
					Vector2(float(dp["x"]), float(dp["z"])).length() / 1000.0], &"ValueLabel"))
			var have := int(o.contracts.get(i, 0))
			if _pay <= 0:
				_pay = have if have > 0 else o.fair_pay()
			_panel_box.add_child(UIUtil.label("HARVEST CONTRACT", &"SubHeaderLabel"))
			var pr := HBoxContainer.new()
			var minus := UIUtil.button("-", &"ChipButton")
			minus.pressed.connect(func() -> void:
				_pay = maxi(_pay - 10, 10)
				_refresh_all())
			pr.add_child(minus)
			pr.add_child(UIUtil.label("%d cr per load" % _pay, &"BigValueLabel"))
			var plus := UIUtil.button("+", &"ChipButton")
			plus.pressed.connect(func() -> void:
				_pay += 10
				_refresh_all())
			pr.add_child(plus)
			_panel_box.add_child(pr)
			_panel_box.add_child(_wrap("Fair pay here is about %d cr (danger %d). Harvesters take the best paid work; cautious ones stay away from agitated nests." % [o.fair_pay(), o.danger]))
			var post := UIUtil.button("Update contract" if have > 0 else "Post contract", &"ChipButton")
			post.pressed.connect(func() -> void:
				outs.set_contract(o, i, _pay)
				_refresh_all())
			_panel_box.add_child(post)
			if have > 0:
				var cancel_b := UIUtil.button("Cancel contract", &"ChipButton")
				cancel_b.pressed.connect(func() -> void:
					outs.set_contract(o, i, 0)
					_refresh_all())
				_panel_box.add_child(cancel_b)
		"nest":
			var i: int = _sel["ref"]
			var n: Dictionary = o.nests[i]
			_panel_box.add_child(UIUtil.label("CRITTER NEST", &"HeaderLabel"))
			_panel_box.add_child(UIUtil.label("Hull %d / %d  ·  agitation %d (a swarm at %d)" % [roundi(float(n["hull"])), roundi(OutpostState.NEST_HULL), roundi(float(n["agitation"])),
					roundi(OutpostState.AGITATION_ATTACK)], &"ValueLabel"))
			_panel_box.add_child(_wrap("Harvesting within %.1f km agitates it. Soldiers clear it once a bounty is posted and two of them stand; it comes back after %d min." % [
					OutpostState.AGITATION_REACH / 1000.0, roundi(OutpostState.NEST_RESPAWN / 60.0)]))
			if o.bounties.has(i):
				_panel_box.add_child(UIUtil.label("Bounty posted: %d cr" % int(o.bounties[i]), &"ValueLabel"))
			else:
				var bb := UIUtil.button("Post a %d cr bounty" % BOUNTY, &"ChipButton")
				bb.disabled = Economy.credits < BOUNTY
				bb.pressed.connect(func() -> void:
					outs.post_bounty(o, i, BOUNTY)
					_refresh_all())
				_panel_box.add_child(bb)
		"unit":
			var u: SurfaceWorld.Unit = _sel["ref"]
			if u.dead:
				_sel = {}
				return
			var nm := String(u.crew.get("name", u.kind.capitalize()))
			_panel_box.add_child(UIUtil.label(nm.to_upper(), &"HeaderLabel"))
			var who := u.kind.capitalize()
			if not u.crew.is_empty():
				who = "%s, %s" % [String(u.crew["role"]), Captain.PERSONALITY_NAMES[int(u.crew["personality"])]]
			_panel_box.add_child(UIUtil.label("%s  ·  hull %d / %d  ·  %s" % [who, roundi(u.hull), roundi(u.max_hull), u.state], &"ValueLabel"))


func _wrap(text: String) -> Label:
	var l := UIUtil.label(text, &"DimLabel")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = PANEL_W - 24.0
	return l

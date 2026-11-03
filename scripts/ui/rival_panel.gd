class_name RivalPanel
extends PanelContainer
## The rival corporations (rival corporation plan, R4 to R6 and M1): R or
## the top bar's RIVALS button opens it, R, Esc or the close button shuts
## it; nothing pauses. A tab per rival (its name, in its colour) picks the
## one shown; what it knows of the other rivals is in its facts. Before first contact it only says what is known: the
## rival exists, its home is not found. After contact: name, personality
## (once revealed), stance, relations, where its home is, its strength
## against yours, the diplomacy actions (propose a pact, demand tribute,
## offer peace, declare war; the board answers with its reason) and, at
## war, a war strike: your idle mercenaries are offered a war bonus to fly
## to its home and hit its station. Then the public intel lines, newest first.

const H := preload("res://scripts/ui/theme/hud_style.gd")
const WIDTH := 560.0
const TOP := 64.0
const REFRESH := 0.5
## War bonus per volunteer and most ships in one strike.
const STRIKE_BONUS := 150
const STRIKE_SHIPS := 6

var hud: HUD
## The rival shown.
var rid: StringName = &"rival_1"
var _tabs: HBoxContainer
var _tab_ids: Array[StringName] = []

var _title: Label
var _status: Label
var _facts: Label
var _reply: Label
var _intel: VBoxContainer
var _buttons: Dictionary = {}
var _strike: Button
var _poach: Button
var _timer := 0.0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.x = WIDTH
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	v.add_child(top)
	_title = UIUtil.label("RIVAL", &"HeaderLabel")
	_title.add_theme_font_size_override("font_size", 18)
	top.add_child(_title)
	top.add_child(UIUtil.spacer())
	top.add_child(UIUtil.label("R or Esc: close", &"SmallLabel"))
	var close := UIUtil.button("x", &"IconButton")
	close.custom_minimum_size = Vector2(26.0, 22.0)
	close.tooltip_text = "Close (R, Esc)"
	close.pressed.connect(close_panel)
	top.add_child(close)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 4)
	v.add_child(_tabs)
	_status = UIUtil.label("", &"BigValueLabel")
	v.add_child(_status)
	_facts = UIUtil.label("", &"")
	_facts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_facts)
	v.add_child(HSeparator.new())
	v.add_child(UIUtil.label("DIPLOMACY", &"SubHeaderLabel"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	for k: String in ["pact", "tribute", "peace", "war"]:
		var b := UIUtil.button({"pact": "Propose pact", "tribute": "Demand tribute", "peace": "Offer peace", "war": "Declare war"}[k], &"ChipButton")
		b.custom_minimum_size.y = 26.0
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(_propose.bind(k))
		row.add_child(b)
		_buttons[k] = b
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	v.add_child(row2)
	_strike = UIUtil.button("War strike (%d cr each)" % STRIKE_BONUS, &"ChipButton")
	_strike.custom_minimum_size.y = 26.0
	_strike.pressed.connect(_launch_strike)
	row2.add_child(_strike)
	_poach = UIUtil.button("Recruit a rival captain (400 cr)", &"ChipButton")
	_poach.custom_minimum_size.y = 26.0
	_poach.pressed.connect(_recruit)
	row2.add_child(_poach)
	_reply = UIUtil.label("", &"DimLabel")
	_reply.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_reply)
	v.add_child(HSeparator.new())
	v.add_child(UIUtil.label("INTEL", &"SubHeaderLabel"))
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size.y = 220.0
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	_intel = VBoxContainer.new()
	_intel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_intel)


func setup(owner_hud: HUD) -> void:
	hud = owner_hud


func toggle() -> void:
	if visible:
		close_panel()
	else:
		open_panel()


func open_panel() -> void:
	visible = true
	_place()
	_refresh()


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


func _place() -> void:
	var root := get_parent() as Control
	if root == null:
		return
	var vp := root.size
	position = Vector2(roundf((vp.x - WIDTH) * 0.5), TOP)
	size = Vector2(WIDTH, minf(vp.y - TOP - 120.0, 640.0))


## One chip per rival, rebuilt when the rivals change.
func _refresh_tabs() -> void:
	var ids := Corps.rival_ids()
	if ids == _tab_ids:
		for i in _tabs.get_child_count():
			(_tabs.get_child(i) as Button).set_pressed_no_signal(ids[i] == rid)
		return
	_tab_ids = ids
	for c in _tabs.get_children():
		c.queue_free()
	if not ids.has(rid) and not ids.is_empty():
		rid = ids[0]
	for id in ids:
		var r := Corps.rival(id)
		var b := UIUtil.button(r.display_name.to_upper(), &"ChipButton")
		b.toggle_mode = true
		b.button_pressed = id == rid
		b.custom_minimum_size.y = 24.0
		b.add_theme_color_override("font_color", r.color)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(func() -> void:
			rid = id
			_reply.text = ""
			_refresh())
		_tabs.add_child(b)
	_tabs.visible = ids.size() > 1


func _refresh() -> void:
	_refresh_tabs()
	var r := Corps.rival(rid)
	var m := r.mind if r else null
	if r == null or m == null:
		_title.text = "RIVAL"
		_status.text = "No rival in this game"
		_facts.text = "This game was started with the rival Off."
		for b: Button in _buttons.values():
			b.disabled = true
		_strike.disabled = true
		_poach.disabled = true
		return
	var t := m.tie(Corps.PLAYER)
	var war := Corps.corps_at_war(rid, Corps.PLAYER)
	_title.text = r.display_name.to_upper()
	_title.add_theme_color_override("font_color", r.color)
	if m.eliminated:
		_status.text = "Eliminated"
	elif not t.contact:
		_status.text = "No contact"
	else:
		_status.text = "At war" if war else t.stance_name()
	_status.add_theme_color_override("font_color", H.BAD if war else H.CREDITS if t.stance == RivalMind.Stance.HARASS and t.contact else H.TEXT_BRIGHT)
	var lines: PackedStringArray = []
	if not t.contact:
		lines.append("A rival charter works this sector. Its home is not found: survey the deep systems (4 to 5 jumps out). Its scouts may find you first.")
	else:
		var home := Sector.system_def(Corps.home_of(rid))
		lines.append("Home: %s" % (home.system_name if home and t.they_know_me else "unknown (survey it to find it)"))
		lines.append("Board: %s" % (m.personality_name() if t.personality_known else "not known yet"))
		lines.append("Relations: %+d" % roundi(t.relations))
		var tree := get_tree()
		lines.append("Strength: theirs ~%.0f, yours ~%.0f (mercenaries, turrets, shields, stations)" % [RivalCorp.strength(tree, rid), RivalCorp.strength(tree, Corps.PLAYER)])
		if SimClock.time < t.pact_until:
			lines.append("Trade pact: %s left" % Fmt.clock(t.pact_until - SimClock.time))
		if SimClock.time < t.ceasefire_until:
			lines.append("Ceasefire: %s left" % Fmt.clock(t.ceasefire_until - SimClock.time))
		# What it does with the other rivals it has met (known through your contact).
		for o in Corps.rivals:
			if o.id == rid or not m.has_tie(o.id) or not m.tie(o.id).contact:
				continue
			var ot := m.tie(o.id)
			var st := "out of the game" if o.mind.eliminated else "at war" if Corps.corps_at_war(rid, o.id) else ot.stance_name().to_lower()
			lines.append("With %s: %s" % [o.display_name, st])
	_facts.text = "\n".join(lines)
	var rc := RivalCorp.of(get_tree())
	for k: String in _buttons:
		var b: Button = _buttons[k]
		var why := rc.propose_problem(rid, k) if rc else "No rival"
		b.disabled = not why.is_empty() or m.eliminated
		b.tooltip_text = why if not why.is_empty() else _hint(k)
	var war_ok := war and t.they_know_me and not m.eliminated
	_strike.disabled = not war_ok
	_strike.tooltip_text = "Your idle mercenaries are offered %d cr each to fly to %s's home and hit its station (up to %d volunteer)" % [STRIKE_BONUS, r.display_name, STRIKE_SHIPS] \
			if war_ok else "Only at war, and only once you know where their home is"
	_poach.disabled = not t.contact or m.eliminated or Economy.credits < 400
	_poach.tooltip_text = "Offer the most disloyal rival captain 400 cr to join you (needs a free berth of its role)"
	for c in _intel.get_children():
		c.queue_free()
	var shown := 0
	for i in range(m.intel.size() - 1, -1, -1):
		var e := m.intel[i]
		if not bool(e.get("public", false)):
			continue
		var l := UIUtil.label("%s  %s" % [Fmt.clock(float(e["time"])), e["text"]], &"SmallLabel")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_intel.add_child(l)
		shown += 1
		if shown >= 30:
			break
	if shown == 0:
		_intel.add_child(UIUtil.label("Nothing yet", &"DimLabel"))


func _hint(k: String) -> String:
	match k:
		"pact":
			return "No hostilities for 20 min and trade income for both. Their board decides."
		"tribute":
			return "They pay if they are losing the war and tired of it."
		"peace":
			return "A ceasefire for 20 min if their board wants out of the war."
		"war":
			return "Open war: mercenaries and turrets on both sides fire, strikes, stations can be destroyed. Losing your home ends the game."
	return ""


func _propose(kind: String) -> void:
	var rc := RivalCorp.of(get_tree())
	if rc == null:
		return
	_reply.text = String(rc.player_proposes(rid, kind)["text"])
	_refresh()


func _launch_strike() -> void:
	var res := WarStrikes.launch(get_tree(), Corps.PLAYER, Corps.home_of(rid), STRIKE_BONUS, STRIKE_SHIPS)
	var sent: Array = res["sent"]
	var refused: PackedStringArray = res["refused"]
	_reply.text = "%d mercenar%s on the way%s" % [sent.size(), "y" if sent.size() == 1 else "ies", (". " + "; ".join(refused)) if not refused.is_empty() else ""] \
			if not sent.is_empty() else "Nobody went%s" % ((": " + "; ".join(refused)) if not refused.is_empty() else ": no idle mercenary at full hull")


func _recruit() -> void:
	var c := WarStrikes.poach_candidate(get_tree(), rid)
	if c == null:
		_reply.text = "No rival captain to approach right now"
		return
	if not Economy.spend(400, PackedInt32Array(), Ledger.HIRES, "Recruiting offer"):
		return
	var res := WarStrikes.poach(get_tree(), c, Corps.PLAYER, 400)
	if not bool(res["ok"]):
		Economy.add_income(400, Ledger.HIRES, "Recruiting offer refused")
	elif RivalCorp.mind(rid):
		RivalCorp.mind(rid).tie(Corps.PLAYER).grudge += 3.0
	_reply.text = String(res["text"])

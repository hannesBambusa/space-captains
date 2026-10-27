class_name TutorialCard
extends PanelContainer
## The [Tutorial]'s objective card, top left next to the left panel:
## "TRAINING 2/6", the step title, one or two plain sentences, a Skip
## tutorial button and a minimise toggle (minimised: one line). While a
## step needs a build bar tile (Mining Outpost, Mercenary Outpost, Defence
## zone) that tile gets a pulsing amber frame ([TutorialPulse]). The build
## bar only shows while a station is selected, so such a step selects the
## home station when it starts (home in view, bar hidden); if the player
## closes the bar later, the card says how to open it again. After the
## last step a short done card shows, closing itself after
## [member done_seconds] or by its button.

const H := preload("res://scripts/ui/theme/hud_style.gd")

@export var card_width: float = 360.0
## Real seconds the done card stays up.
@export var done_seconds: float = 30.0

var tutorial: Tutorial
var hud: HUD
var minimised := false

var _counter: Label
var _title: Label
var _body: Label
var _body_box: VBoxContainer
var _skip: Button
var _close: Button
var _toggle: Button
var _pulse: TutorialPulse
var _done_left := 0.0
## The step [method _sync] last saw (a new one may open the build bar).
var _last_step := Tutorial.OFF


func _ready() -> void:
	custom_minimum_size.x = card_width
	mouse_filter = Control.MOUSE_FILTER_STOP
	minimum_size_changed.connect(func() -> void: _fit.call_deferred())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	v.add_child(top)
	top.add_child(H.icon_rect(&"tab_contracts", 13.0, H.HOLO))
	_counter = UIUtil.label("", &"HeaderLabel")
	top.add_child(_counter)
	top.add_child(UIUtil.spacer())
	_toggle = UIUtil.button("", &"IconButton")
	_toggle.custom_minimum_size = Vector2(22.0, 18.0)
	_toggle.pressed.connect(func() -> void:
		minimised = not minimised
		_sync())
	top.add_child(_toggle)
	_title = UIUtil.label("", &"TitleLabel")
	_title.add_theme_color_override("font_color", H.ACCENT)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_title)
	_body_box = VBoxContainer.new()
	_body_box.add_theme_constant_override("separation", 6)
	v.add_child(_body_box)
	_body = UIUtil.label("", &"")
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = card_width - 28.0
	_body_box.add_child(_body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	_body_box.add_child(row)
	_skip = UIUtil.button("Skip tutorial", &"ChipButton")
	_skip.custom_minimum_size.y = 20.0
	_skip.add_theme_font_size_override("font_size", 11)
	_skip.tooltip_text = "End the tutorial. Turn it back on in the main menu Settings."
	_skip.pressed.connect(func() -> void: tutorial.finish())
	row.add_child(_skip)
	_close = UIUtil.button("Got it", &"AccentButton")
	_close.custom_minimum_size.y = 24.0
	_close.pressed.connect(func() -> void: tutorial.finish())
	row.add_child(_close)


func setup(owner_hud: HUD, t: Tutorial) -> void:
	hud = owner_hud
	tutorial = t
	_pulse = TutorialPulse.new()
	_pulse.name = "TutorialPulse"
	hud.get_node(^"Root").add_child.call_deferred(_pulse)
	tutorial.changed.connect(_sync)
	hud.build_menu.visibility_changed.connect(_sync)
	if hud.manager:
		hud.manager.building_added.connect(func(_b: Building) -> void: _sync())
	_sync()


func _process(delta: float) -> void:
	if tutorial == null or tutorial.step != Tutorial.DONE:
		return
	_done_left -= delta
	if _done_left <= 0.0:
		tutorial.finish()


func _sync() -> void:
	var s := tutorial.step if tutorial else Tutorial.OFF
	visible = s != Tutorial.OFF
	var need := _pulse_target(s)
	if _pulse:
		_pulse.target = need
	if s != _last_step:
		_last_step = s
		if need:
			_open_build_bar.call_deferred()
	if not visible:
		return
	var text := _text_for(s)
	if s == Tutorial.DONE:
		_counter.text = "TRAINING DONE"
		if _done_left <= 0.0:
			_done_left = done_seconds
	else:
		_counter.text = "TRAINING %d/%d" % [s + 1, Tutorial.STEP_COUNT]
		_done_left = 0.0
	_title.text = text[0]
	_body.text = text[1]
	if need and not hud.build_menu.visible:
		_body.text = "Select your station (click it or press H) to open the build bar. " + text[1]
	_body_box.visible = not minimised
	_skip.visible = s != Tutorial.DONE
	_close.visible = s == Tutorial.DONE
	_toggle.icon = H.icon(&"expand" if minimised else &"collapse")
	_toggle.tooltip_text = "Show the training card" if minimised else "Minimise the training card"
	_fit.call_deferred()


## A step that needs a build bar tile starts with the bar open: selects the
## home station (only while home is in view and the bar is hidden).
func _open_build_bar() -> void:
	if hud and not hud.build_menu.visible and hud.is_home_view():
		hud.select_station()


## Shrinks to the content (a free-standing panel only grows on its own).
func _fit() -> void:
	size = Vector2(card_width, 0.0)
	reset_size()


## [title, body] of step [param s], with the real hotkeys of the build bar.
func _text_for(s: int) -> PackedStringArray:
	match s:
		Tutorial.BUILD_MINING:
			return ["Build a Mining Outpost", "Press %s or click Mining Outpost in the build bar, then click a free spot near the station. Wait until construction is done." % _key(Tutorial.MINING_ID, "F1")]
		Tutorial.HIRE_MINER:
			return ["Hire a miner", "Click your Mining Outpost and press Hire miner. Miners choose their own work, but only on clusters with a contract."]
		Tutorial.POST_CONTRACT:
			return ["Post a mining contract", "Click an asteroid cluster (Cinder Cluster is closest) and press Post mining contract. The line \"Factory pays ~X / load, you pay Y: +Z\" shows your profit per load."]
		Tutorial.SELL_ORE:
			return ["Sell your first ore", "Your miner brings ore to the outpost, shuttles fly it to the station and the Factory buys it. Wait for the first sale."]
		Tutorial.MERCENARY:
			return ["Hire a mercenary", "Raids come. Press %s to build a Mercenary Outpost, then hire a mercenary there." % _key(Tutorial.MERC_ID, "F2")]
		Tutorial.DEFENCE_ZONE:
			return ["Set up a defence zone", "Press %s or click Defence zone, then click near your outposts. Your mercenaries patrol it and fight raiders there." % _zone_key()]
		Tutorial.DONE:
			return ["Done", "Tip: research at the Science Lab unlocks planet raids, the best money."]
	return ["", ""]


func _tile(id: StringName) -> Button:
	if hud == null or hud.manager == null or hud.build_menu == null:
		return null
	for d in hud.manager.building_defs:
		if d.id == id:
			return hud.build_menu.get_button(d)
	return null


func _key(id: StringName, fallback: String) -> String:
	var t := _tile(id) as BuildTile
	return t.hotkey if t and not t.hotkey.is_empty() else fallback


func _zone_key() -> String:
	var t := hud.build_menu.get_zone_button() as BuildTile if hud and hud.build_menu else null
	return t.hotkey if t and not t.hotkey.is_empty() else "F7"


## The build bar tile the step needs, or null.
func _pulse_target(s: int) -> Control:
	if hud == null or hud.manager == null or hud.build_menu == null:
		return null
	match s:
		Tutorial.BUILD_MINING:
			return null if _built(Tutorial.MINING_ID) else _tile(Tutorial.MINING_ID)
		Tutorial.MERCENARY:
			return null if _built(Tutorial.MERC_ID) else _tile(Tutorial.MERC_ID)
		Tutorial.DEFENCE_ZONE:
			return hud.build_menu.get_zone_button()
	return null


func _def(id: StringName) -> BuildingDef:
	for d in hud.manager.building_defs:
		if d.id == id:
			return d
	return null


func _built(id: StringName) -> bool:
	var d := _def(id)
	return d != null and hud.manager.count_of(d) > 0

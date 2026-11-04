class_name TutorialCard
extends PanelContainer
## The [Tutorial]'s objective card, top left next to the left panel.
## Every step has a title, a story line (SOLA, the station's operations AI,
## speaking: the text the voice lines are made from, so it never names a
## hotkey) and an objective line under it (what to do, with the real
## hotkeys of the build bar).
## Quick card (new games): "TRAINING 2/6", Skip tutorial and a minimise
## toggle (minimised: one line).
## Academy (the tutorial game): "MINING  2/4" with the chapter number, a
## Next button on info steps, Skip step, Chapters (a list of every chapter
## that jumps there: [method Tutorial.jump_to_chapter]) and Quit tutorial.
## While a step needs a build bar tile that tile gets a pulsing amber frame
## ([TutorialPulse]). The build bar only shows while a station is selected,
## so such a step selects the home station when it starts (home in view,
## bar hidden); if the player closes the bar later, the card says how to
## open it again. After the last step a done card shows, closing itself
## after [member done_seconds] or by its button.
## Voice: when a step opens, SOLA speaks its story line, the file
## [constant VOICE_DIR]<step id>.mp3 when there is one ("done" and
## "done_quick" for the done cards), on the Voice bus (its own slider in
## Settings). The speaker button on the card turns the voice off or on
## ([method Tutorial.voice_on], saved); turned on, it replays the line.
## The replay button next to it reads the current line again (shown while
## the voice is on and the step has a line).

const H := preload("res://scripts/ui/theme/hud_style.gd")
const VOICE_DIR := "res://assets/audio/voice/tutorial/"
const VOICE_BUS := &"Voice"

@export var card_width: float = 380.0
## Real seconds the done card stays up.
@export var done_seconds: float = 45.0

var tutorial: Tutorial
var hud: HUD
var minimised := false

var _counter: Label
var _title: Label
var _body: Label
var _goal: Label
var _body_box: VBoxContainer
var _chapters_box: VBoxContainer
var _next: Button
var _skip_step: Button
var _chapters: Button
var _skip: Button
var _close: Button
var _toggle: Button
var _voice_button: Button
var _replay_button: Button
var _voice: AudioStreamPlayer
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
	_voice = AudioStreamPlayer.new()
	_voice.name = "Voice"
	_voice.bus = VOICE_BUS
	add_child(_voice)
	_replay_button = UIUtil.button("", &"IconButton")
	_replay_button.custom_minimum_size = Vector2(22.0, 18.0)
	_replay_button.icon = H.icon(&"voice_replay")
	_replay_button.tooltip_text = "Hear SOLA read this again"
	_replay_button.pressed.connect(_speak)
	top.add_child(_replay_button)
	_voice_button = UIUtil.button("", &"IconButton")
	_voice_button.custom_minimum_size = Vector2(22.0, 18.0)
	_voice_button.pressed.connect(func() -> void:
		Tutorial.set_voice_on(not Tutorial.voice_on())
		if Tutorial.voice_on():
			_speak()
		else:
			_voice.stop()
		_sync_voice_button())
	top.add_child(_voice_button)
	_sync_voice_button()
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
	_goal = UIUtil.label("", &"")
	_goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_goal.custom_minimum_size.x = card_width - 28.0
	_goal.add_theme_color_override("font_color", H.HOLO)
	_body_box.add_child(_goal)
	_chapters_box = VBoxContainer.new()
	_chapters_box.add_theme_constant_override("separation", 3)
	_chapters_box.hide()
	_body_box.add_child(_chapters_box)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 6)
	_body_box.add_child(row)
	_chapters = _chip("Chapters", "Jump to any chapter")
	_chapters.toggle_mode = true
	_chapters.toggled.connect(func(on: bool) -> void:
		_chapters_box.visible = on
		if on:
			_fill_chapters()
		_fit.call_deferred())
	row.add_child(_chapters)
	_skip_step = _chip("Skip step", "Move on without doing this step")
	_skip_step.pressed.connect(func() -> void: tutorial.advance())
	row.add_child(_skip_step)
	_skip = _chip("Skip tutorial", "End the tutorial. Turn it back on in the main menu Settings.")
	_skip.pressed.connect(func() -> void: tutorial.finish())
	row.add_child(_skip)
	_next = UIUtil.button("Next", &"AccentButton")
	_next.custom_minimum_size.y = 24.0
	_next.pressed.connect(func() -> void: tutorial.advance())
	row.add_child(_next)
	_close = UIUtil.button("Got it", &"AccentButton")
	_close.custom_minimum_size.y = 24.0
	_close.pressed.connect(func() -> void: tutorial.finish())
	row.add_child(_close)


func _chip(text: String, tip: String) -> Button:
	var b := UIUtil.button(text, &"ChipButton")
	b.custom_minimum_size.y = 20.0
	b.add_theme_font_size_override("font_size", 11)
	b.tooltip_text = tip
	return b


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
	if tutorial == null or not tutorial.is_done_card():
		return
	_done_left -= delta
	if _done_left <= 0.0:
		tutorial.finish()


func _sync() -> void:
	var s := tutorial.step if tutorial else Tutorial.OFF
	visible = s != Tutorial.OFF
	var cur := tutorial.current() if tutorial else {}
	var need := _pulse_target(cur)
	# Only a build bar tile needs the bar open (the time step pulses the top bar).
	var bar := need != null and (cur.has("build") or bool(cur.get("zone", false)))
	if _pulse:
		_pulse.target = need
	if s != _last_step:
		_last_step = s
		_chapters.set_pressed_no_signal(false)
		_chapters_box.hide()
		if bar:
			_open_build_bar.call_deferred()
		_speak()
		_sync_voice_button()
	if not visible:
		return
	var academy := tutorial.mode == Tutorial.ACADEMY
	var done := tutorial.is_done_card()
	var text := _done_text() if done else _text_for(cur.get("id", &""))
	if done:
		_counter.text = "TUTORIAL COMPLETE" if academy else "TRAINING DONE"
		if _done_left <= 0.0:
			_done_left = done_seconds
	else:
		_done_left = 0.0
		if academy:
			var c := tutorial.chapter_of()
			var p := tutorial.chapter_progress()
			_counter.text = "%d. %s   %d/%d" % [c + 1, String(Tutorial.chapters()[c]["name"]).to_upper(), p.x, p.y]
		else:
			_counter.text = "TRAINING %d/%d" % [s + 1, tutorial.step_count()]
	_title.text = text[0]
	_body.text = text[1]
	_goal.text = text[2]
	if bar and not hud.build_menu.visible:
		_goal.text = "Select your station (click it or press H) to open the build bar. " + text[2]
	_goal.visible = not _goal.text.is_empty()
	_body_box.visible = not minimised
	var info := bool(cur.get("info", false))
	_next.visible = info and not done
	_skip_step.visible = academy and not done and not info
	_chapters.visible = academy and not done
	_skip.visible = not done
	_skip.text = "Quit tutorial" if academy else "Skip tutorial"
	_skip.tooltip_text = "End the tutorial; this game goes on as a normal sandbox" if academy \
			else "End the tutorial. Turn it back on in the main menu Settings."
	_close.visible = done
	_close.text = "Keep playing" if academy else "Got it"
	_toggle.icon = H.icon(&"expand" if minimised else &"collapse")
	_toggle.tooltip_text = "Show the training card" if minimised else "Minimise the training card"
	_fit.call_deferred()


func _fill_chapters() -> void:
	for c in _chapters_box.get_children():
		c.queue_free()
	var list := Tutorial.chapters()
	var now := tutorial.chapter_of()
	for i in list.size():
		var b := UIUtil.button("%d. %s  ·  %s" % [i + 1, list[i]["name"], list[i]["blurb"]], &"ChipButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 22.0
		b.add_theme_font_size_override("font_size", 11)
		b.disabled = i == now
		if i < now:
			b.add_theme_color_override("font_color", H.TEXT_DIM)
		var c := i
		b.pressed.connect(func() -> void: tutorial.jump_to_chapter(c))
		_chapters_box.add_child(b)


## The voice file of the current step or done card ("" when off).
func voice_key() -> String:
	if tutorial == null or tutorial.step == Tutorial.OFF:
		return ""
	if tutorial.is_done_card():
		return "done" if tutorial.mode == Tutorial.ACADEMY else "done_quick"
	return String(tutorial.current().get("id", &""))


## Plays the current line (stops the one before); silent without a file,
## with the voice turned off or the tutorial over.
func _speak() -> void:
	if _voice == null:
		return
	_voice.stop()
	var key := voice_key()
	if key.is_empty() or not Tutorial.voice_on():
		return
	var path := VOICE_DIR + key + ".mp3"
	if not ResourceLoader.exists(path):
		return
	_voice.stream = load(path) as AudioStream
	_voice.play()


## The current step has a voice line on disk.
func has_line() -> bool:
	var key := voice_key()
	return not key.is_empty() and ResourceLoader.exists(VOICE_DIR + key + ".mp3")


func _sync_voice_button() -> void:
	var on := Tutorial.voice_on()
	_replay_button.visible = on and has_line()
	_voice_button.icon = H.icon(&"voice_on" if on else &"voice_off")
	_voice_button.tooltip_text = "Turn SOLA's voice off" if on else "Turn SOLA's voice on (replays this line)"


## A step that needs a build bar tile starts with the bar open: selects the
## home station (only while home is in view and the bar is hidden).
func _open_build_bar() -> void:
	if hud and not hud.build_menu.visible and hud.is_home_view():
		hud.select_station()


## Shrinks to the content (a free-standing panel only grows on its own).
func _fit() -> void:
	size = Vector2(card_width, 0.0)
	reset_size()


## [title, story, objective] of the done card.
func _done_text() -> PackedStringArray:
	if tutorial.mode == Tutorial.ACADEMY:
		return ["Training complete",
				"Training complete. You are cleared to run Solace Station on your own. From here on the sector plays for keeps: raids and new pirate bases will come as they please. Good luck, administrator.",
				"Keep playing this game, or start a New game, with rival corporations if you want company."]
	return ["Setup complete",
			"Initial setup complete. When you are ready, look to the planets. Surface operations, researched at the Science Lab, opens the best money in the sector.",
			"The main menu's Tutorial shows every part of the game."]


## [title, story, objective] of step [param id]. The story is what SOLA
## says (the voice line, no hotkeys); the objective has the real hotkeys.
func _text_for(id: StringName) -> PackedStringArray:
	match id:
		&"welcome":
			return ["Welcome aboard",
					"Welcome aboard, administrator. I am SOLA, operations intelligence for Solace Station. The corporation has placed this station in your hands, with a few thousand credits and a quiet sector to grow. You run the operation. You build the outposts, hire the captains and set the contracts. The captains fly the ships and take the work that pays them best. Your job is to make the right work worth taking.",
					"Raids stay off until the defence chapter. Press Next when you are ready."]
		&"camera":
			return ["Get your bearings",
					"First, get your bearings. My sensors cover the whole Solace system, from the station hull out to the coldest moon.",
					"Middle-drag, Alt-drag or W A S D to move the camera. Scroll to zoom out to the whole system. Left-drag, Q or E to turn."]
		&"time":
			return ["Change the game speed",
					"Time is yours to command. I can hold the sector still, or speed it up many times over. Building, research and travel all take time, so you will do this often. Try it now. Change the game speed.",
					"Click the speed readout at the top right to go faster (right-click: slower), or press 2 for double speed. Any speed change or pause finishes this step. Later: Space pauses, keys 1 to 6 pick a speed, + and - step it."]
		&"station":
			return ["Solace Station",
					"This is Solace Station. Every structure you raise is ordered from here.",
					"Click the station or press H to open the build bar. Hover a tile for its cost and details."]
		&"build_mining":
			return ["Build a Mining Outpost",
					"Money comes from ore. The Factory pays well for iron, and the asteroid clusters nearby are full of it. Miners need somewhere to dock. Let us build them a Mining Outpost.",
					"Press %s (or click Mining Outpost), place it near the station and wait for construction." % _key(Tutorial.MINING_ID, "F1")]
		&"hire_miner":
			return ["Hire a miner",
					"The outpost is online, but it is empty. Captains are independent contractors. They sign on, they fly, and they decide where to go.",
					"Click the Mining Outpost and press Hire miner."]
		&"post_mining":
			return ["Post a mining contract",
					"Your miner is docked and waiting for a reason to leave. Captains only work where someone pays. Post a contract on a cluster and they will go. Richer rocks pay more, and draw more pirates.",
					"Click an asteroid cluster (the nearest is safest) and press Post mining contract. The profit line shows what each load earns you."]
		&"sell_ore":
			return ["Sell your first ore",
					"Contract posted. When a miner takes it, the ore goes from the rock to the outpost, then by shuttle to the station, and the Factory buys it. I will tell you when the first credits arrive.",
					"Wait for the first ore sale. Speed up time if you like."]
		&"merc":
			return ["Hire a mercenary",
					"Long-range scans show a scavenger base in this system, the Rustjaw Hideout. A station with money coming in is worth robbing. They will come. We need guns of our own.",
					"Press %s to build a Mercenary Outpost, then hire a mercenary there." % _key(Tutorial.MERC_ID, "F2")]
		&"zone":
			return ["Set up a defence zone",
					"Mercenaries go where the fighting is. Mark the space you want held, and they will patrol it.",
					"Press %s (or click Defence zone), then click near your outposts." % _zone_key()]
		&"turret":
			return ["Build a Defense Turret",
					"Mercenaries come and go. Turrets stay. They need no captain, and they never ask for a raise.",
					"Press %s and place a Defense Turret near what you want to keep." % _key(&"defense_turret", "its key")]
		&"raid":
			return ["Fight off a raid",
					"Alert. Rustjaw ships are leaving their base on an attack course. A small raid, sent to test us. Let us pass the test.",
					"Watch the event feed. The step ends when the first raider is shot down."]
		&"bounty":
			return ["Post a bounty",
					"The Rustjaw raiders will keep coming while their base stands. We can put a price on it. A bounty is shared by the mercenaries who bring the target down, and I set the credits aside the moment you post it.",
					"Click the Rustjaw Hideout (or a raider) and post a bounty. Bigger rewards draw more, and better, captains."]
		&"escort":
			return ["Protect your miners",
					"Our miners fly unarmed. Out at the clusters they are easy prey. An escort contract pays mercenaries to fly beside them.",
					"Click your mining cluster and post a new mining contract with Escorted switched on, or select a miner and press Request escort."]
		&"salvage_yard":
			return ["Build a Salvage Yard",
					"Every fight leaves wreckage, and wreckage is metal. A Salvage Yard turns scrap back into ore.",
					"Press %s to build a Salvage Yard." % _key(&"salvage_yard", "its key")]
		&"hire_salvager":
			return ["Hire a salvager",
					"Salvagers find the scrap on their own. When you want one field cleared first, a salvage contract adds a bonus.",
					"Click the Salvage Yard and hire a salvager."]
		&"lab":
			return ["Build a Science Lab",
					"Our captains fly with the cheapest equipment the corporation could find. Research changes that: better modules, new buildings, and a way past the gates.",
					"Press %s to build the Science Lab, a station addon." % _key(&"science_lab", "its key")]
		&"researcher":
			return ["Hire a researcher",
					"The lab needs minds. Applicants are waiting. Each has a field and a temper, and each draws a wage.",
					"Click the Science Lab (or the research box in the top bar), open the Staff tab and hire a researcher."]
		&"fund":
			return ["Fund a project",
					"Researchers choose their own projects, but only from the ones you pay for. Funding sets the credits aside at once.",
					"Fund a project in your researcher's field (they may turn others down). Survival systems, Ballistic calibration and Cargo racks are cheap first picks."]
		&"tech_done":
			return ["Finish a project",
					"Work has begun. Science is slow, so feel free to let the hours pass. I will report when it is done.",
					"Speed up time and wait for the project to finish."]
		&"factory":
			return ["Visit the Factory",
					"Meet our partner, the Factory. It buys your ore and builds the modules captains need, and what it makes follows what they ask for.",
					"Click the Factory, the addon on the station hull, to see its stock and prices."]
		&"outfitter":
			return ["Build an Outfitter",
					"Captains earn their own money, and the good ones spend it on their ships. Give them a place to shop.",
					"Press %s to build the Outfitter." % _key(&"outfitter", "its key")]
		&"gear_sale":
			return ["First gear sale",
					"The shop is open. A captain with credits to spend will dock soon.",
					"Wait for the first module sale."]
		&"jump_nav":
			return ["Research Jump navigation",
					"Solace is only one system. Our jump gates lead out into the dark. To chart what lies beyond them, we need Jump navigation.",
					"Fund Jump navigation at the Science Lab and let it finish."]
		&"explorer_outpost":
			return ["Build an Explorer Outpost",
					"Navigation data received. Explorers will need a berth.",
					"Press %s to build the Explorer Outpost." % _key(&"explorer_outpost", "its key")]
		&"hire_explorer":
			return ["Hire an explorer",
					"Explorers are a different breed. Patient, curious, and paid only when they come home.",
					"Click the Explorer Outpost and hire an explorer."]
		&"explore":
			return ["Post an explore contract",
					"Pick a gate. Your explorer will cross it, survey the system beyond and bring the charts home. Derelicts and discoveries pay extra.",
					"Click a jump gate and post an explore contract."]
		&"map":
			return ["Open the cluster map",
					"The cluster map holds every system we know and every gate between them. Each chart that comes home fills in a little more.",
					"Press M (or MAP in the top bar)."]
		&"surface_ops":
			return ["Research Surface operations",
					"The best money in this sector is not in the rocks. It is on the planets. Before we can land, we need Orbital survey, then Surface operations.",
					"Fund Orbital survey at the Science Lab. When it finishes, fund Surface operations and let it finish."]
		&"found_outpost":
			return ["Found a planet outpost",
					"Surface operations approved. Choose a world. A lander will carry the first structures down.",
					"Click a planet or moon and found an outpost in its OUTPOST section."]
		&"visit_surface":
			return ["Visit the surface",
					"The lander is on its way down. Once it lands, the colony is yours to plan: harvesters, soldiers, contracts. I will keep watch on the station while you are down there.",
					"Once the lander touches down (about a minute), double-click the planet or use its panel's outpost button to go down. H brings you back."]
		&"forward_ops":
			return ["Research Forward operations",
					"Our reach ends at the gates. A forward station would carry it further, and Forward operations is the research that makes one possible.",
					"Fund Forward operations and let it finish."]
		&"forward_build":
			return ["Build a Forward Station",
					"Plans approved. We build the forward station here, then fly it to its new home. It costs water to build, and it can only go to a system we have charted.",
					"Press %s to build a Forward Station at home." % _key(&"forward_station", "its key")]
		&"forward_found":
			return ["Found the forward station",
					"The mobile station is ready to depart. Choose its destination. Escorts will fly with it, and it unfolds on arrival. Remember, forward stations pay upkeep, and they drink water.",
					"Select the mobile station and set its destination, or use Set destination here on the cluster map. It leaves once a mercenary takes the escort contract, so you need a Mercenary Outpost with crew."]
		&"rivals":
			return ["Rival corporations",
					"One last thing, administrator. We are not the only corporation out here. In a new game, rivals may build, explore and expand as we do. Some will trade. Some will make war. If the home station falls, so do we.",
					"In games with rivals, press R for the Rival panel. Press Next to finish."]
	return ["", "", ""]


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
func _pulse_target(cur: Dictionary) -> Control:
	if hud == null or hud.manager == null or hud.build_menu == null or cur.is_empty():
		return null
	if bool(cur.get("zone", false)):
		return hud.build_menu.get_zone_button()
	if cur.get("id", &"") == &"time":
		return hud.top_bar.speed_control
	var id: StringName = cur.get("build", &"")
	if id.is_empty() or _built(id):
		return null
	return _tile(id)


func _def(id: StringName) -> BuildingDef:
	for d in hud.manager.building_defs:
		if d.id == id:
			return d
	return null


func _built(id: StringName) -> bool:
	var d := _def(id)
	return d != null and hud.manager.count_of(d) > 0

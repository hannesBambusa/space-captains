class_name MainMenu
extends Control
## The start screen (scenes/main_menu.tscn, the project's main scene):
## Continue (the newest save), New game, Tutorial (the guided tutorial game:
## SaveManager.new_game(true), [Tutorial] academy mode), Load game ([SaveList]), Settings
## (fullscreen, the tutorial for new games, volumes, a Graphics page:
## [GraphicsOptions]) and Quit, over the slowly turning station ([MenuBackdrop]).
## Styled like the pause menu (ui/theme.tres).
## Run with "-- --screenshot=..." it starts a new game at once, so the
## screenshot check keeps rendering the system (with "-- --tutorial" too,
## the tutorial game).

const THEME_PATH := "res://ui/theme.tres"
const TITLE_COLOR := HudStyle.ACCENT
const HOVER_COOLDOWN := 0.06

var _main: VBoxContainer
var _loads: SaveList
var _settings: VBoxContainer
var _graphics: VBoxContainer
var _continue: Button
var _continue_hint: Label
var _error: Label
var _backup: Button
var _fullscreen: Button
var _tutorial: CheckButton
var _newest: Dictionary = {}
## The New game page: rivals (0 to 3) and their difficulty, then Start.
var _new: VBoxContainer
var _pick_count := 0
var _pick_diff: CorpRegistry.Difficulty = CorpRegistry.Difficulty.NORMAL
var _count_buttons: Array[Button] = []
var _diff_buttons: Array[Button] = []
var _new_hint: Label
## Sector modifier choice (an id or SectorModifier.RANDOM) and its buttons.
var _pick_mod: StringName = SectorModifier.STANDARD
var _mod_buttons: Array[Button] = []
var _mod_ids: Array[StringName] = []
var _mod_hint: Label
var _last_hover := -1.0


func _ready() -> void:
	if ResourceLoader.exists(THEME_PATH):
		theme = load(THEME_PATH)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			SaveManager.new_game.call_deferred("--tutorial" in OS.get_cmdline_user_args())
			return
	_build()
	_show_main()


func _build() -> void:
	# Darken the left side under the menu.
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.0, 0.0, 0.03, 0.82))
	grad.set_color(1, Color(0.0, 0.0, 0.03, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_to = Vector2(1.0, 0.0)
	shade.texture = tex
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = 1000.0
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	margin.offset_right = 760.0
	margin.add_theme_constant_override("margin_left", 110)
	margin.add_theme_constant_override("margin_top", 110)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	margin.add_child(col)

	var kicker := HBoxContainer.new()
	kicker.add_theme_constant_override("separation", 10)
	var bar := ColorRect.new()
	bar.color = TITLE_COLOR
	bar.custom_minimum_size = Vector2(36, 3)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	kicker.add_child(bar)
	var kl := UIUtil.label("SOLACE SECTOR  /  STATION ADMINISTRATION", &"HeaderLabel")
	kl.add_theme_font_override("font", HudStyle.mono("Medium", 2))
	kl.add_theme_font_size_override("font_size", 14)
	kicker.add_child(kl)
	col.add_child(kicker)
	var title := Label.new()
	title.text = "SPACE CAPTAINS"
	title.add_theme_font_override("font", HudStyle.font("Bold", true, false, 8))
	title.add_theme_color_override("font_color", HudStyle.TEXT_BRIGHT)
	title.add_theme_font_size_override("font_size", 92)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.add_theme_constant_override("shadow_outline_size", 10)
	col.add_child(title)
	col.add_child(HudStyle.hazard_stripe(Vector2(240, 8)))
	var sub := UIUtil.label("Run the station. Hire the captains. Let them choose.", &"DimLabel")
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", HudStyle.TEXT)
	col.add_child(sub)
	col.add_child(UIUtil.spacer(0.0))

	var panel := PanelContainer.new()
	panel.theme_type_variation = &"MenuPanel"
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(panel)
	var stack := VBoxContainer.new()
	panel.add_child(stack)

	_main = VBoxContainer.new()
	_main.custom_minimum_size = Vector2(380, 0)
	_main.add_theme_constant_override("separation", 10)
	stack.add_child(_main)
	_continue = _button("Continue", _on_continue, &"AccentButton")
	_continue.custom_minimum_size.y = 54.0
	_continue.add_theme_font_size_override("font_size", 21)
	_main.add_child(_continue)
	_continue_hint = UIUtil.label("", &"DimLabel")
	_continue_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main.add_child(_continue_hint)
	_error = UIUtil.label("", &"WarnLabel")
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.custom_minimum_size.x = 340.0
	_main.add_child(_error)
	_backup = _button("Load the backup", _on_backup)
	_main.add_child(_backup)
	_main.add_child(_button("New game", _show_new))
	var tut := _button("Tutorial", func() -> void: SaveManager.new_game(true))
	tut.tooltip_text = "A guided game in chapters: every part of the job, no rivals, raids only when the defence chapter asks for one"
	_main.add_child(tut)
	_main.add_child(_button("Load game", _show_loads))
	_main.add_child(_button("Settings", _show_settings))
	_main.add_child(_button("Quit", func() -> void: get_tree().quit()))

	_loads = SaveList.new()
	_loads.back.connect(_show_main)
	stack.add_child(_loads)

	_build_new(stack)

	_settings = VBoxContainer.new()
	_settings.custom_minimum_size = Vector2(380, 0)
	_settings.add_theme_constant_override("separation", 10)
	stack.add_child(_settings)
	var st := UIUtil.label("SETTINGS", &"TitleLabel")
	_settings.add_child(st)
	_fullscreen = _button("", _toggle_fullscreen)
	_settings.add_child(_fullscreen)
	var keys := UIUtil.label("F11 or Alt+Enter also toggles fullscreen", &"DimLabel")
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings.add_child(keys)
	_tutorial = CheckButton.new()
	_tutorial.text = "TUTORIAL"
	_tutorial.theme_type_variation = &"MainMenuButton"
	_tutorial.focus_mode = Control.FOCUS_NONE
	_tutorial.custom_minimum_size.y = 46.0
	_tutorial.mouse_entered.connect(_play_hover)
	_tutorial.tooltip_text = "Show the training card in a new game"
	_tutorial.toggled.connect(func(on: bool) -> void: Tutorial.set_runs_on_new_game(on))
	_settings.add_child(_tutorial)
	var tut_hint := UIUtil.label("New games start with a short training card", &"DimLabel")
	tut_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings.add_child(tut_hint)
	_settings.add_child(VolumeSliders.new())
	_settings.add_child(_button("Graphics", _show_graphics))
	_settings.add_child(_button("Back", _show_main))

	_graphics = VBoxContainer.new()
	_graphics.add_theme_constant_override("separation", 12)
	stack.add_child(_graphics)
	_graphics.add_child(UIUtil.label("GRAPHICS", &"TitleLabel"))
	_graphics.add_child(GraphicsOptions.new())
	_graphics.add_child(_button("Back", _show_settings))

	UIUtil.no_focus(self)


func _button(text: String, action: Callable, variation: StringName = &"MainMenuButton") -> Button:
	var b := UIUtil.button(text.to_upper(), variation)
	b.custom_minimum_size = Vector2(0, 46)
	if variation == &"MainMenuButton":
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(action)
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			_play_hover())
	return b


## The hover click (Sfx "ui_hover"), at most once per [constant HOVER_COOLDOWN] so a fast
## sweep over the buttons does not rattle.
func _play_hover() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_hover < HOVER_COOLDOWN:
		return
	_last_hover = now
	Sfx.ui(&"ui_hover")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo() and not _main.visible:
		if _graphics.visible:
			_show_settings()
		else:
			_show_main()
		get_viewport().set_input_as_handled()


func _show_main() -> void:
	_new.hide()
	_loads.hide()
	_settings.hide()
	_graphics.hide()
	_main.show()
	_newest = SaveManager.newest_save()
	_error.hide()
	_backup.hide()
	if _newest.is_empty():
		_continue.disabled = true
		_continue_hint.text = "No saved game yet"
	else:
		_continue.disabled = false
		_continue_hint.text = "%s  ·  %s" % [_newest["name"], SaveList.date_text(int(_newest.get("saved_at", 0)))]
		if not bool(_newest.get("ok", false)):
			_show_error(String(_newest.get("error", "")))


func _show_loads() -> void:
	_main.hide()
	_new.hide()
	_settings.hide()
	_graphics.hide()
	_loads.playing_slot = ""
	_loads.refresh()
	_loads.show()


func _show_settings() -> void:
	_main.hide()
	_new.hide()
	_loads.hide()
	_graphics.hide()
	_update_fullscreen()
	_tutorial.set_pressed_no_signal(Tutorial.runs_on_new_game())
	_settings.show()


func _show_graphics() -> void:
	_settings.hide()
	_graphics.show()


# --- New game ---------------------------------------------------------------------

## The New game page (rival corporation plan): how many rival corps (none,
## 1, 2 or 3) and one difficulty for all of them, remembered for next time
## (Corps.set_next_difficulty / set_next_rival_count), the sector modifier
## ([SectorModifier], or Random; Sector.set_next_modifier), then Start.
func _build_new(stack: Control) -> void:
	_new = VBoxContainer.new()
	_new.custom_minimum_size = Vector2(420, 0)
	_new.add_theme_constant_override("separation", 12)
	stack.add_child(_new)
	_new.add_child(UIUtil.label("NEW GAME", &"TitleLabel"))
	_new.add_child(UIUtil.label("RIVAL CORPORATIONS", &"SubHeaderLabel"))
	var counts := HBoxContainer.new()
	counts.add_theme_constant_override("separation", 6)
	_new.add_child(counts)
	var cg := ButtonGroup.new()
	for n in Corps.MAX_RIVALS + 1:
		var b := _choice(["NONE", "1", "2", "3"][n], cg, "No rival: the sector is yours and the pirates'" if n == 0
				else "%d rival AI corporation%s, each in its own corner of the sector 4 to 5 jumps out" % [n, "" if n == 1 else "s"])
		b.pressed.connect(func() -> void:
			_pick_count = n
			_update_new())
		counts.add_child(b)
		_count_buttons.append(b)
	_new.add_child(UIUtil.label("DIFFICULTY", &"SubHeaderLabel"))
	var diffs := HBoxContainer.new()
	diffs.add_theme_constant_override("separation", 6)
	_new.add_child(diffs)
	var dg := ButtonGroup.new()
	for d: int in [CorpRegistry.Difficulty.EASY, CorpRegistry.Difficulty.NORMAL, CorpRegistry.Difficulty.HARD]:
		var b := _choice(Corps.DIFFICULTY_NAMES[d].to_upper(), dg, ["", "Smaller grant (x0.8), slower boards, less war", "The same rules as you",
				"Bigger grant (x1.3), faster boards and scouts, more war"][d])
		b.pressed.connect(func() -> void:
			_pick_diff = d as CorpRegistry.Difficulty
			_update_new())
		diffs.add_child(b)
		_diff_buttons.append(b)
	_new_hint = UIUtil.label("", &"DimLabel")
	_new_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_new_hint.custom_minimum_size.x = 420.0
	_new.add_child(_new_hint)
	_new.add_child(UIUtil.label("SECTOR", &"SubHeaderLabel"))
	var mods := HFlowContainer.new()
	mods.add_theme_constant_override("h_separation", 6)
	mods.add_theme_constant_override("v_separation", 6)
	mods.custom_minimum_size.x = 420.0
	_new.add_child(mods)
	var mg := ButtonGroup.new()
	_mod_ids.clear()
	for m in SectorModifier.LIST:
		_mod_ids.append(m["id"])
	_mod_ids.append(SectorModifier.RANDOM)
	for id in _mod_ids:
		var tip := "One of the others, rolled when the game starts" if id == SectorModifier.RANDOM else String(SectorModifier.find(id)["blurb"])
		var b := _choice(SectorModifier.name_of(id).to_upper(), mg, tip)
		b.custom_minimum_size = Vector2(0, 32)
		b.pressed.connect(func() -> void:
			_pick_mod = id
			_update_new())
		mods.add_child(b)
		_mod_buttons.append(b)
	_mod_hint = UIUtil.label("", &"DimLabel")
	_mod_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mod_hint.custom_minimum_size.x = 420.0
	_new.add_child(_mod_hint)
	_new.add_child(_button("Start game", _start_new))
	_new.add_child(_button("Back", _show_main))
	_new.hide()


func _choice(text: String, group: ButtonGroup, tip: String) -> Button:
	var b := UIUtil.button(text, &"ChipButton")
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size = Vector2(96, 40)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = tip
	b.mouse_entered.connect(_play_hover)
	return b


func _show_new() -> void:
	_main.hide()
	_loads.hide()
	_settings.hide()
	_graphics.hide()
	var off := Corps.next_difficulty == CorpRegistry.Difficulty.OFF
	_pick_count = 0 if off else Corps.next_rival_count
	_pick_diff = CorpRegistry.Difficulty.NORMAL if off else Corps.next_difficulty
	_pick_mod = Sector.next_modifier
	_update_new()
	_new.show()


func _update_new() -> void:
	for i in _count_buttons.size():
		_count_buttons[i].set_pressed_no_signal(i == _pick_count)
	for i in _diff_buttons.size():
		_diff_buttons[i].set_pressed_no_signal(i + 1 == int(_pick_diff))
		_diff_buttons[i].disabled = _pick_count == 0
	for i in _mod_buttons.size():
		_mod_buttons[i].set_pressed_no_signal(_mod_ids[i] == _pick_mod)
	_mod_hint.text = "One of the five sectors other than Standard, rolled at the start. The first feed line says which." \
			if _pick_mod == SectorModifier.RANDOM else String(SectorModifier.find(_pick_mod)["blurb"])
	if _pick_count == 0:
		_new_hint.text = "No rival corporation: only you and the pirates."
	else:
		_new_hint.text = "%d rival corporation%s on %s. They build, explore and choose peace, pacts, harassment or war on their own, with you and with each other. Losing your home station ends the game." % [
				_pick_count, "" if _pick_count == 1 else "s", Corps.DIFFICULTY_NAMES[_pick_diff]]


func _start_new() -> void:
	Corps.set_next_difficulty(CorpRegistry.Difficulty.OFF if _pick_count == 0 else _pick_diff)
	if _pick_count > 0:
		Corps.set_next_rival_count(_pick_count)
	Sector.set_next_modifier(_pick_mod)
	SaveManager.new_game()


func _on_continue() -> void:
	if _newest.is_empty():
		return
	var err: String = await SaveManager.load_game(String(_newest["slot"]))
	if not err.is_empty() and is_instance_valid(self):
		_show_error(err)


func _on_backup() -> void:
	var err: String = await SaveManager.load_game(String(_newest["slot"]), true)
	if not err.is_empty() and is_instance_valid(self):
		_show_error("Backup: " + err)
		_backup.hide()


func _show_error(err: String) -> void:
	_error.text = err
	_error.show()
	_backup.visible = bool(_newest.get("has_backup", false))


func _toggle_fullscreen() -> void:
	WindowMode.set_fullscreen(not WindowMode.is_fullscreen())
	_update_fullscreen.call_deferred()


func _update_fullscreen() -> void:
	_fullscreen.text = "FULLSCREEN: ON" if WindowMode.is_fullscreen() else "FULLSCREEN: OFF"

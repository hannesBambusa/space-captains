class_name MainMenu
extends Control
## The start screen (scenes/main_menu.tscn, the project's main scene):
## Continue (the newest save), New game, Load game ([SaveList]), Settings
## (fullscreen) and Quit, over the slowly turning station ([MenuBackdrop]).
## Styled like the pause menu (ui/theme.tres).
## Run with "-- --screenshot=..." it starts a new game at once, so the
## screenshot check keeps rendering the system.

const THEME_PATH := "res://ui/theme.tres"
const TITLE_COLOR := Color(1.0, 0.55, 0.15)
## Click played when the mouse moves onto a button (made with ElevenLabs).
const HOVER_SOUND := "res://assets/audio/ui/menu_hover.wav"
const HOVER_VOLUME_DB := -14.0
const HOVER_COOLDOWN := 0.06

var _main: VBoxContainer
var _loads: SaveList
var _settings: VBoxContainer
var _continue: Button
var _continue_hint: Label
var _error: Label
var _backup: Button
var _fullscreen: Button
var _newest: Dictionary = {}
var _hover_player: AudioStreamPlayer
var _last_hover := -1.0


func _ready() -> void:
	if ResourceLoader.exists(THEME_PATH):
		theme = load(THEME_PATH)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			SaveManager.new_game.call_deferred()
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
	margin.add_theme_constant_override("margin_top", 150)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	margin.add_child(col)

	var title := Label.new()
	title.text = "SPACE CAPTAINS"
	title.add_theme_color_override("font_color", TITLE_COLOR)
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	title.add_theme_constant_override("outline_size", 8)
	col.add_child(title)
	var sub := UIUtil.label("Run the station. Hire the captains. Let them choose.", &"DimLabel")
	sub.add_theme_font_size_override("font_size", 18)
	col.add_child(sub)
	col.add_child(UIUtil.spacer(0.0))

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(panel)
	var pm := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pm.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(pm)
	var stack := VBoxContainer.new()
	pm.add_child(stack)

	_main = VBoxContainer.new()
	_main.custom_minimum_size = Vector2(340, 0)
	_main.add_theme_constant_override("separation", 10)
	stack.add_child(_main)
	_continue = _button("Continue", _on_continue, &"AccentButton")
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
	_main.add_child(_button("New game", func() -> void: SaveManager.new_game()))
	_main.add_child(_button("Load game", _show_loads))
	_main.add_child(_button("Settings", _show_settings))
	_main.add_child(_button("Quit", func() -> void: get_tree().quit()))

	_loads = SaveList.new()
	_loads.back.connect(_show_main)
	stack.add_child(_loads)

	_settings = VBoxContainer.new()
	_settings.custom_minimum_size = Vector2(340, 0)
	_settings.add_theme_constant_override("separation", 10)
	stack.add_child(_settings)
	var st := UIUtil.label("SETTINGS", &"TitleLabel")
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings.add_child(st)
	_fullscreen = _button("", _toggle_fullscreen)
	_settings.add_child(_fullscreen)
	var keys := UIUtil.label("F11 or Alt+Enter also toggles fullscreen", &"DimLabel")
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings.add_child(keys)
	_settings.add_child(_button("Back", _show_main))

	UIUtil.no_focus(self)


func _button(text: String, action: Callable, variation: StringName = &"") -> Button:
	var b := UIUtil.button(text, variation)
	b.custom_minimum_size = Vector2(0, 44)
	b.pressed.connect(action)
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			_play_hover())
	return b


## The hover click, at most once per [constant HOVER_COOLDOWN] so a fast
## sweep over the buttons does not rattle.
func _play_hover() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_hover < HOVER_COOLDOWN:
		return
	_last_hover = now
	if _hover_player == null:
		_hover_player = AudioStreamPlayer.new()
		_hover_player.stream = load(HOVER_SOUND)
		_hover_player.volume_db = HOVER_VOLUME_DB
		add_child(_hover_player)
	_hover_player.play()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo() and not _main.visible:
		_show_main()
		get_viewport().set_input_as_handled()


func _show_main() -> void:
	_loads.hide()
	_settings.hide()
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
	_settings.hide()
	_loads.playing_slot = ""
	_loads.refresh()
	_loads.show()


func _show_settings() -> void:
	_main.hide()
	_loads.hide()
	_update_fullscreen()
	_settings.show()


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
	_fullscreen.text = "Fullscreen: on" if WindowMode.is_fullscreen() else "Fullscreen: off"

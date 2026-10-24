extends CanvasLayer
## Autoload "PauseMenu". Esc opens it during a game when nothing else used the
## key (placing a building and selections handle Esc first). Pauses the sim
## while open. Save game writes the current slot, Load game lists the saves
## ([SaveList]), Main menu and Quit save first (SaveManager).
## Also shows short toasts ("Game saved") at the top of the screen, open or not.

const THEME_PATH := "res://ui/theme.tres"
const TOAST_TIME := 2.2

var _root: Control
var _main: VBoxContainer
var _loads: SaveList
var _fullscreen_button: Button
var _was_paused := false
var _toast: Label
var _toast_left := 0.0


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_build_toast()
	_root.hide()


func is_open() -> bool:
	return _root.visible


## The pause state under the menu (what a save made now should keep).
func real_paused() -> bool:
	return _was_paused if is_open() else SimClock.paused


func open() -> void:
	if is_open():
		return
	_was_paused = SimClock.paused
	SimClock.set_paused(true)
	_update_fullscreen_label()
	_show_main()
	_root.show()


func close() -> void:
	if not is_open():
		return
	_root.hide()
	SimClock.set_paused(_was_paused)
	var focus := get_viewport().gui_get_focus_owner()
	if focus:
		focus.release_focus()


## Hides the menu without touching the clock (a load or new game sets it).
func dismiss() -> void:
	_root.hide()


func _unhandled_input(event: InputEvent) -> void:
	if not SaveManager.in_game():
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		if is_open() and _loads.visible:
			_show_main()
		elif is_open():
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


## A short message at the top of the screen.
func toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	_toast.show()
	_toast_left = TOAST_TIME


func _process(delta: float) -> void:
	if _toast_left <= 0.0:
		return
	_toast_left -= delta
	_toast.modulate.a = clampf(_toast_left / 0.5, 0.0, 1.0)
	if _toast_left <= 0.0:
		_toast.hide()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	if ResourceLoader.exists(THEME_PATH):
		_root.theme = load(THEME_PATH)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.02, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)

	var stack := VBoxContainer.new()
	margin.add_child(stack)

	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 10)
	stack.add_child(_main)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.55, 0.15))
	title.add_theme_font_size_override("font_size", 22)
	_main.add_child(title)

	_main.add_child(_button("Resume", close))
	_main.add_child(_button("Save game", _save))
	_main.add_child(_button("Load game", _show_loads))
	_fullscreen_button = _button("Fullscreen", _toggle_fullscreen)
	_main.add_child(_fullscreen_button)
	_main.add_child(_button("Main menu", func() -> void: SaveManager.to_main_menu()))
	_main.add_child(_button("Quit to desktop", func() -> void: SaveManager.quit_game()))

	var hint := Label.new()
	hint.text = "Esc to resume. The game saves on quit."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.5)
	_main.add_child(hint)

	_loads = SaveList.new()
	_loads.back.connect(_show_main)
	stack.add_child(_loads)
	_loads.hide()
	UIUtil.no_focus(_root)


func _build_toast() -> void:
	_toast = Label.new()
	if ResourceLoader.exists(THEME_PATH):
		_toast.theme = load(THEME_PATH)
	_toast.theme_type_variation = &"HeaderLabel"
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 64.0
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.add_theme_color_override("font_color", Color(0.6, 1.0, 0.68))
	_toast.add_theme_font_size_override("font_size", 20)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.hide()
	add_child(_toast)


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(action)
	return b


func _save() -> void:
	var err := SaveManager.save_game()
	toast("Game saved" if err.is_empty() else err)


func _show_main() -> void:
	_loads.hide()
	_main.show()


func _show_loads() -> void:
	_loads.playing_slot = SaveManager.current_slot
	_loads.refresh()
	_main.hide()
	_loads.show()


func _toggle_fullscreen() -> void:
	WindowMode.set_fullscreen(not WindowMode.is_fullscreen())
	_update_fullscreen_label.call_deferred()


func _update_fullscreen_label() -> void:
	_fullscreen_button.text = "Windowed" if WindowMode.is_fullscreen() else "Fullscreen"

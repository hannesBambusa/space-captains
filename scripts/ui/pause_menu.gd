extends CanvasLayer
## Autoload "PauseMenu". Esc opens it when nothing else used the key (placing a
## building and selections handle Esc first). Pauses the sim while open.

const THEME_PATH := "res://ui/theme.tres"

var _root: Control
var _fullscreen_button: Button
var _was_paused := false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.hide()


func is_open() -> bool:
	return _root.visible


func open() -> void:
	if is_open():
		return
	_was_paused = SimClock.paused
	SimClock.set_paused(true)
	_update_fullscreen_label()
	_root.show()


func close() -> void:
	if not is_open():
		return
	_root.hide()
	SimClock.set_paused(_was_paused)
	var focus := get_viewport().gui_get_focus_owner()
	if focus:
		focus.release_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		if is_open():
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


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

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.55, 0.15))
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)

	box.add_child(_button("Resume", close))
	_fullscreen_button = _button("Fullscreen", _toggle_fullscreen)
	box.add_child(_fullscreen_button)
	box.add_child(_button("Quit to desktop", func(): get_tree().quit()))

	var hint := Label.new()
	hint.text = "Esc to resume"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.5)
	box.add_child(hint)


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(action)
	return b


func _toggle_fullscreen() -> void:
	WindowMode.set_fullscreen(not WindowMode.is_fullscreen())
	_update_fullscreen_label.call_deferred()


func _update_fullscreen_label() -> void:
	_fullscreen_button.text = "Windowed" if WindowMode.is_fullscreen() else "Fullscreen"

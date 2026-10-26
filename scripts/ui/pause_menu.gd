extends CanvasLayer
## Autoload "PauseMenu". Esc opens it during a game when nothing else used the
## key (placing a building and selections handle Esc first). Pauses the sim
## while open. Save game writes the current slot, Load game lists the saves
## ([SaveList]), Main menu and Quit save first (SaveManager).
## Also shows short toasts ("Game saved") at the top of the screen, open or not:
## a banner with an icon, red and held longer for raid warnings, amber for
## long-range scans and new factions, green otherwise.

const THEME_PATH := "res://ui/theme.tres"
const TOAST_TIME := 2.2
## Raid and threat warnings stay up longer.
const ALERT_TIME := 5.0

var _root: Control
var _main: VBoxContainer
var _loads: SaveList
var _fullscreen_button: Button
var _was_paused := false
var _toast: PanelContainer
var _toast_label: Label
var _toast_icon: TextureRect
var _toast_style: ChamferBox
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


## A short message at the top of the screen. The look follows the text:
## raids and attacks are alerts, scans and new factions warnings.
func toast(text: String) -> void:
	var low := text.to_lower()
	var color := HudStyle.GOOD
	var icon_name := &"feed_reward"
	var hold := TOAST_TIME
	if low.contains("raid") or low.contains("under attack"):
		color = HudStyle.BAD
		icon_name = &"feed_threat"
		hold = ALERT_TIME
	elif low.contains("long-range") or low.contains("faction") or low.contains("scan"):
		color = HudStyle.WARN
		icon_name = &"warning"
		hold = ALERT_TIME
	elif low.contains("fail") or low.contains("error") or low.contains("could not"):
		color = HudStyle.BAD
		icon_name = &"feed_loss"
	_toast_label.text = text
	_toast_label.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.6))
	_toast_icon.texture = HudStyle.icon(icon_name)
	_toast_icon.modulate = color
	_toast_style.accent_color = color
	_toast_style.border_color = Color(color, 0.45)
	_toast.modulate.a = 1.0
	_toast.show()
	_toast.reset_size()
	_toast_left = hold


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
	dim.color = Color(HudStyle.VOID, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.theme_type_variation = &"MenuPanel"
	panel.custom_minimum_size = Vector2(380, 0)
	center.add_child(panel)

	var stack := VBoxContainer.new()
	panel.add_child(stack)

	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 10)
	stack.add_child(_main)

	var kicker := UIUtil.label("OPERATIONS SUSPENDED", &"HeaderLabel")
	_main.add_child(kicker)
	var title := UIUtil.label("PAUSED", &"TitleLabel")
	title.add_theme_font_size_override("font_size", 34)
	_main.add_child(title)
	_main.add_child(HSeparator.new())

	_main.add_child(_button("Resume", close))
	_main.add_child(_button("Save game", _save))
	_main.add_child(_button("Load game", _show_loads))
	_fullscreen_button = _button("Fullscreen", _toggle_fullscreen)
	_main.add_child(_fullscreen_button)
	_main.add_child(_button("Main menu", func() -> void: SaveManager.to_main_menu()))
	_main.add_child(_button("Quit to desktop", func() -> void: SaveManager.quit_game()))

	_main.add_child(HSeparator.new())
	var hint := UIUtil.label("Esc to resume. The game saves on quit.", &"SmallLabel")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main.add_child(hint)

	_loads = SaveList.new()
	_loads.back.connect(_show_main)
	stack.add_child(_loads)
	_loads.hide()
	UIUtil.no_focus(_root)


func _build_toast() -> void:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(THEME_PATH):
		holder.theme = load(THEME_PATH)
	add_child(holder)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	center.offset_top = 60.0
	center.offset_bottom = 110.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(center)
	_toast = PanelContainer.new()
	_toast.theme_type_variation = &"ToastPanel"
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_toast)
	# Own copy of the style: the accent follows the toast kind.
	var base := holder.theme.get_stylebox(&"panel", &"ToastPanel") if holder.theme else null
	_toast_style = (base.duplicate() as ChamferBox) if base is ChamferBox else ChamferBox.new()
	_toast.add_theme_stylebox_override("panel", _toast_style)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	_toast.add_child(h)
	_toast_icon = HudStyle.icon_rect(&"feed_reward", 20.0)
	h.add_child(_toast_icon)
	_toast_label = UIUtil.label("", &"HeaderLabel")
	_toast_label.add_theme_font_size_override("font_size", 19)
	h.add_child(_toast_label)
	_toast.hide()


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.theme_type_variation = &"MainMenuButton"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 46)
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
	_fullscreen_button.text = "WINDOWED" if WindowMode.is_fullscreen() else "FULLSCREEN"

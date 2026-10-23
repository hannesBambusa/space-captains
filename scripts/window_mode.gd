extends Node
## Autoload "WindowMode". Fullscreen toggle: F11, Alt+Enter, or Cmd+Ctrl+F on macOS.
## Exported builds start fullscreen. Editor/dev runs remember the last choice in
## user://settings.cfg. Command line: --fullscreen / --windowed.

const SETTINGS_PATH := "user://settings.cfg"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		return
	var args := OS.get_cmdline_user_args() + OS.get_cmdline_args()
	if args.has("--fullscreen"):
		set_fullscreen(true, false)
	elif args.has("--windowed"):
		set_fullscreen(false, false)
	elif OS.has_feature("template"):
		# Exported builds always start fullscreen.
		set_fullscreen(true, false)
	else:
		var cfg := ConfigFile.new()
		if cfg.load(SETTINGS_PATH) == OK and cfg.get_value("display", "fullscreen", false):
			set_fullscreen(true, false)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var toggle := key.keycode == KEY_F11 \
			or (key.keycode == KEY_ENTER and key.alt_pressed) \
			or (key.keycode == KEY_F and key.meta_pressed and key.ctrl_pressed)
	if toggle:
		set_fullscreen(not is_fullscreen())
		get_viewport().set_input_as_handled()


func is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func set_fullscreen(on: bool, remember: bool = true) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	if remember:
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS_PATH)
		cfg.set_value("display", "fullscreen", on)
		cfg.save(SETTINGS_PATH)

class_name VolumeSliders
extends GridContainer
## Music / SFX / UI volume sliders ([AudioSettings]). Dragging sets the bus
## at once; letting go saves to user://settings.cfg. Used by the pause menu
## and the main menu's settings page.

const LABEL_WIDTH := 90.0

var _sliders: Dictionary = {}


func _ready() -> void:
	columns = 3
	add_theme_constant_override("h_separation", 12)
	for bus in AudioSettings.BUSES:
		var name_label := UIUtil.label(String(bus).to_upper(), &"SmallLabel")
		name_label.custom_minimum_size.x = LABEL_WIDTH
		add_child(name_label)
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.01
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.custom_minimum_size = Vector2(180, 24)
		s.focus_mode = Control.FOCUS_NONE
		add_child(s)
		var pct := UIUtil.label("", &"SmallLabel")
		pct.custom_minimum_size.x = 44.0
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		add_child(pct)
		s.value_changed.connect(func(v: float) -> void:
			AudioSettings.set_volume(bus, v)
			pct.text = "%d%%" % roundi(v * 100.0))
		s.drag_ended.connect(func(_changed: bool) -> void:
			AudioSettings.set_volume(bus, s.value, true)
			# A sample at the new level.
			if bus == &"UI":
				Sfx.ui(&"ui_click")
			elif bus == &"SFX":
				Sfx.ui(&"build_placed"))
		_sliders[bus] = s
	visibility_changed.connect(refresh)
	refresh()


## Shows the current bus volumes.
func refresh() -> void:
	for bus: StringName in _sliders:
		(_sliders[bus] as HSlider).set_value_no_signal(AudioSettings.volume(bus))
		(_sliders[bus] as HSlider).value_changed.emit(AudioSettings.volume(bus))

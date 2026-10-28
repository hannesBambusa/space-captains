class_name GraphicsOptions
extends VBoxContainer
## Graphics settings ([GraphicsSettings]) as two columns of "-" / "+"
## steppers and sliders: picture quality on the left, anti-aliasing and
## display on the right. Every change applies at once and saves to
## user://settings.cfg. Used by the main menu's settings page and the
## pause menu.

const TITLE_WIDTH := 150.0
const VALUE_WIDTH := 96.0
const COLUMN_WIDTH := 360.0
const FONT_SIZE := 16

## Stepper rows: key -> [[value, text], ...].
const CHOICES := {
	"msaa": [[0, "OFF"], [1, "2X"], [2, "4X"], [3, "8X"]],
	"screen_aa": [[0, "OFF"], [1, "FXAA"], [2, "SMAA"]],
	"taa": [[false, "OFF"], [true, "ON"]],
	"scaling": [[0, "BILINEAR"], [1, "FSR 1"], [2, "FSR 2"]],
	"shadows": [[0, "OFF"], [1, "LOW"], [2, "MEDIUM"], [3, "HIGH"]],
	"glow": [[false, "OFF"], [true, "ON"]],
	"ssao": [[false, "OFF"], [true, "ON"]],
	"aniso": [[0, "OFF"], [1, "2X"], [2, "4X"], [3, "8X"], [4, "16X"]],
	"vsync": [[0, "OFF"], [1, "ON"], [2, "ADAPTIVE"]],
	"fps_cap": [[30, "30"], [60, "60"], [120, "120"], [144, "144"], [0, "NONE"]],
	"show_fps": [[false, "OFF"], [true, "ON"]],
	"driver": [["default", "DEFAULT"], ["vulkan", "VULKAN"], ["d3d12", "D3D12"]],
}

## Stepper key -> value Label; slider key -> [HSlider, value Label].
var _steppers: Dictionary = {}
var _sliders: Dictionary = {}
## Row key -> the row's controls (dimmed when the option has no effect).
var _rows: Dictionary = {}
var _preset_label: Label
var _driver_note: Label


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var preset_row := _grid_row_box()
	add_child(preset_row)
	_preset_label = _stepper(preset_row, "preset", "PRESET", _step_preset)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	add_child(cols)
	var left := _column(cols, "QUALITY")
	_slider(left, "render_scale", "RENDER SCALE", 50.0, 200.0, 5.0)
	_choice(left, "scaling", "UPSCALER")
	_slider(left, "sharpness", "SHARPNESS", 0.0, 100.0, 5.0)
	_choice(left, "shadows", "SHADOWS")
	_choice(left, "glow", "GLOW")
	_choice(left, "ssao", "AMBIENT OCCL.")
	_choice(left, "aniso", "TEXTURE FILTER")
	var right := _column(cols, "ANTI-ALIASING")
	_choice(right, "msaa", "MSAA")
	_choice(right, "screen_aa", "SCREEN AA")
	_choice(right, "taa", "TAA")
	right.add_child(_header("DISPLAY"))
	_choice(right, "vsync", "VSYNC")
	_choice(right, "fps_cap", "FPS CAP")
	_choice(right, "show_fps", "FPS COUNTER")
	if GraphicsSettings.driver_choice_available():
		_choice(right, "driver", "RENDERER")
		_driver_note = _small("")
		right.add_child(_driver_note)
	var hint := _small("Upscaler and sharpness work below 100% render scale.")
	add_child(hint)
	UIUtil.no_focus(self)
	visibility_changed.connect(refresh)
	refresh()


## Shows the current values.
func refresh() -> void:
	var preset := String(GraphicsSettings.get_value("preset"))
	_preset_label.text = preset.to_upper()
	for key: String in _steppers:
		(_steppers[key] as Label).text = _text_of(key, GraphicsSettings.get_value(key))
	for key: String in _sliders:
		var s := _sliders[key][0] as HSlider
		var v := float(GraphicsSettings.get_value(key)) * 100.0
		s.set_value_no_signal(v)
		(_sliders[key][1] as Label).text = "%d%%" % roundi(v)
	_dim("scaling", float(GraphicsSettings.get_value("render_scale")) < 0.999)
	_dim("sharpness", GraphicsSettings.sharpness_used())
	_dim("taa", GraphicsSettings.effective_scaling() != 2)
	if _driver_note:
		var want := String(GraphicsSettings.get_value("driver"))
		var now := GraphicsSettings.running_driver()
		_driver_note.text = "Running %s. Restart to switch." % now.to_upper() \
				if want != "default" and want != now else "Running %s." % now.to_upper()


func _column(parent: Container, title: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = COLUMN_WIDTH
	col.add_theme_constant_override("separation", 6)
	parent.add_child(col)
	col.add_child(_header(title))
	return col


func _header(text: String) -> Label:
	var l := UIUtil.label(text, &"HeaderLabel")
	l.add_theme_font_size_override("font_size", FONT_SIZE)
	return l


func _small(text: String) -> Label:
	var l := UIUtil.label(text, &"SmallLabel")
	l.add_theme_font_size_override("font_size", FONT_SIZE - 2)
	return l


func _grid_row_box() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	return row


## "TITLE ... [-] VALUE [+]" into [param row]; returns the value label.
func _stepper(row: HBoxContainer, key: String, title: String, step: Callable) -> Label:
	var name_label := UIUtil.label(title, &"DimLabel")
	name_label.add_theme_font_size_override("font_size", FONT_SIZE)
	name_label.custom_minimum_size.x = TITLE_WIDTH
	row.add_child(name_label)
	row.add_child(UIUtil.spacer())
	var minus := UIUtil.step_button("-", "", Vector2(30, 28))
	minus.pressed.connect(step.bind(-1))
	row.add_child(minus)
	var value := UIUtil.label("", &"NumberLabel")
	value.add_theme_font_size_override("font_size", FONT_SIZE)
	value.custom_minimum_size.x = VALUE_WIDTH
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(value)
	var plus := UIUtil.step_button("+", "", Vector2(30, 28))
	plus.pressed.connect(step.bind(1))
	row.add_child(plus)
	_rows[key] = [name_label, minus, value, plus]
	return value


func _choice(col: VBoxContainer, key: String, title: String) -> void:
	var row := _grid_row_box()
	col.add_child(row)
	_steppers[key] = _stepper(row, key, title, _step_choice.bind(key))


func _slider(col: VBoxContainer, key: String, title: String, lo: float, hi: float, step: float) -> void:
	var row := _grid_row_box()
	col.add_child(row)
	var name_label := UIUtil.label(title, &"DimLabel")
	name_label.add_theme_font_size_override("font_size", FONT_SIZE)
	name_label.custom_minimum_size.x = TITLE_WIDTH
	row.add_child(name_label)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(120, 24)
	s.focus_mode = Control.FOCUS_NONE
	row.add_child(s)
	var pct := UIUtil.label("", &"NumberLabel")
	pct.add_theme_font_size_override("font_size", FONT_SIZE)
	pct.custom_minimum_size.x = 56.0
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(pct)
	s.value_changed.connect(func(v: float) -> void:
		pct.text = "%d%%" % roundi(v)
		GraphicsSettings.set_value(get_tree(), key, v / 100.0, false)
		_refresh_preset())
	s.drag_ended.connect(func(_changed: bool) -> void:
		GraphicsSettings.set_value(get_tree(), key, s.value / 100.0)
		refresh())
	_sliders[key] = [s, pct]
	_rows[key] = [name_label, s, pct]


func _step_choice(dir: int, key: String) -> void:
	var opts: Array = CHOICES[key]
	var i := _index_of(key, GraphicsSettings.get_value(key))
	i = clampi(i + dir, 0, opts.size() - 1)
	GraphicsSettings.set_value(get_tree(), key, opts[i][0])
	Sfx.ui(&"ui_click")
	refresh()


func _step_preset(dir: int) -> void:
	var presets := GraphicsSettings.PRESETS.slice(0, 4)
	var cur := String(GraphicsSettings.get_value("preset"))
	var i := presets.find(cur)
	if i < 0:
		# From custom: "-" goes to ultra's neighbour below, "+" to ultra.
		i = presets.size() - 1 if dir > 0 else presets.size() - 2
	else:
		i = clampi(i + dir, 0, presets.size() - 1)
	GraphicsSettings.set_preset(get_tree(), presets[i])
	Sfx.ui(&"ui_click")
	refresh()


func _refresh_preset() -> void:
	_preset_label.text = String(GraphicsSettings.get_value("preset")).to_upper()


func _index_of(key: String, value: Variant) -> int:
	var opts: Array = CHOICES[key]
	for i in opts.size():
		if opts[i][0] == value:
			return i
	return 0


func _text_of(key: String, value: Variant) -> String:
	return String(CHOICES[key][_index_of(key, value)][1])


## Dims a row whose option does nothing with the other settings.
func _dim(key: String, active: bool) -> void:
	if not _rows.has(key):
		return
	for c: Control in _rows[key]:
		c.modulate.a = 1.0 if active else 0.45

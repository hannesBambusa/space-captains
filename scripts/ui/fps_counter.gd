class_name FpsCounter
extends CanvasLayer
## Small FPS readout in the top right corner, just under the top bar.
## Added to the root by [GraphicsSettings] while "show_fps" is on.

const THEME_PATH := "res://ui/theme.tres"
const UPDATE_EVERY := 0.5

var _label: Label
var _left := 0.0


func _ready() -> void:
	layer = 99
	process_mode = Node.PROCESS_MODE_ALWAYS
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(THEME_PATH):
		holder.theme = load(THEME_PATH)
	add_child(holder)
	_label = UIUtil.label("", &"SmallLabel")
	_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_label.offset_left = -120.0
	_label.offset_right = -14.0
	_label.offset_top = 48.0
	_label.offset_bottom = 66.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_font_override("font", HudStyle.mono("Medium"))
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 4)
	holder.add_child(_label)


func _process(delta: float) -> void:
	_left -= delta
	if _left > 0.0:
		return
	_left = UPDATE_EVERY
	_label.text = "%d FPS" % roundi(Engine.get_frames_per_second())

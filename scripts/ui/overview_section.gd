class_name OverviewSection
extends VBoxContainer
## One section of the left panel ([OverviewPanel]): a header strip
## (collapse arrow, icon, title, a note such as "2 raiding", the count) over
## a body of rows. Click the header to fold the section. Folded sections are
## kept per id in user://settings.cfg ([overview] collapsed), so they stay
## folded across games.

signal toggled(section: OverviewSection)

const SETTINGS_PATH := "user://settings.cfg"

static var _folded: PackedStringArray = []
static var _loaded := false

var id: StringName
var body: VBoxContainer
var collapsed := false

var _header: Button
var _arrow: Control
var _title: Label
var _note: Label
var _count: Label


func _init(section_id: StringName, title: String, icon_name: StringName, font_size: int, header_height: float) -> void:
	id = section_id
	name = "Section_" + String(section_id)
	add_theme_constant_override("separation", 0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header = Button.new()
	_header.focus_mode = Control.FOCUS_NONE
	_header.custom_minimum_size.y = header_height
	_header.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_header.pressed.connect(func() -> void: set_collapsed(not collapsed, true))
	add_child(_header)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 6.0
	h.offset_right = -8.0
	h.add_theme_constant_override("separation", 6)
	_header.add_child(h)
	_arrow = Control.new()
	_arrow.custom_minimum_size = Vector2(9.0, 9.0)
	_arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_arrow.draw.connect(_draw_arrow)
	h.add_child(_arrow)
	h.add_child(HudStyle.icon_rect(icon_name, float(font_size), HudStyle.HOLO))
	_title = UIUtil.label(title, &"HeaderLabel")
	_title.add_theme_font_size_override("font_size", font_size)
	h.add_child(_title)
	h.add_child(UIUtil.spacer())
	_note = UIUtil.label("", &"SubHeaderLabel")
	_note.add_theme_font_size_override("font_size", font_size - 1)
	_note.visible = false
	h.add_child(_note)
	_count = UIUtil.label("", &"NumberLabel")
	_count.add_theme_font_size_override("font_size", font_size - 1)
	_count.add_theme_color_override("font_color", HudStyle.TEXT_DIM)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.custom_minimum_size.x = 18.0
	h.add_child(_count)
	UIUtil.ignore_mouse(_header)
	body = VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 0)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	_load()
	collapsed = _folded.has(String(id))
	body.visible = not collapsed


func _ready() -> void:
	var sb := get_theme_stylebox(&"panel", &"SectionPanel")
	var normal := sb.duplicate() as StyleBox
	var hover := sb.duplicate() as StyleBox
	if hover is ChamferBox:
		(hover as ChamferBox).bg_color = Color(HudStyle.HOLO, 0.1)
	for s: StringName in [&"normal", &"pressed", &"focus", &"disabled"]:
		_header.add_theme_stylebox_override(s, normal)
	_header.add_theme_stylebox_override(&"hover", hover)
	_header.add_theme_stylebox_override(&"hover_pressed", hover)
	_sync_tip()


## The count on the header ("" hides it).
func set_count(n: int) -> void:
	var s := str(n) if n >= 0 else ""
	if _count.text != s:
		_count.text = s


## A short note left of the count ("2 raiding"), in [param color]; "" hides it.
func set_note(text: String, color: Color = HudStyle.TEXT_DIM) -> void:
	_note.visible = not text.is_empty()
	if _note.text != text:
		_note.text = text
	_note.add_theme_color_override("font_color", color)


## Folds or opens the body; [param save] keeps it in the settings file.
func set_collapsed(on: bool, save: bool = false) -> void:
	if collapsed == on:
		return
	collapsed = on
	body.visible = not on
	_arrow.queue_redraw()
	_sync_tip()
	if save:
		_store(on)
	toggled.emit(self)


func _sync_tip() -> void:
	_header.tooltip_text = ("Show " if collapsed else "Hide ") + _title.text.to_lower()


func _draw_arrow() -> void:
	var s := _arrow.size
	var pts: PackedVector2Array
	if collapsed:
		pts = [Vector2(1.5, 0.0), Vector2(s.x - 1.0, s.y * 0.5), Vector2(1.5, s.y)]
	else:
		pts = [Vector2(0.0, 1.5), Vector2(s.x, 1.5), Vector2(s.x * 0.5, s.y - 1.0)]
	_arrow.draw_colored_polygon(pts, HudStyle.HOLO if not collapsed else HudStyle.TEXT_DIM)


# --- Settings -----------------------------------------------------------------

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	var v: Variant = cfg.get_value("overview", "collapsed", PackedStringArray())
	if v is PackedStringArray:
		_folded = v
	elif v is Array:
		_folded = PackedStringArray(v)


func _store(on: bool) -> void:
	var key := String(id)
	if on and not _folded.has(key):
		_folded.append(key)
	elif not on:
		var i := _folded.find(key)
		if i >= 0:
			_folded.remove_at(i)
	var cfg := ConfigFile.new()
	# A missing or broken file starts empty; other settings in it are kept.
	cfg.load(SETTINGS_PATH)
	cfg.set_value("overview", "collapsed", _folded)
	if cfg.save(SETTINGS_PATH) != OK:
		push_warning("OverviewSection: could not save %s" % SETTINGS_PATH)

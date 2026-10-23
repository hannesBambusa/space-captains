class_name EventFeed
extends VBoxContainer
## Compact event feed, bottom-left: the last few EventLog lines, newest at
## the bottom, each fading out after [member hold_time] seconds. Click an
## entry: the camera flies to the ship or place it is about (and selects the
## ship when it still exists).

const KIND_COLORS: Array[Color] = [
	Color(0.78, 0.84, 0.92), Color(1.0, 0.72, 0.4), Color(1.0, 0.42, 0.36), Color(1.0, 0.36, 0.3), Color(0.6, 1.0, 0.68),
]
const KIND_TAGS: PackedStringArray = ["·", "!", "x", "!!", "+"]

@export var max_visible: int = 5
## Seconds an entry stays before it starts to fade.
@export var hold_time: float = 10.0
@export var fade_time: float = 2.0
@export var feed_width: float = 440.0

var hud: HUD
## Per entry: {button, born (msec), entry}
var _items: Array[Dictionary] = []
var _anchor: Node3D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 2)
	custom_minimum_size.x = feed_width


func setup(owner_hud: HUD) -> void:
	hud = owner_hud
	EventLog.posted.connect(_on_posted)
	_anchor = Node3D.new()
	_anchor.name = "EventFeedAnchor"
	_anchor.set_meta(&"focus_radius", 80.0)
	_anchor.set_meta(&"focus_distance", 700.0)
	hud.add_child.call_deferred(_anchor)


func entry_count() -> int:
	return _items.size()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var i := _items.size() - 1
	while i >= 0:
		var it := _items[i]
		var age := float(now - int(it["born"])) / 1000.0
		var b := it["button"] as Button
		var a := 1.0 - clampf((age - hold_time) / fade_time, 0.0, 1.0)
		if b.is_hovered():
			it["born"] = now - int(hold_time * 500.0)
			a = 1.0
		b.modulate.a = a
		if a <= 0.0:
			b.queue_free()
			_items.remove_at(i)
		i -= 1


func _on_posted(e: Dictionary) -> void:
	var kind: int = e["kind"]
	var b := UIUtil.button("", &"RowButton")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(feed_width, 22.0)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 8.0
	h.add_theme_constant_override("separation", 8)
	b.add_child(h)
	var t := int(float(e["time"]))
	var clock := UIUtil.label("%02d:%02d" % [floori(t / 60.0) % 60, t % 60], &"DimLabel")
	h.add_child(clock)
	var tag := UIUtil.label(KIND_TAGS[kind], &"ValueLabel")
	tag.add_theme_color_override("font_color", KIND_COLORS[kind])
	tag.custom_minimum_size.x = 14.0
	h.add_child(tag)
	var l := UIUtil.label(String(e["text"]))
	l.add_theme_color_override("font_color", KIND_COLORS[kind].lerp(Color.WHITE, 0.35))
	l.add_theme_font_size_override("font_size", 14)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	UIUtil.ignore_mouse(b)
	b.tooltip_text = String(e["text"])
	b.pressed.connect(_on_pressed.bind(e))
	add_child(b)
	_items.append({"button": b, "born": Time.get_ticks_msec(), "entry": e})
	while _items.size() > max_visible:
		(_items[0]["button"] as Button).queue_free()
		_items.remove_at(0)


func _on_pressed(e: Dictionary) -> void:
	if hud == null or hud.camera == null:
		return
	var n := entry_target(e)
	if n:
		hud.camera.focus_on(n)
		if hud.selection and (n is Ship or n is ScavengerDen or n is Building):
			hud.selection.select(n)
		return
	var p: Vector3 = e["position"]
	if p != Vector3.INF and is_instance_valid(_anchor):
		_anchor.global_position = Vector3(p.x, 0.0, p.z)
		hud.camera.focus_on(_anchor, 700.0)


## The entry's node when it still exists, else null.
static func entry_target(e: Dictionary) -> Node3D:
	var w := e.get("target") as WeakRef
	var n := w.get_ref() as Node3D if w else null
	return n if is_instance_valid(n) and n.is_inside_tree() else null

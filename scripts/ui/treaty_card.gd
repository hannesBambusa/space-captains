class_name TreatyCard
extends PanelContainer
## An offer from a rival corporation (RivalCorp.first_offer: peace, a trade
## pact, a tribute demand; with several rivals one card at a time), top
## centre under the top bar. It does not pause; it waits [constant RivalCorp.OFFER_MS] real time with a
## countdown, then counts as refused. Accept, Refuse, and Counter where the
## offer has one (peace: double reparations; tribute: half).

const H := preload("res://scripts/ui/theme/hud_style.gd")
const WIDTH := 520.0
const TOP := 64.0

var _text: Label
var _left: Label
var _counter: Button
var _shown := ""
var _rid: StringName = &""


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.x = WIDTH
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var t := UIUtil.label("OFFER", &"HeaderLabel")
	t.add_theme_color_override("font_color", H.CREDITS)
	top.add_child(t)
	top.add_child(UIUtil.spacer())
	_left = UIUtil.label("", &"NumberLabel")
	top.add_child(_left)
	_text = UIUtil.label("", &"")
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = WIDTH - 24.0
	v.add_child(_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	for k: String in ["accept", "counter", "reject"]:
		var b := UIUtil.button({"accept": "Accept", "counter": "Counter", "reject": "Refuse"}[k], &"ChipButton")
		b.custom_minimum_size = Vector2(90.0, 26.0)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(_answer.bind(k))
		row.add_child(b)
		if k == "counter":
			_counter = b


func _process(_delta: float) -> void:
	var rc := RivalCorp.of(get_tree())
	var fo := rc.first_offer() if rc else {}
	var o: Dictionary = fo.get("offer", {})
	_rid = StringName(fo.get("rid", ""))
	if o.is_empty():
		visible = false
		_shown = ""
		return
	visible = true
	var root := get_parent() as Control
	if root:
		position = Vector2(roundf((root.size.x - WIDTH) * 0.5), TOP + 8.0)
	var who := Corps.display_name(_rid)
	var text := "%s: %s" % [who, o["text"]]
	if text != _shown:
		_shown = text
		_text.text = text
		var kind := String(o["kind"])
		_counter.visible = kind == "peace" or kind == "tribute"
		_counter.tooltip_text = "Ask for double the reparations" if kind == "peace" else "Pay half and see if they take it"
	var left := maxi(int(o.get("until", 0)) - Time.get_ticks_msec(), 0)
	_left.text = "%d s" % ceili(left / 1000.0)


func _answer(choice: String) -> void:
	var rc := RivalCorp.of(get_tree())
	if rc and not _rid.is_empty():
		rc.answer_offer(_rid, choice)

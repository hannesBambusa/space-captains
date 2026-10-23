class_name TopBar
extends PanelContainer
## Compact top bar: credits, materials, sim time and speed/pause state.
## Deliveries flash a short "-credits / +materials" delta next to the values;
## income (station fees, the corporate grant) flashes a green "+credits"
## beside it. Deltas landing within one flash add up.

## Seconds a delta stays visible before it fades.
@export var flash_hold: float = 1.6
@export var flash_fade: float = 0.8

var _credits: Label
var _materials: Label
var _time: Label
var _speed: Label
var _speed_pips: PipMeter
var _credits_delta: Label
var _materials_delta: Label
var _income_delta: Label
var _tweens: Dictionary = {}
## Running sums while a delta is still showing: label -> int.
var _sums: Dictionary = {}


func _ready() -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	add_child(h)
	_credits = _add_stat(h, "CREDITS")
	_credits_delta = _add_delta(h, PipMeter.BAD)
	_income_delta = _add_delta(h, PipMeter.GOOD)
	_add_divider(h)
	_materials = _add_stat(h, "MATERIALS")
	_materials_delta = _add_delta(h, PipMeter.GOOD)
	_add_divider(h)
	_time = _add_stat(h, "SIM")
	_speed_pips = PipMeter.new()
	_speed_pips.style = PipMeter.Style.PIPS
	_speed_pips.max_value = 3.0
	_speed_pips.pip_size = 6.0
	_speed_pips.pip_gap = 2.0
	h.add_child(_speed_pips)
	_speed = UIUtil.label("", &"ValueLabel")
	_speed.custom_minimum_size.x = 52.0
	h.add_child(_speed)
	tooltip_text = "Space: pause    1 / 2 / 3: sim speed"
	Economy.changed.connect(_on_economy)
	ContractBoard.delivery_made.connect(_on_delivery)
	ContractBoard.payout_made.connect(func(_c: Contract, _s: Node, credits: int) -> void: _flash_sum(_credits_delta, -credits))
	Economy.income.connect(func(amount: int, source: String) -> void:
		_flash_sum(_income_delta, amount)
		_income_delta.tooltip_text = "Last income: %s" % source)
	SimClock.paused_changed.connect(func(_p: bool) -> void: _update_speed())
	SimClock.speed_changed.connect(func(_s: float) -> void: _update_speed())
	_on_economy(Economy.credits, Economy.materials)
	_update_speed()


func _process(_delta: float) -> void:
	var t := int(SimClock.time)
	var text := "%02d:%02d:%02d" % [floori(t / 3600.0), floori(t / 60.0) % 60, t % 60]
	if _time.text != text:
		_time.text = text


func _add_stat(parent: HBoxContainer, title: String) -> Label:
	parent.add_child(UIUtil.label(title, &"HeaderLabel"))
	var v := UIUtil.label("", &"ValueLabel")
	parent.add_child(v)
	return v


func _add_delta(parent: HBoxContainer, color: Color) -> Label:
	var l := UIUtil.label("", &"ValueLabel")
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 13)
	l.custom_minimum_size.x = 40.0
	l.modulate.a = 0.0
	parent.add_child(l)
	return l


## Shows a delta next to a value and fades it out.
func flash(label: Label, text: String) -> void:
	label.text = text
	var old := _tweens.get(label) as Tween
	if old and old.is_valid():
		old.kill()
	label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(flash_hold)
	tw.tween_property(label, "modulate:a", 0.0, flash_fade)
	_tweens[label] = tw


## Adds [param amount] to the delta shown on [param label] (or starts a new one).
func _flash_sum(label: Label, amount: int) -> void:
	if amount == 0:
		return
	var tw := _tweens.get(label) as Tween
	var sum: int = _sums.get(label, 0) if tw and tw.is_valid() and label.modulate.a > 0.05 else 0
	sum += amount
	_sums[label] = sum
	flash(label, ("+%s" if sum > 0 else "-%s") % UIUtil.amount(absi(sum)))


func _on_delivery(_contract: Contract, _ship: Node, credits: int, materials: int, _ore: int) -> void:
	if credits != 0:
		_flash_sum(_credits_delta, -credits)
	if materials != 0:
		_flash_sum(_materials_delta, materials)


func _add_divider(parent: HBoxContainer) -> void:
	var d := VSeparator.new()
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.add_theme_stylebox_override("separator", get_theme_stylebox("separator", "HSeparator"))
	parent.add_child(d)


func _on_economy(credits: int, materials: int) -> void:
	_credits.text = Economy.format_amount(credits)
	_materials.text = Economy.format_amount(materials)


func _update_speed() -> void:
	var idx := SimClock.SPEEDS.find(SimClock.speed)
	_speed_pips.value = 0.0 if SimClock.paused else float(idx + 1)
	if SimClock.paused:
		_speed.text = "PAUSED"
		_speed.add_theme_color_override("font_color", PipMeter.BAD)
	else:
		_speed.text = "%dx" % int(SimClock.speed) if SimClock.speed >= 1.0 else "%.2fx" % SimClock.speed
		_speed.remove_theme_color_override("font_color")

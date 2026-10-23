class_name DefenseSection
extends VBoxContainer
## Building panel section for the station defenses ([DefenseStructure]):
## hull and shields with the repair state and what repairs cost you, then
##   Defense Turret: target, kills, shots, a fire-at-will / hold-fire toggle;
##   Shield Generator: bubble HP, regen, state, radius.
## Refreshes a few times a second while shown.

const REFRESH := 0.25
const SHIELD_COLOR := Color(0.4, 0.78, 1.0)

@export var width: float = 356.0

var structure: DefenseStructure

var _header: Label
var _hull_bar: PipMeter
var _hull: Label
var _repair: Label
var _target: Label
var _kills: Label
var _fire_button: Button
var _bubble_bar: PipMeter
var _bubble: Label
var _bubble_info: Label
var _turret_box: VBoxContainer
var _shield_box: VBoxContainer
var _timer := 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	add_child(HSeparator.new())
	_header = UIUtil.label("", &"HeaderLabel")
	add_child(_header)
	var hh := HBoxContainer.new()
	hh.add_theme_constant_override("separation", 8)
	add_child(hh)
	_hull = UIUtil.label("", &"ValueLabel")
	_hull.custom_minimum_size.x = 210.0
	hh.add_child(_hull)
	_hull_bar = _bar(PipMeter.GOOD)
	hh.add_child(_hull_bar)
	_repair = _wrapped(&"DimLabel")
	add_child(_repair)

	_turret_box = VBoxContainer.new()
	_turret_box.add_theme_constant_override("separation", 4)
	add_child(_turret_box)
	_target = UIUtil.label("", &"ValueLabel")
	_target.clip_text = true
	_target.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_target.custom_minimum_size.x = width
	_turret_box.add_child(_target)
	_kills = UIUtil.label("", &"DimLabel")
	_turret_box.add_child(_kills)
	_fire_button = UIUtil.button("", &"AccentButton")
	_fire_button.toggle_mode = true
	_fire_button.toggled.connect(func(on: bool) -> void:
		var t := structure as DefenseTurret
		if t:
			t.set_fire_at_will(not on)
		_refresh())
	_turret_box.add_child(_fire_button)

	_shield_box = VBoxContainer.new()
	_shield_box.add_theme_constant_override("separation", 4)
	add_child(_shield_box)
	_shield_box.add_child(UIUtil.label("STATION SHIELD", &"HeaderLabel"))
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 8)
	_shield_box.add_child(bh)
	_bubble = UIUtil.label("", &"ValueLabel")
	_bubble.custom_minimum_size.x = 210.0
	bh.add_child(_bubble)
	_bubble_bar = _bar(SHIELD_COLOR)
	bh.add_child(_bubble_bar)
	_bubble_info = _wrapped(&"DimLabel")
	_shield_box.add_child(_bubble_info)


func show_structure(s: DefenseStructure) -> void:
	structure = s
	visible = s != null
	_refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH
		_refresh()


func _refresh() -> void:
	if not is_instance_valid(structure) or structure.durability == null:
		return
	var s := structure
	var d := s.durability
	_header.text = "DEFENSES"
	_hull.text = "Hull %d / %d   shields %d" % [roundi(d.hull), roundi(d.max_hull), roundi(d.shields)]
	_hull_bar.value = d.fraction()
	_hull_bar.color = PipMeter.GOOD if d.fraction() > 0.5 else (Color(1.0, 0.75, 0.3) if d.fraction() > 0.25 else PipMeter.BAD)
	var rate := d.max_hull * s.repair_rate
	if s.repairing:
		_repair.text = "Repairing %d hull/s, %s cr per 100 hull, paid by you (%d cr so far)." % [roundi(rate), _cost_text(), s.repair_total_paid]
	elif d.hull < d.max_hull:
		var why := "after %d s without a hit" % roundi(s.repair_delay) if d.seconds_since_hit() < s.repair_delay else "when you have credits"
		_repair.text = "Needs %d cr of repairs; the station repairs it %s." % [s.cost_to_repair(), why]
	else:
		_repair.text = "Hull intact. The station repairs damage for %s cr per 100 hull." % _cost_text()
	var t := s as DefenseTurret
	_turret_box.visible = t != null
	if t:
		_refresh_turret(t)
	var g := s as ShieldGenerator
	_shield_box.visible = g != null
	if g:
		_refresh_shield(g)


func _refresh_turret(t: DefenseTurret) -> void:
	if not t.is_active():
		_target.text = "Target: offline until built"
	elif Combat.is_live_target(t.target):
		var dist := Combat.flat_distance(t.global_position, t.target.global_position)
		_target.text = "Target: %s, %d m  (%s)" % [String(t.target.call(&"get_display_name")), roundi(dist), DefenseTurret.MODE_NAMES[t.mode].to_lower()]
	else:
		_target.text = "Target: none in range (%d m)" % roundi(t.weapon_range)
	_kills.text = "Kills %d   shots %d   %d dmg x %.1f/s" % [t.kills, t.shots_fired, roundi(t.weapon_damage), t.fire_rate]
	_fire_button.set_pressed_no_signal(not t.fire_at_will)
	_fire_button.text = "Holding fire (click: fire at will)" if not t.fire_at_will else "Fire at will (click: hold fire)"
	_fire_button.tooltip_text = "Hold fire: the turret tracks targets but does not shoot."


func _refresh_shield(g: ShieldGenerator) -> void:
	var b := g.shield
	if not is_instance_valid(b):
		_bubble.text = "No bubble"
		_bubble_bar.value = 0.0
		_bubble_info.text = ""
		return
	_bubble_bar.value = b.charge()
	_bubble_bar.color = SHIELD_COLOR if b.charge() > 0.25 else PipMeter.BAD
	match b.state:
		StationShield.State.OFFLINE:
			_bubble.text = "Offline"
		StationShield.State.DOWN:
			_bubble.text = "DOWN, re-raising in %d s" % ceili(b.cooldown_left)
		StationShield.State.COLLAPSING:
			_bubble.text = "Collapsing"
		_:
			_bubble.text = "%s  %d / %d HP" % [b.get_state_name(), roundi(b.hp), roundi(b.max_hp)]
	var regen := "regenerating %d HP/s" % roundi(b.regen) if b.is_regenerating() else "regenerates %d HP/s after %d s without hits" % [roundi(b.regen), roundi(b.regen_delay)]
	_bubble_info.text = "Radius %d m. %s. Broken, it re-raises after %d s at %d%%. Hits taken %d." % [
			roundi(b.radius), regen[0].to_upper() + regen.substr(1), roundi(b.cooldown), roundi(b.restore_fraction * 100.0), b.hits_taken]


func _cost_text() -> String:
	return "%.0f" % (DefenseStructure.REPAIR_COST_PER_HULL * 100.0)


func _bar(c: Color) -> PipMeter:
	var bar := PipMeter.new()
	bar.style = PipMeter.Style.BAR
	bar.max_value = 1.0
	bar.color = c
	bar.custom_minimum_size = Vector2(110.0, 6.0)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return bar


func _wrapped(variation: StringName) -> Label:
	var l := UIUtil.label("", variation)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	return l

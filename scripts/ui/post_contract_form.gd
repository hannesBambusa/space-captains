class_name PostContractForm
extends VBoxContainer
## The "post a per-load contract" form of the cluster and planet panels
## (BeltPanel, PlanetPanel): a header, the pay per load stepper (Shift: 5
## steps) with the fair pay line under it, the load limit stepper, the post
## button and its hint. [member rules] is a MiningRules or PlanetRaidRules
## (reward_min, reward_max, reward_step, load_limit_options, clamp_reward).
## The owner fills [member fair] and adds to [member hint] after
## [method refresh], then calls [method set_problem]; rows of its own go in
## before the button ([method add_row]). [method single_payment] turns it
## into a one-off reward form (explore contracts: no load limit, "Reward").

## A stepper moved or the credits changed: the owner refreshes.
signal changed
signal post_pressed

var rules: Variant
var reward: int = 0
var load_limit_index: int = 0
## The fair pay line, set by the owner.
var fair: Label
var hint: Label
var post: Button

var _reward_value: Label
var _reward_minus: Button
var _reward_plus: Button
var _limit_value: Label
var _limit_minus: Button
var _limit_plus: Button
var _single := false


func _init(header: String, post_text: String, form_rules: Variant, width: float) -> void:
	rules = form_rules
	add_theme_constant_override("separation", 6)
	add_child(UIUtil.label(header, &"HeaderLabel"))
	var r := UIUtil.stepper_row(self, "Pay per load", _step_reward, "Lower the pay (Shift: 50)", "Raise the pay (Shift: 50)")
	_reward_value = r[0]
	_reward_minus = r[1]
	_reward_plus = r[2]
	fair = _wrapped(width)
	add_child(fair)
	var l := UIUtil.stepper_row(self, "Load limit", _step_limit, "Fewer loads", "More loads")
	_limit_value = l[0]
	_limit_minus = l[1]
	_limit_plus = l[2]
	Economy.changed.connect(func(_c: int, _m: int) -> void:
		if is_visible_in_tree():
			changed.emit())
	post = UIUtil.button(post_text, &"AccentButton")
	post.pressed.connect(post_pressed.emit)
	add_child(post)
	hint = _wrapped(width)
	add_child(hint)


## "generous", "above fair", "fair", "below fair" or "low" for
## [param pay] against [param fair_pay].
static func fair_verdict(pay: int, fair_pay: int) -> String:
	if pay >= fair_pay * 1.6:
		return "generous"
	if pay > fair_pay:
		return "above fair"
	if pay < fair_pay * 0.7:
		return "low"
	if pay < fair_pay:
		return "below fair"
	return "fair"


## One reward instead of pay per load: the load limit row goes, the pay
## row reads [param pay_title], [method refresh] leaves the hint to the owner.
func single_payment(pay_title: String) -> void:
	_single = true
	_limit_value.get_parent().visible = false
	var title := _reward_value.get_parent().get_child(0) as Label
	if title:
		title.text = pay_title


## Adds [param c] above the post button.
func add_row(c: Control) -> void:
	add_child(c)
	move_child(c, post.get_index())


## The load limit picked (0 = none).
func load_limit() -> int:
	if _single:
		return 0
	return rules.load_limit_options[load_limit_index]


func set_reward(value: int) -> void:
	reward = rules.clamp_reward(value)
	changed.emit()


## The steppers and the base hint ("Paid on delivery, ...").
func refresh() -> void:
	_reward_value.text = "%d cr" % reward
	_reward_minus.disabled = reward <= rules.reward_min
	_reward_plus.disabled = reward >= rules.reward_max
	if _single:
		hint.text = ""
		return
	var limit := load_limit()
	_limit_value.text = "No limit" if limit <= 0 else "%d loads" % limit
	_limit_minus.disabled = load_limit_index <= 0
	_limit_plus.disabled = load_limit_index >= rules.load_limit_options.size() - 1
	var max_cost := "" if limit <= 0 else " Up to %s cr in total." % Economy.format_amount(limit * reward)
	hint.text = "Paid on delivery, %d cr per load.%s" % [reward, max_cost]


## [param why] ("" = can post) disables the button and replaces the hint.
func set_problem(why: String) -> void:
	post.disabled = not why.is_empty()
	post.tooltip_text = why
	if not why.is_empty():
		hint.text = why + "."


func _step_reward(dir: int) -> void:
	set_reward(reward + dir * rules.reward_step * (5 if Input.is_key_pressed(KEY_SHIFT) else 1))


func _step_limit(dir: int) -> void:
	var n: int = rules.load_limit_options.size()
	load_limit_index = clampi(load_limit_index + dir, 0, n - 1)
	changed.emit()


func _wrapped(width: float) -> Label:
	var l := UIUtil.label("", &"DimLabel")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width - 24.0
	return l

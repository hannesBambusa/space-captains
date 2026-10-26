class_name GatePanel
extends PanelContainer
## Bottom-right panel for the selected jump gate (P3): where it leads, how
## many jumps that is from home, the danger ("?" with a depth hint while
## nobody has charted it, else "3 of 5, seen 12 min ago"), what the last
## survey found there, the explore contracts on it (with cancel) and the
## "Post explore contract" form (PostContractForm in single payment mode:
## the reward, reserved now and paid once when the explorer brings the
## survey home, the fair pay by depth, the gate to leave by, and the note
## that a survey earns nothing by itself). Gates in a remote system can
## take one while that system is charted.

@export var panel_width: float = 380.0

var hud: HUD
var gate: JumpGate

var _title: Label
var _leads: Label
var _depth: Label
var _danger: Label
var _seen: Label
var _found: Label
var _contracts_header: Label
var _contracts: VBoxContainer
var _form: PostContractForm
var _exit: Button
var _exit_index := 0
var _refresh_timer := 0.0


## Pay range of the form (PostContractForm reads these).
class Rules extends RefCounted:
	var reward_min := 100
	var reward_max := 3000
	var reward_step := 25
	var load_limit_options: Array[int] = [0]

	func clamp_reward(v: int) -> int:
		return clampi(roundi(float(v) / reward_step) * reward_step, reward_min, reward_max)


func _ready() -> void:
	custom_minimum_size.x = panel_width
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	top.add_child(UIUtil.label("JUMP GATE", &"HeaderLabel"))
	top.add_child(UIUtil.spacer())
	var close := UIUtil.button("x", &"IconButton")
	close.custom_minimum_size = Vector2(26.0, 22.0)
	close.tooltip_text = "Deselect (Esc)"
	close.pressed.connect(func() -> void:
		if hud and hud.selection:
			hud.selection.deselect())
	top.add_child(close)
	_title = UIUtil.label("", &"TitleLabel")
	v.add_child(_title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	_leads = _grid_row(grid, "Leads to")
	_depth = _grid_row(grid, "From home")
	_danger = _grid_row(grid, "Danger")
	_seen = _grid_row(grid, "Survey")
	_found = UIUtil.label("", &"DimLabel")
	_found.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_found.custom_minimum_size.x = panel_width - 24.0
	v.add_child(_found)

	v.add_child(HSeparator.new())
	_contracts_header = UIUtil.label("CONTRACTS", &"HeaderLabel")
	v.add_child(_contracts_header)
	_contracts = VBoxContainer.new()
	_contracts.add_theme_constant_override("separation", 1)
	v.add_child(_contracts)

	v.add_child(HSeparator.new())
	_form = PostContractForm.new("POST EXPLORE CONTRACT", "Post explore contract", Rules.new(), panel_width)
	_form.single_payment("Reward")
	_form.changed.connect(_refresh_form)
	_form.post_pressed.connect(_on_post)
	var row := HBoxContainer.new()
	row.add_child(UIUtil.label("Leave by", &"DimLabel"))
	row.add_child(UIUtil.spacer())
	_exit = UIUtil.button("", &"")
	_exit.tooltip_text = "The gate the explorer leaves the system by once the survey is done (click to change)."
	_exit.pressed.connect(func() -> void:
		_exit_index += 1
		_refresh_form())
	row.add_child(_exit)
	_form.add_row(row)
	v.add_child(_form)


func _grid_row(grid: GridContainer, title: String) -> Label:
	grid.add_child(UIUtil.label(title, &"DimLabel"))
	var l := UIUtil.label("", &"ValueLabel")
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(l)
	return l


func setup(owner_hud: HUD) -> void:
	hud = owner_hud
	if hud.selection:
		hud.selection.selection_changed.connect(func(t: Node3D) -> void: show_gate(t as JumpGate))
	ContractBoard.contract_posted.connect(func(_c: Contract) -> void:
		_rebuild_contracts()
		_refresh_form())
	ContractBoard.contract_removed.connect(func(_c: Contract) -> void:
		_rebuild_contracts()
		_refresh_form())
	Sector.surveyed.connect(func(_id: StringName) -> void: _refresh_info())


## The system this gate is in and the one behind it.
func from_id() -> StringName:
	var w := SystemWorld.of(gate) if gate else null
	return w.system_id if w else ClusterNetwork.HOME_ID


func target_id() -> StringName:
	if gate == null or gate.def == null or Sector.network == null:
		return &""
	return Sector.network.gate_target(from_id(), gate.def.name).get("system", &"")


func show_gate(g: JumpGate) -> void:
	var changed := g != gate
	gate = g
	visible = g != null
	if g == null:
		return
	if changed:
		_form.reward = fair_reward()
		_exit_index = 0
	_title.text = g.def.name
	_refresh_info()
	_rebuild_contracts()
	_refresh_form()


func fair_reward() -> int:
	var to := target_id()
	if to.is_empty() or to == ClusterNetwork.HOME_ID:
		return 300
	return ExploreContract.fair_for(maxi(Sector.network.depth(to), 1), ExploreContract.danger_guess(to))


func get_post_button() -> Button:
	return _form.post


func set_reward(value: int) -> void:
	_form.set_reward(value)


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 0.5
		_refresh_info()
		for c in _contracts.get_children():
			if c is ContractRow:
				(c as ContractRow).refresh()


func _refresh_info() -> void:
	if gate == null or not is_instance_valid(gate):
		return
	var to := target_id()
	var def := Sector.system_def(to) if not to.is_empty() else null
	_leads.text = gate.def.target_system if def == null else def.system_name
	if to == ClusterNetwork.HOME_ID:
		_depth.text = "Home"
		_danger.text = "-"
		_seen.text = "Your home system"
		_found.text = ""
		return
	var e := Sector.network.entry(to) if Sector.network and not to.is_empty() else null
	var st := Sector.state(to)
	_depth.text = "%d jump%s" % [e.depth, "" if e.depth == 1 else "s"] if e else "?"
	if st and st.known:
		_danger.text = "%d of 5" % e.danger
		var seen := Sector.seen_text(to)
		_seen.text = seen.left(1).to_upper() + seen.substr(1)
		_found.text = "Charted: %s." % Survey.tally_text(to)
	else:
		_danger.text = "? (uncharted, %d jump%s out)" % [e.depth, "" if e.depth == 1 else "s"] if e else "?"
		_danger.tooltip_text = "Nobody knows yet. Deeper systems are usually rougher: about danger %d this far out." % ExploreContract.danger_guess(to) if e else ""
		_seen.text = "Never surveyed"
		_found.text = "Nobody has charted %s yet: you see nothing of it until an explorer has been there." % _leads.text
		if st and not st.revealed.is_empty():
			_found.text = "Partly charted so far: %s." % Survey.tally_text(to)


## Explore contracts on this gate (by name: the contract outlives the node).
func _gate_contracts() -> Array[Contract]:
	var out: Array[Contract] = []
	if gate == null:
		return out
	var from := from_id()
	for c in ContractBoard.contracts:
		var ec := c as ExploreContract
		if ec and ec.from_system == from and ec.gate_name == gate.def.name:
			out.append(c)
	return out


func _rebuild_contracts() -> void:
	if gate == null:
		return
	for c in _contracts.get_children():
		_contracts.remove_child(c)
		c.queue_free()
	var list := _gate_contracts()
	_contracts_header.text = "CONTRACTS  %d" % list.size()
	if list.is_empty():
		_contracts.add_child(UIUtil.label("None posted. Explorers only go through a gate on contract.", &"DimLabel"))
		return
	for c in list:
		_contracts.add_child(ContractRow.new(c, hud, false))


## Gates of the target to leave by: "" (the way in) first.
func _exit_options() -> PackedStringArray:
	var out := PackedStringArray([""])
	var def := Sector.system_def(target_id())
	if def == null:
		return out
	var back := Sector.gate_between(target_id(), from_id())
	for g in def.gates:
		if g.name != back:
			out.append(g.name)
	return out


func _exit_gate() -> String:
	var opts := _exit_options()
	return opts[_exit_index % opts.size()]


## "Unknown gate", numbered when the target has more than one.
func _unknown_gate_label(ex: String) -> String:
	var hidden := PackedStringArray()
	for g in _exit_options():
		if not g.is_empty() and not Sector.is_revealed(target_id(), g):
			hidden.append(g)
	return "Unknown gate" if hidden.size() <= 1 else "Unknown gate %d" % (hidden.find(ex) + 1)


func _outpost_problem() -> String:
	var mgr := hud.manager if hud else null
	var def := mgr.def_by_id(&"explorer_outpost") if mgr else null
	if def == null or mgr.count_of(def) == 0:
		if not Research.is_building_unlocked(&"explorer_outpost"):
			return "No explorers yet: research Jump navigation, then build an Explorer Outpost and hire explorers."
		return "No explorers yet: build an Explorer Outpost and hire explorers there."
	for b in mgr.buildings:
		if is_instance_valid(b) and b.def == def and not b.captains.is_empty():
			return ""
	return "No explorers yet: hire some at the Explorer Outpost."


func _refresh_form() -> void:
	if gate == null:
		return
	var reward := _form.reward
	_form.refresh()
	var to := target_id()
	var fair := fair_reward()
	var e := Sector.network.entry(to) if Sector.network and not to.is_empty() else null
	_form.fair.text = "Fair pay for a survey %d jump%s out is about %d cr (%s). Bold pilots like the uncharted, cautious ones stay near home." % [
			e.depth if e else 1, "" if e and e.depth == 1 else "s", fair, PostContractForm.fair_verdict(reward, fair)]
	var ex := _exit_gate()
	# Gates nobody has charted yet keep their names to themselves.
	_exit.text = "The way in" if ex.is_empty() else (ex if Sector.is_revealed(target_id(), ex) else _unknown_gate_label(ex))
	_form.hint.text = "Reserved from your credits now (%s cr), paid once when the explorer brings the survey home. A survey earns nothing by itself: it charts %s for later." % [
			UIUtil.amount(reward), _leads.text]
	var outpost := _outpost_problem()
	if not outpost.is_empty():
		_form.hint.text += " " + outpost
	var why := ContractBoard.explore_problem(from_id(), gate.def.name)
	if why.is_empty():
		why = ContractBoard.post_problem(reward, true)
	_form.set_problem(why)


func _on_post() -> void:
	if gate == null:
		return
	ContractBoard.post_explore(from_id(), gate.def.name, _form.reward, _exit_gate())
	_refresh_form()

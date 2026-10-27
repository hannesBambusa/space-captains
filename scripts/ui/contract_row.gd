class_name ContractRow
extends OverviewRow
## One posted contract in a list: type and target (or just the reward when
## the list is already about one target), reward, takers (or the bounty's
## fleet, "Fleet of 3 forming", or its lone wolf) and progress, "paused,
## station can't pay" while the credits do not cover one payment, and a
## cancel button (its tooltip says what a bounty's escrow does: all back
## while nobody has taken it, half back and half to the takers once taken). Click = camera flies to the contract beacon and the target
## is selected (the view switches to its system first). Outside home the
## target is tagged with its system ("[Ostra] Flint Cluster").

var contract: Contract
var hud: HUD
var _cancel: Button


func _init(c: Contract, owner_hud: HUD, show_target: bool = true) -> void:
	super(_focus_target(c, owner_hud), _title_for(c, show_target), "", 0)
	contract = c
	hud = owner_hud
	toggle_mode = false
	title_label.size_flags_stretch_ratio = 0.85
	_cancel = UIUtil.button("x", &"IconButton")
	_cancel.custom_minimum_size = Vector2(22.0, 18.0)
	_cancel.tooltip_text = "Cancel this contract. Trips already under way are still paid."
	_cancel.mouse_filter = Control.MOUSE_FILTER_STOP
	_cancel.pressed.connect(func() -> void: ContractBoard.cancel(contract))
	right_box.add_child(_cancel)
	right_box.visible = true
	pressed.connect(_on_pressed)
	hovered.connect(func(r: OverviewRow, on: bool) -> void:
		if hud and hud.marker:
			hud.marker.hover_target = r.target if on else null)
	refresh()


func refresh() -> void:
	if contract == null:
		return
	var parts: PackedStringArray = []
	if subtitle_has_reward():
		parts.append(contract.get_reward_text())
	var n := contract.takers.size()
	var team := contract.get_activity_text()
	if not team.is_empty():
		parts.append(team)
	else:
		parts.append("%d on it" % n if n > 0 else contract.get_status_name().to_lower())
	if n > 0 and contract.is_paused():
		parts.append("paused, station can't pay")
	var warn := contract.get_warning_text()
	if not warn.is_empty():
		parts.append(warn)
	var prog := contract.get_progress_text()
	if not prog.is_empty() and not subtitle_has_reward():
		parts.append(prog)
	set_subtitle("  ·  ".join(parts))
	tooltip_text = "%s\n%s\nPosted at %s\nPaid out: %s cr" % [contract.get_title(), contract.get_reward_text(), _clock(contract.created_time), Economy.format_amount(contract.credits_paid)]
	if contract is BountyContract:
		tooltip_text += "\nReserved: %s cr" % Economy.format_amount((contract as BountyContract).escrow)
	elif contract is ExploreContract:
		tooltip_text += "\nReserved: %s cr" % Economy.format_amount((contract as ExploreContract).escrow)
	if contract.is_paused():
		tooltip_text += "\nPaused: the station can't pay one %s cr payment, captains won't take it until credits come in" % Economy.format_amount(contract.reward)
	if not warn.is_empty():
		tooltip_text += "\n%s. %s." % [warn, contract.get_warning_hint()]
	_cancel.tooltip_text = ContractBoard.cancel_text(contract)


func subtitle_has_reward() -> bool:
	return title_label.text != contract.get_reward_text()


func _on_pressed() -> void:
	if hud == null:
		return
	if is_instance_valid(target):
		hud.focus(target)
	if hud.selection and is_instance_valid(contract.target) and (contract.target is AsteroidCluster or contract.target is PlanetBody or contract.target is Ship or contract.target is ScavengerDen or contract.target is ScrapField or contract.target is JumpGate):
		hud.selection.select(contract.target)


## The contract's beacon when there is one, else its target.
static func _focus_target(c: Contract, owner_hud: HUD) -> Node3D:
	if c is PlanetRaidContract or c is ExploreContract:
		return c.target
	if owner_hud and owner_hud.is_inside_tree():
		var w := SystemWorld.of(owner_hud)
		var markers := w.contract_markers if w else null
		var m := markers.get_marker(c) if markers else null
		if m:
			return m
	return c.target


## The target ("[Ostra] Flint Cluster" outside home) or the reward.
static func _title_for(c: Contract, show_target: bool) -> String:
	if not show_target:
		return c.get_reward_text()
	var tag := HUD.system_tag(c.system_id)
	return (tag + " " if not tag.is_empty() else "") + c.get_target_name()


static func _clock(t: float) -> String:
	var s := int(t)
	return "%02d:%02d:%02d" % [floori(s / 3600.0), floori(s / 60.0) % 60, s % 60]

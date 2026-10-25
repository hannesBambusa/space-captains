class_name ContractRow
extends OverviewRow
## One posted contract in a list: type and target (or just the reward when
## the list is already about one target), reward, takers (or the bounty's
## fleet, "Fleet of 3 forming", or its lone wolf) and progress, "paused,
## station can't pay" while the credits do not cover one payment, and a
## cancel button (its tooltip says what a bounty's escrow does: all back
## while nobody has taken it, half back and half to the takers once taken). Click = camera flies to the contract beacon and the target
## is selected.

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
	var team := (contract as BountyContract).get_team_text() if contract is BountyContract else ""
	if not team.is_empty():
		parts.append(team)
	else:
		parts.append("%d on it" % n if n > 0 else contract.get_status_name().to_lower())
	if n > 0 and contract.is_paused():
		parts.append("paused, station can't pay")
	var prog := contract.get_progress_text()
	if not prog.is_empty() and not subtitle_has_reward():
		parts.append(prog)
	set_subtitle("  ·  ".join(parts))
	tooltip_text = "%s\n%s\nPosted at %s\nPaid out: %s cr" % [contract.get_title(), contract.get_reward_text(), _clock(contract.created_time), Economy.format_amount(contract.credits_paid)]
	if contract is BountyContract:
		tooltip_text += "\nReserved: %s cr" % Economy.format_amount((contract as BountyContract).escrow)
	if contract.is_paused():
		tooltip_text += "\nPaused: the station can't pay one %s cr payment, captains won't take it until credits come in" % Economy.format_amount(contract.reward)
	_cancel.tooltip_text = ContractBoard.cancel_text(contract)


func subtitle_has_reward() -> bool:
	return title_label.text != contract.get_reward_text()


func _on_pressed() -> void:
	if hud == null:
		return
	if hud.camera and is_instance_valid(target):
		hud.camera.focus_on(target)
	if hud.selection and is_instance_valid(contract.target) and (contract.target is AsteroidCluster or contract.target is PlanetBody or contract.target is Ship or contract.target is ScavengerDen or contract.target is ScrapField):
		hud.selection.select(contract.target)


## The contract's beacon when there is one, else its target.
static func _focus_target(c: Contract, owner_hud: HUD) -> Node3D:
	if c is PlanetRaidContract:
		return c.target
	if owner_hud and owner_hud.is_inside_tree():
		var markers := owner_hud.get_tree().get_first_node_in_group(ContractMarkers.GROUP) as ContractMarkers
		var m := markers.get_marker(c) if markers else null
		if m:
			return m
	return c.target


static func _title_for(c: Contract, show_target: bool) -> String:
	return c.get_target_name() if show_target else c.get_reward_text()


static func _clock(t: float) -> String:
	var s := int(t)
	return "%02d:%02d:%02d" % [floori(s / 3600.0), floori(s / 60.0) % 60, s % 60]

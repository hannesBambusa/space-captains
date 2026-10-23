class_name MiningDemo
extends Node
## Mining loop setups for screenshots and play-testing (user args after "--"):
##   --mining-demo            Mining Outpost near the station, 4 miners (Bold,
##                            Cautious, Greedy, Lazy), contracts on Cinder Belt
##                            (80 cr/load) and Talon Reach (fair pay). Runs live.
##   --mining-demo=belt       ... Cinder Belt selected: belt panel and beacon.
##   --mining-demo=contracts  ... overview with the contract list, ships on trips.
##   --mining-demo=flying     ... fast-forwards until a miner is in flight, follows it.
##   --mining-demo=mining     ... fast-forwards until a miner drills, follows it.
##   --mining-demo=docking    ... fast-forwards until a miner backs into the hangar.
##   --mining-demo=crossing   ... fast-forwards until a miner flies its lane over
##                            (or under) a belt, follows it.
##   --mining-demo=unload     ... fast-forwards until a miner unloads at the
##                            outpost, mid-swing of the crane arm (lights on).
##   --mining-demo=captain    ... only Talon Reach (fair) and Crystal Veil (low pay):
##                            the Cautious captain refuses; its panel is open.
##   --advance=<sim seconds>  fast-forward this much after setup (any view).
##   --time-scale=<x>         sim speed multiplier (any value, e.g. 8).
## --cam / --focus (ScreenshotMode) override the demo camera.

@export var demo_offset: Vector3 = Vector3(115.0, 0.0, 80.0)
@export var demo_seed: int = 11
## Upper bound for "until" fast-forwards, sim seconds.
@export var max_search_time: float = 400.0

var _view := ""
var _advance := 0.0
var _time_scale := 0.0
var _has_view := false
var _yaw_offset := 40.0


func _ready() -> void:
	var on := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--mining-demo":
			on = true
		elif arg.begins_with("--mining-demo="):
			on = true
			_view = arg.trim_prefix("--mining-demo=")
		elif arg.begins_with("--advance="):
			_advance = arg.trim_prefix("--advance=").to_float()
		elif arg.begins_with("--time-scale="):
			_time_scale = arg.trim_prefix("--time-scale=").to_float()
		elif arg.begins_with("--cam=") or arg.begins_with("--focus="):
			_has_view = true
		elif arg.begins_with("--demo-yaw="):
			_yaw_offset = arg.trim_prefix("--demo-yaw=").to_float()
	if _time_scale > 0.0:
		SimClock.set_speed(_time_scale)
	if on:
		_run()
	elif _advance > 0.0:
		_advance_only()


func _advance_only() -> void:
	for i in 3:
		await get_tree().process_frame
	SimStepper.run(get_tree(), _advance)


func _run() -> void:
	for i in 3:
		await get_tree().process_frame
	var tree := get_tree()
	var manager := tree.get_first_node_in_group(BuildingManager.GROUP) as BuildingManager
	var hud := tree.get_first_node_in_group(HUD.GROUP) as HUD
	var cam := tree.get_first_node_in_group("rts_camera") as RTSCamera
	if manager == null or hud == null or not manager.has_zone() or manager.building_defs.is_empty():
		push_warning("MiningDemo: missing building manager, HUD or build zone")
		return
	var sys := manager.solar_system
	manager.rng.seed = demo_seed
	var outpost := manager.spawn_finished(manager.building_defs[0], demo_offset, deg_to_rad(-30.0))
	await tree.process_frame
	var ships: Array[Ship] = []
	for p in Captain.PERSONALITY_NAMES.size():
		var s := outpost.hire(p)
		if s:
			s.snap_to_slot()
			ships.append(s)
	var cinder := _belt(sys, "Cinder Belt")
	var talon := _belt(sys, "Talon Reach")
	var veil := _belt(sys, "Crystal Veil")
	var rules := ContractBoard.mining_rules
	if _view == "captain":
		ContractBoard.post_mining(talon, rules.default_reward(talon))
		ContractBoard.post_mining(veil, 100)
	else:
		ContractBoard.post_mining(cinder, 80)
		ContractBoard.post_mining(talon, rules.default_reward(talon))
	hud.overview.set_open(true)

	if _advance > 0.0:
		SimStepper.run(tree, _advance)
	var follow: Node3D = outpost
	var dist := 420.0
	var yaw := NAN
	match _view:
		"belt":
			hud.selection.select(cinder)
			var markers := tree.get_first_node_in_group(ContractMarkers.GROUP) as ContractMarkers
			var c := ContractBoard.get_for_target(cinder)
			var m := markers.get_marker(c[0]) if markers and not c.is_empty() else null
			follow = m if m else cinder
			dist = 5200.0
		"contracts":
			if _advance <= 0.0:
				SimStepper.run(tree, 12.0)
			hud.selection.select(outpost)
			dist = 520.0
		"flying":
			var flyer := _until(ships, func(s: Ship) -> bool:
				return s.brain.state == CaptainBrain.State.TRAVELING_TO_JOB and s.global_position.distance_to(outpost.global_position) > 500.0)
			if flyer:
				follow = flyer
				dist = 110.0
				yaw = _sunlit_yaw(flyer, 35.0)
		"crossing":
			var crosser := _until(ships, func(s: Ship) -> bool:
				if s.brain.state != CaptainBrain.State.TRAVELING_TO_JOB or absf(s.global_position.y) < 45.0:
					return false
				var band := SpaceNav.rock_band_at(tree, s.global_position)
				return band != null and SpaceNav.distance_to_belt(band, s.global_position) < band.def.width * 0.25)
			if crosser:
				follow = crosser
				dist = 140.0
				yaw = _sunlit_yaw(crosser, 70.0)
		"mining":
			var miner := _until(ships, func(s: Ship) -> bool:
				return s.brain.state == CaptainBrain.State.MINING and s.brain.trip.progress > 0.35)
			if miner:
				follow = miner
				dist = 85.0
				yaw = _sunlit_yaw(miner, 40.0)
		"docking":
			var docker := _until(ships, func(s: Ship) -> bool:
				return s.brain.state == CaptainBrain.State.DOCKING and s.mover.path.size() <= 2 and s.slot_index < outpost.inner_berths)
			if docker:
				follow = outpost
				dist = 170.0
				# Look into the hangar mouth (outpost +Z).
				var mouth := outpost.global_basis.z
				yaw = rad_to_deg(atan2(mouth.x, mouth.z)) + 35.0
		"unload":
			var fx := outpost.get_unload_fx()
			if fx:
				SimStepper.run(tree, max_search_time * 2.0, 0.05, func() -> bool:
					return fx.is_unloading() and fx.swing > 0.45 and fx.swing < 0.7 and fx.chunks_spawned > 0)
			# Frame the crane: between the hold and the hopper.
			var anchor := Node3D.new()
			anchor.name = "UnloadView"
			outpost.add_child(anchor)
			anchor.position = Vector3(14.0, 0.0, 9.0)
			follow = anchor
			dist = 55.0
			var side := outpost.global_basis.x
			yaw = rad_to_deg(atan2(side.x, side.z)) + _yaw_offset
		"captain":
			var cautious := ships[1] if ships.size() > 1 else null
			_until(ships, func(_s: Ship) -> bool:
				return cautious != null and not cautious.brain.last_refusal.is_empty())
			if cautious:
				hud.selection.select(cautious)
				follow = cautious
				dist = 160.0
		_:
			hud.selection.select(outpost)
	if not _has_view and cam and is_instance_valid(follow):
		if not is_nan(yaw):
			cam.set_yaw(yaw, true)
		cam.focus_on(follow, dist, true)


## Fast-forwards until one ship passes [param test]; returns it (or null).
func _until(ships: Array[Ship], test: Callable) -> Ship:
	var found: Array[Ship] = []
	SimStepper.run(get_tree(), max_search_time, 0.1, func() -> bool:
		for s in ships:
			if test.call(s):
				found.append(s)
				return true
		return false)
	return found[0] if not found.is_empty() else null


## Camera yaw that looks at [param ship] from the star's side (lit), turned
## by [param offset_deg].
static func _sunlit_yaw(ship: Node3D, offset_deg: float) -> float:
	var p := ship.global_position
	return rad_to_deg(atan2(-p.x, -p.z)) + offset_deg


static func _belt(sys: SolarSystem, belt_name: String) -> SystemBelt:
	for b in sys.belts:
		if b.def.name == belt_name:
			return b
	return sys.belts[0] if not sys.belts.is_empty() else null

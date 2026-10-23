class_name ProgressDemo
extends Node
## Stage 3 setups for screenshots and play-testing (user args after "--"):
##   --progress-demo=ranks      mining outpost, 4 miners on Cinder Belt;
##                              fast-forwards to the first rank-up. The miner
##                              is selected (rank bar), the roster is open.
##   --progress-demo=traits     a miner back from a near-loss (Survivor,
##                              Shaken fading) with Crystal Hound; selected.
##   --progress-demo=outfitter  outfitter and outposts, captains with money;
##                              fast-forwards through their shopping, Mk II
##                              unlocked. The Outfitter is selected.
##   --progress-demo=career     a Bold veteran miner quits mining for a
##                              mercenary berth; the new ship is selected.
##   --progress-demo=salvage    salvage yard, 3 salvagers and a salvage
##                              contract on a fresh wreck; follows a salvager
##                              at work, the field selected.
##   --progress-demo=eject      a miner's ship destroyed by a scavenger; the
##                              captain ejects. Follows the pod home.
## --cam / --focus (ScreenshotMode) override the demo camera.

@export var mining_offset: Vector3 = Vector3(260.0, 0.0, 180.0)
@export var merc_offset: Vector3 = Vector3(-230.0, 0.0, 250.0)
@export var outfitter_offset: Vector3 = Vector3(-60.0, 0.0, -300.0)
@export var yard_offset: Vector3 = Vector3(330.0, 0.0, -200.0)
@export var demo_seed: int = 31
@export var max_search_time: float = 900.0

var tree: SceneTree
var hud: HUD
var cam: RTSCamera
var manager: BuildingManager
var world: CombatWorld
var sys: SolarSystem
var _view := ""
var _has_view := false


func _ready() -> void:
	var on := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--progress-demo="):
			on = true
			_view = arg.trim_prefix("--progress-demo=")
		elif arg == "--progress-demo":
			on = true
			_view = "ranks"
		elif arg.begins_with("--cam=") or arg.begins_with("--focus="):
			_has_view = true
	if on:
		_run()


func _run() -> void:
	for i in 3:
		await get_tree().process_frame
	tree = get_tree()
	manager = tree.get_first_node_in_group(BuildingManager.GROUP) as BuildingManager
	hud = tree.get_first_node_in_group(HUD.GROUP) as HUD
	cam = tree.get_first_node_in_group("rts_camera") as RTSCamera
	world = CombatWorld.of(tree)
	if manager == null or hud == null or world == null or not manager.has_zone() or manager.building_defs.size() < 4:
		push_warning("ProgressDemo: missing building manager, HUD, combat world or building defs")
		return
	sys = manager.solar_system
	world.raids.enabled = false
	manager.rng.seed = demo_seed
	seed(demo_seed)
	Career.rng.seed = demo_seed
	Economy.credits = 9000
	Economy.materials = 1500
	var mine := manager.spawn_finished(manager.building_defs[0], mining_offset, deg_to_rad(-30.0))
	await tree.process_frame
	var follow: Node3D = mine
	var dist := 300.0
	var yaw := NAN
	var cinder := _belt("Cinder Belt")
	match _view:
		"ranks":
			var miners := _hire(mine, [0, 1, 2, 3])
			ContractBoard.post_mining(cinder, ContractBoard.mining_rules.default_reward(cinder))
			var up := _until(miners, func(s: Ship) -> bool: return s.captain.rank >= Reputation.Rank.LICENSED)
			_run_for(25.0)
			hud.overview.set_open(true)
			if is_instance_valid(up):
				hud.selection.select(up)
				follow = up
				dist = 140.0
		"traits":
			var miners := _hire(mine, [1, 2])
			var m := miners[0]
			var c := m.captain
			c.crystal_loads = CaptainTraits.CRYSTAL_LOADS
			c.add_trait(CaptainTraits.CRYSTAL_HOUND)
			c.add_reputation(70.0)
			m.trip_lowest_hull = 0.16
			m.trip_was_hit = true
			m.durability.hull = m.durability.max_hull * 0.3
			m.on_docked_home()
			ContractBoard.post_mining(cinder, ContractBoard.mining_rules.default_reward(cinder))
			_run_for(40.0)
			hud.selection.select(m)
			follow = m
			dist = 150.0
		"outfitter":
			var merc := manager.spawn_finished(manager.building_defs[1], merc_offset, deg_to_rad(25.0))
			var outf := manager.spawn_finished(manager.building_defs[2], outfitter_offset, deg_to_rad(160.0))
			await tree.process_frame
			var ships := _hire(mine, [0, 1, 2, 3])
			ships.append_array(_hire(merc, [0, 1, 2]))
			var o := outf.get_service() as Outfitter
			for s in ships:
				s.captain.add_reputation(Reputation.THRESHOLDS[Reputation.Rank.VETERAN] + 10.0 * float(ships.find(s)))
				s.captain.wallet = 900
			o.unlock_next()
			_run_for(100.0)
			o.add_rare_part(ModuleCatalog.shared().find(&"deflector_3"))
			hud.selection.select(outf)
			follow = outf
			dist = 260.0
			yaw = rad_to_deg(atan2(outf.global_basis.z.x, outf.global_basis.z.z)) + 30.0
		"career":
			var merc := manager.spawn_finished(manager.building_defs[1], merc_offset, deg_to_rad(25.0))
			await tree.process_frame
			_hire(merc, [1])
			var miners := _hire(mine, [0, 1])
			var m := miners[0]
			var c := m.captain
			c.nerve = 9
			c.piloting = 8
			c.career_since = -Career.COOLDOWN
			c.add_reputation(260.0)
			c.add_trait(CaptainTraits.GRUDGE)
			c.loads_delivered = 22
			c.wallet = 1400
			c.add_history("Took Talon Reach, 65 cr/load")
			_run_for(3.0)
			if Career.offer(m, "Mercenary").is_empty() and is_instance_valid(c.ship):
				_run_for(14.0)
				hud.selection.select(c.ship)
				follow = c.ship
				dist = 150.0
		"salvage":
			var yard := manager.spawn_finished(manager.building_defs[3], yard_offset, deg_to_rad(200.0))
			await tree.process_frame
			var salvagers := _hire(yard, [0, 1, 2])
			var home := sys.home_station.global_position
			var wreck := world.spawn_scrap(home + Vector3(900.0, 0.0, -1500.0), 160, 900.0, 40.0, "Hauler wreck")
			ContractBoard.post_salvage(wreck, 50)
			var worker := _until(salvagers, func(s: Ship) -> bool:
				return s.brain.state == CaptainBrain.State.MINING and s.brain.trip.progress > 0.3)
			hud.selection.select(wreck)
			follow = wreck
			if worker:
				follow = worker
			dist = 160.0
			if worker:
				yaw = MiningDemo._sunlit_yaw(worker, 40.0)
		"eject":
			var home := sys.home_station.global_position
			var pod: EscapePod = null
			for i in 40:
				var s := mine.hire(1)
				if s == null:
					break
				s.snap_to_slot()
				s.captain.piloting = 9
				s.captain.add_reputation(80.0)
				s.loadout.set_module(ShipModule.Slot.DEFENSE, ModuleCatalog.shared().find(&"survival_cell_2").duplicate())
				s.refit()
				s.enter_space()
				s.global_position = home + Vector3(1500.0, 0.0, -1700.0)
				var raider := sys.dens[0].spawn()
				raider.global_position = s.global_position + Vector3(220.0, 0.0, 60.0)
				_run_for(0.3)
				var c := s.captain
				s.destroy(raider)
				if c.alive and c.ship is EscapePod:
					pod = c.ship as EscapePod
					raider.ai.state = ScavengerBrain.State.ROAMING
					break
				raider.leave_map()
			if pod:
				_run_for(8.0)
				hud.selection.select(pod)
				follow = pod
				dist = 90.0
				yaw = MiningDemo._sunlit_yaw(pod, 30.0)
	if not _has_view and cam and is_instance_valid(follow):
		if not is_nan(yaw):
			cam.set_yaw(yaw, true)
		cam.focus_on(follow, dist, true)


func _hire(b: Building, personalities: Array) -> Array[Ship]:
	var out: Array[Ship] = []
	for p: int in personalities:
		var s := b.hire(p)
		if s:
			s.snap_to_slot()
			out.append(s)
	return out


func _run_for(seconds: float) -> void:
	SimStepper.run(tree, seconds)


## Fast-forwards until one ship passes [param test]; returns it (or null).
func _until(ships: Array[Ship], test: Callable) -> Ship:
	var found: Array[Ship] = []
	SimStepper.run(tree, max_search_time, 0.1, func() -> bool:
		for s in ships:
			if is_instance_valid(s) and not s.dead and test.call(s):
				found.append(s)
				return true
		return false)
	return found[0] if not found.is_empty() else null


func _belt(belt_name: String) -> SystemBelt:
	for b in sys.belts:
		if b.def.name == belt_name:
			return b
	return sys.belts[0]

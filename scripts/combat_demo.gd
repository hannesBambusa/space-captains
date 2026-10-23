class_name CombatDemo
extends Node
## Combat setups for screenshots and play-testing (user args after "--"):
##   --combat-demo            = raid
##   --combat-demo=raid       both outposts near the station, 4 miners and 4
##                            mercenaries; a scavenger raid arrives and the
##                            mercs fight it near home. Follows a merc.
##   --combat-demo=fight      ... fast-forwards to the first kill and drops to
##                            slow motion on the explosion.
##   --combat-demo=escort     escorted mining contract on Talon Reach: a miner
##                            with two escorts in formation, shield beacon.
##   --combat-demo=bounty     bounty on a scavenger: target panel and red
##                            reticle, a merc on the way.
##   --combat-demo=den        Rustjaw Hideout selected, its scavengers around it.
##   --combat-demo=denfight   bounty on Rustjaw Hideout, mercs attacking it.
##   --combat-demo=fleet      bounty on Rustjaw Hideout: the mercs (team
##                            players) form a fleet, fly out in formation
##                            and attack it; the leader is selected.
##   --combat-demo=outpost    the Mercenary Outpost with its mercs docked.
##   --combat-demo=scrap      a scrap field from a fresh kill, selected.
##   --combat-demo=captain    a fighting merc selected: captain panel.
##   --combat-demo=feed       wide view after a raid: event feed and overview.
##   --combat-demo=swarm      performance check: two more outposts (16 player
##                            ships) and a 16-ship raid fighting near home.
##   --combat-demo=defense    a Shield Generator and two Defense Turrets; the
##                            mercs are away on a bounty when a 4-ship raid
##                            hits the station shield bubble, turrets firing.
##                            Frames the bubble.
##   --combat-demo=turret     ... the same fight, close on a firing turret
##                            (selected: its panel).
## Works with --advance and --time-scale (MiningDemo reads those); --cam /
## --focus (ScreenshotMode) override the demo camera.

@export var mining_offset: Vector3 = Vector3(115.0, 0.0, 80.0)
@export var merc_offset: Vector3 = Vector3(-96.0, 0.0, 104.0)
@export var demo_seed: int = 23
@export var max_search_time: float = 600.0

var _view := ""
var _has_view := false
var tree: SceneTree
var hud: HUD
var cam: RTSCamera
var manager: BuildingManager
var world: CombatWorld
var sys: SolarSystem
var mining_outpost: Building
var merc_outpost: Building
var miners: Array[Ship] = []
var mercs: Array[Ship] = []


func _ready() -> void:
	var on := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--combat-demo":
			on = true
			_view = "raid"
		elif arg.begins_with("--combat-demo="):
			on = true
			_view = arg.trim_prefix("--combat-demo=")
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
	if manager == null or hud == null or world == null or not manager.has_zone() or manager.building_defs.size() < 2:
		push_warning("CombatDemo: missing building manager, HUD, combat world or build zone")
		return
	sys = manager.solar_system
	world.raids.enabled = false
	Economy.credits = 8000
	manager.rng.seed = demo_seed
	mining_outpost = manager.spawn_finished(manager.building_defs[0], mining_offset, deg_to_rad(-30.0))
	merc_outpost = manager.spawn_finished(manager.building_defs[1], merc_offset, deg_to_rad(25.0))
	await tree.process_frame
	for p in 4:
		var m := mining_outpost.hire(p)
		if m:
			m.snap_to_slot()
			miners.append(m)
		var s := merc_outpost.hire(p)
		if s:
			s.snap_to_slot()
			mercs.append(s)
	hud.overview.set_open(true)
	var follow: Node3D = merc_outpost
	var dist := 300.0
	var yaw := NAN
	var home := sys.home_station.global_position
	match _view:
		"raid", "fight", "captain", "feed":
			_run_for(4.0)
			var raiders := world.raids.trigger_raid(3, sys.dens[0])
			for i in raiders.size():
				raiders[i].global_position = home + Vector3(1900.0 + 120.0 * i, 0.0, -1300.0 + 90.0 * i)
			var fighter := _until(mercs, func(s: Ship) -> bool:
				return s.brain.state == CaptainBrain.State.ENGAGING and world.projectiles.count() > 6)
			follow = merc_outpost
			if fighter:
				follow = fighter
			dist = 260.0
			if _view == "fight":
				var n0 := world.fx.explosions_played
				SimStepper.run(tree, max_search_time, 0.05, func() -> bool: return world.fx.explosions_played > n0)
				var boom := _anchor_at(_last_explosion_pos())
				follow = boom
				dist = 170.0
				SimClock.set_speed(0.15)
			elif _view == "captain" and fighter:
				hud.selection.select(fighter)
				dist = 190.0
			elif _view == "feed":
				var talon := _belt("Talon Reach")
				ContractBoard.post_mining(talon, 200)
				ContractBoard.post_bounty(sys.dens[0], 900, 4)
				_run_for(70.0)
				follow = sys.home_station
				if is_instance_valid(fighter):
					follow = fighter
				dist = 900.0
		"swarm":
			var extra_m := _place_near(manager.building_defs[0], rad_to_deg(atan2(mining_offset.z, mining_offset.x)) + 15.0, 200)
			var extra_c := _place_near(manager.building_defs[1], rad_to_deg(atan2(merc_offset.z, merc_offset.x)) + 15.0, 200)
			await tree.process_frame
			for p in 4:
				for b in [extra_m, extra_c]:
					var s := (b as Building).hire(p)
					if s:
						s.snap_to_slot()
						(mercs if b == extra_c else miners).append(s)
			ContractBoard.post_mining(_belt("Cinder Belt"), 80)
			_run_for(4.0)
			var swarm := world.raids.trigger_raid(8, sys.dens[0])
			swarm.append_array(world.raids.trigger_raid(8, sys.dens[1]))
			for i in swarm.size():
				swarm[i].global_position = home + Vector3(1500.0 + 60.0 * (i % 4), 0.0, -900.0 + 70.0 * (i / 4.0))
			_until(mercs, func(s: Ship) -> bool:
				return s.brain.state == CaptainBrain.State.ENGAGING and world.projectiles.count() > 20)
			follow = sys.home_station
			dist = 1600.0
			print("CombatDemo swarm: %d ships, %d tracers" % [tree.get_nodes_in_group(Ship.GROUP).size(), world.projectiles.count()])
		"defense", "turret":
			var gen := _place_near(_def(&"shield_generator"), -95.0)
			var turrets: Array[Building] = []
			for a in [-25.0, -60.0]:
				var t := _place_near(_def(&"defense_turret"), a, 200)
				if t:
					turrets.append(t)
			# Every merc out on a bounty far from home.
			ContractBoard.post_bounty(sys.dens[0], 2400, 4)
			SimStepper.run(tree, 150.0, 0.1, func() -> bool:
				for m in mercs:
					if is_instance_valid(m) and Combat.flat_distance(m.global_position, home) < 3500.0:
						return false
				return true)
			# Whoever turned the bounty down is sent off duty.
			for m in mercs:
				if is_instance_valid(m) and Combat.flat_distance(m.global_position, home) < 3500.0:
					m.retire()
			var raiders := world.raids.trigger_raid(4, sys.dens[1] if sys.dens.size() > 1 else sys.dens[0])
			var bubble := StationShield.find(tree)
			var from := Vector3(cos(deg_to_rad(-40.0)), 0.0, sin(deg_to_rad(-40.0)))
			for i in raiders.size():
				raiders[i].global_position = home + from * (1500.0 + 80.0 * i) + from.cross(Vector3.UP) * (120.0 * i - 180.0)
			SimStepper.run(tree, max_search_time, 0.05, func() -> bool:
				var firing := false
				for t in turrets:
					var dt := t.get_service() as DefenseTurret if is_instance_valid(t) else null
					if dt and dt.mode == DefenseTurret.Mode.FIRING:
						firing = true
				return firing and bubble and bubble.hits_taken > 16 and bubble.seconds_since_hit() < 0.3 and world.projectiles.count() > 6)
			follow = bubble if bubble else sys.home_station
			dist = (bubble.radius if bubble else 400.0) * 3.1
			yaw = rad_to_deg(atan2(-from.x, -from.z)) + 180.0 + 25.0
			if _view == "turret" and not turrets.is_empty() and is_instance_valid(turrets[0]):
				hud.selection.select(turrets[0])
				follow = turrets[0]
				dist = 85.0
				yaw = rad_to_deg(atan2(-from.x, -from.z)) + 180.0 + 35.0
			print("CombatDemo defense: generator %s, %d turrets, shield %s %d HP, %d hits" % [
					gen != null, turrets.size(), bubble.get_state_name() if bubble else "-", roundi(bubble.hp) if bubble else 0, bubble.hits_taken if bubble else 0])
		"escort":
			var talon := _belt("Talon Reach")
			var mc := ContractBoard.post_mining(talon, 220)
			ContractBoard.post_escort_for_mining(mc, 45, 2)
			var pair := _until(miners, func(s: Ship) -> bool:
				var ec := ContractBoard.escort_for_mining(mc)
				if ec == null or not (s.brain.state == CaptainBrain.State.TRAVELING_TO_JOB or s.brain.state == CaptainBrain.State.RETURNING):
					return false
				if s.global_position.distance_to(mining_outpost.global_position) < 800.0:
					return false
				var n := 0
				for e in ec.escorts_of(s):
					if e.brain.state == CaptainBrain.State.ESCORTING and e.global_position.distance_to(s.global_position) < 110.0:
						n += 1
				return n >= mini(2, ec.escorts_of(s).size()) and n > 0)
			if pair:
				follow = pair
				dist = 190.0
				yaw = _sunlit_yaw(pair, 150.0)
		"bounty":
			var mark := sys.dens[0].spawn()
			var away := -SpaceNav.world_velocity(sys.home_station).normalized()
			mark.global_position = home + away * 7500.0
			mark.ai = null
			mark.mover.hold()
			# Tougher than usual so the hunt is still on when the shot is taken.
			mark.durability = Durability.new(1500.0, 300.0, 20.0)
			ContractBoard.post_bounty(mark, 175)
			_until(mercs, func(s: Ship) -> bool:
				var d := s.global_position.distance_to(mark.global_position)
				return (s.brain.state == CaptainBrain.State.HUNTING or s.brain.state == CaptainBrain.State.ENGAGING) and d < 1200.0)
			hud.selection.select(mark)
			follow = mark
			dist = 420.0
		"fleet":
			var den := sys.dens[0]
			for s in mercs:
				s.captain.teamwork = 8
			ContractBoard.post_bounty(den, 1800, 4)
			var lead := _until(mercs, func(s: Ship) -> bool:
				var mb := s.brain as MercenaryBrain
				if mb.fleet == null or mb.fleet.leader != s or mb.fleet.state != MercFleet.State.ENGAGING or mb.fleet.members.size() < 2:
					return false
				return s.global_position.distance_to(den.global_position) < 1100.0 and world.projectiles.count() > 2)
			if lead:
				hud.selection.select(lead)
				follow = lead
				dist = 420.0
				yaw = _sunlit_yaw(den, 20.0)
		"den", "denfight":
			var den := sys.dens[0]
			if _view == "denfight":
				ContractBoard.post_bounty(den, 2000, 4)
				_until(mercs, func(s: Ship) -> bool:
					return s.brain.state == CaptainBrain.State.ENGAGING and s.global_position.distance_to(den.global_position) < 700.0 and world.projectiles.count() > 4)
			else:
				_run_for(30.0)
			hud.selection.select(den)
			follow = den
			dist = 300.0 if _view == "den" else 420.0
			yaw = _sunlit_yaw(den, 40.0)
		"outpost":
			_run_for(2.0)
			hud.selection.select(merc_outpost)
			follow = merc_outpost
			dist = 230.0
			yaw = rad_to_deg(atan2(merc_outpost.global_basis.z.x, merc_outpost.global_basis.z.z)) + 30.0
		"scrap":
			var victim := sys.dens[0].spawn()
			victim.global_position = home + Vector3(1400.0, 0.0, 400.0)
			victim.ai = null
			victim.mover.hold()
			_run_for(0.5)
			victim.destroy(mercs[0])
			_run_for(14.0)
			var fields := world.get_scrap_fields()
			if not fields.is_empty():
				hud.selection.select(fields[0])
				follow = fields[0]
				dist = 160.0
	if not _has_view and cam and is_instance_valid(follow):
		if not is_nan(yaw):
			cam.set_yaw(yaw, true)
		cam.focus_on(follow, dist, true)


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


func _last_explosion_pos() -> Vector3:
	var best := Vector3.ZERO
	for c in world.fx.get_children():
		if c.name.begins_with("Explosion") and (c as Node3D).visible:
			best = (c as Node3D).global_position
	return best


func _anchor_at(pos: Vector3) -> Node3D:
	var a := Node3D.new()
	a.name = "DemoAnchor"
	add_child(a)
	a.global_position = Vector3(pos.x, 0.0, pos.z)
	return a


static func _sunlit_yaw(n: Node3D, offset_deg: float) -> float:
	var p := n.global_position
	return rad_to_deg(atan2(-p.x, -p.z)) + offset_deg


func _def(id: StringName) -> BuildingDef:
	for d in manager.building_defs:
		if d.id == id:
			return d
	return null


## Places [param def] finished on the first valid spot near the station,
## searching outward from [param min_dist] m around [param angle_deg]
## (frame-local, from +X).
func _place_near(def: BuildingDef, angle_deg: float, min_dist: int = 100) -> Building:
	if def == null:
		return null
	for r in range(min_dist, 520, 10):
		for k in 15:
			var a := deg_to_rad(angle_deg + ceilf(k / 2.0) * 10.0 * (1.0 if k % 2 == 1 else -1.0))
			var off := Vector3(cos(a), 0.0, sin(a)) * float(r)
			var p := manager.plan_placement(def, off, false)
			if p.is_valid():
				return manager.spawn_finished(def, off, p.yaw)
	push_warning("CombatDemo: no spot for %s" % def.display_name)
	return null


func _belt(belt_name: String) -> SystemBelt:
	for b in sys.belts:
		if b.def.name == belt_name:
			return b
	return sys.belts[0]

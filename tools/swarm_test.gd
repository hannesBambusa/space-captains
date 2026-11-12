extends Node
## Headless check of the Swarm: the home system's Swarm Hive is brought in,
## grows (ScavengerDen.growth, one more drone out per SWARM_GROW_TIME) and
## buds a second hive (ThreatDirector.bud_hive); a save round trip keeps
## both hives and the growth. Prints "SWARM ..." lines; exit 1 on a failed
## check. Run: Godot --headless --path . res://tools/swarm_test.tscn
## (-- --shot=/abs/dir with a window: a close shot of the hive and drones).

var _fails: PackedStringArray = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.autosave_interval = 1e12
	Tutorial.write_settings = false
	_run.call_deferred()


func _ok(cond: bool, what: String) -> void:
	print("SWARM %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails.append(what)


func _hives(tree: SceneTree) -> Array[ScavengerDen]:
	var out: Array[ScavengerDen] = []
	var sys := SolarSystem.of(SystemWorld.home(tree))
	for d in sys.dens:
		if is_instance_valid(d) and d.is_alive() and d.faction_def and d.faction_def.id == ScavengerDen.SWARM_ID:
			out.append(d)
	return out


func _run() -> void:
	var tree := get_tree()
	var dummy := Node.new()
	tree.root.add_child(dummy)
	tree.current_scene = dummy
	Sector.next_modifier = SectorModifier.STANDARD
	Corps.next_difficulty = CorpRegistry.Difficulty.OFF
	await SaveManager.new_game(false)
	for i in 3:
		await tree.process_frame
	Tutorial.of(tree).finish()
	var home := SystemWorld.home(tree)
	var sys := SolarSystem.of(home)
	var threats := CombatWorld.of(home).threats
	var def: DenDef = null
	for d in sys.system_def.dens:
		if d.get_faction().id == ScavengerDen.SWARM_ID:
			def = d
	_ok(def != null, "home system has a Swarm Hive def (arrival %d, %.0f min)" % [def.arrival_order if def else -1, def.min_arrival_time / 60.0 if def else 0.0])
	if def == null:
		tree.quit(1)
		return
	threats.arrived[def.name] = SimClock.time
	var hive := sys.arrive_den(def, true)
	SimStepper.run(tree, 30.0)
	_ok(hive and hive.is_alive() and not hive.is_arriving(), "hive in place")
	print("SWARM hive: %s, hull %.0f, out %d/%d" % [hive.get_display_name(), hive.durability.max_hull, hive.spawns.size(), hive.spawn_limit()])
	await _shot(hive)
	SimStepper.run(tree, ScavengerDen.SWARM_GROW_TIME * 3.0 + 30.0)
	_ok(hive.growth >= 3, "hive grew (growth %d, limit %d)" % [hive.growth, hive.spawn_limit()])
	_ok(_hives(tree).size() == 2 and threats.extra_dens.size() == 1, "budded a second hive (%d hives)" % _hives(tree).size())
	var drones := 0
	for h in _hives(tree):
		drones += h.spawns.size()
	print("SWARM drones out: %d" % drones)
	var data := GameSnapshot.capture(tree)
	await SaveManager.load_snapshot(data)
	for i in 3:
		await tree.process_frame
	var after := _hives(tree)
	_ok(after.size() == 2, "save round trip keeps both hives (%d)" % after.size())
	var g := 0
	for h in after:
		g = maxi(g, h.growth)
	_ok(g >= 3, "growth kept after the load (%d)" % g)
	tree.quit(0 if _fails.is_empty() else 1)


func _shot(hive: ScavengerDen) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			var hud := Tutorial.of(get_tree()).hud
			hud.camera.focus_on(hive, 900.0, true)
			hud.camera.set_pitch(30.0)
			for i in 60:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--shot=").path_join("swarm.png"))

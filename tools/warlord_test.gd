extends Node
## Headless check of the pirate warlord ([WarlordDirector], [WarlordShip]):
## forces the first warlord in, checks the warning, the flagship and its
## escorts, a save round trip, a retreat and the return with one escort
## more, then the kill and its reward. Prints "WARLORD ..." lines; exit 1
## on a failed check. Run: Godot --headless --path . res://tools/warlord_test.tscn

var _fails: PackedStringArray = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.autosave_interval = 1e12
	Tutorial.write_settings = false
	_run.call_deferred()


func _ok(cond: bool, what: String) -> void:
	print("WARLORD %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails.append(what)


func _dir() -> WarlordDirector:
	return CombatWorld.of(SystemWorld.home(get_tree())).warlords


func _escorts(w: WarlordShip) -> int:
	var n := 0
	for s in SystemWorld.nodes_in(w, Ship.GROUP):
		var e := s as ScavengerShip
		if e and not e.dead and not e is WarlordShip and e.ai and e.ai.guard == w:
			n += 1
	return n


## With a window and "-- --shot=/abs/dir": the flagship close up, saved as <dir>/warlord.png.
func _shot(w: WarlordShip) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			var hud := Tutorial.of(get_tree()).hud
			hud.camera.focus_on(w, 200.0, true)
			hud.camera.set_pitch(22.0)
			for i in 60:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--shot=").path_join("warlord.png"))


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
	var d := _dir()
	_ok(d != null and d.enabled, "director at home")
	d.next_at = SimClock.time
	SimStepper.run(tree, 2.0)
	_ok(d.phase == WarlordDirector.Phase.WARNED and not d.warlord_name.is_empty(), "warned: %s, %s" % [d.warlord_name, d.title])
	SimStepper.run(tree, WarlordDirector.WARN_TIME + 2.0)
	var w := d.ship
	_ok(d.phase == WarlordDirector.Phase.PRESENT and is_instance_valid(w), "arrived")
	if not is_instance_valid(w):
		tree.quit(1)
		return
	print("WARLORD flagship: %s hull %.0f shields %.0f dmg %.1f, %d escorts, %.1f km from home" % [w.get_display_name(), w.durability.max_hull,
			w.durability.max_shields, w.stats.weapon_damage, _escorts(w), w.global_position.length() / 1000.0])
	_ok(w.durability.max_hull > 2000.0, "flagship hull scaled")
	_ok(_escorts(w) == WarlordDirector.BASE_ESCORTS, "escorts guard the flagship (%d)" % _escorts(w))
	SimStepper.run(tree, 30.0)
	await _shot(w)
	_ok(w.ai and w.ai.state == ScavengerBrain.State.RAIDING, "flagship raids (%s)" % (w.get_status_text()))
	# Save round trip.
	var name := d.warlord_name
	var data := GameSnapshot.capture(tree)
	await SaveManager.load_snapshot(data)
	for i in 3:
		await tree.process_frame
	d = _dir()
	w = d.ship
	_ok(d.phase == WarlordDirector.Phase.PRESENT and is_instance_valid(w) and w.warlord_name == name, "save round trip keeps the warlord")
	_ok(is_instance_valid(w) and _escorts(w) == WarlordDirector.BASE_ESCORTS, "escorts still guard it after the load")
	_ok(is_instance_valid(w) and w.durability.max_hull > 2000.0, "flagship hull after the load")
	# Retreat.
	w.take_hit(w.durability.max_shields + w.durability.max_hull * 0.75, null, w.global_position)
	SimStepper.run(tree, 2.0)
	_ok(w.leaving(), "breaks off below %.0f%%" % (WarlordShip.RETREAT_HULL * 100.0))
	SimStepper.run(tree, WarlordShip.RETREAT_MAX + 5.0)
	_ok(d.phase == WarlordDirector.Phase.AWAY and d.ship == null, "warped out, away")
	d.return_at = SimClock.time
	SimStepper.run(tree, 2.0 + WarlordDirector.WARN_TIME + 2.0)
	w = d.ship
	_ok(d.phase == WarlordDirector.Phase.PRESENT and is_instance_valid(w) and w.visit == 2, "came back (visit 2)")
	_ok(is_instance_valid(w) and _escorts(w) == WarlordDirector.BASE_ESCORTS + 1, "one escort more (%d)" % (_escorts(w) if is_instance_valid(w) else -1))
	# Kill.
	var cr := Economy.credits
	w.take_hit(w.durability.max_shields + w.durability.max_hull * 2.0, null, w.global_position)
	SimStepper.run(tree, 2.0)
	_ok(w.dead and d.ship == null, "flagship destroyed")
	_ok(Economy.credits >= cr + WarlordDirector.REWARD + WarlordDirector.REWARD_STEP, "reward paid (+%d)" % (Economy.credits - cr))
	_ok(d.phase == WarlordDirector.Phase.WAITING and d.next_at > SimClock.time, "next warlord scheduled")
	tree.quit(0 if _fails.is_empty() else 1)

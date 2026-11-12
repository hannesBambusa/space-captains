extends Node
## Headless check of remote work ([RemoteWork]): a mining contract on a
## cluster in Ostra (no station there), a miner hired at home flies out
## through Ostra Gate, mines, comes home with the load and delivers it; a
## save round trip while the job runs keeps the held system and the
## contract. Prints "REMOTE ..." lines; exit 1 on a failed check.
## Run: Godot --headless --path . res://tools/remote_work_test.tscn

var _fails: PackedStringArray = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.autosave_interval = 1e12
	Tutorial.write_settings = false
	_run.call_deferred()


func _ok(cond: bool, what: String) -> void:
	print("REMOTE %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails.append(what)


func _until(test: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if test.call():
			return true
		await get_tree().process_frame
	return test.call()


func _nearest_belt(w: SystemWorld) -> AsteroidCluster:
	var best: AsteroidCluster = null
	for b in w.sys.belts:
		if not b.is_depleted and (best == null or b.global_position.length() < best.global_position.length()):
			best = b
	return best


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
	var hud := Tutorial.of(tree).hud
	hud.tutorial.finish()
	var vm := hud.view_manager
	Economy.add(20000, PackedInt32Array(), Ledger.OTHER, "Test credits")
	# A mining outpost and a miner at home.
	var mgr := hud.manager
	var def := mgr.def_by_id(&"mining_outpost")
	var b: Building = null
	for ring in range(1, 12):
		for k in 16:
			var off := Vector3(cos(TAU * k / 16.0), 0.0, sin(TAU * k / 16.0)) * (260.0 + ring * 90.0)
			if b == null and mgr.plan_placement(def, off, false).is_valid():
				b = mgr.spawn_finished(def, off)
	var s: Ship = b.hire() if b else null
	_ok(s != null and s is MinerShip, "miner hired at home")
	# Ostra live, its cluster charted, a generous contract on it.
	var w := vm.pin(&"s1")
	vm.unpin(&"s1")
	_ok(w != null and not w.has_station, "Ostra live, no station")
	var belt := _nearest_belt(w) if w else null
	_ok(belt != null, "a cluster in Ostra")
	if belt == null or s == null:
		tree.quit(1)
		return
	Sector.reveal(&"s1", PackedStringArray([belt.def.name]))
	_ok(RemoteWork.post_block(belt).is_empty(), "posting allowed")
	var mc := ContractBoard.post_mining(belt, 400)
	_ok(mc != null and mc.system_id == &"s1", "remote contract posted in %s" % (mc.system_id if mc else "-"))
	await tree.process_frame
	vm.remote_work.refresh()
	_ok(RemoteWork.is_held(tree, &"s1") and vm.is_pinned(&"s1"), "Ostra held live for the work")
	var c := s.captain
	var listed := RemoteWork.contracts_for(s.brain)
	_ok(listed.has(mc), "the docked miner sees the remote contract")
	SimClock.set_speed(24.0)
	var out := await _until(func() -> bool: return is_instance_valid(c.ship) and SystemWorld.of(c.ship) == w, 120.0)
	_ok(out, "miner flew out to Ostra (%s)" % (c.ship.brain.last_decision if is_instance_valid(c.ship) and c.ship.brain else "?"))
	var mining := await _until(func() -> bool:
		return is_instance_valid(c.ship) and c.ship.brain and c.ship.brain.state == CaptainBrain.State.MINING, 90.0)
	_ok(mining, "mining in Ostra")
	# Save round trip mid-job.
	var data := GameSnapshot.capture(tree)
	_ok(data.get("forward", {}).has("s1") and bool(data["forward"]["s1"].get("remote_work", false)), "Ostra saved as a remote-work part")
	await SaveManager.load_snapshot(data)
	for i in 5:
		await tree.process_frame
	SimClock.set_speed(24.0)
	hud = Tutorial.of(tree).hud
	vm = hud.view_manager
	vm.remote_work.refresh()
	var mc2: MiningContract = null
	for x in ContractBoard.get_listed(Corps.PLAYER):
		if x is MiningContract and x.system_id == &"s1":
			mc2 = x
	_ok(mc2 != null and is_instance_valid(mc2.belt), "remote contract back after the load")
	_ok(RemoteWork.is_held(tree, &"s1") and vm.is_pinned(&"s1"), "Ostra held again after the load")
	var cap: Captain = null
	for n in SystemWorld.nodes_in(vm.world(&"s1"), Ship.GROUP):
		if n is MinerShip and (n as Ship).captain:
			cap = (n as Ship).captain
	if cap == null:
		for n in tree.get_nodes_in_group(Ship.GROUP):
			if n is MinerShip and (n as Ship).captain:
				cap = (n as Ship).captain
	_ok(cap != null, "the miner is back after the load (%s)" % (SystemWorld.of(cap.ship).system_id if cap and is_instance_valid(cap.ship) else "-"))
	if cap == null or mc2 == null:
		tree.quit(1)
		return
	var ore0 := mc2.materials_delivered
	var home := await _until(func() -> bool: return mc2.materials_delivered > ore0, 300.0)
	_ok(home, "the load came home through the gates (%d delivered)" % mc2.materials_delivered)
	print("REMOTE miner: %s, %s" % [cap.ship.brain.last_decision if is_instance_valid(cap.ship) and cap.ship.brain else "-",
			PilotCard.status_text(cap, cap.ship if is_instance_valid(cap.ship) else null)])
	ContractBoard.cancel(mc2, true)
	await _bounty_leg(tree)
	SimClock.set_speed(1.0)
	tree.quit(0 if _fails.is_empty() else 1)


## A lone raider in Ostra with a bounty on it; a mercenary hired at home
## flies out through the gate and hunts it there.
func _bounty_leg(tree: SceneTree) -> void:
	var hud := Tutorial.of(tree).hud
	var vm := hud.view_manager
	var w := vm.world(&"s1")
	var mgr := hud.manager
	var def := mgr.def_by_id(&"mercenary_outpost")
	var mo: Building = null
	for ring in range(1, 14):
		for k in 16:
			var off := Vector3(cos(TAU * k / 16.0), 0.0, sin(TAU * k / 16.0)) * (300.0 + ring * 110.0)
			if mo == null and mgr.plan_placement(def, off, false).is_valid():
				mo = mgr.spawn_finished(def, off)
	var m: Ship = mo.hire() if mo else null
	_ok(m != null and m is MercenaryShip, "mercenary hired at home")
	if m == null or w == null:
		return
	var belt := _nearest_belt(w)
	var r := ScavengerShip.new()
	r.setup_scavenger(null, "Lone-1", false, Factions.scavengers())
	SpaceNav.space_root(w).add_child(r)
	r.global_position = (belt.global_position if belt else Vector3(8000, 0, 0)) + Vector3(600, 0, 0)
	r.mover.avoid_enabled = true
	if r.ai and belt:
		r.ai.set_guard(belt, 1500.0)
	w.combat.notify_spawned(r)
	var bc := ContractBoard.post_bounty(r, 900, 1)
	_ok(bc != null and bc.system_id == &"s1", "remote bounty posted")
	vm.remote_work.refresh()
	var c := m.captain
	var out := await _until(func() -> bool: return is_instance_valid(c.ship) and SystemWorld.of(c.ship) == w, 120.0)
	_ok(out, "mercenary flew out to Ostra (%s)" % (c.ship.brain.last_decision if is_instance_valid(c.ship) and c.ship.brain else "?"))
	var hunting := await _until(func() -> bool:
		return is_instance_valid(c.ship) and c.ship.brain and c.ship.brain.state == CaptainBrain.State.HUNTING and SystemWorld.of(c.ship) == w, 60.0)
	_ok(hunting, "hunting the raider in Ostra")
	var done := await _until(func() -> bool: return not Combat.is_live(r), 240.0)
	_ok(done, "raider shot down")
	var back := await _until(func() -> bool: return is_instance_valid(c.ship) and SystemWorld.of(c.ship) == SystemWorld.home(tree), 240.0)
	_ok(back, "mercenary came home through the gates")

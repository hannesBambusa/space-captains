extends Node
## Headless smoke test (tools/smoke.sh). Starts a new game in its own scene,
## builds a finished Mining Outpost and a Mercenary Outpost, hires two miners
## and a merc, posts a mining contract on the nearest cluster, then
## fast-forwards the sim ([SimStepper], 60 s per frame) and prints one
## summary block. Seeded RNGs (global and every node's
## RandomNumberGenerator once it is ready), so runs are close to repeatable.
## Never saves (autosave off, no slot written). Quits with 1 when a script
## error was logged during the run, or when the run stalls (a script error
## stops the run coroutine; [constant STALL_TIME] real seconds after it, or
## [constant MAX_REAL_TIME] in all, it reports what it has and quits).
## Args after "--": --minutes=N (default 10); --multi also switches the view
## (s1, s2, home, a few times, live systems dropped after) and sends one
## mercenary through Ostra Gate and back (GateTransit.debug_round_trip),
## then prints a "SMOKE multi" block. --explore (P3) instead fixes the
## network seed, researches Jump navigation, builds an Explorer Outpost,
## hires a Bold, a Cautious and a Greedy explorer, posts an explore contract
## on Ostra Gate at fair pay and runs until the survey is paid (at most
## [constant EXPLORE_MAX] sim seconds), then prints a "SMOKE explore" block.
## --long (P4): at least [constant LONG_MINUTES] sim minutes on the fixed
## network seed [constant LONG_SEED] (systems two jumps out that can raid
## home), then a "SMOKE long" block with the gate raids (GateRaidSource).
## --forward (F1): at minute 1 a forward station on Ostra (s1,
## ForwardStations.debug_found), a Mining Outpost there, two miners and a
## mining contract on the s1 cluster nearest it; the view stays home. The
## run steps every world itself to time them (ms per 0.1 s step, home vs
## forward), then a few real frames; prints a "SMOKE forward" block, with
## the forward miners' states and deaths and a check that no captain works
## another system's contract (fails the run). The network seed is fixed
## ([constant FORWARD_SEED]: a near cluster, no bases in the way).
## --forward --save-roundtrip (F3): at minute [constant ROUNDTRIP_MINUTE]
## GameSnapshot.capture to memory (through var_to_bytes like a save file),
## SaveManager.load_snapshot (the load path, no file), then the rest of the
## run; buildings, captains and contracts per system must match, forward ore
## must keep rising (fails the run otherwise).
## --forward --long (F4): [constant FORWARD_LONG_MINUTES]+ sim minutes on
## [constant FORWARD_LONG_SEED] (Ostra with a base), plus a Mercenary
## Outpost and a merc there and a defence zone over the station; at
## minute [constant FORWARD_REFILL_MINUTE] water is topped up when the
## station ran dry. Prints the forward raids (after the grace),
## alarms, zone fights, upkeep, water, the hauling fee, berths after deaths
## (forward and home) and the station's feed lines. Every --forward run
## gets [constant FORWARD_WATER] water at the founding.
## --colony (F6, with or without --forward): no debug founding. Forward
## operations researched by script, Ostra and a second target charted, two
## mercenaries, then two Forward Stations built at home one after the
## other: the first flies to an Ostra planet with Ostra viewed (live), the
## second to the other target with the view at home (as data, the ambush
## rolls). Saves to memory and reloads while parked, while waiting for an
## escort and in transit. Prints the build, wait, flight and found times,
## the hops, the escort and convoy feed lines, the stations live; fails
## when one is not founded or a reload changed the convoy. Station 1 is
## attacked at home on its way out ([constant COLONY_RAIDERS] raiders):
## fails when its escorts never fight them; any mobile station spooling a
## warp longer than [constant COLONY_SPOOL_MAX] fails the run too.
## Every run fails when a base has more ships out than its spawn cap;
## --forward also checks that a forward Factory shares home's keep-at-least
## and held ore (installed for a moment at the end).
## The default run never touches them.

const SEED := 12345
## --explore: the gate network seed and the longest run, sim seconds.
const EXPLORE_SEED := 4242
const EXPLORE_MAX := 2400.0
## --long: the network seed and the shortest run, sim minutes.
const LONG_SEED := 3
const LONG_MINUTES := 40.0
## --forward --save-roundtrip: the sim minute the game is saved to memory
## and loaded back.
const ROUNDTRIP_MINUTE := 5
## --forward: the network seed (--net-seed=N overrides it, for sweeps).
const FORWARD_SEED := 24
## --forward --long: the network seed (a base in Ostra) and the shortest run.
const FORWARD_LONG_SEED := 7
const FORWARD_LONG_MINUTES := 26.0
## The forward feed lines the report keeps (threat, supply, losses).
const FW_FEED_WORDS: PackedStringArray = ["aid", "water", "Upkeep", "under attack", "entered", "was lost", "ejected", "fleeing", "destroyed"]
## Water given at the founding, and the minute a dry station gets more (--long).
const FORWARD_WATER := 40
const FORWARD_REFILL_MINUTE := 20
const STALL_TIME := 3.0
const MAX_REAL_TIME := 300.0

var minutes: float = 10.0
var multi := false
var explore := false
var long_run := false
var forward := false
## --miners=N: N miners on the nearest iron cluster at fair pay, iron set to
## 0 at the start, the station's iron printed every half minute (how long a
## building's iron takes to mine).
var miners := 0
var _iron_t0 := -1.0
var _iron_hits := {}
## --surface: a planet outpost founded at minute 0 on the best home world,
## a bay, a garrison, 2 harvesters, 2 soldiers, contracts on every deposit;
## the surface is viewed live from minute 2 to 4, data the rest.
var surface := false
var _sf: OutpostState
var _sf_reload_bad := false
var _sf_gas: OutpostState
var save_roundtrip := false
var colony := false
## --rival: a rival corp (Normal) in the game (rival corporation plan).
var rival := false
## --rivals=N: N rivals (1 to 3; implies --rival).
var rival_count := 1
## --modifier=<id>: the run's sector modifier (Standard by default).
var modifier: StringName = SectorModifier.STANDARD
## --rival --war: contact at minute 2, war at minute 3, a player strike at 8.
var rival_war := false
## --rival --eliminate: war at minute 2, the rival HQ knocked out at 3: the
## scuttle must destroy it and the rival must be eliminated (victory).
var rival_kill := false
## --rival --expand: the rival has Forward operations, its charts and the
## money at minute 1; it must found a forward station.
var rival_expand := false
## --war: the system the player strike went to, and the minute it left.
var _strike_target: StringName = &""
var _strike_minute := -1
## --rival --lab: the rival gets a finished Science Lab and money at minute 1.
var rival_lab := false
var _kill_log: PackedStringArray = []
var _war_log: PackedStringArray = []
var _station_low := 1.0
## --rival --save-roundtrip: save and reload at this minute.
const RIVAL_ROUNDTRIP_MINUTE := 8
var _rival_rt := ""
var _rival_rt_note := ""
var _rival_rt_ok := true
var net_seed := -1
var _multi: PackedStringArray = []
## --rival: per rival id, the money and ore flows ([method _rival_flow_sample]).
var _flow := {}
## Corp id -> {raids, lost, dead}: pirate raids launched at its station
## systems and its ships pirates destroyed (captains lost with them), live.
var _pirate := {}
## --rival: rival 1's world built from data and dropped back ([method _rival_trip_step]).
var _trip_log: PackedStringArray = []
## --war: the player strike found its target system live (it was data).
var _strike_live_seen := false
var _strike_was_data := false

var _seeded := 0
var _raids: PackedStringArray = []
var _cargo_n := 0
var _cargo_ore := 0
var _payouts := 0
var _finished := 0
var _log: SmokeLogger
## The home system's parts. Found by group so the test also runs on older
## code (before SystemWorld); with SystemWorld, the home system's members.
var _root: Node
var _sys: SolarSystem
var _mgr: BuildingManager
var _combat: CombatWorld
var _start_time := 0.0
var _done := false
var _stall := 0.0
var _real := 0.0


class SmokeLogger extends Logger:
	var errors := 0
	var warnings := 0
	var script_errors := 0
	var first: PackedStringArray = []
	var _lock := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_lock.lock()
		if error_type == ERROR_TYPE_WARNING:
			warnings += 1
		else:
			errors += 1
			if error_type == ERROR_TYPE_SCRIPT:
				script_errors += 1
		if first.size() < 5:
			first.append("%s (%s:%d %s)" % [rationale if not rationale.is_empty() else code, file, line, function])
		_lock.unlock()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.autosave_interval = 1e12
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--minutes="):
			minutes = maxf(a.trim_prefix("--minutes=").to_float(), 0.1)
		elif a == "--multi":
			multi = true
		elif a == "--explore":
			explore = true
		elif a == "--long":
			long_run = true
		elif a == "--forward":
			forward = true
		elif a.begins_with("--miners="):
			miners = clampi(a.trim_prefix("--miners=").to_int(), 1, 4)
		elif a == "--surface":
			surface = true
		elif a == "--save-roundtrip":
			save_roundtrip = true
		elif a == "--colony":
			colony = true
		elif a.begins_with("--net-seed="):
			net_seed = a.trim_prefix("--net-seed=").to_int()
		elif a == "--rival":
			rival = true
		elif a.begins_with("--rivals="):
			rival = true
			rival_count = clampi(a.trim_prefix("--rivals=").to_int(), 1, 3)
		elif a == "--war":
			rival_war = true
		elif a == "--eliminate":
			rival_kill = true
		elif a == "--expand":
			rival_expand = true
		elif a == "--lab":
			rival_lab = true
		elif a.begins_with("--modifier="):
			# A sector modifier for this run (SectorModifier id, or "random").
			modifier = StringName(a.trim_prefix("--modifier="))
		elif a == "--rival-live":
			# The rival station worlds stay pinned live (the data sim off), to compare.
			RivalWorlds.data_enabled = false
	# Never the player's menu setting: Off unless --rival (Normal).
	Corps.next_difficulty = CorpRegistry.Difficulty.NORMAL if rival else CorpRegistry.Difficulty.OFF
	Corps.next_rival_count = rival_count
	# Never the player's menu setting either: Standard unless --modifier=.
	Sector.next_modifier = modifier
	_log = SmokeLogger.new()
	OS.add_logger(_log)
	seed(SEED)
	get_tree().node_added.connect(_on_node_added)
	_run.call_deferred()


func _on_node_added(n: Node) -> void:
	if not n.ready.is_connected(_seed_rngs):
		n.ready.connect(_seed_rngs.bind(n), CONNECT_ONE_SHOT)
	if n is RaidDirector:
		(n as RaidDirector).raid_started.connect(func(den: ScavengerDen, _size: int) -> void:
			var w := SystemWorld.of(den) if is_instance_valid(den) else null
			if w and not w.corp_id.is_empty():
				_pirate_stats(w.corp_id)["raids"] += 1)
	elif n is Ship and not (n as Ship).destroyed.is_connected(_on_ship_lost):
		(n as Ship).destroyed.connect(_on_ship_lost)


func _pirate_stats(corp: StringName) -> Dictionary:
	return _pirate.get_or_add(corp, {"raids": 0, "lost": 0, "dead": 0})


## A hired ship pirates destroyed (see [member _pirate]).
func _on_ship_lost(ship: Ship, killer: Node3D) -> void:
	if ship.captain == null or not (killer is ScavengerShip or killer is ScavengerDen):
		return
	var corp := Combat.corp_of_faction(ship.get_faction())
	if corp.is_empty():
		return
	var p := _pirate_stats(corp)
	p["lost"] += 1
	if not ship.captain.alive:
		p["dead"] += 1


## Reseeds the node's RandomNumberGenerator members after its _ready
## randomized them.
func _seed_rngs(n: Node) -> void:
	if not is_instance_valid(n) or n.get_script() == null:
		return
	for p in (n.get_script() as Script).get_script_property_list():
		if p["type"] != TYPE_OBJECT:
			continue
		var v: Variant = n.get(p["name"])
		if v is RandomNumberGenerator:
			_seeded += 1
			(v as RandomNumberGenerator).seed = SEED + _seeded * 7919


func _run() -> void:
	var tree := get_tree()
	var t0 := Time.get_ticks_msec()
	# SaveManager frees the current scene first: give it a dummy.
	var dummy := Node.new()
	dummy.name = "SmokeDummy"
	tree.root.add_child(dummy)
	tree.current_scene = dummy
	await SaveManager.new_game()
	for i in 5:
		await tree.process_frame
	_find_home()
	if _mgr == null or _sys == null:
		print("SMOKE FAIL: no home system")
		tree.quit(1)
		return
	if colony:
		Sector.start(net_seed if net_seed >= 0 else FORWARD_SEED)
		_setup()
		var why_c := await _colony_run()
		_colony_print()
		_finish(Time.get_ticks_msec() - t0, why_c)
		return
	if forward:
		Sector.start(net_seed if net_seed >= 0 else FORWARD_LONG_SEED if long_run else FORWARD_SEED)
		if long_run:
			minutes = maxf(minutes, FORWARD_LONG_MINUTES)
	elif long_run:
		Sector.start(LONG_SEED)
		minutes = maxf(minutes, LONG_MINUTES)
	_setup()
	Economy.cargo_received.connect(func(ore: PackedInt32Array, _s: String) -> void:
		_cargo_n += 1
		for x in ore:
			_cargo_ore += x)
	ContractBoard.payout_made.connect(func(_c: Contract, _s: Node, _cr: int) -> void: _payouts += 1)
	ContractBoard.delivery_made.connect(func(_c: Contract, _s: Node, _cr: int, _m: int, _o: int) -> void: _payouts += 1)
	ContractBoard.contract_removed.connect(func(c: Contract) -> void:
		if c.is_finished():
			_finished += 1)
	var raids := _combat.raids if _combat else null
	if raids:
		raids.raid_started.connect(func(_d: Node, size: int) -> void: _raids.append("%s x%d" % [Fmt.clock(SimClock.time), size]))
	_start_time = SimClock.time
	if explore:
		await _explore_run()
		_finish(Time.get_ticks_msec() - t0)
		return
	var left := minutes * 60.0
	var minute := 0
	while left > 0.0:
		if multi:
			_multi_step(minute)
		if rival and save_roundtrip and minute == RIVAL_ROUNDTRIP_MINUTE:
			await _rival_roundtrip()
		if rival:
			_rival_flow_sample()
			if not rival_kill:
				_rival_trip_step(minute)
		if rival_war:
			_war_step(minute)
		if rival_kill:
			_kill_step(minute)
		if rival_expand and minute == 1:
			_expand_setup()
		if surface:
			await _surface_step(minute)
		if miners > 0:
			for half in 2:
				left -= SimStepper.run(tree, minf(30.0, left))
				_iron_watch()
			minute += 1
			await tree.process_frame
			continue
		if rival_lab and minute == 1:
			var lr := Corps.rivals[0]
			RivalWorlds.of(tree).materialise_corp(lr.id)
			var lw := Corps.hq_world(get_tree(), lr.id)
			lr.economy.add(5000, Economy.cost(500, 100), Ledger.OTHER, "Smoke money")
			lw.buildings.spawn_finished(lw.buildings.def_by_id(&"science_lab"), Vector3.ZERO)
		if forward:
			if save_roundtrip and minute == ROUNDTRIP_MINUTE:
				await _forward_roundtrip()
			if minute == 1:
				_forward_setup()
				for i in 5:
					await tree.process_frame
				_forward_hire()
			if long_run and minute == FORWARD_REFILL_MINUTE:
				_forward_refill()
			left -= _forward_run(minf(60.0, left))
		else:
			left -= SimStepper.run(tree, minf(60.0, left))
		minute += 1
		await tree.process_frame
	if multi:
		_multi_report()
	if forward:
		await _forward_report()
	if long_run and not forward:
		_long_report()
	if rival:
		_rival_report()
	if miners > 0:
		for goal in [50, 60, 75, 100, 150]:
			print("SMOKE iron reached %3d at %s" % [goal, Fmt.clock(float(_iron_hits[goal])) if _iron_hits.has(goal) else "never"])
	var sf_why := _surface_report() if surface else ""
	var why := "%d trip checks on another system's contract" % _fw_wrong if _fw_wrong > 0 else ""
	if _fw_factory_bad:
		why = "a forward Factory keeps its own reserve or held ore (see SMOKE forward factory)"
	if save_roundtrip and not _rt_ok:
		why = "save round trip changed the game (see SMOKE forward reload)"
	if rival and not _rival_rt_ok:
		why = "save round trip changed the game (see SMOKE rival reload)"
	if rival and not Corps.has_rival():
		why = "no rival corp"
	if not sf_why.is_empty():
		why = sf_why
	_finish(Time.get_ticks_msec() - t0, why)


func _finish(ms: int, why: String = "") -> void:
	if _done:
		return
	_done = true
	var over := _bases_over_cap()
	if is_instance_valid(_mgr):
		_report(SimClock.time - _start_time, ms)
		print("SMOKE bases over cap %s" % (", ".join(over) if not over.is_empty() else "none"))
	if why.is_empty() and not over.is_empty():
		why = "bases with more ships out than their cap: %s" % ", ".join(over)
	if not why.is_empty():
		print("SMOKE FAIL: %s" % why)
	get_tree().quit(1 if _log.script_errors > 0 or not why.is_empty() else 0)


## Bases (live, and as data in systems not live) with more ships out than
## their spawn cap ("7/4 out").
func _bases_over_cap() -> PackedStringArray:
	var out: PackedStringArray = []
	var tree := get_tree()
	for n in tree.get_nodes_in_group(ScavengerDen.GROUP):
		var d := n as ScavengerDen
		if d and not d.dead and d.def and d.spawns.size() > d.def.spawn_cap:
			out.append("%s %d/%d" % [d.get_display_name(), d.spawns.size(), d.def.spawn_cap])
	var vm := ViewManager.of(tree)
	for id: StringName in Sector.states:
		var def := Sector.system_def(id)
		if def == null or (vm and vm.is_live(id)):
			continue
		var st := Sector.states[id] as RemoteSystemState
		for ddef in def.dens:
			var dd: Dictionary = st.dens.get(ddef.name, {})
			if dd.is_empty() or bool(dd.get("dead", false)):
				continue
			var n_out := RemoteSim.den_out(st, dd)
			if n_out > ddef.spawn_cap:
				out.append("%s (data) %d/%d" % [ddef.name, n_out, ddef.spawn_cap])
	return out


## Watchdog: a script error ends the run coroutine without a report.
func _process(delta: float) -> void:
	_real += delta
	if _done:
		return
	if _log.script_errors > 0:
		_stall += delta
	if _stall > STALL_TIME:
		_finish(int(_real * 1000.0), "run stopped after a script error")
	elif _real > MAX_REAL_TIME * (2.0 if colony else 1.0):
		_finish(int(_real * 1000.0), "timed out after %.0f s" % (MAX_REAL_TIME * (2.0 if colony else 1.0)))


## Outposts, crews and a mining contract so the run has traffic.
func _find_home() -> void:
	var tree := get_tree()
	var w: Node = tree.get_first_node_in_group("system_world")
	if w:
		_sys = w.get("sys")
		_mgr = w.get("buildings")
		_combat = w.get("combat")
	else:
		_sys = tree.get_first_node_in_group(SolarSystem.GROUP) as SolarSystem
		_mgr = tree.get_first_node_in_group(BuildingManager.GROUP) as BuildingManager
		_combat = tree.get_first_node_in_group(CombatWorld.GROUP) as CombatWorld
	_root = _sys.get_parent() if _sys else null


func _setup() -> void:
	var mgr := _mgr
	Economy.add(20000, PackedInt32Array(), Ledger.OTHER, "Smoke test credits")
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for id: StringName in [&"mining_outpost", &"mercenary_outpost"]:
		var def := mgr.def_by_id(id)
		var b := _spawn_near_station(mgr, def) if def else null
		if b == null:
			print("SMOKE setup: could not place %s" % id)
			continue
		b.captain_rng = rng
		for i in ((miners if miners > 0 else 2) if id == &"mining_outpost" else 1):
			b.hire()
	var sys := _sys
	var station := sys.home_station.global_position if sys and sys.home_station else Vector3.ZERO
	var best: AsteroidCluster = null
	for c in sys.belts if sys else []:
		if best == null or c.global_position.distance_to(station) < best.global_position.distance_to(station):
			best = c
	if miners > 0:
		best = null
		for c in sys.belts if sys else []:
			if c.ore_type == AsteroidBelt.OreType.IRON and (best == null or c.global_position.distance_to(station) < best.global_position.distance_to(station)):
				best = c
		Economy.ore[Economy.Ore.IRON] = 0
		_iron_t0 = SimClock.time
		print("SMOKE iron test    %d miners on %s, %.1f km from the station, pay 60 a load" % [miners, best.def.name if best else "-", best.global_position.distance_to(station) / 1000.0 if best else 0.0])
		if best:
			ContractBoard.post_mining(best, 60)
		return
	if best:
		ContractBoard.post_mining(best, 40)


## --miners: the station's iron and when it first reached 60, 100 and 150.
func _iron_watch() -> void:
	var iron := Economy.ore[Economy.Ore.IRON]
	for goal in [50, 60, 75, 100, 150]:
		if iron >= goal and not _iron_hits.has(goal):
			_iron_hits[goal] = SimClock.time - _iron_t0
	print("SMOKE iron %5s    %d iron" % [Fmt.clock(SimClock.time - _iron_t0), iron])


func _spawn_near_station(mgr: BuildingManager, def: BuildingDef) -> Building:
	for ring in range(1, 12):
		var r := 260.0 + ring * 90.0
		for k in 16:
			var a := TAU * float(k) / 16.0
			var off := Vector3(cos(a) * r, 0.0, sin(a) * r)
			if mgr.plan_placement(def, off, false).is_valid():
				return mgr.spawn_finished(def, off)
	return null


var _merc: Captain
var _merc_wallet := 0
var _nodes0 := 0


## --multi: minute 1 sends the merc, 2..5 switch the view, 6 drops the live
## remote systems.
func _multi_step(minute: int) -> void:
	var vm := ViewManager.of(get_tree())
	if vm == null:
		return
	match minute:
		1:
			_nodes0 = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
			var s := GateTransit.debug_round_trip(get_tree(), "Ostra Gate", 30.0)
			if s:
				_merc = s.captain
				_merc_wallet = _merc.wallet
			_multi.append("merc sent: %s" % (_merc.captain_name if _merc else "none"))
		2, 3, 4, 5:
			var id: StringName = [&"s1", &"s2", &"s1", &"home"][minute - 2]
			vm.debug_view_all = true
			vm.view_now(id)
			_multi.append("view %s (%s ms)" % [id, vm.build_ms(id) if id != &"home" else 0])
		6:
			for id in vm.worlds.keys():
				if id != ClusterNetwork.HOME_ID:
					vm.dematerialise(id)


func _multi_report() -> void:
	var vm := ViewManager.of(get_tree())
	print("SMOKE multi ---------------------------------------")
	print("SMOKE multi steps   %s" % ", ".join(_multi))
	print("SMOKE multi view    %s, live %s, nodes %d at minute 1 -> %d" % [vm.viewed_id() if vm else &"?", vm.worlds.keys() if vm else [], _nodes0,
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	if _merc:
		var s := _merc.ship if is_instance_valid(_merc.ship) else null
		var where := String(SystemWorld.of(s).system_id) if s else "data: " + _merc.away_in
		print("SMOKE multi merc    %s in %s, %s, wallet %d -> %d, rank %d" % [_merc.captain_name, where, s.get_status_text() if s else "-",
				_merc_wallet, _merc.wallet, _merc.rank])


## --long: the gate raids of the run.
func _long_report() -> void:
	var g := _combat.gate_raids if _combat else null
	print("SMOKE long ----------------------------------------")
	if g == null:
		print("SMOKE long gate raids: no GateRaidSource")
		return
	var src: PackedStringArray = []
	for c in g.candidates():
		src.append("%s (danger %d, %d jumps, via %s)" % [Sector.system_def(c["id"]).system_name, int(c["danger"]), int(c["jumps"]), c["gate"]])
	print("SMOKE long seed      %d, sources: %s" % [LONG_SEED, ", ".join(src) if not src.is_empty() else "-"])
	print("SMOKE long gate raids %s" % g.summary())


# --- Forward station (F1) ----------------------------------------------------

const FORWARD_ID := &"s1"
var _fw: SystemWorld
var _fw_factory_bad := false
var _fw_outpost: Building
var _fw_notes: PackedStringArray = []
var _fw_miners: Array[Ship] = []
var _fw_deaths: PackedStringArray = []
## Trip checks per system, and the ones on another system's contract.
var _fw_trips := {}
var _fw_wrong := 0
var _fw_wrong_first := ""
## Stepping time per bucket ("home", "forward", "other"), usec, and steps.
var _fw_usec := {}
var _fw_steps := 0
## F4: forward raids launched, alarm sites seen, feed lines of the station
## system, the zone, the most raiders seen in it, the merc.
var _fw_raids: PackedStringArray = []
var _fw_alarms := {}
var _fw_feed: PackedStringArray = []
var _fw_zone: DefenseZone
var _fw_zone_peak := 0
var _fw_merc: Ship
var _fw_refill := ""


func _forward_setup() -> void:
	_fw = ForwardStations.debug_found(get_tree(), FORWARD_ID)
	if _fw == null:
		_fw_notes.append("found failed")
		return
	var site := _fw.station_site
	_fw_notes.append("seed %d, founded %s on %s at %s" % [Sector.get_seed(), site.get("name", "?"), site.get("planet", "?"), Fmt.clock(SimClock.time)])
	Economy.add(0, PackedInt32Array([0, 0, 0, 0, FORWARD_WATER]), Ledger.OTHER, "Smoke test water")
	_fw_bind()
	EventLog.posted.connect(func(e: Dictionary) -> void:
		var tr := e.get("target") as WeakRef
		var t := tr.get_ref() as Node if tr else null
		var text := String(e.get("text", ""))
		if is_instance_valid(t) and is_instance_valid(_fw) and SystemWorld.of(t) == _fw and _fw_keeps(text):
			_fw_feed.append("%s %s" % [Fmt.clock(SimClock.time), text]))


func _fw_keeps(text: String) -> bool:
	for w in FW_FEED_WORDS:
		if text.contains(w):
			return true
	return false


## Signal links to the forward world (again after a reload).
func _fw_bind() -> void:
	var raids := _fw.combat.raids if is_instance_valid(_fw) and _fw.combat else null
	if raids:
		raids.raid_started.connect(func(_d: Node, size: int) -> void: _fw_raids.append("%s x%d" % [Fmt.clock(SimClock.time), size]))


## --long: a dry station gets water again (the restored line).
func _forward_refill() -> void:
	var sup := _fw.supply if is_instance_valid(_fw) else null
	if sup == null or not sup.dry:
		_fw_refill = "not dry at %s, no refill" % Fmt.clock(SimClock.time)
		return
	Economy.add(0, PackedInt32Array([0, 0, 0, 0, 30]), Ledger.OTHER, "Smoke test water")
	_fw_refill = "dry at %s: +30 water" % Fmt.clock(SimClock.time)


func _forward_hire() -> void:
	var mgr := _fw.buildings if _fw else null
	if mgr == null or not mgr.has_zone():
		_fw_notes.append("no forward BuildingManager")
		return
	var def := mgr.def_by_id(&"mining_outpost")
	_fw_outpost = _spawn_near_station(mgr, def) if def else null
	if _fw_outpost == null:
		_fw_notes.append("could not place the outpost")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 2
	_fw_outpost.captain_rng = rng
	var hired := 0
	for i in 2:
		var s := _fw_outpost.hire()
		if s:
			hired += 1
			_fw_miners.append(s)
			s.destroyed.connect(func(_s: Ship, killer: Node3D) -> void:
				_fw_deaths.append("%s at %s by %s" % [s.captain.captain_name if s.captain else "?", Fmt.clock(SimClock.time),
						killer.get_display_name() if killer is Ship else String(killer.name) if killer else "-"]))
	var sys := _fw.sys
	var station := sys.home_station.global_position
	var best: AsteroidCluster = null
	for c in sys.belts:
		if best == null or c.global_position.distance_to(station) < best.global_position.distance_to(station):
			best = c
	var mc := ContractBoard.post_mining(best, 40) if best else null
	_fw_notes.append("outpost %s, %d miners, contract %s (%s, %.1f km)" % [_fw_outpost.display_name, hired, mc.get_title() if mc else "none",
			mc.system_id if mc else &"-", best.global_position.distance_to(station) / 1000.0 if best else 0.0])
	if not long_run:
		return
	var md := mgr.def_by_id(&"mercenary_outpost")
	var mo := _spawn_near_station(mgr, md) if md else null
	if mo:
		mo.captain_rng = rng
		_fw_merc = mo.hire()
	var zones := _fw.combat.zones if _fw.combat else null
	if zones:
		_fw_zone = zones.place(station, 3000.0)
		if _fw_zone:
			zones.set_kill_bounty(_fw_zone, 50)
			zones.add_budget(_fw_zone, 500)
	_fw_notes.append("merc %s, zone %s" % [_fw_merc.captain.captain_name if _fw_merc else "none", _fw_zone.zone_name if _fw_zone else "none"])


## SimStepper.run with the time of each step split by system.
func _forward_run(seconds: float) -> float:
	var tree := get_tree()
	var home_vp := SystemWorld.home(tree).get_viewport()
	var fw_vp := _fw.get_viewport() if is_instance_valid(_fw) else null
	var done := 0.0
	while done < seconds:
		var h := minf(0.1, seconds - done)
		SimClock.advance(h)
		var t := Time.get_ticks_usec()
		for w in SystemWorld.all(tree):
			if w.sys:
				w.sys.update_bodies(SimClock.time)
		_fw_add("other", t)
		for g in [Ship.GROUP, SimStepper.GROUP]:
			for n in tree.get_nodes_in_group(g):
				if not is_instance_valid(n) or n.is_queued_for_deletion():
					continue
				t = Time.get_ticks_usec()
				n.call(&"sim_step", h)
				var vp := n.get_viewport() if n.is_inside_tree() else null
				_fw_add("home" if vp == home_vp else "forward" if vp == fw_vp and fw_vp else "other", t)
		_fw_steps += 1
		if _fw_steps % 10 == 0:
			_fw_check_systems()
			_fw_watch()
		done += h
	return done


## F2: a captain on a trip works a contract of its own system only.
func _fw_check_systems() -> void:
	for n in get_tree().get_nodes_in_group(Ship.GROUP):
		var s := n as Ship
		if s == null or s.dead or s.brain == null or not (s.brain is CaptainBrain) or s.transit:
			continue
		var tr := (s.brain as CaptainBrain).trip
		if tr == null or tr.contract == null or tr.contract is ExploreContract:
			continue
		var here := (s.brain as CaptainBrain).system_id()
		_fw_trips[here] = int(_fw_trips.get(here, 0)) + 1
		if tr.contract.system_id != here:
			_fw_wrong += 1
			if _fw_wrong_first.is_empty():
				_fw_wrong_first = "%s in %s on %s (%s)" % [s.get_display_name(), here, tr.contract.get_title(), tr.contract.system_id]


## F4: alarm sites and raiders in the zone, sampled.
func _fw_watch() -> void:
	var alarm := _fw.combat.alarm if is_instance_valid(_fw) and _fw.combat else null
	if alarm:
		for k in alarm.alarms:
			if not _fw_alarms.has(k):
				_fw_alarms[k] = String((alarm.alarms[k] as Dictionary).get("name", "?"))
	if is_instance_valid(_fw_zone):
		_fw_zone_peak = maxi(_fw_zone_peak, _fw_zone.raiders_inside)


func _fw_add(bucket: String, since: int) -> void:
	_fw_usec[bucket] = int(_fw_usec.get(bucket, 0)) + Time.get_ticks_usec() - since


func _forward_report() -> void:
	var tree := get_tree()
	var vm := ViewManager.of(tree)
	# Real frames at 1x, both worlds simulating (the view on home).
	var frames := 120
	SimClock.speed = 1.0
	var t0 := Time.get_ticks_usec()
	for i in frames:
		await tree.process_frame
	var frame_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / frames
	var roles := {}
	for n in tree.get_nodes_in_group(Ship.GROUP):
		var s := n as Ship
		if s and not s.dead and is_instance_valid(_fw) and SystemWorld.of(s) == _fw:
			var role := String((s.get_script() as Script).get_global_name()).trim_suffix("Ship")
			roles[role] = int(roles.get(role, 0)) + 1
	var parts: PackedStringArray = []
	var keys := roles.keys()
	keys.sort()
	for k in keys:
		parts.append("%s %d" % [k, roles[k]])
	var depot := _fw_outpost.get_cargo_depot() if is_instance_valid(_fw_outpost) else null
	var shipped := 0
	if depot:
		for x in depot.total_shipped:
			shipped += x
	var steps := maxf(_fw_steps, 1.0)
	print("SMOKE forward -------------------------------------")
	print("SMOKE forward setup  %s" % "; ".join(_fw_notes))
	print("SMOKE forward ore delivered %d in %d shuttle trips (waiting in the depot %s)" % [shipped, depot.trips if depot else 0, depot.stock if depot else []])
	print("SMOKE forward ships  %s" % (", ".join(parts) if not parts.is_empty() else "none"))
	var states: PackedStringArray = []
	for s in _fw_miners:
		if is_instance_valid(s) and not s.dead:
			states.append("%s (%s): %s, %s" % [s.captain.captain_name, s.captain.get_personality_name(), s.get_status_text(),
					s.brain.last_decision if s.brain else "-"])
	print("SMOKE forward miners %s; deaths %s" % ["; ".join(states) if not states.is_empty() else "none alive",
			", ".join(_fw_deaths) if not _fw_deaths.is_empty() else "-"])
	print("SMOKE forward systems trip checks %s, on another system's contract %d%s" % [_fw_trips, _fw_wrong,
			" (first: %s)" % _fw_wrong_first if _fw_wrong > 0 else ""])
	_forward_supply_report(shipped)
	if save_roundtrip:
		var end := _fw_shipped()
		var rising := end > _rt_ore
		_rt_ok = _rt_ok and rising
		for l in _rt:
			print("SMOKE forward reload %s" % l)
		print("SMOKE forward reload forward ore %d at the save -> %d at the end (%s)" % [_rt_ore, end, "rising" if rising else "NOT RISING"])
	print("SMOKE forward live   %s, viewed %s, pinned %s" % [vm.worlds.keys(), vm.viewed_id(), vm.is_pinned(FORWARD_ID)])
	print("SMOKE forward factory %s" % _forward_factory_check())
	print("SMOKE forward ms/step home %.3f, forward %.3f, other %.3f (%d steps); ms/frame %.2f over %d real frames" % [
			_fw_usec.get("home", 0) / 1000.0 / steps, _fw_usec.get("forward", 0) / 1000.0 / steps, _fw_usec.get("other", 0) / 1000.0 / steps,
			_fw_steps, frame_ms, frames])


func _expand_setup() -> void:
	var r := Corps.rival(Corps.RIVAL_IDS[0])
	if r == null:
		return
	RivalManager.forward_after = 1.0
	r.research.grant(r.research.catalog().find(&"eng_forward_operations"))
	var all: Array = []
	for id in Sector.network.ids:
		all.append(String(id))
	r.mind.stats["charted"] = all
	r.economy.add(6000, Economy.cost(800, 300), Ledger.OTHER, "Smoke money")


## --eliminate: see [member rival_kill]. Every rival is knocked out (its
## HQ hit by a player merc) so the last one ends the game in victory.
func _kill_step(minute: int) -> void:
	var rc := RivalCorp.of(get_tree())
	if rc == null or not Corps.has_rival():
		return
	if minute == 2:
		for r in Corps.rivals:
			var t := r.mind.tie(Corps.PLAYER)
			t.i_know_them = true
			t.they_know_me = true
			t.contact = true
			rc.set_stance(r, Corps.PLAYER, RivalMind.Stance.WAR)
			r.mind.next_meeting = 1e9
	if minute == 3:
		var me: Ship = null
		for r in Corps.rivals:
			RivalWorlds.of(get_tree()).materialise_corp(r.id)
		for n in SystemWorld.nodes_in(SystemWorld.home(get_tree()), Ship.GROUP):
			if n is MercenaryShip:
				me = n
		for r in Corps.rivals:
			var w := Corps.hq_world(get_tree(), r.id)
			if w == null or w.buildings == null or w.buildings.station_hull == null:
				continue
			var hull := w.buildings.station_hull
			# No repairs: as if the attackers kept it down.
			hull.repair_rate = 0.0
			hull.take_hit(hull.durability.hull + 10.0, me, hull.global_position)
			_kill_log.append("3:00 %s HQ hit by %s: disabled %s, scuttle %.0f s" % [r.display_name, me.get_display_name() if me else "?", hull.disabled, hull.scuttle_left])
	if minute == 5:
		var gone := 0
		for r in Corps.rivals:
			var st := Sector.state(Corps.home_of(r.id))
			gone += 1 if r.mind.eliminated else 0
			_kill_log.append("5:00 %s eliminated %s, HQ site %s" % [r.display_name, r.mind.eliminated, "gone" if st and st.station.is_empty() else "STILL THERE"])
		_kill_log.append("end screen %s, player captains %d" % [get_tree().root.get_node_or_null(^"EndScreen") != null, _player_captains()])
		var es := get_tree().root.get_node_or_null(^"EndScreen")
		if es:
			es.queue_free()
		if gone < Corps.rivals.size():
			_rival_rt_ok = false


func _player_captains() -> int:
	var n := 0
	for b in _mgr.buildings if _mgr else []:
		if is_instance_valid(b):
			n += b.captains.size()
	return n


## --war: forces first contact and war with rival 1, then a player strike;
## with two rivals or more also contact and war between rivals 1 and 2.
func _war_step(minute: int) -> void:
	var rc := RivalCorp.of(get_tree())
	var r := Corps.rival(Corps.RIVAL_IDS[0])
	if rc == null or r == null:
		return
	var rid := r.id
	var hull := _mgr.station_hull.hull_fraction() if _mgr and _mgr.station_hull else 1.0
	_station_low = minf(_station_low, hull)
	if minute == 2:
		var t := r.mind.tie(Corps.PLAYER)
		t.i_know_them = true
		t.they_know_me = true
		var st := Sector.state(Corps.home_of(rid))
		if st:
			st.known = true
		var r2 := Corps.rival(Corps.RIVAL_IDS[1])
		if r2:
			r.mind.tie(r2.id).i_know_them = true
			r2.mind.tie(r.id).they_know_me = true
	if minute == 3:
		_war_log.append("3:00 %s" % rc.player_proposes(rid, "war")["text"])
		var r2b := Corps.rival(Corps.RIVAL_IDS[1])
		if r2b and r.mind.tie(r2b.id).contact:
			rc.set_stance(r, r2b.id, RivalMind.Stance.WAR)
			_war_log.append("3:00 %s at war with %s: %s" % [r.display_name, r2b.display_name, Corps.corps_at_war(rid, r2b.id)])
	# The player strike from minute 8: with --expand at rival 1's forward
	# station once it has one (until minute 16), else at its home.
	var fwd: Array[StringName] = []
	for sid in WarStrikes.station_systems(rid):
		if sid != Corps.home_of(rid):
			fwd.append(sid)
	if _strike_target.is_empty() and minute >= 8 and (not rival_expand or not fwd.is_empty() or minute >= 16):
		_strike_target = fwd[0] if rival_expand and not fwd.is_empty() else Corps.home_of(rid)
		_strike_minute = minute
		# The 4:00 peace offer is taken above: back to war, or the strikers turn home at once.
		if not Corps.corps_at_war(Corps.PLAYER, rid):
			var tw := r.mind.tie(Corps.PLAYER)
			tw.ceasefire_until = 0.0
			rc.set_stance(r, Corps.PLAYER, RivalMind.Stance.WAR)
			_war_log.append("%d:00 back at war for the strike: %s" % [minute, Corps.corps_at_war(Corps.PLAYER, rid)])
		# The target as data, so the strike must build it on arrival.
		var rwk := RivalWorlds.of(get_tree())
		if rwk and ViewManager.of(get_tree()).is_live(_strike_target):
			rwk.clear_requests(_strike_target)
			if rwk.hold_reason(_strike_target).is_empty():
				rwk.debug_release(_strike_target)
		_strike_was_data = rwk != null and rwk.is_data(_strike_target)
		if rwk and not _strike_was_data:
			_war_log.append("%d:00 target kept live: %s" % [minute, rwk.hold_reason(_strike_target)])
		var res := WarStrikes.launch(get_tree(), Corps.PLAYER, _strike_target, 100, 3)
		_war_log.append("%d:00 player strike on %s (%s): %d sent, refused %s" % [minute, _sys_name(_strike_target),
				"forward" if fwd.has(_strike_target) else "home", (res["sent"] as Array).size(), res["refused"]])
		if (res["sent"] as Array).is_empty() and minute < 16:
			_strike_target = &""      # nobody went: ask again next minute
			_strike_minute = -1
	if _strike_minute >= 0 and minute > _strike_minute and (minute <= _strike_minute + 3 or (not _strike_live_seen and minute <= _strike_minute + 7)):
		# Every player merc on this strike, wherever it is (RivalCorp.mercs_of
		# lists only the ones in the corp's own station systems), and the ones
		# in a gate jump (data in Sector.transits, the node is gone meanwhile).
		var lines: PackedStringArray = []
		for n in get_tree().get_nodes_in_group(Ship.GROUP):
			var st := n as Ship
			var mb := st.brain as MercenaryBrain if st else null
			if mb == null or st.dead or Corps.owner_of(st) != Corps.PLAYER or mb.strike_system != _strike_target:
				continue
			var lw := SystemWorld.of(st)
			if lw and lw.system_id == _strike_target and mb.mode == MercenaryBrain.Mode.STRIKE:
				_strike_live_seen = true
			var fl := st.captain.flight_log if st.captain else null
			var last := fl.entries[fl.entries.size() - 1] if fl and not fl.entries.is_empty() else null
			lines.append("%s in %s, %s, hull %.0f%%, last log: %s" % [st.captain.captain_name if st.captain else "?", _sys_name(lw.system_id) if lw else "?",
					MercenaryBrain.Mode.keys()[mb.mode], st.hull_fraction() * 100.0, (last.headline + " (" + last.why + ")") if last else "-"])
		# Strikers flying as data through systems that are not live.
		for sid: StringName in Sector.states:
			for d: Dictionary in (Sector.states[sid] as RemoteSystemState).ships:
				var md: Dictionary = (d.get("brain", {}) as Dictionary).get("merc", {})
				if StringName(md.get("strike_system", "")) == _strike_target:
					lines.append("a striker as data in %s (%s)" % [_sys_name(sid), "transit phase %s" % (d.get("transit", {}) as Dictionary).get("phase", "?") if d.has("transit") else "no transit"])
		_war_log.append("%d:00 strikers on %s: %s; %d ship(s) in a gate jump" % [minute, _sys_name(_strike_target),
				"; ".join(lines) if not lines.is_empty() else "none live", Sector.transits.size()])
	if minute == 5 or minute == 12:
		var hud := get_tree().get_first_node_in_group(HUD.GROUP) as HUD
		if hud and hud.rival_panel:
			hud.rival_panel.open_panel()
			_war_log.append("%d:00 panel: %s / %s / war strike %s" % [minute, hud.rival_panel._status.text, hud.rival_panel._facts.text.replace("\n", "; "),
					"on" if not hud.rival_panel._strike.disabled else "off"])
			hud.rival_panel.close_panel()
		else:
			_war_log.append("%d:00 panel: NO HUD" % minute)
	if minute == 14:
		_war_log.append("14:00 peace: %s" % rc.player_proposes(rid, "peace")["text"])
	var fo := rc.first_offer()
	if not fo.is_empty():
		var o: Dictionary = fo["offer"]
		# While the strike flies (target data or kept live), offers are turned down: it must arrive.
		var flying := not _strike_target.is_empty() and not _strike_live_seen and _strike_minute >= 0 and minute <= _strike_minute + 7
		_war_log.append("%s offer %s from %s: %s -> %s" % [Fmt.clock(SimClock.time), o["kind"], Corps.display_name(fo["rid"]), o["text"],
				rc.answer_offer(fo["rid"], "reject" if flying else "accept")])


## Every rival's money and mind, for the round trip.
func _rival_sig() -> Array:
	var out := []
	for r in Corps.rivals:
		out.append([r.id, r.display_name, r.economy.credits, r.economy.ore, r.mind.to_dict().size(), r.mind.ties.size()])
	return out


## Saves to memory and reloads with rivals: every station system (the
## rival HQs too) and the rivals' money and minds must match.
func _rival_roundtrip() -> void:
	var tree := get_tree()
	var before := _census()
	var r0 := _rival_sig()
	var data: Dictionary = bytes_to_var(var_to_bytes(GameSnapshot.capture(tree)))
	await SaveManager.load_snapshot(data)
	# Paused while the scene settles: a payout in those frames is not a save bug.
	SimClock.paused = true
	for i in 5:
		await tree.process_frame
	_find_home()
	var after := _census()
	var r1 := _rival_sig()
	SimClock.paused = false
	# Trips can be re-decided on load (ShipCodec): compare the ships without them.
	var re := RegEx.create_from_string(" on [^,]*")
	var trips := 0
	for k: String in before.keys():
		if k.ends_with(" ships"):
			var a: String = before[k]
			var b: String = after.get(k, "")
			if a != b and re.sub(a, "", true) == re.sub(b, "", true):
				trips += 1
				before[k] = re.sub(a, "", true)
				after[k] = re.sub(b, "", true)
	var diffs: PackedStringArray = []
	for k in before:
		if before[k] != after.get(k):
			diffs.append("%s: %s -> %s" % [k, before[k], after.get(k, "missing")])
	for k in after:
		if not before.has(k):
			diffs.append("%s: new %s" % [k, after[k]])
	if trips > 0:
		_rival_rt_note = " (%d system%s with a trip re-decided on load)" % [trips, "" if trips == 1 else "s"]
	if r0 != r1:
		diffs.append("rivals %s -> %s" % [r0, r1])
	_rival_rt = "at %s: keys %s, %s%s" % [Fmt.clock(SimClock.time), before.keys(), "identical after load" if diffs.is_empty() else "DIFF " + "; ".join(diffs), _rival_rt_note]
	_rival_rt_ok = diffs.is_empty()


## --rival: what each rival corp built and did (rival corporation plan).
func _rival_report() -> void:
	print("SMOKE rival ---------------------------------------")
	if not _rival_rt.is_empty():
		print("SMOKE rival reload   %s" % _rival_rt)
	if not Corps.has_rival():
		print("SMOKE rival FAIL: no rival corp")
		return
	var net := Sector.network
	var homes: PackedStringArray = []
	for r in Corps.rivals:
		var hid := Corps.home_of(r.id)
		homes.append("%s %s (%s, %d jumps, branch %d)" % [r.id, hid, _sys_name(hid), net.depth(hid), net.entry(hid).branch])
	print("SMOKE rival homes    %s; remote systems %d" % ["; ".join(homes), net.remote_ids().size()])
	var hud := get_tree().get_first_node_in_group(HUD.GROUP) as HUD
	var listed := ContractBoard.get_listed()
	var bad := 0
	for c in listed:
		if c.corp != Corps.PLAYER:
			bad += 1
	print("SMOKE rival listing  board %d contracts, the player's list %d (%d not the player's), player escrow %d" % [ContractBoard.contracts.size(),
			listed.size(), bad, ContractBoard.escrow_total()])
	if bad > 0 or hud == null:
		_rival_rt_ok = false
	for i in Corps.rivals.size():
		for j in range(i + 1, Corps.rivals.size()):
			var a := Corps.rivals[i]
			var b := Corps.rivals[j]
			print("SMOKE rival pair     %s / %s: %d jumps apart, contact %s, at war %s, stance %s / %s" % [a.display_name, b.display_name,
					net.path(Corps.home_of(a.id), Corps.home_of(b.id)).size() - 1, a.mind.has_tie(b.id) and a.mind.tie(b.id).contact,
					Corps.corps_at_war(a.id, b.id), a.mind.tie(b.id).stance_name() if a.mind.has_tie(b.id) else "-",
					b.mind.tie(a.id).stance_name() if b.mind.has_tie(a.id) else "-"])
	_rival_flow_sample()
	for r in Corps.rivals:
		_rival_report_one(r)
		_rival_flow_report(r)
	if rival_kill:
		print("SMOKE rival eliminate %s" % " | ".join(_kill_log))
	if rival_expand:
		var fs := ForwardStations.of(get_tree())
		var rid := Corps.RIVAL_IDS[0]
		var rids: Array[StringName] = fs.ids(rid) if fs else []
		for x in rids:
			print("SMOKE rival expand   site %s: %s" % [x, Sector.state(x).station])
		print("SMOKE rival expand   forward stations %s, player slots %d, rival slots %d" % [rids, ForwardStations.free_slots(get_tree()),
				ForwardStations.free_slots(get_tree(), rid)])
		if rids.is_empty():
			_rival_rt_ok = false
	if not _trip_log.is_empty():
		print("SMOKE rival data trip %s" % " | ".join(_trip_log))
	if rival_war:
		var r := Corps.rivals[0]
		var t := r.mind.tie(Corps.PLAYER)
		print("SMOKE rival war      %s" % " | ".join(_war_log))
		print("SMOKE rival strike   on %s: target was data at launch %s, strikers seen there live %s" % [_sys_name(_strike_target), _strike_was_data, _strike_live_seen])
		if not _strike_live_seen and not _strike_target.is_empty():
			_rival_rt_ok = false
		print("SMOKE rival war      %s toward you: %s, strikes %d, ops %d, wars %d, treaties %d, home station lowest %d%%, losses %.1f, weariness %.2f" % [
				r.display_name, "war" if Corps.corps_at_war(r.id, Corps.PLAYER) else t.stance_name(), int(r.mind.stats.get("strikes", 0)), int(r.mind.stats.get("ops", 0)),
				int(r.mind.stats.get("wars", 0)), int(r.mind.stats.get("treaties", 0)), roundi(_station_low * 100.0), t.losses, t.weariness])
		var where: PackedStringArray = []
		for x in SystemWorld.all(get_tree()):
			for n in SystemWorld.nodes_in(x, Ship.GROUP):
				var sh := n as Ship
				if sh and not sh.dead and sh.role == Ship.Role.MERCENARY:
					where.append("%s[%s] in %s: %s" % [sh.get_display_name(), Corps.owner_of(sh), x.system_id, sh.get_status_text()])
		for tr: Dictionary in Sector.transits:
			where.append("in jump to %s" % tr.get("to", "?"))
		print("SMOKE rival mercs    %s" % " | ".join(where))
		var feed: PackedStringArray = []
		for e in EventLog.entries:
			var tx := String(e["text"])
			if tx.contains("strike") or tx.contains("war") or tx.contains("War") or tx.contains("Intel"):
				feed.append("%s %s" % [Fmt.clock(float(e["time"])), tx])
		print("SMOKE rival feed     %s" % " | ".join(feed.slice(maxi(feed.size() - 14, 0))))


## --rival: rival 1's headquarters goes from data to live at minute 4
## (RivalWorlds.request) and back to data at minute 5 (debug_release): the
## buildings and their captains must be the same on both sides each time.
func _rival_trip_step(minute: int) -> void:
	var r := Corps.rival(Corps.RIVAL_IDS[0])
	var rw := RivalWorlds.of(get_tree())
	var vm := ViewManager.of(get_tree())
	if r == null or rw == null or not RivalWorlds.data_enabled:
		return
	var id := Corps.home_of(r.id)
	if minute == 4:
		if not rw.is_data(id):
			_trip_log.append("4:00 HQ live (%s), no data trip" % rw.hold_reason(id))
			return
		var before := RivalData.shape(Sector.state(id))
		var b0 := rw.came_back
		rw.request(id, 50.0, "smoke data trip")
		var w := vm.world(id)
		var after := _live_shape(w)
		var ok := w != null and before == after and rw.came_back == b0 + 1
		_trip_log.append("4:00 data -> live %s: %s%s" % ["same" if ok else "DIFF", ", ".join(after), "" if ok else " (data was %s)" % ", ".join(before)])
		if not ok:
			_rival_rt_ok = false
	elif minute == 5 and vm.is_live(id):
		var why := rw.hold_reason(id)
		if not why.is_empty():
			_trip_log.append("5:00 HQ held live (%s), no release" % why)
			return
		var before := _live_shape(vm.world(id))
		rw.debug_release(id)
		var after := RivalData.shape(Sector.state(id))
		var ok := rw.is_data(id) and before == after
		_trip_log.append("5:00 live -> data %s: %s%s" % ["same" if ok else "DIFF", ", ".join(after),
				"" if ok else " (live was %s)" % ", ".join(before)])
		if not ok:
			_rival_rt_ok = false


## [method RivalData.shape] of a live world [param w].
func _live_shape(w: SystemWorld) -> PackedStringArray:
	var out: PackedStringArray = []
	if w == null or w.buildings == null:
		return out
	for b in w.buildings.buildings:
		if is_instance_valid(b) and not b.is_queued_for_deletion():
			out.append("%s/%s/%d" % [b.def.id, "on" if b.is_active() else "building", b.captains.size()])
	out.sort()
	return out


## Every sim minute: each rival's credit changes by ledger category since
## the last sample (entries are marked with what was counted, so merged
## entries count once), its captains by role, and (once) the hooks for ore
## deliveries and mining loads.
func _rival_flow_sample() -> void:
	for r in Corps.rivals:
		if not _flow.has(r.id):
			var f0 := {"cats": {}, "ore": Economy.zero_ore(), "loads": 0, "load_units": 0, "load_pay": 0, "cap_min": {}, "last": SimClock.time, "start": SimClock.time}
			_flow[r.id] = f0
			var rid := r.id
			r.economy.cargo_received.connect(func(ore: PackedInt32Array, _s: String) -> void:
				var o: PackedInt32Array = _flow[rid]["ore"]
				for i in mini(ore.size(), o.size()):
					o[i] += ore[i]
				_flow[rid]["ore"] = o)
			ContractBoard.delivery_made.connect(func(c: Contract, _sh: Node, cr: int, mat: int, _o: int) -> void:
				if c.corp == rid and c is MiningContract:
					_flow[rid]["loads"] += 1
					_flow[rid]["load_units"] += mat
					_flow[rid]["load_pay"] += cr)
		var f: Dictionary = _flow[r.id]
		var cats: Dictionary = f["cats"]
		for e in r.economy.ledger.entries:
			var amt := int(e["amt"])
			var d := amt - int(e.get("_m", 0))
			if d == 0:
				continue
			e["_m"] = amt
			var pair: Array = cats.get(e["cat"], [0, 0])
			if d > 0:
				pair[0] += d
			else:
				pair[1] -= d
			cats[e["cat"]] = pair
		var mins := (SimClock.time - float(f["last"])) / 60.0
		f["last"] = SimClock.time
		var roles: Dictionary = _rival_roles(r.id)
		var cm: Dictionary = f["cap_min"]
		for k: String in roles:
			cm[k] = float(cm.get(k, 0.0)) + float(roles[k]) * mins


## Captains of [param rid] by role, over its station worlds (live, and the
## ones that are data from their saved world).
func _rival_roles(rid: StringName) -> Dictionary:
	var roles := {}
	for w in SystemWorld.all(get_tree()):
		if not w.has_station or w.corp_id != rid or w.buildings == null:
			continue
		for b in w.buildings.buildings:
			if is_instance_valid(b):
				for c in b.captains:
					roles[c.role] = int(roles.get(c.role, 0)) + 1
	var vm := ViewManager.of(get_tree())
	for id in WarStrikes.station_systems(rid):
		if id != ClusterNetwork.HOME_ID and vm and not vm.is_live(id):
			var dr := RivalData.roles(Sector.state(id))
			for k: String in dr:
				roles[k] = int(roles.get(k, 0)) + int(dr[k])
	return roles


func _rival_flow_report(r: Corp) -> void:
	var f: Dictionary = _flow.get(r.id, {})
	if f.is_empty():
		return
	var mins := maxf((SimClock.time - float(f["start"])) / 60.0, 0.01)
	var parts: PackedStringArray = []
	var cats: Dictionary = f["cats"]
	for k: String in cats:
		var pair: Array = cats[k]
		parts.append("%s +%d/-%d" % [k, pair[0], pair[1]])
	var cm: Dictionary = f["cap_min"]
	var cms: PackedStringArray = []
	for k: String in cm:
		cms.append("%s %.0f" % [k, float(cm[k])])
	var rw := RivalWorlds.of(get_tree())
	var dl: Dictionary = rw.data_loads.get(r.id, {}) if rw else {}
	var sold := ""
	var mp := 0.0
	var mn := 0
	for ms in RivalCorp.mercs_of(get_tree(), r.id):
		mp += MercFleet.power_of(ms)
		mn += 1
	if mn > 0:
		sold += ", live merc power %.2f each" % (mp / mn)
	var hw := Corps.hq_world(get_tree(), r.id)
	var fac := Factory.find(hw.buildings) if hw and hw.buildings else null
	if fac and fac.market:
		sold += ", Factory market bought %s for %d cr in all" % [fac.market.total_units, fac.market.total_credits]
	var pl := _pirate_stats(r.id)
	sold += "; pirate raids live %d (%d ships lost, %d captains dead)" % [int(pl["raids"]), int(pl["lost"]), int(pl["dead"])]
	print("SMOKE rival flows    %s over %.0f min: %s; ore in %s; mining loads live %d (%d units, %d cr), as data %d (%d units, %d cr); captain-minutes %s%s" % [r.id, mins,
			", ".join(parts), f["ore"], f["loads"], f["load_units"], f["load_pay"], int(dl.get("loads", 0)), int(dl.get("units", 0)), int(dl.get("pay", 0)),
			", ".join(cms), sold])


func _rival_report_one(r: Corp) -> void:
	var id := Corps.home_of(r.id)
	var w := Corps.hq_world(get_tree(), r.id)
	var t := r.mind.tie(Corps.PLAYER)
	print("SMOKE rival corp     %s %s (%s), home %s, live %s, toward you %s%s%s" % [r.id, r.display_name, r.mind.personality_name(),
			_sys_name(id), w != null, t.stance_name(), ", contact" if t.contact else "", ", ELIMINATED" if r.mind.eliminated else ""])
	print("SMOKE rival money    %s: %d cr, ore %s" % [r.id, r.economy.credits, r.economy.ore])
	var builds := {}
	var roles := {}
	if w and w.buildings:
		for b in w.buildings.buildings:
			if is_instance_valid(b):
				builds[b.def.display_name] = int(builds.get(b.def.display_name, 0)) + 1
				for c in b.captains:
					roles[c.role] = int(roles.get(c.role, 0)) + 1
	if w and w.buildings:
		var ed := w.buildings.def_by_id(&"explorer_outpost")
		var rm := w.get_node_or_null(^"RivalManager") as RivalManager
		var goal := rm._saving_for() if rm else null
		print("SMOKE rival explorer %s: limit '%s', count %d, cost %d cr %s, has %d cr %s, saving for %s, projects %s, researchers %d" % [r.id,
				w.buildings.limit_reason(ed) if ed else "?", w.buildings.count_of(ed) if ed else -1, ed.cost_credits if ed else 0, ed.cost_ore() if ed else [],
				r.economy.credits, r.economy.ore, goal.id if goal else "-", r.research.projects, r.research.researchers.size()])
		var lab := r.research.lab()
		var rs: PackedStringArray = []
		for x in r.research.researchers:
			var jn := r.research.catalog().find(&"eng_jump_navigation")
			rs.append("%s (%s, %s) proj '%s' unpaid %s, jump nav: %s" % [x.researcher_name, x.field_name(), x.personality_name(), x.project, x.unpaid,
					"takes it" if jn and ResearchChoice.accepts(x, jn) else ResearchChoice.refusal(x, jn) if jn else "?"])
		print("SMOKE rival lab      %s: lab %s active %s; %s" % [r.id, lab != null, lab.building.is_active() if lab else false, "; ".join(rs)])
	if w == null:
		builds = RivalData.builds(Sector.state(id))
		roles = RivalData.roles(Sector.state(id))
	var ps: Dictionary = RivalManager.plan_stats.get(r.id, {})
	var pk := ps.keys()
	pk.sort_custom(func(a: String, b: String) -> bool: return int(ps[a]) > int(ps[b]))
	var pparts: PackedStringArray = []
	for k: String in pk.slice(0, 14):
		pparts.append("%s %d" % [k, int(ps[k])])
	print("SMOKE rival plan     %s: %s" % [r.id, ", ".join(pparts)])
	print("SMOKE rival builds   %s: %s, captains %s, research %s, charted %d, strength %.1f" % [r.id, builds, roles, r.research.done.keys(),
			(r.mind.stats.get("charted", []) as Array).size(), RivalCorp.strength(get_tree(), r.id)])
	var rw := RivalWorlds.of(get_tree())
	if rw:
		var ws: PackedStringArray = []
		for sid in WarStrikes.station_systems(r.id):
			ws.append("%s %s%s" % [_sys_name(sid), "live" if ViewManager.of(get_tree()).is_live(sid) else "data",
					" (%s)" % rw.reasons[sid] if not String(rw.reasons.get(sid, "")).is_empty() else ""])
		print("SMOKE rival worlds   %s: %s; went data %d times, came back %d times (all rivals)" % [r.id, ", ".join(ws), rw.went_data, rw.came_back])
	var key: PackedStringArray = []
	for e in r.mind.intel:
		var tx := String(e["text"])
		if bool(e.get("public", false)) or tx.begins_with("Our scouts found") or tx.begins_with("We made contact") or tx.contains("declared war") \
				or tx.contains("offered") or tx.contains("-> ") and not tx.contains("-> Peace (runner-up Trade pact)"):
			key.append("%s %s" % [Fmt.clock(float(e["time"])), tx])
	print("SMOKE rival story    %s: %s" % [r.id, " | ".join(key.slice(maxi(key.size() - 10, 0)))])


## A Factory addon at the forward station for a moment: it must use home's
## keep-at-least and held yard ore (one player ore pool), then it is removed.
func _forward_factory_check() -> String:
	var fm := _fw.buildings if is_instance_valid(_fw) else null
	var def := fm.def_by_id(&"factory") if fm else null
	var bays: Array = fm.free_bays() if fm else []
	var hf := Building.first_active_service(SystemWorld.home(get_tree()), Factory.GROUP) as Factory
	if def == null or bays.is_empty() or hf == null:
		return "skipped (no bay or no home Factory)"
	var b := fm.install_addon(def, bays[0], true)
	var ff := Building.first_active_service(_fw, Factory.GROUP) as Factory if b else null
	if ff == null or ff == hf:
		if b:
			fm.remove_addon(b)
		return "skipped (not installed)"
	var hm := hf.market
	var m := ff.market
	var keep0 := hm.reserve[Economy.Ore.IRON]
	m.set_reserve(Economy.Ore.IRON, keep0 + 50)
	var shared := m.primary() == hm and hm.reserve[Economy.Ore.IRON] == keep0 + 50 and m.kept(Economy.Ore.IRON) == hm.kept(Economy.Ore.IRON)
	var held0 := hm.held[Economy.Ore.TITANIUM]
	var cargo := Economy.zero_ore()
	cargo[Economy.Ore.TITANIUM] = 5
	m.hold(cargo)
	shared = shared and hm.held[Economy.Ore.TITANIUM] == held0 + 5 and m.surplus(Economy.Ore.IRON) == hm.surplus(Economy.Ore.IRON)
	hm.held[Economy.Ore.TITANIUM] = held0
	hm.set_reserve(Economy.Ore.IRON, keep0)
	fm.remove_addon(b)
	if not shared:
		_fw_factory_bad = true
	return "keep and held shared with home's: %s" % ("ok" if shared else "FAIL")


## F4: threat, upkeep, water, hauling fee, berths.
func _forward_supply_report(shipped: int) -> void:
	var raids := _fw.combat.raids if is_instance_valid(_fw) and _fw.combat else null
	var sup := _fw.supply if is_instance_valid(_fw) else null
	var founded := float(_fw.station_site.get("founded_at", 0.0)) if is_instance_valid(_fw) else 0.0
	print("SMOKE forward raids  %d launched: %s; first allowed %s (founded %s + %s grace); bases %s, danger %d" % [_fw_raids.size(),
			", ".join(_fw_raids) if not _fw_raids.is_empty() else "-", Fmt.clock(founded + (raids.first_raid_time if raids else 0.0)),
			Fmt.clock(founded), Fmt.clock(raids.first_raid_time if raids else 0.0), _fw_bases(), raids.danger if raids else -1])
	var al: PackedStringArray = []
	for k in _fw_alarms:
		al.append(_fw_alarms[k])
	print("SMOKE forward alarms %d: %s" % [_fw_alarms.size(), ", ".join(al) if not al.is_empty() else "-"])
	if is_instance_valid(_fw_zone):
		print("SMOKE forward zone   %s: raiders inside at most %d, kills %d, paid %d cr, budget left %d" % [_fw_zone.zone_name, _fw_zone_peak,
				_fw_zone.kills, _fw_zone.paid_total, _fw_zone.budget])
	if is_instance_valid(_fw_merc) and not _fw_merc.dead:
		print("SMOKE forward merc   %s: %s, kills %d" % [_fw_merc.captain.captain_name, _fw_merc.get_status_text(), _fw_merc.captain.kills])
	elif long_run:
		print("SMOKE forward merc   lost or none")
	if sup:
		print("SMOKE forward upkeep paid %d cr, owed %d; water used %d, %s (stock %d)%s" % [sup.upkeep_paid, sup.owed, sup.water_used,
				"DRY" if sup.dry else "ok", Economy.ore[Economy.Ore.WATER], ", refill: " + _fw_refill if not _fw_refill.is_empty() else ""])
		var notes := 0
		for e in Economy.ledger.entries:
			if e["cat"] == Ledger.HAULING:
				notes += int(e.get("n", 1))
		print("SMOKE forward hauling fee %s (worth %d cr at the Factory price, %d ledger notes); ore landed %d of %d shipped" % [
				Economy.cost_text(sup.hauled_fee) if not Economy.cost_text(sup.hauled_fee).is_empty() else "none", sup.hauled_fee_value, notes,
				shipped - _sum(sup.hauled_fee), shipped])
	else:
		print("SMOKE forward supply MISSING")
	print("SMOKE forward berths %s" % "; ".join(_berths()))
	var lines := _fw_feed
	if lines.size() > 16:
		lines = lines.slice(lines.size() - 16)
	for l in lines:
		print("SMOKE forward feed   %s" % l)


func _fw_bases() -> String:
	var out: PackedStringArray = []
	var sys := _fw.sys if is_instance_valid(_fw) else null
	for d in sys.dens if sys else []:
		if is_instance_valid(d):
			out.append("%s%s" % [d.get_display_name(), "" if d.is_alive() else " (destroyed)"])
	return ", ".join(out) if not out.is_empty() else "none"


## Hiring buildings in every station system: captains/berths and why one
## cannot hire now (a dead captain's berth must reopen).
func _berths() -> PackedStringArray:
	var out: PackedStringArray = []
	for w in SystemWorld.all(get_tree()):
		if not w.has_station or w.buildings == null:
			continue
		for b in w.buildings.buildings:
			if is_instance_valid(b) and b.def.can_hire():
				var why := b.hire_block_reason()
				out.append("%s %s %d/%d (%s)" % [w.system_id, b.display_name, b.captains.size(), b.def.max_hires, why if not why.is_empty() else "can hire"])
	return out


static func _sum(a: PackedInt32Array) -> int:
	var n := 0
	for x in a:
		n += x
	return n


# --- Save round trip (F3) ----------------------------------------------------

var _rt: PackedStringArray = []
var _rt_ok := true
var _rt_ore := -1


func _forward_roundtrip() -> void:
	var tree := get_tree()
	var before := _census()
	_rt_ore = _fw_shipped()
	var data: Dictionary = bytes_to_var(var_to_bytes(GameSnapshot.capture(tree)))
	await SaveManager.load_snapshot(data)
	for i in 5:
		await tree.process_frame
	_find_home()
	var vm := ViewManager.of(tree)
	_fw = vm.world(FORWARD_ID) if vm else null
	_fw_outpost = null
	_fw_miners.clear()
	if _fw and _fw.buildings:
		for b in _fw.buildings.buildings:
			if is_instance_valid(b) and b.def.id == &"mining_outpost":
				_fw_outpost = b
		for s in _fw_outpost.ships if _fw_outpost else []:
			if s is MinerShip:
				_fw_miners.append(s)
	_fw_bind()
	var after := _census()
	var diffs: PackedStringArray = []
	for k in before:
		if before[k] != after.get(k):
			diffs.append("%s: %s -> %s" % [k, before[k], after.get(k, "missing")])
	for k in after:
		if not before.has(k):
			diffs.append("%s: new %s" % [k, after[k]])
	_rt_ok = diffs.is_empty() and _fw != null
	_rt.append("at %s: %d forward ore, keys %s, %s" % [Fmt.clock(SimClock.time), _rt_ore, before.keys(),
			"identical after load" if diffs.is_empty() else "DIFF " + "; ".join(diffs)])
	var st := Sector.state(FORWARD_ID)
	if st and not st.ships.is_empty():
		_rt_ok = false
	_rt.append("live %s, pinned %s, forward world %s, stale data ships %d; %s" % [vm.worlds.keys() if vm else [], vm.is_pinned(FORWARD_ID) if vm else false,
			"ok" if _fw else "MISSING", st.ships.size() if st else -1, after.get("%s ships" % FORWARD_ID, "-")])


## Forward ore shipped so far (the outpost's depot).
func _fw_shipped() -> int:
	var depot := _fw_outpost.get_cargo_depot() if is_instance_valid(_fw_outpost) else null
	var n := 0
	if depot:
		for x in depot.total_shipped:
			n += x
	return n


## Per station system: buildings (name, state, berths), captains (name,
## rank, wallet), contracts (title, status, system), as comparable strings.
func _census() -> Dictionary:
	var out := {}
	# Rival station worlds that are data: their saved world (RivalData).
	var vm := ViewManager.of(get_tree())
	for id in RivalWorlds.sites():
		if vm and not vm.is_live(id):
			var st := Sector.state(id)
			out["%s data" % id] = "%s; jobs %s; builds %d hires %d" % [", ".join(RivalData.shape(st)), RivalData.mining_jobs(st.world),
					((st.world.get("data", {}) as Dictionary).get("builds", []) as Array).size(), ((st.world.get("data", {}) as Dictionary).get("hires", []) as Array).size()]
	for w in SystemWorld.all(get_tree()):
		if not w.has_station or w.buildings == null:
			continue
		var bl: PackedStringArray = []
		var cl: PackedStringArray = []
		for b in w.buildings.buildings:
			if not is_instance_valid(b):
				continue
			bl.append("%s/%d/%d" % [b.display_name, b.state, b.captains.size()])
			for c in b.captains:
				cl.append("%s r%d %d cr" % [c.captain_name, c.rank, c.wallet])
		bl.sort()
		cl.sort()
		var kl: PackedStringArray = []
		for c in ContractBoard.contracts:
			if c.system_id == w.system_id:
				kl.append("%s/%d/%s" % [c.get_title(), c.status, c.system_id])
		kl.sort()
		var sl: PackedStringArray = []
		for n in SystemWorld.nodes_in(w, Ship.GROUP):
			var sh := n as Ship
			if sh and not sh.dead:
				var tr := (sh.brain as CaptainBrain).trip if sh.brain is CaptainBrain else null
				sl.append("%s%s" % [sh.get_display_name(), " on " + tr.contract.get_title() if tr and tr.contract else ""])
		sl.sort()
		out["%s ships" % w.system_id] = ", ".join(sl)
		out["%s buildings" % w.system_id] = ", ".join(bl)
		out["%s captains" % w.system_id] = ", ".join(cl)
		out["%s contracts" % w.system_id] = ", ".join(kl)
	return out


# --- Colony (F6) -------------------------------------------------------------

## Longest wait for one step of a convoy, sim seconds.
const COLONY_STEP_MAX := 1500.0
## Longest warp spool a mobile station may sit in, sim seconds (a climb
## to a belt lane takes about 20; more fails the run).
const COLONY_SPOOL_MAX := 60.0
## Station 1 is attacked at home on its way out by this many raiders.
const COLONY_RAIDERS := 3
var _col: PackedStringArray = []
var _col_feed: PackedStringArray = []
var _col_ok := true
var _col_spool := false
var _col_unguarded := false


func _colony_run() -> String:
	var tree := get_tree()
	Research.grant(TechCatalog.shared().find(&"eng_forward_operations"))
	Economy.add(0, PackedInt32Array([900, 400, 0, 0, 800]), Ledger.OTHER, "Smoke test ore and water")
	var net := Sector.network
	var t1: StringName = net.gate_target(ClusterNetwork.HOME_ID, "Ostra Gate")["system"]
	var t2: StringName = &""
	for id in net.remote_ids():
		var e := net.entry(id)
		if id != t1 and e.danger <= ForwardStations.MAX_DANGER and (t2.is_empty() or e.depth > net.entry(t2).depth):
			t2 = id
	for id in [t1, t2]:
		Sector.mark_surveyed(id, SimClock.time)
	_col.append("seed %d, targets %s (danger %d, %d jump), %s (danger %d, %d jumps)" % [Sector.get_seed(), _sys_name(t1), net.entry(t1).danger, net.entry(t1).depth,
			_sys_name(t2), net.entry(t2).danger, net.entry(t2).depth])
	EventLog.posted.connect(func(e: Dictionary) -> void:
		var text := String(e.get("text", ""))
		if text.contains("Forward Station") or text.contains("Forward station") or text.contains("escort") or text.contains("ambush") or text.contains("Station founded"):
			_col_feed.append("%s %s" % [Fmt.clock(SimClock.time), text]))
	var mo := _find_outpost(&"mercenary_outpost")
	if mo:
		mo.hire()
	var mercs := 0
	for s in mo.ships if mo else []:
		if s is MercenaryShip:
			mercs += 1
	_col.append("mercenaries %d" % mercs)
	# Station 1: Ostra, viewed (live).
	var ms := await _colony_build(1)
	if ms == null:
		return "station 1 was not built"
	await _colony_roundtrip("parked")
	ms = _mobile(1)
	if not await _colony_send(ms, t1):
		return "station 1: no destination"
	await _colony_roundtrip("waiting")
	ms = _mobile(1)
	var vm := ViewManager.of(tree)
	vm.view_now(t1)
	if not await _colony_fly(1, t1, false):
		return "station 1 not founded in %s" % _sys_name(t1)
	vm.view_now(ClusterNetwork.HOME_ID)
	# Station 2: the other target, the view at home (data), a reload in transit.
	ms = await _colony_build(2)
	if ms == null:
		return "station 2 was not built"
	if not await _colony_send(ms, t2):
		return "station 2: no destination"
	if not await _colony_fly(2, t2, true):
		return "station 2 not founded in %s" % _sys_name(t2)
	var fs := ForwardStations.of(tree)
	if fs.count() != 2:
		return "%d stations founded" % fs.count()
	if _col_spool:
		return "a mobile station spooled its warp longer than %.0f s" % COLONY_SPOOL_MAX
	if _col_unguarded:
		return "the escorts never fought the raiders attacking station 1"
	return "" if _col_ok else "a reload changed the convoy (see SMOKE colony reload)"


func _colony_print() -> void:
	var tree := get_tree()
	var vm := ViewManager.of(tree)
	var fs := ForwardStations.of(tree)
	var live: PackedStringArray = []
	for id in fs.ids() if fs else []:
		var w := vm.world(id)
		live.append("%s: %s (%s, pinned %s, supply %s)" % [_sys_name(id), Sector.state(id).station.get("name", "?"), "live" if w else "NOT LIVE",
				vm.is_pinned(id), "yes" if w and w.supply else "no"])
	print("SMOKE colony --------------------------------------")
	for l in _col:
		print("SMOKE colony %s" % l)
	print("SMOKE colony stations %s" % ("; ".join(live) if not live.is_empty() else "none"))
	print("SMOKE colony slots left %d, mobile left %d" % [ForwardStations.free_slots(tree), MobileStation.count_all(tree)])
	for l in _col_feed:
		print("SMOKE colony feed  %s" % l)


func _sys_name(id: StringName) -> String:
	var d := Sector.system_def(id)
	return d.system_name if d else String(id)


func _find_outpost(id: StringName) -> Building:
	for b in _mgr.buildings:
		if is_instance_valid(b) and b.def.id == id:
			return b
	return null


func _mobile(n: int) -> MobileStation:
	for node in get_tree().get_nodes_in_group(MobileStation.MOBILE_GROUP):
		var ms := node as MobileStation
		if ms.number == n and not ms.dead:
			return ms
	return null


## Places a Forward Station at home (paid, real construction) and runs
## until it is a mobile station.
func _colony_build(n: int) -> MobileStation:
	var tree := get_tree()
	var def := _mgr.def_by_id(ForwardStations.BUILD_ID)
	var why := _mgr.limit_reason(def)
	var b: Building = null
	for ring in range(1, 14):
		var r := 420.0 + ring * 110.0
		for k in 16:
			var a := TAU * float(k) / 16.0
			var off := Vector3(cos(a) * r, 0.0, sin(a) * r)
			if b == null and why.is_empty() and _mgr.plan_placement(def, off).is_valid():
				b = _mgr.place(def, off)
	if b == null:
		if why.is_empty():
			why = Economy.shortfall_text(def.cost_credits, def.cost_ore())
		if why.is_empty():
			why = "no spot"
		_col.append("build %d: could not place (%s)" % [n, why])
		return null
	var t0 := SimClock.time
	SimStepper.run(tree, def.build_time + 5.0, 0.1, func() -> bool: return _mobile(n) != null)
	for i in 3:
		await tree.process_frame
	var ms := _mobile(n)
	_col.append("build %d: %s, %s cr + %s, done in %s -> %s" % [n, def.display_name, Fmt.amount(def.cost_credits), Economy.cost_text(def.cost_ore()),
			Fmt.clock(SimClock.time - t0), ms.get_display_name() if ms else "NOTHING"])
	return ms


## Views the target, picks the first valid planet (the site picker's
## rule), sets the destination, views home again.
func _colony_send(ms: MobileStation, target: StringName) -> bool:
	var tree := get_tree()
	var vm := ViewManager.of(tree)
	var w := vm.view_now(target)
	for i in 3:
		await tree.process_frame
	var pick: PlanetBody = null
	var refused: PackedStringArray = []
	for p in w.sys.planets:
		var why := ms.destination_problem(target, p)
		if why.is_empty() and pick == null:
			pick = p
		elif not why.is_empty():
			refused.append("%s: %s" % [p.def.name, why])
	var ok := pick != null and ms.set_destination(target, pick)
	_col.append("send %d: %s in %s%s; refused %s" % [ms.number, pick.def.name if pick else "no planet", _sys_name(target), "" if ok else " FAILED",
			"; ".join(refused) if not refused.is_empty() else "-"])
	vm.view_now(ClusterNetwork.HOME_ID)
	for i in 3:
		await tree.process_frame
	return ok


## Runs until station [param n] founded [param target]; times the wait for
## an escort, the flight and the deploy. [param reload]: a save and load
## once it is out of home.
func _colony_fly(n: int, target: StringName, reload: bool) -> bool:
	var tree := get_tree()
	var t0 := SimClock.time
	var marks := {}
	var reloaded := false
	var hops := ""
	var spool := 0.0
	var raiders: Array[ScavengerShip] = []
	var hull := -1.0
	var fought := 0
	while SimClock.time - t0 < COLONY_STEP_MAX * 2.0 and Sector.state(target).station.is_empty():
		SimStepper.run(tree, 2.0)
		var ms := _mobile(n)
		if ms and ms.mover.warp_state == ShipMover.Warp.SPOOL:
			spool = maxf(spool, SpaceNav.WARP_SPOOL - ms.mover.warp_timer)
		if n == 1 and ms and ms.state == MobileStation.State.TRAVEL and not marks.has("attack") and SystemWorld.of(ms) and SystemWorld.of(ms).is_home:
			raiders = _colony_attack(ms)
			marks["attack"] = SimClock.time - t0
			hull = ms.durability.hull
		if ms and hull >= 0.0:
			marks["hull_lost"] = hull - ms.durability.hull
			for e in ms.escorts():
				var mb := e.brain as MercenaryBrain
				if mb and mb.combat_target is ScavengerShip and raiders.has(mb.combat_target):
					fought += 1
		if ms and ms.state == MobileStation.State.TRAVEL and not marks.has("left"):
			marks["left"] = SimClock.time - t0
			hops = ", ".join(ms.transit.hops) if ms.transit else "?"
			marks["escorts"] = ", ".join(ms.escorts().map(func(e: Ship) -> String: return e.get_display_name()))
		if ms and ms.state == MobileStation.State.CRUISE and not marks.has("cruise"):
			marks["cruise"] = SimClock.time - t0
		if ms and ms.state == MobileStation.State.DEPLOY and not marks.has("deploy"):
			marks["deploy"] = SimClock.time - t0
		var data := _mobile_dict(n)
		if not data.is_empty():
			marks["data"] = String(data.get("where", ""))
			var dst := int((data["d"]["mobile"] as Dictionary).get("state", 0))
			if dst == MobileStation.State.CRUISE and not marks.has("cruise"):
				marks["cruise"] = SimClock.time - t0
			if dst == MobileStation.State.DEPLOY and not marks.has("deploy"):
				marks["deploy"] = SimClock.time - t0
			var roll: Variant = (data["d"]["mobile"] as Dictionary).get("last_roll", null)
			if roll is Dictionary:
				marks["roll"] = "%s chance %d%%, roll %d%%" % [_sys_name(StringName(roll["system"])), roundi(float(roll["chance"]) * 100.0), roundi(float(roll["roll"]) * 100.0)]
		if reload and not reloaded and marks.has("left") and (not data.is_empty() or (ms and SystemWorld.of(ms) and not SystemWorld.of(ms).is_home)):
			reloaded = true
			await _colony_roundtrip("in transit (%s)" % ("data: " + String(data.get("where", "")) if not data.is_empty() else "live"))
		await tree.process_frame
	var done := not Sector.state(target).station.is_empty()
	var w := ViewManager.of(tree).world(target)
	_col.append("fly %d: longest warp spool %.1f s (at most %.0f)" % [n, spool, COLONY_SPOOL_MAX])
	if spool > COLONY_SPOOL_MAX:
		_col_ok = false
		_col_spool = true
	if marks.has("attack"):
		var down := raiders.filter(func(r: Variant) -> bool: return not is_instance_valid(r) or (r as ScavengerShip).dead).size()
		_col.append("attack %d: %d raiders at %s in %s, %d down by the founding, station hull -%d, escort fight samples %d" % [n, raiders.size(),
				Fmt.clock(float(marks["attack"])), _sys_name(ClusterNetwork.HOME_ID), down, roundi(float(marks.get("hull_lost", 0.0))), fought])
		if fought == 0:
			_col_ok = false
			_col_unguarded = true
	_col.append("fly %d to %s: waited %s for %s, hops %s, data %s, arrived %s, deploy %s, founded %s%s; roll %s" % [n, _sys_name(target),
			Fmt.clock(float(marks.get("left", -1.0))), marks.get("escorts", "-"), hops, marks.get("data", "never"),
			Fmt.clock(float(marks.get("cruise", -1.0))), Fmt.clock(float(marks.get("deploy", -1.0))),
			Fmt.clock(SimClock.time - t0) if done else "NOT", (": " + String(Sector.state(target).station.get("name", "?")) + (" live" if w else " NOT LIVE")) if done else "",
			marks.get("roll", "-")])
	if done:
		# The escorts fly home through the gates.
		SimStepper.run(tree, 240.0)
		var where: PackedStringArray = []
		var mo := _find_outpost(&"mercenary_outpost")
		for c in mo.captains if mo else []:
			var s := c.ship
			where.append("%s %s" % [c.captain_name, ("%s: %s" % [SystemWorld.of(s).system_id if s and SystemWorld.of(s) else "?", s.get_status_text()]) if is_instance_valid(s) else (c.away_in if not c.away_in.is_empty() else "no ship")])
		_col.append("escorts 4 min later: %s, wallets %s" % ["; ".join(where), ", ".join((mo.captains if mo else []).map(func(c: Captain) -> String: return str(c.wallet)))])
	return done


## Raiders from a home base sent at [param ms] (launched, 1.4 km out).
func _colony_attack(ms: MobileStation) -> Array[ScavengerShip]:
	var out: Array[ScavengerShip] = []
	for d in SystemWorld.nodes_in(ms, ScavengerDen.GROUP):
		var den := d as ScavengerDen
		if den == null or den.dead:
			continue
		var k := 0
		for r in den.spawn_pack(COLONY_RAIDERS, true):
			r.global_position = ms.global_position + Vector3(cos(k * 2.1) * 1400.0, 0.0, sin(k * 2.1) * 1400.0)
			r.ai.set_raid_objective(ms)
			out.append(r)
			k += 1
		break
	return out


## Station [param n] as data: {d, where} or {}.
func _mobile_dict(n: int) -> Dictionary:
	for id: StringName in Sector.states:
		for d: Dictionary in (Sector.states[id] as RemoteSystemState).ships:
			if MobileStation.is_mobile(d) and int(d["mobile"]["number"]) == n:
				return {"d": d, "where": _sys_name(id)}
	for t: Dictionary in Sector.transits:
		if MobileStation.is_mobile(t["ship"]) and int(t["ship"]["mobile"]["number"]) == n:
			return {"d": t["ship"], "where": "the jump to %s" % _sys_name(t["to"])}
	return {}


## Save to memory, load, compare the convoys.
func _colony_roundtrip(label: String) -> void:
	var tree := get_tree()
	var before := _convoy_census()
	var data: Dictionary = bytes_to_var(var_to_bytes(GameSnapshot.capture(tree)))
	await SaveManager.load_snapshot(data)
	for i in 5:
		await tree.process_frame
	_find_home()
	var after := _convoy_census()
	var same := before == after
	_col_ok = _col_ok and same
	_col.append("reload %s at %s: %s" % [label, Fmt.clock(SimClock.time), ("identical: " + before) if same else "DIFF %s -> %s" % [before, after]])


## Every mobile station and its escort contract, comparable.
func _convoy_census() -> String:
	var parts: PackedStringArray = []
	for node in get_tree().get_nodes_in_group(MobileStation.MOBILE_GROUP):
		var ms := node as MobileStation
		if ms.dead:
			continue
		var c := ms.contract
		parts.append("%s %s in %s dest %s hull %d, contract %s, escorts %d" % [ms.get_display_name(), MobileStation.STATE_NAMES[ms.state],
				SystemWorld.of(ms).system_id if SystemWorld.of(ms) else &"?", ms.dest, roundi(ms.durability.hull),
				("%d cr x%d" % [c.reward, c.max_escorts]) if c and not c.is_finished() else "none", ms.escorts().size()])
	for id: StringName in Sector.states:
		for d: Dictionary in (Sector.states[id] as RemoteSystemState).ships:
			if MobileStation.is_mobile(d):
				parts.append("Forward Station %d as data in %s, %d escorts" % [int(d["mobile"]["number"]), id, (d.get("escorts", []) as Array).size()])
	for t: Dictionary in Sector.transits:
		if MobileStation.is_mobile(t["ship"]):
			parts.append("Forward Station %d in the jump to %s, %d escorts" % [int(t["ship"]["mobile"]["number"]), t["to"], (t["ship"].get("escorts", []) as Array).size()])
	var open := 0
	for c in ContractBoard.contracts:
		if c is EscortContract:
			open += 1
	parts.append("%d escort contracts" % open)
	parts.sort()
	return "; ".join(parts)


# --- Explore (P3) ------------------------------------------------------------

var _explore: PackedStringArray = []


func _explore_run() -> void:
	var tree := get_tree()
	Sector.start(EXPLORE_SEED)
	Research.grant(TechCatalog.shared().find(&"eng_jump_navigation"))
	var def := _mgr.def_by_id(&"explorer_outpost")
	var b := _spawn_near_station(_mgr, def) if def else null
	if b == null:
		_explore.append("no outpost")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 1
	b.captain_rng = rng
	for p in [Captain.Personality.BOLD, Captain.Personality.CAUTIOUS, Captain.Personality.GREEDY]:
		b.hire(p)
	for i in 5:
		await tree.process_frame
	var to: StringName = Sector.network.gate_target(ClusterNetwork.HOME_ID, "Ostra Gate")["system"]
	var c := ContractBoard.post_explore(ClusterNetwork.HOME_ID, "Ostra Gate", ExploreContract.fair_for(1, ExploreContract.danger_guess(to)))
	if c == null:
		_explore.append("could not post")
		return
	var t0 := SimClock.time
	var marks := {}
	var income := {}
	Economy.income.connect(func(amount: int, source: String) -> void:
		income[source] = int(income.get(source, 0)) + amount)
	var lines: PackedStringArray = []
	EventLog.posted.connect(func(e: Dictionary) -> void:
		var t := String(e.get("text", ""))
		if t.begins_with("Corporate bounty") or t.contains("salvage"):
			lines.append(t))
	while SimClock.time - t0 < EXPLORE_MAX and not c.is_finished():
		SimStepper.run(tree, 10.0)
		if c.taken() and not marks.has("taken"):
			marks["taken"] = "%s at %s" % [c.explorer_name, Fmt.clock(SimClock.time - t0)]
		if c.phase == Survey.PHASE_SURVEY and not marks.has("survey"):
			marks["survey"] = Fmt.clock(SimClock.time - t0)
		if c.phase == Survey.PHASE_BACK and not marks.has("back"):
			marks["back"] = Fmt.clock(SimClock.time - t0)
		await tree.process_frame
	var refusals: PackedStringArray = []
	for s in b.ships:
		if is_instance_valid(s) and s.brain and not s.brain.last_refusal.is_empty():
			refusals.append("%s (%s): %s" % [s.captain.captain_name, s.captain.get_personality_name(), s.brain.last_refusal])
	var st := Sector.state(to)
	var found := 0
	for x in Sector.discoveries:
		if x["system"] == to:
			found += 1
	print("SMOKE explore -------------------------------------")
	print("SMOKE explore seed  %d, target %s, reward %d cr" % [EXPLORE_SEED, Sector.system_def(to).system_name, c.reward])
	print("SMOKE explore taken %s; surveying from %s, heading home from %s, done %s (%s)" % [marks.get("taken", "never"), marks.get("survey", "-"),
			marks.get("back", "-"), Fmt.clock(SimClock.time - t0), Contract.STATUS_NAMES[c.status]])
	print("SMOKE explore waypoints %d/%d, paid %d cr, known %s, revealed %d names: %s" % [c.waypoint, c.waypoints, c.credits_paid, st.known, st.revealed.size(), Survey.tally_text(to)])
	print("SMOKE explore finds %d (delivered %d)" % [found, Sector.discoveries.filter(func(x: Dictionary) -> bool: return bool(x["delivered"])).size()])
	print("SMOKE explore refused %s" % ("; ".join(refusals) if not refusals.is_empty() else "-"))
	var paid := 0
	var sum := 0
	for x in Sector.discoveries:
		if bool(x.get("paid", false)):
			paid += 1
			sum += int(x.get("bounty", 0))
	print("SMOKE explore bounty %d of %d finds paid, %d cr (income Discovery %d, Salvage %d), looted %s" % [paid, found, sum,
			int(income.get(DiscoveryBounty.SOURCE, 0)), int(income.get(DerelictLoot.INCOME_SOURCE, 0)), st.looted])
	for l in lines:
		print("SMOKE explore feed  %s" % l)


func _report(advanced: float, ms: int) -> void:
	var roles: Dictionary = {}
	var alive := 0
	for n in get_tree().get_nodes_in_group(Ship.GROUP):
		var s := n as Ship
		if s == null or s.dead or not _root.is_ancestor_of(s):
			continue
		alive += 1
		var role := String((s.get_script() as Script).get_global_name())
		roles[role] = int(roles.get(role, 0)) + 1
	var keys := roles.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for k in keys:
		parts.append("%s %d" % [String(k).trim_suffix("Ship"), roles[k]])
	var raids := _combat.raids if _combat else null
	print("SMOKE ---------------------------------------------")
	print("SMOKE sim advanced  %.0f s (%.1f min) in %.1f s real" % [advanced, advanced / 60.0, ms / 1000.0])
	print("SMOKE credits       %d   ore %s" % [Economy.credits, Economy.ore])
	print("SMOKE ships alive   %d: %s" % [alive, ", ".join(parts)])
	print("SMOKE raids         %d launched: %s" % [raids.raids_sent if raids else -1, ", ".join(_raids) if not _raids.is_empty() else "-"])
	print("SMOKE ore delivered %d in %d cargo drops" % [_cargo_ore, _cargo_n])
	print("SMOKE contracts     %d payouts, %d finished, %d listed" % [_payouts, _finished, ContractBoard.contracts.size()])
	var lg := Economy.ledger
	var lg_ok := lg.total() == Economy.credits - Economy.start_credits
	print("SMOKE ledger        %d entries, sum check %s (%d vs %d)" % [lg.entries.size(), "ok" if lg_ok else "FAIL", lg.total(), Economy.credits - Economy.start_credits])
	print("SMOKE log           %d errors (%d script), %d warnings" % [_log.errors, _log.script_errors, _log.warnings])
	for line in _log.first:
		print("SMOKE   %s" % line)
	print("SMOKE ---------------------------------------------")


# --- Planet outposts (--surface) ---------------------------------------------------------

func _surface_step(minute: int) -> void:
	var tree := get_tree()
	var outs := Outposts.of(tree)
	if minute == 0:
		Research.done[OutpostState.TECH] = SimClock.time
		Economy.add(20000, Economy.cost(1500, 400), Ledger.OTHER, "Smoke money")
		var w := SystemWorld.home(tree)
		var best: PlanetBody = null
		var why := ""
		for p in w.sys.planets:
			var bodies: Array = [p]
			for c in p.get_children():
				if c is PlanetBody:
					bodies.append(c)
			for b: PlanetBody in bodies:
				var pr := outs.found_problem(b)
				if pr.is_empty() and (best == null or b.def.type == PlanetDef.Type.OCEAN or b.def.type == PlanetDef.Type.ICE):
					best = b
				elif why.is_empty():
					why = "%s: %s" % [b.def.name, pr]
		if best == null:
			print("SMOKE surface      no world takes an outpost (%s)" % why)
			return
		_sf = outs.found(best)
		print("SMOKE surface      founding on %s (%s, danger %d, lift %d s)" % [_sf.planet, Economy.ore_name(_sf.good), _sf.danger, roundi(_sf.lift_seconds)])
		# A gas giant platform too, run as data only (fuel).
		for p in w.sys.planets:
			if p.def.type == PlanetDef.Type.GAS_GIANT and outs.found_problem(p).is_empty():
				_sf_gas = outs.found(p)
				print("SMOKE surface      platform on %s (%s, danger %d)" % [_sf_gas.planet, Economy.ore_name(_sf_gas.good), _sf_gas.danger])
				break
		return
	if _sf == null:
		return
	if minute == 1 and _sf_gas and _sf_gas.is_founded():
		outs.build(_sf_gas, OutpostState.BAY, 200.0, 0.0)
		outs.build(_sf_gas, OutpostState.GARRISON, -200.0, 0.0)
		for b in _sf_gas.buildings:
			b["built"] = 1.0
		for i in 2:
			outs.hire(_sf_gas, OutpostState.HARVESTER)
		outs.hire(_sf_gas, OutpostState.SOLDIER)
		for i in _sf_gas.deposits.size():
			outs.set_contract(_sf_gas, i, _sf_gas.fair_pay())
	if minute == 1 and _sf.is_founded():
		outs.build(_sf, OutpostState.BAY, 220.0, 0.0)
		outs.build(_sf, OutpostState.GARRISON, -220.0, 0.0)
		outs.build(_sf, OutpostState.TURRET, 0.0, 240.0)
		for b in _sf.buildings:
			b["built"] = 1.0
		for i in 2:
			outs.hire(_sf, OutpostState.HARVESTER)
			outs.hire(_sf, OutpostState.SOLDIER)
		for i in _sf.deposits.size():
			outs.set_contract(_sf, i, _sf.fair_pay())
		print("SMOKE surface      built %d, crew %d, contracts %d, %s" % [_sf.buildings.size(), _sf.crew.size(), _sf.contracts.size(), outs.hire_problem(_sf, OutpostState.HARVESTER)])
	if minute == 2:
		var sm := SurfaceMode.enter(tree, _sf)
		for i in 3:
			await tree.process_frame
		print("SMOKE surface      live: %s, units %d, hud %s" % [sm != null and SurfaceWorld.current(tree) != null, SurfaceWorld.current(tree).units.size() if SurfaceWorld.current(tree) else 0, sm.hud != null if sm else false])
	if minute == 3:
		# A building going up live: one node per building, however often its dict changes.
		var sw := SurfaceWorld.current(tree)
		Economy.add(5000, Economy.cost(500, 200), Ledger.OTHER, "Smoke money")
		var why := outs.spot_problem(_sf, OutpostState.DOME, 300.0, -320.0) + outs.build_problem(_sf, OutpostState.DOME)
		outs.build(_sf, OutpostState.DOME, 300.0, -320.0)
		if not why.is_empty():
			print("SMOKE surface      dome refused: %s" % why)
		for i in 30:
			outs.sim_step(0.1)
			sw.sim_step(0.1)
		print("SMOKE surface      building nodes %d for %d buildings (dome built %.2f)" % [sw._bnodes.size(), _sf.buildings.size(), float(_sf.building(OutpostState.DOME).get("built", -1.0))])
		if sw._bnodes.size() != _sf.buildings.size():
			_sf_reload_bad = true
	if minute == 4:
		# Raiders on the ground (forced raid at 3:35) go into a save.
		var sw := SurfaceWorld.current(tree)
		var left := sw.hostiles_left() if sw else {}
		var saved := false
		for od: Dictionary in Sector.save_state().get("outposts", []):
			if String(od.get("planet", "")) == _sf.planet and od.has("ground"):
				saved = true
		print("SMOKE surface      hostiles on the ground %s, in the save %s" % [left, saved])
		if not left.is_empty() and not saved:
			_sf_reload_bad = true
		# Escape opens the pause menu (not the hidden orbit selection), again closes it.
		var pm := tree.root.get_node_or_null(^"PauseMenu")
		var opened := false
		var closed := false
		for n in 2:
			var esc := InputEventKey.new()
			esc.keycode = KEY_ESCAPE
			esc.physical_keycode = KEY_ESCAPE
			esc.pressed = true
			get_viewport().push_input(esc)
			await tree.process_frame
			var esc_up := esc.duplicate() as InputEventKey
			esc_up.pressed = false
			get_viewport().push_input(esc_up)
			await tree.process_frame
			if n == 0:
				opened = pm != null and bool(pm.call(&"is_open"))
			else:
				closed = pm != null and not bool(pm.call(&"is_open"))
		print("SMOKE surface      escape: pause menu opened %s, closed %s, still on the surface %s" % [opened, closed, SurfaceMode.of(tree) != null])
		if not (opened and closed and SurfaceMode.of(tree) != null):
			_sf_reload_bad = true
		# Keys: M must not reach the hidden HUD, H leaves the surface.
		var hud := tree.get_first_node_in_group(HUD.GROUP) as HUD
		var map_was := hud.cluster_map.visible if hud else false
		for code in [KEY_M, KEY_H]:
			var ev := InputEventKey.new()
			ev.keycode = code
			ev.physical_keycode = code
			ev.pressed = true
			get_viewport().push_input(ev)
			await tree.process_frame
			var up := ev.duplicate() as InputEventKey
			up.pressed = false
			get_viewport().push_input(up)
		await tree.process_frame
		var keys_ok := hud != null and hud.cluster_map.visible == map_was and SurfaceMode.of(tree) == null
		print("SMOKE surface      keys: M kept off the HUD %s, H left %s" % [hud != null and hud.cluster_map.visible == map_was, SurfaceMode.of(tree) == null])
		if not keys_ok:
			_sf_reload_bad = true
		var sm := SurfaceMode.of(tree)
		if sm:
			sm.leave()
		await tree.process_frame
		print("SMOKE surface      left: live %s, hud %s" % [SurfaceWorld.current(tree) != null and not SurfaceWorld.current(tree).is_queued_for_deletion(), (tree.get_first_node_in_group(HUD.GROUP) as CanvasLayer).visible])
	if minute == 2 or minute == 4 or minute % 3 == 0:
		print("SMOKE surface m%-2d  stock %d, lifts %d, delivered %d, loads %d, crew %d, owed %d, nests ag %s" % [minute, _sf.stock[_sf.good], _sf.lifts.size(), _sf.delivered[_sf.good], _sf.loads_total,
				_sf.crew.size(), _sf.upkeep_owed, ", ".join(_sf.nests.map(func(n: Dictionary) -> String: return "%d" % roundi(float(n["agitation"]))))])
	# A critter wave and a ground raid: live at minute 3, as data at minute 7.
	if minute == 3 or minute == 7:
		_sf.nests[0]["agitation"] = 45.0
		_sf.next_raid = SimClock.time + 35.0
		_sf.raid = {}
	# A full save and reload at minute 9 (through SaveManager.load_snapshot).
	if minute == 9:
		var key := _sf.key()
		var before := _sf_census(_sf)
		var data: Dictionary = bytes_to_var(var_to_bytes(GameSnapshot.capture(tree)))
		await SaveManager.load_snapshot(data)
		for i in 5:
			await tree.process_frame
		_find_home()
		_sf = Sector.outposts.get(key) as OutpostState
		var after := _sf_census(_sf) if _sf else "missing"
		print("SMOKE surface      save reload %s%s" % ["ok" if before == after else "DIFF", "" if before == after else ": %s -> %s" % [before, after]])
		if before != after:
			_sf_reload_bad = true
		if _sf == null:
			return
	# Round trip through the save at minute 5.
	if minute == 5:
		var before := JSON.stringify(_sf.to_dict(), "", true)
		var back := OutpostState.from_dict(JSON.parse_string(JSON.stringify(_sf.to_dict())))
		var after := JSON.stringify(back.to_dict(), "", true)
		print("SMOKE surface      dict round trip %s" % ("ok" if before == after else "DIFF"))
		if before != after:
			_sf.set_meta(&"rt_bad", true)
			var da: Dictionary = _sf.to_dict()
			var db: Dictionary = back.to_dict()
			for k: String in db:
				if not da.has(k):
					print("SMOKE surface      rt extra key %s" % k)
			for k: String in da:
				if JSON.stringify(da[k], "", true) != JSON.stringify(db.get(k), "", true):
					print("SMOKE surface      rt %s: %s -> %s" % [k, JSON.stringify(da[k]).left(160), JSON.stringify(db.get(k)).left(160)])


func _sf_census(o: OutpostState) -> String:
	var loads := 0
	for d in o.deposits:
		loads += int(d["loads"])
	return "b%d c%d d%d/%d n%d st%d del%d k%d sh%d" % [o.buildings.size(), o.crew.size(), o.deposits.size(), loads, o.nests.size(), o.stock[o.good], o.delivered[o.good], o.contracts.size(), o.shuttles]


func _surface_report() -> String:
	if _sf == null:
		return "--surface: no outpost founded"
	var fights: PackedStringArray = []
	for e: Dictionary in EventLog.entries:
		var t := String(e["text"]).to_lower()
		if t.contains("critters") or t.contains("raiders") or t.contains("ground raid") or t.contains("disabled") or t.contains("destroyed on"):
			fights.append("%s %s" % [Fmt.clock(float(e["time"])), t.left(110)])
	for f in fights:
		print("SMOKE surface fight %s" % f)
	if _sf_gas:
		_sf_gas = Sector.outposts.get(_sf_gas.key(), _sf_gas) as OutpostState
		print("SMOKE surface gas   %s: delivered %s, loads %d, crew %d, lost %s" % [_sf_gas.planet, Economy.cost_text(_sf_gas.delivered), _sf_gas.loads_total, _sf_gas.crew.size(), _sf_gas.lost])
		if _sf_gas.delivered[Economy.Ore.FUEL] <= 0 and not _sf_gas.lost:
			return "the gas giant platform delivered no fuel"
	if _sf_reload_bad:
		return "outpost changed over a save reload"
	if fights.size() < 4:
		return "fewer than 4 surface fight lines (live and data waves and raids)"
	var hs := _sf.crew_of(OutpostState.HARVESTER).size()
	print("SMOKE surface end  %s: delivered %s, loads %d, harvesters %d, soldiers %d, lost %s" % [_sf.planet, Economy.cost_text(_sf.delivered), _sf.loads_total, hs,
			_sf.crew_of(OutpostState.SOLDIER).size(), _sf.lost])
	var f := Factory.find(SystemWorld.home(get_tree()))
	var price := f.market.willing_price(_sf.good) if f else 6.0
	var mins := maxf((SimClock.time - _sf.founded_at) / 60.0, 0.1)
	var worth := _sf.delivered[_sf.good] * price
	var pay := 0
	for c in _sf.crew_of(OutpostState.HARVESTER):
		pay += int(c.get("wallet", 0))
	var net := (worth - pay - OutpostState.UPKEEP * mins) / mins
	print("SMOKE surface econ  %.1f min founded, %d units at %.1f cr = %d cr, harvester wallets %d cr (pay net of fees), upkeep %d: net %d cr/min, %.2f loads/min per harvester" % [mins,
			_sf.delivered[_sf.good], price, roundi(worth), pay, roundi(OutpostState.UPKEEP * mins), roundi(net), _sf.loads_total / mins / maxf(hs, 1.0)])
	if _sf.has_meta(&"rt_bad"):
		return "outpost dict round trip changed the state"
	if _sf.delivered[_sf.good] <= 0:
		return "the outpost delivered nothing to the station"
	return ""

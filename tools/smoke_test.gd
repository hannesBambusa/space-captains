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
var save_roundtrip := false
var colony := false
var net_seed := -1
var _multi: PackedStringArray = []

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
		elif a == "--save-roundtrip":
			save_roundtrip = true
		elif a == "--colony":
			colony = true
		elif a.begins_with("--net-seed="):
			net_seed = a.trim_prefix("--net-seed=").to_int()
	_log = SmokeLogger.new()
	OS.add_logger(_log)
	seed(SEED)
	get_tree().node_added.connect(_on_node_added)
	_run.call_deferred()


func _on_node_added(n: Node) -> void:
	if not n.ready.is_connected(_seed_rngs):
		n.ready.connect(_seed_rngs.bind(n), CONNECT_ONE_SHOT)


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
	var why := "%d trip checks on another system's contract" % _fw_wrong if _fw_wrong > 0 else ""
	if _fw_factory_bad:
		why = "a forward Factory keeps its own reserve or held ore (see SMOKE forward factory)"
	if save_roundtrip and not _rt_ok:
		why = "save round trip changed the game (see SMOKE forward reload)"
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
		for i in (2 if id == &"mining_outpost" else 1):
			b.hire()
	var sys := _sys
	var station := sys.home_station.global_position if sys and sys.home_station else Vector3.ZERO
	var best: AsteroidCluster = null
	for c in sys.belts if sys else []:
		if best == null or c.global_position.distance_to(station) < best.global_position.distance_to(station):
			best = c
	if best:
		ContractBoard.post_mining(best, 40)


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

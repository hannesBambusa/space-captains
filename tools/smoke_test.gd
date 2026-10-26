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
## The default run never touches them.

const SEED := 12345
## --explore: the gate network seed and the longest run, sim seconds.
const EXPLORE_SEED := 4242
const EXPLORE_MAX := 2400.0
## --long: the network seed and the shortest run, sim minutes.
const LONG_SEED := 3
const LONG_MINUTES := 40.0
const STALL_TIME := 3.0
const MAX_REAL_TIME := 300.0

var minutes: float = 10.0
var multi := false
var explore := false
var long_run := false
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
	if long_run:
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
		left -= SimStepper.run(tree, minf(60.0, left))
		minute += 1
		await tree.process_frame
	if multi:
		_multi_report()
	if long_run:
		_long_report()
	_finish(Time.get_ticks_msec() - t0)


func _finish(ms: int, why: String = "") -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(_mgr):
		_report(SimClock.time - _start_time, ms)
	if not why.is_empty():
		print("SMOKE FAIL: %s" % why)
	get_tree().quit(1 if _log.script_errors > 0 or not why.is_empty() else 0)


## Watchdog: a script error ends the run coroutine without a report.
func _process(delta: float) -> void:
	_real += delta
	if _done:
		return
	if _log.script_errors > 0:
		_stall += delta
	if _stall > STALL_TIME:
		_finish(int(_real * 1000.0), "run stopped after a script error")
	elif _real > MAX_REAL_TIME:
		_finish(int(_real * 1000.0), "timed out after %.0f s" % MAX_REAL_TIME)


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

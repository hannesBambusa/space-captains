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
## Args after "--": --minutes=N (default 10).

const SEED := 12345
const STALL_TIME := 3.0
const MAX_REAL_TIME := 300.0

var minutes: float = 10.0

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
	var left := minutes * 60.0
	while left > 0.0:
		left -= SimStepper.run(tree, minf(60.0, left))
		await tree.process_frame
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
	Economy.add(20000)
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
	print("SMOKE log           %d errors (%d script), %d warnings" % [_log.errors, _log.script_errors, _log.warnings])
	for line in _log.first:
		print("SMOKE   %s" % line)
	print("SMOKE ---------------------------------------------")

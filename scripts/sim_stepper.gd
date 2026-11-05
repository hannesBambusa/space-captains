class_name SimStepper
extends RefCounted
## Fast-forwards the simulation inside one frame: advances SimClock, moves
## the orbits and clusters of every live system ([SystemWorld]), steps every
## ship and every other sim node in all of them (group
## [constant GROUP]: projectiles, effects, dens, scrap fields, the raid
## director), in fixed steps. Used by the demos (--advance) and by tests.
## Ignores pause on purpose.
##
## Profiling: with "--profile" among the user args (after "--"), every step
## is timed per kind (ships by brain class, other nodes by script class,
## the orbits as "bodies") and every [constant PROFILE_EVERY] sim seconds a
## "STEPPROF" line prints the top kinds in real ms per sim minute. Off
## otherwise (one bool check per step).

## Non-ship nodes with a sim_step(dt) method join this group.
const GROUP := "sim_step"
## Sim seconds between STEPPROF lines.
const PROFILE_EVERY := 300.0

## -1 unknown, 0 off, 1 on.
static var _prof := -1
static var _prof_usec := {}
static var _prof_from := 0.0


## Advances up to [param seconds] sim seconds in [param step] increments.
## Stops early when [param until] returns true. Returns the seconds advanced.
static func run(tree: SceneTree, seconds: float, step: float = 0.1, until: Callable = Callable()) -> float:
	if _prof < 0:
		_prof = 1 if OS.get_cmdline_user_args().has("--profile") else 0
		_prof_from = SimClock.time
	if _prof == 1:
		return _run_profiled(tree, seconds, step, until)
	var systems: Array[SolarSystem] = []
	for w in SystemWorld.all(tree):
		if w.sys:
			systems.append(w.sys)
	var done := 0.0
	while done < seconds:
		var h := minf(step, seconds - done)
		SimClock.advance(h)
		for sys in systems:
			sys.update_bodies(SimClock.time)
		for n in tree.get_nodes_in_group(Ship.GROUP):
			if is_instance_valid(n) and not n.is_queued_for_deletion():
				(n as Ship).sim_step(h)
		for n in tree.get_nodes_in_group(GROUP):
			if is_instance_valid(n) and not n.is_queued_for_deletion():
				n.call(&"sim_step", h)
		done += h
		if until.is_valid() and until.call():
			break
	return done


## [method run] with every step timed per kind (see the class notes).
static func _run_profiled(tree: SceneTree, seconds: float, step: float, until: Callable) -> float:
	var systems: Array[SolarSystem] = []
	for w in SystemWorld.all(tree):
		if w.sys:
			systems.append(w.sys)
	var done := 0.0
	while done < seconds:
		var h := minf(step, seconds - done)
		SimClock.advance(h)
		var t0 := Time.get_ticks_usec()
		for sys in systems:
			sys.update_bodies(SimClock.time)
		_add("bodies", t0)
		for n in tree.get_nodes_in_group(Ship.GROUP):
			if is_instance_valid(n) and not n.is_queued_for_deletion():
				var s := n as Ship
				var t1 := Time.get_ticks_usec()
				s.sim_step(h)
				_add(_kind_of(s.brain) if s.brain else "ship " + _kind_of(s), t1)
		for n in tree.get_nodes_in_group(GROUP):
			if is_instance_valid(n) and not n.is_queued_for_deletion():
				var t2 := Time.get_ticks_usec()
				n.call(&"sim_step", h)
				_add(_kind_of(n), t2)
		done += h
		if SimClock.time - _prof_from >= PROFILE_EVERY:
			_print_profile()
		if until.is_valid() and until.call():
			break
	return done


static func _kind_of(o: Object) -> String:
	var sc := o.get_script() as Script if o else null
	if sc:
		var g := sc.get_global_name()
		return String(g) if not g.is_empty() else sc.resource_path.get_file()
	return o.get_class() if o else "?"


static func _add(kind: String, since: int) -> void:
	_prof_usec[kind] = int(_prof_usec.get(kind, 0)) + Time.get_ticks_usec() - since


static func _print_profile() -> void:
	var minutes := (SimClock.time - _prof_from) / 60.0
	var keys := _prof_usec.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(_prof_usec[a]) > int(_prof_usec[b]))
	var total := 0
	for k: String in keys:
		total += int(_prof_usec[k])
	var parts: PackedStringArray = []
	for k: String in keys.slice(0, 10):
		parts.append("%s %.0f" % [k, int(_prof_usec[k]) / 1000.0 / minutes])
	print("STEPPROF %s: %.0f ms per sim min in all; %s" % [Fmt.clock(SimClock.time), total / 1000.0 / minutes, ", ".join(parts)])
	_prof_usec.clear()
	_prof_from = SimClock.time

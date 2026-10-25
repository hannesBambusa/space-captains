class_name SimStepper
extends RefCounted
## Fast-forwards the simulation inside one frame: advances SimClock, moves
## the orbits and clusters, steps every ship and every other sim node (group
## [constant GROUP]: projectiles, effects, dens, scrap fields, the raid
## director), in fixed steps. Used by the demos (--advance) and by tests.
## Ignores pause on purpose.

## Non-ship nodes with a sim_step(dt) method join this group.
const GROUP := "sim_step"


## Advances up to [param seconds] sim seconds in [param step] increments.
## Stops early when [param until] returns true. Returns the seconds advanced.
static func run(tree: SceneTree, seconds: float, step: float = 0.1, until: Callable = Callable()) -> float:
	var sys := SolarSystem.of(tree)
	var done := 0.0
	while done < seconds:
		var h := minf(step, seconds - done)
		SimClock.advance(h)
		if sys:
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

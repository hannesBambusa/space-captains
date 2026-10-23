class_name MiningContract
extends Contract
## Mine a belt: the player pays [member reward] credits for every load a miner
## delivers to its outpost; the ore turns into materials (MiningRules).
## [member max_loads] > 0 caps the contract; it completes when that many loads
## are delivered. Loads already on a trip count against the cap.

var belt: SystemBelt
var ore_type: AsteroidBelt.OreType = AsteroidBelt.OreType.IRON
var max_loads: int = 0
var loads_delivered: int = 0
## Loads promised to ships currently on a trip.
var loads_in_flight: int = 0
var materials_delivered: int = 0


func _init(on_belt: SystemBelt = null, credits_per_load: int = 0, load_limit: int = 0) -> void:
	type = Type.MINING
	belt = on_belt
	target = on_belt
	reward = credits_per_load
	max_loads = maxi(load_limit, 0)
	if on_belt and on_belt.def:
		ore_type = on_belt.def.ore_type


func is_available() -> bool:
	if not super.is_available():
		return false
	return max_loads <= 0 or loads_delivered + loads_in_flight < max_loads


func add_taker(ship: Node) -> bool:
	if not super.add_taker(ship):
		return false
	loads_in_flight += 1
	return true


## Ends a trip. [param delivered] = the load reached the outpost.
func finish_trip(ship: Node, delivered: bool) -> void:
	if not takers.has(ship):
		return
	loads_in_flight = maxi(loads_in_flight - 1, 0)
	if delivered:
		loads_delivered += 1
	takers.erase(ship)
	if not is_finished() and max_loads > 0 and loads_delivered >= max_loads:
		_set_status(Status.COMPLETED)
	else:
		_update_status()


func get_target_name() -> String:
	return belt.def.name if is_instance_valid(belt) and belt.def else super.get_target_name()


func get_reward_text() -> String:
	return "%d cr/load" % reward


func get_progress_text() -> String:
	if max_loads > 0:
		return "%d / %d loads" % [loads_delivered, max_loads]
	return "%d loads" % loads_delivered


## The belt spans a whole ring: the site is the stretch of it nearest to
## [param from] (the asker's outpost; the home station for markers).
func get_site_position(from: Vector3 = Vector3.ZERO) -> Vector3:
	if not is_instance_valid(belt):
		return Vector3.ZERO
	return SpaceNav.nearest_belt_point(belt, from)


func get_danger() -> int:
	return belt.danger if is_instance_valid(belt) else 1

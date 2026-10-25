class_name LoadContract
extends Contract
## Base for the contracts paid per load a ship brings home (mining, planet
## raid, salvage): every taker is one load on a trip ([member loads_in_flight])
## until [method finish_trip]. [member max_loads] > 0 caps the contract;
## loads already on a trip count against the cap, and it completes when that
## many loads are delivered. Once the site is used up ([method _is_exhausted])
## it completes as soon as the last trip on it ends.

var max_loads: int = 0
var loads_delivered: int = 0
## Loads promised to ships currently on a trip.
var loads_in_flight: int = 0


func is_available() -> bool:
	if not super.is_available():
		return false
	return max_loads <= 0 or loads_delivered + loads_in_flight < max_loads


func add_taker(ship: Node) -> bool:
	if not super.add_taker(ship):
		return false
	loads_in_flight += 1
	return true


## Ends a trip. [param delivered] = the load reached home.
func finish_trip(ship: Node, delivered: bool) -> void:
	if not takers.has(ship):
		return
	loads_in_flight = maxi(loads_in_flight - 1, 0)
	if delivered:
		loads_delivered += 1
	takers.erase(ship)
	if not is_finished() and max_loads > 0 and loads_delivered >= max_loads:
		_set_status(Status.COMPLETED)
	elif not is_finished() and _is_exhausted() and takers.is_empty():
		_set_status(Status.COMPLETED)
	else:
		_update_status()


func get_reward_text() -> String:
	return "%d cr/load" % reward


## True when the site has nothing left for new trips.
func _is_exhausted() -> bool:
	return false


## No new trips: completes now, or once the last trip ends.
func _complete_when_idle() -> void:
	if is_finished():
		return
	if takers.is_empty():
		_set_status(Status.COMPLETED)
	else:
		changed.emit(self)

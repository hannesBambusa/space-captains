class_name EscortContract
extends Contract
## Fly with a miner and keep it safe. Two forms:
## - on one miner ([member ward]): escorts join that ship's trips;
## - on a mining contract ([member mining_contract], posted from the belt
##   panel as "Escorted"): escorts join any miner on a trip for it.
## Each escort is assigned to one miner ([member assignments]); at most
## [member max_escorts] per miner. Pay: [member reward] credits to each
## escort per completed escorted trip (the miner delivers its load with the
## escort near), paid from the player's credits on delivery. Like Majesty's
## protect flag. Cancelled automatically when the ward is lost or the mining
## contract ends.
## A third use (F6): the ward is a [MobileStation] flying to its new
## system; one trip = the whole flight, paid on the founding
## (MobileStation.finish_convoy). While the convoy is data the ward is
## null and [member ward_id] holds its save id (saved, linked again when it
## is built live).

## Escorts farther than this from their miner at delivery are not paid, metres.
const PAY_DISTANCE := 3000.0

var ward: Ship
var mining_contract: MiningContract
var max_escorts: int = 2
## Save id of a ward that is data now (a mobile station in the jump or in
## a system not live), 0 = none; [member ward_name] for the rows meanwhile.
var ward_id: int = 0
var ward_name: String = ""
var trips_completed: int = 0
## escort Ship -> miner Ship
var assignments: Dictionary = {}


func _init(ward_ship: Ship = null, linked: MiningContract = null, pay_per_trip: int = 0, escorts_per_miner: int = 2) -> void:
	type = Type.ESCORT
	ward = ward_ship
	mining_contract = linked
	reward = pay_per_trip
	max_escorts = maxi(escorts_per_miner, 1)
	if ward_ship:
		target = ward_ship
	elif linked:
		target = linked.belt


func is_linked() -> bool:
	return ward == null and mining_contract != null


## Miners this contract protects right now.
func covered_miners() -> Array[Ship]:
	var out: Array[Ship] = []
	if ward:
		if is_instance_valid(ward) and not ward.dead:
			out.append(ward)
	elif mining_contract:
		for t in mining_contract.takers:
			var s := t as Ship
			if is_instance_valid(s) and not s.dead:
				out.append(s)
	return out


func covers(miner: Ship, contract: Contract) -> bool:
	if ward:
		return miner == ward
	return mining_contract != null and contract == mining_contract


func escorts_of(miner: Ship) -> Array[Ship]:
	var out: Array[Ship] = []
	for e in assignments:
		if is_instance_valid(e) and assignments[e] == miner:
			out.append(e as Ship)
	return out


## The miner a new escort should join: the covered one with the fewest
## escorts and a free place. Null when none needs one.
func pick_ward() -> Ship:
	var best: Ship = null
	var best_n := max_escorts
	for m in covered_miners():
		var n := escorts_of(m).size()
		if n < best_n:
			best_n = n
			best = m
	return best


func is_available() -> bool:
	if is_finished():
		return false
	if ward:
		return is_instance_valid(ward) and not ward.dead and escorts_of(ward).size() < max_escorts
	if mining_contract == null or mining_contract.is_finished():
		return false
	return takers.size() < max_escorts * maxi(covered_miners().size(), 1)


func assign(escort: Ship, miner: Ship) -> void:
	assignments[escort] = miner


func unassign(escort: Ship) -> void:
	assignments.erase(escort)


func miner_of(escort: Ship) -> Ship:
	var o = assignments.get(escort)
	if not is_instance_valid(o):
		return null
	var m := o as Ship
	return m if m and not m.dead else null


func remove_taker(ship: Node) -> void:
	assignments.erase(ship)
	super.remove_taker(ship)


func get_target_name() -> String:
	if ward_id != 0 and not is_instance_valid(ward):
		return ward_name if not ward_name.is_empty() else "?"
	if ward:
		return ward.get_display_name() if is_instance_valid(ward) else "?"
	if mining_contract:
		return "%s miners" % mining_contract.get_target_name()
	return super.get_target_name()


func get_title() -> String:
	return "Escort: %s" % get_target_name()


func get_reward_text() -> String:
	return "%d cr/trip" % reward


func get_progress_text() -> String:
	return "%d trip%s" % [trips_completed, "" if trips_completed == 1 else "s"]


func get_danger() -> int:
	if is_instance_valid(ward) and ward is MobileStation:
		return (ward as MobileStation).route_danger()
	if mining_contract:
		return mining_contract.get_danger()
	if is_instance_valid(ward) and ward.brain and ward.brain.trip and ward.brain.trip.contract:
		return ward.brain.trip.contract.get_danger()
	return 1


## A mobile station waiting with nobody on its contract.
func get_warning_text() -> String:
	if is_instance_valid(ward) and ward is MobileStation and (ward as MobileStation).state == MobileStation.State.WAITING and escorts_of(ward).is_empty():
		return "No escort: %s is waiting" % ward.get_display_name()
	return ""


func get_warning_hint() -> String:
	return "Hire mercenaries or raise escort pay" if not get_warning_text().is_empty() else ""


func get_site_position(from: Vector3 = Vector3.ZERO) -> Vector3:
	if is_instance_valid(ward):
		return ward.global_position
	if mining_contract:
		return mining_contract.get_site_position(from)
	return super.get_site_position(from)


## Called by the board after a covered miner delivered with escorts paid.
func note_trip_completed() -> void:
	trips_completed += 1
	changed.emit(self)

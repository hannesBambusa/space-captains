class_name SalvageContract
extends Contract
## Salvage a scrap field: the player pays [member reward] credits for every
## load a salvager delivers to its yard; the scrap turns into materials
## ([constant MATERIALS_PER_SCRAP] each). One load is [constant LOAD_SCRAP]
## scrap times the ship's hold. Scrap promised to ships on a trip is
## reserved, so takers never outnumber what is left. Completes when the field
## is stripped or gone. While the contract is open the field does not fade.
## Danger comes from the place: near a living Scavenger Den, or the belt the
## field lies in.

const LOAD_SCRAP := 20
const MATERIALS_PER_SCRAP := 1.0
## Fair pay per load.
const FAIR_REWARD := 40
## Chance per delivered load of a rare part (den ruins: [constant DEN_RARE_CHANCE]).
const RARE_CHANCE := 0.06
const DEN_RARE_CHANCE := 0.14
## Den danger reach, metres.
const DEN_NEAR := 3500.0
const DEN_FAR := 7000.0

static var rng := RandomNumberGenerator.new()

var field: ScrapField
var loads_delivered: int = 0
var loads_in_flight: int = 0
var materials_delivered: int = 0
var rare_chance: float = RARE_CHANCE


func _init(on_field: ScrapField = null, credits_per_load: int = 0, taker_limit: int = 3) -> void:
	type = Type.SALVAGE
	field = on_field
	target = on_field
	reward = credits_per_load
	max_takers = taker_limit
	if on_field and on_field.get_meta(&"den_ruins", false):
		rare_chance = DEN_RARE_CHANCE


func is_available() -> bool:
	if not super.is_available() or not is_instance_valid(field):
		return false
	return field.amount - loads_in_flight * LOAD_SCRAP > 0


func add_taker(ship: Node) -> bool:
	if not super.add_taker(ship):
		return false
	loads_in_flight += 1
	return true


## Ends a trip. [param delivered] = the load reached the yard.
func finish_trip(ship: Node, delivered: bool) -> void:
	if not takers.has(ship):
		return
	loads_in_flight = maxi(loads_in_flight - 1, 0)
	if delivered:
		loads_delivered += 1
	takers.erase(ship)
	if not is_finished() and (not is_instance_valid(field) or field.amount <= 0) and takers.is_empty():
		_set_status(Status.COMPLETED)
	else:
		_update_status()


## The field was stripped or left: no new takers; done once the last trip ends.
func mark_done() -> void:
	if is_finished():
		return
	if takers.is_empty():
		_set_status(Status.COMPLETED)
	else:
		changed.emit(self)


func get_target_name() -> String:
	return field.get_display_name() if is_instance_valid(field) else "Scrap field"


func get_reward_text() -> String:
	return "%d cr/load" % reward


func get_progress_text() -> String:
	var left := "%d scrap left" % field.amount if is_instance_valid(field) else "stripped"
	return "%d loads, %s" % [loads_delivered, left]


func get_danger() -> int:
	if not is_instance_valid(field) or not field.is_inside_tree():
		return 1
	return danger_at(field.get_tree(), field.global_position)


## Danger 1..5 at [param pos]: living dens nearby, else the belt it lies in.
static func danger_at(tree: SceneTree, pos: Vector3) -> int:
	var sys := tree.get_first_node_in_group(SolarSystem.GROUP) as SolarSystem
	if sys == null:
		return 1
	var d := 1
	for den in sys.dens:
		if not is_instance_valid(den) or not den.is_alive():
			continue
		var dist := Combat.flat_distance(pos, den.global_position)
		if dist < DEN_NEAR:
			d = maxi(d, 4)
		elif dist < DEN_FAR:
			d = maxi(d, 3)
	for b in sys.belts:
		if SpaceNav.distance_to_belt(b, pos) < b.def.width * 0.5 + 900.0:
			d = maxi(d, b.danger)
	return d

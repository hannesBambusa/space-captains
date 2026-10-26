class_name SalvageContract
extends LoadContract
## Salvage a scrap field. Every delivered load goes to the salvager's
## Salvage Yard, which pays [constant FAIR_REWARD] per load from its own funds
## and reprocesses the scrap into ore (SalvageYard). One load is
## [constant LOAD_SCRAP] scrap times the ship's hold.
## Free salvage: every scrap field has one unlisted [member free] contract
## ([method free_for], reward 0, never on the board) that salvagers pick on
## their own. A player-posted contract adds [member reward] credits per load
## on top of the yard's pay (a bonus that draws salvagers to that field
## first); while it is open the field does not fade.
## Scrap promised to ships on a trip is reserved across every contract on the
## field ([method reserved_loads]), so takers never outnumber what is left,
## and no more than SalvagerShip.SLOT_COUNT ships work one field. Completes
## when the field is stripped or gone. Danger comes from the place: near a
## living Scavenger Den, or the belt the field lies in.

const LOAD_SCRAP := 20
const MATERIALS_PER_SCRAP := 1.0
## Fair pay per load (what the yard pays; player contracts add a bonus).
const FAIR_REWARD := 40
## Chance per delivered load of a rare part (den ruins: [constant DEN_RARE_CHANCE]).
const RARE_CHANCE := 0.06
const DEN_RARE_CHANCE := 0.14
## Den danger reach, metres.
const DEN_NEAR := 3500.0
const DEN_FAR := 7000.0

static var rng := RandomNumberGenerator.new()
## Free salvage contracts: ScrapField instance id -> SalvageContract.
static var _free: Dictionary = {}
static var _next_free_id := -1

var field: ScrapField
var materials_delivered: int = 0
var rare_chance: float = RARE_CHANCE
## Free salvage (not on the board, the yard's pay only).
var free: bool = false


func _init(on_field: ScrapField = null, credits_per_load: int = 0, taker_limit: int = 3) -> void:
	type = Type.SALVAGE
	field = on_field
	target = on_field
	reward = credits_per_load
	max_takers = taker_limit
	if on_field and on_field.get_meta(&"den_ruins", false):
		rare_chance = DEN_RARE_CHANCE


## The free salvage contract of [param f] (made on first use), or null.
static func free_for(f: ScrapField) -> SalvageContract:
	if f == null or not is_instance_valid(f) or f.is_queued_for_deletion():
		return null
	var key := f.get_instance_id()
	var c := _free.get(key) as SalvageContract
	if c:
		return c
	c = SalvageContract.new(f, 0, SalvagerShip.SLOT_COUNT)
	c.free = true
	c.id = _next_free_id
	_next_free_id -= 1
	c.created_time = SimClock.time
	_register_free(f, c)
	return c


## Keeps [param c] as [param f]'s free salvage until the field is stripped
## or gone.
static func _register_free(f: ScrapField, c: SalvageContract) -> void:
	var key := f.get_instance_id()
	_free[key] = c
	f.depleted.connect(func(_f: ScrapField) -> void: c.mark_done())
	f.tree_exiting.connect(func() -> void:
		c.mark_done()
		_free.erase(key))


## Free salvage contracts open now, one per scrap field with scrap left.
static func free_contracts(ctx: Node) -> Array[Contract]:
	var out: Array[Contract] = []
	for f in ScrapField.all(ctx):
		if f.amount <= 0:
			continue
		var c := free_for(f)
		if c and c.is_available():
			out.append(c)
	return out


## True while a salvager is on a free salvage trip to [param f].
static func free_in_use(f: ScrapField) -> bool:
	var c := _free.get(f.get_instance_id()) as SalvageContract if f else null
	return c != null and not c.takers.is_empty()


## Every salvage contract on [param f]: its free one and the posted ones.
static func all_on(f: ScrapField) -> Array[SalvageContract]:
	var out: Array[SalvageContract] = []
	if f == null or not is_instance_valid(f):
		return out
	var fc := _free.get(f.get_instance_id()) as SalvageContract
	if fc:
		out.append(fc)
	for c in ContractBoard.get_for_target(f):
		if c is SalvageContract and not c.is_finished():
			out.append(c as SalvageContract)
	return out


## Loads on their way from [param f] (reserved scrap), every contract.
static func reserved_loads(f: ScrapField) -> int:
	var n := 0
	for c in all_on(f):
		n += c.loads_in_flight
	return n


## Salvagers working [param f] now, every contract.
static func workers_on(f: ScrapField) -> int:
	var n := 0
	for c in all_on(f):
		n += c.takers.size()
	return n


func is_available() -> bool:
	if not super.is_available() or not is_instance_valid(field):
		return false
	if workers_on(field) >= SalvagerShip.SLOT_COUNT:
		return false
	return field.amount - reserved_loads(field) * LOAD_SCRAP > 0


func _is_exhausted() -> bool:
	return not is_instance_valid(field) or field.amount <= 0


## The field was stripped or left: no new takers; done once the last trip ends.
func mark_done() -> void:
	_complete_when_idle()


func get_target_name() -> String:
	return field.get_display_name() if is_instance_valid(field) else "Scrap field"


func get_type_name() -> String:
	return "free salvage" if free else super.get_type_name()


func get_reward_text() -> String:
	if free:
		return "yard pays %d cr/load" % FAIR_REWARD
	return "%d cr/load bonus + yard %d" % [reward, FAIR_REWARD]


func get_progress_text() -> String:
	var left := "%d scrap left" % field.amount if is_instance_valid(field) else "stripped"
	return "%d loads, %s" % [loads_delivered, left]


func get_danger() -> int:
	if not is_instance_valid(field) or not field.is_inside_tree():
		return 1
	return danger_at(field, field.global_position)


## Danger 1..5 at [param pos]: living dens nearby, else the cluster it lies in.
static func danger_at(ctx: Node, pos: Vector3) -> int:
	var sys := SolarSystem.of(ctx)
	if sys == null:
		return 1
	var d := 1
	for den in sys.dens:
		if not is_instance_valid(den) or not den.is_alive():
			continue
		var dist := SpaceNav.flat_distance(pos, den.global_position)
		if dist < DEN_NEAR:
			d = maxi(d, 4)
		elif dist < DEN_FAR:
			d = maxi(d, 3)
	for b in sys.belts:
		if b.distance_to(pos) < 900.0:
			d = maxi(d, b.danger)
	return d


## Puts a loaded free salvage contract back as [param f]'s (see [method free_for]).
static func restore_free(f: ScrapField, c: SalvageContract) -> void:
	if f == null or c == null:
		return
	c.free = true
	_next_free_id = mini(_next_free_id, c.id - 1)
	_register_free(f, c)

extends Node
## Autoload "Economy". The player's resources: credits (pay contractors) and
## typed ore (iron, titanium, crystal: for building, tooling, and to sell to
## the Factory). Everything that costs something goes through
## [method can_afford] and [method spend]; ore costs are PackedInt32Array in
## [enum Ore] order (see [method cost]). [member materials] is the total of
## all ore, for old callers and the [signal changed] signal.
##
## Income (Majesty style, stage 2): captains spend a share of every payment
## at the station (docking and service fees, see Captain.station_spend_share),
## which comes back through [method add_income]; a small corporate grant is
## paid every [member grant_interval] sim seconds. Each income shows as a
## green delta in the top bar ([signal income]). Selling ore to the Factory
## (FactoryMarket) is income too.

## [param materials] is the ore total; read [member ore] for the types.
signal changed(credits: int, materials: int)
## Credits that came in (fees, grant). [param source] is a short reason.
signal income(amount: int, source: String)
## A cargo shuttle landed [param ore] (Ore order) at the station.
signal cargo_received(ore: PackedInt32Array, source: String)

enum Ore { IRON, TITANIUM, CRYSTAL }

const ORE_NAMES: PackedStringArray = ["Iron", "Titanium", "Crystal"]
## UI colours, close to the ore veins on the asteroids.
const ORE_COLORS: Array[Color] = [Color(0.95, 0.6, 0.42), Color(0.8, 0.85, 0.94), Color(0.42, 0.9, 1.0)]

@export var start_credits: int = 2000
## Iron, titanium, crystal at start.
@export var start_ore: PackedInt32Array = PackedInt32Array([300, 80, 0])
## Corporate grant, credits per sim minute.
@export var grant_per_minute: float = 30.0
## The grant is paid in installments this often, sim seconds.
@export var grant_interval: float = 20.0

var credits: int = 0
## Iron, titanium, crystal.
var ore := PackedInt32Array([0, 0, 0])
## All ore together.
var materials: int:
	get: return ore[0] + ore[1] + ore[2]
## Totals for tests and the UI.
var total_fees: int = 0
var total_grants: int = 0

var _grant_clock: float = 0.0
var _last_time: float = 0.0


func _ready() -> void:
	reset()


## Start values (a new game).
func reset() -> void:
	credits = start_credits
	ore = PackedInt32Array([0, 0, 0])
	for i in ore.size():
		ore[i] = start_ore[i] if i < start_ore.size() else 0
	total_fees = 0
	total_grants = 0
	_grant_clock = 0.0
	_last_time = SimClock.time
	changed.emit(credits, materials)


func save_state() -> Dictionary:
	return {"credits": credits, "ore": ore, "total_fees": total_fees, "total_grants": total_grants, "grant_clock": _grant_clock}


## Call after SimClock is restored (the grant counts from its time).
func load_state(d: Dictionary) -> void:
	credits = int(d.get("credits", start_credits))
	ore = PackedInt32Array(d.get("ore", start_ore))
	total_fees = int(d.get("total_fees", 0))
	total_grants = int(d.get("total_grants", 0))
	_grant_clock = float(d.get("grant_clock", 0.0))
	_last_time = SimClock.time
	changed.emit(credits, materials)


func _process(_delta: float) -> void:
	tick_grant()


## Pays the grant for the sim time passed since the last call (works with
## fast-forward too, since it reads the clock).
func tick_grant() -> void:
	var now := SimClock.time
	var dt := now - _last_time
	_last_time = now
	if dt <= 0.0 or grant_per_minute <= 0.0:
		return
	_grant_clock += dt
	while _grant_clock >= grant_interval:
		_grant_clock -= grant_interval
		var amount := roundi(grant_per_minute * grant_interval / 60.0)
		total_grants += amount
		add_income(amount, "Grant")


## Credits that come back to the player (fees, grant, refunds).
func add_income(amount: int, source: String) -> void:
	if amount <= 0:
		return
	if source == "Fees":
		total_fees += amount
	add(amount)
	income.emit(amount, source)


## A captain paid [param paid] spends their share at the station. Returns the
## credits that came back to the player.
func collect_fees(captain: Captain, paid: int) -> int:
	if captain == null or paid <= 0:
		return 0
	var fee := roundi(float(paid) * captain.station_spend_share())
	captain.credits_spent += fee
	captain.wallet += paid - fee
	add_income(fee, "Fees")
	return fee


## Ore cost in [enum Ore] order.
static func cost(iron: int, titanium: int = 0, crystal: int = 0) -> PackedInt32Array:
	return PackedInt32Array([iron, titanium, crystal])


## Player ore type for an AsteroidBelt.OreType (rock counts as iron).
static func ore_of_belt(belt_ore: int) -> Ore:
	match belt_ore:
		AsteroidBelt.OreType.TITANIUM:
			return Ore.TITANIUM
		AsteroidBelt.OreType.CRYSTAL:
			return Ore.CRYSTAL
	return Ore.IRON


## "100 iron + 30 titanium" ("" for no ore).
static func cost_text(cost_ore: PackedInt32Array) -> String:
	var parts: PackedStringArray = []
	for i in mini(cost_ore.size(), ORE_NAMES.size()):
		if cost_ore[i] > 0:
			parts.append("%s %s" % [UIUtil.amount(cost_ore[i]), ORE_NAMES[i].to_lower()])
	return " + ".join(parts)


func has_ore(cost_ore: PackedInt32Array) -> bool:
	for i in mini(cost_ore.size(), ore.size()):
		if ore[i] < cost_ore[i]:
			return false
	return true


func can_afford(cost_credits: int, cost_ore: PackedInt32Array = PackedInt32Array()) -> bool:
	return credits >= cost_credits and has_ore(cost_ore)


## Why a cost cannot be paid, or "" when it can.
func shortfall_text(cost_credits: int, cost_ore: PackedInt32Array = PackedInt32Array()) -> String:
	var parts: PackedStringArray = []
	if credits < cost_credits:
		parts.append("%d more credits" % (cost_credits - credits))
	for i in mini(cost_ore.size(), ore.size()):
		if ore[i] < cost_ore[i]:
			parts.append("%d more %s" % [cost_ore[i] - ore[i], ORE_NAMES[i].to_lower()])
	return "" if parts.is_empty() else "Needs " + " and ".join(parts)


## Deducts the cost. Returns false (and changes nothing) when unaffordable.
func spend(cost_credits: int, cost_ore: PackedInt32Array = PackedInt32Array()) -> bool:
	if cost_credits < 0 or not can_afford(cost_credits, cost_ore):
		return false
	for i in mini(cost_ore.size(), ore.size()):
		if cost_ore[i] < 0:
			return false
	credits -= cost_credits
	for i in mini(cost_ore.size(), ore.size()):
		ore[i] -= cost_ore[i]
	changed.emit(credits, materials)
	return true


func add(add_credits: int, add_ore: PackedInt32Array = PackedInt32Array()) -> void:
	credits += add_credits
	for i in mini(add_ore.size(), ore.size()):
		ore[i] += add_ore[i]
	changed.emit(credits, materials)


## Ore a cargo shuttle brought to the station (CargoShuttle): into the stock.
func receive_cargo(cargo_ore: PackedInt32Array, source: String) -> void:
	add(0, cargo_ore)
	cargo_received.emit(cargo_ore, source)


func add_ore_of(type: Ore, amount: int) -> void:
	if amount == 0:
		return
	ore[type] = maxi(ore[type] + amount, 0)
	changed.emit(credits, materials)


## Sets the ore stock outright (demos, tests).
func set_ore(iron: int, titanium: int, crystal: int) -> void:
	ore = PackedInt32Array([iron, titanium, crystal])
	changed.emit(credits, materials)


## "2,000" style thousands separators.
static func format_amount(value: int) -> String:
	return UIUtil.amount(value)

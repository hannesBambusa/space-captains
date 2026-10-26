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
##
## Every credit change is written to [member ledger] (the Ledger panel, L):
## [method spend] and [method add] take a category ([Ledger] constants) and
## a short label; [method add_income] uses its source as the category.

## [param materials] is the ore total; read [member ore] for the types.
signal changed(credits: int, materials: int)
## Credits that came in (fees, grant). [param source] is a short reason.
signal income(amount: int, source: String)
## A cargo shuttle landed [param ore] (Ore order) at the station.
signal cargo_received(ore: PackedInt32Array, source: String)

## Asteroid ore first (iron, titanium, crystal), then the planet goods that
## raiders bring back from planet raids (phase C2, see PlanetRaidRules):
## fuel (gas giants), water (ice and ocean worlds), rare metals (lava),
## silicates (desert) and heavy ore (rocky). Saves keep this order; older
## saves with three entries are padded ([method padded]).
enum Ore { IRON, TITANIUM, CRYSTAL, FUEL, WATER, RARE_METALS, SILICATES, HEAVY_ORE }

## Every resource type ([enum Ore]).
const COUNT := 8
## The asteroid ores (iron, titanium, crystal): the first entries.
const BASE_COUNT := 3
const ORE_NAMES: PackedStringArray = ["Iron", "Titanium", "Crystal", "Fuel", "Water", "Rare metals", "Silicates", "Heavy ore"]
## UI colours, close to the ore veins on the asteroids; planet goods by their world.
const ORE_COLORS: Array[Color] = [Color(0.95, 0.6, 0.42), Color(0.8, 0.85, 0.94), Color(0.42, 0.9, 1.0),
		Color(1.0, 0.66, 0.28), Color(0.45, 0.72, 1.0), Color(1.0, 0.42, 0.62), Color(0.93, 0.82, 0.55), Color(0.66, 0.6, 0.55)]
## HUD icon per type (assets/ui/icons).
const ORE_ICONS: Array[StringName] = [&"iron", &"titanium", &"crystal", &"fuel", &"water", &"rare_metals", &"silicates", &"heavy_ore"]

@export var start_credits: int = 3000
## Iron, titanium, crystal at start.
@export var start_ore: PackedInt32Array = PackedInt32Array([300, 80, 0, 0, 0, 0, 0, 0])
## Corporate grant, credits per sim minute.
@export var grant_per_minute: float = 90.0
## The grant is paid in installments this often, sim seconds.
@export var grant_interval: float = 20.0

var credits: int = 0
## Every type in [enum Ore] order.
var ore := zero_ore()
## The asteroid ore together (iron, titanium, crystal).
var materials: int:
	get: return ore[0] + ore[1] + ore[2]
## Totals for tests and the UI.
var total_fees: int = 0
var total_grants: int = 0
## The credit log (see [Ledger]).
var ledger := Ledger.new()

var _grant_clock: float = 0.0
var _last_time: float = 0.0


func _ready() -> void:
	reset()


## Start values (a new game).
func reset() -> void:
	credits = start_credits
	ore = zero_ore()
	for i in ore.size():
		ore[i] = start_ore[i] if i < start_ore.size() else 0
	total_fees = 0
	total_grants = 0
	_grant_clock = 0.0
	_last_time = SimClock.time
	ledger.clear()
	changed.emit(credits, materials)


func save_state() -> Dictionary:
	return {"credits": credits, "ore": ore, "total_fees": total_fees, "total_grants": total_grants, "grant_clock": _grant_clock}


## Call after SimClock is restored (the grant counts from its time).
func load_state(d: Dictionary) -> void:
	credits = int(d.get("credits", start_credits))
	ore = padded(PackedInt32Array(d.get("ore", start_ore)))
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
		add_income(amount, Ledger.GRANT, "Corporate grant")


## Credits that come back to the player (fees, grant, refunds).
## [param source] is the ledger category ([Ledger] constants).
func add_income(amount: int, source: String, label: String = "") -> void:
	if amount <= 0:
		return
	if source == Ledger.FEES:
		total_fees += amount
	add(amount, PackedInt32Array(), source, label)
	income.emit(amount, source)


## Credits paid to a captain out of an escrow reserved earlier: nothing
## leaves the credits now, the ledger gets a note line.
func note_escrow_pay(amount: int, category: String, label: String) -> void:
	ledger.note_held(amount, category, label, credits)


## A captain paid [param paid] spends their share at the station. Returns the
## credits that came back to the player.
func collect_fees(captain: Captain, paid: int) -> int:
	if captain == null or paid <= 0:
		return 0
	var fee := roundi(float(paid) * captain.station_spend_share())
	captain.credits_spent += fee
	captain.wallet += paid - fee
	add_income(fee, Ledger.FEES, "Station fees")
	return fee


## All zeros, one entry per [enum Ore] type.
static func zero_ore() -> PackedInt32Array:
	var a := PackedInt32Array()
	a.resize(COUNT)
	a.fill(0)
	return a


## [param a] grown (zeros) or cut to [constant COUNT] entries (old saves had three).
static func padded(a: PackedInt32Array) -> PackedInt32Array:
	var out := a.duplicate()
	var n := out.size()
	out.resize(COUNT)
	for i in range(n, COUNT):
		out[i] = 0
	return out


## True for the planet goods (fuel, water, rare metals, silicates, heavy ore).
static func is_planet_good(type: int) -> bool:
	return type >= BASE_COUNT and type < COUNT


## [param total] split between [param n] evenly in whole credits; the
## first part takes the remainder.
static func split_evenly(total: int, n: int) -> PackedInt32Array:
	var parts := PackedInt32Array()
	var each := floori(float(total) / float(n))
	for i in n:
		parts.append(each + (total - each * n if i == 0 else 0))
	return parts


## Ore cost in [enum Ore] order.
static func cost(iron: int, titanium: int = 0, crystal: int = 0) -> PackedInt32Array:
	return PackedInt32Array([iron, titanium, crystal])


## Lower-case name of [param type] ([enum Ore]): "rare metals".
static func ore_name(type: int) -> String:
	return ORE_NAMES[type].to_lower()


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
			parts.append("%s %s" % [Fmt.amount(cost_ore[i]), ore_name(i)])
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
			parts.append("%d more %s" % [cost_ore[i] - ore[i], ore_name(i)])
	return "" if parts.is_empty() else "Needs " + " and ".join(parts)


## Deducts the cost. Returns false (and changes nothing) when unaffordable.
## [param category] and [param label] go to the [member ledger].
func spend(cost_credits: int, cost_ore: PackedInt32Array = PackedInt32Array(), category: String = Ledger.OTHER, label: String = "") -> bool:
	if cost_credits < 0 or not can_afford(cost_credits, cost_ore):
		return false
	for i in mini(cost_ore.size(), ore.size()):
		if cost_ore[i] < 0:
			return false
	credits -= cost_credits
	for i in mini(cost_ore.size(), ore.size()):
		ore[i] -= cost_ore[i]
	ledger.record(-cost_credits, category, label, credits)
	changed.emit(credits, materials)
	return true


## [param category] and [param label] go to the [member ledger].
func add(add_credits: int, add_ore: PackedInt32Array = PackedInt32Array(), category: String = Ledger.OTHER, label: String = "") -> void:
	credits += add_credits
	for i in mini(add_ore.size(), ore.size()):
		ore[i] += add_ore[i]
	ledger.record(add_credits, category, label, credits)
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
	ore[Ore.IRON] = iron
	ore[Ore.TITANIUM] = titanium
	ore[Ore.CRYSTAL] = crystal
	changed.emit(credits, materials)


## "2,000" style thousands separators.
static func format_amount(value: int) -> String:
	return Fmt.amount(value)

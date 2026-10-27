class_name StationSupply
extends Node
## What a forward station costs to run (forward plan F4): upkeep, water and
## the hauling fee. Child "StationSupply" of a forward station's
## [SystemWorld] (made by SystemHost.materialise; home has none). Saved with
## its system (GameSnapshot.capture_system, "supply").
##
## Upkeep: free for [member free_upkeep_time] after the founding, then
## [member upkeep_per_minute] credits, paid every
## [member tick_interval] sim seconds like the grant (ledger Upkeep,
## "Upkeep: <station>"). An installment the credits cannot cover is owed;
## while anything is owed nobody can be hired there ([method hire_block]),
## and every tick tries to pay the whole debt.
## Water: [member water_per_minute] units of the global stock
## (Economy.Ore.WATER), taken per tick. When a tick finds too little the
## station runs dry: no hiring there and its captains work at
## [member dry_work_speed] (mining, salvage and repair timers, see
## [method work_mult]) until a later tick gets its water. One feed line when
## it runs dry, one when it is back.
## Hauling fee: [member hauling_fee] of the ore a cargo shuttle lands at the
## station is kept by the haulers ([method take_hauling_fee]). The ledger
## gets a note line (amount 0, category Hauling) with the units in the label
## and their worth at the Factory's price in brackets: the ledger counts
## credits only, so the note keeps its sum check while the fee still shows
## next to the credit lines it is weighed against.

signal changed

const GROUP := "station_supply"
## The Factory keeps this many minutes of the stations' water use.
const WATER_RESERVE_MINUTES := 10.0
## The top bar warns when the water lasts less than this, minutes.
const WATER_WARN_MINUTES := 5.0

@export var upkeep_per_minute: float = 40.0
## No upkeep for this long after the founding, sim seconds.
@export var free_upkeep_time: float = 120.0
@export var water_per_minute: float = 2.0
## Upkeep and water are taken this often, sim seconds.
@export var tick_interval: float = 15.0
## Work speed of the station's captains while it has no water.
@export var dry_work_speed: float = 0.7
## Share of each forward ore delivery the haulers keep.
@export var hauling_fee: float = 0.15

## Credits owed (installments not paid yet).
var owed: int = 0
var upkeep_paid: int = 0
var water_used: int = 0
## No water: no hiring, slower work.
var dry := false
## Ore kept by the haulers so far ([enum Economy.Ore] order) and its worth
## at the Factory price when it was taken, credits.
var hauled_fee := Economy.zero_ore()
var hauled_fee_value: int = 0

var _clock: float = 0.0
var _upkeep_carry: float = 0.0
var _water_carry: float = 0.0
var _last_time: float = 0.0


## The supply of [param ctx]'s system, or null (home, no station).
static func of(ctx: Node) -> StationSupply:
	var w := SystemWorld.of(ctx)
	return w.supply if w else null


## Why nobody can be hired at [param building] for supply reasons, or "".
static func hire_block(building: Node) -> String:
	var s := of(building)
	return s.hire_problem() if s else ""


## Every forward station's supply (all live station systems).
static func all(tree: SceneTree) -> Array[StationSupply]:
	var out: Array[StationSupply] = []
	if tree:
		for n in tree.get_nodes_in_group(GROUP):
			if n is StationSupply and not n.is_queued_for_deletion():
				out.append(n as StationSupply)
	return out


## Water all forward stations use together, units per sim minute.
static func water_use_per_minute(tree: SceneTree) -> float:
	var total := 0.0
	for s in all(tree):
		total += s.water_per_minute
	return total


## Sim minutes the water stock lasts at the stations' use (INF: none used).
static func water_minutes_left(tree: SceneTree) -> float:
	var use := water_use_per_minute(tree)
	return float(Economy.ore[Economy.Ore.WATER]) / use if use > 0.0 else INF


## Water the Factory must leave in stock for the stations:
## [constant WATER_RESERVE_MINUTES] of their use (FactoryMarket).
static func water_reserve(tree: SceneTree) -> int:
	return ceili(water_use_per_minute(tree) * WATER_RESERVE_MINUTES)


## Per station "Eris Station (Ostra): 2/min" lines and the time left, for
## the top bar's water tooltip; "" without forward stations.
static func water_text(tree: SceneTree) -> String:
	var list := all(tree)
	if list.is_empty():
		return ""
	var lines: PackedStringArray = ["Forward stations use %s water per minute:" % Fmt.amount(roundi(water_use_per_minute(tree)))]
	for s in list:
		lines.append("  %s (%s): %s/min, used %s so far%s" % [s.station_name(), s.system_name(), Fmt.amount(roundi(s.water_per_minute)),
				Fmt.amount(s.water_used), ", DRY" if s.dry else ""])
	var left := water_minutes_left(tree)
	lines.append("Your water lasts about %s." % _minutes_text(left))
	lines.append("The Factory keeps at least %d in stock for them (%d min of use)." % [water_reserve(tree), roundi(WATER_RESERVE_MINUTES)])
	return "\n".join(lines)


## True when the stock lasts less than [constant WATER_WARN_MINUTES].
static func water_low(tree: SceneTree) -> bool:
	return water_minutes_left(tree) < WATER_WARN_MINUTES


static func _minutes_text(m: float) -> String:
	if m == INF:
		return "for ever"
	if m < 1.0:
		return "less than a minute"
	return "%d min" % floori(m)


## Work speed of a captain whose home is [param ctx] (1 at home).
static func work_mult(ctx: Node) -> float:
	var s := of(ctx)
	return s.dry_work_speed if s and s.dry else 1.0


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(SimStepper.GROUP)
	_last_time = SimClock.time


func _process(_delta: float) -> void:
	if not SimClock.paused:
		sim_step(0.0)


## Steps on the clock's advance since the last call (from _process or SimStepper).
func sim_step(_dt: float) -> void:
	var dt := SimClock.time - _last_time
	_last_time = SimClock.time
	if dt <= 0.0:
		return
	_clock += dt
	while _clock >= tick_interval:
		_clock -= tick_interval
		_tick()


func station_name() -> String:
	var w := get_parent() as SystemWorld
	return String(w.station_site.get("name", "Forward station")) if w else "Forward station"


## The system's name ("Ostra").
func system_name() -> String:
	var w := get_parent() as SystemWorld
	var def := Sector.system_def(w.system_id) if w else null
	return def.system_name if def else "?"


func system_id() -> StringName:
	var w := get_parent() as SystemWorld
	return w.system_id if w else &""


## Sim time of the founding (0 when unknown).
func founded_at() -> float:
	var w := get_parent() as SystemWorld
	return float(w.station_site.get("founded_at", 0.0)) if w else 0.0


## Upkeep is still free (the first [member free_upkeep_time] after the founding).
func upkeep_free() -> bool:
	return SimClock.time < founded_at() + free_upkeep_time


func hire_problem() -> String:
	if owed > 0:
		return "Upkeep unpaid (%s cr owed): no hiring here until it is paid" % Fmt.amount(owed)
	if dry:
		return "No water: no hiring here until water is back"
	return ""


func _tick() -> void:
	if not upkeep_free():
		_upkeep_carry += upkeep_per_minute * tick_interval / 60.0
	var due := floori(_upkeep_carry)
	_upkeep_carry -= due
	var was_owed := owed > 0
	owed += due
	if owed > 0 and Economy.spend(owed, PackedInt32Array(), Ledger.UPKEEP, "Upkeep: %s" % station_name(), system_id()):
		upkeep_paid += owed
		owed = 0
		if was_owed:
			EventLog.post("Upkeep for %s is paid: hiring there again" % station_name(), EventLog.Kind.INFO, _station_node())
	elif owed > 0 and not was_owed:
		EventLog.post("Upkeep for %s unpaid (%s cr): no hiring there until it is paid" % [station_name(), Fmt.amount(owed)],
				EventLog.Kind.LOSS, _station_node())
	_water_carry += water_per_minute * tick_interval / 60.0
	var need := floori(_water_carry)
	if need > 0:
		if Economy.ore[Economy.Ore.WATER] >= need:
			Economy.add_ore_of(Economy.Ore.WATER, -need)
			water_used += need
			_water_carry -= need
			if dry:
				dry = false
				EventLog.post("%s has water again: hiring and full work speed are back" % station_name(), EventLog.Kind.INFO, _station_node())
		else:
			# No arrears: a dry station waits for its next unit only.
			_water_carry = minf(_water_carry, float(need))
			if not dry:
				dry = true
				EventLog.post("%s ran out of water: no hiring there, its captains work at %d%% speed" % [station_name(), roundi(dry_work_speed * 100.0)],
						EventLog.Kind.LOSS, _station_node())
	changed.emit()


## The fee on [param cargo] landing here: the haulers' share is taken off
## (rounded per type), noted in the ledger; returns what lands.
func take_hauling_fee(cargo: PackedInt32Array) -> PackedInt32Array:
	var net := cargo.duplicate()
	var fee := Economy.zero_ore()
	var value := 0.0
	var any := false
	var f := Factory.find(self)
	for i in mini(cargo.size(), fee.size()):
		var n := roundi(float(cargo[i]) * hauling_fee)
		if n <= 0:
			continue
		any = true
		fee[i] = n
		net[i] -= n
		hauled_fee[i] += n
		value += float(n) * (f.market.willing_price(i) if f and f.market else 0.0)
	if not any:
		return net
	var worth := roundi(value)
	hauled_fee_value += worth
	var w := get_parent() as SystemWorld
	Economy.ledger.note_held(maxi(worth, 1), Ledger.HAULING, "Hauling fee: %s at %s" % [Economy.cost_text(fee), station_name()], Economy.credits,
			w.system_id if w else &"")
	changed.emit()
	return net


## "Upkeep 40 cr/min, water 2/min (ok)" for the station's row.
func status_text() -> String:
	var parts: PackedStringArray = ["upkeep %d cr/min%s" % [roundi(upkeep_per_minute), " (%s owed)" % Fmt.amount(owed) if owed > 0 else (" (free for %s)" % Fmt.clock(founded_at() + free_upkeep_time - SimClock.time) if upkeep_free() else "")],
			"water %s/min (%s)" % [Fmt.amount(roundi(water_per_minute)), "dry" if dry else "ok"]]
	return ", ".join(parts)


## "40 cr/min, free 1:55" / "40 cr/min, 120 owed" for the overview row.
func upkeep_short() -> String:
	if owed > 0:
		return "%d cr/min, %s owed" % [roundi(upkeep_per_minute), Fmt.amount(owed)]
	if upkeep_free():
		return "%d cr/min, free %s" % [roundi(upkeep_per_minute), Fmt.clock(founded_at() + free_upkeep_time - SimClock.time)]
	return "%d cr/min, paid" % roundi(upkeep_per_minute)


## "2/min, 20 min left" / "2/min, DRY" for the overview row.
func water_short() -> String:
	if dry:
		return "%s/min, DRY" % Fmt.amount(roundi(water_per_minute))
	var left := water_minutes_left(get_tree()) if is_inside_tree() else INF
	return "%s/min, %s left" % [Fmt.amount(roundi(water_per_minute)), _minutes_text(left)] if left != INF else "%s/min" % Fmt.amount(roundi(water_per_minute))


func tooltip_text() -> String:
	var lines: PackedStringArray = [
		"Upkeep: %d cr per minute from your credits (free the first %d min), paid so far %s cr%s." % [roundi(upkeep_per_minute),
				roundi(free_upkeep_time / 60.0), Fmt.amount(upkeep_paid), ", %s cr owed: no hiring here until it is paid" % Fmt.amount(owed) if owed > 0 else ""],
		"Water: %s per minute from your stock (%s left), used so far %s.%s" % [Fmt.amount(roundi(water_per_minute)), Fmt.amount(Economy.ore[Economy.Ore.WATER]),
				Fmt.amount(water_used), " Out of water: no hiring here, captains work at %d%% speed." % roundi(dry_work_speed * 100.0) if dry else ""],
		"Hauling fee: %d%% of the ore landed here, so far %s (worth about %s cr)." % [roundi(hauling_fee * 100.0),
				Economy.cost_text(hauled_fee) if not Economy.cost_text(hauled_fee).is_empty() else "none", Fmt.amount(hauled_fee_value)],
	]
	return "\n".join(lines)


func _station_node() -> Node3D:
	var w := get_parent() as SystemWorld
	return w.sys.home_station if w and w.sys else null


# --- Save ---------------------------------------------------------------------

func save_state() -> Dictionary:
	return {"owed": owed, "upkeep_paid": upkeep_paid, "water_used": water_used, "dry": dry, "hauled_fee": hauled_fee,
			"hauled_fee_value": hauled_fee_value, "clock": _clock, "upkeep_carry": _upkeep_carry, "water_carry": _water_carry}


func load_state(d: Dictionary) -> void:
	_last_time = SimClock.time
	owed = int(d.get("owed", 0))
	upkeep_paid = int(d.get("upkeep_paid", 0))
	water_used = int(d.get("water_used", 0))
	dry = bool(d.get("dry", false))
	hauled_fee = Economy.padded(PackedInt32Array(d.get("hauled_fee", Economy.zero_ore())))
	hauled_fee_value = int(d.get("hauled_fee_value", 0))
	_clock = float(d.get("clock", 0.0))
	_upkeep_carry = float(d.get("upkeep_carry", 0.0))
	_water_carry = float(d.get("water_carry", 0.0))
	changed.emit()

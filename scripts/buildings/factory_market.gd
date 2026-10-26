class_name FactoryMarket
extends Node
## The Factory's ore market (child of [Factory]). It buys the player's ore,
## one stock per type (Economy.Ore order: iron, titanium, crystal, then the
## planet goods fuel, water, rare metals, silicates, heavy ore), and the
## Factory's production draws on these stocks.
##
## Demand per type (0..1): 1 / (1 + (stock / target)^[member demand_curve]),
## plus a bump while production needs that ore (open backorders for parts
## made from it). Willingness to pay = floor + (ceiling - floor) * demand, so
## the price is high while the stock is low and sinks as it fills.
## The stocks drain by manufacturing and a steady corporate export draw
## (base + share of the stock per minute), so the price always recovers.
##
## Auto-sell (on from the start): the player sets an asking price per type;
## the Factory buys over time, [member max_buy_per_min] while the ask is at or
## below [member eager_ratio] of its willingness, slower as the ask climbs
## above it, nothing past [member refuse_ratio]. It never takes the player
## below the reserve for that type. Every sale pays the ask per unit, as
## income ("Factory" in the top bar); the event feed gets one summary line
## per [member report_interval]. [method sell_now] sells at once at the
## Factory's current willingness instead.
## Follow market (per type, on from the start): the ask tracks the
## Factory's willingness times [member follow_margin] every step, so the
## ore sells steadily near the top price. Setting the ask by hand
## ([method set_ask], [method step_ask]) turns it off for that type;
## [method match_market] turns it back on.

signal changed
## [param ore] Economy.Ore, [param units] sold, [param credits] paid.
signal sold(ore: int, units: int, credits: int)

const TYPES := Economy.COUNT
const LEVEL_NAMES: PackedStringArray = ["Low", "Normal", "High"]
const MAX_HISTORY := 12

@export var target_stock: PackedFloat32Array = PackedFloat32Array([250.0, 150.0, 80.0, 60.0, 120.0, 40.0, 80.0, 100.0])
@export var start_stock: PackedFloat32Array = PackedFloat32Array([200.0, 80.0, 10.0, 0.0, 0.0, 0.0, 0.0, 0.0])
@export var price_floor: PackedFloat32Array = PackedFloat32Array([5.0, 5.0, 6.0, 6.0, 3.0, 12.0, 4.0, 3.0])
@export var price_ceiling: PackedFloat32Array = PackedFloat32Array([12.0, 20.0, 30.0, 22.0, 10.0, 38.0, 14.0, 12.0])
@export var demand_curve: float = 1.5
## Demand added per open backorder that needs this ore, and its cap.
@export var backorder_demand: float = 0.06
@export var backorder_demand_max: float = 0.3
## Corporate export draw per sim minute: base units plus a share of the stock.
@export var export_base_per_min: PackedFloat32Array = PackedFloat32Array([3.0, 5.0, 3.0, 3.0, 5.0, 1.5, 3.0, 4.0])
@export var export_share_per_min: PackedFloat32Array = PackedFloat32Array([0.04, 0.06, 0.05, 0.05, 0.06, 0.04, 0.05, 0.05])
## Fastest buying, units per sim minute (ask at or below eager_ratio x willingness).
@export var max_buy_per_min: PackedFloat32Array = PackedFloat32Array([40.0, 30.0, 20.0, 24.0, 36.0, 12.0, 28.0, 32.0])
@export var eager_ratio: float = 0.8
@export var refuse_ratio: float = 1.35
## Asking price defaults and the stepper.
@export var default_ask: PackedFloat32Array = PackedFloat32Array([6.0, 11.0, 16.0, 13.0, 6.0, 22.0, 8.0, 7.0])
@export var ask_step: PackedFloat32Array = PackedFloat32Array([0.5, 0.5, 1.0, 0.5, 0.5, 1.0, 0.5, 0.5])
@export var ask_max: PackedFloat32Array = PackedFloat32Array([20.0, 40.0, 80.0, 50.0, 25.0, 90.0, 35.0, 30.0])
## Follow market: ask = willingness times this.
@export var follow_margin: float = 0.95
## Default "keep at least" per type: enough for the next structure, and
## a small stock of each planet good to refine and build with.
@export var default_reserve: PackedInt32Array = PackedInt32Array([200, 50, 0, 20, 20, 20, 20, 20])
@export var reserve_step: PackedInt32Array = PackedInt32Array([50, 10, 10, 10, 10, 5, 10, 10])
## Auto-sell settles this often, sim seconds.
@export var sell_interval: float = 3.0
## Event feed summary interval, sim seconds.
@export var report_interval: float = 60.0
## Price samples for the trend, every [member sample_interval] s.
@export var sample_interval: float = 10.0
@export var trend_window: int = 6

var stock := _zeros_f()
var ask := _zeros_f()
var reserve := Economy.zero_ore()
## Salvage Yard ore that landed at the station: auto-sell skips it on top of
## the reserve ([method hold]). Shrinks to the ore the player still has.
var held := Economy.zero_ore()
var auto_sell: bool = true
## Per type: the ask follows the Factory's price.
var follow: Array[bool] = [true, true, true, true, true, true, true, true]
## Open backorders per ore type (set by the Factory).
var backorder_need := Economy.zero_ore()
var total_units := Economy.zero_ore()
var total_credits: int = 0
## Newest last: {time, ore, units, credits}, one per summary.
var history: Array[Dictionary] = []

var _acc := _zeros_f()
var _credit_carry := 0.0
var _sell_timer := 0.0
var _report_timer := 0.0
var _sample_timer := 0.0
## Per type: PackedFloat32Array of willingness samples, newest last.
var _samples: Array[PackedFloat32Array] = []
var _pending_units := Economy.zero_ore()
var _pending_credits := Economy.zero_ore()


func _init() -> void:
	for i in TYPES:
		stock[i] = start_stock[i]
		ask[i] = default_ask[i]
		reserve[i] = default_reserve[i]
		_follow_price(i)
		_samples.append(PackedFloat32Array())


# --- Prices -----------------------------------------------------------------------

## How much the Factory wants ore of [param ore] right now, 0..1.
func demand(ore: int) -> float:
	var base := 1.0 / (1.0 + pow(maxf(stock[ore], 0.0) / maxf(target_stock[ore], 1.0), demand_curve))
	return clampf(base + minf(float(backorder_need[ore]) * backorder_demand, backorder_demand_max), 0.0, 1.0)


## 0 = Low, 1 = Normal, 2 = High.
func demand_level(ore: int) -> int:
	var d := demand(ore)
	return 2 if d >= 0.66 else (0 if d < 0.38 else 1)


func demand_name(ore: int) -> String:
	return LEVEL_NAMES[demand_level(ore)]


## Credits per unit the Factory is willing to pay now.
func willing_price(ore: int) -> float:
	return lerpf(price_floor[ore], price_ceiling[ore], demand(ore))


## Willingness now minus about [member trend_window] samples ago, credits.
func trend(ore: int) -> float:
	var s := _samples[ore]
	if s.is_empty():
		return 0.0
	return willing_price(ore) - s[0]


## "rising" / "falling" / "steady".
func trend_text(ore: int) -> String:
	var t := trend(ore)
	var eps := ask_step[ore] * 0.3
	return "rising" if t > eps else ("falling" if t < -eps else "steady")


## Units per sim minute the Factory buys at [param price].
func buy_rate_at(ore: int, price: float) -> float:
	var r := price / maxf(willing_price(ore), 0.01)
	if r <= eager_ratio:
		return max_buy_per_min[ore]
	if r >= refuse_ratio:
		return 0.0
	var f := 1.0 - (r - eager_ratio) / (refuse_ratio - eager_ratio)
	return max_buy_per_min[ore] * f * f


## Expected sales, units per minute, at the current ask (0 when auto-sell is
## off or the player has nothing above the reserve).
func expected_rate(ore: int) -> float:
	if not auto_sell or surplus(ore) <= 0:
		return 0.0
	return buy_rate_at(ore, ask[ore])


## Player ore above the reserve and the held yard ore.
func surplus(ore: int) -> int:
	return maxi(Economy.ore[ore] - reserve[ore] - mini(held[ore], Economy.ore[ore]), 0)


## Ore bought at the Salvage Yard landed: auto-sell leaves it alone.
func hold(cargo: PackedInt32Array) -> void:
	for i in mini(cargo.size(), TYPES):
		held[i] += cargo[i]
	changed.emit()


## Units of [param ore] currently held back (bought ore the player still has).
func held_units(ore: int) -> int:
	return mini(held[ore], Economy.ore[ore])


## Sets the ask by hand: follow market goes off for this type.
func set_ask(ore: int, price: float) -> void:
	follow[ore] = false
	ask[ore] = clampf(snappedf(price, ask_step[ore]), ask_step[ore], ask_max[ore])
	changed.emit()


func step_ask(ore: int, steps: int) -> void:
	set_ask(ore, ask[ore] + ask_step[ore] * steps)


## Follow market back on: the ask tracks the Factory's price.
func match_market(ore: int) -> void:
	set_follow(ore, true)


func set_follow(ore: int, on: bool) -> void:
	follow[ore] = on
	if on:
		_follow_price(ore)
	changed.emit()


func is_following(ore: int) -> bool:
	return follow[ore]


## Ask = willingness times [member follow_margin] (not snapped, so it tracks).
func _follow_price(ore: int) -> void:
	ask[ore] = clampf(willing_price(ore) * follow_margin, ask_step[ore], ask_max[ore])


func set_reserve(ore: int, amount: int) -> void:
	reserve[ore] = maxi(amount, 0)
	changed.emit()


func set_auto_sell(on: bool) -> void:
	auto_sell = on
	changed.emit()


# --- Stock ------------------------------------------------------------------------

func has_stock(cost: PackedInt32Array) -> bool:
	for i in mini(cost.size(), TYPES):
		if stock[i] < float(cost[i]):
			return false
	return true


## Production takes [param cost] from the stocks. False (nothing taken) when short.
func consume(cost: PackedInt32Array) -> bool:
	if not has_stock(cost):
		return false
	for i in mini(cost.size(), TYPES):
		stock[i] -= float(cost[i])
	changed.emit()
	return true


## Sells [param units] of [param ore] at once at the Factory's willingness,
## unit by unit (the price sinks as its stock fills). Returns credits paid.
func sell_now(ore: int, units: int) -> int:
	units = mini(units, Economy.ore[ore])
	if units <= 0:
		return 0
	var credits := 0.0
	for i in units:
		credits += willing_price(ore)
		stock[ore] += 1.0
	var paid := _pay(ore, units, credits)
	_add_history(ore, units, paid)
	EventLog.post("Sold %d %s to the Factory (+%s cr)" % [units, Economy.ore_name(ore), Fmt.amount(paid)],
			EventLog.Kind.REWARD, null, Vector3.INF, "factory_sell_now:%d" % total_units[ore])
	return paid


# --- Refining -------------------------------------------------------------------

## Planet goods the Factory refines into asteroid ore for you (instant, no
## fee): Economy.Ore -> {batch: units taken, out: ore made per batch}.
## Heavy ore gives iron and titanium, silicates crystal.
const REFINE := {
	Economy.Ore.HEAVY_ORE: {"batch": 10, "out": [12, 4, 0]},
	Economy.Ore.SILICATES: {"batch": 10, "out": [0, 0, 4]},
}


func can_refine(ore: int) -> bool:
	return REFINE.has(ore)


## Batches of [param ore] the player can refine now.
func refine_batches(ore: int) -> int:
	if not REFINE.has(ore):
		return 0
	return floori(float(Economy.ore[ore]) / float(int(REFINE[ore]["batch"])))


## "10 heavy ore into 12 iron and 4 titanium".
func refine_text(ore: int) -> String:
	if not REFINE.has(ore):
		return ""
	var r: Dictionary = REFINE[ore]
	return "%d %s into %s" % [int(r["batch"]), Economy.ore_name(ore), Economy.cost_text(PackedInt32Array(r["out"])).replace(" + ", " and ")]


## Refines up to [param batches] batches of [param ore] from the player's
## stock into asteroid ore. Returns the batches done.
func refine(ore: int, batches: int = 1) -> int:
	var n := mini(batches, refine_batches(ore))
	if n <= 0:
		return 0
	var r: Dictionary = REFINE[ore]
	var take := Economy.zero_ore()
	take[ore] = int(r["batch"]) * n
	if not Economy.spend(0, take):
		return 0
	var out := Economy.zero_ore()
	var per: Array = r["out"]
	for i in per.size():
		out[i] = int(per[i]) * n
	Economy.add(0, out)
	EventLog.post("Factory refined %d %s into %s" % [take[ore], Economy.ore_name(ore), Economy.cost_text(out).replace(" + ", " and ")],
			EventLog.Kind.INFO, null, Vector3.INF, "factory_refine")
	changed.emit()
	return n


# --- Simulation -------------------------------------------------------------------

func sim_step(dt: float) -> void:
	if dt <= 0.0:
		return
	for i in TYPES:
		held[i] = mini(held[i], Economy.ore[i])
		var draw := (export_base_per_min[i] + export_share_per_min[i] * stock[i]) * dt / 60.0
		stock[i] = maxf(stock[i] - draw, 0.0)
		if follow[i]:
			_follow_price(i)
		if auto_sell and surplus(i) > 0:
			_acc[i] += buy_rate_at(i, ask[i]) * dt / 60.0
		else:
			# Nothing to sell: no backlog builds up (a part unit carries over).
			_acc[i] = minf(_acc[i], 0.99)
	_sell_timer -= dt
	if _sell_timer <= 0.0:
		_sell_timer = sell_interval
		_settle()
	_sample_timer -= dt
	if _sample_timer <= 0.0:
		_sample_timer = sample_interval
		for i in TYPES:
			_samples[i].append(willing_price(i))
			if _samples[i].size() > trend_window:
				_samples[i].remove_at(0)
	_report_timer -= dt
	if _report_timer <= 0.0:
		_report_timer = report_interval
		_flush_report()


## Auto-sell: the units the Factory bought since the last settle, at the ask.
func _settle() -> void:
	var any := false
	for i in TYPES:
		var n := mini(floori(_acc[i]), surplus(i))
		if n <= 0:
			continue
		_acc[i] -= float(n)
		stock[i] += float(n)
		var paid := _pay(i, n, ask[i] * float(n))
		_pending_units[i] += n
		_pending_credits[i] += paid
		any = true
	if any:
		changed.emit()


func _pay(ore: int, units: int, credits: float) -> int:
	var total := credits + _credit_carry
	var paid := floori(total)
	_credit_carry = total - float(paid)
	var cost := Economy.zero_ore()
	cost[ore] = units
	Economy.spend(0, cost)
	Economy.add_income(paid, "Factory")
	total_units[ore] += units
	total_credits += paid
	sold.emit(ore, units, paid)
	changed.emit()
	return paid


## One event feed line for the auto-sales since the last report.
func _flush_report() -> void:
	var parts: PackedStringArray = []
	var credits := 0
	for i in TYPES:
		if _pending_units[i] <= 0:
			continue
		parts.append("%d %s" % [_pending_units[i], Economy.ore_name(i)])
		credits += _pending_credits[i]
		_add_history(i, _pending_units[i], _pending_credits[i])
		_pending_units[i] = 0
		_pending_credits[i] = 0
	if parts.is_empty():
		return
	EventLog.post("Factory bought %s (+%s cr)" % [", ".join(parts), Fmt.amount(credits)], EventLog.Kind.REWARD, null, Vector3.INF, "factory_sales")


func _add_history(ore: int, units: int, credits: int) -> void:
	history.append({"time": SimClock.time, "ore": ore, "units": units, "credits": credits})
	if history.size() > MAX_HISTORY:
		history.remove_at(0)


# --- Save ---------------------------------------------------------------------

const SAVE_FIELDS: PackedStringArray = [
	"stock", "ask", "reserve", "held", "auto_sell", "follow", "total_units", "total_credits", "history",
	"_acc", "_credit_carry", "_sell_timer", "_report_timer", "_sample_timer", "_samples", "_pending_units", "_pending_credits",
]


func save_state() -> Dictionary:
	return SaveUtil.props(self, SAVE_FIELDS)


func load_state(d: Dictionary) -> void:
	SaveUtil.apply_props(self, d)
	_pad_types()
	changed.emit()


## Saves from before the planet goods hold three types: the new ones start
## at their defaults.
func _pad_types() -> void:
	var n := stock.size()
	if n >= TYPES:
		return
	stock.resize(TYPES)
	ask.resize(TYPES)
	_acc.resize(TYPES)
	for i in range(n, TYPES):
		stock[i] = start_stock[i]
		ask[i] = default_ask[i]
		_acc[i] = 0.0
	reserve = _grow_i(reserve, default_reserve)
	held = Economy.padded(held)
	total_units = Economy.padded(total_units)
	_pending_units = Economy.padded(_pending_units)
	_pending_credits = Economy.padded(_pending_credits)
	while follow.size() < TYPES:
		follow.append(true)
	while _samples.size() < TYPES:
		_samples.append(PackedFloat32Array())
	if backorder_need.size() < TYPES:
		backorder_need = Economy.padded(backorder_need)


static func _grow_i(a: PackedInt32Array, defaults: PackedInt32Array) -> PackedInt32Array:
	var out := a.duplicate()
	var n := out.size()
	out.resize(TYPES)
	for i in range(n, TYPES):
		out[i] = defaults[i]
	return out


static func _zeros_f() -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(TYPES)
	a.fill(0.0)
	return a

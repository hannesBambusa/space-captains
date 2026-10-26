class_name SalvageYard
extends Node
## The Salvage Yard's business (service node of the Salvage Yard building).
##
## Salvagers work scrap fields on their own (free salvage, see
## SalvageContract.free_for) and deliver the scrap here. The yard pays the
## captain [constant SalvageContract.FAIR_REWARD] per full load from its own
## [member funds], not from the player's credits (the station still takes its
## fee share of the pay, Economy.collect_fees). When the yard is short it
## pays what it has and owes the rest ([member owed]); debts are paid first,
## oldest first, as soon as sales bring money in. Salvagers see a yard in
## debt and value its pay at [constant DEBT_PAY_TRUST].
##
## The yard keeps a scrap stock and reprocesses [member reprocess_rate] scrap
## per sim second into ore: [constant MIX] (iron, titanium, crystal shares),
## den ruins richer ([constant DEN_MIX]). The stock's mix is the weighted
## average of what was delivered.
##
## It sells that ore to the player at [member discount] times the Factory's
## current bid (FactoryMarket.willing_price; [constant FALLBACK_BID] without a
## Factory). Bought ore is paid at once and waits at the yard's
## [CargoDepot]; a cargo shuttle flies it to the station, where it goes into
## the player's stock (Economy) and the Factory market's auto-sell can sell
## it on at the full price: the gap is the player's margin. Auto-buy (on
## from the start) buys every
## [member auto_buy_interval] s while the player keeps at least
## [member credit_floor] credits.

signal changed

const GROUP := "salvage_yards"
const TYPES := 3
## Ore shares per scrap: iron, titanium, crystal.
const MIX := [0.75, 0.2, 0.05]
const DEN_MIX := [0.6, 0.28, 0.12]
## Factory bid per type when there is no Factory (its default asks).
const FALLBACK_BID := [6.0, 11.0, 16.0]
## Salvagers count a yard's pay at this share while it owes money.
const DEBT_PAY_TRUST := 0.5
const MAX_DELIVERIES := 10

## Credits the yard starts with.
@export var start_funds: int = 300
## Scrap reprocessed per sim second.
@export var reprocess_rate: float = 1.0
## Yard ask = Factory bid times this.
@export var discount: float = 0.7
@export var auto_buy: bool = true
## Auto-buy never takes the player below this many credits.
@export var credit_floor: int = 200
@export var auto_buy_interval: float = 2.0

var building: Building
var funds: int = 0
## Scrap waiting to be reprocessed.
var scrap: float = 0.0
## Ore shares of the scrap in stock (weighted by delivery).
var mix := PackedFloat32Array(MIX)
## Reprocessed ore for sale: iron, titanium, crystal.
var stock := PackedInt32Array([0, 0, 0])
## Oldest first: {captain: Captain, amount: int}.
var owed: Array[Dictionary] = []
## Newest last: {time, captain, scrap, paid, owed, rare}.
var deliveries: Array[Dictionary] = []
var total_scrap: int = 0
var delivery_count: int = 0
var total_paid: int = 0
var total_sold := PackedInt32Array([0, 0, 0])
var total_sales: int = 0

var _ore_acc := PackedFloat32Array([0.0, 0.0, 0.0])
var _buy_timer := 0.0


static func find(ctx: Node) -> SalvageYard:
	return Building.first_active_service(ctx, GROUP) as SalvageYard


## The yard [param ship] belongs to, or null.
static func of(ship: Ship) -> SalvageYard:
	if ship == null or not is_instance_valid(ship.home):
		return null
	var b := ship.home as Building
	return b.get_service() as SalvageYard if b else null


func setup(owner_building: Building) -> void:
	building = owner_building


func _ready() -> void:
	funds = start_funds
	add_to_group(GROUP)
	add_to_group(SimStepper.GROUP)


func _process(delta: float) -> void:
	if not SimClock.paused:
		sim_step(delta * SimClock.speed)


func sim_step(dt: float) -> void:
	if dt <= 0.0 or building == null or not building.is_active():
		return
	if scrap > 0.0:
		var n := minf(scrap, reprocess_rate * dt)
		scrap -= n
		var any := false
		for i in TYPES:
			_ore_acc[i] += n * mix[i]
			var whole := floori(_ore_acc[i])
			if whole > 0:
				_ore_acc[i] -= float(whole)
				stock[i] += whole
				any = true
		if scrap <= 0.001:
			scrap = 0.0
		if any:
			changed.emit()
	if auto_buy:
		_buy_timer -= dt
		if _buy_timer <= 0.0:
			_buy_timer = auto_buy_interval
			_auto_buy()


# --- Deliveries -------------------------------------------------------------------

## Pay per load as salvagers see it now (less while the yard owes money).
func expected_load_pay() -> float:
	return float(SalvageContract.FAIR_REWARD) * (DEBT_PAY_TRUST if owed_total() > 0 else 1.0)


func owed_total() -> int:
	var t := 0
	for d in owed:
		t += int(d["amount"])
	return t


## A salvager delivered [param amount] scrap ([param fraction] of a full
## load). Pays the captain from the yard funds, owes what it cannot pay.
## Returns the credits paid now.
func accept_load(ship: Ship, amount: int, fraction: float, den_ruins: bool, rare: String = "") -> int:
	var cap := ship.captain if ship else null
	if amount > 0:
		var share := DEN_MIX if den_ruins else MIX
		var total := scrap + float(amount)
		for i in TYPES:
			mix[i] = (mix[i] * scrap + float(share[i]) * float(amount)) / maxf(total, 1.0)
		scrap = total
		total_scrap += amount
	var due := roundi(float(SalvageContract.FAIR_REWARD) * clampf(fraction, 0.0, 2.0))
	var paid := mini(due, maxi(funds, 0))
	if paid > 0:
		funds -= paid
		total_paid += paid
		if cap:
			Economy.collect_fees(cap, paid)
	var short := due - paid
	if short > 0 and cap:
		owed.append({"captain": cap, "amount": short})
	delivery_count += 1
	# Salvagers deliver without a mining contract: the yard plays its own
	# unload (arm, conveyor, silo) for the scrap.
	var fx := building.get_unload_fx() if building and is_instance_valid(building) else null
	if fx and amount > 0:
		fx.play_unload(Economy.Ore.IRON, amount, CaptainBrain.UNLOAD_TIME)
	deliveries.append({"time": SimClock.time, "captain": cap.captain_name if cap else "?", "scrap": amount, "paid": paid, "owed": short, "rare": rare})
	if deliveries.size() > MAX_DELIVERIES:
		deliveries.remove_at(0)
	changed.emit()
	return paid


## Pays debts, oldest first, from the funds.
func _pay_debts() -> void:
	while not owed.is_empty() and funds > 0:
		var d := owed[0]
		var cap := d["captain"] as Captain
		var pay := mini(int(d["amount"]), funds)
		funds -= pay
		total_paid += pay
		d["amount"] = int(d["amount"]) - pay
		if cap:
			cap.credits_earned += pay
			Economy.collect_fees(cap, pay)
		if int(d["amount"]) <= 0:
			owed.remove_at(0)


# --- Selling to the player ----------------------------------------------------------

## What the Factory pays per unit of [param ore] now.
func factory_bid(ore: int) -> float:
	var f := Factory.find(self) if is_inside_tree() else null
	return f.market.willing_price(ore) if f else float(FALLBACK_BID[ore])


## The yard's ask per unit, below the Factory's bid.
func ask(ore: int) -> float:
	return factory_bid(ore) * discount


## Credits for [param units] of [param ore] at the ask (rounded up).
func price_of(ore: int, units: int) -> int:
	return ceili(ask(ore) * float(units) - 0.001)


## Most units of [param ore] the player can buy keeping [param floor_credits].
func affordable(ore: int, floor_credits: int = 0) -> int:
	var budget := Economy.credits - floor_credits
	if budget <= 0:
		return 0
	return mini(stock[ore], floori(float(budget) / maxf(ask(ore), 0.01)))


## The player buys up to [param units] of [param ore]. Returns units bought.
func buy(ore: int, units: int, floor_credits: int = 0) -> int:
	units = mini(units, affordable(ore, floor_credits))
	if units <= 0:
		return 0
	var cost := price_of(ore, units)
	if not Economy.spend(cost):
		return 0
	stock[ore] -= units
	# Paid now; the ore waits at the yard's depot for a cargo shuttle.
	var depot := CargoDepot.of(building)
	if depot:
		depot.add_stock(ore, units)
	else:
		var got := PackedInt32Array([0, 0, 0])
		got[ore] = units
		Economy.add(0, got)
	funds += cost
	total_sold[ore] += units
	total_sales += cost
	_pay_debts()
	changed.emit()
	return units


func set_auto_buy(on: bool) -> void:
	auto_buy = on
	_buy_timer = 0.0
	changed.emit()


func _auto_buy() -> void:
	var parts: PackedStringArray = []
	var spent := 0
	for i in TYPES:
		if stock[i] <= 0:
			continue
		var before := Economy.credits
		var n := buy(i, stock[i], credit_floor)
		if n > 0:
			parts.append("%d %s" % [n, Economy.ore_name(i)])
			spent += before - Economy.credits
	if not parts.is_empty():
		EventLog.post("Bought %s from the Salvage Yard (-%s cr)" % [", ".join(parts), Fmt.amount(spent)],
				EventLog.Kind.INFO, building, Vector3.INF, "salvage_yard_buy")


## "Reprocessing 34 scrap" / "Idle".
func status_text() -> String:
	return "Reprocessing %d scrap" % ceili(scrap) if scrap > 0.0 else "Idle, no scrap"


# --- Save ---------------------------------------------------------------------

const SAVE_FIELDS: PackedStringArray = [
	"funds", "scrap", "mix", "stock", "deliveries", "total_scrap", "delivery_count", "total_paid", "total_sold",
	"total_sales", "auto_buy", "_ore_acc", "_buy_timer",
]


## Funds, scrap, stock and the debts (captains by save id).
func save_state() -> Dictionary:
	var d := SaveUtil.props(self, SAVE_FIELDS)
	var debts := []
	for o in owed:
		debts.append({"captain": SaveIds.of(o["captain"]), "amount": o["amount"]})
	d["owed"] = debts
	return d


func load_state(d: Dictionary, refs: SaveRefs) -> void:
	var fields := d.duplicate()
	fields.erase("owed")
	SaveUtil.apply_props(self, fields)
	owed.clear()
	for o: Dictionary in d.get("owed", []):
		owed.append({"captain": refs.captain(int(o["captain"])), "amount": int(o["amount"])})
	changed.emit()

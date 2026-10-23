extends Node
## Autoload "Economy". The player's two resources: credits (pay contractors)
## and materials (ore, for building). Everything that costs something goes
## through [method can_afford] and [method spend].
##
## Income (Majesty style, stage 2): captains spend a share of every payment
## at the station (docking and service fees, see Captain.station_spend_share),
## which comes back through [method add_income]; a small corporate grant is
## paid every [member grant_interval] sim seconds. Each income shows as a
## green delta in the top bar ([signal income]).

signal changed(credits: int, materials: int)
## Credits that came in (fees, grant). [param source] is a short reason.
signal income(amount: int, source: String)

@export var start_credits: int = 2000
@export var start_materials: int = 300
## Corporate grant, credits per sim minute.
@export var grant_per_minute: float = 60.0
## The grant is paid in installments this often, sim seconds.
@export var grant_interval: float = 20.0

var credits: int = 0
var materials: int = 0
## Totals for tests and the UI.
var total_fees: int = 0
var total_grants: int = 0

var _grant_clock: float = 0.0
var _last_time: float = 0.0


func _ready() -> void:
	credits = start_credits
	materials = start_materials
	_last_time = SimClock.time


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


func can_afford(cost_credits: int, cost_materials: int = 0) -> bool:
	return credits >= cost_credits and materials >= cost_materials


## Why a cost cannot be paid, or "" when it can.
func shortfall_text(cost_credits: int, cost_materials: int = 0) -> String:
	var parts: PackedStringArray = []
	if credits < cost_credits:
		parts.append("%d more credits" % (cost_credits - credits))
	if materials < cost_materials:
		parts.append("%d more materials" % (cost_materials - materials))
	return "" if parts.is_empty() else "Needs " + " and ".join(parts)


## Deducts the cost. Returns false (and changes nothing) when unaffordable.
func spend(cost_credits: int, cost_materials: int = 0) -> bool:
	if cost_credits < 0 or cost_materials < 0 or not can_afford(cost_credits, cost_materials):
		return false
	credits -= cost_credits
	materials -= cost_materials
	changed.emit(credits, materials)
	return true


func add(add_credits: int, add_materials: int = 0) -> void:
	credits += add_credits
	materials += add_materials
	changed.emit(credits, materials)


## "2,000" style thousands separators.
static func format_amount(value: int) -> String:
	return UIUtil.amount(value)

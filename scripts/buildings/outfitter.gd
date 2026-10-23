class_name Outfitter
extends Node
## Service node of the Outfitter building (see BuildingDef.service_script).
## Docked captains walk in on their own (Ship._visit_services) and buy one
## module per visit from their wallet: a Mk I..III module for a free unlocked
## slot, or an upgrade of a bought one. Stock comes from the Factory
## warehouse (finite, see [Factory]); the best tier allowed is the lower of
## the captain's rank tier and what the Factory is tooled for (or a rare part
## lets it make). Without an Outfitter captains cannot buy modules at all.
##
## What they buy follows personality (slot weights in [constant SLOT_WEIGHTS]):
##   Bold      guns and engines
##   Cautious  shields, armour, escape pods
##   Greedy    cargo holds and tools (drills), prospecting scanners
##   Lazy      engines, always the cheapest
## When the part they want is out of stock:
##   Bold      takes the best part in stock, else places a backorder
##   Cautious  places a backorder and waits for it
##   Greedy    places a backorder and waits for it
##   Lazy      takes whatever is in stock, else tries again next visit
## A captain with an open backorder buys nothing else until it arrives (or
## lapses). Each captain keeps a reserve in the wallet ([constant RESERVE]).
## The player gets [member sale_share] of every price as income.

signal sold(sale: Dictionary)
signal changed

const GROUP := "outfitters"
## Slot weights per personality, in ShipModule.Slot order
## (tool, cargo, defense, engine, sensor).
const SLOT_WEIGHTS := [
	[1.0, 0.3, 0.3, 0.9, 0.4],
	[0.3, 0.3, 1.0, 0.5, 0.55],
	[0.85, 1.0, 0.25, 0.3, 0.7],
	[0.35, 0.3, 0.35, 1.0, 0.3],
]
## Credits each personality keeps back (Bold, Cautious, Greedy, Lazy).
const RESERVE: PackedInt32Array = [40, 150, 220, 60]
const MAX_SALES_LISTED := 12

@export var sale_share: float = 0.35

var building: Building
## Newest last: {time, captain, module, tier, price, income}.
var sales: Array[Dictionary] = []
var total_sales: int = 0
var total_income: int = 0
## Visits that found the wanted part out of stock.
var stockouts: int = 0


static func find(tree: SceneTree) -> Outfitter:
	for n in tree.get_nodes_in_group(GROUP):
		var o := n as Outfitter
		if o and is_instance_valid(o.building) and o.building.is_active():
			return o
	return null


func setup(owner_building: Building) -> void:
	building = owner_building


func _ready() -> void:
	add_to_group(GROUP)


## The Factory this shop sells from, or null.
func factory() -> Factory:
	return Factory.find(get_tree()) if is_inside_tree() else null


# --- Stock ----------------------------------------------------------------------

## Highest tier the Factory can supply now (0 without a Factory).
func supplied_tier() -> int:
	var f := factory()
	return f.tooling_tier if f else 0


func is_stocked(m: ShipModule) -> bool:
	var f := factory()
	return f != null and f.can_make(m)


## Highest tier [param captain] may buy here (rank and Factory tooling).
func max_tier_for(captain: Captain) -> int:
	return mini(Reputation.max_tier_for(captain.rank), supplied_tier())


func price_of(m: ShipModule) -> int:
	var f := factory()
	return f.price_of(m) if f else m.cost


## Why [param m] is not for [param captain] now, or "". Stock aside.
func block_reason(captain: Captain, m: ShipModule) -> String:
	if not m.fits_role(captain.role):
		return "Not for a %s" % captain.role.to_lower()
	if m.tier > Reputation.max_tier_for(captain.rank):
		return "Needs %s rank" % Reputation.rank_name(Reputation.MAX_TIER.find(m.tier))
	if factory() == null:
		return "No Factory"
	if not is_stocked(m) and factory().stock_of(m) <= 0:
		return "Factory not tooled for %s" % ShipModule.TIER_NAMES[m.tier]
	return ""


# --- Shopping -------------------------------------------------------------------

## The module this captain wants most and can afford now, or null.
## [param in_stock_only] skips parts the warehouse has none of for them.
func choose_for(ship: Ship, in_stock_only: bool = false) -> ShipModule:
	var cap := ship.captain
	var f := factory()
	if cap == null or ship.loadout == null or f == null:
		return null
	var budget := cap.wallet - RESERVE[cap.personality]
	if budget <= 0:
		return null
	var weights: Array = SLOT_WEIGHTS[cap.personality]
	var best: ShipModule = null
	var best_score := 0.0
	for m in ModuleCatalog.shared().for_role(cap.role):
		if not block_reason(cap, m).is_empty() or not ship.loadout.can_fit(m):
			continue
		if in_stock_only and f.free_stock_for(m, cap) <= 0:
			continue
		var price := price_of(m)
		if price > budget:
			continue
		var score := float(weights[m.slot])
		if cap.personality == Captain.Personality.LAZY:
			score /= maxf(float(price), 1.0) / 100.0
		else:
			score *= 1.0 + 0.3 * float(m.tier)
		if m.eject_bonus > 0.0:
			score *= 1.25 if (cap.personality == Captain.Personality.CAUTIOUS or cap.has_trait(CaptainTraits.SURVIVOR)) else 0.6
		if score > best_score:
			best_score = score
			best = m
	return best


## A docked captain looks in. Buys at most one module. Returns it or null.
## An open backorder comes first; out of stock goes by personality.
func visit(ship: Ship) -> ShipModule:
	if building == null or not building.is_active() or not is_instance_valid(ship) or ship.dead:
		return null
	var f := factory()
	var cap := ship.captain
	if f == null or cap == null:
		return null
	var order := f.order_of(cap)
	if not order.is_empty():
		var om := order["module"] as ShipModule
		if not ship.loadout.can_fit(om) or not block_reason(cap, om).is_empty():
			f.cancel_backorder(cap)
		elif f.free_stock_for(om, cap) > 0:
			return sell(ship, om)
		else:
			return null
	var want := choose_for(ship)
	if want == null:
		return null
	if f.free_stock_for(want, cap) > 0:
		return sell(ship, want)
	stockouts += 1
	f.note_miss(want)
	var alt: ShipModule = null
	if cap.personality == Captain.Personality.BOLD or cap.personality == Captain.Personality.LAZY:
		alt = choose_for(ship, true)
	if alt:
		return sell(ship, alt)
	if cap.personality == Captain.Personality.LAZY:
		ship.show_toast("%s out of stock" % want.display_name, Color(1.0, 0.8, 0.5))
		changed.emit()
		return null
	f.place_backorder(want, cap)
	ship.show_toast("Ordered %s" % want.display_name, Color(1.0, 0.85, 0.5))
	EventLog.post("%s ordered %s from the Factory (out of stock)" % [cap.captain_name, want.display_name], EventLog.Kind.INFO, ship, Vector3.INF, "order:%s:%s" % [cap.captain_name, want.id])
	changed.emit()
	return null


## Installs [param m] on [param ship], paid from the captain's wallet, from
## the Factory warehouse.
func sell(ship: Ship, m: ShipModule) -> ShipModule:
	var cap := ship.captain
	var f := factory()
	var price := price_of(m)
	if f == null or cap == null or cap.wallet < price or not ship.loadout.can_fit(m) or not block_reason(cap, m).is_empty():
		return null
	if not f.take(m, cap):
		return null
	cap.wallet -= price
	cap.credits_spent += price
	cap.modules_bought += 1
	var fitted := m.duplicate() as ShipModule
	ship.loadout.set_module(m.slot, fitted)
	ship.refit()
	var income := roundi(float(price) * sale_share)
	Economy.add_income(income, "Outfitter")
	total_sales += price
	total_income += income
	var sale := {"time": SimClock.time, "captain": cap.captain_name, "module": m.display_name, "tier": m.tier, "price": price, "income": income}
	sales.append(sale)
	if sales.size() > MAX_SALES_LISTED:
		sales.remove_at(0)
	EventLog.post("%s bought %s (%s cr)" % [cap.captain_name, m.display_name, UIUtil.amount(price)], EventLog.Kind.INFO, ship, Vector3.INF, "buy:%s:%s" % [cap.captain_name, m.id])
	ship.show_toast("Fitted %s" % m.display_name, Color(0.6, 1.0, 0.7))
	sold.emit(sale)
	changed.emit()
	return fitted

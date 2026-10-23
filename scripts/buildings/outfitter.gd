class_name Outfitter
extends Node
## Service node of the Outfitter building (see BuildingDef.service_script).
## Docked captains walk in on their own (Ship._visit_services) and buy one
## module per visit from their wallet: a Mk I..III module for a free unlocked
## slot, or an upgrade of a bought one. The best tier allowed is the lower of
## the captain's rank tier and the Outfitter's unlocked tier (Mk I at first;
## "Unlock Mk II" / "Unlock Mk III" cost materials). Rare salvaged parts stock
## one Mk II/III module early, or discount it when already stocked.
##
## What they buy follows personality (slot weights in [constant SLOT_WEIGHTS]):
##   Bold      guns and engines
##   Cautious  shields, armour, escape pods
##   Greedy    cargo holds and tools (drills), prospecting scanners
##   Lazy      engines, always the cheapest
## Each captain keeps a reserve in the wallet ([constant RESERVE]). The
## player gets [member sale_share] of every price as income.

signal sold(sale: Dictionary)
signal changed

const GROUP := "outfitters"
## Materials to unlock tier 2 / 3.
const UNLOCK_COST := {2: 300, 3: 800}
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
## Rare part discount on the stocked module.
const RARE_DISCOUNT := 0.4
const MAX_SALES_LISTED := 12

@export var sale_share: float = 0.35

var building: Building
## Highest tier on sale (1..3).
var unlocked_tier: int = 1
## Newest last: {time, captain, module, tier, price, income}.
var sales: Array[Dictionary] = []
var total_sales: int = 0
var total_income: int = 0
## Rare parts: module id -> "stocked" (sold before its tier is unlocked) or
## "discount" (next sale RARE_DISCOUNT off).
var rare_parts: Dictionary = {}


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


# --- Unlocks ------------------------------------------------------------------

## Materials needed for the next tier, 0 when all are unlocked.
func next_unlock_cost() -> int:
	return int(UNLOCK_COST.get(unlocked_tier + 1, 0))


## Why the next tier cannot be unlocked now, or "".
func unlock_block_reason() -> String:
	if unlocked_tier >= 3:
		return "All tiers unlocked"
	if building and not building.is_active():
		return "Finish construction first"
	return Economy.shortfall_text(0, next_unlock_cost())


func unlock_next() -> bool:
	if not unlock_block_reason().is_empty():
		return false
	if not Economy.spend(0, next_unlock_cost()):
		return false
	unlocked_tier += 1
	EventLog.post("Outfitter now sells %s modules" % ShipModule.TIER_NAMES[unlocked_tier], EventLog.Kind.INFO, building)
	changed.emit()
	return true


# --- Stock ----------------------------------------------------------------------

func is_stocked(m: ShipModule) -> bool:
	return m.tier <= unlocked_tier or rare_parts.get(m.id, "") == "stocked"


## Highest tier [param captain] may buy here (rank and unlocks).
func max_tier_for(captain: Captain) -> int:
	return mini(Reputation.max_tier_for(captain.rank), unlocked_tier)


func price_of(m: ShipModule) -> int:
	if rare_parts.get(m.id, "") == "discount":
		return roundi(m.cost * (1.0 - RARE_DISCOUNT))
	return m.cost


## Why [param m] is not for [param captain] now, or "".
func block_reason(captain: Captain, m: ShipModule) -> String:
	if not m.fits_role(captain.role):
		return "Not for a %s" % captain.role.to_lower()
	if m.tier > Reputation.max_tier_for(captain.rank):
		return "Needs %s rank" % Reputation.rank_name(Reputation.MAX_TIER.find(m.tier))
	if not is_stocked(m):
		return "%s not unlocked here" % ShipModule.TIER_NAMES[m.tier]
	return ""


## A salvaged rare part: [param m] is stocked before its tier is unlocked, or
## discounted when it already is.
func add_rare_part(m: ShipModule) -> String:
	var kind := "discount" if m.tier <= unlocked_tier or rare_parts.get(m.id, "") == "stocked" else "stocked"
	rare_parts[m.id] = kind
	changed.emit()
	return kind


# --- Shopping -------------------------------------------------------------------

## The module this captain wants most and can afford now, or null.
func choose_for(ship: Ship) -> ShipModule:
	var cap := ship.captain
	if cap == null or ship.loadout == null:
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
func visit(ship: Ship) -> ShipModule:
	if building == null or not building.is_active() or not is_instance_valid(ship) or ship.dead:
		return null
	var m := choose_for(ship)
	if m == null:
		return null
	return sell(ship, m)


## Installs [param m] on [param ship], paid from the captain's wallet.
func sell(ship: Ship, m: ShipModule) -> ShipModule:
	var cap := ship.captain
	var price := price_of(m)
	if cap == null or cap.wallet < price or not ship.loadout.can_fit(m) or not block_reason(cap, m).is_empty():
		return null
	cap.wallet -= price
	cap.credits_spent += price
	cap.modules_bought += 1
	if rare_parts.get(m.id, "") == "discount":
		rare_parts.erase(m.id)
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

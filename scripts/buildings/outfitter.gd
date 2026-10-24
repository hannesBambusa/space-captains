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
## An order is paid up front (only when the wallet above the reserve covers
## it) and held by the Factory; picking the part up completes the sale from
## that deposit, with no second charge. A captain with an open order buys
## nothing else until it arrives (or lapses, refunded). Each captain keeps a
## reserve in the wallet ([constant RESERVE]).
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
const RESERVE: PackedInt32Array = [20, 60, 80, 30]
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
		var why := block_reason(cap, om)
		if not ship.loadout.can_fit(om) or not why.is_empty():
			f.cancel_backorder(cap, "%s no longer fits the ship%s" % [om.display_name, " (%s)" % why.to_lower() if not why.is_empty() else ""])
		elif f.free_stock_for(om, cap) > 0:
			return sell(ship, om, "The order arrived")
		else:
			return null
	var want := choose_for(ship)
	if want == null:
		return null
	if f.free_stock_for(want, cap) > 0:
		return sell(ship, want, "First choice")
	stockouts += 1
	f.note_miss(want)
	var alt: ShipModule = null
	if cap.personality == Captain.Personality.BOLD or cap.personality == Captain.Personality.LAZY:
		alt = choose_for(ship, true)
	if alt:
		return sell(ship, alt, "Wanted %s, out of stock: a %s takes what is there" % [want.display_name, cap.get_personality_name()])
	if cap.personality == Captain.Personality.LAZY:
		cap.flight_log.note(CaptainLog.Kind.PURCHASE, CaptainLog.Outcome.FAILED, "Wanted %s, out of stock" % want.display_name,
				"Nothing else in stock fits; a Lazy captain tries again next visit", _why(cap, want), "stockout:" + String(want.id))
		ship.show_toast("%s out of stock" % want.display_name, Color(1.0, 0.8, 0.5))
		changed.emit()
		return null
	var price := price_of(want)
	if not f.place_backorder(want, cap, price):
		return null
	cap.flight_log.note(CaptainLog.Kind.PURCHASE, CaptainLog.Outcome.DID, "Ordered %s from the Factory, paid %s cr up front" % [want.display_name, UIUtil.amount(price)],
			"Out of stock: a %s %s" % [cap.get_personality_name(), "waits for the part it wants" if cap.personality != Captain.Personality.BOLD else "found nothing else worth taking, so orders it"],
			_why(cap, want), "order:" + String(want.id))
	ship.show_toast("Ordered %s (%s cr)" % [want.display_name, UIUtil.amount(price)], Color(1.0, 0.85, 0.5))
	EventLog.post("%s ordered %s from the Factory (out of stock, paid %s cr)" % [cap.captain_name, want.display_name, UIUtil.amount(price)], EventLog.Kind.INFO, ship, Vector3.INF, "order:%s:%s" % [cap.captain_name, want.id])
	changed.emit()
	return null


## Why [param cap] picked [param m]: the personality's slot weight and the tier.
func _why(cap: Captain, m: ShipModule) -> String:
	var w := float((SLOT_WEIGHTS[cap.personality] as Array)[m.slot])
	var line := "%s slot weight %.2f for a %s, %s" % [ShipModule.SLOT_NAMES[m.slot], w, cap.get_personality_name(), ShipModule.TIER_NAMES[m.tier]]
	if cap.personality == Captain.Personality.LAZY:
		line += ", cheapest that fits"
	if m.eject_bonus > 0.0:
		line += ", escape gear (%s)" % ("wanted" if cap.personality == Captain.Personality.CAUTIOUS or cap.has_trait(CaptainTraits.SURVIVOR) else "not their thing")
	return line + "; budget %s cr (wallet less %s cr reserve)" % [UIUtil.amount(maxi(cap.wallet - RESERVE[cap.personality], 0)), UIUtil.amount(RESERVE[cap.personality])]


## Installs [param m] on [param ship] from the Factory warehouse. Paid from
## the captain's wallet, or from the deposit when it fills their open order
## for [param m] (no second charge). [param context] heads the decision
## log's reason.
func sell(ship: Ship, m: ShipModule, context: String = "") -> ShipModule:
	var cap := ship.captain
	var f := factory()
	if f == null or cap == null or not ship.loadout.can_fit(m) or not block_reason(cap, m).is_empty():
		return null
	var order := f.order_of(cap)
	var prepaid: bool = not order.is_empty() and order["module"] == m
	var price := int(order.get("paid", 0)) if prepaid else price_of(m)
	if not prepaid and cap.wallet < price:
		return null
	if not f.take(m, cap):
		return null
	var why := ("%s: " % context if not context.is_empty() else "") + _why(cap, m)
	if not prepaid:
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
	var headline := ("Picked up %s, paid %s cr when ordered" if prepaid else "Bought %s for %s cr") % [m.display_name, UIUtil.amount(price)]
	cap.flight_log.note(CaptainLog.Kind.PURCHASE, CaptainLog.Outcome.DID, headline,
			why,
			"Wallet %s cr left, keeps %s cr in reserve. %s" % [UIUtil.amount(cap.wallet), UIUtil.amount(RESERVE[cap.personality]), m.blurb])
	ship.show_toast("Fitted %s" % m.display_name, Color(0.6, 1.0, 0.7))
	sold.emit(sale)
	changed.emit()
	return fitted


# --- Save ---------------------------------------------------------------------

func save_state() -> Dictionary:
	return SaveUtil.props(self, ["sales", "total_sales", "total_income", "stockouts"])


func load_state(d: Dictionary, _refs: SaveRefs) -> void:
	SaveUtil.apply_props(self, d)
	changed.emit()

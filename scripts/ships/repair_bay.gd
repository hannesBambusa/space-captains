class_name RepairBay
extends RefCounted
## Paid hull repairs in a home berth. Hull never regenerates in space (only
## shields do, see Durability); docked, the ship is patched up at
## Ship.dock_repair_rate, and the captain pays [constant COST_PER_HULL] per
## hull point from their wallet. The station keeps [constant PLAYER_SHARE]
## of it as income ("Repairs"). A broke captain gets what the wallet covers
## and the rest waits until they have earned more ([method can_afford]).
## Ships without a captain (or not the player's) repair for free.
## One repair session per docking: when it ends (hull done, wallet empty or
## the ship leaves), the station's share is paid in one sum and the feed
## gets one line ([method end_session]).

## Credits per hull point: a full repair of a 380-hull mercenary is about 57 cr.
const COST_PER_HULL := 0.15
## Share of the repair bill that is the station's income.
const PLAYER_SHARE := 0.35
## Repairs run to this hull fraction (full). MercenaryBrain.REPAIRED is the
## lower level at which a docked merc stays in the berth for them.
const DONE_AT := 1.0
## Hull points short of the goal that count as done: float sums never land
## exactly on max_hull * DONE_AT (368.6 / 380 is 0.96999.. < 0.97).
const HULL_EPS := 0.01


## Cost of bringing [param ship] back to [constant DONE_AT], credits.
static func cost_to_repair(ship: Ship) -> int:
	if ship == null or ship.durability == null:
		return 0
	var missing := maxf(ship.durability.max_hull * DONE_AT - ship.durability.hull, 0.0)
	return ceili(missing * COST_PER_HULL)


## True when the hull needs work.
static func needs_repair(ship: Ship) -> bool:
	return ship != null and ship.durability != null and ship.durability.hull < ship.durability.max_hull * DONE_AT - HULL_EPS


## True when the captain can pay for at least a little more hull.
static func can_afford(ship: Ship) -> bool:
	if not _pays(ship):
		return true
	return float(ship.captain.wallet) + ship.repair_credit >= COST_PER_HULL


## True when [param ship] is below [param hull] (fraction) and its captain
## can pay for repairs: it should fly home for them first.
static func should_repair(ship: Ship, hull: float) -> bool:
	return ship.hull_fraction() < hull and can_afford(ship)


## One docked step: repairs what the rate and the wallet allow. Returns the
## hull points repaired.
static func step(ship: Ship, dt: float) -> float:
	var d := ship.durability
	var goal := d.max_hull * DONE_AT
	if not needs_repair(ship) or dt <= 0.0:
		_finish(ship, goal)
		ship.repairing = false
		end_session(ship)
		return 0.0
	var points := minf(d.max_hull * ship.dock_repair_rate * dt, goal - d.hull)
	if _pays(ship):
		var cap := ship.captain
		# Pay whole credits up front; the change is kept for the next step.
		var cost := points * COST_PER_HULL
		if ship.repair_credit < cost:
			var need := ceili(cost - ship.repair_credit)
			var paid := mini(need, maxi(cap.wallet, 0))
			if ship.repair_session_paid <= 0:
				ship.repair_from = d.fraction()
			cap.wallet -= paid
			cap.credits_spent += paid
			ship.repair_credit += float(paid)
			ship.repair_session_paid += paid
		if ship.repair_credit < cost:
			points = ship.repair_credit / COST_PER_HULL
			cost = ship.repair_credit
		ship.repair_credit -= cost
	if points <= 0.0001:
		ship.repairing = false
		end_session(ship)
		return 0.0
	d.repair(points)
	if not needs_repair(ship):
		_finish(ship, goal)
		ship.repairing = false
		end_session(ship)
		return points
	ship.repairing = true
	return points


## Snaps a hull within [constant HULL_EPS] of the goal onto it, so the
## fraction reads done everywhere.
static func _finish(ship: Ship, goal: float) -> void:
	var d := ship.durability
	if not d.is_dead() and d.hull < goal and not needs_repair(ship):
		d.hull = goal


## Pays the station its share of the session's bill and posts one line.
static func end_session(ship: Ship) -> void:
	var paid := ship.repair_session_paid
	if paid <= 0:
		return
	ship.repair_session_paid = 0
	var share := roundi(float(paid) * PLAYER_SHARE)
	Economy.add_income(share, Ledger.REPAIRS, "Ship repairs")
	var who := ship.captain.captain_name if ship.captain else ship.get_display_name()
	var note := "" if not needs_repair(ship) else ", %d%% hull (wallet empty)" % roundi(ship.hull_fraction() * 100.0)
	EventLog.post("%s paid %d cr for repairs%s. Repairs: +%d cr" % [who, paid, note, share], EventLog.Kind.REWARD, ship, Vector3.INF, "repairs:" + who)
	if ship.captain:
		var partial := needs_repair(ship)
		var broke := partial and not can_afford(ship)
		var pct := floori(ship.hull_fraction() * 100.0)
		var headline := "Repaired to %d%% for %d cr" % [pct, paid]
		if broke:
			headline = "Left with hull %d%%: out of credits" % pct
		elif partial:
			headline = "Paid %d cr for repairs, only part of the job" % paid
		var why := "Hull %d%% to %d%% for %d cr at %.2f cr per hull point" % [roundi(ship.repair_from * 100.0), pct, paid, COST_PER_HULL]
		if broke:
			why += ": the wallet ran dry, %d cr still to go; flies on damaged" % cost_to_repair(ship)
		elif partial:
			why += ": left the berth before the job was done"
		ship.captain.flight_log.note(CaptainLog.Kind.REPAIR, CaptainLog.Outcome.FAILED if partial else CaptainLog.Outcome.DID, headline, why,
				"Wallet now %s cr. The station keeps %d%% (%d cr)." % [Fmt.amount(ship.captain.wallet), roundi(PLAYER_SHARE * 100.0), share],
				"repairs_broke" if broke else "")


static func _pays(ship: Ship) -> bool:
	return ship != null and ship.captain != null and ship.faction == Combat.Faction.PLAYER

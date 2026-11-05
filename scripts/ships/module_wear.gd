class_name ModuleWear
extends RefCounted
## Bought modules (Mk I..III) wear out with use, so captains keep coming back
## to the Outfitter (the player's sale share, the Factory's ore demand).
## Stock fittings (tier 0) never wear.
##
## ShipModule.condition runs from 1 (new) to 0. Use is counted in seconds
## of work and a module lasts [constant LIFE] of them by tier:
##   engine, sensor  every sim second in space (Ship.sim_step)
##   tool            drills and salvage claws per second of work
##                   (CaptainBrain, Ship.job_work), guns [constant SHOT_S] per
##                   shot (ShipWeapon.try_fire)
##   defense         [constant DAMAGE_S] per point of damage taken (Ship.take_hit)
##   cargo           [constant LOAD_S] per load delivered (CaptainBrain._deliver);
##                   an ammo rack (a mercenary's cargo slot) per shot like the guns
## Worn parts work less well ([method effect_of], applied in
## ShipLoadout.derive): below [constant WORN] at [constant WORN_EFFECT], below
## [constant FAILING] at [constant FAILING_EFFECT]. At 0 the part breaks and
## the slot goes back to the hull's stock part. Below [constant REPLACE_AT]
## a captain may buy the same tier again for that slot, first in line
## (ShipLoadout.can_fit, Outfitter.choose_for).

## Seconds of use a module lasts, by tier (stock, Mk I, Mk II, Mk III).
const LIFE: Array[float] = [0.0, 1500.0, 2100.0, 2700.0]
const SHOT_S := 1.0
const DAMAGE_S := 0.5
const LOAD_S := 60.0
const WORN := 0.25
const WORN_EFFECT := 0.85
const FAILING := 0.1
const FAILING_EFFECT := 0.7
const REPLACE_AT := 0.35


## How well [param m] works now: 1, or less when worn.
static func effect_of(m: ShipModule) -> float:
	if m == null or m.tier < 1:
		return 1.0
	if m.condition < FAILING:
		return FAILING_EFFECT
	if m.condition < WORN:
		return WORN_EFFECT
	return 1.0


## True when [param m] is worn enough that its captain shops for a new one.
static func is_worn(m: ShipModule) -> bool:
	return m != null and m.tier >= 1 and m.condition < REPLACE_AT


## "84%" for a bought module, "" for a stock part.
static func condition_text(m: ShipModule) -> String:
	if m == null or m.tier < 1:
		return ""
	return "%d%%" % ceili(m.condition * 100.0)


## A sim step in space: the engine and the sensors wear.
static func fly(ship: Ship, dt: float) -> void:
	use(ship, ShipModule.Slot.ENGINE, dt)
	use(ship, ShipModule.Slot.SENSOR, dt)


## One shot fired: the guns wear, and an ammo rack in the cargo slot.
static func shot(ship: Ship) -> void:
	if ship == null or ship.loadout == null:
		return
	use(ship, ShipModule.Slot.TOOL, SHOT_S)
	var rack := ship.loadout.get_module(ShipModule.Slot.CARGO)
	if rack and not is_equal_approx(rack.fire_rate_mult, 1.0):
		use(ship, ShipModule.Slot.CARGO, SHOT_S)


## Wears [param ship]'s module in [param slot] by [param seconds] of use.
## Re-derives the stats when it crosses a wear level, breaks it at 0.
static func use(ship: Ship, slot: ShipModule.Slot, seconds: float) -> void:
	if seconds <= 0.0 or ship == null or ship.captain == null or ship.loadout == null or ship.dead:
		return
	var m := ship.loadout.get_module(slot)
	if m == null or m.tier < 1:
		return
	var before := effect_of(m)
	var was_worn := is_worn(m)
	m.condition = maxf(m.condition - seconds / LIFE[clampi(m.tier, 1, 3)], 0.0)
	if m.condition <= 0.0:
		_break(ship, m)
		return
	if effect_of(m) != before:
		ship.refit()
	if is_worn(m) and not was_worn:
		ship.captain.flight_log.note(CaptainLog.Kind.PURCHASE, CaptainLog.Outcome.DID, "%s is wearing out (%s)" % [m.display_name, condition_text(m)],
				"Parts wear with use; below %d%% they shop for a new one at the Outfitter" % roundi(REPLACE_AT * 100.0), "", "worn:" + String(m.id))


static func _break(ship: Ship, m: ShipModule) -> void:
	var cap := ship.captain
	ship.loadout.set_module(m.slot, ShipLoadout.stock_part(ship.get_role_name(), m.slot))
	ship.refit()
	cap.flight_log.note(CaptainLog.Kind.PURCHASE, CaptainLog.Outcome.FAILED, "%s wore out" % m.display_name,
			"Used up after about %d min of work; the %s slot is back on the stock part" % [roundi(LIFE[clampi(m.tier, 1, 3)] / 60.0), ShipModule.SLOT_NAMES[m.slot].to_lower()],
			"", "broke:" + String(m.id))
	ship.show_toast("%s wore out" % m.display_name, Color(1.0, 0.7, 0.4))
	EventLog.post("%s's %s wore out" % [cap.captain_name, m.display_name], EventLog.Kind.INFO, ship, Vector3.INF, "broke:%s:%s" % [cap.captain_name, m.id])

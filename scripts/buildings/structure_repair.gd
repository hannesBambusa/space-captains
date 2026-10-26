class_name StructureRepair
extends RefCounted
## The station's own hull repairs of a structure, shared by [StructureHull]
## (outposts, the station) and [DefenseStructure] (turrets, shield
## generators): from the owner's repair delay after the last hit, its repair
## rate of max hull per second, paid by the player at
## [constant COST_PER_HULL] per point. Whole credits are paid up front and
## the change is kept for the next step. No credits, no repairs. A session
## runs until the hull is full, the credits run out or the next hit; the
## owner posts one feed line per session ([signal session_ended]).

## Repairing started or stopped.
signal changed
## A session ended; [param paid] credits were spent on it (0 or more).
## Emitted before [signal changed].
signal session_ended(paid: int)

## RepairBay's rate less the share the station keeps from captains (the
## station pays the yard, not itself).
const COST_PER_HULL := RepairBay.COST_PER_HULL * (1.0 - RepairBay.PLAYER_SHARE)
## Saved fields, under the owners' old save keys.
const FIELDS: PackedStringArray = ["repairing", "repair_session_paid", "repair_total_paid", "_repair_credit"]

var repairing := false
## Credits paid for repairs this session / ever.
var repair_session_paid: int = 0
var repair_total_paid: int = 0

var _repair_credit := 0.0


## Repairs [param d] when [param active] and [param delay] sim seconds have
## passed since the last hit, at [param rate] of max hull per second; ends
## the session otherwise.
func step(d: Durability, dt: float, active: bool, delay: float, rate: float) -> void:
	if active and d.hull < d.max_hull and d.seconds_since_hit() >= delay:
		_repair(d, dt, rate)
	elif repairing:
		end_session()


## Credits to bring [param d] back to full.
static func cost_to_repair(d: Durability) -> int:
	if d == null:
		return 0
	return ceili(maxf(d.max_hull - d.hull, 0.0) * COST_PER_HULL)


func _repair(d: Durability, dt: float, rate: float) -> void:
	var points := minf(d.max_hull * rate * dt, d.max_hull - d.hull)
	var cost := points * COST_PER_HULL
	if _repair_credit < cost:
		# Whole credits up front; the change is kept for the next step.
		var need := ceili(cost - _repair_credit)
		if Economy.credits < need or not Economy.spend(need, PackedInt32Array(), Ledger.REPAIRS, "Structure repairs"):
			if repairing:
				end_session()
			return
		_repair_credit += float(need)
		repair_session_paid += need
		repair_total_paid += need
	_repair_credit -= cost
	d.repair(points)
	if not repairing:
		repairing = true
		changed.emit()
	if d.hull >= d.max_hull:
		end_session()


## Ends the session (on a hit, when destroyed). Nothing when none is open.
func end_session() -> void:
	if not repairing and repair_session_paid <= 0:
		return
	repairing = false
	var paid := repair_session_paid
	repair_session_paid = 0
	session_ended.emit(paid)
	changed.emit()


func save_state() -> Dictionary:
	return SaveUtil.props(self, FIELDS)


## Missing keys keep their value (older saves).
func load_state(d: Dictionary) -> void:
	for n in FIELDS:
		if d.has(n):
			set(n, d[n])

class_name BountyContract
extends Contract
## Destroy a target: a raider ship or a hostile base (any faction). Posting
## reserves the reward: it leaves the player's credits at once into
## [member escrow] (held by the ContractBoard), so it can always be paid.
## When the target dies the reward is paid from the escrow, split equally
## among the player ships that damaged it in the last
## [constant CREDIT_WINDOW] seconds (the killer alone when it was alone);
## what is left (nobody eligible) goes back to the player.
## The contract completes on its own when the target dies, and is cancelled
## when the target leaves without dying (a scavenger slipping home).
## Fleets: a target too strong for one ship gets a [MercFleet]; once it
## leaves the rally point nobody else takes the contract, and the fleet
## splits the reward (ContractBoard). A lone wolf going after it alone
## claims it ([method claim_solo]) and keeps the whole reward.

## Damage older than this does not earn a share, sim seconds.
const CREDIT_WINDOW := 90.0

## Who got paid and how much, filled on completion: [{ship_name, credits}].
var payouts: Array[Dictionary] = []
var killer_name: String = ""
## The fleet working it (null when none).
var fleet: MercFleet
## Credits reserved for this bounty and not paid out yet.
var escrow: int = 0
var _solo: WeakRef


func _init(on_target: Node3D = null, credits: int = 0, taker_limit: int = 3) -> void:
	type = Type.BOUNTY
	target = on_target
	reward = credits
	max_takers = taker_limit


func is_den() -> bool:
	return target is ScavengerDen


func is_available() -> bool:
	if not super.is_available() or not Combat.is_live(target):
		return false
	if fleet and not fleet.is_recruiting():
		return false
	return solo_runner() == null


## A lone wolf took it on alone: nobody else joins while they are on it.
func claim_solo(ship: Ship) -> void:
	_solo = weakref(ship)
	changed.emit(self)


## The lone wolf on it alone, or null.
func solo_runner() -> Ship:
	var s := _solo.get_ref() as Ship if _solo else null
	if s == null or s.dead or not takers.has(s):
		return null
	return s


## "Fleet of 3 forming", "Rhea Voss alone" or "".
func get_team_text() -> String:
	if fleet and fleet.state != MercFleet.State.DONE:
		return fleet.get_label()
	var s := solo_runner()
	if s:
		return "%s alone" % s.get_display_name()
	return ""


func get_target_name() -> String:
	if is_instance_valid(target) and target.has_method(&"get_display_name"):
		return String(target.call(&"get_display_name"))
	return super.get_target_name()


func get_reward_text() -> String:
	return "%d cr" % reward


func get_activity_text() -> String:
	return get_team_text()


## Taken: a captain is on it (alone or in a fleet).
func is_taken() -> bool:
	return not takers.is_empty() or (fleet != null and not fleet.members.is_empty())


func get_progress_text() -> String:
	if status == Status.COMPLETED:
		return "destroyed" + (" by %s" % killer_name if not killer_name.is_empty() else "")
	if Combat.is_live(target):
		var d := target.get(&"durability") as Durability
		if d:
			return "hull %d%%" % roundi(d.fraction() * 100.0)
	return ""


## The target faction's bounty danger (scavengers: hideout 4, ship 2).
func get_danger() -> int:
	var f := Factions.of(target)
	if is_den():
		return f.den_bounty_danger if f else 4
	return f.ship_bounty_danger if f else 2


## The target's faction ("Corsairs"), "" when none.
func get_faction_name() -> String:
	var f := Factions.of(target)
	return f.display_name if f else ""


## Called by the board when the target died.
func mark_completed() -> void:
	if not is_finished():
		takers.clear()
		_set_status(Status.COMPLETED)

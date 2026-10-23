class_name BountyContract
extends Contract
## Destroy a target: a scavenger ship or a Scavenger Den. Nothing is reserved
## when posting; when the target dies the reward is paid from the player's
## credits, split equally among the player ships that damaged it in the last
## [constant CREDIT_WINDOW] seconds (the killer alone when it was alone).
## The contract completes on its own when the target dies, and is cancelled
## when the target leaves without dying (a scavenger slipping home).

## Damage older than this does not earn a share, sim seconds.
const CREDIT_WINDOW := 90.0

## Who got paid and how much, filled on completion: [{ship_name, credits}].
var payouts: Array[Dictionary] = []
var killer_name: String = ""


func _init(on_target: Node3D = null, credits: int = 0, taker_limit: int = 3) -> void:
	type = Type.BOUNTY
	target = on_target
	reward = credits
	max_takers = taker_limit


func is_den() -> bool:
	return target is ScavengerDen


func is_available() -> bool:
	return super.is_available() and Combat.is_live(target)


func get_target_name() -> String:
	if is_instance_valid(target) and target.has_method(&"get_display_name"):
		return String(target.call(&"get_display_name"))
	return super.get_target_name()


func get_reward_text() -> String:
	return "%d cr" % reward


func get_progress_text() -> String:
	if status == Status.COMPLETED:
		return "destroyed" + (" by %s" % killer_name if not killer_name.is_empty() else "")
	if Combat.is_live(target):
		var d := target.get(&"durability") as Durability
		if d:
			return "hull %d%%" % roundi(d.fraction() * 100.0)
	return ""


func get_danger() -> int:
	if is_den():
		return 4
	return 2


## Called by the board when the target died.
func mark_completed() -> void:
	if not is_finished():
		takers.clear()
		_set_status(Status.COMPLETED)

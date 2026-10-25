class_name Contract
extends RefCounted
## A paid job the player posts on the ContractBoard. Captains decide on their
## own whether to take it (see CaptainBrain and the per-role evaluators).
##
## Subclasses per [enum Type] fill in the target and the work: MiningContract
## now; BountyContract (target: an enemy ship or den, paid on destruction) and
## EscortContract (target: a miner or a mining contract, paid per completed
## trip) later; SalvageContract (target: a scrap field, paid per load) in
## stage 3. The board, the UI rows and the brain only use this base API.
##
## Status: OPEN (no one on it), ACTIVE (at least one taker on a trip),
## COMPLETED (limit reached), CANCELLED (withdrawn by the player). Takers are
## the ships currently working a trip on this contract.

signal changed(contract: Contract)

enum Type { MINING, BOUNTY, ESCORT, SALVAGE }
enum Status { OPEN, ACTIVE, COMPLETED, CANCELLED }

const TYPE_NAMES: PackedStringArray = ["Mining", "Bounty", "Escort", "Salvage"]
const STATUS_NAMES: PackedStringArray = ["Open", "Active", "Completed", "Cancelled"]

var id: int = 0
var type: Type = Type.MINING
## What the contract is about (a belt, an enemy, a ship to escort).
var target: Node3D
## Credits per unit of work (per load, per kill, per trip).
var reward: int = 0
var status: Status = Status.OPEN
var takers: Array[Node] = []
## Max ships on it at once. 0 = no limit.
var max_takers: int = 0
var created_time: float = 0.0
## Total credits paid out so far.
var credits_paid: int = 0
## Ships that ever took it (stats).
var times_taken: int = 0


func is_finished() -> bool:
	return status == Status.COMPLETED or status == Status.CANCELLED


## True when a new taker may start a trip on it.
func is_available() -> bool:
	if is_finished() or not is_instance_valid(target):
		return false
	return max_takers <= 0 or takers.size() < max_takers


func add_taker(ship: Node) -> bool:
	if not is_available() or takers.has(ship):
		return false
	takers.append(ship)
	times_taken += 1
	_update_status()
	return true


func remove_taker(ship: Node) -> void:
	takers.erase(ship)
	_update_status()


func get_type_name() -> String:
	return TYPE_NAMES[type]


func get_status_name() -> String:
	if is_paused():
		return "Paused, station can't pay"
	return STATUS_NAMES[status]


## Paid per delivery or trip from the player's credits at the time (mining,
## escort, salvage bonus); a bounty is reserved when posted instead.
func pays_per_delivery() -> bool:
	return type != Type.BOUNTY


## The station cannot pay one payment now: captains do not take it ("Station
## can't pay") until credits come in. Trips under way are paid what is there.
func is_paused() -> bool:
	return not is_finished() and pays_per_delivery() and reward > 0 and Economy.credits < reward


## Short name of the target, e.g. "Cinder Belt".
func get_target_name() -> String:
	return String(target.name) if is_instance_valid(target) else "?"


func get_title() -> String:
	return "%s: %s" % [get_type_name(), get_target_name()]


## "50 cr/load" style reward text.
func get_reward_text() -> String:
	return "%d cr" % reward


## One-line progress text for lists ("3 / 10 loads").
func get_progress_text() -> String:
	return ""


## Where the work happens (world, on the plane). Markers and scoring use it.
## [param from] is the asker's position, for targets that span an area.
func get_site_position(_from: Vector3 = Vector3.ZERO) -> Vector3:
	return target.global_position if is_instance_valid(target) else Vector3.ZERO


## Danger 1..5 of the job.
func get_danger() -> int:
	return 1


## Withdrawn by the player (use ContractBoard.cancel).
func mark_cancelled() -> void:
	if not is_finished():
		_set_status(Status.CANCELLED)


func _update_status() -> void:
	if not is_finished():
		status = Status.ACTIVE if not takers.is_empty() else Status.OPEN
	changed.emit(self)


func _set_status(s: Status) -> void:
	status = s
	changed.emit(self)

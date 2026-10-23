class_name MercenaryShip
extends Ship
## A hired mercenary fighter. Flight, docking and repairs come from Ship,
## the decisions from MercenaryBrain (patrol and defend home, bounty and
## escort contracts scored by MercenaryEvaluator, retreat to repair).
## This class only sets the role, the circling side for attack runs and the
## belt lane of escorts.

## +1 / -1: which way this pilot circles a target.
var attack_side: float = 1.0


func _init() -> void:
	role = Role.MERCENARY
	hit_radius = 9.0


## Escorts fly in their miner's belt lane, so they stay beside it.
func lane_sign() -> float:
	var mb := brain as MercenaryBrain
	if mb and mb.mode == MercenaryBrain.Mode.ESCORT and mb.trip:
		var ec := mb.trip.contract as EscortContract
		var w := ec.miner_of(self) if ec else null
		if is_instance_valid(w):
			return w.lane_sign()
	return super.lane_sign()


func _make_brain() -> CaptainBrain:
	return MercenaryBrain.new(self, MercenaryEvaluator.new())


func _on_ready_ship() -> void:
	attack_side = 1.0 if randf() < 0.5 else -1.0
	set_meta(&"focus_distance", 170.0)


func _on_damaged(_amount: float, attacker: Node3D) -> void:
	var mb := brain as MercenaryBrain
	if mb:
		mb.on_attacked(attacker)

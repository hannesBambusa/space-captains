class_name RoleEvaluator
extends RefCounted
## Scores contracts for one ship role. CaptainBrain owns one and calls
## [method pick] when the captain is idle. Subclass per role: MinerEvaluator
## (mining contracts) now; a mercenary evaluator (bounty, escort) in stage 2
## only needs [method handles] and [method evaluate].

## Refusal reasons shown in the UI.
const TOO_DANGEROUS := "Too dangerous for that pay"
const TOO_FAR := "Too far"
const NOT_WORTH_IT := "Not worth it"
const CANT_PAY := "Station can't pay"
## Union Rep refusing below-fair pay.
const BELOW_FAIR := "Pay below fair, the union says no"


class Evaluation:
	var contract: Contract
	var utility: float = 0.0
	var accept: bool = false
	## Why not, when [member accept] is false.
	var reason: String = ""
	## Score parts for debugging and the UI tooltip.
	var terms: Dictionary = {}


## True when this role can work contracts of [param type].
func handles(_type: Contract.Type) -> bool:
	return false


## Scores one contract for the brain's captain. Null when not handled.
func evaluate(_brain: CaptainBrain, _contract: Contract) -> Evaluation:
	return null


## Best accepted evaluation, or the best refused one (for its reason), or null
## when nothing on the list is for this role.
func pick(brain: CaptainBrain, contracts: Array[Contract]) -> Evaluation:
	var best_yes: Evaluation = null
	var best_no: Evaluation = null
	for c in contracts:
		if not handles(c.type):
			continue
		var e := evaluate(brain, c)
		if e == null:
			continue
		if e.accept:
			if best_yes == null or e.utility > best_yes.utility:
				best_yes = e
		elif best_no == null or e.utility > best_no.utility:
			best_no = e
	return best_yes if best_yes else best_no

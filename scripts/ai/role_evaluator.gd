class_name RoleEvaluator
extends RefCounted
## Scores contracts for one ship role. CaptainBrain owns one and calls
## [method pick] when the captain is idle. Subclass per role: MinerEvaluator
## (mining contracts) now; a mercenary evaluator (bounty, escort) in stage 2
## only needs [method handles] and [method evaluate].

## Travel term scale: sim seconds of the trip (warp hops included, see
## [method travel_of]) per unit of distance cost. Raised from 30 with the
## fuller travel estimate (zone exit, approach), so the cost per km held.
const TRAVEL_SCALE_S := 45.0

## Refusal reasons shown in the UI.
const TOO_DANGEROUS := "Too dangerous for that pay"
## A refusal mostly down to the travel cost. Distance never refuses a job
## on its own: better pay always makes a far trip worth it.
const NOT_WORTH_TRIP := "Not worth the trip at this pay"
const NOT_WORTH_IT := "Not worth it"
const CANT_PAY := "Station can't pay"
## Union Rep refusing below-fair pay.
const BELOW_FAIR := "Pay below fair, the union says no"
## Trait terms (CaptainTraits): Lone Wolf on solo work, Union Rep at
## below-fair pay.
const LONE_WOLF_BONUS := 0.1
const UNION_SULK := 0.35


class Evaluation:
	var contract: Contract
	var utility: float = 0.0
	var accept: bool = false
	## Why not, when [member accept] is false.
	var reason: String = ""
	## Score parts for debugging and the UI tooltip.
	var terms: Dictionary = {}


## Every evaluation of the last [method pick], in board order (the decision
## log lists the best alternatives from it).
var scored: Array[Evaluation] = []


## Sim seconds to fly [param km] one way: x = warp hop, y = normal flight.
static func travel_of(brain: CaptainBrain, km: float) -> Vector2:
	return SpaceNav.travel_estimate(km * 1000.0, brain.ship.max_speed if brain.ship else SpaceNav.REF_SPEED)


## Pay term: pay_weight * Greed * [param reward] / [param scale].
static func pay_term(brain: CaptainBrain, reward: float, scale: float) -> float:
	var cap := brain.captain
	return brain.profile.pay_weight * reward / scale * (cap.pay_scale() if cap else 1.0)


## Distance term: distance_weight * one-way travel time ([method travel_of])
## / [param scale].
static func distance_term(brain: CaptainBrain, trip: Vector2, scale: float = TRAVEL_SCALE_S) -> float:
	return brain.profile.distance_weight * (trip.x + trip.y) / scale


## Danger term: danger_weight * (danger - 1)^2 / 4 * Nerve.
static func danger_term(brain: CaptainBrain, danger: int) -> float:
	var cap := brain.captain
	return brain.profile.danger_weight * pow(float(maxi(danger - 1, 0)), 2.0) / 4.0 * (cap.danger_scale() if cap else 1.0)


## Random term, +-profile.noise (one roll of the brain's rng).
static func noise_of(brain: CaptainBrain) -> float:
	return brain.rng.randf_range(-brain.profile.noise, brain.profile.noise)


## True when a Union Rep sulks at [param pay] below [param fair].
static func sulks(cap: Captain, pay: float, fair: float) -> bool:
	return cap != null and cap.has_trait(CaptainTraits.UNION_REP) and pay < fair


## [param base] plus the Lone Wolf bonus on [param solo] work, less the
## Union Rep sulk when [param sulking].
static func trait_bonus(cap: Captain, base: float, solo: bool, sulking: bool) -> float:
	var t := base
	if cap and solo and cap.has_trait(CaptainTraits.LONE_WOLF):
		t += LONE_WOLF_BONUS
	if sulking:
		t -= UNION_SULK
	return t


## The hard rules and the threshold of a per-load job (mining, salvage,
## raid) on a scored [param e] (terms pay, distance, danger): station can't
## pay, the premium rule ([param offered] against [param fair] from
## the profile's premium danger), then the threshold with its reason. Sets
## [member Evaluation.reason] or [member Evaluation.accept]. No distance
## limit: travel only counts in the score (a low score mostly from it reads
## [constant NOT_WORTH_TRIP]).
static func judge(e: Evaluation, prof: PersonalityProfile, danger: int, offered: float, fair: float, sulking: bool) -> void:
	var pay: float = e.terms["pay"]
	var dist: float = e.terms["distance"]
	var dang: float = e.terms["danger"]
	if e.contract.is_paused():
		e.reason = CANT_PAY
	elif prof.premium_danger > 0 and danger >= prof.premium_danger and offered < fair * prof.premium_factor:
		e.reason = TOO_DANGEROUS
	elif e.utility < prof.accept_threshold:
		if sulking:
			e.reason = BELOW_FAIR
		elif dang >= dist and dang > pay * 0.25:
			e.reason = TOO_DANGEROUS
		elif dist > pay * 0.25:
			e.reason = NOT_WORTH_TRIP
		else:
			e.reason = NOT_WORTH_IT
	else:
		e.accept = true


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
	scored.clear()
	for c in contracts:
		if not handles(c.type):
			continue
		var e := evaluate(brain, c)
		if e == null:
			continue
		scored.append(e)
		if e.accept:
			if best_yes == null or e.utility > best_yes.utility:
				best_yes = e
		elif best_no == null or e.utility > best_no.utility:
			best_no = e
	return best_yes if best_yes else best_no

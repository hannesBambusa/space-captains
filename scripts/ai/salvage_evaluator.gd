class_name SalvageEvaluator
extends RoleEvaluator
## Salvager scoring for salvage contracts.
##   pay      = pay_weight * Greed * reward / PAY_SCALE
##   distance = distance_weight * one-way km from the yard / DIST_SCALE_KM
##   danger   = danger_weight * Nerve * (danger - 1)^2 / 4 (dens nearby, the
##              belt the field lies in: SalvageContract.danger_at)
##   size     = SIZE_WEIGHT * log2(scrap / SIZE_REF), clamped: big fields
##              are worth the trip, scraps are not
##   utility  = pay - distance - danger + size + Loyalty bonus + noise
## Hard rules as for miners: the station must afford one load, max trip
## length, and the premium rule for dangerous places (fair pay:
## SalvageContract.FAIR_REWARD). Traits: Lone Wolf +0.1, Union Rep sulks at
## below-fair pay.

const PAY_SCALE := 40.0
const DIST_SCALE_KM := 5.0
const SIZE_WEIGHT := 0.15
const SIZE_REF := 40.0


func handles(type: Contract.Type) -> bool:
	return type == Contract.Type.SALVAGE


func evaluate(brain: CaptainBrain, contract: Contract) -> Evaluation:
	var sc := contract as SalvageContract
	if sc == null or not is_instance_valid(sc.field):
		return null
	var prof := brain.profile
	var cap := brain.captain
	var e := Evaluation.new()
	e.contract = contract
	var km := Combat.flat_distance(sc.field.global_position, brain.home_position()) / 1000.0
	var danger := sc.get_danger()
	var fair := SalvageContract.FAIR_REWARD
	var pay := prof.pay_weight * float(sc.reward) / PAY_SCALE * (cap.pay_scale() if cap else 1.0)
	var dist := prof.distance_weight * km / DIST_SCALE_KM
	var dang := prof.danger_weight * pow(float(maxi(danger - 1, 0)), 2.0) / 4.0 * (cap.danger_scale() if cap else 1.0)
	var size := clampf(SIZE_WEIGHT * log(maxf(float(sc.field.amount), 1.0) / SIZE_REF) / log(2.0), -0.25, 0.45)
	var loyal := cap.loyalty_bonus() if cap else 0.0
	var sulking := false
	if cap:
		if cap.has_trait(CaptainTraits.LONE_WOLF):
			loyal += MinerEvaluator.LONE_WOLF_BONUS
		if cap.has_trait(CaptainTraits.UNION_REP) and sc.reward < fair:
			loyal -= MinerEvaluator.UNION_SULK
			sulking = true
	e.utility = pay - dist - dang + size + loyal + brain.rng.randf_range(-prof.noise, prof.noise)
	e.terms = {"pay": pay, "distance": dist, "danger": dang, "size": size, "km": km}
	if Economy.credits < sc.reward:
		e.reason = CANT_PAY
	elif prof.max_trip_km > 0.0 and km > prof.max_trip_km:
		e.reason = TOO_FAR
	elif prof.premium_danger > 0 and danger >= prof.premium_danger and float(sc.reward) < float(fair) * prof.premium_factor:
		e.reason = TOO_DANGEROUS
	elif e.utility < prof.accept_threshold:
		if sulking:
			e.reason = BELOW_FAIR
		elif dang >= dist and dang > pay * 0.25:
			e.reason = TOO_DANGEROUS
		elif dist > pay * 0.25:
			e.reason = TOO_FAR
		else:
			e.reason = NOT_WORTH_IT
	else:
		e.accept = true
	return e

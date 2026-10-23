class_name MinerEvaluator
extends RoleEvaluator
## Miner scoring for mining contracts.
##   pay      = pay_weight * reward / PAY_SCALE
##   distance = distance_weight * one-way km from the home outpost / DIST_SCALE_KM
##   danger   = danger_weight * (danger - 1)^2 / 4
##   utility  = pay - distance - danger + noise(+-profile.noise)
## Hard rules before the threshold: the station must afford one load, the trip
## must be within max_trip_km, and from premium_danger up the reward must be
## premium_factor times the fair reward (MiningRules.default_reward).
## Attributes: Greed scales the pay term, Nerve the danger term, Loyalty adds
## a small bonus. An escorted mining contract (linked EscortContract) counts
## as [constant ESCORT_DANGER_RELIEF] danger levels safer.
## Traits (see CaptainTraits): Crystal Hound +[constant CRYSTAL_HOUND_BONUS] on
## crystal belts; Lone Wolf ignores escort cover and scores solo work
## +[constant LONE_WOLF_BONUS]; Union Rep scores below-fair pay
## -[constant UNION_SULK] and says so.

const PAY_SCALE := 50.0
const DIST_SCALE_KM := 5.0
const ESCORT_DANGER_RELIEF := 2
const CRYSTAL_HOUND_BONUS := 0.3
const LONE_WOLF_BONUS := 0.1
const UNION_SULK := 0.35


func handles(type: Contract.Type) -> bool:
	return type == Contract.Type.MINING


func evaluate(brain: CaptainBrain, contract: Contract) -> Evaluation:
	var mc := contract as MiningContract
	if mc == null or not is_instance_valid(mc.belt):
		return null
	var prof := brain.profile
	var e := Evaluation.new()
	e.contract = contract
	var km := SpaceNav.distance_to_belt(mc.belt, brain.home_position()) / 1000.0
	var danger := mc.get_danger()
	var cap := brain.captain
	var escorted := ContractBoard.escort_for_mining(mc) != null
	var lone := cap != null and cap.has_trait(CaptainTraits.LONE_WOLF)
	if escorted and not lone:
		danger = maxi(danger - ESCORT_DANGER_RELIEF, 1)
	var fair := ContractBoard.mining_rules.default_reward(mc.belt)
	var pay := prof.pay_weight * float(mc.reward) / PAY_SCALE * (cap.pay_scale() if cap else 1.0)
	var dist := prof.distance_weight * km / DIST_SCALE_KM
	var dang := prof.danger_weight * pow(float(maxi(danger - 1, 0)), 2.0) / 4.0 * (cap.danger_scale() if cap else 1.0)
	var loyal := cap.loyalty_bonus() if cap else 0.0
	var traits := 0.0
	var sulking := false
	if cap:
		if cap.has_trait(CaptainTraits.CRYSTAL_HOUND) and mc.ore_type == AsteroidBelt.OreType.CRYSTAL:
			traits += CRYSTAL_HOUND_BONUS
		if lone and not escorted:
			traits += LONE_WOLF_BONUS
		if cap.has_trait(CaptainTraits.UNION_REP) and mc.reward < fair:
			traits -= UNION_SULK
			sulking = true
	e.utility = pay - dist - dang + loyal + traits + brain.rng.randf_range(-prof.noise, prof.noise)
	e.terms = {"pay": pay, "distance": dist, "danger": dang, "km": km, "fair": fair, "escorted": escorted, "traits": traits}
	if Economy.credits < mc.reward:
		e.reason = CANT_PAY
	elif prof.max_trip_km > 0.0 and km > prof.max_trip_km:
		e.reason = TOO_FAR
	elif prof.premium_danger > 0 and danger >= prof.premium_danger and float(mc.reward) < float(fair) * prof.premium_factor:
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

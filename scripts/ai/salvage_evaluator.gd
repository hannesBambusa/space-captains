class_name SalvageEvaluator
extends RoleEvaluator
## Salvager scoring for salvage: free salvage on every scrap field
## (SalvageContract.free_for, added to the list in [method pick]) and the
## player's salvage contracts, which pay a bonus on top of the yard.
##   pay      = pay_weight * Greed * (yard pay + bonus) / PAY_SCALE; the yard
##              pays SalvageContract.FAIR_REWARD per load, half while it owes
##              money (SalvageYard.expected_load_pay)
##   distance = distance_weight * one-way travel time from the yard (warp
##              hop plus flight) / TRAVEL_SCALE_S
##   danger   = danger_weight * Nerve * (danger - 1)^2 / 4 (dens nearby, the
##              belt the field lies in: SalvageContract.danger_at)
##   size     = SIZE_WEIGHT * log2(scrap / SIZE_REF), clamped: big fields
##              are worth the trip, scraps are not
##   crowd    = CROWD_WEIGHT per salvager already on the field
##   utility  = pay - distance - danger + size - crowd + Loyalty bonus + noise
## Hard rules as for miners: the station must afford a posted bonus, max trip
## length, and the premium rule for dangerous places (fair pay:
## SalvageContract.FAIR_REWARD, compared with yard pay plus bonus). Traits:
## Lone Wolf +0.1, Union Rep sulks at below-fair pay.

const PAY_SCALE := 40.0
const SIZE_WEIGHT := 0.15
const SIZE_REF := 40.0
const CROWD_WEIGHT := 0.12


func handles(type: Contract.Type) -> bool:
	return type == Contract.Type.SALVAGE


## Adds the free salvage of every scrap field to the board's contracts.
func pick(brain: CaptainBrain, contracts: Array[Contract]) -> Evaluation:
	var all := contracts.duplicate()
	if brain.ship and brain.ship.is_inside_tree():
		all.append_array(SalvageContract.free_contracts(brain.ship.get_tree()))
	return super.pick(brain, all)


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
	var yard := SalvageYard.of(brain.ship)
	var yard_pay := yard.expected_load_pay() if yard else 0.0
	var total := float(sc.reward) + yard_pay
	var pay := prof.pay_weight * total / PAY_SCALE * (cap.pay_scale() if cap else 1.0)
	var trip := travel_of(brain, km)
	var dist := prof.distance_weight * (trip.x + trip.y) / TRAVEL_SCALE_S
	var dang := prof.danger_weight * pow(float(maxi(danger - 1, 0)), 2.0) / 4.0 * (cap.danger_scale() if cap else 1.0)
	var size := clampf(SIZE_WEIGHT * log(maxf(float(sc.field.amount), 1.0) / SIZE_REF) / log(2.0), -0.25, 0.45)
	var crowd := CROWD_WEIGHT * float(SalvageContract.workers_on(sc.field))
	var loyal := cap.loyalty_bonus() if cap else 0.0
	var sulking := false
	if cap:
		if cap.has_trait(CaptainTraits.LONE_WOLF):
			loyal += MinerEvaluator.LONE_WOLF_BONUS
		if cap.has_trait(CaptainTraits.UNION_REP) and total < float(fair):
			loyal -= MinerEvaluator.UNION_SULK
			sulking = true
	var noise := brain.rng.randf_range(-prof.noise, prof.noise)
	e.utility = pay - dist - dang + size - crowd + loyal + noise
	e.terms = {"pay": pay, "distance": dist, "danger": dang, "size": size, "crowd": crowd, "km": km, "fair": fair, "reward": roundi(total), "bonus": sc.reward,
			"scrap": sc.field.amount,
			"danger_level": danger, "base_danger": danger, "loyal": loyal, "noise": noise, "warp_s": trip.x, "flight_s": trip.y, "pay_div": PAY_SCALE, "time_div": TRAVEL_SCALE_S}
	if sc.reward > 0 and Economy.credits < sc.reward:
		e.reason = CANT_PAY
	elif too_long(prof, trip):
		e.reason = TOO_FAR
	elif prof.premium_danger > 0 and danger >= prof.premium_danger and total < float(fair) * prof.premium_factor:
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

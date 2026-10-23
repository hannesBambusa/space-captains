class_name MercenaryEvaluator
extends RoleEvaluator
## Mercenary scoring for bounty and escort contracts.
##   pay      = pay_weight * Greed * reward / PAY_SCALE (bounty or escort scale)
##   distance = distance_weight * one-way km from the home outpost / DIST_SCALE_KM
##   danger   = danger_weight * Nerve * (danger - 1)^2 / 4 (escorts: half,
##              they fight beside the miner, not into the den)
##   utility  = pay - distance - danger + Loyalty bonus + noise
## Hard rules: the station must be able to pay one reward, and the ship must
## be repaired (hull above [constant MIN_HULL]).
## Traits: Grudge weighs bounties on scavengers [constant GRUDGE_PAY] times;
## Lone Wolf scores escort jobs -[constant LONE_WOLF_ESCORT] and bounties
## +[constant LONE_WOLF_BONUS].

const BOUNTY_PAY_SCALE := 120.0
const ESCORT_PAY_SCALE := 40.0
const DIST_SCALE_KM := 6.0
const ESCORT_DANGER_SHARE := 0.5
const MIN_HULL := 0.7
const NEEDS_REPAIRS := "Needs repairs first"
const NO_MINER := "No miner to escort"
const GRUDGE_PAY := 1.4
const LONE_WOLF_ESCORT := 0.25
const LONE_WOLF_BONUS := 0.1


func handles(type: Contract.Type) -> bool:
	return type == Contract.Type.BOUNTY or type == Contract.Type.ESCORT


func evaluate(brain: CaptainBrain, contract: Contract) -> Evaluation:
	if not (contract is BountyContract or contract is EscortContract):
		return null
	var prof := brain.profile
	var cap := brain.captain
	var e := Evaluation.new()
	e.contract = contract
	var site := contract.get_site_position(brain.home_position())
	var km := Combat.flat_distance(site, brain.home_position()) / 1000.0
	var danger := contract.get_danger()
	var escort := contract is EscortContract
	var scale := ESCORT_PAY_SCALE if escort else BOUNTY_PAY_SCALE
	var pay := prof.pay_weight * float(contract.reward) / scale * (cap.pay_scale() if cap else 1.0)
	var dist := prof.distance_weight * km / DIST_SCALE_KM
	var dang := prof.danger_weight * pow(float(maxi(danger - 1, 0)), 2.0) / 4.0 * (cap.danger_scale() if cap else 1.0)
	if escort:
		dang *= ESCORT_DANGER_SHARE
	var loyal := cap.loyalty_bonus() if cap else 0.0
	if cap and not escort and cap.has_trait(CaptainTraits.GRUDGE):
		pay *= GRUDGE_PAY
	if cap and cap.has_trait(CaptainTraits.LONE_WOLF):
		loyal += -LONE_WOLF_ESCORT if escort else LONE_WOLF_BONUS
	e.utility = pay - dist - dang + loyal + brain.rng.randf_range(-prof.noise, prof.noise)
	e.terms = {"pay": pay, "distance": dist, "danger": dang, "km": km}
	if Economy.credits < contract.reward:
		e.reason = CANT_PAY
	elif brain.ship.hull_fraction() < MIN_HULL:
		e.reason = NEEDS_REPAIRS
	elif escort and (contract as EscortContract).ward != null and (contract as EscortContract).pick_ward() == null:
		e.reason = NO_MINER
	elif prof.max_trip_km > 0.0 and km > prof.max_trip_km:
		e.reason = TOO_FAR
	elif e.utility < prof.accept_threshold:
		if dang >= dist and dang > pay * 0.25:
			e.reason = TOO_DANGEROUS
		elif dist > pay * 0.25:
			e.reason = TOO_FAR
		else:
			e.reason = NOT_WORTH_IT
	else:
		e.accept = true
	return e

class_name MercenaryEvaluator
extends RoleEvaluator
## Mercenary scoring for bounty and escort contracts.
##   pay      = pay_weight * Greed * reward / PAY_SCALE (bounty or escort scale)
##   distance = distance_weight * one-way km from the home outpost / DIST_SCALE_KM
##   danger   = danger_weight * Nerve * (danger - 1)^2 / 4 (escorts: half,
##              they fight beside the miner, not into the den)
##   utility  = pay - distance - danger + Loyalty bonus + noise
## Hard rules: the station must be able to pay one reward, and the ship must
## be repaired (hull above [constant MIN_HULL]) unless the captain cannot pay
## for repairs; then the danger weighs more the lower the hull
## ([constant DAMAGED_DANGER]).
## Traits: Grudge weighs bounties on scavengers [constant GRUDGE_PAY] times;
## Lone Wolf scores escort jobs -[constant LONE_WOLF_ESCORT] and bounties
## +[constant LONE_WOLF_BONUS].
## Fleets ([MercFleet]): a bounty whose target needs more than
## MercFleet.SOLO_NEED ships like this one is too strong to take alone.
##   lone wolf  daring (Captain.daring: Nerve up, Teamwork down) at least
##              [constant LONE_WOLF_DARING] and the need within
##              1 + [constant LONE_WOLF_REACH] * daring: a roll decides to go
##              alone, the danger weighs [constant LONE_WOLF_DANGER] as much
##              (brave or foolish), they keep the whole bounty
##   call       Teamwork at least [constant CALL_TEAMWORK] (or Grudge against
##              scavengers): pay and danger are scored per head of the fleet
##              wanted; taking it calls the fleet
##   otherwise  refused, "Too strong to take on alone"
## While a fleet forms, the contract is a join offer ([method evaluate_fleet_join]):
## the share and the danger per head, then a yes chance from Teamwork,
## personality ([constant JOIN_PERSONALITY]), the share and the distance to
## the rally point. Grudge against scavengers always says yes. A no is
## remembered by the fleet.

const BOUNTY_PAY_SCALE := 120.0
const ESCORT_PAY_SCALE := 40.0
const DIST_SCALE_KM := 6.0
const ESCORT_DANGER_SHARE := 0.5
const MIN_HULL := 0.7
## Danger multiplier added per missing hull share when flying damaged.
const DAMAGED_DANGER := 2.0
const NEEDS_REPAIRS := "Needs repairs first"
const NO_MINER := "No miner to escort"
const GRUDGE_PAY := 1.4
const LONE_WOLF_ESCORT := 0.25
const LONE_WOLF_BONUS := 0.1
const TOO_STRONG := "Too strong to take on alone"
const DECLINED := "Rather not fly in that fleet"
const FLEET_FULL := "That fleet is full"
## Daring needed to take a fight above their weight alone, and how far above.
const LONE_WOLF_DARING := 0.72
const LONE_WOLF_REACH := 3.4
## Solo chance per evaluation, from [constant LONE_WOLF_DARING] to full daring.
const LONE_WOLF_CHANCE := Vector2(0.3, 0.9)
const LONE_WOLF_DANGER := 0.6
## Teamwork needed to call a fleet.
const CALL_TEAMWORK := 3
## Join chance: base plus per Teamwork point above 1, by personality
## (Bold, Cautious, Greedy, Lazy).
const JOIN_BASE := 0.1
const JOIN_PER_TEAMWORK := 0.08
const JOIN_PERSONALITY: Array[float] = [0.0, 0.15, -0.1, -0.05]
## Join chance lost per km from the rally point.
const JOIN_PER_KM := 0.04


func handles(type: Contract.Type) -> bool:
	return type == Contract.Type.BOUNTY or type == Contract.Type.ESCORT


func evaluate(brain: CaptainBrain, contract: Contract) -> Evaluation:
	if not (contract is BountyContract or contract is EscortContract):
		return null
	var prof := brain.profile
	var cap := brain.captain
	var bounty := contract as BountyContract
	if bounty and bounty.fleet and bounty.fleet.state == MercFleet.State.FORMING:
		return evaluate_fleet_join(brain, bounty.fleet)
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
	dang *= 1.0 + DAMAGED_DANGER * (1.0 - brain.ship.hull_fraction())
	var loyal := cap.loyalty_bonus() if cap else 0.0
	if cap and not escort and cap.has_trait(CaptainTraits.GRUDGE):
		pay *= GRUDGE_PAY
	if cap and cap.has_trait(CaptainTraits.LONE_WOLF):
		loyal += -LONE_WOLF_ESCORT if escort else LONE_WOLF_BONUS
	e.terms = {"pay": pay, "distance": dist, "danger": dang, "km": km}
	var too_strong := false
	if bounty and cap:
		var need := MercFleet.need_for(bounty, brain.ship)
		e.terms["need"] = need
		if need > MercFleet.SOLO_NEED:
			var daring := cap.daring()
			var grudge := cap.has_trait(CaptainTraits.GRUDGE) and _scavenger_target(bounty)
			var solo_chance := lerpf(LONE_WOLF_CHANCE.x, LONE_WOLF_CHANCE.y, clampf((daring - LONE_WOLF_DARING) / (1.0 - LONE_WOLF_DARING), 0.0, 1.0))
			if daring >= LONE_WOLF_DARING and need <= 1.0 + LONE_WOLF_REACH * daring and brain.rng.randf() < solo_chance:
				dang *= LONE_WOLF_DANGER
				e.terms["solo_brave"] = true
			elif cap.effective_teamwork() >= CALL_TEAMWORK or grudge:
				var size := MercFleet.size_for(need, bounty)
				pay /= float(size)
				dang /= float(size)
				e.terms["call_fleet"] = size
			else:
				too_strong = true
			e.terms["pay"] = pay
			e.terms["danger"] = dang
	e.utility = pay - dist - dang + loyal + brain.rng.randf_range(-prof.noise, prof.noise)
	if too_strong:
		e.reason = TOO_STRONG
	elif Economy.credits < contract.reward:
		e.reason = CANT_PAY
	elif brain.ship.hull_fraction() < MIN_HULL and RepairBay.can_afford(brain.ship):
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


## Whether [param brain]'s captain joins [param fleet]: the share and the
## danger per head must be worth it, then a roll on the join chance.
func evaluate_fleet_join(brain: CaptainBrain, fleet: MercFleet) -> Evaluation:
	var prof := brain.profile
	var cap := brain.captain
	var bounty := fleet.contract
	var e := Evaluation.new()
	e.contract = bounty
	if fleet.declined.has(brain.ship.get_instance_id()):
		e.reason = DECLINED
		return e
	if not fleet.is_recruiting():
		e.reason = FLEET_FULL
		return e
	var heads := float(fleet.members.size() + 1)
	var km := Combat.flat_distance(brain.ship.global_position, fleet.rally_point()) / 1000.0
	var pay := prof.pay_weight * fleet.share_for_next() / BOUNTY_PAY_SCALE * (cap.pay_scale() if cap else 1.0)
	var dist := prof.distance_weight * km / DIST_SCALE_KM
	var dang := prof.danger_weight * pow(float(maxi(bounty.get_danger() - 1, 0)), 2.0) / 4.0 * (cap.danger_scale() if cap else 1.0) / heads
	var grudge := cap != null and cap.has_trait(CaptainTraits.GRUDGE) and _scavenger_target(bounty)
	if grudge:
		pay *= GRUDGE_PAY
	e.utility = pay - dist - dang + (cap.loyalty_bonus() if cap else 0.0) + brain.rng.randf_range(-prof.noise, prof.noise)
	var chance := JOIN_BASE + JOIN_PER_TEAMWORK * float((cap.effective_teamwork() if cap else 5) - 1)
	if cap:
		chance += JOIN_PERSONALITY[cap.personality]
	chance += clampf((pay - 1.0) * 0.05, -0.2, 0.2) - JOIN_PER_KM * km
	e.terms = {"pay": pay, "distance": dist, "danger": dang, "km": km, "join_chance": chance, "join_fleet": true}
	if Economy.credits < bounty.reward:
		e.reason = CANT_PAY
	elif brain.ship.hull_fraction() < MIN_HULL and RepairBay.can_afford(brain.ship):
		e.reason = NEEDS_REPAIRS
	elif grudge:
		e.accept = true
	elif e.utility < prof.accept_threshold:
		e.reason = TOO_DANGEROUS if dang > pay * 0.25 else NOT_WORTH_IT
	elif brain.rng.randf() >= chance:
		e.reason = DECLINED
		fleet.declined[brain.ship.get_instance_id()] = true
	else:
		e.accept = true
	return e


static func _scavenger_target(bounty: BountyContract) -> bool:
	return bounty.target is ScavengerShip or bounty.target is ScavengerDen

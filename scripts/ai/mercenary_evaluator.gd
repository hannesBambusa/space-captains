class_name MercenaryEvaluator
extends RoleEvaluator
## Mercenary scoring for bounty and escort contracts.
##   pay      = pay_weight * Greed * reward / PAY_SCALE (bounty or escort scale)
##   distance = distance_weight * one-way travel time from the home outpost
##              (warp hop plus flight) / MERC_TRAVEL_SCALE_S. Distance alone
##              never refuses a job inside the system: a low score is "not
##              worth it" (or too dangerous), never "too far"
##   danger   = danger_weight * Nerve * (danger - 1)^2 / 4 (escorts: half,
##              they fight beside the miner, not into the den)
##   utility  = pay - distance - danger + Loyalty bonus + noise
## Hard rules: an escort contract must not be paused (the station can pay
## one trip; a bounty's reward is reserved when posted), and the ship must
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
##              scavengers) and the free mercs together strong enough
##              (MercFleet.assess: combined power, not each ship alone):
##              pay and danger are scored per head of the fleet wanted;
##              taking it calls the fleet. Too few free mercs: refused,
##              [constant FLEET_SHORT] ("Needs about 5 mercenaries, 3
##              available" in the log); a full fleet of mercs like the hired
##              ones would still be too weak: [constant FLEET_TOO_WEAK]
##   otherwise  refused, "Too strong to take on alone"
## While a fleet forms, the contract is a join offer ([method evaluate_fleet_join]):
## the share and the danger per head, then a yes chance from Teamwork,
## personality ([constant JOIN_PERSONALITY]), the share and the distance to
## the rally point. Grudge against scavengers always says yes. A no is
## remembered by the fleet.

const BOUNTY_PAY_SCALE := 120.0
const ESCORT_PAY_SCALE := 40.0
const MERC_TRAVEL_SCALE_S := 36.0
const ESCORT_DANGER_SHARE := 0.5
const MIN_HULL := 0.7
## Danger multiplier added per missing hull share when flying damaged.
const DAMAGED_DANGER := 2.0
const NEEDS_REPAIRS := "Needs repairs first"
const NO_MINER := "No miner to escort"
const GRUDGE_PAY := 1.4
const LONE_WOLF_ESCORT := 0.25
const TOO_STRONG := "Too strong to take on alone"
const FLEET_SHORT := "Not enough mercenaries free for a fleet"
const FLEET_TOO_WEAK := "Too dangerous for the current fleet"
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
## Join danger scale by how far the fleet with this ship falls short of the
## need (need / power), clamped to this range.
const JOIN_COVER := Vector2(0.6, 1.5)
## Join chance added when this ship would make the fleet strong enough.
const JOIN_COMPLETES := 0.3


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
	var km := SpaceNav.flat_distance(site, brain.home_position()) / 1000.0
	var danger := contract.get_danger()
	var escort := contract is EscortContract
	var scale := ESCORT_PAY_SCALE if escort else BOUNTY_PAY_SCALE
	var pay := pay_term(brain, float(contract.reward), scale)
	var trip := travel_of(brain, km)
	var dist := distance_term(brain, trip, MERC_TRAVEL_SCALE_S)
	var dang := danger_term(brain, danger)
	if escort:
		dang *= ESCORT_DANGER_SHARE
	dang *= 1.0 + DAMAGED_DANGER * (1.0 - brain.ship.hull_fraction())
	var loyal := cap.loyalty_bonus() if cap else 0.0
	if cap and not escort and cap.has_trait(CaptainTraits.GRUDGE):
		pay *= GRUDGE_PAY
	if cap and cap.has_trait(CaptainTraits.LONE_WOLF):
		loyal += -LONE_WOLF_ESCORT if escort else LONE_WOLF_BONUS
	e.terms = {"pay": pay, "distance": dist, "danger": dang, "km": km, "reward": contract.reward, "danger_level": danger, "base_danger": danger,
			"warp_s": trip.x, "flight_s": trip.y, "pay_div": scale, "time_div": MERC_TRAVEL_SCALE_S}
	var too_strong := false
	var fleet_block := ""
	if bounty and cap:
		var need := MercFleet.need_for(bounty, brain.ship)
		e.terms["need"] = need
		if need > MercFleet.SOLO_NEED:
			var daring := cap.daring()
			var grudge := cap.has_trait(CaptainTraits.GRUDGE) and _scavenger_target(bounty)
			var solo_chance := lerpf(LONE_WOLF_CHANCE.x, LONE_WOLF_CHANCE.y, clampf((daring - LONE_WOLF_DARING) / (1.0 - LONE_WOLF_DARING), 0.0, 1.0))
			e.terms["daring"] = daring
			e.terms["solo_chance"] = solo_chance if daring >= LONE_WOLF_DARING else 0.0
			e.terms["grudge"] = grudge
			if daring >= LONE_WOLF_DARING and need <= 1.0 + LONE_WOLF_REACH * daring and brain.rng.randf() < solo_chance:
				dang *= LONE_WOLF_DANGER
				e.terms["solo_brave"] = true
			elif cap.effective_teamwork() >= CALL_TEAMWORK or grudge:
				var a := MercFleet.assess(bounty, brain.ship)
				var size := int(a["wanted"])
				pay /= float(size)
				dang /= float(size)
				e.terms["fleet_text"] = String(a["text"])
				e.terms["fleet_power"] = float(a["power"])
				e.terms["fleet_goal"] = float(a["goal"])
				e.terms["fleet_available"] = int(a["available"])
				e.terms["fleet_estimate"] = int(a["estimate"])
				if bool(a["too_strong"]):
					fleet_block = FLEET_TOO_WEAK
				elif not bool(a["enough"]):
					fleet_block = FLEET_SHORT
				else:
					e.terms["call_fleet"] = size
			else:
				too_strong = true
			e.terms["pay"] = pay
			e.terms["danger"] = dang
	var noise := noise_of(brain)
	e.utility = pay - dist - dang + loyal + noise
	e.terms["loyal"] = loyal
	e.terms["noise"] = noise
	if too_strong:
		e.reason = TOO_STRONG
	elif not fleet_block.is_empty():
		e.reason = fleet_block
	elif contract.is_paused():
		e.reason = CANT_PAY
	elif RepairBay.should_repair(brain.ship, MIN_HULL):
		e.reason = NEEDS_REPAIRS
	elif escort and (contract as EscortContract).ward != null and (contract as EscortContract).pick_ward() == null:
		e.reason = NO_MINER
	elif e.utility < prof.accept_threshold:
		e.reason = TOO_DANGEROUS if dang >= dist and dang > pay * 0.25 else NOT_WORTH_IT
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
	if fleet.has_declined(brain.ship):
		e.reason = DECLINED
		return e
	if not fleet.is_recruiting():
		e.reason = FLEET_FULL
		return e
	var heads := float(fleet.members.size() + 1)
	var km := SpaceNav.flat_distance(brain.ship.global_position, fleet.rally_point()) / 1000.0
	var pay := pay_term(brain, fleet.share_for_next(), BOUNTY_PAY_SCALE)
	var trip := travel_of(brain, km)
	var dist := distance_term(brain, trip, MERC_TRAVEL_SCALE_S)
	var dang := danger_term(brain, bounty.get_danger()) / heads
	# Combined power: a fleet that covers the need (with this ship) weighs less.
	var with_me := fleet.power() + MercFleet.power_of(brain.ship)
	var cover := clampf(MercFleet.target_need(bounty.target) * MercFleet.FLEET_POWER_SHARE / maxf(with_me, 0.1), JOIN_COVER.x, JOIN_COVER.y)
	dang *= cover
	var grudge := cap != null and cap.has_trait(CaptainTraits.GRUDGE) and _scavenger_target(bounty)
	if grudge:
		pay *= GRUDGE_PAY
	var loyal := cap.loyalty_bonus() if cap else 0.0
	var noise := noise_of(brain)
	e.utility = pay - dist - dang + loyal + noise
	var chance := JOIN_BASE + JOIN_PER_TEAMWORK * float((cap.effective_teamwork() if cap else 5) - 1)
	if cap:
		chance += JOIN_PERSONALITY[cap.personality]
	chance += clampf((pay - 1.0) * 0.05, -0.2, 0.2) - JOIN_PER_KM * km
	# This ship would make the fleet strong enough to set out.
	var completes := not fleet.strong_enough() and with_me >= MercFleet.target_need(bounty.target) * MercFleet.FLEET_POWER_SHARE
	if completes:
		chance += JOIN_COMPLETES
	e.terms = {"pay": pay, "distance": dist, "danger": dang, "km": km, "join_chance": chance, "join_fleet": true, "loyal": loyal, "noise": noise,
			"share": fleet.share_for_next(), "heads": heads, "reward": bounty.reward, "danger_level": bounty.get_danger(), "base_danger": bounty.get_danger(),
			"grudge": grudge, "leader": fleet.leader_name, "cover": cover, "completes": completes, "warp_s": trip.x, "flight_s": trip.y, "pay_div": BOUNTY_PAY_SCALE, "time_div": MERC_TRAVEL_SCALE_S}
	if RepairBay.should_repair(brain.ship, MIN_HULL):
		e.reason = NEEDS_REPAIRS
	elif grudge:
		e.accept = true
	elif e.utility < prof.accept_threshold:
		e.reason = TOO_DANGEROUS if dang > pay * 0.25 else NOT_WORTH_IT
	elif brain.rng.randf() >= chance:
		e.reason = DECLINED
		fleet.declined[brain.ship.get_instance_id()] = SimClock.time
	else:
		e.accept = true
	return e


static func _scavenger_target(bounty: BountyContract) -> bool:
	return bounty.target is ScavengerShip or bounty.target is ScavengerDen

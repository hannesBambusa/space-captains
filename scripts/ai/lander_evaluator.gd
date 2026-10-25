class_name LanderEvaluator
extends RoleEvaluator
## Lander scoring for planet raid contracts (PlanetRaidContract).
##   pay      = pay_weight * Greed * reward / PAY_SCALE
##   distance = distance_weight * one-way travel time to the planet (warp
##              hop plus flight) / TRAVEL_SCALE_S
##   danger   = danger_weight * Nerve * (danger - 1)^2 / 4, danger after
##              gear relief (MinerEvaluator.gear_relief)
##   rich     = RICH_WEIGHT * log2(load value / RICH_REF), clamped, times
##              the personality's taste for a big haul (Greedy x2, Bold
##              x1.2, Lazy x0.8, Cautious x0.5) and Greed: a rich world is
##              worth a longer, riskier trip to some pilots
##   crowd    = CROWD_WEIGHT per lander already on that planet
##   utility  = pay - distance - danger + rich - crowd + Loyalty + noise
## Hard rules: a world claimed by a faction (PlanetClaims, a garrison in
## orbit) is refused with that reason before anything else; then as for miners: the station must afford one load, the trip
## limit, and the premium rule from the profile's premium danger (fair pay:
## PlanetRaidRules.fair_reward). Traits: Lone Wolf +0.1, Union Rep sulks at
## below-fair pay. The load value is the yield at the Factory's price now.

const PAY_SCALE := 140.0
const RICH_WEIGHT := 0.3
const RICH_REF := 300.0
const CROWD_WEIGHT := 0.1
## Taste for a rich haul by personality (Bold, Cautious, Greedy, Lazy).
const RICH_TASTE: PackedFloat32Array = [1.2, 0.5, 2.0, 0.8]
## Price per unit without a Factory (Economy.Ore order), credits.
const FALLBACK_PRICE: PackedFloat32Array = [6.0, 11.0, 16.0, 13.0, 6.0, 22.0, 8.0, 7.0]


func handles(type: Contract.Type) -> bool:
	return type == Contract.Type.PLANET_RAID


## Value of one load from [param rc] at the Factory's price now, credits.
static func load_value(rc: PlanetRaidContract, ship: Ship) -> float:
	if rc == null or not is_instance_valid(rc.planet):
		return 0.0
	var units := float(PlanetRaidContract.rules().base_yield(rc.planet.def)) * (ship.stats.cargo if ship and ship.stats else 1.0)
	var f := Factory.find(ship.get_tree()) if ship and ship.is_inside_tree() else null
	var price := f.market.willing_price(rc.loot) if f else FALLBACK_PRICE[clampi(rc.loot, 0, FALLBACK_PRICE.size() - 1)]
	return units * price


func evaluate(brain: CaptainBrain, contract: Contract) -> Evaluation:
	var rc := contract as PlanetRaidContract
	if rc == null or not is_instance_valid(rc.planet) or not rc.planet.is_inside_tree():
		return null
	var prof := brain.profile
	var cap := brain.captain
	var e := Evaluation.new()
	e.contract = contract
	var km := SpaceNav.flat_distance(rc.planet.global_position, brain.home_position()) / 1000.0
	var danger := rc.get_danger()
	var base_danger := danger
	var gear := MinerEvaluator.gear_relief(brain.ship)
	danger = maxi(danger - gear, 1)
	var fair := rc.fair_reward()
	var pay := pay_term(brain, float(rc.reward), PAY_SCALE)
	var trip := travel_of(brain, km)
	var dist := distance_term(brain, trip)
	var dang := danger_term(brain, danger)
	var value := load_value(rc, brain.ship)
	var taste := RICH_TASTE[clampi(int(prof.personality), 0, RICH_TASTE.size() - 1)] * (cap.pay_scale() if cap else 1.0)
	var rich := clampf(RICH_WEIGHT * log(maxf(value, 1.0) / RICH_REF) / log(2.0), -0.3, 0.5) * taste
	var crowd := CROWD_WEIGHT * float(rc.takers.size())
	var loyal := cap.loyalty_bonus() if cap else 0.0
	var sulking := sulks(cap, rc.reward, fair)
	var traits := trait_bonus(cap, 0.0, true, sulking)
	var noise := noise_of(brain)
	e.utility = pay - dist - dang + rich - crowd + loyal + traits + noise
	var units := roundi(float(PlanetRaidContract.rules().base_yield(rc.planet.def)) * (brain.ship.stats.cargo if brain.ship.stats else 1.0))
	e.terms = {"pay": pay, "distance": dist, "danger": dang, "rich": rich, "taste": taste, "loot_value": value, "crowd": crowd, "km": km, "fair": fair,
			"reward": rc.reward, "danger_level": danger, "base_danger": base_danger, "gear": gear, "loyal": loyal, "traits": traits, "noise": noise,
			"units": units, "loot_name": Economy.ore_name(rc.loot), "landers": rc.takers.size(),
			"warp_s": trip.x, "flight_s": trip.y, "pay_div": PAY_SCALE, "time_div": TRAVEL_SCALE_S}
	var claim := PlanetClaims.claim_reason(rc.planet)
	if not claim.is_empty():
		e.reason = claim
		e.terms["claim_why"] = "Its garrison and patrols guard the planet; a bounty on the garrison breaks the claim"
	else:
		judge(e, prof, danger, rc.reward, fair, sulking)
	return e

class_name MinerEvaluator
extends RoleEvaluator
## Miner scoring for mining contracts.
##   pay      = pay_weight * reward / PAY_SCALE
##   distance = distance_weight * one-way travel time from the home outpost
##              (warp hop plus flight, RoleEvaluator.travel_of) / TRAVEL_SCALE_S
##   danger   = danger_weight * (danger - 1)^2 / 4
##   utility  = pay - distance - danger + noise(+-profile.noise)
## Hard rules before the threshold: the station must afford one load, and
## from premium_danger up the reward must be premium_factor times the fair
## reward (MiningRules.default_reward). No distance limit: a far cluster only
## scores lower (refused as "not worth the trip" when that sinks it).
## Attributes: Greed scales the pay term, Nerve the danger term, Loyalty adds
## a small bonus. An escorted mining contract (linked EscortContract) counts
## as [constant ESCORT_DANGER_RELIEF] danger levels safer. Well-equipped
## ships feel safer too: every [constant GEAR_TIERS_PER_LEVEL] module tiers in
## the defense and engine slots count one danger level less (at most
## [constant GEAR_MAX_RELIEF]), so Mk II/III gear from the Factory opens the
## dangerous belts.
## Escort queue: miners on an escorted contract wait in the berth until an
## escort joins them, and each escort flies with one miner at a time. So a
## miner refuses an escorted contract ([constant ESCORT_QUEUE]) while as
## many miners already wait for an escort on it as mercenaries have taken
## the escort contract (at least one waits for the first): a well-paid
## escorted job no longer pulls every miner into the berths while the
## other work stops.
## Traits (see CaptainTraits): Crystal Hound +[constant CRYSTAL_HOUND_BONUS] on
## crystal belts; Lone Wolf ignores escort cover and scores solo work
## +[constant LONE_WOLF_BONUS]; Union Rep scores below-fair pay
## -[constant UNION_SULK] and says so.

const PAY_SCALE := 50.0
const ESCORT_DANGER_RELIEF := 2
const CRYSTAL_HOUND_BONUS := 0.3
const GEAR_TIERS_PER_LEVEL := 3
const GEAR_MAX_RELIEF := 2
const ESCORT_QUEUE := "Too many waiting for an escort"


## Danger levels a ship's defense and engine modules take off.
static func gear_relief(ship: Ship) -> int:
	if ship == null or ship.loadout == null:
		return 0
	var tiers := 0
	for slot: ShipModule.Slot in [ShipModule.Slot.DEFENSE, ShipModule.Slot.ENGINE]:
		var m := ship.loadout.get_module(slot)
		if m:
			tiers += m.tier
	return mini(floori(float(tiers) / GEAR_TIERS_PER_LEVEL), GEAR_MAX_RELIEF)


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
	var base_danger := danger
	var cap := brain.captain
	var escorted := ContractBoard.escort_for_mining(mc) != null
	var lone := cap != null and cap.has_trait(CaptainTraits.LONE_WOLF)
	if escorted and not lone:
		danger = maxi(danger - ESCORT_DANGER_RELIEF, 1)
	var gear := gear_relief(brain.ship)
	danger = maxi(danger - gear, 1)
	var fair := ContractBoard.mining_rules.default_reward(mc.belt)
	var pay := pay_term(brain, float(mc.reward), PAY_SCALE)
	var trip := travel_of(brain, km)
	var dist := distance_term(brain, trip)
	var dang := danger_term(brain, danger)
	var loyal := cap.loyalty_bonus() if cap else 0.0
	var hound := cap != null and cap.has_trait(CaptainTraits.CRYSTAL_HOUND) and mc.ore_type == AsteroidBelt.OreType.CRYSTAL
	var sulking := sulks(cap, mc.reward, fair)
	var traits := trait_bonus(cap, CRYSTAL_HOUND_BONUS if hound else 0.0, not escorted, sulking)
	var noise := noise_of(brain)
	e.utility = pay - dist - dang + loyal + traits + noise
	e.terms = {"pay": pay, "distance": dist, "danger": dang, "km": km, "fair": fair, "escorted": escorted and not lone, "traits": traits, "gear": gear,
			"reward": mc.reward, "danger_level": danger, "base_danger": base_danger, "loyal": loyal, "noise": noise,
			"warp_s": trip.x, "flight_s": trip.y, "pay_div": PAY_SCALE, "time_div": TRAVEL_SCALE_S}
	judge(e, prof, danger, mc.reward, fair, sulking)
	if e.accept and escorted:
		var ec := ContractBoard.escort_for_mining(mc)
		var waiting := waiting_for_escort(mc, brain.ship)
		var room := maxi(ec.takers.size(), 1)
		if waiting >= room:
			e.accept = false
			e.reason = ESCORT_QUEUE
			e.terms["why"] = "%d miner%s already wait%s for an escort on %s, %d mercenar%s on the escort contract" % [waiting, "" if waiting == 1 else "s",
					"s" if waiting == 1 else "", mc.get_target_name(), ec.takers.size(), "y" if ec.takers.size() == 1 else "ies"]
	return e


## Miners on [param mc] (other than [param except]) waiting for an escort.
static func waiting_for_escort(mc: MiningContract, except: Ship = null) -> int:
	var n := 0
	for s in mc.takers:
		if not is_instance_valid(s):
			continue
		var sh := s as Ship
		if sh and sh != except and not sh.dead and sh.brain and sh.brain.state == CaptainBrain.State.WAITING_ESCORT:
			n += 1
	return n

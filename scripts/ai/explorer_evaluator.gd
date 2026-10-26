class_name ExplorerEvaluator
extends RoleEvaluator
## Explorer scoring for explore contracts (ExploreContract, P3).
##   pay      = pay_weight * Greed * reward / PAY_SCALE
##   distance = distance_weight * trip time / TIME_SCALE_S: the gate legs
##              there and back (JUMP_TIME_S per jump each way) plus the
##              survey (SURVEY_TIME_S)
##   danger   = danger_weight * Nerve * (danger - 1)^2 / 4, the system's
##              danger when known, else the guess from its depth (depth + 1,
##              Bold pilots take it at the depth), less gear relief
##   unknown  = Bold: UNKNOWN_BOLD per jump into an unknown system (they
##              like the deep and the uncharted)
##   lazy     = Lazy: LAZY_JUMP per jump past the first (short routes only)
##   utility  = pay - distance - danger + unknown - lazy + Loyalty + noise
## Hard rules first: Cautious pilots refuse a known danger of
## CAUTIOUS_MAX_DANGER or more, and unknown systems more than one jump out;
## then RoleEvaluator.judge (the premium rule, the threshold and its
## reason). Traits: Lone Wolf +0.1, Union Rep sulks at below-fair pay.

const PAY_SCALE := 300.0
const JUMP_TIME_S := 150.0
const SURVEY_TIME_S := 420.0
const TIME_SCALE_S := 900.0
const UNKNOWN_BOLD := 0.15
const LAZY_JUMP := 0.25
const CAUTIOUS_MAX_DANGER := 3

const TOO_DANGEROUS_CAREFUL := "Too dangerous for a careful pilot"
const UNKNOWN_DEEP := "Unknown space more than one jump out"


func handles(type: Contract.Type) -> bool:
	return type == Contract.Type.EXPLORE


func evaluate(brain: CaptainBrain, contract: Contract) -> Evaluation:
	var ec := contract as ExploreContract
	if ec == null or ec.target_system.is_empty():
		return null
	var prof := brain.profile
	var cap := brain.captain
	var p := cap.personality if cap else Captain.Personality.BOLD
	var e := Evaluation.new()
	e.contract = contract
	var jumps := maxi(ec.jumps(), 1)
	var known := ec.is_known()
	var guess := ec.get_danger()
	var danger := guess
	if not known and p == Captain.Personality.BOLD:
		danger = clampi(jumps, 1, 5)
	var gear := MinerEvaluator.gear_relief(brain.ship)
	var base_danger := danger
	danger = maxi(danger - gear, 1)
	var fair := ec.fair_reward()
	var pay := pay_term(brain, float(ec.reward), PAY_SCALE)
	var time_s := JUMP_TIME_S * 2.0 * jumps + SURVEY_TIME_S
	var dist := prof.distance_weight * time_s / TIME_SCALE_S
	var dang := danger_term(brain, danger)
	var unknown := UNKNOWN_BOLD * jumps if not known and p == Captain.Personality.BOLD else 0.0
	var lazy := LAZY_JUMP * (jumps - 1) if p == Captain.Personality.LAZY else 0.0
	var loyal := cap.loyalty_bonus() if cap else 0.0
	var sulking := sulks(cap, ec.reward, fair)
	var traits := trait_bonus(cap, 0.0, true, sulking)
	var noise := noise_of(brain)
	e.utility = pay - dist - dang + unknown - lazy + loyal + traits + noise
	e.terms = {"pay": pay, "distance": dist + lazy, "danger": dang, "unknown": unknown, "lazy": lazy, "km": 0.0, "fair": fair,
			"reward": ec.reward, "danger_level": danger, "base_danger": base_danger, "gear": gear, "loyal": loyal, "traits": traits, "noise": noise,
			"jumps": jumps, "known": known, "trip_s": time_s, "warp_s": 0.0, "flight_s": time_s, "pay_div": PAY_SCALE, "time_div": TIME_SCALE_S}
	if p == Captain.Personality.CAUTIOUS and known and guess >= CAUTIOUS_MAX_DANGER:
		e.reason = TOO_DANGEROUS_CAREFUL
		e.terms["why"] = "%s is danger %d: a Cautious pilot goes nowhere rated %d or more" % [ec.target_name(), guess, CAUTIOUS_MAX_DANGER]
	elif p == Captain.Personality.CAUTIOUS and not known and jumps > 1:
		e.reason = UNKNOWN_DEEP
		e.terms["why"] = "%s is %d jumps out and nobody has charted it: a Cautious pilot only goes one jump into the unknown" % [ec.target_name(), jumps]
	else:
		judge(e, prof, danger, ec.reward, fair, sulking)
	return e

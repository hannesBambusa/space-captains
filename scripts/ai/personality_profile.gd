class_name PersonalityProfile
extends Resource
## How a personality weighs a job. Used by every role evaluator:
## utility = pay - distance cost - danger cost + noise, accepted above
## [member accept_threshold]. See MinerEvaluator for the term scales.

@export var personality: Captain.Personality = Captain.Personality.BOLD

@export_group("Scoring")
## Weight of the reward term.
@export var pay_weight: float = 1.0
## Weight of the one-way distance term.
@export var distance_weight: float = 0.7
## Weight of the danger term.
@export var danger_weight: float = 0.6
## Utility needed to accept.
@export var accept_threshold: float = 0.3
## Uniform random spread added per contract and evaluation.
@export var noise: float = 0.15
## Danger level from which the reward must beat the fair reward by
## [member premium_factor]. 0 = no such rule.
@export_range(0, 5, 1) var premium_danger: int = 0
@export var premium_factor: float = 1.6

@export_group("Pacing")
## Sim seconds between evaluations while docked (min, max).
@export var evaluate_interval: Vector2 = Vector2(3.0, 6.0)
## Rest after unloading, sim seconds (min, max).
@export var rest_time: Vector2 = Vector2(6.0, 10.0)
## Chance per evaluation to take a break instead of working.
@export_range(0.0, 1.0, 0.01) var break_chance: float = 0.0
@export var break_time: Vector2 = Vector2(20.0, 40.0)

@export_group("Threat (stage 2)")
## Threat level (0..1) at which the captain abandons the job and flees.
@export_range(0.0, 1.0, 0.01) var flee_threat: float = 0.5
## Mercenaries break off and go home to repair below this hull fraction.
@export_range(0.0, 1.0, 0.01) var retreat_hull: float = 0.4
## Mercenaries: after a fight, go home to repair (paid) below this hull
## fraction (minus the Nerve offset). Cautious near any damage, Greedy late.
@export_range(0.0, 1.0, 0.01) var repair_hull: float = 0.75
## Mercenaries: chance per idle evaluation to fly a patrol around home.
@export_range(0.0, 1.0, 0.01) var patrol_chance: float = 0.5

@export_group("Attributes")
## Base for Nerve, Greed, Diligence, Piloting, Skill, Loyalty, Teamwork (1..10).
@export var attribute_base: PackedInt32Array = [5, 5, 5, 5, 5, 5, 5]
## Each attribute is rolled base +- this, clamped 1..10.
@export var attribute_spread: int = 2

const PROFILE_PATHS: PackedStringArray = [
	"res://data/ai/personality_bold.tres",
	"res://data/ai/personality_cautious.tres",
	"res://data/ai/personality_greedy.tres",
	"res://data/ai/personality_lazy.tres",
]

static var _cache: Dictionary = {}


static func for_personality(p: Captain.Personality) -> PersonalityProfile:
	if _cache.has(p):
		return _cache[p]
	var prof: PersonalityProfile = null
	var idx := int(p)
	if idx >= 0 and idx < PROFILE_PATHS.size() and ResourceLoader.exists(PROFILE_PATHS[idx]):
		prof = load(PROFILE_PATHS[idx]) as PersonalityProfile
	if prof == null:
		prof = PersonalityProfile.new()
		prof.personality = p
	_cache[p] = prof
	return prof

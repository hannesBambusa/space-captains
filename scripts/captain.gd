class_name Captain
extends Resource
## A hired ship captain (the person; the ship is the hardware). Personality
## picks the PersonalityProfile that CaptainBrain scores contracts with, and
## sets the base of the attributes rolled at hire.
##
## Attributes 1..10 (see [method roll_attributes] and the factor helpers):
##   Nerve      danger weight, flee and retreat thresholds
##   Greed      pay weight, share of earnings spent at the station
##   Diligence  rest time, break chance, patrol eagerness
##   Piloting   speed, turn rate, dodge chance
##   Skill      the specialty: Mining or Salvage (work time) or Gunnery
##              (accuracy, damage)
##   Loyalty    a small bonus for station contracts, defence eagerness
##   Teamwork   how readily they call or join a mercenary fleet ([MercFleet]);
##              low Teamwork with high Nerve makes a lone wolf who takes on
##              bounties above their weight alone
##
## Stage 3: reputation and rank ([Reputation]: rank unlocks module slots and
## tiers, never stats), traits from events ([CaptainTraits], at most 3, some
## fade), the wallet that buys modules and ships, a career history, and the
## stranded state of a captain who ejected and waits for a new ship.
## Rank-ups and trait changes post to the event feed.

signal rank_changed(captain: Captain, rank: int)
signal traits_changed(captain: Captain)

enum Personality { BOLD, CAUTIOUS, GREEDY, LAZY }
enum Specialty { MINING, GUNNERY, SALVAGE }

const FIRST_NAMES: PackedStringArray = [
	"Rook", "Vega", "Juno", "Kade", "Sable", "Orin", "Tamsin", "Ezra", "Nyx", "Calder",
	"Ines", "Mara", "Dax", "Lio", "Sora", "Teague", "Wren", "Yuri", "Zeke", "Anika",
	"Bram", "Cass", "Idris", "Kenji", "Noor", "Pell", "Rhea", "Soren", "Talia", "Vik",
	"Ivo", "Hollis", "Mira", "Jett",
]
const LAST_NAMES: PackedStringArray = [
	"Valdez", "Okafor", "Harrow", "Lindqvist", "Moreau", "Tanaka", "Kovac", "Reyes",
	"Strand", "Achebe", "Voss", "Hale", "Ibarra", "Novak", "Sato", "Brandt", "Qadir",
	"Mercer", "Oyelaran", "Castell", "Dunmore", "Falk", "Halvorsen", "Marsh", "Petrov",
	"Rask", "Kade", "Orlov",
]
const PERSONALITY_NAMES: PackedStringArray = ["Bold", "Cautious", "Greedy", "Lazy"]
const PERSONALITY_HINTS: PackedStringArray = [
	"Takes risky contracts in dangerous belts.",
	"Avoids dangerous belts unless the pay is well above fair.",
	"Chases the best pay and minds distance less.",
	"Wants short trips and takes long breaks.",
]
const SPECIALTY_NAMES: PackedStringArray = ["Mining", "Gunnery", "Salvage"]
const ATTRIBUTE_NAMES: PackedStringArray = ["Nerve", "Greed", "Diligence", "Piloting", "Skill", "Loyalty", "Teamwork"]
const ATTRIBUTE_HINTS: PackedStringArray = [
	"Nerve: how much danger they accept before refusing, fleeing or retreating.",
	"Greed: how much pay matters. Greedy captains spend less at the station.",
	"Diligence: short rests, few breaks, eager patrols.",
	"Piloting: top speed, turn rate and the chance to dodge a hit.",
	"Specialty skill: Mining and Salvage shorten the work, Gunnery raises accuracy and damage.",
	"Loyalty: favours station contracts and defending home.",
	"Teamwork: how readily they fly in a fleet and split a bounty. Low Teamwork and high Nerve: a lone wolf who takes on big bounties alone. Lone Wolf counts 3 lower, Union Rep 2 higher.",
]
## Teamwork shift from traits (see [method effective_teamwork]).
const LONE_WOLF_TEAMWORK := -3
const UNION_REP_TEAMWORK := 2

@export var captain_name: String = ""
@export var personality: Personality = Personality.BOLD
## Role of the ship, e.g. "Miner".
@export var role: String = ""
@export var specialty: Specialty = Specialty.MINING

@export_group("Attributes")
@export_range(1, 10) var nerve: int = 5
@export_range(1, 10) var greed: int = 5
@export_range(1, 10) var diligence: int = 5
@export_range(1, 10) var piloting: int = 5
## Specialty skill (Mining or Gunnery, see [member specialty]).
@export_range(1, 10) var skill: int = 5
@export_range(1, 10) var loyalty: int = 5
@export_range(1, 10) var teamwork: int = 5

## Career stats.
var loads_delivered: int = 0
var credits_earned: int = 0
## Credits kept after station spending (stage 3: buys modules).
var wallet: int = 0
## Credits spent at the station (fees and services).
var credits_spent: int = 0
var kills: int = 0
var escorts_completed: int = 0
## False once the captain died with their ship.
var alive: bool = true

## Stage 3 career.
var reputation: float = 0.0
var rank: int = Reputation.Rank.ROOKIE
## [{id: StringName, since: float, until: float (INF = stays)}], oldest first.
var traits: Array[Dictionary] = []
## Career lines, oldest first ("00:12 Miner at Mining Outpost 1").
var history: PackedStringArray = []
var hired_at: float = 0.0
## Sim time of the hire or the last career switch.
var career_since: float = 0.0
var crystal_loads: int = 0
var salvage_loads: int = 0
## Jobs done alone / with escorts (Lone Wolf).
var solo_jobs: int = 0
var team_jobs: int = 0
var fights_survived: int = 0
var ejections: int = 0
var modules_bought: int = 0
## The ship flown now (null while stranded or dead).
var ship: Ship
## True while waiting at the home outpost without a ship (after ejecting).
var stranded: bool = false


func get_personality_name() -> String:
	return PERSONALITY_NAMES[personality]


func get_personality_hint() -> String:
	return PERSONALITY_HINTS[personality]


func get_specialty_name() -> String:
	return SPECIALTY_NAMES[specialty]


func get_profile() -> PersonalityProfile:
	return PersonalityProfile.for_personality(personality)


## Attributes in [constant ATTRIBUTE_NAMES] order (Teamwork after traits).
func get_attributes() -> PackedInt32Array:
	return PackedInt32Array([nerve, greed, diligence, piloting, skill, loyalty, effective_teamwork()])


# --- Reputation -------------------------------------------------------------

func get_rank_name() -> String:
	return Reputation.rank_name(rank)


## Adds reputation; on a rank-up updates the ship's slots and posts it.
## Returns true on a rank-up.
func add_reputation(amount: float) -> bool:
	if amount <= 0.0 or not alive:
		return false
	reputation += amount
	var r := Reputation.rank_for(reputation)
	if r <= rank:
		return false
	rank = r
	if is_instance_valid(ship) and ship.loadout:
		ship.loadout.unlocked_slots = Reputation.slots_for(rank)
	var tier_up := Reputation.max_tier_for(rank) > Reputation.max_tier_for(rank - 1)
	EventLog.post("%s is now %s (%d slots%s)" % [captain_name, get_rank_name(), Reputation.slots_for(rank), ", " + ShipModule.TIER_NAMES[Reputation.max_tier_for(rank)] if tier_up else ""],
			EventLog.Kind.REWARD, ship if is_instance_valid(ship) else null)
	rank_changed.emit(self, rank)
	return true


# --- Traits -------------------------------------------------------------------

func has_trait(id: StringName) -> bool:
	for t in traits:
		if t["id"] == id:
			return true
	return false


func trait_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for t in traits:
		out.append(t["id"] as StringName)
	return out


## Gains [param id] (a fading one is refreshed). With 3 traits already the
## oldest fading one makes room; when none fades, the new one is not taken.
func add_trait(id: StringName) -> bool:
	if not alive:
		return false
	var fade := CaptainTraits.fade_time(id)
	var until := SimClock.time + fade if fade > 0.0 else INF
	for t in traits:
		if t["id"] == id:
			t["until"] = until
			return false
	if traits.size() >= CaptainTraits.MAX_TRAITS:
		var drop := -1
		for i in traits.size():
			if float(traits[i]["until"]) < INF:
				drop = i
				break
		if drop < 0:
			return false
		remove_trait(traits[drop]["id"] as StringName)
	traits.append({"id": id, "since": SimClock.time, "until": until})
	EventLog.post("%s gained the %s trait" % [captain_name, CaptainTraits.trait_name(id)], EventLog.Kind.INFO, ship if is_instance_valid(ship) else null)
	traits_changed.emit(self)
	return true


func remove_trait(id: StringName) -> void:
	for i in traits.size():
		if traits[i]["id"] == id:
			traits.remove_at(i)
			EventLog.post("%s is no longer %s" % [captain_name, CaptainTraits.trait_name(id)], EventLog.Kind.INFO, ship if is_instance_valid(ship) else null)
			traits_changed.emit(self)
			return


## Sim seconds until [param id] fades (INF when it stays, 0 when absent).
func trait_time_left(id: StringName) -> float:
	for t in traits:
		if t["id"] == id:
			return maxf(float(t["until"]) - SimClock.time, 0.0)
	return 0.0


## Fades expired traits and checks the slow ones (Union Rep). Cheap; call
## every few sim seconds.
func update_traits() -> void:
	var now := SimClock.time
	var i := traits.size() - 1
	while i >= 0:
		if float(traits[i]["until"]) <= now:
			remove_trait(traits[i]["id"] as StringName)
		i -= 1
	if not has_trait(CaptainTraits.UNION_REP) and loyalty >= CaptainTraits.UNION_LOYALTY \
			and now - hired_at >= CaptainTraits.UNION_SERVICE and rank >= Reputation.Rank.LICENSED:
		add_trait(CaptainTraits.UNION_REP)


## Counts one finished job, alone or with escorts (Lone Wolf).
func note_job(escorted: bool) -> void:
	if escorted:
		team_jobs += 1
	else:
		solo_jobs += 1
	var total := solo_jobs + team_jobs
	if solo_jobs >= CaptainTraits.LONE_WOLF_JOBS and float(team_jobs) <= float(total) * CaptainTraits.LONE_WOLF_TEAM_SHARE:
		add_trait(CaptainTraits.LONE_WOLF)


## Back home after a trip whose hull fell to [param lowest] (share of max).
func note_survived(lowest: float, was_hit: bool) -> void:
	if not was_hit:
		return
	fights_survived += 1
	add_reputation(Reputation.SURVIVED_FIGHT)
	if lowest < CaptainTraits.SURVIVOR_HULL:
		add_trait(CaptainTraits.SURVIVOR)
	if lowest < CaptainTraits.SHAKEN_HULL:
		add_trait(CaptainTraits.SHAKEN)


func add_history(line: String) -> void:
	var t := int(SimClock.time)
	history.append("%02d:%02d %s" % [floori(t / 60.0), t % 60, line])


## Nerve after traits (Shaken: 3 lower).
func effective_nerve() -> int:
	return clampi(nerve - (3 if has_trait(CaptainTraits.SHAKEN) else 0), 1, 10)


## Teamwork after traits (Lone Wolf lower, Union Rep higher).
func effective_teamwork() -> int:
	var t := teamwork
	if has_trait(CaptainTraits.LONE_WOLF):
		t += LONE_WOLF_TEAMWORK
	if has_trait(CaptainTraits.UNION_REP):
		t += UNION_REP_TEAMWORK
	return clampi(t, 1, 10)


## 0..1: how ready this captain is to take on a fight above their weight
## alone (high Nerve, low Teamwork). See MercenaryEvaluator.
func daring() -> float:
	return 0.6 * unit(effective_nerve()) + 0.4 * (1.0 - unit(effective_teamwork()))


## Chance to eject when the ship is destroyed: Piloting, modules, Survivor.
func eject_chance(stats: ShipStats = null) -> float:
	var c := 0.1 + 0.3 * unit(piloting)
	if stats:
		c += stats.eject_bonus
	if has_trait(CaptainTraits.SURVIVOR):
		c += 0.1
	return clampf(c, 0.0, 0.9)


## Rolls every attribute: the personality's base plus a spread, clamped 1..10.
func roll_attributes(rng: RandomNumberGenerator) -> void:
	var prof := get_profile()
	var base := prof.attribute_base
	var spread := prof.attribute_spread
	var vals: Array[int] = []
	for i in ATTRIBUTE_NAMES.size():
		var b := base[i] if i < base.size() else 5
		vals.append(clampi(b + rng.randi_range(-spread, spread), 1, 10))
	nerve = vals[0]
	greed = vals[1]
	diligence = vals[2]
	piloting = vals[3]
	skill = vals[4]
	loyalty = vals[5]
	teamwork = vals[6]


## -1 at 1, 0 at 5.5, +1 at 10.
static func factor(value: int) -> float:
	return clampf((float(value) - 5.5) / 4.5, -1.0, 1.0)


## 0 at 1, 1 at 10.
static func unit(value: int) -> float:
	return clampf((float(value) - 1.0) / 9.0, 0.0, 1.0)


## Share of earnings spent at the station (fees, services): 30% down to 20%
## with Greed.
## Union Rep keeps 4% more.
func station_spend_share() -> float:
	return lerpf(0.30, 0.20, unit(greed)) - (0.04 if has_trait(CaptainTraits.UNION_REP) else 0.0)


## Multiplier on the danger term of contract scoring (Nerve, Survivor).
func danger_scale() -> float:
	return lerpf(1.45, 0.6, unit(effective_nerve())) * (0.9 if has_trait(CaptainTraits.SURVIVOR) else 1.0)


## Multiplier on the pay term (Greed).
func pay_scale() -> float:
	return lerpf(0.85, 1.25, unit(greed))


## Multiplier on rest times (Diligence).
func rest_scale() -> float:
	return lerpf(1.45, 0.7, unit(diligence))


## Added to the profile's break chance (Diligence).
func break_bonus() -> float:
	return -0.06 * factor(diligence)


## Nerve shift for thresholds: added to the flee threat level and taken off
## the retreat hull level, so brave captains hold on longer. Grudge adds a
## little: they do not run from scavengers as soon.
func nerve_offset() -> float:
	return 0.12 * factor(effective_nerve()) + (0.05 if has_trait(CaptainTraits.GRUDGE) else 0.0)


## Speed and turn multiplier (Piloting).
func piloting_scale() -> float:
	return lerpf(0.9, 1.12, unit(piloting))


## Chance to dodge an incoming hit (Piloting).
func dodge_chance() -> float:
	return lerpf(0.02, 0.2, unit(piloting))


## Work time multiplier (Mining or Salvage skill, for that role's tool).
func drill_time_scale() -> float:
	return lerpf(1.25, 0.78, unit(skill)) if specialty != Specialty.GUNNERY else 1.3


## Hit chance per shot (Gunnery skill).
func accuracy() -> float:
	return lerpf(0.5, 0.88, unit(skill)) if specialty == Specialty.GUNNERY else 0.4


## Weapon damage multiplier (Gunnery skill).
func damage_scale() -> float:
	return lerpf(0.85, 1.2, unit(skill)) if specialty == Specialty.GUNNERY else 0.8


## Utility bonus for any station contract (Loyalty).
func loyalty_bonus() -> float:
	return 0.06 * factor(loyalty)


## [param personality_override] >= 0 forces the personality (demos, tests).
static func generate(rng: RandomNumberGenerator, role_name: String, personality_override: int = -1) -> Captain:
	var c := Captain.new()
	c.captain_name = "%s %s" % [FIRST_NAMES[rng.randi() % FIRST_NAMES.size()], LAST_NAMES[rng.randi() % LAST_NAMES.size()]]
	c.personality = (rng.randi() % PERSONALITY_NAMES.size()) as Personality
	if personality_override >= 0:
		c.personality = clampi(personality_override, 0, PERSONALITY_NAMES.size() - 1) as Personality
	c.role = role_name
	c.specialty = specialty_for(role_name)
	c.roll_attributes(rng)
	c.hired_at = SimClock.time
	c.career_since = c.hired_at
	return c


static func specialty_for(role_name: String) -> Specialty:
	match role_name:
		"Mercenary":
			return Specialty.GUNNERY
		"Salvager":
			return Specialty.SALVAGE
	return Specialty.MINING

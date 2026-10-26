class_name PlanetRaidContract
extends LoadContract
## Raid a planet or moon (phase C2): the player pays [member reward] credits
## for every load a lander (a pilot of the Raider Dock flying a dropship)
## brings home. The load is the planet's loot (PlanetRaidRules.loot_of:
## fuel, water, rare metals, silicates or heavy ore), which goes into the
## dock's stock and reaches the station by cargo shuttle, like ore from a
## Mining Outpost. Capped by [member max_loads] (see [LoadContract]). Paid
## per delivery: nothing is reserved, it can only be posted while one
## payment can be paid and pauses while it cannot (Contract.is_paused).
## Every planet keeps a record of its raids ([method record_of]): loads and
## units brought home, the last raid's time. Saved under "planets"; C4
## (depletion) builds on it.

const RULES_PATH := "res://data/contracts/planet_raid_rules.tres"

static var _rules: PlanetRaidRules
## Planet name -> {raids: int, units: int, last: float (sim time), credits: int}.
static var records: Dictionary = {}

var planet: PlanetBody
var loot: int = Economy.Ore.HEAVY_ORE
var units_delivered: int = 0


func _init(on_planet: PlanetBody = null, credits_per_load: int = 0, load_limit: int = 0) -> void:
	type = Type.PLANET_RAID
	planet = on_planet
	target = on_planet
	reward = credits_per_load
	max_loads = maxi(load_limit, 0)
	if on_planet and on_planet.def:
		loot = rules().loot_of(on_planet.def)


static func rules() -> PlanetRaidRules:
	if _rules == null:
		_rules = load(RULES_PATH) as PlanetRaidRules
		if _rules == null:
			_rules = PlanetRaidRules.new()
	return _rules


## Planet or moon named [param body_name] in the system, or null.
static func find_planet(ctx: Node, body_name: String) -> PlanetBody:
	var sys := SolarSystem.of(ctx)
	if sys == null:
		return null
	for p in sys.planets:
		if p.def.name == body_name:
			return p
		for c in p.get_children():
			if c is PlanetBody and (c as PlanetBody).def.name == body_name:
				return c as PlanetBody
	return null


## The raid record of [param body] ({} = never raided).
static func record_of(body: PlanetBody) -> Dictionary:
	if body == null or body.def == null:
		return {}
	return records.get(body.def.name, {})


static func note_raid(body: PlanetBody, units: int, credits: int) -> void:
	if body == null or body.def == null:
		return
	var r: Dictionary = records.get(body.def.name, {"raids": 0, "units": 0, "credits": 0, "last": 0.0})
	r["raids"] = int(r["raids"]) + 1
	r["units"] = int(r["units"]) + units
	r["credits"] = int(r.get("credits", 0)) + credits
	r["last"] = SimClock.time
	records[body.def.name] = r


static func save_records() -> Dictionary:
	return records.duplicate(true)


static func load_records(d: Dictionary) -> void:
	records = d.duplicate(true)


## Danger 1..5 of raiding [param body] from home (see PlanetRaidRules.danger_of).
static func danger_for(body: PlanetBody) -> int:
	if body == null or not is_instance_valid(body) or not body.is_inside_tree():
		return 1
	var sys := SolarSystem.of(body)
	var home := sys.home_station.global_position if sys and is_instance_valid(sys.home_station) else Vector3.ZERO
	return rules().danger_of(body, home)


func get_type_name() -> String:
	return "Planet raid"


func get_target_name() -> String:
	return planet.def.name if is_instance_valid(planet) and planet.def else super.get_target_name()


func get_progress_text() -> String:
	var units := "%s %s" % [Fmt.amount(units_delivered), Economy.ore_name(loot)]
	if max_loads > 0:
		return "%d / %d loads, %s" % [loads_delivered, max_loads, units]
	return "%d loads, %s" % [loads_delivered, units]


func get_danger() -> int:
	return danger_for(planet)


func fair_reward() -> int:
	return rules().fair_reward(planet.def if is_instance_valid(planet) else null, get_danger())

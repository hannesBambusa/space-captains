class_name SectorModifier
extends RefCounted
## Sector modifiers: one per game, picked on the New game page (or Random,
## rolled from the non-standard ones), kept in [member Sector.modifier] and
## saved under "cluster"."modifier". A modifier is a set of multipliers the
## systems read through [method num]; a key it does not set reads as the
## default. It works everywhere in the sector (home, forward stations,
## rival worlds), so the rivals play under it too. The tutorial game is
## always Standard.
## Keys:
## - reserve: ore per cluster (ClusterDef.get_reserve)
## - threat: speed of the base arrival clock (ThreatDirector.threat_time)
## - raid_interval: time between raids (RaidDirector.interval)
## - raid_extra: raiders added to each raid after the gentle ones (RaidDirector.wave_size)
## - ore_price: what the Factory pays for every ore and planet good (FactoryMarket.willingness)
## - iron, titanium, crystal: how often new clusters are that ore (ClusterSpawner._pick_ore)
## - credits_add: start credits added (or taken) on a new game (Sector.reset)

const STANDARD := &"standard"
## The New game choice that rolls one of the others.
const RANDOM := &"random"

const LIST: Array[Dictionary] = [
	{"id": &"standard", "name": "Standard",
		"blurb": "The sector as the corporation surveyed it. No surprises."},
	{"id": &"motherlode", "name": "Motherlode",
		"blurb": "Rich rocks, hungry pirates. Clusters hold 60% more ore, but pirate bases arrive sooner and raids come more often.",
		"reserve": 1.6, "threat": 1.4, "raid_interval": 0.8},
	{"id": &"backwater", "name": "Backwater",
		"blurb": "Thin rocks, quiet space. Clusters hold 30% less ore and the Factory pays 15% more for it. Pirate bases come late and raids are rare.",
		"reserve": 0.7, "ore_price": 1.15, "threat": 0.6, "raid_interval": 1.35},
	{"id": &"pirate_haven", "name": "Pirate haven",
		"blurb": "Raiders everywhere. Bases arrive much sooner, raids come often and bring one ship more. The corporation adds 1,500 cr of hazard money.",
		"threat": 1.7, "raid_interval": 0.7, "raid_extra": 1.0, "credits_add": 1500.0},
	{"id": &"boom", "name": "Boom market",
		"blurb": "Ore prices are up: the Factory pays 30% more for everything you sell it. The corporation starts you with 1,000 cr less.",
		"ore_price": 1.3, "credits_add": -1000.0},
	{"id": &"crystal_rush", "name": "Crystal rush",
		"blurb": "New clusters are crystal three times as often. Crystal sits far out and pays well, and the corsairs who hunt there come a little sooner.",
		"crystal": 3.0, "iron": 0.8, "threat": 1.2},
]


## The modifier dict of [param id] (Standard for an unknown id).
static func find(id: StringName) -> Dictionary:
	for m in LIST:
		if m["id"] == id:
			return m
	return LIST[0]


## Every id but Standard: what Random picks from.
static func random_pool() -> Array[StringName]:
	var out: Array[StringName] = []
	for m in LIST:
		if m["id"] != STANDARD:
			out.append(m["id"])
	return out


## [param key] of the running game's modifier, [param default] when it does not set it.
static func num(key: String, default: float = 1.0) -> float:
	return float(find(Sector.modifier).get(key, default))


static func name_of(id: StringName) -> String:
	return "Random" if id == RANDOM else String(find(id)["name"])

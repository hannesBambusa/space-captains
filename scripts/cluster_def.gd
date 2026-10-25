class_name ClusterDef
extends Resource
## An asteroid cluster: a dense clump of rock 1 to 3 km across that orbits
## the star like a planet (inclined circular orbit). AsteroidCluster builds it.
## (The class keeps its old name; "belt" in code means a cluster.)
## Starting clusters live in SystemDef.belts; ClusterSpawner makes new ones
## at run time with [method make_generated] and saves them with
## [method to_dict].

@export var name: String = "Cluster"
@export var ore_type: AsteroidBelt.OreType = AsteroidBelt.OreType.IRON
## Optional second ore. ROCK = none.
@export var secondary_ore: AsteroidBelt.OreType = AsteroidBelt.OreType.ROCK
@export_range(0.0, 1.0, 0.01) var secondary_share: float = 0.25

@export_group("Orbit")
## Distance of the cluster centre from the star, metres.
@export var orbit_radius: float = 6000.0
@export_range(0.0, 360.0, 0.1, "degrees") var start_angle_deg: float = 0.0
@export_range(0.0, 10.0, 0.1, "degrees") var inclination_deg: float = 1.5
@export_range(0.0, 360.0, 0.1, "degrees") var ascending_node_deg: float = 0.0
## Sim seconds per orbit. 0 = derived from the radius ([method get_orbit_period]).
@export var orbit_period: float = 0.0

@export_group("Shape")
## Diameter of the clump, metres.
@export var size: float = 2000.0
## Max rock centre height above/below the cluster centre, metres. Heights
## are gaussian, densest at the middle.
@export var vertical_spread: float = 300.0
## Asteroid count. 0 = derived from the size ([method get_count]).
@export var count: int = 0
@export var min_scale: float = 2.0
@export var max_scale: float = 25.0

@export_group("Content")
## 0..1. Share of ore-bearing asteroids.
@export_range(0.0, 1.0, 0.01) var richness: float = 0.3
## 1..5. Base danger before nearby hostile bases add theirs.
@export_range(1, 5, 1) var danger: int = 1
## Loads the cluster holds before it is mined out. 0 = derived ([method get_reserve]).
@export var reserve_loads: int = 0
@export var seed: int = 1
## Crystal glow multiplier (near asteroids and far dust).
@export var glow: float = 1.0
## Colour of the far-view dust.
@export var dust_color: Color = Color(0.62, 0.55, 0.48, 1.0)

## Orbit period per metre of radius (sim s / m): every cluster drifts at
## about 12.6 m/s, slower than the planets.
const PERIOD_PER_M := 0.5


func get_orbit_period() -> float:
	return orbit_period if orbit_period > 0.0 else orbit_radius * PERIOD_PER_M


func get_count() -> int:
	if count > 0:
		return count
	return clampi(int(1500.0 * pow(size / 1000.0, 1.6)), 1200, 9000)


## Reserve in loads: bigger and richer clusters hold more (25 to 60).
func get_reserve() -> int:
	if reserve_loads > 0:
		return reserve_loads
	var s := clampf((size - 1000.0) / 2000.0, 0.0, 1.0)
	return clampi(roundi(25.0 + 20.0 * s + 15.0 * richness), 25, 60)


func radius() -> float:
	return size * 0.5


func to_dict() -> Dictionary:
	return {"name": name, "ore": int(ore_type), "ore2": int(secondary_ore), "share": secondary_share,
			"r": orbit_radius, "a": start_angle_deg, "inc": inclination_deg, "node": ascending_node_deg,
			"period": orbit_period, "size": size, "vs": vertical_spread, "count": count, "min": min_scale,
			"max": max_scale, "rich": richness, "danger": danger, "reserve": reserve_loads, "seed": seed,
			"glow": glow, "dust": dust_color}


static func from_dict(d: Dictionary) -> ClusterDef:
	var b := ClusterDef.new()
	b.name = String(d.get("name", "Cluster"))
	b.ore_type = int(d.get("ore", 1)) as AsteroidBelt.OreType
	b.secondary_ore = int(d.get("ore2", 0)) as AsteroidBelt.OreType
	b.secondary_share = float(d.get("share", 0.25))
	b.orbit_radius = float(d.get("r", 6000.0))
	b.start_angle_deg = float(d.get("a", 0.0))
	b.inclination_deg = float(d.get("inc", 1.5))
	b.ascending_node_deg = float(d.get("node", 0.0))
	b.orbit_period = float(d.get("period", 0.0))
	b.size = float(d.get("size", 2000.0))
	b.vertical_spread = float(d.get("vs", 300.0))
	b.count = int(d.get("count", 0))
	b.min_scale = float(d.get("min", 2.0))
	b.max_scale = float(d.get("max", 25.0))
	b.richness = float(d.get("rich", 0.3))
	b.danger = int(d.get("danger", 1))
	b.reserve_loads = int(d.get("reserve", 0))
	b.seed = int(d.get("seed", 1))
	b.glow = float(d.get("glow", 1.0))
	b.dust_color = d.get("dust", Color(0.62, 0.55, 0.48, 1.0)) as Color
	return b

class_name SystemDef
extends Resource
## Data for one star system. SolarSystem builds the scene from this.
## Angles: 0 deg = +X, 90 deg = +Z. All distances in metres, times in sim seconds.

@export var system_name: String = "System"
## 1..5. Generated systems: about the gate depth from home (SystemGenerator).
@export_range(1, 5, 1) var danger: int = 1

@export_group("Star")
## Spectral class, for labels ("G", "K", "M", "F", "A", "B").
@export var star_class: String = "G"
@export var star_radius: float = 600.0
## Surface temperature in kelvin; drives the star and light colour.
@export var star_temperature: float = 5600.0
## Optional override. Alpha 0 = derive from temperature.
@export var star_color_override: Color = Color(0, 0, 0, 0)
## Light energy of the star at the system's mid range.
@export var light_energy: float = 1.15

@export_group("Bodies")
@export var planets: Array[PlanetDef] = []
## Starting asteroid clusters (ClusterSpawner adds new ones as these are mined out).
@export var belts: Array[ClusterDef] = []
@export var gates: Array[GateDef] = []
## Hostile bases at fixed spots; each adds its danger to clusters nearby.
@export var dens: Array[DenDef] = []
## Derelict hulks (built as [Derelict] nodes, looted by explorers: DerelictLoot).
@export var derelicts: Array[DerelictDef] = []

@export_group("Asteroid clusters")
## Clusters kept in the system: below the minimum a new one is surveyed.
@export var cluster_min: int = 4
@export var cluster_max: int = 6
## Sim seconds from a cluster running out (or the count falling under the
## minimum) to a new one showing up, random in this range.
@export var cluster_respawn: Vector2 = Vector2(180.0, 360.0)
## Orbit radius range new clusters may take, metres.
@export var cluster_orbit_range: Vector2 = Vector2(9500.0, 44000.0)
## Names for new clusters, used in order, skipping names in use.
@export var cluster_names: PackedStringArray = []

@export_group("Threat escalation")
## A den arrives at the latest at its min arrival time times this, growth or not.
@export var arrival_max_wait_mult: float = 1.5
## Sim seconds between the long-range scan warning and the arrival.
@export var arrival_warning_time: float = 75.0
## Sim seconds at least between two arrivals.
@export var arrival_min_gap: float = 180.0
## Extra threat-clock speed while every arrived base is destroyed (0.5 = 1.5x).
@export var cleared_speedup: float = 0.5
## Bases alive at which the system counts as crowded.
@export var crowd_bases: int = 3
## Threat-clock speed while crowded (0.35 = arrivals take about 3x as long).
@export var crowd_slowdown: float = 0.35
## The min gap between arrivals is multiplied by this while crowded.
@export var crowd_gap_mult: float = 3.0
## Sim seconds after its arrival before a base sends raids.
@export var arrival_raid_grace: float = 240.0

@export_group("Home station")
## Name of the planet the station orbits. Empty = no station.
@export var station_planet: String = ""
@export var station_orbit_radius: float = 1600.0
@export var station_orbit_period: float = 360.0
@export_range(0.0, 360.0, 0.1, "degrees") var station_start_angle_deg: float = 0.0

@export_group("Look")
@export var sky_seed: float = 7.31
## Camera bounds radius. 0 = derive from the outermost body.
@export var system_radius: float = 0.0


func get_star_color() -> Color:
	if star_color_override.a > 0.0:
		return Color(star_color_override, 1.0)
	return kelvin_to_color(star_temperature)


## Outermost extent of any body, plus a margin.
func get_extent() -> float:
	if system_radius > 0.0:
		return system_radius
	var r := star_radius * 4.0
	for p in planets:
		var moon_reach := p.radius * (p.ring_outer if p.has_rings else 1.0)
		for m: PlanetDef in p.moons:
			moon_reach = maxf(moon_reach, m.orbit_radius + m.radius)
		r = maxf(r, p.orbit_radius + moon_reach)
	for b in belts:
		r = maxf(r, b.orbit_radius + b.radius())
	for g in gates:
		r = maxf(r, g.orbit_radius + 300.0)
	return r + 1500.0


func find_planet(planet_name: String) -> PlanetDef:
	for p in planets:
		if p.name == planet_name:
			return p
	return null


## Approximate blackbody colour (Tanner Helland fit), 1000-40000 K.
static func kelvin_to_color(kelvin: float) -> Color:
	var t := clampf(kelvin, 1000.0, 40000.0) / 100.0
	var r: float
	var g: float
	var b: float
	if t <= 66.0:
		r = 255.0
		g = 99.4708025861 * log(t) - 161.1195681661
	else:
		r = 329.698727446 * pow(t - 60.0, -0.1332047592)
		g = 288.1221695283 * pow(t - 60.0, -0.0755148492)
	if t >= 66.0:
		b = 255.0
	elif t <= 19.0:
		b = 0.0
	else:
		b = 138.5177312231 * log(t - 10.0) - 305.0447927307
	return Color(clampf(r, 0, 255) / 255.0, clampf(g, 0, 255) / 255.0, clampf(b, 0, 255) / 255.0)

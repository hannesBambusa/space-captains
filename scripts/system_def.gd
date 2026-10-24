class_name SystemDef
extends Resource
## Data for one star system. SolarSystem builds the scene from this.
## Angles: 0 deg = +X, 90 deg = +Z. All distances in metres, times in sim seconds.

@export var system_name: String = "System"

@export_group("Star")
@export var star_radius: float = 1500.0
## Surface temperature in kelvin; drives the star and light colour.
@export var star_temperature: float = 5600.0
## Optional override. Alpha 0 = derive from temperature.
@export var star_color_override: Color = Color(0, 0, 0, 0)
## Light energy of the star at the system's mid range.
@export var light_energy: float = 1.15

@export_group("Bodies")
@export var planets: Array[PlanetDef] = []
@export var belts: Array[BeltDef] = []
@export var gates: Array[GateDef] = []
## Scavenger Dens, each claiming a belt (its danger includes the den).
@export var dens: Array[DenDef] = []

@export_group("Threat escalation")
## A den arrives at the latest at its min arrival time times this, growth or not.
@export var arrival_max_wait_mult: float = 1.5
## Sim seconds between the long-range scan warning and the arrival.
@export var arrival_warning_time: float = 75.0
## Sim seconds at least between two arrivals.
@export var arrival_min_gap: float = 180.0
## Extra threat-clock speed while every arrived base is destroyed (0.5 = 1.5x).
@export var cleared_speedup: float = 0.5
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
		r = maxf(r, b.orbit_radius + b.width * 0.5)
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

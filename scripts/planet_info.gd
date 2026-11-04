class_name PlanetInfo
extends RefCounted
## Planet lookups shared by the planet panel, planet outposts and claims
## (they lived on the planet raid contract before planet outposts replaced
## planet raids).

## Base danger by planet type (PlanetDef.Type): lava and gas giants 2, the rest 1.
const BASE_DANGER: PackedInt32Array = [1, 1, 1, 1, 2, 2]
## Distance from the station that adds a danger level, and two, km.
const FAR_KM := 15.0
const DEEP_KM := 30.0


## Planet or moon named [param body_name] in [param ctx]'s system, or null.
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


## Danger 1..5 at [param body]: its type, its distance from the system's
## station, and at least what nearby bases give the spot.
static func danger_for(body: PlanetBody) -> int:
	if body == null or not is_instance_valid(body) or not body.is_inside_tree():
		return 1
	var sys := SolarSystem.of(body)
	var home := sys.home_station.global_position if sys and is_instance_valid(sys.home_station) else Vector3.ZERO
	var d := BASE_DANGER[clampi(body.def.type, 0, BASE_DANGER.size() - 1)]
	var km := SpaceNav.flat_distance(body.global_position, home) / 1000.0
	if km > DEEP_KM:
		d += 2
	elif km > FAR_KM:
		d += 1
	d = maxi(d, SalvageContract.danger_at(body, body.global_position))
	return clampi(d, 1, 5)

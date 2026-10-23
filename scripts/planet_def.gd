class_name PlanetDef
extends Resource
## One planet or moon. Moons are PlanetDefs nested in [member moons]; their
## orbit fields are relative to the parent planet.

enum Type { ROCKY, OCEAN, DESERT, ICE, LAVA, GAS_GIANT }

@export var name: String = "Planet"
@export var type: Type = Type.ROCKY
## Body radius in metres.
@export var radius: float = 400.0
## Variation seed for the surface noise.
@export var seed: float = 1.0
## Multiplies the type's base palette.
@export var tint: Color = Color.WHITE

@export_group("Orbit")
## Distance from the parent (star or planet) in metres.
@export var orbit_radius: float = 8000.0
## Seconds per orbit at 1x sim speed. 0 = fixed in place.
@export var orbit_period: float = 600.0
@export_range(0.0, 360.0, 0.1, "degrees") var start_angle_deg: float = 0.0
## Tilt of the orbit plane against the parent's plane (the system plane for
## a planet, the planet's orbit plane for a moon). Planets 2 to 8, moons 5 to 20.
@export_range(0.0, 30.0, 0.1, "degrees") var inclination_deg: float = 3.0
## Longitude of the ascending node: where the orbit crosses the parent's
## plane going up (0 = +X, 90 = +Z).
@export_range(0.0, 360.0, 0.1, "degrees") var ascending_node_deg: float = 0.0

@export_group("Spin")
## Seconds per rotation at 1x sim speed. 0 = no spin. Negative = retrograde.
@export var spin_period: float = 180.0
@export_range(-90.0, 90.0, 0.1, "degrees") var axial_tilt_deg: float = 12.0

@export_group("Atmosphere")
## Alpha is the strength. Alpha 0 = no atmosphere shell.
@export var atmosphere_color: Color = Color(0.3, 0.62, 1.0, 1.0)

@export_group("Rings")
@export var has_rings: bool = false
## Ring inner/outer edge as multiples of [member radius].
@export var ring_inner: float = 1.3
@export var ring_outer: float = 2.1
@export var ring_color: Color = Color(0.82, 0.74, 0.62, 1.0)

@export_group("Moons")
## PlanetDef entries. Typed as Resource because a script that holds a typed
## array of itself leaks at exit (cyclic script reference).
@export var moons: Array[Resource] = []


## Orbit plane relative to the parent's plane (see Orbiter.inclined_basis).
func orbit_plane() -> Basis:
	return Orbiter.inclined_basis(inclination_deg, ascending_node_deg)

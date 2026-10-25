class_name Orbiter
extends Node3D
## Anything on a circular orbit around its parent's origin. The orbit plane
## is the parent's horizontal plane tilted by [member orbit_basis] (an
## inclination about the line of nodes, see [method inclined_basis]);
## identity = the y = 0 plane. Never rotated itself, so children keep a
## stable, level frame. Driven by SolarSystem through [method update_sim]
## with the sim clock time.

@export var orbit_radius: float = 0.0
## Sim seconds per orbit. 0 = fixed at the start angle.
@export var orbit_period: float = 0.0
@export var start_angle_deg: float = 0.0
## Orbit plane relative to the parent's axes (world axes for a planet,
## the planet's orbit plane included for a moon).
var orbit_basis := Basis.IDENTITY


func setup_orbit(radius: float, period: float, start_deg: float, plane: Basis = Basis.IDENTITY) -> void:
	orbit_radius = radius
	orbit_period = period
	start_angle_deg = start_deg
	orbit_basis = plane
	update_sim(0.0)


## Orbit plane tilted by [param inclination_deg] about the line of nodes at
## [param node_deg] (0 = +X, 90 = +Z). The orbit rises above the parent's
## plane after crossing the ascending node.
static func inclined_basis(inclination_deg: float, node_deg: float) -> Basis:
	if is_zero_approx(inclination_deg):
		return Basis.IDENTITY
	var n := deg_to_rad(node_deg)
	# The orbit runs +X toward +Z: tilting about the node axis by -i lifts
	# the half after the node to +Y.
	return Basis(Vector3(cos(n), 0.0, sin(n)), -deg_to_rad(inclination_deg))


## Marks this node as a camera focus target.
func make_focusable(pick_radius: float, view_distance: float) -> void:
	set_meta(&"focus_radius", pick_radius)
	set_meta(&"focus_distance", view_distance)
	add_to_group(RTSCamera.FOCUS_GROUP)


func orbit_angle(sim_time: float) -> float:
	var a := deg_to_rad(start_angle_deg)
	if orbit_period != 0.0:
		a += TAU * sim_time / orbit_period
	return a


## Offset from the parent's origin at [param sim_time].
func orbit_offset(sim_time: float) -> Vector3:
	return orbit_point(orbit_angle(sim_time))


## Offset from the parent's origin at orbit angle [param a] (radians).
func orbit_point(a: float) -> Vector3:
	return orbit_basis * Vector3(cos(a), 0.0, sin(a)) * orbit_radius


## Velocity relative to the parent at [param sim_time], m/s.
func orbit_velocity_at(sim_time: float) -> Vector3:
	if orbit_period == 0.0 or orbit_radius == 0.0:
		return Vector3.ZERO
	var a := orbit_angle(sim_time)
	return orbit_basis * Vector3(-sin(a), 0.0, cos(a)) * orbit_radius * TAU / orbit_period


func update_sim(sim_time: float) -> void:
	position = orbit_offset(sim_time)

class_name Orbiter
extends Node3D
## Anything on a circular orbit in the y = 0 plane around its parent's origin.
## Never rotated itself, so children keep a stable frame. Driven by
## SolarSystem through [method update_sim] with the sim clock time.

@export var orbit_radius: float = 0.0
## Sim seconds per orbit. 0 = fixed at the start angle.
@export var orbit_period: float = 0.0
@export var start_angle_deg: float = 0.0


func setup_orbit(radius: float, period: float, start_deg: float) -> void:
	orbit_radius = radius
	orbit_period = period
	start_angle_deg = start_deg
	update_sim(0.0)


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


func update_sim(sim_time: float) -> void:
	var a := orbit_angle(sim_time)
	position = Vector3(cos(a), 0.0, sin(a)) * orbit_radius

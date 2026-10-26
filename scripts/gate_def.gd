class_name GateDef
extends Resource
## A jump gate linking this system to another one in the cluster.

@export var name: String = "Gate"
## System name the gate leads to. Generated network: filled at run time
## (Sector, ClusterNetwork), the home gates on every new game and load.
@export var target_system: String = ""
## Name of the gate a ship comes out of in [member target_system].
@export var target_gate: String = ""
@export var orbit_radius: float = 26000.0
@export_range(0.0, 360.0, 0.1, "degrees") var orbit_angle_deg: float = 0.0
## Seconds per orbit at 1x. 0 = fixed in place.
@export var orbit_period: float = 0.0
## Lean of the ring away from upright, so the portal reads from above. 0 = upright.
@export_range(0.0, 90.0, 0.5, "degrees") var tilt_deg: float = 62.0
@export var portal_color: Color = Color(0.35, 0.75, 1.0, 1.0)

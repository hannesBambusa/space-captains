class_name DerelictDef
extends Resource
## A derelict hulk in a SystemDef: a fixed spot with loot (generated
## systems, SystemGenerator). Built as a [Derelict] node while its system
## is live; explorers strip it during a survey (DerelictLoot).

enum Kind { PROBE, FREIGHTER, FRIGATE, STATION_HULK }

@export var name: String = "Derelict"
@export var kind: Kind = Kind.FREIGHTER
## Distance from the star, metres.
@export var orbit_radius: float = 20000.0
@export_range(0.0, 360.0, 0.1, "degrees") var angle_deg: float = 0.0
## Metres above (+) or below (-) the system plane.
@export var height: float = 0.0
## Loot table id (DerelictLoot.roll: derelict_probe, _freighter, _frigate, _station).
@export var loot_table: StringName = &"derelict_small"
## 1..3. Better hulks deeper in the network.
@export_range(1, 3, 1) var loot_tier: int = 1


## Spot in system space (star at the origin).
func position() -> Vector3:
	var a := deg_to_rad(angle_deg)
	return Vector3(cos(a), 0.0, sin(a)) * orbit_radius + Vector3.UP * height

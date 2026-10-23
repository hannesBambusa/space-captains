class_name DenDef
extends Resource
## A Scavenger Den in a SystemDef. Placed at a fixed point next to the belt
## it claims: [member angle_deg] around the star (0 = +X, 90 = +Z) at the
## belt's centre-line radius plus [member radial_offset].
## Belt danger: the claimed belt's authored danger includes this den's
## [member danger_bonus]; destroying the den takes it off (min 1), so the
## ratings agree with where the dens are.

@export var name: String = "Scavenger Hideout"
## Gang name used for the den's ships ("Rustjaw" -> "Scavenger Rustjaw-3").
@export var gang: String = "Rustjaw"
@export var belt_name: String = ""
@export_range(0.0, 360.0, 0.1, "degrees") var angle_deg: float = 0.0
## Metres out from (+) or in toward (-) the star from the belt centre line.
@export var radial_offset: float = 900.0
## Metres above (+) or below (-) the system plane. Keep it clear of the
## belt's rock layer only if the den sits inside the band radially.
@export var height: float = 0.0

@export_group("Spawning")
## Scavengers alive at once from this den.
@export var spawn_cap: int = 3
## Sim seconds between spawns while below the cap.
@export var respawn_time: float = 45.0
## Scavengers out at the start.
@export var initial_spawns: int = 2

@export_group("Toughness")
@export var hull: float = 4000.0
@export var shields: float = 800.0
@export var shield_regen: float = 10.0

@export_group("Territory")
## Danger levels this den adds to its belt.
@export_range(0, 4) var danger_bonus: int = 2
## Scavengers roam within this arc of the belt around the den, degrees.
@export var roam_arc_deg: float = 22.0
## Miners on the claimed belt closer than this to the den are hunted, metres.
@export var hunt_range: float = 9000.0

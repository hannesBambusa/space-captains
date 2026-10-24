class_name DenDef
extends Resource
## A hostile base in a SystemDef (Scavenger Hideout, Corsair Nest, Syndicate
## Fortress: [member faction]). Placed at a fixed point next to the belt
## it claims: [member angle_deg] around the star (0 = +X, 90 = +Z) at the
## belt's centre-line radius plus [member radial_offset].
## Belt danger: the claimed belt's authored danger includes this den's
## [member danger_bonus]; destroying the den takes it off (min 1), so the
## ratings agree with where the dens are.
## Arrival (ThreatDirector): a den with [member arrival_order] 0 is there
## from the start; the others arrive one by one in that order, each once
## [member min_arrival_time] has passed and the colony has grown to
## [member growth_captains] and [member growth_structures], or anyway at
## min time times SystemDef.arrival_max_wait_mult. Until then the den does
## not exist: no ships, no danger, no map marker.

@export var name: String = "Scavenger Hideout"
## Whose base it is. Null = the scavengers.
@export var faction: FactionDef
## Gang name ("Rustjaw" -> "Scavenger Rustjaw-3"; factions with a name pool
## use it for their callsigns instead).
@export var gang: String = "Rustjaw"
@export var belt_name: String = ""
@export_range(0.0, 360.0, 0.1, "degrees") var angle_deg: float = 0.0
## Metres out from (+) or in toward (-) the star from the belt centre line.
@export var radial_offset: float = 900.0
## Metres above (+) or below (-) the system plane. Keep it clear of the
## belt's rock layer only if the den sits inside the band radially.
@export var height: float = 0.0

@export_group("Arrival")
## 0 = there at the start. Otherwise the place in the arrival queue (1 first).
@export var arrival_order: int = 0
## Earliest arrival, sim seconds of threat time (see ThreatDirector).
@export var min_arrival_time: float = 0.0
## Growth the colony must show before the den arrives early: living hired
## captains and active structures (the start Factory counts).
@export var growth_captains: int = 0
@export var growth_structures: int = 0

@export_group("Spawning")
## Ships alive at once from this den.
@export var spawn_cap: int = 3
## Sim seconds between spawns while below the cap.
@export var respawn_time: float = 45.0
## Ships out at the start.
@export var initial_spawns: int = 2

@export_group("Toughness")
## -1 = the faction's default (FactionDef.den_hull and so on).
@export var hull: float = 4000.0
@export var shields: float = 800.0
@export var shield_regen: float = 10.0

@export_group("Territory")
## Danger levels this den adds to its belt.
@export_range(0, 4) var danger_bonus: int = 2
## Its ships roam within this arc of the belt around the den, degrees.
@export var roam_arc_deg: float = 22.0
## Prey on the claimed belt closer than this to the den is hunted, metres.
@export var hunt_range: float = 9000.0


func get_faction() -> FactionDef:
	return faction if faction else Factions.scavengers()


func get_hull() -> float:
	return hull if hull >= 0.0 else get_faction().den_hull


func get_shields() -> float:
	return shields if shields >= 0.0 else get_faction().den_shields


func get_shield_regen() -> float:
	return shield_regen if shield_regen >= 0.0 else get_faction().den_shield_regen


func starts_present() -> bool:
	return arrival_order <= 0

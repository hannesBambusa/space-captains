class_name ShipStats
extends RefCounted
## Final numbers for one ship: the loadout base plus its modules, then the
## captain's attributes (Piloting, specialty skill). Read by Ship, the mover,
## the weapon and the AI. Rebuilt with [method ShipLoadout.derive].

var max_hull: float = 200.0
var max_shields: float = 0.0
var shield_regen: float = 0.0
## Sim seconds without damage before shields regenerate.
var shield_delay: float = 4.0
var max_speed: float = 150.0
var acceleration: float = 32.0
var turn_rate_deg: float = 110.0
var weapon_kind: ShipModule.WeaponKind = ShipModule.WeaponKind.NONE
var weapon_damage: float = 0.0
var weapon_range: float = 0.0
var fire_rate: float = 0.0
## 0..1 chance a shot hits a target that does not dodge.
var accuracy: float = 0.5
## 0..1 chance to dodge an incoming hit.
var dodge: float = 0.0
var drill_mult: float = 1.0
## Loads per trip (bigger holds carry more ore or scrap; pay scales with it).
var cargo: float = 1.0
## Materials per load multiplier.
var yield_mult: float = 1.0
## Hit chance added by modules (already in [member accuracy]).
var accuracy_bonus: float = 0.0
## Eject chance added by modules (see Captain.eject_chance).
var eject_bonus: float = 0.0
var sensor_range: float = 1500.0


func has_weapon() -> bool:
	return weapon_kind == ShipModule.WeaponKind.CANNON and weapon_damage > 0.0 and fire_rate > 0.0


## Damage per second at full accuracy.
func dps() -> float:
	return weapon_damage * fire_rate if has_weapon() else 0.0

class_name ShipModule
extends Resource
## One fitted module in a [ShipLoadout] slot. Tier 0 is the stock fitting a
## hull comes with; Mk I..III (tiers 1..3) are sold at the Outfitter
## (data/modules/*.tres), gated by the captain's rank and the Outfitter's
## unlocks. Captains choose them by personality (see [Outfitter]).
## Every stat is additive to the loadout base except the *_mult ones.

enum Slot { TOOL, CARGO, DEFENSE, ENGINE, SENSOR }
enum WeaponKind { NONE, DRILL, CANNON, MISSILE }

const SLOT_NAMES: PackedStringArray = ["Tool", "Cargo", "Defense", "Engine", "Sensor"]
const TIER_NAMES: PackedStringArray = ["Stock", "Mk I", "Mk II", "Mk III"]

@export var id: StringName = &""
@export var display_name: String = "Module"
@export var slot: Slot = Slot.TOOL
## 0 = stock fitting, 1..3 = Mk I..III.
@export_range(0, 3) var tier: int = 0
## Outfitter price, credits.
@export var cost: int = 0
## Roles that can fit it ("Miner", "Mercenary", "Salvager"). Empty = any.
@export var roles: PackedStringArray = []
## One-line description for tooltips.
@export var blurb: String = ""

@export_group("Defense")
@export var hull_bonus: float = 0.0
@export var shield_bonus: float = 0.0
## Shield points per second once regenerating.
@export var shield_regen: float = 0.0
## Added to the chance the captain ejects when the ship is destroyed.
@export var eject_bonus: float = 0.0

@export_group("Engine")
@export var speed_mult: float = 1.0
@export var accel_mult: float = 1.0
@export var turn_mult: float = 1.0

@export_group("Tool")
@export var weapon_kind: WeaponKind = WeaponKind.NONE
## Damage per shot.
@export var weapon_damage: float = 0.0
@export var weapon_range: float = 0.0
## Shots per second (both muzzles together).
@export var fire_rate: float = 0.0
## Drill time multiplier (mining and salvage tools).
@export var drill_mult: float = 1.0
## Fire rate multiplier (ammo racks).
@export var fire_rate_mult: float = 1.0

@export_group("Cargo and sensors")
## Loads the hold carries.
@export var cargo_bonus: float = 0.0
@export var sensor_range: float = 0.0
## Materials per load multiplier (prospecting scanners).
@export var yield_mult: float = 1.0
## Added to the hit chance per shot (targeting arrays).
@export var accuracy_bonus: float = 0.0


func get_tier_name() -> String:
	return TIER_NAMES[clampi(tier, 0, TIER_NAMES.size() - 1)]


func fits_role(role: String) -> bool:
	return roles.is_empty() or roles.has(role)

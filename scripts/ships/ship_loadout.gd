class_name ShipLoadout
extends Resource
## The hardware side of a ship: hull base values plus one module per slot
## (tool, cargo, defense, engine, sensor). Every hull starts with its role's
## stock fittings (data/loadouts/*.tres, tier 0). Captains buy Mk I..III
## modules at the Outfitter; [member unlocked_slots] (set from the captain's
## rank) caps how many slots may hold a bought module. Upgrading a slot that
## already holds one does not use another slot.
## [method derive] turns it into [ShipStats], applying the captain.

@export var role_name: String = ""

@export_group("Base")
@export var base_hull: float = 200.0
@export var base_shields: float = 0.0
@export var base_shield_regen: float = 0.0
@export var base_speed: float = 150.0
@export var base_acceleration: float = 32.0
@export var base_turn_rate_deg: float = 110.0
@export var base_cargo: float = 1.0
@export var base_sensor_range: float = 1500.0

@export_group("Slots")
@export var tool: ShipModule
@export var cargo: ShipModule
@export var defense: ShipModule
@export var engine: ShipModule
@export var sensor: ShipModule
## Slots that may hold a bought module (rank: 2 at Rookie up to 5).
@export_range(0, 5) var unlocked_slots: int = 5

const DEFAULT_PATHS := {
	"Miner": "res://data/loadouts/miner_default.tres",
	"Mercenary": "res://data/loadouts/mercenary_default.tres",
	"Scavenger": "res://data/loadouts/scavenger_default.tres",
	"Salvager": "res://data/loadouts/salvager_default.tres",
	"Lander": "res://data/loadouts/lander_default.tres",
	"Explorer": "res://data/loadouts/explorer_default.tres",
}
## Dropship research (Research autoload) for landers: more cargo per raid,
## tougher hulls.
const HEAVY_DROPSHIPS := &"pln_heavy_dropships"
const ARMOURED_DROPSHIPS := &"eng_armoured_dropships"
const HEAVY_CARGO_BONUS := 0.4
const ARMOURED_HULL_MULT := 1.4
const ARMOURED_SHIELD_BONUS := 60.0


## The module in [param slot], or null when the slot is empty.
func get_module(slot: ShipModule.Slot) -> ShipModule:
	match slot:
		ShipModule.Slot.TOOL:
			return tool
		ShipModule.Slot.CARGO:
			return cargo
		ShipModule.Slot.DEFENSE:
			return defense
		ShipModule.Slot.ENGINE:
			return engine
		ShipModule.Slot.SENSOR:
			return sensor
	return null


func set_module(slot: ShipModule.Slot, m: ShipModule) -> void:
	match slot:
		ShipModule.Slot.TOOL:
			tool = m
		ShipModule.Slot.CARGO:
			cargo = m
		ShipModule.Slot.DEFENSE:
			defense = m
		ShipModule.Slot.ENGINE:
			engine = m
		ShipModule.Slot.SENSOR:
			sensor = m


## Slots holding a bought (Mk I+) module.
func upgrades_fitted() -> int:
	var n := 0
	for m in modules():
		if m.tier >= 1:
			n += 1
	return n


## True when [param m] may go in now: an upgrade over what its slot holds,
## and a free unlocked slot unless it replaces a bought module. Never a
## module made for another role (see [method fits_hull]).
func can_fit(m: ShipModule) -> bool:
	if m == null or not fits_hull(m):
		return false
	var cur := get_module(m.slot)
	var cur_tier := cur.tier if cur else 0
	if m.tier <= cur_tier:
		return false
	return cur_tier >= 1 or upgrades_fitted() < unlocked_slots


## True when [param m] is made for this hull's role (stock parts always are).
func fits_hull(m: ShipModule) -> bool:
	return m != null and (m.tier <= 0 or role_name.is_empty() or m.fits_role(role_name))


func modules() -> Array[ShipModule]:
	var out: Array[ShipModule] = []
	for m in [tool, cargo, defense, engine, sensor]:
		if m != null:
			out.append(m)
	return out


## Stats for this loadout flown by [param captain] (null = average pilot).
func derive(captain: Captain = null) -> ShipStats:
	var s := ShipStats.new()
	s.max_hull = base_hull
	s.max_shields = base_shields
	s.shield_regen = base_shield_regen
	s.max_speed = base_speed
	s.acceleration = base_acceleration
	s.turn_rate_deg = base_turn_rate_deg
	s.cargo = base_cargo
	s.sensor_range = base_sensor_range
	var fire_mult := 1.0
	for m in modules():
		s.max_hull += m.hull_bonus
		s.max_shields += m.shield_bonus
		s.shield_regen += m.shield_regen
		s.max_speed *= m.speed_mult
		s.acceleration *= m.accel_mult
		s.turn_rate_deg *= m.turn_mult
		s.cargo += m.cargo_bonus
		s.sensor_range = maxf(s.sensor_range, m.sensor_range)
		s.eject_bonus += m.eject_bonus
		s.yield_mult *= m.yield_mult
		s.accuracy_bonus += m.accuracy_bonus
		fire_mult *= m.fire_rate_mult
		if m.slot == ShipModule.Slot.TOOL:
			s.weapon_kind = m.weapon_kind
			s.weapon_damage = m.weapon_damage
			s.weapon_range = m.weapon_range
			s.fire_rate = m.fire_rate
			s.drill_mult = m.drill_mult
	s.fire_rate *= fire_mult
	if role_name == "Mercenary":
		s.accuracy_bonus += Research.merc_accuracy()
	elif role_name == "Miner":
		s.cargo += Research.miner_hold()
	if role_name == "Lander":
		if Research.is_done(HEAVY_DROPSHIPS):
			s.cargo += HEAVY_CARGO_BONUS
		if Research.is_done(ARMOURED_DROPSHIPS):
			s.max_hull *= ARMOURED_HULL_MULT
			s.max_shields += ARMOURED_SHIELD_BONUS
	if captain:
		var p := captain.piloting_scale()
		s.max_speed *= p
		s.acceleration *= p
		s.turn_rate_deg *= p
		s.dodge = captain.dodge_chance()
		s.accuracy = clampf(captain.accuracy() + s.accuracy_bonus, 0.0, 0.97)
		s.weapon_damage *= captain.damage_scale()
		s.drill_mult *= captain.drill_time_scale()
	return s


## The default loadout for a role name ("Miner", "Mercenary", "Scavenger").
## Always returns a fresh copy, so stage 3 can change a ship's modules.
static func default_for(role: String) -> ShipLoadout:
	var path: String = DEFAULT_PATHS.get(role, "")
	if not path.is_empty() and ResourceLoader.exists(path):
		var l := load(path) as ShipLoadout
		if l:
			return l.duplicate(true) as ShipLoadout
	var fallback := ShipLoadout.new()
	fallback.role_name = role
	return fallback

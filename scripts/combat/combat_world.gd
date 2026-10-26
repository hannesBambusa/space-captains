class_name CombatWorld
extends Node3D
## Scene node that owns the shared combat systems: the tracer pool, the
## effects pool, the scrap fields, the raid director, the threat director (base arrivals), the planet claims, the defence zones
## and the colony alarm, and knows the
## station shield bubbles the tracers test against. Also the hub for
## combat events the UI listens to (spawns, deaths, scrap fields).
## Lives in scenes/system.tscn; every lookup is null-safe so scenes without
## it (the sector prototype) still run.

signal combatant_spawned(node: Node3D)
## A ship or den died. [param killer] may be null.
signal combatant_destroyed(node: Node3D, killer: Node3D)
signal scrap_changed

const GROUP := "combat_world"

## Scrap amount left by a destroyed ship / den.
@export var ship_scrap: int = 40
@export var den_scrap: int = 400
## Sim seconds a scrap field lasts (ships / dens).
@export var ship_scrap_life: float = 180.0
@export var den_scrap_life: float = 420.0

var projectiles: ProjectilePool
var fx: CombatFx
var raids: RaidDirector
var threats: ThreatDirector
## Faction planet claims: garrisons and re-claims (phase C3).
var claims: PlanetClaims
## Defence zones and the colony alarm (mercenaries answer attacks).
var zones: DefenseZones
var alarm: ColonyAlarm
var scrap_root: Node3D
## Station shield bubbles that stop hostile tracers (ProjectilePool).
var shields: Array[StationShield] = []


## The combat world of [param n]'s system (see [method SystemWorld.of]).
static func of(n: Node) -> CombatWorld:
	var w := SystemWorld.of(n)
	return w.combat if w else null


static func projectiles_of(n: Node) -> ProjectilePool:
	var w := of(n)
	return w.projectiles if w else null


static func fx_of(n: Node) -> CombatFx:
	var w := of(n)
	return w.fx if w else null


func _ready() -> void:
	add_to_group(GROUP)
	projectiles = ProjectilePool.new()
	projectiles.name = "Projectiles"
	add_child(projectiles)
	fx = CombatFx.new()
	fx.name = "Effects"
	add_child(fx)
	scrap_root = Node3D.new()
	scrap_root.name = "ScrapFields"
	add_child(scrap_root)
	raids = RaidDirector.new()
	raids.name = "RaidDirector"
	add_child(raids)
	threats = ThreatDirector.new()
	threats.name = "ThreatDirector"
	add_child(threats)
	claims = PlanetClaims.new()
	claims.name = "PlanetClaims"
	add_child(claims)
	zones = DefenseZones.new()
	zones.name = "DefenseZones"
	add_child(zones)
	alarm = ColonyAlarm.new()
	alarm.name = "ColonyAlarm"
	add_child(alarm)


func register_shield(s: StationShield) -> void:
	if not shields.has(s):
		shields.append(s)


func unregister_shield(s: StationShield) -> void:
	shields.erase(s)


func notify_spawned(node: Node3D) -> void:
	combatant_spawned.emit(node)


func notify_destroyed(node: Node3D, killer: Node3D) -> void:
	combatant_destroyed.emit(node, killer)


## Leaves a scrap field at [param pos] (world, on the plane).
func spawn_scrap(pos: Vector3, amount: int, life: float, radius: float, label: String) -> ScrapField:
	var f := ScrapField.new()
	f.setup(amount, life, radius, label)
	scrap_root.add_child(f)
	# Keeps the height: a wreck in a belt lane stays clear of the rocks.
	f.global_position = pos
	f.tree_exited.connect(func() -> void: scrap_changed.emit())
	scrap_changed.emit()
	return f


func get_scrap_fields() -> Array[ScrapField]:
	var out: Array[ScrapField] = []
	if scrap_root == null:
		return out
	for c in scrap_root.get_children():
		var f := c as ScrapField
		if f and not f.is_queued_for_deletion():
			out.append(f)
	return out

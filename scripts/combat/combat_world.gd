class_name CombatWorld
extends Node3D
## Scene node that owns the shared combat systems: the tracer pool, the
## effects pool, the scrap fields and the raid director, and knows the
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
var scrap_root: Node3D
## Station shield bubbles that stop hostile tracers (ProjectilePool).
var shields: Array[StationShield] = []


static func of(tree: SceneTree) -> CombatWorld:
	return tree.get_first_node_in_group(GROUP) as CombatWorld if tree else null


static func projectiles_of(tree: SceneTree) -> ProjectilePool:
	var w := of(tree)
	return w.projectiles if w else null


static func fx_of(tree: SceneTree) -> CombatFx:
	var w := of(tree)
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

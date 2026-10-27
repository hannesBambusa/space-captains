class_name CombatWorld
extends Node3D
## Scene node that owns the shared combat systems: the tracer pool, the
## effects pool, the scrap fields, the raid director, the threat director (base arrivals), the planet claims, the defence zones
## and the colony alarm, and knows the
## station shield bubbles the tracers test against. Also the hub for
## combat events the UI listens to (spawns, deaths, scrap fields).
## Lives in scenes/system.tscn; every lookup is null-safe so scenes without
## it (the sector prototype) still run. In a system without a station
## ([member has_station] false: remote systems, previews) only the pools and
## scrap exist: no raid or threat director, defence zones or alarm (all
## null). Planet claims and gate raids are home's only ([member is_home]).
## At a forward station (F4) the raid director counts from the founding
## (RaidDirector.start_offset), sends its first raid after
## [member forward_raid_grace] with waves from the system's danger, and the
## threat director brings no new bases (ThreatDirector.arrivals off).

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
## A forward station's first raid: this long after its founding, sim seconds.
@export var forward_raid_grace: float = 600.0

var projectiles: ProjectilePool
var fx: CombatFx
var raids: RaidDirector
var threats: ThreatDirector
## Raids through the jump gates from dangerous systems nearby (P4, home only).
var gate_raids: GateRaidSource
## Faction planet claims: garrisons and re-claims (phase C3).
var claims: PlanetClaims
## Defence zones and the colony alarm (mercenaries answer attacks).
var zones: DefenseZones
var alarm: ColonyAlarm
var scrap_root: Node3D
## Station shield bubbles that stop hostile tracers (ProjectilePool).
var shields: Array[StationShield] = []
## In the player's home system (set from its SystemWorld when ready).
var is_home := true
## In a system with a station (home or forward, SystemWorld.has_station).
var has_station := true


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
	var w := SystemWorld.of(self)
	is_home = w == null or w.is_home
	has_station = w == null or w.has_station
	if not has_station:
		return
	raids = RaidDirector.new()
	raids.name = "RaidDirector"
	threats = ThreatDirector.new()
	threats.name = "ThreatDirector"
	if not is_home and w:
		raids.start_offset = float(w.station_site.get("founded_at", SimClock.time))
		raids.first_raid_time = forward_raid_grace
		var def := Sector.system_def(w.system_id)
		raids.danger = def.danger if def else 1
		threats.arrivals = false
	add_child(raids)
	add_child(threats)
	if is_home:
		claims = PlanetClaims.new()
		claims.name = "PlanetClaims"
		add_child(claims)
	zones = DefenseZones.new()
	zones.name = "DefenseZones"
	add_child(zones)
	alarm = ColonyAlarm.new()
	alarm.name = "ColonyAlarm"
	add_child(alarm)
	if not is_home:
		return
	gate_raids = GateRaidSource.new()
	gate_raids.name = "GateRaidSource"
	add_child(gate_raids)


func register_shield(s: StationShield) -> void:
	if not shields.has(s):
		shields.append(s)


func unregister_shield(s: StationShield) -> void:
	shields.erase(s)


func notify_spawned(node: Node3D) -> void:
	combatant_spawned.emit(node)


func notify_destroyed(node: Node3D, killer: Node3D) -> void:
	combatant_destroyed.emit(node, killer)


## Leaves a scrap field at [param pos] (world, on the plane), moving with
## the frame it was made in ([method ScrapField.pick_anchor]; [param source]
## is the dying node).
func spawn_scrap(pos: Vector3, amount: int, life: float, radius: float, label: String, source: Node = null) -> ScrapField:
	var f := ScrapField.new()
	f.setup(amount, life, radius, label)
	scrap_root.add_child(f)
	# Keeps the height: a wreck in a belt lane stays clear of the rocks.
	f.global_position = pos
	f.anchor_to(ScrapField.pick_anchor(self, pos, source))
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

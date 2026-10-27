class_name FogOfWar
extends Node
## Fog of war of one live remote system (P3; SystemHost adds it as a child
## of the SystemWorld). Only what explorers revealed (the system's
## RemoteSystemState.revealed, by name: planets with their moons, clusters,
## bases, derelicts, gates) is shown: the rest is hidden in 3D (the node with its
## label; a planet's orbit line too), and the HUD (minimap, ship markers,
## overview, picking) skips hidden nodes. Raider ships and scrap show only
## within the sweep radius of one of the player's ships there. The star
## always shows. Updates at once when Sector reveals something here, so a
## viewed system fills in live as its explorer sweeps it.
## [method is_revealed] is the test the UI uses for data rows.

## Raiders and scrap show within this of a player's ship, metres.
const SIGHT := 12000.0
const INTERVAL := 0.25

var _timer := 0.0


## True when [param n] (a planet, moon, cluster, base or gate) may be shown:
## always in a station system (home, forward), else when its name is revealed. Other nodes: true.
static func is_revealed(n: Node) -> bool:
	var w := SystemWorld.of(n)
	if w == null or w.has_station or w.system_id.is_empty():
		return true
	var key := key_of(n)
	return key.is_empty() or Sector.is_revealed(w.system_id, key)


## The revealed-list name of [param n], "" for things the fog does not track.
static func key_of(n: Node) -> String:
	if n is PlanetBody:
		return (n as PlanetBody).def.name
	if n is AsteroidCluster:
		return (n as AsteroidCluster).def.name
	if n is JumpGate:
		return (n as JumpGate).def.name if (n as JumpGate).def else ""
	if n is Derelict:
		return (n as Derelict).def.name if (n as Derelict).def else ""
	if n is ScavengerDen and not (n is ClaimGarrison):
		return (n as ScavengerDen).def.name if (n as ScavengerDen).def else ""
	return ""


func _ready() -> void:
	Sector.revealed.connect(_on_revealed)
	apply()


func _exit_tree() -> void:
	if Sector.revealed.is_connected(_on_revealed):
		Sector.revealed.disconnect(_on_revealed)


func _on_revealed(id: StringName, _names: PackedStringArray) -> void:
	var w := get_parent() as SystemWorld
	if w and w.system_id == id:
		apply()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = INTERVAL
		_apply_sight()


## Shows and hides the bodies, clusters, bases and gates.
func apply() -> void:
	var w := get_parent() as SystemWorld
	var sys := w.sys if w else null
	if sys == null:
		return
	var id := w.system_id
	for p in sys.planets:
		var on := Sector.is_revealed(id, p.def.name)
		p.visible = on
		var line := sys.orbit_line_of(p)
		if line:
			line.visible = on
	for b in sys.belts:
		b.visible = Sector.is_revealed(id, b.def.name)
	for g in sys.gates:
		g.visible = Sector.is_revealed(id, g.def.name)
	for d in sys.dens:
		if is_instance_valid(d) and d.def:
			d.visible = Sector.is_revealed(id, d.def.name)
	for x in sys.derelicts:
		if is_instance_valid(x) and x.def:
			x.visible = Sector.is_revealed(id, x.def.name)
	_apply_sight()


## Raiders and scrap fields near one of the player's ships.
func _apply_sight() -> void:
	var w := get_parent() as SystemWorld
	if w == null:
		return
	var eyes: Array[Vector3] = []
	for n in SystemWorld.nodes_in(w, Ship.GROUP):
		var s := n as Ship
		if s and not s.dead and s.faction == Combat.Faction.PLAYER and s.is_inside_tree():
			eyes.append(s.global_position)
	for n in SystemWorld.nodes_in(w, Ship.GROUP):
		var s := n as Ship
		if s and s.faction != Combat.Faction.PLAYER:
			s.visible = _seen(s.global_position, eyes)
	for n in SystemWorld.nodes_in(w, ScrapField.GROUP):
		var f := n as Node3D
		if f:
			f.visible = _seen(f.global_position, eyes)


static func _seen(p: Vector3, eyes: Array[Vector3]) -> bool:
	for e in eyes:
		if SpaceNav.flat_distance(p, e) <= SIGHT:
			return true
	return false

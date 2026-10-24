class_name RaidDirector
extends Node
## Sends scavenger raids toward the player's structures now and then. The
## first raid comes after [member first_raid_time]; then one every
## [member raid_interval] (+- jitter). Waves grow slowly: [member base_wave]
## plus one raider per [member growth_time] of sim time, up to
## [member max_wave]. Raiders come from a living den, beyond its spawn cap.
## Needs at least one player building (nothing to raid otherwise).
## Factions: a raid first picks a faction among those with a living base
## whose FactionDef.raid_after has passed, by FactionDef.raid_weight
## (no roll while only one qualifies, so the early game is the scavengers'
## alone as before), then one of its bases. A faction with a raid_size
## sends that many (Syndicate 3-5, rarer by weight; Corsairs a pair)
## instead of the growing wave, launched in its packs.
## Only bases that have arrived exist (ThreatDirector), so a faction raids
## once its first base is in; a base that just arrived waits
## SystemDef.arrival_raid_grace before it sends raiders.

signal raid_started(den: ScavengerDen, size: int)

@export var enabled: bool = true
@export var first_raid_time: float = 420.0
@export var raid_interval: float = 330.0
@export var raid_jitter: float = 60.0
@export var base_wave: int = 1
@export var growth_time: float = 600.0
@export var max_wave: int = 6

var raids_sent: int = 0
var _next_raid: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(SimStepper.GROUP)
	_rng.randomize()
	_next_raid = SimClock.time + first_raid_time


func _process(_delta: float) -> void:
	if not SimClock.paused:
		sim_step(0.0)


func sim_step(_dt: float) -> void:
	if not enabled or SimClock.time < _next_raid:
		return
	_next_raid = SimClock.time + raid_interval + _rng.randf_range(-raid_jitter, raid_jitter)
	var mgr := get_tree().get_first_node_in_group(BuildingManager.GROUP) as BuildingManager
	if mgr == null or mgr.buildings.is_empty():
		return
	var den := pick_den()
	if den:
		trigger_raid(size_for(den), den)


func wave_size() -> int:
	return clampi(base_wave + int(SimClock.time / growth_time), 1, max_wave)


## Raid size from [param den]: its faction's range, else the growing wave.
func size_for(den: ScavengerDen) -> int:
	var r := den.faction_def.raid_size
	if r.x <= 0:
		return wave_size()
	return _rng.randi_range(r.x, maxi(r.y, r.x))


## A living base to raid from (see the class notes), or null.
func pick_den() -> ScavengerDen:
	var by_faction: Dictionary = {}
	var order: Array[FactionDef] = []
	var sys := get_tree().get_first_node_in_group(SolarSystem.GROUP) as SolarSystem
	var grace := sys.system_def.arrival_raid_grace if sys and sys.system_def else 0.0
	for n in get_tree().get_nodes_in_group(ScavengerDen.GROUP):
		var d := n as ScavengerDen
		if d == null or not d.is_alive() or SimClock.time - d.arrived_at < grace:
			continue
		var f := d.faction_def
		if f.raid_weight <= 0.0 or SimClock.time < f.raid_after:
			continue
		if not by_faction.has(f):
			by_faction[f] = [] as Array[ScavengerDen]
			order.append(f)
		(by_faction[f] as Array[ScavengerDen]).append(d)
	if order.is_empty():
		return null
	var pick := order[0]
	if order.size() > 1:
		var total := 0.0
		for f in order:
			total += f.raid_weight
		var roll := _rng.randf() * total
		for f in order:
			roll -= f.raid_weight
			pick = f
			if roll <= 0.0:
				break
	var live: Array[ScavengerDen] = by_faction[pick]
	return live[_rng.randi() % live.size()]


## Sends a raid of [param size] ships now. Returns the raiders.
func trigger_raid(size: int, from_den: ScavengerDen = null) -> Array[ScavengerShip]:
	var out: Array[ScavengerShip] = []
	var den := from_den
	if den == null:
		den = pick_den()
		if den == null:
			return out
	var pack := den.faction_def.pack_size
	while out.size() < size:
		var group := den.spawn_pack(mini(pack, size - out.size()), true)
		if group.is_empty():
			break
		out.append_array(group)
	if not out.is_empty():
		raids_sent += 1
		raid_started.emit(den, out.size())
		EventLog.post("%s raid incoming (%d from %s)" % [den.faction_def.unit_name, out.size(), den.get_display_name()], EventLog.Kind.THREAT, out[0],
				Vector3.INF, "", den.faction_def.id)
	return out


# --- Save ---------------------------------------------------------------------

func save_state() -> Dictionary:
	return {"enabled": enabled, "raids_sent": raids_sent, "next_raid": _next_raid, "rng": SaveUtil.rng_state(_rng)}


func load_state(d: Dictionary) -> void:
	enabled = bool(d.get("enabled", enabled))
	raids_sent = int(d.get("raids_sent", 0))
	_next_raid = float(d.get("next_raid", _next_raid))
	SaveUtil.set_rng(_rng, d.get("rng", {}))

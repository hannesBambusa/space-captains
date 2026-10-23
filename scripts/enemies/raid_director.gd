class_name RaidDirector
extends Node
## Sends scavenger raids toward the player's structures now and then. The
## first raid comes after [member first_raid_time]; then one every
## [member raid_interval] (+- jitter). Waves grow slowly: [member base_wave]
## plus one raider per [member growth_time] of sim time, up to
## [member max_wave]. Raiders come from a living den, beyond its spawn cap.
## Needs at least one player building (nothing to raid otherwise).

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
	trigger_raid(wave_size())


func wave_size() -> int:
	return clampi(base_wave + int(SimClock.time / growth_time), 1, max_wave)


## Sends a raid of [param size] ships now. Returns the raiders.
func trigger_raid(size: int, from_den: ScavengerDen = null) -> Array[ScavengerShip]:
	var out: Array[ScavengerShip] = []
	var den := from_den
	if den == null:
		var live: Array[ScavengerDen] = []
		for n in get_tree().get_nodes_in_group(ScavengerDen.GROUP):
			var d := n as ScavengerDen
			if d and d.is_alive():
				live.append(d)
		if live.is_empty():
			return out
		den = live[_rng.randi() % live.size()]
	for i in size:
		var s := den.spawn(true)
		if s:
			out.append(s)
	if not out.is_empty():
		raids_sent += 1
		raid_started.emit(den, out.size())
		EventLog.post("Scavenger raid incoming (%d from %s)" % [out.size(), den.get_display_name()], EventLog.Kind.THREAT, out[0])
	return out

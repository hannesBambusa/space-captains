class_name MiningContract
extends LoadContract
## Mine an asteroid cluster ([member belt]): the player pays [member reward]
## credits for every load a miner delivers to its outpost; the ore turns
## into materials (MiningRules). Capped by [member max_loads] (see
## [LoadContract]). A cluster holds a finite reserve: no new trips
## once it has nothing left for them; when it is mined out the contract
## completes as soon as the last trip on it ends (nothing is held in escrow,
## so nothing is refunded).

var belt: AsteroidCluster
var ore_type: AsteroidBelt.OreType = AsteroidBelt.OreType.IRON
var materials_delivered: int = 0
## The cluster ran out: no new takers, done once the last trip ends.
var depleted: bool = false
## Cluster name, kept for the feed and lists after the cluster is gone.
var site_name: String = ""


func _init(on_belt: AsteroidCluster = null, credits_per_load: int = 0, load_limit: int = 0) -> void:
	type = Type.MINING
	belt = on_belt
	target = on_belt
	reward = credits_per_load
	max_loads = maxi(load_limit, 0)
	if on_belt and on_belt.def:
		ore_type = on_belt.def.ore_type
		site_name = on_belt.def.name
		on_belt.depleted.connect(func(_b: AsteroidCluster) -> void: mark_depleted())
		# The cluster leaves the system once it has faded: drop the reference.
		on_belt.tree_exiting.connect(_on_belt_gone)
		if on_belt.is_depleted:
			depleted = true


func is_available() -> bool:
	if depleted or not super.is_available():
		return false
	return not (is_instance_valid(belt) and not belt.has_ore_for_new_trip())


func _is_exhausted() -> bool:
	return depleted


func _on_belt_gone() -> void:
	if target == belt:
		target = null
	belt = null


## The cluster is mined out: no new trips; completes once the last ends.
func mark_depleted() -> void:
	depleted = true
	_complete_when_idle()


func get_target_name() -> String:
	if is_instance_valid(belt) and belt.def:
		return belt.def.name
	return site_name if not site_name.is_empty() else super.get_target_name()


func get_progress_text() -> String:
	var text := "%d / %d loads" % [loads_delivered, max_loads] if max_loads > 0 else "%d loads" % loads_delivered
	if depleted:
		return text + ", mined out"
	return text


## The edge of the cluster facing [param from] (the asker's outpost; the
## home station for markers).
func get_site_position(from: Vector3 = Vector3.ZERO) -> Vector3:
	if not is_instance_valid(belt):
		return Vector3.ZERO
	return SpaceNav.nearest_belt_point(belt, from)


func get_danger() -> int:
	return belt.danger if is_instance_valid(belt) else 1


## Escorted contract: miners on it waiting in the berth with no escort
## assigned (CaptainBrain WAITING_ESCORT).
func escort_waiting_count() -> int:
	var ec := ContractBoard.escort_for_mining(self)
	if ec == null:
		return 0
	var n := 0
	for t in takers:
		var s := t as Ship
		if is_instance_valid(s) and not s.dead and s.brain and s.brain.state == CaptainBrain.State.WAITING_ESCORT and ec.escorts_of(s).is_empty():
			n += 1
	return n


func get_warning_text() -> String:
	var n := escort_waiting_count()
	return "" if n == 0 else "No escort: %d miner%s waiting" % [n, "" if n == 1 else "s"]


func get_warning_hint() -> String:
	return "Hire mercenaries or raise escort pay" if escort_waiting_count() > 0 else ""

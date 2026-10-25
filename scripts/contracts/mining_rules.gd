class_name MiningRules
extends Resource
## Tuning for mining contracts: what a load is worth in materials, the fair
## default reward per load, the posting UI range and mining times.
## Arrays are indexed by AsteroidBelt.OreType (ROCK, IRON, TITANIUM, CRYSTAL).

## Materials per full load, per ore.
@export var materials_per_load: PackedInt32Array = [4, 10, 25, 60]
## Fair reward per load for a danger-1 belt, per ore.
@export var base_reward: PackedInt32Array = [20, 50, 90, 150]
## Added to the fair reward per danger level above 1.
@export var danger_premium: int = 15
## Sim seconds of drilling per load, per ore.
@export var mine_time: PackedFloat32Array = [10.0, 14.0, 18.0, 24.0]

@export_group("Posting UI")
@export var reward_min: int = 20
@export var reward_max: int = 400
@export var reward_step: int = 10
## Load-limit choices offered when posting. 0 = no limit.
@export var load_limit_options: PackedInt32Array = [0, 3, 5, 10, 20, 50]


func materials_for(ore: int) -> int:
	return materials_per_load[clampi(ore, 0, materials_per_load.size() - 1)]


func mine_time_for(ore: int) -> float:
	return mine_time[clampi(ore, 0, mine_time.size() - 1)]


## Fair reward for one load from [param belt], snapped to the UI step.
func default_reward(belt: AsteroidCluster) -> int:
	if belt == null or belt.def == null:
		return reward_min
	var raw := base_reward[clampi(belt.ore_type, 0, base_reward.size() - 1)] + danger_premium * maxi(belt.danger - 1, 0)
	return clamp_reward(raw)


func clamp_reward(value: int) -> int:
	var snapped_value := int(round(float(value) / float(reward_step))) * reward_step
	return clampi(snapped_value, reward_min, reward_max)

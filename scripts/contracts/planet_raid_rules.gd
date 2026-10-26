class_name PlanetRaidRules
extends Resource
## Tuning for planet raids (phase C2): what each planet type yields, the fair
## pay per load, how long a dropship spends on the surface and how
## dangerous the trip is. Arrays are indexed by PlanetDef.Type (ROCKY,
## OCEAN, DESERT, ICE, LAVA, GAS_GIANT). Data: data/contracts/planet_raid_rules.tres.
## A planet's yield per load = units_per_load (type) x size factor (radius)
## x richness (stable per planet, from its seed); a dropship's cargo stat
## multiplies it like a miner's hold.
## Danger 1..5: the type's base, plus one past [member far_km] and two past
## [member deep_km] from home, at least what nearby hostile bases and belts
## give the spot (SalvageContract.danger_at). C4 adds planet defences.

## Loot per type (Economy.Ore): rocky heavy ore, ocean water, desert
## silicates, ice water, lava rare metals, gas giant fuel.
@export var loot: PackedInt32Array = [7, 4, 6, 4, 5, 3]
## Units of loot per full load, per type, before size and richness.
@export var units_per_load: PackedInt32Array = [44, 36, 34, 48, 18, 26]
## Fair reward per load at danger 1, per type.
@export var base_reward: PackedInt32Array = [90, 80, 100, 90, 120, 120]
## Added to the fair reward per danger level above 1.
@export var danger_premium: int = 20
## Base danger per type (lava and gas giants are rough landings).
@export var base_danger: PackedInt32Array = [1, 1, 1, 1, 2, 2]
## Sim seconds on the surface per load, per type.
@export var surface_time: PackedFloat32Array = [26.0, 22.0, 24.0, 26.0, 32.0, 28.0]
## Size factor: radius / size_ref, clamped to size_range.
@export var size_ref: float = 900.0
@export var size_range: Vector2 = Vector2(0.8, 1.35)
## Richness per planet, from its seed: this range.
@export var richness_range: Vector2 = Vector2(0.85, 1.25)
## Distance from home (km) that adds one and two danger levels.
@export var far_km: float = 15.0
@export var deep_km: float = 30.0

@export_group("Flight")
## Sim seconds to dive from orbit to the surface, and to climb back out.
@export var descent_time: float = 14.0
@export var climb_time: float = 12.0

@export_group("Posting UI")
@export var reward_min: int = 40
@export var reward_max: int = 500
@export var reward_step: int = 10
## Load-limit choices offered when posting. 0 = no limit.
@export var load_limit_options: PackedInt32Array = [0, 3, 5, 10, 20]


func _i(t: int) -> int:
	return clampi(t, 0, PlanetDef.Type.size() - 1)


## Economy.Ore looted on a planet of [param def].
func loot_of(def: PlanetDef) -> int:
	return loot[_i(def.type)] if def else Economy.Ore.HEAVY_ORE


## 0.85..1.25, stable per planet (its seed and name).
func richness_of(def: PlanetDef) -> float:
	if def == null:
		return 1.0
	var h := float(absi(hash("%s/%.3f" % [def.name, def.seed])) % 1000) / 999.0
	return lerpf(richness_range.x, richness_range.y, h)


func size_factor(def: PlanetDef) -> float:
	return clampf(def.radius / maxf(size_ref, 1.0), size_range.x, size_range.y) if def else 1.0


## Units per full load from [param def] (before the dropship's cargo stat).
func base_yield(def: PlanetDef) -> int:
	if def == null:
		return 0
	return maxi(roundi(float(units_per_load[_i(def.type)]) * size_factor(def) * richness_of(def)), 1)


func surface_time_of(def: PlanetDef) -> float:
	return surface_time[_i(def.type)] if def else 25.0


## Danger 1..5 of raiding [param body], from home at [param home].
func danger_of(body: PlanetBody, home: Vector3) -> int:
	if body == null or not is_instance_valid(body) or not body.is_inside_tree():
		return 1
	var d := base_danger[_i(body.def.type)]
	var km := SpaceNav.flat_distance(body.global_position, home) / 1000.0
	if km > deep_km:
		d += 2
	elif km > far_km:
		d += 1
	d = maxi(d, SalvageContract.danger_at(body, body.global_position))
	return clampi(d, 1, 5)


## Fair reward for one load from [param body] at [param danger], snapped.
func fair_reward(def: PlanetDef, danger: int) -> int:
	if def == null:
		return reward_min
	return clamp_reward(base_reward[_i(def.type)] + danger_premium * maxi(danger - 1, 0))


func clamp_reward(value: int) -> int:
	var snapped_value := int(round(float(value) / float(reward_step))) * reward_step
	return clampi(snapped_value, reward_min, reward_max)

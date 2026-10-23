class_name Reputation
extends RefCounted
## Reputation ranks (no levels). Captains earn reputation from deeds; the
## rank only unlocks hardware, never raw stats:
##   rank      reputation  module slots  max module tier
##   Rookie         0           2           Mk I
##   Licensed      50           3           Mk I
##   Veteran      200           4           Mk II
##   Ace          600           5           Mk III
##   Legend      1500           5           Mk III
## Pace: a decent miner (a load every ~90 sim seconds on a near belt) is
## Licensed after ~5 sim minutes, Veteran after ~20 and Ace after ~60.
## Dens and fights pay more.

enum Rank { ROOKIE, LICENSED, VETERAN, ACE, LEGEND }

const RANK_NAMES: PackedStringArray = ["Rookie", "Licensed", "Veteran", "Ace", "Legend"]
## Short badge for lists.
const RANK_BADGES: PackedStringArray = ["RKE", "LIC", "VET", "ACE", "LGD"]
const RANK_COLORS: Array[Color] = [
	Color(0.62, 0.66, 0.72), Color(0.55, 0.85, 1.0), Color(0.6, 1.0, 0.68), Color(1.0, 0.82, 0.35), Color(1.0, 0.55, 0.9),
]
const THRESHOLDS: PackedFloat32Array = [0.0, 50.0, 200.0, 600.0, 1500.0]
const SLOTS: PackedInt32Array = [2, 3, 4, 5, 5]
const MAX_TIER: PackedInt32Array = [1, 1, 2, 3, 3]

## Deeds, reputation points.
const LOAD := 15.0
## Added per load by ore (rock, iron, titanium, crystal).
const ORE_BONUS: PackedFloat32Array = [0.0, 2.0, 5.0, 9.0]
## Added per load per danger level above 1.
const DANGER_BONUS := 2.0
const KILL := 20.0
## Den kill: the killer gets [constant DEN], every other attacker [constant DEN_ASSIST].
const DEN := 200.0
const DEN_ASSIST := 100.0
const ESCORT_TRIP := 10.0
const SALVAGE_LOAD := 14.0
const SURVIVED_FIGHT := 6.0
const EJECTED := 12.0


static func rank_for(rep: float) -> int:
	var r := 0
	for i in THRESHOLDS.size():
		if rep >= THRESHOLDS[i]:
			r = i
	return r


static func rank_name(rank: int) -> String:
	return RANK_NAMES[clampi(rank, 0, RANK_NAMES.size() - 1)]


static func slots_for(rank: int) -> int:
	return SLOTS[clampi(rank, 0, SLOTS.size() - 1)]


static func max_tier_for(rank: int) -> int:
	return MAX_TIER[clampi(rank, 0, MAX_TIER.size() - 1)]


## Reputation needed for the next rank (INF at Legend).
static func next_threshold(rank: int) -> float:
	return THRESHOLDS[rank + 1] if rank + 1 < THRESHOLDS.size() else INF


## 0..1 progress from the current rank to the next (1 at Legend).
static func progress(rep: float) -> float:
	var r := rank_for(rep)
	if r + 1 >= THRESHOLDS.size():
		return 1.0
	return clampf((rep - THRESHOLDS[r]) / (THRESHOLDS[r + 1] - THRESHOLDS[r]), 0.0, 1.0)


## Reputation for one delivered mining load.
static func for_load(ore: int, danger: int) -> float:
	return LOAD + ORE_BONUS[clampi(ore, 0, ORE_BONUS.size() - 1)] + DANGER_BONUS * float(maxi(danger - 1, 0))

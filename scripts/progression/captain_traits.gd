class_name CaptainTraits
extends RefCounted
## The trait table. Traits come from events (see Captain and the hooks in
## the brains, ships and ContractBoard), at most [constant MAX_TRAITS] at a
## time; fading ones expire after their sim time. Each has one small effect:
##   Survivor       near-loss survived or ejected: +10% eject chance, and the
##                  danger term weighs 10% less
##   Shaken         badly damaged: Nerve counts 3 lower until it fades
##   Crystal Hound  many crystal loads: crystal mining contracts score +0.3
##   Grudge         wingmate killed by scavengers: scavenger bounties score
##                  +40% pay, patrols more often, flees later; fades
##   Lone Wolf      works alone: escort cover means nothing to them, solo
##                  work scores +0.1, escort jobs -0.25, Teamwork 3 lower
##   Union Rep      loyal long service: keeps 4% more of each payment; pay
##                  below fair scores -0.35 (sulks), Teamwork 2 higher

const MAX_TRAITS := 3

const SURVIVOR := &"survivor"
const SHAKEN := &"shaken"
const CRYSTAL_HOUND := &"crystal_hound"
const GRUDGE := &"grudge"
const LONE_WOLF := &"lone_wolf"
const UNION_REP := &"union_rep"

## id -> {name, tip, fade (sim seconds, 0 = stays), good (for the colour)}
const INFO := {
	&"survivor": {"name": "Survivor", "tip": "Lived through a near-loss. +10% eject chance; weighs danger a little less.", "fade": 0.0, "good": true},
	&"shaken": {"name": "Shaken", "tip": "Badly damaged recently. Nerve counts 3 lower until it fades.", "fade": 300.0, "good": false},
	&"crystal_hound": {"name": "Crystal Hound", "tip": "Has hauled a lot of crystal. Prefers crystal belts.", "fade": 0.0, "good": true},
	&"grudge": {"name": "Grudge", "tip": "Lost a wingmate to raiders (scavengers, corsairs or the Syndicate). Hunts them harder; fades in time.", "fade": 900.0, "good": true},
	&"lone_wolf": {"name": "Lone Wolf", "tip": "Works alone. Ignores escort cover, dislikes escort jobs and fleets (Teamwork -3).", "fade": 0.0, "good": true},
	&"union_rep": {"name": "Union Rep", "tip": "Long, loyal service. Keeps 4% more of each payment; sulks at below-fair pay. Teamwork +2.", "fade": 0.0, "good": true},
}

## Thresholds for earning them.
## Survivor: back home after the hull fell below this share (or ejected).
const SURVIVOR_HULL := 0.2
## Shaken: back home after the hull fell below this share.
const SHAKEN_HULL := 0.4
const CRYSTAL_LOADS := 6
## Lone Wolf: this many solo jobs with at most [constant LONE_WOLF_TEAM_SHARE] escorted.
const LONE_WOLF_JOBS := 12
const LONE_WOLF_TEAM_SHARE := 0.15
const UNION_LOYALTY := 7
## Union Rep: sim seconds of service.
const UNION_SERVICE := 900.0
## Grudge: player ships this close to a loss to scavengers take it personally, metres.
const GRUDGE_RADIUS := 2500.0


static func trait_name(id: StringName) -> String:
	return String((INFO.get(id, {}) as Dictionary).get("name", String(id)))


static func tip(id: StringName) -> String:
	return String((INFO.get(id, {}) as Dictionary).get("tip", ""))


static func fade_time(id: StringName) -> float:
	return float((INFO.get(id, {}) as Dictionary).get("fade", 0.0))


static func is_good(id: StringName) -> bool:
	return bool((INFO.get(id, {}) as Dictionary).get("good", true))

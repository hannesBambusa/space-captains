class_name OutpostState
extends RefCounted
## One planet outpost as plain data (planet outposts plan): kept in
## Sector.outposts (saved with the cluster), stepped as data by [Outposts]
## while nobody views the surface, and the source the live surface world
## ([SurfaceWorld]) is built from and written back to.
##
## The landing zone is [constant ZONE_SIZE] metres square with the landing
## pad at the centre. Positions are zone-local (x, z) in metres; heights come
## from the terrain ([SurfaceTerrain], seeded by [member seed]).
##
## Goods by planet type ([constant GOODS]): ice and ocean worlds give water,
## desert silicates, rocky heavy ore, lava rare metals. Gas giants have no
## outpost.

## Building kinds.
const PAD := &"landing_pad"
const BAY := &"harvester_bay"
const GARRISON := &"garrison"
const TURRET := &"ground_turret"
const DOME := &"shield_dome"
## Crew roles.
const HARVESTER := "Harvester"
const SOLDIER := "Soldier"

const ZONE_SIZE := 4000.0
## Buildings stand within this of the pad, with this gap between footprints.
const BASE_RADIUS := 700.0
const BUILD_GAP := 40.0
## Deposits lie this far from the pad.
const DEPOSIT_RANGE := Vector2(500.0, 1700.0)
const DEPOSITS := Vector2i(3, 5)
## Seconds after a deposit ran out before a new one turns up (while fewer than the minimum).
const DEPOSIT_RESPAWN := 240.0

## Planet type (PlanetDef.Type) -> good (Economy.Ore); -1 = no outpost.
## Gas giants: a floating platform over the cloud deck, harvesting fuel
## from gas pockets (the only steady fuel source; Mk III drives need it).
const GOODS := [Economy.Ore.HEAVY_ORE, Economy.Ore.WATER, Economy.Ore.SILICATES, Economy.Ore.WATER, Economy.Ore.RARE_METALS, Economy.Ore.FUEL]
## Units per harvester load, by good (Economy.Ore index).
## Tuned so a load is worth about 180 to 225 cr at the Factory's mid price
## (water ~6.5, silicates ~9, heavy ore ~7.5, rare metals ~25, fuel ~14): 2 harvesters
## at fair pay net about 200 cr/min after upkeep (planet outposts plan, S5).
const LOAD_UNITS := {Economy.Ore.WATER: 30, Economy.Ore.SILICATES: 22, Economy.Ore.HEAVY_ORE: 26, Economy.Ore.RARE_METALS: 9, Economy.Ore.FUEL: 14}
## Fair pay per load at danger 1, by good, and the premium per danger level above it.
const FAIR_PAY := {Economy.Ore.WATER: 50, Economy.Ore.SILICATES: 55, Economy.Ore.HEAVY_ORE: 50, Economy.Ore.RARE_METALS: 70, Economy.Ore.FUEL: 60}
const DANGER_PREMIUM := 15
## Loads per deposit.
const DEPOSIT_LOADS := Vector2i(20, 40)
## Deposit look and name by good.
const DEPOSIT_NAMES := {Economy.Ore.WATER: "ice field", Economy.Ore.SILICATES: "silica dunes", Economy.Ore.HEAVY_ORE: "ore seam", Economy.Ore.RARE_METALS: "magma vent", Economy.Ore.FUEL: "gas pocket"}

## Costs: credits, iron, titanium; build seconds; hull; berths (hiring buildings).
const BUILDINGS := {
	PAD: {"name": "Landing Pad", "credits": 0, "iron": 0, "ti": 0, "time": 0.0, "hull": 3000.0, "radius": 60.0},
	BAY: {"name": "Harvester Bay", "credits": 500, "iron": 40, "ti": 0, "time": 20.0, "hull": 1200.0, "radius": 45.0, "role": HARVESTER, "berths": 4, "hire": 200},
	GARRISON: {"name": "Garrison", "credits": 600, "iron": 50, "ti": 30, "time": 25.0, "hull": 1400.0, "radius": 45.0, "role": SOLDIER, "berths": 4, "hire": 300},
	TURRET: {"name": "Ground Turret", "credits": 250, "iron": 30, "ti": 0, "time": 15.0, "hull": 800.0, "radius": 18.0},
	DOME: {"name": "Shield Dome", "credits": 600, "iron": 60, "ti": 60, "time": 30.0, "hull": 1500.0, "radius": 30.0, "max": 1},
}
const BUILD_ORDER: Array[StringName] = [BAY, GARRISON, TURRET, DOME]

## Founding cost and time, upkeep per sim minute.
const FOUND_CREDITS := 1500
const FOUND_IRON := 100
const FOUND_TITANIUM := 50
const FOUND_TIME := 60.0
const UPKEEP := 20.0
## The research that unlocks founding (renamed Surface operations).
const TECH := &"pln_assault_doctrine"

## Research on top (old ids kept so saves keep them): Heavy shuttles, Armoured rovers.
const HEAVY_SHUTTLES := &"pln_heavy_dropships"
const ARMOURED_ROVERS := &"eng_armoured_dropships"
const HEAVY_SHUTTLE_BONUS := 0.4
const ARMOURED_HULL_MULT := 1.4

## Shuttle: units per lift, most shuttles, and seconds stock may wait before another joins.
const SHUTTLE_LOAD := 60
const MAX_SHUTTLES := 3
const SHUTTLE_WAIT := 90.0

## Harvester and soldier stats (hull, speed m/s); harvesting seconds per load.
const HARVESTER_HULL := 240.0
const HARVESTER_SPEED := 30.0
const HARVEST_TIME := 20.0
const SOLDIER_HULL := 520.0
const SOLDIER_SPEED := 26.0
## Nest and critter numbers.
const NEST_HULL := 2000.0
const NEST_RESPAWN := 900.0
## Agitation per load harvested within this of a nest; decay per sim minute; attack threshold.
const AGITATION_REACH := 1300.0
const AGITATION_PER_LOAD := 6.0
const AGITATION_DECAY := 0.5
const AGITATION_ATTACK := 30.0

var system_id: StringName
var planet: String = ""
var planet_type: int = 0
var corp: StringName = &"player"
var seed: int = 0
var danger: int = 1
var good: int = Economy.Ore.WATER
## Sim time it was ordered and when it is founded (the lander lands), -1 = not yet.
var ordered_at := 0.0
var founded_at := -1.0
## [{kind, x, z, hull, built (0..1 progress), disabled}]
var buildings: Array[Dictionary] = []
## [{x, z, loads, total, name}]
var deposits: Array[Dictionary] = []
## [{x, z, hull, agitation, dead_until (-1 alive)}]
var nests: Array[Dictionary] = []
## [{name, personality, role, hull, wallet, loads, kills, deposit (-1), trip (0..1 progress of the data trip)}]
var crew: Array[Dictionary] = []
## Deposit index -> pay per load (posted harvest contracts).
var contracts: Dictionary = {}
## Nest index -> bounty credits (posted).
var bounties: Dictionary = {}
## Goods waiting at the pad (Economy.Ore order).
var stock := Economy.zero_ore()
## Shuttles in the air: [{units, left (sim s)}]; how many shuttles the pad runs.
var lifts: Array[Dictionary] = []
var shuttles: int = 1
## Sim seconds a lift takes from the pad to the station (by distance, set at founding).
var lift_seconds := 70.0
## Hostiles still on the ground at the last save, {kind: power}: resolved as
## a data attack once after loading (Outposts._common_step).
var pending_ground: Dictionary = {}
var stock_wait := 0.0
var upkeep_owed := 0
var upkeep_acc := 0.0
var deposit_timer := -1.0
## Sim time of the next ground raid, and a forming one {at, size, source} ({} = none).
var next_raid := -1.0
var raid: Dictionary = {}
var lost := false
## Totals for the panels.
var delivered := Economy.zero_ore()
var loads_total: int = 0


func key() -> String:
	return key_of(system_id, planet)


static func key_of(sys: StringName, planet_name: String) -> String:
	return "%s|%s" % [sys, planet_name]


func is_founded() -> bool:
	return founded_at >= 0.0 and not lost


func good_name() -> String:
	return Economy.ore_name(good)


func load_units() -> int:
	return int(LOAD_UNITS.get(good, 30))


func fair_pay() -> int:
	return int(FAIR_PAY.get(good, 60)) + DANGER_PREMIUM * maxi(danger - 1, 0)


static func good_of(type: int) -> int:
	return GOODS[type] if type >= 0 and type < GOODS.size() else -1


func building(kind: StringName) -> Dictionary:
	for b in buildings:
		if StringName(b["kind"]) == kind:
			return b
	return {}


func count(kind: StringName) -> int:
	var n := 0
	for b in buildings:
		if StringName(b["kind"]) == kind:
			n += 1
	return n


## Built and not disabled.
func active(kind: StringName) -> int:
	var n := 0
	for b in buildings:
		if StringName(b["kind"]) == kind and float(b.get("built", 1.0)) >= 1.0 and not bool(b.get("disabled", false)):
			n += 1
	return n


func crew_of(role: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in crew:
		if String(c["role"]) == role:
			out.append(c)
	return out


func berths(role: String) -> int:
	var kind := BAY if role == HARVESTER else GARRISON
	return active(kind) * int(BUILDINGS[kind]["berths"])


func pad() -> Dictionary:
	return building(PAD)


func pad_alive() -> bool:
	var p := pad()
	return not p.is_empty() and float(p["hull"]) > 0.0


func living_nests() -> int:
	var n := 0
	for x in nests:
		if float(x.get("dead_until", -1.0)) < 0.0:
			n += 1
	return n


## Defence strength for the data rolls: soldiers, turrets, the dome.
## Units per shuttle lift (Heavy shuttles: +40%).
static func shuttle_load() -> int:
	return roundi(SHUTTLE_LOAD * (1.0 + HEAVY_SHUTTLE_BONUS)) if Research.is_done(HEAVY_SHUTTLES) else SHUTTLE_LOAD


## Full hull of a [param role] vehicle (Armoured rovers: x1.4).
static func max_hull(role: String) -> float:
	var h := HARVESTER_HULL if role == HARVESTER else SOLDIER_HULL
	return h * ARMOURED_HULL_MULT if Research.is_done(ARMOURED_ROVERS) else h


## The first finished, working building of [param kind], {} when none.
func active_building(kind: StringName) -> Dictionary:
	for b in buildings:
		if StringName(b["kind"]) == kind and float(b.get("built", 1.0)) >= 1.0 and not bool(b.get("disabled", false)):
			return b
	return {}


func defence() -> float:
	var d := 0.0
	for c in crew_of(SOLDIER):
		d += clampf(float(c["hull"]) / SOLDIER_HULL, 0.2, 1.0)
	d += 0.7 * active(TURRET)
	d += 1.5 * active(DOME)
	return d


func to_dict() -> Dictionary:
	var d := {"system": String(system_id), "planet": planet, "type": planet_type, "corp": String(corp), "seed": seed, "danger": danger,
			"good": good, "ordered_at": ordered_at, "founded_at": founded_at, "buildings": buildings.duplicate(true),
			"deposits": deposits.duplicate(true), "nests": nests.duplicate(true), "crew": crew.duplicate(true),
			"contracts": _int_keys_out(contracts), "bounties": _int_keys_out(bounties), "stock": stock, "lifts": lifts.duplicate(true),
			"shuttles": shuttles, "lift": lift_seconds, "stock_wait": stock_wait, "owed": upkeep_owed, "upkeep_acc": upkeep_acc, "deposit_timer": deposit_timer,
			"next_raid": next_raid, "raid": raid.duplicate(true), "lost": lost, "delivered": delivered, "loads": loads_total}
	if not pending_ground.is_empty():
		d["ground"] = pending_ground.duplicate()
	return d


static func from_dict(d: Dictionary) -> OutpostState:
	var o := OutpostState.new()
	o.system_id = StringName(d.get("system", ""))
	o.planet = String(d.get("planet", ""))
	o.planet_type = int(d.get("type", 0))
	o.corp = StringName(d.get("corp", "player"))
	o.seed = int(d.get("seed", 0))
	o.danger = int(d.get("danger", 1))
	o.good = int(d.get("good", Economy.Ore.WATER))
	o.ordered_at = float(d.get("ordered_at", 0.0))
	o.founded_at = float(d.get("founded_at", -1.0))
	o.buildings.assign(d.get("buildings", []))
	o.deposits.assign(_ints(d.get("deposits", []), ["loads", "total"]))
	o.nests.assign(d.get("nests", []))
	o.crew.assign(_ints(d.get("crew", []), ["deposit", "kills", "loads", "personality", "wallet"]))
	o.contracts = _int_keys_in(d.get("contracts", {}))
	o.bounties = _int_keys_in(d.get("bounties", {}))
	o.stock = Economy.padded(PackedInt32Array(d.get("stock", [])))
	for l: Dictionary in d.get("lifts", []):
		o.lifts.append({"units": Economy.padded(PackedInt32Array(l.get("units", []))), "left": float(l.get("left", 0.0))})
	o.shuttles = int(d.get("shuttles", 1))
	o.lift_seconds = float(d.get("lift", 70.0))
	o.pending_ground = (d.get("ground", {}) as Dictionary).duplicate()
	o.stock_wait = float(d.get("stock_wait", 0.0))
	o.upkeep_owed = int(d.get("owed", 0))
	o.upkeep_acc = float(d.get("upkeep_acc", 0.0))
	o.deposit_timer = float(d.get("deposit_timer", -1.0))
	o.next_raid = float(d.get("next_raid", -1.0))
	o.raid = (d.get("raid", {}) as Dictionary).duplicate(true)
	if o.raid.has("size"):
		o.raid["size"] = int(o.raid["size"])
	o.lost = bool(d.get("lost", false))
	o.delivered = Economy.padded(PackedInt32Array(d.get("delivered", [])))
	o.loads_total = int(d.get("loads", 0))
	return o


## Copies of the dicts in [param list] with [param keys] made ints again (JSON gives floats).
static func _ints(list: Array, keys: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for x: Dictionary in list:
		var c := x.duplicate(true)
		for k: String in keys:
			if c.has(k):
				c[k] = int(c[k])
		out.append(c)
	return out


static func _int_keys_out(d: Dictionary) -> Dictionary:
	var out := {}
	for k: Variant in d:
		out[str(k)] = d[k]
	return out


static func _int_keys_in(d: Dictionary) -> Dictionary:
	var out := {}
	for k: Variant in d:
		out[int(k)] = int(d[k])
	return out

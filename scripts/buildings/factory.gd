class_name Factory
extends Node
## Service node of the Factory (see BuildingDef.service_script), the
## structure the station starts with (BuildingManager.factory_def). It buys
## the player's ore ([member market], FactoryMarket) and turns its ore stock
## into ship modules from the ModuleCatalog, one at a time, into a parts
## warehouse of [member warehouse_cap] units. The Outfitter sells from this
## warehouse; without an Outfitter nothing reaches the captains.
##
## Ore per tier ([constant TIER_ORE]): Mk I iron, Mk II titanium plus iron,
## Mk III crystal plus titanium; build time [constant TIER_TIME]. Mk II and
## Mk III also need tooling upgrades (player ore, [constant TOOLING_COST]).
## So mining titanium and crystal is what lets the Factory make the gear
## that gets captains through more dangerous belts.
##
## Production order: backorders first (captains who could not buy a part,
## oldest first, ignoring the warehouse cap), then a spread that keeps every
## part captains could use in stock, weighted by the roles and ranks hired
## and by recent misses. Rare parts from salvage go into the warehouse and
## let the Factory make that module before its tooling, or discount the
## next one when already tooled.
##
## The furnace glow (mesh "factory_furnace_glow") pulses while producing.

signal changed
signal produced(module: ShipModule)

const GROUP := "factories"
## Ore (Economy.Ore order) per module, by tier.
const TIER_ORE := [[0, 0, 0], [15, 0, 0], [10, 20, 0], [0, 15, 20]]
## Sim seconds to make one module, by tier.
const TIER_TIME: PackedFloat32Array = [0.0, 40.0, 75.0, 120.0]
## Player ore for tooling tier 2 / 3.
const TOOLING_COST := {2: [250, 50, 0], 3: [200, 400, 200]}
## Rare part discount on the next one sold.
const RARE_DISCOUNT := 0.4
## Spread weight per tier (Mk I parts are wanted most).
const TIER_WEIGHT: PackedFloat32Array = [0.0, 1.0, 0.6, 0.35]
const MAX_LOG := 12

@export var warehouse_cap: int = 16
## Backorders lapse after this many sim seconds.
@export var backorder_timeout: float = 600.0
## Warehouse at game start: one of each.
@export var start_parts: PackedStringArray = PackedStringArray([
	"mining_laser_1", "ore_hold_1", "prospector_array_1", "reinforced_plating_1",
	"shield_projector_1", "survival_cell_1", "ion_drive_1",
])
## Furnace glow pulse: energy scale idle / producing, and pulse period (s).
@export var glow_idle: float = 0.35
@export var glow_busy: float = 1.0
@export var glow_period: float = 3.2

var building: Building
var market: FactoryMarket
## Highest tier the Factory is tooled for (1..3).
var tooling_tier: int = 1
## Module id -> units in the warehouse.
var warehouse: Dictionary = {}
## Module being made, or null; sim seconds into it.
var job: ShipModule
var job_time: float = 0.0
## Oldest first: {module: ShipModule, captain: Captain, time: float}.
var backorders: Array[Dictionary] = []
## Module id -> "stocked" (can be made before its tooling) or "discount".
var rare_parts: Dictionary = {}
## Module id -> recent times a captain wanted it and it was out (decays).
var misses: Dictionary = {}
## Newest last: {time, text}.
var log_lines: Array[Dictionary] = []
var total_built: int = 0

## Per glow mesh: {mats: Array[StandardMaterial3D], base: PackedFloat32Array}.
var _glow: Array[Dictionary] = []


static func find(tree: SceneTree) -> Factory:
	for n in tree.get_nodes_in_group(GROUP):
		var f := n as Factory
		if f and is_instance_valid(f.building) and f.building.is_active():
			return f
	return null


static func ore_cost(m: ShipModule) -> PackedInt32Array:
	return ore_cost_tier(m.tier)


static func ore_cost_tier(tier: int) -> PackedInt32Array:
	return PackedInt32Array(TIER_ORE[clampi(tier, 0, 3)])


static func build_time(m: ShipModule) -> float:
	return TIER_TIME[clampi(m.tier, 0, 3)]


func setup(owner_building: Building) -> void:
	building = owner_building
	_find_glow()


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(SimStepper.GROUP)
	market = FactoryMarket.new()
	market.name = "Market"
	add_child(market)
	market.changed.connect(func() -> void: changed.emit())
	var catalog := ModuleCatalog.shared()
	for id in start_parts:
		if catalog.find(StringName(id)):
			warehouse[StringName(id)] = int(warehouse.get(StringName(id), 0)) + 1


func _process(delta: float) -> void:
	if not SimClock.paused:
		sim_step(delta * SimClock.speed)
	_update_glow()


func sim_step(dt: float) -> void:
	if dt <= 0.0 or building == null or not building.is_active():
		return
	market.sim_step(dt)
	_expire_backorders()
	if job == null:
		_start_next()
	if job:
		job_time += dt
		if job_time >= build_time(job):
			_finish_job()
			_start_next()


# --- Warehouse ------------------------------------------------------------------

func stock_of(m: ShipModule) -> int:
	return int(warehouse.get(m.id, 0)) if m else 0


func warehouse_total() -> int:
	var n := 0
	for id: StringName in warehouse:
		n += int(warehouse[id])
	return n


## Units [param captain] may buy: stock not held for other captains' orders.
func free_stock_for(m: ShipModule, captain: Captain) -> int:
	var held := 0
	for o in backorders:
		if o["module"] == m and o["captain"] != captain:
			held += 1
	return stock_of(m) - held


## Takes one unit out for a sale; fulfils [param captain]'s order for it.
func take(m: ShipModule, captain: Captain) -> bool:
	if free_stock_for(m, captain) <= 0:
		return false
	warehouse[m.id] = stock_of(m) - 1
	if int(warehouse[m.id]) <= 0:
		warehouse.erase(m.id)
	if rare_parts.get(m.id, "") == "discount":
		rare_parts.erase(m.id)
	var o := order_of(captain)
	if not o.is_empty() and o["module"] == m:
		backorders.erase(o)
		_update_need()
	changed.emit()
	return true


## Adds units outright (demos, tests, salvage).
func add_stock(m: ShipModule, units: int = 1) -> void:
	if m == null or units <= 0:
		return
	warehouse[m.id] = stock_of(m) + units
	changed.emit()


func price_of(m: ShipModule) -> int:
	if rare_parts.get(m.id, "") == "discount":
		return roundi(m.cost * (1.0 - RARE_DISCOUNT))
	return m.cost


# --- Backorders -----------------------------------------------------------------

## The open order of [param captain], or {}.
func order_of(captain: Captain) -> Dictionary:
	for o in backorders:
		if o["captain"] == captain:
			return o
	return {}


## [param captain] orders [param m] (replaces an older order of theirs).
func place_backorder(m: ShipModule, captain: Captain) -> void:
	var old := order_of(captain)
	if not old.is_empty():
		if old["module"] == m:
			return
		backorders.erase(old)
	backorders.append({"module": m, "captain": captain, "time": SimClock.time})
	_update_need()
	_log("Backorder: %s for %s" % [m.display_name, captain.captain_name])
	changed.emit()


func cancel_backorder(captain: Captain) -> void:
	var o := order_of(captain)
	if not o.is_empty():
		backorders.erase(o)
		_update_need()
		changed.emit()


func orders_for(m: ShipModule) -> int:
	var n := 0
	for o in backorders:
		if o["module"] == m:
			n += 1
	return n


## A captain wanted [param m] and it was out: production leans towards it.
func note_miss(m: ShipModule) -> void:
	misses[m.id] = float(misses.get(m.id, 0.0)) + 1.0


func _expire_backorders() -> void:
	var gone := false
	for o in backorders.duplicate():
		var c := o["captain"] as Captain
		if c == null or not c.alive or SimClock.time - float(o["time"]) > backorder_timeout:
			backorders.erase(o)
			gone = true
	if gone:
		_update_need()
		changed.emit()


## Open orders per ore type, for the market's demand.
func _update_need() -> void:
	var need := PackedInt32Array([0, 0, 0])
	for o in backorders:
		var cost := ore_cost(o["module"] as ShipModule)
		for i in 3:
			if cost[i] > 0:
				need[i] += 1
	market.backorder_need = need


# --- Production -----------------------------------------------------------------

## True when the Factory can make [param m] (tooling or a rare part).
func can_make(m: ShipModule) -> bool:
	return m != null and m.tier >= 1 and (m.tier <= tooling_tier or rare_parts.get(m.id, "") == "stocked")


## Why [param m] is not being made, or "".
func make_block_reason(m: ShipModule) -> String:
	if not can_make(m):
		return "Needs %s tooling" % ShipModule.TIER_NAMES[m.tier]
	var short := _short_ore(ore_cost(m))
	return "" if short.is_empty() else "Short of %s" % short


func job_progress() -> float:
	return clampf(job_time / maxf(build_time(job), 0.01), 0.0, 1.0) if job else 0.0


## "Making Ore Hold Mk II 45%" / "Idle: warehouse full" / "Waiting for titanium".
func status_text() -> String:
	if building and not building.is_active():
		return building.get_status_text()
	if job:
		return "Making %s %d%%" % [job.display_name, roundi(job_progress() * 100.0)]
	if warehouse_total() >= warehouse_cap and backorders.is_empty():
		return "Idle: warehouse full"
	return "Waiting for ore"


func _start_next() -> void:
	var m := _pick_job()
	if m == null or not market.consume(ore_cost(m)):
		return
	job = m
	job_time = 0.0
	changed.emit()


func _finish_job() -> void:
	var m := job
	job = null
	job_time = 0.0
	warehouse[m.id] = stock_of(m) + 1
	total_built += 1
	if misses.has(m.id):
		misses[m.id] = float(misses[m.id]) * 0.5
	_log("Made %s" % m.display_name)
	produced.emit(m)
	changed.emit()


## Backorders first, then the spread (only below the warehouse cap).
func _pick_job() -> ShipModule:
	for o in backorders:
		var m := o["module"] as ShipModule
		if can_make(m) and stock_of(m) < orders_for(m) and market.has_stock(ore_cost(m)):
			return m
	if warehouse_total() >= warehouse_cap:
		return null
	var roles := _hired_roles()
	var best: ShipModule = null
	var best_score := INF
	for m in ModuleCatalog.shared().modules:
		if m == null or not can_make(m) or not market.has_stock(ore_cost(m)):
			continue
		var w := TIER_WEIGHT[m.tier] * (1.0 + 0.5 * float(misses.get(m.id, 0.0)))
		var role_rank := _role_rank(m, roles)
		if role_rank < 0:
			w *= 0.15
		elif Reputation.max_tier_for(role_rank) < m.tier:
			w *= 0.3
		var score := float(stock_of(m) + 1) / maxf(w, 0.001) + float(m.cost) * 0.0001
		if score < best_score:
			best_score = score
			best = m
	return best


## Role -> best rank among living captains of that role.
func _hired_roles() -> Dictionary:
	var out := {}
	var manager := get_tree().get_first_node_in_group(BuildingManager.GROUP) as BuildingManager if is_inside_tree() else null
	if manager == null:
		return out
	for b in manager.buildings:
		if not is_instance_valid(b):
			continue
		for c in b.captains:
			if c and c.alive:
				out[c.role] = maxi(int(out.get(c.role, -1)), c.rank)
	return out


## Best rank of a hired captain who could fit [param m], -1 when none.
func _role_rank(m: ShipModule, roles: Dictionary) -> int:
	var best := -1
	for role: String in roles:
		if m.fits_role(role):
			best = maxi(best, int(roles[role]))
	return best


# --- Tooling and rare parts -------------------------------------------------------

## Player ore for the next tooling tier (empty when fully tooled).
func next_tooling_cost() -> PackedInt32Array:
	var c: Array = TOOLING_COST.get(tooling_tier + 1, [])
	return PackedInt32Array(c)


## Why the next tooling tier cannot be bought now, or "".
func tooling_block_reason() -> String:
	if tooling_tier >= 3:
		return "Fully tooled"
	if building and not building.is_active():
		return "Finish construction first"
	return Economy.shortfall_text(0, next_tooling_cost())


func upgrade_tooling() -> bool:
	if not tooling_block_reason().is_empty():
		return false
	if not Economy.spend(0, next_tooling_cost()):
		return false
	tooling_tier += 1
	_log("Tooled for %s" % ShipModule.TIER_NAMES[tooling_tier])
	EventLog.post("Factory tooled for %s modules" % ShipModule.TIER_NAMES[tooling_tier], EventLog.Kind.INFO, building)
	changed.emit()
	return true


## A salvaged rare part: one unit goes into the warehouse; the Factory may
## make [param m] before its tooling ("stocked") or the next one sells at a
## discount ("discount"). Returns the kind.
func add_rare_part(m: ShipModule) -> String:
	var kind := "discount" if can_make(m) else "stocked"
	rare_parts[m.id] = kind
	warehouse[m.id] = stock_of(m) + 1
	_log("Rare part: %s" % m.display_name)
	changed.emit()
	return kind


# --- Look -------------------------------------------------------------------------

func _find_glow() -> void:
	_glow.clear()
	if building == null:
		return
	var n := building.find_child("factory_furnace_glow", true, false)
	if n == null:
		return
	for mi in ModelLoader.meshes_of(n):
		if mi.mesh == null:
			continue
		var mats: Array[StandardMaterial3D] = []
		var base := PackedFloat32Array()
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i) as StandardMaterial3D
			if src == null or not src.emission_enabled:
				continue
			var m := src.duplicate() as StandardMaterial3D
			mi.set_surface_override_material(i, m)
			mats.append(m)
			base.append(src.emission_energy_multiplier)
		if not mats.is_empty():
			_glow.append({"mats": mats, "base": base})


func _update_glow() -> void:
	if _glow.is_empty():
		return
	var busy := job != null and building.is_active()
	var level := glow_idle
	if busy:
		level = lerpf(glow_idle, glow_busy, 0.65 + 0.35 * sin(SimClock.time * TAU / glow_period))
	for e in _glow:
		var mats: Array[StandardMaterial3D] = e["mats"]
		var base: PackedFloat32Array = e["base"]
		for i in mats.size():
			mats[i].emission_energy_multiplier = base[i] * level


func _log(text: String) -> void:
	log_lines.append({"time": SimClock.time, "text": text})
	if log_lines.size() > MAX_LOG:
		log_lines.remove_at(0)


## Ore types the market stock is short of for [param cost], "" when none.
func _short_ore(cost: PackedInt32Array) -> String:
	var parts: PackedStringArray = []
	for i in cost.size():
		if float(cost[i]) > market.stock[i]:
			parts.append(Economy.ORE_NAMES[i].to_lower())
	return " and ".join(parts)

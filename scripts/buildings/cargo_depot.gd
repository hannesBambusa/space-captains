class_name CargoDepot
extends Node
## Cargo stock of an outpost (child of the [Building], made for defs with
## BuildingDef.max_shuttles) and the cargo shuttles that fly it to the
## Home Station.
##
## Mining Outpost: miners unload their ore here ([method add_stock], from
## ContractBoard.deliver_mining_load) instead of into the player's stock.
## Salvage Yard: the yard still sells its reprocessed ore to the player
## (SalvageYard.buy, paid at once), but the bought ore waits here and goes
## to the station by shuttle. Either way the player's ore only rises when a
## shuttle lands on a station docking pad (CargoShuttle).
##
## Shuttles: one from the start (once the building is active), more as the
## throughput grows ([method wanted_shuttles]: units delivered over the last
## [member throughput_window] s against what one shuttle moves per minute on
## this outpost's round trip, plus one while the backlog is over two loads),
## up to BuildingDef.max_shuttles. A docked shuttle loads when the stock fills
## a load ([member BuildingDef.shuttle_capacity]) or the oldest unit has
## waited [member max_wait] s. Only one shuttle loads at a time.
##
## [member supply_interval] > 0 (BuildingDef.shuttle_supply_interval, the
## Mercenary Outpost): no cargo, the shuttle flies a cosmetic supply run that
## often.
##
## Sim time only: [method sim_step] runs from _process and from SimStepper.

signal changed

const GROUP := "cargo_depots"
const TYPES := 3

## Oldest waiting unit leaves after this many sim seconds, even short of a full load.
@export var max_wait: float = 40.0
## Sim seconds of deliveries the throughput is measured over.
@export var throughput_window: float = 180.0
## Docking and loading overhead per round trip, sim seconds (shuttle sizing).
@export var trip_overhead: float = 45.0
## Shuttle count is rechecked this often, sim seconds.
@export var check_interval: float = 3.0
## Cosmetic supply runs every this many sim seconds (0 = cargo depot).
var supply_interval: float = 0.0

var building: Building
## Waiting for a shuttle: iron, titanium, crystal.
var stock := PackedInt32Array([0, 0, 0])
var shuttles: Array[CargoShuttle] = []
## Units that reached the station, per type.
var total_shipped := PackedInt32Array([0, 0, 0])
var trips: int = 0

## {time, amount} per delivery inside the throughput window, oldest first.
var _history: Array[Dictionary] = []
## SimClock.time the oldest waiting unit arrived (INF = nothing waiting).
var _waiting_since: float = INF
var _check_timer: float = 0.0
var _supply_timer: float = 0.0
var _spawned: int = 0


## The depot of [param b], or null.
static func of(b: Building) -> CargoDepot:
	return b.get_cargo_depot() if is_instance_valid(b) else null


## The depot of [param ship]'s home, or null.
static func of_ship(ship: Node) -> CargoDepot:
	var s := ship as Ship
	return of(s.home) if s and is_instance_valid(s.home) else null


func setup(owner_building: Building) -> void:
	building = owner_building
	supply_interval = building.def.shuttle_supply_interval


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(SimStepper.GROUP)
	_supply_timer = supply_interval * 0.3


func _process(delta: float) -> void:
	if not SimClock.paused:
		sim_step(delta * SimClock.speed)


func sim_step(dt: float) -> void:
	if dt <= 0.0 or building == null or not building.is_active() or not building.is_inside_tree():
		return
	_supply_timer -= dt
	_check_timer -= dt
	if _check_timer <= 0.0:
		_check_timer = check_interval
		_prune()
		if shuttles.size() < wanted_shuttles():
			_spawn_shuttle()


func is_supply_only() -> bool:
	return supply_interval > 0.0


func capacity() -> int:
	return maxi(building.def.shuttle_capacity, 1)


# --- Stock --------------------------------------------------------------------

## [param amount] units of [param type] (Economy.Ore) arrived at the outpost.
func add_stock(type: int, amount: int) -> void:
	if amount <= 0:
		return
	stock[type] += amount
	if _waiting_since == INF:
		_waiting_since = SimClock.time
	_history.append({"time": SimClock.time, "amount": amount})
	changed.emit()


func waiting_total() -> int:
	return stock[0] + stock[1] + stock[2]


## True when a docked shuttle should load now.
func load_ready() -> bool:
	if is_supply_only():
		return _supply_timer <= 0.0
	var n := waiting_total()
	return n >= capacity() or (n > 0 and SimClock.time - _waiting_since >= max_wait)


## Takes a load (up to [method capacity], rarest ore first) for a shuttle.
func take_load() -> PackedInt32Array:
	var out := PackedInt32Array([0, 0, 0])
	if is_supply_only():
		_supply_timer = supply_interval
		return out
	var room := capacity()
	for i in range(TYPES - 1, -1, -1):
		var n := mini(stock[i], room)
		stock[i] -= n
		out[i] = n
		room -= n
	_waiting_since = INF if waiting_total() == 0 else SimClock.time
	changed.emit()
	return out


## A shuttle landed [param cargo] at the station.
func note_shipped(cargo: PackedInt32Array) -> void:
	trips += 1
	for i in mini(cargo.size(), TYPES):
		total_shipped[i] += cargo[i]
	changed.emit()


# --- Shuttles -----------------------------------------------------------------

## Units delivered here per sim minute, over the throughput window.
func throughput_per_min() -> float:
	_trim_history()
	var total := 0
	for h in _history:
		total += int(h["amount"])
	return float(total) * 60.0 / throughput_window


## Units one shuttle moves per sim minute on this outpost's round trip.
func shuttle_rate_per_min() -> float:
	var dist := Vector2(building.position.x, building.position.z).length()
	var trip_time := 2.0 * dist / CargoShuttle.CRUISE_SPEED + trip_overhead
	return float(capacity()) * 60.0 / maxf(trip_time, 1.0)


## How many shuttles this outpost should run now (1 .. max_shuttles).
func wanted_shuttles() -> int:
	if is_supply_only():
		return mini(1, building.def.max_shuttles)
	var n := ceili(throughput_per_min() / maxf(shuttle_rate_per_min(), 0.01) - 0.05)
	if waiting_total() >= capacity() * 2:
		n = maxi(n, shuttles.size() + 1)
	return clampi(n, 1, building.def.max_shuttles)


## True while another shuttle of this depot is loading or about to leave.
func loading_busy(asking: CargoShuttle) -> bool:
	for s in shuttles:
		if s != asking and is_instance_valid(s) and s.is_loading():
			return true
	return false


## A free shuttle berth index (0 ..), parked beside the apron.
func free_berth() -> int:
	for i in building.def.max_shuttles + 2:
		var used := false
		for s in shuttles:
			if is_instance_valid(s) and s.slot_index == i:
				used = true
				break
		if not used:
			return i
	return shuttles.size()


## Shuttle berth [param index], building space: beside the apron, clear of
## the miners' lane and berths; -Z (the nose) points out of the dock.
func berth_transform(index: int) -> Transform3D:
	var out := building.dock_outward()
	var side := out.cross(Vector3.UP)
	var sgn := -1.0 if index % 2 == 0 else 1.0
	var p := building.spawn_local() + out * 12.0 + side * sgn * (26.0 + 12.0 * floorf(index / 2.0))
	p.y = 3.0
	return Transform3D(Basis.looking_at(out, Vector3.UP), p)


## A shuttle was lost or left: forget it.
func remove_shuttle(s: CargoShuttle) -> void:
	shuttles.erase(s)
	changed.emit()


## "Stock waiting: 37 iron, shuttles 2/3".
func summary_text() -> String:
	if is_supply_only():
		return "Supply shuttles %d/%d" % [shuttles.size(), building.def.max_shuttles]
	var parts: PackedStringArray = []
	for i in TYPES:
		if stock[i] > 0:
			parts.append("%s %s" % [UIUtil.amount(stock[i]), Economy.ORE_NAMES[i].to_lower()])
	return "Stock waiting: %s, shuttles %d/%d" % [", ".join(parts) if not parts.is_empty() else "none", shuttles.size(), building.def.max_shuttles]


func _spawn_shuttle() -> void:
	var mgr := get_tree().get_first_node_in_group(BuildingManager.GROUP) as BuildingManager
	if mgr == null or mgr.frame == null:
		return
	_spawned += 1
	var s := CargoShuttle.new()
	s.setup_shuttle(self, free_berth(), _spawned)
	var berth := berth_transform(s.slot_index)
	s.position = berth.origin
	s.rotation.y = ShipMover.yaw_for(-berth.basis.z)
	building.add_child(s)
	shuttles.append(s)
	changed.emit()


func _prune() -> void:
	for s in shuttles.duplicate():
		if not is_instance_valid(s) or s.dead:
			shuttles.erase(s)


func _trim_history() -> void:
	var cut := SimClock.time - throughput_window
	while not _history.is_empty() and float(_history[0]["time"]) < cut:
		_history.remove_at(0)

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
## up to BuildingDef.max_shuttles, plus one while the oldest unit has waited
## [member stuck_wait] s with every shuttle away). A docked shuttle loads when
## the stock fills a load ([member BuildingDef.shuttle_capacity]) or the
## oldest unit has waited [member max_wait] s, so a small purchase leaves
## within that time once a shuttle is in. Only one shuttle loads at a time.
##
## Transit: [method in_flight] is the ore aboard shuttles on their way,
## [method pending] that plus the stock waiting here, [method pending_all]
## the same over every depot (the top bar's "+40" hint) and
## [method departure_eta] / [method transit_text] say when the waiting stock
## leaves ("In transit: 40 iron (shuttle leaving in 0:12)").
##
## [member supply_interval] > 0 (BuildingDef.shuttle_supply_interval, the
## Mercenary Outpost): no cargo, the shuttle flies a cosmetic supply run that
## often.
##
## Sim time only: [method sim_step] runs from _process and from SimStepper.

signal changed

const GROUP := "cargo_depots"
const TYPES := Economy.COUNT

## Oldest waiting unit leaves after this many sim seconds, even short of a full load.
@export var max_wait: float = 40.0
## Stock waiting this long with no shuttle docked brings in one more shuttle, sim seconds.
@export var stuck_wait: float = 90.0
## Sim seconds of deliveries the throughput is measured over.
@export var throughput_window: float = 180.0
## Docking and loading overhead per round trip, sim seconds (shuttle sizing).
@export var trip_overhead: float = 45.0
## Shuttle count is rechecked this often, sim seconds.
@export var check_interval: float = 3.0
## A shot-down shuttle is replaced after this many sim seconds.
@export var replace_delay: float = 45.0
## Cosmetic supply runs every this many sim seconds (0 = cargo depot).
var supply_interval: float = 0.0

var building: Building
## Waiting for a shuttle, per Economy.Ore type (asteroid ore and planet goods).
var stock := Economy.zero_ore()
var shuttles: Array[CargoShuttle] = []
## Units that reached the station, per type.
var total_shipped := Economy.zero_ore()
var trips: int = 0

## {time, amount} per delivery inside the throughput window, oldest first.
var _history: Array[Dictionary] = []
## SimClock.time the oldest waiting unit arrived (INF = nothing waiting).
var _waiting_since: float = INF
var _check_timer: float = 0.0
var _supply_timer: float = 0.0
var _spawned: int = 0
## SimClock.time before which no new shuttle comes (a shuttle was lost).
var _replace_at: float = 0.0


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
		if shuttles.size() < wanted_shuttles() and SimClock.time >= _replace_at:
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
	var n := 0
	for v in stock:
		n += v
	return n


## True when a docked shuttle should load now.
func load_ready() -> bool:
	if building and building.is_disabled():
		return false
	if is_supply_only():
		return _supply_timer <= 0.0
	var n := waiting_total()
	return n >= capacity() or (n > 0 and SimClock.time - _waiting_since >= max_wait)


## Takes a load (up to [method capacity], rarest ore first) for a shuttle.
func take_load() -> PackedInt32Array:
	var out := Economy.zero_ore()
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
	var dist := SpaceNav.flat_length(building.position)
	var trip_time := 2.0 * dist / CargoShuttle.CRUISE_SPEED + trip_overhead
	return float(capacity()) * 60.0 / maxf(trip_time, 1.0)


## How many shuttles this outpost should run now (1 .. max_shuttles).
func wanted_shuttles() -> int:
	if is_supply_only():
		return mini(1, building.def.max_shuttles)
	var n := ceili(throughput_per_min() / maxf(shuttle_rate_per_min(), 0.01) - 0.05)
	if waiting_total() >= capacity() * 2:
		n = maxi(n, shuttles.size() + 1)
	if waiting_total() > 0 and SimClock.time - _waiting_since >= stuck_wait and docked_shuttle() == null:
		n = maxi(n, shuttles.size() + 1)
	return clampi(n, 1, building.def.max_shuttles)


## True while another shuttle of this depot is loading or about to leave.
func loading_busy(asking: CargoShuttle) -> bool:
	for s in shuttles:
		if s != asking and is_instance_valid(s) and s.is_loading():
			return true
	return false


## A shuttle parked at the berth and free to load, or null.
func docked_shuttle() -> CargoShuttle:
	for s in shuttles:
		if is_instance_valid(s) and not s.dead and s.phase == CargoShuttle.Phase.PARKED:
			return s
	return null


## Ore aboard this depot's shuttles on their way to the station (loading
## counts: it is no longer in the stock).
func in_flight() -> PackedInt32Array:
	var out := Economy.zero_ore()
	for s in shuttles:
		if is_instance_valid(s) and not s.dead and s.is_carrying_cargo():
			for i in TYPES:
				out[i] += s.cargo[i]
	return out


## Ore of this depot not yet at the station: waiting here plus in flight.
func pending() -> PackedInt32Array:
	var out := in_flight()
	if not is_supply_only():
		for i in TYPES:
			out[i] += stock[i]
	return out


## Pending ore over every depot (see [method pending]).
static func pending_all(ctx: Node) -> PackedInt32Array:
	var out := Economy.zero_ore()
	for n in SystemWorld.nodes_in(ctx, GROUP):
		var d := n as CargoDepot
		if d and is_instance_valid(d.building) and d.building.is_active():
			var p := d.pending()
			for i in TYPES:
				out[i] += p[i]
	return out


## Sim seconds until the waiting stock leaves: 0 = loading now or about
## to, -1 = nothing waiting or no shuttle docked (all away).
func departure_eta() -> float:
	if is_supply_only() or waiting_total() <= 0:
		return -1.0
	if docked_shuttle() == null:
		return -1.0
	if waiting_total() >= capacity():
		return 0.0
	return maxf(max_wait - (SimClock.time - _waiting_since), 0.0)


## "40 iron, 3 crystal" for [param ore] ("" when empty).
static func ore_text(ore: PackedInt32Array) -> String:
	var parts: PackedStringArray = []
	for i in mini(ore.size(), TYPES):
		if ore[i] > 0:
			parts.append("%s %s" % [Fmt.amount(ore[i]), Economy.ore_name(i)])
	return ", ".join(parts)


## Lines about the stock on its way: "In transit: 40 iron (shuttle leaving
## in 0:12)" for the waiting stock and "On the way to the station: 31 iron"
## for what is aboard. Empty when nothing is pending.
func transit_lines() -> PackedStringArray:
	var out: PackedStringArray = []
	if is_supply_only():
		return out
	var waiting := ore_text(stock)
	if not waiting.is_empty():
		var eta := departure_eta()
		var when := ""
		if eta < 0.0:
			when = "waiting for a shuttle to come back"
		elif eta <= 0.5:
			when = "shuttle loading now"
		else:
			when = "shuttle leaving in %s" % Fmt.clock(ceilf(eta))
		out.append("In transit: %s (%s)" % [waiting, when])
	var aboard := ore_text(in_flight())
	if not aboard.is_empty():
		out.append("On the way to the station: %s" % aboard)
	return out


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


## A shuttle was lost or left: forget it. [param lost]: it was shot down,
## so the next one comes after [member replace_delay].
func remove_shuttle(s: CargoShuttle, lost: bool = false) -> void:
	shuttles.erase(s)
	if lost:
		_replace_at = SimClock.time + replace_delay
	changed.emit()


## Sim seconds until the replacement for a lost shuttle arrives, 0 = none pending.
func replacement_eta() -> float:
	if building == null or shuttles.size() >= wanted_shuttles():
		return 0.0
	return maxf(_replace_at - SimClock.time, 0.0)


## "Stock waiting: 37 iron, shuttles 2/3".
func summary_text() -> String:
	if is_supply_only():
		return "Supply shuttles %d/%d" % [shuttles.size(), building.def.max_shuttles]
	var parts: PackedStringArray = []
	for i in TYPES:
		if stock[i] > 0:
			parts.append("%s %s" % [Fmt.amount(stock[i]), Economy.ore_name(i)])
	var text := "Stock waiting: %s, shuttles %d/%d" % [", ".join(parts) if not parts.is_empty() else "none", shuttles.size(), building.def.max_shuttles]
	var eta := replacement_eta()
	if eta > 0.0:
		text += "\nReplacement shuttle in %s" % Fmt.clock(ceilf(eta))
	return text


func _spawn_shuttle() -> void:
	var mgr := BuildingManager.of(self)
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


# --- Save ---------------------------------------------------------------------

## The stock and counters; the shuttles are saved as ships.
func save_state() -> Dictionary:
	return SaveUtil.props(self, ["stock", "total_shipped", "trips", "_history", "_waiting_since", "_check_timer", "_supply_timer", "_spawned", "_replace_at"])


func load_state(d: Dictionary, _refs: SaveRefs) -> void:
	SaveUtil.apply_props(self, d)
	# Saves before the planet goods hold three types.
	stock = Economy.padded(stock)
	total_shipped = Economy.padded(total_shipped)
	changed.emit()

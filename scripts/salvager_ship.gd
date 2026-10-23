class_name SalvagerShip
extends MinerShip
## A hired salvager. Works scrap fields on its own (free salvage, paid by its
## Salvage Yard) or on a player's salvage contract (bonus): flies to the
## field, holds off a chunk and cuts it free with the claw beam
## ([constant WORK_TIME] scaled by the tool, the Salvage skill and the hold),
## takes one load of scrap ([constant SalvageContract.LOAD_SCRAP] times the
## hold) from the field and brings it home to the yard. Everything else
## (flight, flee, scavengers stealing part of the load, the trip) is the
## miner's.
## Fields keep the height their wreck died at. One down among a belt's rocks
## is cut from the salvager's lane above (below) it, so the ship never sits
## in the turning rocks; elsewhere the salvager holds at the field's height.
## Model: assets/models/ships/salvager.glb (set by the Salvage Yard).

const WORK_TIME := 16.0
## Hover distance from the cut point, metres.
const STANDOFF := 16.0
## Work spots around a field, one salvager each (spread evenly).
const SLOT_COUNT := 6
## Salvagers working near their field skip separation from each other
## (their spots are spread apart already) inside this flat distance, metres.
const WORK_ZONE := 150.0

## Work spots taken per field: ScrapField instance id -> Array of ships (null = free).
static var _slots: Dictionary = {}

var _slot_field := 0


func _init() -> void:
	role = Role.SALVAGER


func _make_brain() -> CaptainBrain:
	return SalvagerBrain.new(self, SalvageEvaluator.new())


func _on_ready_ship() -> void:
	super._on_ready_ship()
	role = Role.SALVAGER


func job_begin(trip: CaptainBrain.Trip) -> bool:
	var sc := trip.contract as SalvageContract
	if sc == null or not is_instance_valid(sc.field) or sc.field.amount <= 0:
		return false
	var f := sc.field
	# Each salvager takes its own spot around the field, counted from the side
	# facing home, so they never crowd one cut point.
	var slot := _take_slot(f)
	var toward := (home.global_position if is_instance_valid(home) else global_position) - f.global_position
	toward.y = 0.0
	if toward.length() < 1.0:
		toward = Vector3.RIGHT
	var dir := toward.normalized().rotated(Vector3.UP, TAU * float(slot) / float(SLOT_COUNT) + _rng.randf_range(-0.15, 0.15))
	var cut := f.global_position + dir * f.radius * _rng.randf_range(0.4, 0.55)
	var hover := cut + dir * STANDOFF
	var band := SpaceNav.rock_band_at(get_tree(), hover)
	if band and absf(cut.y) < band.rock_layer_height() + 6.0:
		hover.y = lane_sign() * band.lane_altitude()
	trip.meta["cut"] = cut
	trip.meta["hover"] = hover
	trip.meta["scrap"] = 0
	trip.ore = -1
	trip.work_time = WORK_TIME * (stats.drill_mult if stats else 1.0) * load_time_scale()
	trip.progress = 0.0
	trip.cargo = 1.0
	return true


func job_target(trip: CaptainBrain.Trip, working: bool) -> Dictionary:
	var sc := trip.contract as SalvageContract
	if sc == null or not is_instance_valid(sc.field) or not trip.meta.has("hover"):
		return {}
	var pos: Vector3 = trip.meta["hover"]
	var cut: Vector3 = trip.meta["cut"]
	var out := {"pos": pos, "vel": Vector3.ZERO}
	if working or Combat.flat_distance(pos, global_position) < 60.0:
		out["face"] = Vector3(cut.x - pos.x, 0.0, cut.z - pos.z)
	return out


func job_work(trip: CaptainBrain.Trip, dt: float) -> bool:
	trip.progress = clampf(trip.progress + dt / maxf(trip.work_time, 0.1), 0.0, 1.0)
	hold_fill = trip.progress
	if trip.progress < 1.0:
		return false
	var sc := trip.contract as SalvageContract
	var want := roundi(float(SalvageContract.LOAD_SCRAP) * (stats.cargo if stats else 1.0))
	var got := sc.field.take(want) if sc and is_instance_valid(sc.field) else 0
	trip.meta["scrap"] = got
	hold_fill = float(got) / maxf(float(want), 1.0)
	return true


func job_end(_trip: CaptainBrain.Trip) -> void:
	_release_slot()
	if _beam:
		_beam.set_active(false)


func _exit_tree() -> void:
	super._exit_tree()
	_release_slot()


## Ships near the same field they work do not push each other apart.
func separation_key() -> int:
	var t := brain.trip if brain else null
	if _slot_field == 0 or t == null or not t.meta.has("hover"):
		return 0
	return _slot_field if Combat.flat_distance(global_position, t.meta["hover"]) < WORK_ZONE else 0


## First free spot index around [param f] (wraps past SLOT_COUNT when full).
func _take_slot(f: ScrapField) -> int:
	_release_slot()
	_slot_field = f.get_instance_id()
	var list: Array = _slots.get(_slot_field, [])
	var i := list.find(null)
	if i < 0:
		i = list.size()
		list.append(self)
	else:
		list[i] = self
	_slots[_slot_field] = list
	return i % SLOT_COUNT


func _release_slot() -> void:
	if _slot_field == 0:
		return
	var list: Array = _slots.get(_slot_field, [])
	var i := list.find(self)
	if i >= 0:
		list[i] = null
	while not list.is_empty() and list[-1] == null:
		list.pop_back()
	if list.is_empty():
		_slots.erase(_slot_field)
	_slot_field = 0


func lose_cargo(share: float) -> float:
	var taken := super.lose_cargo(share)
	if brain and brain.trip:
		hold_fill = brain.trip.cargo
	return taken


func _update_beam() -> void:
	var t := brain.trip if brain else null
	if t == null or brain.state != CaptainBrain.State.MINING or not t.meta.has("cut"):
		_beam.set_active(false)
		return
	var nose := global_transform * Vector3(0.0, 0.0, -nose_offset)
	var cut: Vector3 = t.meta["cut"]
	# Flat: a salvager in its lane cuts a field down among the rocks.
	var to_cut := cut - global_position
	to_cut.y = 0.0
	var facing := (global_basis * Vector3.FORWARD).dot(to_cut.normalized())
	if facing < 0.85:
		_beam.set_active(false)
		return
	_beam.aim(nose, cut + Vector3(0.0, 1.0, 0.0))

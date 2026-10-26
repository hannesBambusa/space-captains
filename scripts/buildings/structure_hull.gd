class_name StructureHull
extends StaticCombatant
## Hull of a structure that is not a weapon: the outposts (Mining Outpost,
## Mercenary Outpost, Salvage Yard; BuildingDef.structure_hull) and the
## Home Station itself (BuildingManager.station_hull). A combatant raiders
## can shoot (see [Combat]).
##
## It is never destroyed: at 0 hull it is disabled ([member disabled]) and
## raiders stop shooting it (they loot it instead, as before). Disabled, an
## outpost stops its cargo shuttles and its hiring; the station closes its
## docking pads (shuttles wait). The station repairs it on its own like the
## turrets ([StructureRepair]): from [member repair_delay] s after the last
## hit, [member repair_rate] of max hull per second, paid by the player;
## back online at [member online_at] of max hull. Hits raise the
## colony alarm (ColonyAlarm), so nearby mercenaries come.

signal changed
signal disabled_changed(on: bool)

@export var repair_delay: float = 8.0
@export var repair_rate: float = 0.012
## Back online from this hull share.
@export var online_at: float = 0.4

var durability: Durability
var disabled := false
var label: String = "Structure"
## The building it belongs to (null for the station).
var building: Building
var hit_radius: float = 30.0
var repair := StructureRepair.new()
var times_disabled: int = 0


## Call before adding to the tree. [param height] lifts the aim point above
## the owner's origin so tracers hit the body.
func setup(owner_label: String, hull: float, radius: float, height: float, owner_building: Building = null) -> void:
	label = owner_label
	building = owner_building
	hit_radius = radius
	durability = Durability.new(hull, 0.0, 0.0)
	position = Vector3(0.0, height, 0.0)
	name = "Hull"
	repair.changed.connect(changed.emit)
	repair.session_ended.connect(_on_repair_ended)


func _ready() -> void:
	add_to_group(Combat.GROUP)
	add_to_group(SimStepper.GROUP)


func _process(delta: float) -> void:
	if not SimClock.paused:
		sim_step(delta * SimClock.speed)


func sim_step(dt: float) -> void:
	if dt <= 0.0 or durability == null:
		return
	repair.step(durability, dt, building == null or building.is_active(), repair_delay, repair_rate)
	if disabled and durability.fraction() >= online_at:
		disabled = false
		EventLog.post("%s is back online (hull %d%%)" % [label, roundi(durability.fraction() * 100.0)], EventLog.Kind.INFO, _focus())
		changed.emit()
		disabled_changed.emit(false)


func hull_fraction() -> float:
	return durability.fraction() if durability else 1.0


func is_damaged() -> bool:
	return durability != null and durability.hull < durability.max_hull


## "Hull 64%, repairing" and the like; "" at full hull.
func get_status_text() -> String:
	if durability == null:
		return ""
	if disabled:
		return "Disabled (hull %d%%, back online at %d%%)%s" % [roundi(hull_fraction() * 100.0), roundi(online_at * 100.0), ", repairing" if repair.repairing else ""]
	if not is_damaged():
		return ""
	return "Hull %d%%%s" % [roundi(hull_fraction() * 100.0), ", repairing" if repair.repairing else ""]


# --- Combatant API (see Combat) ---------------------------------------------

## Never destroyed (disabled instead).
func is_alive() -> bool:
	return durability != null


func is_targetable() -> bool:
	return not disabled and is_inside_tree() and (building == null or building.is_active())


func get_hit_radius() -> float:
	return hit_radius


func get_display_name() -> String:
	return label


func take_hit(amount: float, attacker: Node3D, _at: Vector3) -> void:
	if disabled or durability == null:
		return
	durability.apply(amount, attacker)
	if repair.repairing:
		repair.end_session()
	ColonyAlarm.raise(self, self, label, attacker)
	if durability.hull <= 0.0:
		_disable(attacker)
	changed.emit()


func _disable(attacker: Node3D) -> void:
	disabled = true
	times_disabled += 1
	# Kept at 1 hull so it can be repaired (Durability ignores repairs at 0).
	durability.hull = 1.0
	var by := Combat.by_suffix(attacker)
	var what := "docking pads closed until repaired" if building == null else "shuttles and hiring stopped until repaired"
	EventLog.post("%s disabled%s: %s" % [label, by, what], EventLog.Kind.LOSS, _focus())
	disabled_changed.emit(true)


func _focus() -> Node3D:
	return building if building else self


# --- Repairs ------------------------------------------------------------------

## Credits to bring the hull back to full.
func cost_to_repair() -> int:
	return StructureRepair.cost_to_repair(durability)


func _on_repair_ended(paid: int) -> void:
	if paid > 0:
		EventLog.post("%s repaired by the station: -%d cr" % [label, paid], EventLog.Kind.INFO, _focus(), Vector3.INF, "repairs:" + label)


# --- Save ---------------------------------------------------------------------

func save_state() -> Dictionary:
	var d := SaveUtil.props_and_durability(self, ["disabled", "times_disabled"], durability)
	d.merge(repair.save_state())
	return d


func load_state(d: Dictionary, refs: SaveRefs) -> void:
	SaveUtil.apply_props_and_durability(self, d, durability, refs, StructureRepair.FIELDS)
	repair.load_state(d)
	changed.emit()

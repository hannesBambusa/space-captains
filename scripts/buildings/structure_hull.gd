class_name StructureHull
extends Node3D
## Hull of a structure that is not a weapon: the outposts (Mining Outpost,
## Mercenary Outpost, Salvage Yard; BuildingDef.structure_hull) and the
## Home Station itself (BuildingManager.station_hull). A combatant raiders
## can shoot (see [Combat]).
##
## It is never destroyed: at 0 hull it is disabled ([member disabled]) and
## raiders stop shooting it (they loot it instead, as before). Disabled, an
## outpost stops its cargo shuttles and its hiring; the station closes its
## docking pads (shuttles wait). The station repairs it on its own like the
## turrets (DefenseStructure): from [member repair_delay] s after the last
## hit, [member repair_rate] of max hull per second, paid by the player at
## DefenseStructure.REPAIR_COST_PER_HULL per point; back online at
## [member online_at] of max hull. No credits, no repairs. Hits raise the
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
var repairing := false
var repair_session_paid: int = 0
var repair_total_paid: int = 0
var times_disabled: int = 0

var _repair_credit := 0.0


## Call before adding to the tree. [param height] lifts the aim point above
## the owner's origin so tracers hit the body.
func setup(owner_label: String, hull: float, radius: float, height: float, owner_building: Building = null) -> void:
	label = owner_label
	building = owner_building
	hit_radius = radius
	durability = Durability.new(hull, 0.0, 0.0)
	position = Vector3(0.0, height, 0.0)
	name = "Hull"


func _ready() -> void:
	add_to_group(Combat.GROUP)
	add_to_group(SimStepper.GROUP)


func _process(delta: float) -> void:
	if not SimClock.paused:
		sim_step(delta * SimClock.speed)


func sim_step(dt: float) -> void:
	if dt <= 0.0 or durability == null:
		return
	var built := building == null or building.is_active()
	if built and durability.hull < durability.max_hull and durability.seconds_since_hit() >= repair_delay:
		_repair(dt)
	elif repairing:
		_end_repair()
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
		return "Disabled (hull %d%%, back online at %d%%)%s" % [roundi(hull_fraction() * 100.0), roundi(online_at * 100.0), ", repairing" if repairing else ""]
	if not is_damaged():
		return ""
	return "Hull %d%%%s" % [roundi(hull_fraction() * 100.0), ", repairing" if repairing else ""]


# --- Combatant API (see Combat) ---------------------------------------------

func get_faction() -> int:
	return Combat.Faction.PLAYER


## Never destroyed (disabled instead).
func is_alive() -> bool:
	return durability != null


func is_targetable() -> bool:
	return not disabled and is_inside_tree() and (building == null or building.is_active())


func get_hit_radius() -> float:
	return hit_radius


func get_aim_velocity() -> Vector3:
	return SpaceNav.world_velocity(self)


func get_dodge() -> float:
	return 0.0


func get_display_name() -> String:
	return label


func take_hit(amount: float, attacker: Node3D, _at: Vector3) -> void:
	if disabled or durability == null:
		return
	durability.apply(amount, attacker)
	if repairing:
		_end_repair()
	ColonyAlarm.raise(get_tree(), self, label, attacker)
	if durability.hull <= 0.0:
		_disable(attacker)
	changed.emit()


func _disable(attacker: Node3D) -> void:
	disabled = true
	times_disabled += 1
	# Kept at 1 hull so it can be repaired (Durability ignores repairs at 0).
	durability.hull = 1.0
	var by := ""
	if is_instance_valid(attacker) and attacker.has_method(&"get_display_name"):
		by = " by %s" % String(attacker.call(&"get_display_name"))
	var what := "docking pads closed until repaired" if building == null else "shuttles and hiring stopped until repaired"
	EventLog.post("%s disabled%s: %s" % [label, by, what], EventLog.Kind.LOSS, _focus())
	disabled_changed.emit(true)


func _focus() -> Node3D:
	return building if building else self


# --- Repairs ------------------------------------------------------------------

## Credits to bring the hull back to full.
func cost_to_repair() -> int:
	if durability == null:
		return 0
	return ceili(maxf(durability.max_hull - durability.hull, 0.0) * DefenseStructure.REPAIR_COST_PER_HULL)


func _repair(dt: float) -> void:
	var d := durability
	var points := minf(d.max_hull * repair_rate * dt, d.max_hull - d.hull)
	var cost := points * DefenseStructure.REPAIR_COST_PER_HULL
	if _repair_credit < cost:
		var need := ceili(cost - _repair_credit)
		if Economy.credits < need or not Economy.spend(need):
			if repairing:
				_end_repair()
			return
		_repair_credit += float(need)
		repair_session_paid += need
		repair_total_paid += need
	_repair_credit -= cost
	d.repair(points)
	if not repairing:
		repairing = true
		changed.emit()
	if d.hull >= d.max_hull:
		_end_repair()


func _end_repair() -> void:
	if not repairing and repair_session_paid <= 0:
		return
	repairing = false
	var paid := repair_session_paid
	repair_session_paid = 0
	if paid > 0:
		EventLog.post("%s repaired by the station: -%d cr" % [label, paid], EventLog.Kind.INFO, _focus(), Vector3.INF, "repairs:" + label)
	changed.emit()


# --- Save ---------------------------------------------------------------------

func save_state() -> Dictionary:
	var d := SaveUtil.props(self, ["disabled", "repairing", "repair_session_paid", "repair_total_paid", "times_disabled", "_repair_credit"])
	d["durability"] = SaveUtil.durability(durability)
	return d


func load_state(d: Dictionary, refs: SaveRefs) -> void:
	var fields := d.duplicate()
	fields.erase("durability")
	SaveUtil.apply_props(self, fields)
	SaveUtil.set_durability(durability, d.get("durability", {}), refs)
	changed.emit()

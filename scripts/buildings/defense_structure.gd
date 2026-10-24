class_name DefenseStructure
extends Node3D
## Base for the station's armed structures (Defense Turret, Shield
## Generator): the building's service node (BuildingDef.service_script) and
## the combatant raiders shoot at (see [Combat]). Hull and a small shield
## ([Durability]); the station patches the hull up on its own once it has
## not been hit for [member repair_delay] sim seconds, at
## [member repair_rate] of max hull per second, and the player pays
## [constant REPAIR_COST_PER_HULL] per point (RepairBay's rate less the share
## the station keeps from captains: the station pays the yard, not itself).
## No credits, no repairs. One feed line per repair session.
## Destroyed: explosion, a scrap field, the building is removed (the slot
## is free to build again).
## Sits [member aim_height] above the building origin so tracers hit the body.

signal changed

const REPAIR_COST_PER_HULL := RepairBay.COST_PER_HULL * (1.0 - RepairBay.PLAYER_SHARE)

@export var max_hull: float = 500.0
@export var max_shields: float = 100.0
@export var shield_regen: float = 8.0
@export var shield_delay: float = 5.0
## Sim seconds without a hit before hull repairs start.
@export var repair_delay: float = 8.0
## Hull repaired per sim second, share of max hull.
@export var repair_rate: float = 0.012
@export var hit_radius: float = 12.0
@export var aim_height: float = 12.0
@export var scrap_amount: int = 60
@export var explosion_size: float = 20.0

var building: Building
var durability: Durability
var dead := false
## Credits paid for repairs this session / ever.
var repair_session_paid: int = 0
var repair_total_paid: int = 0
## Repairing right now.
var repairing := false

var _repair_credit := 0.0
## Meshes recoloured alone: MeshInstance3D -> its own material (set as the
## material override; the construction look replaces it while building).
var _own_mats: Dictionary = {}


## Called by Building after the node is added (see BuildingDef.service_script).
func setup(owner_building: Building) -> void:
	building = owner_building
	position = Vector3(0.0, aim_height, 0.0)
	durability = Durability.new(max_hull, max_shields, shield_regen)
	durability.shield_delay = shield_delay
	add_to_group(Combat.GROUP)
	add_to_group(SimStepper.GROUP)
	building.state_changed.connect(_on_building_state)
	_on_setup()


func _process(delta: float) -> void:
	if building == null:
		return
	if not SimClock.paused:
		sim_step(delta * SimClock.speed)
	_animate(delta)


func sim_step(dt: float) -> void:
	if dead or dt <= 0.0 or building == null:
		return
	durability.step(dt)
	if building.is_active() and durability.hull < durability.max_hull and durability.seconds_since_hit() >= repair_delay:
		_repair(dt)
	elif repairing:
		_end_repair()
	_step(dt)


func is_active() -> bool:
	return not dead and building != null and building.is_active()


func get_status_text() -> String:
	if dead:
		return "Destroyed"
	return "Active, repairing" if repairing else "Active"


func hull_fraction() -> float:
	return durability.fraction() if durability else 1.0


func shield_fraction() -> float:
	return durability.shield_fraction() if durability else 0.0


# --- Combatant API (see Combat) ---------------------------------------------

func get_faction() -> int:
	return Combat.Faction.PLAYER


func is_alive() -> bool:
	return not dead and building != null


func is_targetable() -> bool:
	return is_active() and is_inside_tree()


func get_hit_radius() -> float:
	return hit_radius


func get_aim_velocity() -> Vector3:
	return SpaceNav.world_velocity(building) if building else Vector3.ZERO


func get_dodge() -> float:
	return 0.0


func get_display_name() -> String:
	return building.display_name if building else String(name)


func take_hit(amount: float, attacker: Node3D, _at: Vector3) -> void:
	if dead or not is_active():
		return
	durability.apply(amount, attacker)
	if repairing:
		_end_repair()
	_on_damaged(amount, attacker)
	changed.emit()
	if durability.is_dead():
		destroy(attacker)


## Blows the structure up: explosion, scrap field, feed line; the building
## is removed.
func destroy(killer: Node3D = null) -> void:
	if dead:
		return
	dead = true
	_end_repair()
	var pos := global_position
	var world := CombatWorld.of(get_tree())
	if world:
		world.fx.explode(pos, explosion_size)
		world.spawn_scrap(Vector3(pos.x, building.global_position.y, pos.z), scrap_amount, world.ship_scrap_life, 30.0, "%s wreck" % get_display_name())
	var by := ""
	if is_instance_valid(killer) and killer.has_method(&"get_display_name"):
		by = " by %s" % String(killer.call(&"get_display_name"))
	EventLog.post("%s destroyed%s" % [get_display_name(), by], EventLog.Kind.LOSS, null, pos)
	remove_from_group(Combat.GROUP)
	_on_destroyed()
	changed.emit()
	if world:
		world.notify_destroyed(self, killer)
	var mgr := get_tree().get_first_node_in_group(BuildingManager.GROUP) as BuildingManager
	if mgr:
		mgr.remove_building(building)
	else:
		building.queue_free()


# --- Repairs ------------------------------------------------------------------

## Credits to bring the hull back to full.
func cost_to_repair() -> int:
	if durability == null:
		return 0
	return ceili(maxf(durability.max_hull - durability.hull, 0.0) * REPAIR_COST_PER_HULL)


func _repair(dt: float) -> void:
	var d := durability
	var points := minf(d.max_hull * repair_rate * dt, d.max_hull - d.hull)
	var cost := points * REPAIR_COST_PER_HULL
	if _repair_credit < cost:
		# Whole credits up front; the change is kept for the next step.
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
	if paid > 0 and building:
		EventLog.post("%s repaired by the station: -%d cr" % [get_display_name(), paid], EventLog.Kind.INFO, building, Vector3.INF, "repairs:" + get_display_name())
	changed.emit()


# --- Hooks for subclasses -----------------------------------------------------

func _on_setup() -> void:
	pass


func _step(_dt: float) -> void:
	pass


## Per frame (real delta), after the sim step.
func _animate(_delta: float) -> void:
	pass


func _on_damaged(_amount: float, _attacker: Node3D) -> void:
	pass


func _on_destroyed() -> void:
	pass


## Puts the own materials back once construction is done (the construction
## look clears every material override).
func _on_building_state(_b: Building) -> void:
	if not building.is_active():
		return
	for mi: MeshInstance3D in _own_mats:
		if is_instance_valid(mi):
			mi.material_override = _own_mats[mi]


## Material of [param mesh_name]'s first surface, duplicated and set as its
## material override so it can be recoloured alone. Null when missing.
func _own_material(mesh_name: String) -> StandardMaterial3D:
	var model := building.get_model() if building else null
	var mi := model.find_child(mesh_name, true, false) as MeshInstance3D if model else null
	if mi == null or mi.mesh == null:
		return null
	var src := mi.get_active_material(0) as StandardMaterial3D
	if src == null:
		return null
	var m := src.duplicate() as StandardMaterial3D
	m.emission_enabled = true
	if m.emission == Color.BLACK:
		m.emission = m.albedo_color
	mi.material_override = m
	_own_mats[mi] = m
	return m


# --- Save ---------------------------------------------------------------------

func save_state() -> Dictionary:
	var d := SaveUtil.props(self, ["repair_session_paid", "repair_total_paid", "repairing", "_repair_credit"])
	d["durability"] = SaveUtil.durability(durability)
	_save_extra(d)
	return d


func load_state(d: Dictionary, refs: SaveRefs) -> void:
	var fields := d.duplicate()
	fields.erase("durability")
	fields.erase("extra")
	SaveUtil.apply_props(self, fields)
	SaveUtil.set_durability(durability, d.get("durability", {}), refs)
	_load_extra(d.get("extra", {}))
	changed.emit()


## Subclass state, under "extra".
func _save_extra(_d: Dictionary) -> void:
	pass


func _load_extra(_d: Dictionary) -> void:
	pass

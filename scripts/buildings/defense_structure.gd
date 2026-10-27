class_name DefenseStructure
extends StaticCombatant
## Base for the station's armed structures (Defense Turret, Shield
## Generator): the building's service node (BuildingDef.service_script) and
## the combatant raiders shoot at (see [Combat]). Hull and a small shield
## ([Durability]); the station patches the hull up on its own once it has
## not been hit for [member repair_delay] sim seconds, at
## [member repair_rate] of max hull per second, and the player pays
## [constant REPAIR_COST_PER_HULL] per point ([StructureRepair]). No
## credits, no repairs. One feed line per repair session.
## Destroyed: explosion, a scrap field, the building is removed (the slot
## is free to build again).
## Sits [member aim_height] above the building origin so tracers hit the body.

signal changed

const REPAIR_COST_PER_HULL := StructureRepair.COST_PER_HULL

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
var repair := StructureRepair.new()

## Meshes recoloured alone: MeshInstance3D -> its own material (set as the
## material override; the construction look replaces it while building).
var _own_mats: Dictionary = {}


## Called by Building after the node is added (see BuildingDef.service_script).
func setup(owner_building: Building) -> void:
	building = owner_building
	position = Vector3(0.0, aim_height, 0.0)
	durability = Durability.new(max_hull, max_shields, shield_regen)
	durability.shield_delay = shield_delay
	repair.changed.connect(changed.emit)
	repair.session_ended.connect(_on_repair_ended)
	add_to_group(Combat.GROUP)
	add_to_group(SimStepper.GROUP)
	building.state_changed.connect(_on_building_state)
	_on_setup()


func _process(delta: float) -> void:
	if building == null:
		return
	# Substepped: the guns' fire rate holds at high sim speed.
	SimClock.substep(sim_step)
	_animate(delta)


func sim_step(dt: float) -> void:
	if dead or dt <= 0.0 or building == null:
		return
	durability.step(dt)
	repair.step(durability, dt, building.is_active(), repair_delay, repair_rate)
	_step(dt)


func is_active() -> bool:
	return not dead and building != null and building.is_active()


func get_status_text() -> String:
	if dead:
		return "Destroyed"
	return "Active, repairing" if repair.repairing else "Active"


func hull_fraction() -> float:
	return durability.fraction() if durability else 1.0


func shield_fraction() -> float:
	return durability.shield_fraction() if durability else 0.0


# --- Combatant API (see Combat) ---------------------------------------------

func is_alive() -> bool:
	return not dead and building != null


func is_targetable() -> bool:
	return is_active() and is_inside_tree()


func get_hit_radius() -> float:
	return hit_radius


func get_aim_velocity() -> Vector3:
	return SpaceNav.world_velocity(building) if building else Vector3.ZERO


func get_display_name() -> String:
	return building.display_name if building else String(name)


func take_hit(amount: float, attacker: Node3D, _at: Vector3) -> void:
	if dead or not is_active():
		return
	durability.apply(amount, attacker)
	if repair.repairing:
		repair.end_session()
	ColonyAlarm.raise(self, self, get_display_name(), attacker)
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
	repair.end_session()
	var pos := global_position
	var world := CombatWorld.of(self)
	if world:
		world.fx.explode(pos, explosion_size)
		world.spawn_scrap(Vector3(pos.x, building.global_position.y, pos.z), scrap_amount, world.ship_scrap_life, 30.0, "%s wreck" % get_display_name())
	var by := Combat.by_suffix(killer)
	EventLog.post("%s destroyed%s" % [get_display_name(), by], EventLog.Kind.LOSS, null, pos)
	remove_from_group(Combat.GROUP)
	_on_destroyed()
	changed.emit()
	if world:
		world.notify_destroyed(self, killer)
	var mgr := BuildingManager.of(self)
	if mgr:
		mgr.remove_building(building)
	else:
		building.queue_free()


# --- Repairs ------------------------------------------------------------------

## Credits to bring the hull back to full.
func cost_to_repair() -> int:
	return StructureRepair.cost_to_repair(durability)


func _on_repair_ended(paid: int) -> void:
	if paid > 0 and building:
		EventLog.post("%s repaired by the station: -%d cr" % [get_display_name(), paid], EventLog.Kind.INFO, building, Vector3.INF, "repairs:" + get_display_name())


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
	var d := SaveUtil.props_and_durability(repair, StructureRepair.FIELDS, durability)
	_save_extra(d)
	return d


func load_state(d: Dictionary, refs: SaveRefs) -> void:
	SaveUtil.apply_props_and_durability(self, d, durability, refs, StructureRepair.FIELDS + PackedStringArray(["extra"]))
	repair.load_state(d)
	_load_extra(d.get("extra", {}))
	changed.emit()


## Subclass state, under "extra".
func _save_extra(_d: Dictionary) -> void:
	pass


func _load_extra(_d: Dictionary) -> void:
	pass

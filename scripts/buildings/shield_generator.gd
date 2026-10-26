class_name ShieldGenerator
extends DefenseStructure
## Service node of the Shield Generator: projects the station shield bubble
## ([StationShield]) over the whole complex once built. The bubble lives in
## the Structures frame (it is centred on the complex, not on the
## generator). The generator itself can be shot once the bubble is down;
## destroyed, the bubble goes down until a new one is built.
## Look: shield_emitter_glow pulses with the bubble's charge and dims while
## it is down; shield_capacitors fill (scale Y) with the charge.

const EMITTER := "shield_emitter_glow"
const CAPACITORS := "shield_capacitors"

var shield: StationShield

var _glow_mat: StandardMaterial3D
var _glow_base := 2.0
var _caps: Node3D
var _caps_scale := Vector3.ONE
var _shown_charge := 0.0


func _init() -> void:
	max_hull = 900.0
	max_shields = 150.0
	shield_regen = 10.0
	hit_radius = 22.0
	aim_height = 18.0
	scrap_amount = 120
	explosion_size = 30.0


func _on_setup() -> void:
	var mgr := BuildingManager.of(building)
	shield = StationShield.new()
	shield.setup(self, mgr)
	var frame := building.get_parent()
	if frame:
		frame.add_child(shield)
	_glow_mat = _own_material(EMITTER)
	if _glow_mat:
		_glow_base = maxf(_glow_mat.emission_energy_multiplier, 2.0)
	var model := building.get_model()
	_caps = model.find_child(CAPACITORS, true, false) as Node3D if model else null
	if _caps:
		_caps_scale = _caps.scale


## Only once the bubble is down: inside it, the generator is shielded anyway.
func is_targetable() -> bool:
	return super.is_targetable() and not (is_instance_valid(shield) and shield.is_up())


func get_status_text() -> String:
	if dead:
		return "Destroyed"
	if not is_instance_valid(shield):
		return "No shield"
	var text := "Shield %s" % shield.get_state_name().to_lower()
	if shield.is_up():
		text += " %d%%" % roundi(shield.charge() * 100.0)
	elif shield.state == StationShield.State.DOWN:
		text += ", back in %d s" % ceili(shield.cooldown_left)
	return text + (", repairing" if repair.repairing else "")


func _on_destroyed() -> void:
	if is_instance_valid(shield):
		shield.shutdown()


## Removed some other way: the bubble goes too.
func _exit_tree() -> void:
	if is_instance_valid(shield) and shield.is_alive():
		shield.shutdown()


func _animate(delta: float) -> void:
	var k := shield.charge() if is_instance_valid(shield) and is_active() else 0.0
	_shown_charge = lerpf(_shown_charge, k, clampf(delta * 3.0, 0.0, 1.0))
	if _caps:
		_caps.scale = Vector3(_caps_scale.x, _caps_scale.y * maxf(_shown_charge, 0.04), _caps_scale.z)
	if _glow_mat:
		var up := is_instance_valid(shield) and shield.is_up() and is_active()
		var pulse := 0.85 + 0.15 * sin(SimClock.time * lerpf(1.2, 3.5, 1.0 - _shown_charge) * TAU * 0.5)
		_glow_mat.emission_energy_multiplier = _glow_base * (lerpf(0.35, 1.0, _shown_charge) * pulse if up else 0.12)


func _save_extra(d: Dictionary) -> void:
	d["extra"] = {"shield": shield.save_state() if is_instance_valid(shield) else {}}


func _load_extra(d: Dictionary) -> void:
	if is_instance_valid(shield):
		shield.load_state(d.get("shield", {}))

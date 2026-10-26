class_name ExplorerShip
extends Ship
## A hired explorer (P3): an Explorer Outpost scout on explore contracts.
## Unarmed and quick; the decisions and the survey flight are
## ExplorerBrain's (gates out, the waypoint rings of [Survey], gates home),
## this class only sets the role and turns the sensor dish while it surveys.
## Model: assets/models/ships/explorer.glb (nose -Z, "engine_glow" plume on
## +Z, "sensor_dish" turned about its local Y, "scan_point" at the sensor tip).

const DISH_NODE := "sensor_dish"
## Dish turn rate while surveying, degrees per sim second.
const DISH_RATE_DEG := 40.0

var _dish: Node3D


func _init() -> void:
	role = Role.EXPLORER
	hit_radius = 9.0


func _make_brain() -> CaptainBrain:
	return ExplorerBrain.new(self, ExplorerEvaluator.new())


func _on_ready_ship() -> void:
	role = Role.EXPLORER
	_dish = _model.find_child(DISH_NODE, true, false) as Node3D if _model else null
	set_meta(&"focus_distance", 140.0)


func _on_damaged(_amount: float, attacker: Node3D) -> void:
	var eb := brain as ExplorerBrain
	if eb:
		eb.on_attacked(attacker)


## True while it sweeps a system.
func is_surveying() -> bool:
	return brain != null and transit == null and brain.state == CaptainBrain.State.SURVEYING


func _apply_visuals(dt: float) -> void:
	super._apply_visuals(dt)
	if _dish and dt > 0.0 and is_surveying():
		_dish.rotate_object_local(Vector3.UP, deg_to_rad(DISH_RATE_DEG) * dt)

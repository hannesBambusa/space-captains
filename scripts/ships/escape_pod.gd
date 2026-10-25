class_name EscapePod
extends Ship
## A captain's escape pod after their ship was destroyed. Slow and fragile:
## it flies straight home on its own (no brain) at [constant SPEED] relative
## to its orbiting outpost, and scavengers and raiders
## may shoot it down, which kills the captain for good. At the home outpost
## the captain climbs out and waits there without a ship
## ([method Building.receive_pod]) until a new one is bought.
## Model: assets/models/ships/escape_pod.glb (capsule placeholder if missing).

const MODEL_PATH := "res://assets/models/ships/escape_pod.glb"
## Closing speed on the (orbiting) home outpost, m/s.
const SPEED := 60.0
## Arrival distance from the outpost's approach point, metres.
const ARRIVE_DISTANCE := 90.0


func _init() -> void:
	role = Role.POD
	hit_radius = 4.0


## Call before adding to the tree. [param home_building] may be null (the
## outpost is gone): the pod then makes for the Home Station.
func setup_pod(pod_captain: Captain, home_building: Building) -> void:
	captain = pod_captain
	home = home_building
	slot_index = 0
	_model_path = MODEL_PATH
	captain.ship = self
	name = StringName(("Pod_%s" % captain.captain_name).validate_node_name().replace(" ", ""))
	var l := ShipLoadout.new()
	l.role_name = "Pod"
	l.base_hull = 70.0
	l.base_speed = SPEED
	l.base_acceleration = 14.0
	l.base_turn_rate_deg = 80.0
	l.base_sensor_range = 600.0
	loadout = l


func _on_ready_ship() -> void:
	set_meta(&"focus_distance", 90.0)
	mover.avoid_enabled = true


func _fallback_model() -> Node3D:
	return ModelLoader.pod_placeholder()


func _leaves_scrap() -> bool:
	return false


func get_status_text() -> String:
	return "Escape pod, going home"


func sim_step(dt: float) -> void:
	super.sim_step(dt)
	if dead:
		return
	var goal := _goal()
	# The outpost orbits at ~100 m/s: the pod's top speed is relative to it.
	mover.max_speed = SPEED + (goal["vel"] as Vector3).length()
	set_world_goal(goal["pos"], goal["vel"], Vector3.ZERO, 30.0)
	if global_position.distance_to(goal["pos"]) < ARRIVE_DISTANCE:
		_arrive()


func _goal() -> Dictionary:
	if is_instance_valid(home):
		var p := home.to_global(home.approach_point())
		return {"pos": p, "vel": SpaceNav.world_velocity(home)}
	var sys := SolarSystem.of(get_tree())
	if sys and sys.home_station:
		var st := sys.home_station
		return {"pos": st.global_position, "vel": SpaceNav.world_velocity(st)}
	return {"pos": global_position, "vel": Vector3.ZERO}


## Home: the captain waits at the outpost (or retires when it is gone).
func _arrive() -> void:
	dead = true
	if captain and captain.ship == self:
		captain.ship = null
	if is_instance_valid(home):
		home.receive_pod(captain)
	elif captain:
		captain.alive = false
		EventLog.post("%s reached the station with no outpost to return to and retired" % captain.captain_name, EventLog.Kind.LOSS)
	_leave_world()


func _on_destroyed(killer: Node3D) -> void:
	if captain == null:
		return
	captain.alive = false
	if captain.ship == self:
		captain.ship = null
	if is_instance_valid(home):
		home.forget_captain(captain)
	var by := Combat.by_suffix(killer)
	EventLog.post("%s was killed in their escape pod%s" % [captain.captain_name, by], EventLog.Kind.LOSS, null, global_position)

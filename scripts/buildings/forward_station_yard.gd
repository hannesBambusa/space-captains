class_name ForwardStationYard
extends Node
## Service of the Forward Station structure (BuildingDef "forward_station",
## home only, research Forward operations). The build site is an ordinary
## construction (the forward station model rises under the drones); when it
## is finished the site becomes a [MobileStation] in open space at the same
## spot, parked beside the complex, and the structure is taken off the
## station's list (no refund: the cost bought the station).

var building: Building


func setup(b: Building) -> void:
	building = b
	b.state_changed.connect(_on_state_changed)


func _ready() -> void:
	# Finished at once (tests, a load of a finished site): convert next frame.
	if building and building.is_active():
		_launch.call_deferred()


func _on_state_changed(b: Building) -> void:
	if b.is_active():
		_launch()


func _launch() -> void:
	if building == null or not is_instance_valid(building) or not building.is_inside_tree() or building.is_queued_for_deletion():
		return
	var mgr := BuildingManager.of(building)
	var at := building.global_position
	var yaw := building.global_rotation.y
	var ms := MobileStation.new()
	ms.setup_station(0, building.get_tree())
	SpaceNav.space_root(building).add_child(ms)
	ms.mover.avoid_enabled = true
	ms.place_in_space(at, yaw, SpaceNav.world_velocity(building))
	if mgr:
		ms.park_offset = mgr.frame.to_local(at)
		mgr.remove_building(building)
	EventLog.post("%s is ready beside the station: select it and set a destination" % ms.get_display_name(), EventLog.Kind.REWARD, ms)
	building = null

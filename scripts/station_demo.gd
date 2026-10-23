class_name StationDemo
extends Node
## Station complex setups for screenshots (user args after "--"):
##   --station-demo           builds [member layout] (finished, each linked to
##                            the complex by its corridor) and frames the complex.
##   --station-demo=placing   ... then arms placement of [member ghost_def_index]
##                            with the ghost on a valid spot (preview corridor).
##   --station-demo=building  ... the last structure (and its corridor) still
##                            under construction (~50 %).
## Spots are searched like a player would pick them: valid link, near the
## station, spread round it. --cam / --focus (ScreenshotMode) override the view.

## Building def indices (BuildingManager.building_defs) in build order.
@export var layout: PackedInt32Array = PackedInt32Array([0, 1, 2, 3, 0, 1, 3, 0])
@export var ghost_def_index: int = 3
## Search rings (distance from the station, m) and angle step.
@export var search_radii: Vector2 = Vector2(170.0, 1400.0)
@export var search_step: float = 25.0
@export var search_angle_deg: float = 9.0
## Weight of the angle from the preferred direction against distance (m per radian).
@export var spread_weight: float = 160.0
## First preferred direction (degrees) and the turn per structure.
@export var start_angle_deg: float = -20.0
@export var turn_deg: float = 137.5
@export var view_pitch_deg: float = 58.0

var _ghost_offset := Vector3.INF


func _ready() -> void:
	var view := ""
	var on := false
	var has_view := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--station-demo":
			on = true
		elif arg.begins_with("--station-demo="):
			on = true
			view = arg.trim_prefix("--station-demo=")
		elif arg.begins_with("--cam=") or arg.begins_with("--focus="):
			has_view = true
	set_process(false)
	if on:
		_run(view, has_view)


func _run(view: String, has_view: bool) -> void:
	for i in 3:
		await get_tree().process_frame
	var tree := get_tree()
	var manager := tree.get_first_node_in_group(BuildingManager.GROUP) as BuildingManager
	var hud := tree.get_first_node_in_group(HUD.GROUP) as HUD
	var cam := tree.get_first_node_in_group("rts_camera") as RTSCamera
	if manager == null or hud == null or not manager.has_zone() or manager.building_defs.is_empty():
		push_warning("StationDemo: missing building manager, HUD or build zone")
		return
	var built: Array[Building] = []
	for i in layout.size():
		var def := manager.building_defs[layout[i] % manager.building_defs.size()]
		var spot := find_spot(manager, def, deg_to_rad(start_angle_deg + turn_deg * i))
		if spot == Vector3.INF:
			push_warning("StationDemo: no valid spot for %s" % def.display_name)
			continue
		var p := manager.plan_placement(def, spot, false)
		var b := manager.spawn_finished(def, spot, p.yaw)
		built.append(b)
	if view == "building" and not built.is_empty():
		var last := built[built.size() - 1]
		# Back under construction half way; its corridor follows.
		built[built.size() - 1].set_construction_progress(0.5)
	print("StationDemo: %d structures, %d corridors" % [built.size(), manager.links.corridors.size()])
	if not has_view and cam and manager.solar_system.home_station:
		var box := manager.links.complex_bounds()
		var c := box.get_center()
		var radius := maxf(box.size.x, box.size.y) * 0.5 * 1.1 + 40.0
		cam.frame_area(manager.solar_system.home_station, Vector3(c.x, 0.0, c.y), radius, view_pitch_deg, false, true)
	if view == "placing":
		var def := manager.building_defs[ghost_def_index % manager.building_defs.size()]
		_ghost_offset = find_spot(manager, def, deg_to_rad(start_angle_deg + turn_deg * layout.size()))
		hud.placement.arm(def)
		set_process(true)


## Valid spot for [param def] near the station, close to direction
## [param prefer] (radians, atan2(x, z)); Vector3.INF when none.
func find_spot(manager: BuildingManager, def: BuildingDef, prefer: float) -> Vector3:
	var best := Vector3.INF
	var best_score := INF
	var d := search_radii.x
	while d <= search_radii.y:
		var a := 0.0
		while a < 360.0:
			var ang := deg_to_rad(a)
			var spot := Vector3(sin(ang), 0.0, cos(ang)) * d
			var score := d + absf(angle_difference(ang, prefer)) * spread_weight
			if score < best_score and manager.plan_placement(def, spot, false).is_valid():
				best_score = score
				best = spot
			a += search_angle_deg
		d += search_step
	return best


func _process(_delta: float) -> void:
	var tree := get_tree()
	var manager := tree.get_first_node_in_group(BuildingManager.GROUP) as BuildingManager
	var placement := tree.get_first_node_in_group(PlacementController.GROUP) as PlacementController
	var cam := get_viewport().get_camera_3d()
	if manager == null or placement == null or cam == null or _ghost_offset == Vector3.INF:
		return
	placement.cursor_override = cam.unproject_position(manager.to_world(_ghost_offset))

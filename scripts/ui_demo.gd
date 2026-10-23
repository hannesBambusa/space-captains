class_name UIDemo
extends Node
## Screenshot setups for checking the UI (user args after "--"):
##   --ui-demo              Mining Outpost near the station (finished), 2 miners
##                          hired, overview open, outpost selected.
##   --ui-demo=construct    same outpost, still under construction (~45 %).
##   --build-ghost          placement armed, ghost on a valid spot, zone shown.
##   --build-ghost=invalid  ghost on an invalid spot (against the station).
## Without --cam/--focus the camera follows the outpost (or the station).

## Station-relative spot used for the demo outpost and the valid ghost.
@export var demo_offset: Vector3 = Vector3(115.0, 0.0, 80.0)
@export var invalid_offset: Vector3 = Vector3(70.0, 0.0, -40.0)
## Valid ghost spot: within corridor reach of the station.
@export var ghost_offset: Vector3 = Vector3(-75.0, 0.0, 125.0)
@export var demo_seed: int = 7

var _ghost_offset := Vector3.INF


func _ready() -> void:
	var demo := ""
	var ghost := ""
	var has_view := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--ui-demo":
			demo = "done"
		elif arg.begins_with("--ui-demo="):
			demo = arg.trim_prefix("--ui-demo=")
		elif arg == "--build-ghost":
			ghost = "valid"
		elif arg.begins_with("--build-ghost="):
			ghost = arg.trim_prefix("--build-ghost=")
		elif arg.begins_with("--cam=") or arg.begins_with("--focus="):
			has_view = true
	set_process(false)
	if demo.is_empty() and ghost.is_empty():
		return
	_run(demo, ghost, has_view)


func _run(demo: String, ghost: String, has_view: bool) -> void:
	# Let the system, the camera and ScreenshotMode's view settle first.
	for i in 3:
		await get_tree().process_frame
	var tree := get_tree()
	var manager := tree.get_first_node_in_group(BuildingManager.GROUP) as BuildingManager
	var hud := tree.get_first_node_in_group(HUD.GROUP) as HUD
	var cam := tree.get_first_node_in_group("rts_camera") as RTSCamera
	if manager == null or hud == null or not manager.has_zone() or manager.building_defs.is_empty():
		push_warning("UIDemo: missing building manager, HUD or build zone")
		return
	var def := manager.building_defs[0]
	manager.rng.seed = demo_seed
	if not demo.is_empty():
		var b := manager.place(def, demo_offset, deg_to_rad(-30.0))
		if b == null:
			b = manager.spawn_finished(def, demo_offset, deg_to_rad(-30.0))
		if demo == "construct":
			b.started_at = SimClock.time - def.build_time * 0.45
		else:
			b.finish_construction()
			for i in 2:
				var s := b.hire()
				if s:
					s.snap_to_slot()
		hud.overview.set_open(true)
		hud.selection.select(b)
		if not has_view and cam:
			cam.focus_on(b, 420.0, true)
	if not ghost.is_empty():
		_ghost_offset = invalid_offset if ghost == "invalid" else ghost_offset
		hud.placement.arm(def)
		if not has_view and cam and manager.solar_system.home_station:
			cam.focus_on(manager.solar_system.home_station, 900.0, true)
		set_process(true)


func _process(_delta: float) -> void:
	var tree := get_tree()
	var manager := tree.get_first_node_in_group(BuildingManager.GROUP) as BuildingManager
	var placement := tree.get_first_node_in_group(PlacementController.GROUP) as PlacementController
	var cam := get_viewport().get_camera_3d()
	if manager == null or placement == null or cam == null or _ghost_offset == Vector3.INF:
		return
	placement.cursor_override = cam.unproject_position(manager.to_world(_ghost_offset))

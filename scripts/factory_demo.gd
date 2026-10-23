class_name FactoryDemo
extends Node
## Factory setups for screenshots (user args after "--"):
##   --factory-demo           mining outpost and Outfitter, two miners on
##                            Cinder Belt and a mercenary; fast-forwards a few
##                            minutes of auto-sell and production, tools the
##                            Factory for Mk II. The Factory is selected (its
##                            panel open) and framed.
##   --factory-demo=complex   the same, framing the whole station complex.
## --cam / --focus (ScreenshotMode) override the demo camera.

@export var mining_offset: Vector3 = Vector3(115.0, 0.0, 80.0)
@export var outfitter_offset: Vector3 = Vector3(-27.0, 0.0, -134.0)
@export var merc_offset: Vector3 = Vector3(-96.0, 0.0, 104.0)
@export var demo_seed: int = 17
@export var run_seconds: float = 360.0
@export var view_distance: float = 330.0
@export var view_pitch_deg: float = 55.0


func _ready() -> void:
	var view := ""
	var on := false
	var has_view := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--factory-demo":
			on = true
		elif arg.begins_with("--factory-demo="):
			on = true
			view = arg.trim_prefix("--factory-demo=")
		elif arg.begins_with("--cam=") or arg.begins_with("--focus="):
			has_view = true
	if on:
		_run(view, has_view)


func _run(view: String, has_view: bool) -> void:
	for i in 3:
		await get_tree().process_frame
	var tree := get_tree()
	var manager := tree.get_first_node_in_group(BuildingManager.GROUP) as BuildingManager
	var hud := tree.get_first_node_in_group(HUD.GROUP) as HUD
	var cam := tree.get_first_node_in_group("rts_camera") as RTSCamera
	var world := CombatWorld.of(tree)
	if manager == null or hud == null or manager.factory_building == null or manager.building_defs.size() < 3:
		push_warning("FactoryDemo: missing building manager, HUD or Factory")
		return
	if world:
		world.raids.enabled = false
	seed(demo_seed)
	manager.rng.seed = demo_seed
	var factory := manager.get_factory()
	var mine := manager.spawn_finished(manager.building_defs[0], mining_offset, deg_to_rad(-30.0))
	var merc := manager.spawn_finished(manager.building_defs[1], merc_offset, deg_to_rad(25.0))
	var outf := manager.spawn_finished(manager.building_defs[2], outfitter_offset, deg_to_rad(160.0))
	await tree.process_frame
	for p: int in [0, 2]:
		var s := mine.hire(p)
		if s:
			s.snap_to_slot()
			s.captain.wallet = 500
	var m := merc.hire(1)
	if m:
		m.snap_to_slot()
	var cinder: SystemBelt = null
	for b in manager.solar_system.belts:
		if b.def.name == "Cinder Belt":
			cinder = b
	if cinder:
		ContractBoard.post_mining(cinder, ContractBoard.mining_rules.default_reward(cinder))
	Economy.set_ore(560, 260, 40)
	factory.upgrade_tooling()
	SimStepper.run(tree, run_seconds)
	Economy.tick_grant()
	print("FactoryDemo: %s, stock %s, warehouse %d, sold %s for %d cr, outfitter sales %d" % [factory.status_text(), factory.market.stock,
			factory.warehouse_total(), factory.market.total_units, factory.market.total_credits, (outf.get_service() as Outfitter).sales.size()])
	var fb := manager.factory_building
	if view != "complex":
		hud.selection.select(fb)
	if has_view or cam == null:
		return
	if view == "complex":
		var box := manager.links.complex_bounds()
		var c := box.get_center()
		var radius := maxf(box.size.x, box.size.y) * 0.5 * 1.1 + 40.0
		cam.frame_area(manager.solar_system.home_station, Vector3(c.x, 0.0, c.y), radius, view_pitch_deg, false, true)
	else:
		# Look at the dock mouth side, the station behind it, the panel on the right.
		var out := fb.global_basis.z
		cam.set_yaw(rad_to_deg(atan2(out.x, out.z)) - 35.0, true)
		cam.focus_on(fb, view_distance, true)

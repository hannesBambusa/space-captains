extends Node
## Headless check of [RideAlong]: rides a mercenary at home, through a gate
## round trip to Ostra and back, then stops it by panning. Prints "RIDE ..."
## lines; exit 1 on a failed check. Run:
## Godot --headless --path . res://tools/ride_along_test.tscn

var _fails: PackedStringArray = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.autosave_interval = 1e12
	Tutorial.write_settings = false
	_run.call_deferred()


func _ok(cond: bool, what: String) -> void:
	print("RIDE %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails.append(what)


## Waits real frames until [param test] holds, at most [param seconds].
func _until(test: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if test.call():
			return true
		await get_tree().process_frame
	return test.call()


## With a window and "-- --shot=/abs/dir": saves <dir>/ride_<tag>.png.
func _shot(tag: String) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			for i in 30:
				await get_tree().process_frame
			var img := get_viewport().get_texture().get_image()
			img.save_png(arg.trim_prefix("--shot=").path_join("ride_%s.png" % tag))


func _run() -> void:
	var tree := get_tree()
	var dummy := Node.new()
	tree.root.add_child(dummy)
	tree.current_scene = dummy
	await SaveManager.new_game(false)
	for i in 5:
		await tree.process_frame
	var hud := Tutorial.of(tree).hud
	hud.tutorial.finish()
	var mgr := hud.manager
	var def := mgr.def_by_id(&"mercenary_outpost")
	var b: Building = null
	for ring in range(1, 12):
		for k in 16:
			var a := TAU * float(k) / 16.0
			var off := Vector3(cos(a), 0.0, sin(a)) * (260.0 + ring * 90.0)
			if b == null and mgr.plan_placement(def, off, false).is_valid():
				b = mgr.spawn_finished(def, off)
	_ok(b != null, "merc outpost placed")
	Economy.add(5000, PackedInt32Array(), Ledger.OTHER, "Test credits")
	var s: Ship = b.hire() if b else null
	_ok(s != null and s.captain != null, "merc hired")
	if s == null:
		tree.quit(1)
		return
	var c := s.captain
	var ride := hud.ride_along
	ride.start(c)
	SimClock.set_speed(4.0)
	await _until(func() -> bool: return hud.camera.get_follow_target() == c.ship, 3.0)
	_ok(ride.is_riding() and ride.visible, "riding, banner shown")
	_ok(hud.camera.get_follow_target() == c.ship, "camera follows the ship")
	await _until(func() -> bool: return hud.camera.get_distance() <= RideAlong.CHASE_MAX + 1.0, 4.0)
	_ok(hud.camera.get_distance() <= RideAlong.CHASE_MAX + 1.0, "chase distance %.0f" % hud.camera.get_distance())
	await _until(func() -> bool: return absf(hud.camera.current_pitch_deg() - RideAlong.CHASE_PITCH) < 2.0, 4.0)
	_ok(absf(hud.camera.current_pitch_deg() - RideAlong.CHASE_PITCH) < 2.0, "low chase pitch (%.1f)" % hud.camera.current_pitch_deg())
	print("RIDE status: %s" % ride._status.text)
	await _shot("home")
	var vm := hud.view_manager
	var t := GateTransit.debug_round_trip(tree, "Ostra Gate", 20.0)
	_ok(t != null and t.captain == c, "gate round trip started")
	SimClock.set_speed(24.0)
	var away := await _until(func() -> bool: return vm.viewed_id() != ClusterNetwork.HOME_ID, 90.0)
	_ok(away, "view went to %s with the captain" % vm.viewed_id())
	var there := await _until(func() -> bool:
		return is_instance_valid(c.ship) and c.ship.is_inside_tree() and SystemWorld.of(c.ship) == vm.viewed \
				and hud.camera.get_follow_target() == c.ship, 60.0)
	_ok(there, "camera picked the ship up on the far side")
	await _shot("ostra")
	print("RIDE status: %s" % ride._status.text)
	var back := await _until(func() -> bool:
		return vm.viewed_id() == ClusterNetwork.HOME_ID and is_instance_valid(c.ship) \
				and hud.camera.get_follow_target() == c.ship, 120.0)
	_ok(back, "came home with the captain")
	_ok(ride.is_riding(), "still riding after the round trip")
	SimClock.set_speed(1.0)
	hud.camera.stop_follow()
	await tree.process_frame
	_ok(not ride.is_riding() and not ride.visible, "panning stops the ride")
	tree.quit(0 if _fails.is_empty() else 1)

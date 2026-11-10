extends Node
## Headless check of the tutorial game (Tutorial academy mode): starts it the
## way the main menu does, walks the command chapter by hand, jumps through
## every chapter (top-ups, research grants, the raid gate), reloads the save
## state from memory and quits the tutorial. Prints "TUT ..." lines; exit 1
## on a failed check or a script error. Run: tools/tutorial_test.sh

var _fails: PackedStringArray = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.autosave_interval = 1e12
	Tutorial.write_settings = false
	_run.call_deferred()


func _ok(cond: bool, what: String) -> void:
	print("TUT %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails.append(what)


func _run() -> void:
	var tree := get_tree()
	var dummy := Node.new()
	tree.root.add_child(dummy)
	tree.current_scene = dummy
	await SaveManager.new_game(true)
	for i in 5:
		await tree.process_frame
	var t := Tutorial.of(tree)
	_ok(t != null, "tutorial node")
	if t == null:
		tree.quit(1)
		return
	_ok(t.mode == Tutorial.ACADEMY and t.step == 0, "academy at step 0 (mode %d step %d)" % [t.mode, t.step])
	_ok(not Corps.has_rival(), "no rivals")
	var combat := CombatWorld.of(SystemWorld.home(tree))
	_ok(combat.raids.enabled == false and combat.threats.arrivals == false, "raids and arrivals off")
	await tree.create_timer(0.6).timeout
	var music := AudioDirector.get(&"_tutorial") as AudioStreamPlayer
	_ok(AudioDirector.in_tutorial() and music != null and music.playing, "tutorial music plays")
	_ok(AudioServer.get_bus_effect_count(AudioServer.get_bus_index(&"Music")) > 0, "music bus has the voice duck")
	var card := t.hud.tutorial_card
	_ok(card.voice_key() == "welcome", "voice key welcome")
	var vp := card.get_node_or_null(^"Voice") as AudioStreamPlayer
	if Tutorial.voice_on():
		_ok(vp != null and vp.playing and vp.stream != null, "welcome voice line plays")
	else:
		print("TUT skip voice check: voice is off in this user's settings")
	var replay := card.get(&"_replay_button") as Button
	if Tutorial.voice_on():
		_ok(replay != null and replay.visible, "replay button shows on a voiced step")
		vp.stop()
		replay.pressed.emit()
		_ok(vp.playing and vp.stream.resource_path.ends_with("welcome.mp3"), "replay reads the line again")
	t.advance()
	_ok(t.current()["id"] == &"camera", "welcome -> camera")
	if Tutorial.voice_on():
		_ok(vp != null and vp.playing and vp.stream != null and vp.stream.resource_path.ends_with("camera.mp3"), "camera line replaces the welcome line")
	t.hud.camera.focus_on(t.hud.solar_system.home_station, t.hud.camera.max_distance, true)
	await tree.process_frame
	t._on_camera(Vector3.ZERO, 700.0, 0.0)
	t._on_camera(Vector3(400, 0, 0), 700.0, 0.0)
	t._check()
	if Tutorial.voice_on():
		_ok(t.current()["id"] == &"camera" and t.met, "a met step waits for its line to end")
		vp.stop()
		vp.finished.emit()
	_ok(t.current()["id"] == &"time", "camera -> time once the line ends")
	await tree.process_frame
	_ok(not t.hud.build_menu.visible, "time step leaves the build bar closed (the station step stays open)")
	var pulse := t.hud.get_node_or_null(^"Root/TutorialPulse") as TutorialPulse
	_ok(pulse != null and pulse.target == t.hud.top_bar.speed_control, "time step pulses the speed readout")
	vp.stop()
	SimClock.set_speed(4.0)
	await tree.process_frame
	_ok(t.current()["id"] == &"station", "time -> station")
	var cam := t.hud.camera
	var st := t.hud.solar_system.home_station
	# The camera eases in on real frame time: wait for it (at most 3 real s),
	# not a frame count (headless frames got faster as the sim got cheaper).
	var t_end := Time.get_ticks_msec() + 3000
	while cam.get_distance() > 700.0 and Time.get_ticks_msec() < t_end:
		await tree.process_frame
	print("TUT station view: %.0f m from the station, camera distance %.0f" % [cam.get_pivot().distance_to(st.global_position) if cam.has_method(&"get_pivot") else -1.0, cam.get_distance()])
	_ok(cam.get_distance() <= 700.0, "station step zooms in (%.0f)" % cam.get_distance())
	t.hud.fly_home()
	for i in 3:
		await tree.process_frame
	vp.stop()
	t._check()
	_ok(t.current()["id"] == &"build_mining", "station -> build_mining (%s)" % t.current().get("id"))
	_ok(Economy.credits >= 2000, "mining top-up (%d cr)" % Economy.credits)
	SimClock.set_speed(1.0)
	var chapters := Tutorial.chapters()
	for c in chapters.size():
		t.jump_to_chapter(c)
		await tree.process_frame
		var cur := t.current()
		print("TUT chapter %d %s -> step %s, %d cr, iron %d" % [c, chapters[c]["name"], cur.get("id", "done"), Economy.credits, Economy.ore[0]])
		_ok(t.step >= 0, "chapter %d running" % c)
		for g: StringName in chapters[c]["grants"]:
			_ok(Research.is_done(g), "chapter %d grants %s" % [c, g])
	_ok(t.chapter_of() == chapters.size() - 1, "at the last chapter")
	t.jump_to_chapter(2)
	var raid_i := t._index_of(&"raid")
	while t.step < raid_i and t.step >= 0:
		t.advance()
	_ok(t.current().get("id") == &"raid", "at raid step")
	_ok(combat.raids.enabled, "raids on at the raid step")
	_ok(combat.raids.pending_size > 0 or t._flag, "a raid is announced (pending %d)" % combat.raids.pending_size)
	var saved := t.save_state()
	t.load_state({"step": 2})
	_ok(t.mode == Tutorial.QUICK, "old save loads as quick")
	t.load_state(saved)
	_ok(t.mode == Tutorial.ACADEMY and t.step == raid_i, "academy save round trip")
	SimStepper.run(tree, 120.0)
	print("TUT raid: flag %s, step %s" % [t._flag, t.current().get("id")])
	t.finish()
	await tree.process_frame
	_ok(t.step == Tutorial.OFF and combat.raids.enabled and combat.threats.arrivals, "quit restores raids and arrivals")
	await tree.create_timer(2.5).timeout
	_ok(not AudioDirector.in_tutorial() and not music.playing, "tutorial music fades out after quitting")
	tree.quit(0 if _fails.is_empty() else 1)

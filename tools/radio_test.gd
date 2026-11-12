extends Node
## Headless check of [RadioChatter]: a miner on a home mining contract and
## a mercenary, a forced raid, ~80 real s at 24x; collects every subtitle
## and whether its voice file played. Also checks every line in
## data/radio/radio_lines.json has both voice files. Prints "RADIO ..."
## lines; exit 1 on a failed check.
## Run: Godot --headless --path . res://tools/radio_test.tscn

var _fails: PackedStringArray = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.autosave_interval = 1e12
	Tutorial.write_settings = false
	_run.call_deferred()


func _ok(cond: bool, what: String) -> void:
	print("RADIO %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails.append(what)


func _place(mgr: BuildingManager, id: StringName, r0: float) -> Building:
	var def := mgr.def_by_id(id)
	for ring in range(1, 14):
		for k in 16:
			var off := Vector3(cos(TAU * k / 16.0), 0.0, sin(TAU * k / 16.0)) * (r0 + ring * 100.0)
			if mgr.plan_placement(def, off, false).is_valid():
				return mgr.spawn_finished(def, off)
	return null


func _run() -> void:
	var tree := get_tree()
	var dummy := Node.new()
	tree.root.add_child(dummy)
	tree.current_scene = dummy
	# Every line has both files.
	RadioChatter._load_table()
	var missing := 0
	var total := 0
	for p in RadioChatter.KEYS.size():
		var lines: Dictionary = RadioChatter._table["lines"][RadioChatter.KEYS[p]]
		for ev: String in lines:
			for n in (lines[ev] as Array).size():
				for slot in 2:
					total += 1
					if not ResourceLoader.exists(RadioChatter.line_path(p, slot, StringName(ev), n)):
						missing += 1
	_ok(missing == 0, "voice files: %d of %d present" % [total - missing, total])
	Sector.next_modifier = SectorModifier.STANDARD
	Corps.next_difficulty = CorpRegistry.Difficulty.OFF
	await SaveManager.new_game(false)
	for i in 3:
		await tree.process_frame
	var hud := Tutorial.of(tree).hud
	hud.tutorial.finish()
	Economy.add(20000, PackedInt32Array(), Ledger.OTHER, "Test credits")
	var mo := _place(hud.manager, &"mining_outpost", 260.0)
	var me := _place(hud.manager, &"mercenary_outpost", 300.0)
	var miner: Ship = mo.hire() if mo else null
	var merc: Ship = me.hire() if me else null
	_ok(miner != null and merc != null, "a miner and a mercenary")
	var best: AsteroidCluster = null
	for b in hud.solar_system.belts:
		if best == null or b.global_position.length() < best.global_position.length():
			best = b
	ContractBoard.post_mining(best, 120)
	var heard := {}
	var voiced := 0
	var last := ""
	var raided := false
	SimClock.set_speed(24.0)
	var end := Time.get_ticks_msec() + 80000
	while Time.get_ticks_msec() < end:
		await tree.process_frame
		if not raided and Time.get_ticks_msec() > end - 60000:
			raided = true
			var raids := CombatWorld.of(SystemWorld.home(tree)).raids
			var den := raids.pick_den()
			if den:
				raids.warn_raid(den, 2)
		var text := hud.radio._label.text if hud.radio.visible else ""
		if text != last and not text.is_empty():
			last = text
			heard[text] = true
			var p := hud.radio._player
			if p.playing and p.stream:
				voiced += 1
			print("RADIO heard: %s%s" % [text, "" if p.playing else "  (silent)"])
	SimClock.set_speed(1.0)
	_ok(heard.size() >= 3, "%d different lines heard" % heard.size())
	_ok(voiced >= 3, "%d of them voiced" % voiced)
	tree.quit(0 if _fails.is_empty() else 1)

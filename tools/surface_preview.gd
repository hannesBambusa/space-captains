extends Node
## Debug tool: a fully built planet outpost, shown in planet mode.
## Run: Godot --path . res://tools/surface_preview.tscn [-- --gas] [--type=rocky|ocean|desert|ice|lava]
##   [--zoom=520] [--yaw=0.6] [--shot=/abs/out.png]
## New game, an outpost founded on a home world (--gas: a gas giant
## platform), every building finished (Harvester Bay, Garrison, two Ground
## Turrets, Shield Dome), two harvesters and two soldiers hired, contracts
## on every deposit, then planet mode (SurfaceMode) on it. --type shows the
## same outpost on another kind of ground (the look only; its goods stay
## the real planet's). Stays open to
## look around (the game's own camera and HUD); --shot saves one frame and
## quits. Writes no saves and no settings.

var _gas := false
var _shot := ""
var _type := -1
var _zoom := -1.0
var _yaw := NAN


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.autosave_interval = 1e12
	Tutorial.write_settings = false
	for a in OS.get_cmdline_user_args():
		if a == "--gas":
			_gas = true
		elif a.begins_with("--shot="):
			_shot = a.trim_prefix("--shot=")
		elif a.begins_with("--type="):
			_type = ["rocky", "ocean", "desert", "ice", "lava"].find(a.trim_prefix("--type="))
		elif a.begins_with("--zoom="):
			_zoom = float(a.trim_prefix("--zoom="))
		elif a.begins_with("--yaw="):
			_yaw = float(a.trim_prefix("--yaw="))
	_run.call_deferred()


func _run() -> void:
	var tree := get_tree()
	var dummy := Node.new()
	tree.root.add_child(dummy)
	tree.current_scene = dummy
	await SaveManager.new_game(false)
	for i in 3:
		await tree.process_frame
	var tut := Tutorial.of(tree)
	if tut and tut.hud and tut.hud.tutorial:
		tut.hud.tutorial.finish()
	Research.done[OutpostState.TECH] = SimClock.time
	Economy.add(50000, Economy.cost(3000, 1000), Ledger.OTHER, "Preview money")
	var outs := Outposts.of(tree)
	var w := SystemWorld.home(tree)
	var best: PlanetBody = null
	for p in w.sys.planets:
		var bodies: Array = [p]
		for c in p.get_children():
			if c is PlanetBody:
				bodies.append(c)
		for b: PlanetBody in bodies:
			if (b.def.type == PlanetDef.Type.GAS_GIANT) == _gas and outs.found_problem(b).is_empty() and best == null:
				best = b
	if best == null:
		print("SURFACE PREVIEW: no world takes an outpost")
		tree.quit(1)
		return
	var o := outs.found(best)
	SimStepper.run(tree, OutpostState.FOUND_TIME + 10.0, 0.1, func() -> bool: return o.is_founded())
	print("SURFACE PREVIEW: outpost on %s, founded %s" % [o.planet, o.is_founded()])
	for spot: Array in [[OutpostState.BAY, 220.0, 0.0], [OutpostState.GARRISON, -220.0, 0.0], [OutpostState.TURRET, 0.0, 240.0],
			[OutpostState.TURRET, 160.0, -200.0], [OutpostState.DOME, -60.0, -230.0]]:
		if not outs.build(o, spot[0], spot[1], spot[2]):
			print("SURFACE PREVIEW: could not build %s (%s)" % [spot[0], outs.spot_problem(o, spot[0], spot[1], spot[2])])
	for b in o.buildings:
		b["built"] = 1.0
	for i in 2:
		outs.hire(o, OutpostState.HARVESTER)
		outs.hire(o, OutpostState.SOLDIER)
	for i in o.deposits.size():
		outs.set_contract(o, i, o.fair_pay())
	if _type >= 0 and not _gas:
		o.planet_type = _type
	var sm := SurfaceMode.enter(tree, o)
	if sm and _zoom > 0.0:
		sm._dist = _zoom
		sm._target_dist = _zoom
	if sm and not is_nan(_yaw):
		sm._yaw = _yaw
	print("SURFACE PREVIEW: planet mode %s, buildings %d, crew %d" % [sm != null, o.buildings.size(), o.crew.size()])
	if _shot.is_empty():
		return
	for i in 120:
		await tree.process_frame
	get_viewport().get_texture().get_image().save_png(_shot)
	print("SURFACE PREVIEW: shot ", _shot)
	tree.quit(0)

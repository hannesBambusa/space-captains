extends Node
## Headless check of [SectorModifier]: a new game under each modifier (and
## Random, and the tutorial), comparing start credits, a cluster's ore, the
## raid interval and wave, the threat clock and the Factory's price with
## Standard; then a save round trip. Prints "MOD ..." lines; exit 1 on a
## failed check. Never writes user settings (restores next_modifier).
## Run: Godot --headless --path . res://tools/sector_modifier_test.tscn

var _fails: PackedStringArray = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.autosave_interval = 1e12
	Tutorial.write_settings = false
	_run.call_deferred()


func _ok(cond: bool, what: String) -> void:
	print("MOD %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails.append(what)


## A new game under [param id]: {credits, reserve, interval, wave, price, threat_rate}.
func _sample(id: StringName, tutorial: bool = false) -> Dictionary:
	var tree := get_tree()
	Sector.next_modifier = id
	await SaveManager.new_game(tutorial)
	for i in 3:
		await tree.process_frame
	var home := SystemWorld.home(tree)
	var combat := CombatWorld.of(home)
	var raids := combat.raids
	var f := Factory.find(home)
	var probe := ClusterDef.new()
	probe.size = 2000.0 * ClusterDef.SPREAD
	probe.richness = 0.3
	probe.ore_type = AsteroidBelt.OreType.IRON
	var t0: float = combat.threats.threat_time
	var cr := Economy.credits
	SimStepper.run(tree, 30.0)
	return {"mod": Sector.modifier, "credits": cr, "reserve": probe.get_reserve(),
			"interval": raids.interval(), "price": f.market.willing_price(Economy.Ore.IRON) if f and f.market else 0.0,
			"threat": combat.threats.threat_time - t0}


func _run() -> void:
	var tree := get_tree()
	var dummy := Node.new()
	tree.root.add_child(dummy)
	tree.current_scene = dummy
	var keep := Sector.next_modifier
	var base := await _sample(SectorModifier.STANDARD)
	print("MOD standard: %s" % base)
	_ok(base["mod"] == SectorModifier.STANDARD, "standard game is standard")
	for m in SectorModifier.LIST:
		var id: StringName = m["id"]
		if id == SectorModifier.STANDARD:
			continue
		var r := await _sample(id)
		print("MOD %s: %s" % [id, r])
		_ok(r["mod"] == id, "%s chosen" % id)
		var want_cr := int(base["credits"]) + int(m.get("credits_add", 0.0))
		_ok(int(r["credits"]) == want_cr, "%s start credits %d (want %d)" % [id, r["credits"], want_cr])
		var k_res := float(m.get("reserve", 1.0))
		_ok(absf(float(r["reserve"]) - float(base["reserve"]) * k_res) <= 1.0, "%s reserve %d (x%.2f of %d)" % [id, r["reserve"], k_res, base["reserve"]])
		var k_int := float(m.get("raid_interval", 1.0))
		_ok(absf(float(r["interval"]) - float(base["interval"]) * k_int) < 1.0, "%s raid interval %.0f s" % [id, r["interval"]])
		var k_pr := float(m.get("ore_price", 1.0))
		_ok(absf(float(r["price"]) - float(base["price"]) * k_pr) < 0.05, "%s iron price %.2f" % [id, r["price"]])
		var k_th := float(m.get("threat", 1.0))
		_ok(absf(float(r["threat"]) - float(base["threat"]) * k_th) < 0.5, "%s threat clock %.1f in 30 s" % [id, r["threat"]])
	var rnd := await _sample(SectorModifier.RANDOM)
	_ok(rnd["mod"] != SectorModifier.STANDARD and rnd["mod"] != SectorModifier.RANDOM, "random rolled %s" % rnd["mod"])
	var tut := await _sample(&"pirate_haven", true)
	_ok(tut["mod"] == SectorModifier.STANDARD, "tutorial game is standard")
	await _sample(&"boom")
	var snap := Sector.save_state()
	_ok(String(snap.get("modifier", "")) == "boom", "saved under cluster.modifier")
	Sector.modifier = SectorModifier.STANDARD
	Sector.load_state(snap)
	_ok(Sector.modifier == &"boom", "loaded back")
	snap.erase("modifier")
	Sector.load_state(snap)
	_ok(Sector.modifier == SectorModifier.STANDARD, "a save without it loads as standard")
	Sector.next_modifier = keep
	tree.quit(0 if _fails.is_empty() else 1)

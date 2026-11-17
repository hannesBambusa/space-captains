extends Node
## Debug tool: traces cargo shuttle flights for a route plot.
## Run: Godot --headless --path . res://tools/shuttle_trace.tscn -- --out=/abs/trace.csv [--minutes=6]
## New game, mining outposts round the station (a mercenary outpost as an
## obstacle), their depots kept stocked. Every 0.2 sim s one CSV line per
## shuttle in the station's structures frame: t,name,phase,x,y,z,yaw,speed,bank.
## Lines starting with "#" give the layout: pads, keep-out circles, berths.
## Writes no saves.

const ANGLES: PackedFloat32Array = [10.0, 95.0, 170.0, 250.0, 320.0]

var _out := ""
var _minutes := 6.0
var _file: FileAccess
var _mgr: BuildingManager
var _next := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a.begins_with("--minutes="):
			_minutes = float(a.trim_prefix("--minutes="))
	SaveManager.autosave_interval = 1e12
	Corps.next_difficulty = CorpRegistry.Difficulty.OFF
	seed(12345)
	_run.call_deferred()


func _run() -> void:
	var tree := get_tree()
	var dummy := Node.new()
	tree.root.add_child(dummy)
	tree.current_scene = dummy
	await SaveManager.new_game()
	for i in 5:
		await tree.process_frame
	var w: Node = tree.get_first_node_in_group("system_world")
	_mgr = w.get("buildings")
	Economy.add(50000, PackedInt32Array(), Ledger.OTHER, "Trace credits")
	_file = FileAccess.open(_out, FileAccess.WRITE)
	var depots: Array[CargoDepot] = []
	var mine := _mgr.def_by_id(&"mining_outpost")
	for i in ANGLES.size():
		var b := _place(mine, deg_to_rad(ANGLES[i]))
		if b:
			depots.append(CargoDepot.of(b))
	_place(_mgr.def_by_id(&"mercenary_outpost"), deg_to_rad(50.0))
	for i in 5:
		await tree.process_frame
	var left := _minutes * 60.0
	var laid := false
	while left > 0.0:
		for d in depots:
			if d and d.waiting_total() < d.capacity():
				d.add_stock(Economy.Ore.IRON, d.capacity())
		left -= SimStepper.run(tree, minf(20.0, left), 0.1, _sample)
		if not laid:
			laid = _layout(depots)
		await tree.process_frame
	_file.close()
	print("TRACE done ", _out)
	tree.quit(0)


func _place(def: BuildingDef, ang: float) -> Building:
	for ring in 40:
		var r := 120.0 + ring * 20.0
		var off := Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		if _mgr.plan_placement(def, off, false).is_valid():
			print("TRACE placed %s at r %.0f, %.0f deg" % [def.id, r, rad_to_deg(ang)])
			return _mgr.spawn_finished(def, off)
	return null


func _layout(depots: Array[CargoDepot]) -> bool:
	var s: CargoShuttle = null
	for n in get_tree().get_nodes_in_group(Ship.GROUP):
		if n is CargoShuttle:
			s = n
			break
	if s == null:
		return false
	for i in s._pad_count():
		var p := s._pad_local(i)
		_file.store_line("#pad,%d,%.1f,%.1f,%.1f,%.1f" % [i, p.x, p.z, p.x, p.z])
	for c in s._keepouts():
		_file.store_line("#keepout,%.1f,%.1f,%.1f" % [c.x, c.y, c.z])
	for d in depots:
		var p := d.building.position
		_file.store_line("#outpost,%s,%.1f,%.1f" % [d.building.name, p.x, p.z])
	return true


func _sample() -> bool:
	if SimClock.time < _next:
		return false
	_next = SimClock.time + 0.2
	for n in get_tree().get_nodes_in_group(Ship.GROUP):
		var s := n as CargoShuttle
		if s == null or s.dead or s.phase == CargoShuttle.Phase.PARKED:
			continue
		var frame := s._frame()
		if frame == null:
			continue
		var p := frame.to_local(s.global_position)
		var fwd := frame.global_basis.inverse() * (s.global_basis * Vector3.FORWARD)
		_file.store_line("%.1f,%s,%d,%.2f,%.2f,%.2f,%.3f,%.2f,%.3f" % [SimClock.time, s.name, s.phase, p.x, p.y, p.z, atan2(fwd.x, -fwd.z), s.mover.velocity.length(), s.mover.bank])
	return false

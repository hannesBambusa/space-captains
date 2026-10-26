class_name ExploreContract
extends Contract
## Explore the system behind a jump gate (P3): one explorer from the
## Explorer Outpost flies there through the gates, surveys it ([Survey])
## and brings the charts home; [member reward] is paid once, on that return.
## Posting reserves the reward like a bounty ([member escrow], held by the
## ContractBoard). The gate is named, not linked: [member from_system] and
## [member gate_name] ([member target] is the live JumpGate while its system
## is live, for markers and the camera), so the contract outlives its
## system going to data and back, and saves.
##
## One explorer at a time ([member explorer_id], the captain's save id: the
## ship itself may be data far away). Cancel: all of it back while nobody
## has taken it; once taken, half comes back now and the explorer is still
## paid the other half on the way home (the contract leaves the board but
## the board holds it until then, ContractBoard.held). The explorer lost:
## the contract is open again.
##
## Fair pay: [method fair_for] by jumps and danger (the danger guessed from
## the depth while the system is unknown). It earns nothing by itself: the
## charts open the system for later (discovery bounties, derelicts, P4).

## The system the gate is in, the gate, and the system behind it.
var from_system: StringName = ClusterNetwork.HOME_ID
var gate_name: String = ""
var target_system: StringName = &""
## The target's gate to leave by ("" = back the way it came in).
var exit_gate: String = ""
## Credits reserved for it and not paid out yet.
var escrow: int = 0
## Save id of the explorer's captain on it (0 = nobody).
var explorer_id: int = 0
var explorer_name: String = ""
## Survey progress for the lists: phase ("out", "survey", "back"), waypoints.
var phase: String = ""
var waypoint: int = 0
var waypoints: int = 0


func _init(from: StringName = ClusterNetwork.HOME_ID, gate: String = "", credits: int = 0, exit: String = "") -> void:
	type = Type.EXPLORE
	from_system = from
	gate_name = gate
	reward = credits
	exit_gate = exit
	max_takers = 1
	var t := Sector.network.gate_target(from, gate) if Sector.network else {}
	target_system = t.get("system", &"")


## Fair pay for a survey [param jumps] out of a system of danger
## [param danger] (known, or guessed).
static func fair_for(jumps: int, danger: int) -> int:
	return 250 + 200 * maxi(jumps - 1, 0) + 50 * maxi(danger - 1, 0)


## Danger the captains go by: the system's when known, else a guess from
## the depth (the unknown is feared: depth + 1).
static func danger_guess(id: StringName) -> int:
	var e := Sector.network.entry(id) if Sector.network else null
	var st := Sector.state(id)
	if e == null:
		return 1
	if st and st.known:
		return e.danger
	return clampi(e.depth + 1, 1, 5)


func jumps() -> int:
	return Sector.network.depth(target_system) if Sector.network else 1


func is_known() -> bool:
	var st := Sector.state(target_system)
	return st != null and st.known


func get_danger() -> int:
	return danger_guess(target_system)


func fair_reward() -> int:
	return fair_for(jumps(), get_danger())


func target_name() -> String:
	var def := Sector.system_def(target_system)
	return def.system_name if def else String(target_system)


## The gate node while its system is live, else null.
func gate() -> JumpGate:
	var tree := Engine.get_main_loop() as SceneTree
	var vm := ViewManager.of(tree) if tree else null
	var w := vm.world(from_system) if vm else null
	if w == null and tree and from_system == ClusterNetwork.HOME_ID:
		w = SystemWorld.home(tree)
	if w == null or w.sys == null:
		return null
	for g in w.sys.gates:
		if is_instance_valid(g) and g.def and g.def.name == gate_name:
			return g
	return null


## Keeps [member target] on the live gate (or null while it is data).
func refresh_target() -> void:
	var g := gate()
	target = g


func taken() -> bool:
	return explorer_id != 0


func is_available() -> bool:
	return not is_finished() and not taken() and Sector.network != null and not target_system.is_empty()


## Escrowed: never paused.
func pays_per_delivery() -> bool:
	return false


func add_taker(ship: Node) -> bool:
	var s := ship as Ship
	if not is_available() or s == null or s.captain == null:
		return false
	takers.clear()
	takers.append(ship)
	times_taken += 1
	explorer_id = SaveIds.of(s.captain)
	explorer_name = s.captain.captain_name
	phase = Survey.PHASE_OUT
	waypoint = 0
	waypoints = 0
	_update_status()
	return true


func remove_taker(ship: Node) -> void:
	var s := ship as Ship if is_instance_valid(ship) else null
	release_explorer(s.captain if s else null)


## The explorer of [param cap] is off it (lost, gave up): open again.
## Null: whoever is on it.
func release_explorer(cap: Captain) -> void:
	if cap and explorer_id != 0 and SaveIds.of(cap) != explorer_id:
		return
	explorer_id = 0
	explorer_name = ""
	phase = ""
	waypoint = 0
	waypoints = 0
	takers.clear()
	if is_finished():
		# Cancelled while it was out: nobody comes back for the rest.
		ContractBoard.drop_held(self)
	_update_status()


## A (re-)created ship of the explorer on it: the takers list points at it.
func attach_ship(ship: Ship) -> void:
	if ship and ship.captain and SaveIds.of(ship.captain) == explorer_id:
		takers.clear()
		takers.append(ship)


## Survey data [param s] (Survey) moved on.
func note_progress(s: Dictionary) -> void:
	phase = String(s.get("phase", ""))
	waypoints = (s.get("points", PackedVector3Array()) as PackedVector3Array).size()
	waypoint = mini(int(s.get("i", 0)), waypoints)
	changed.emit(self)


func get_type_name() -> String:
	return "Explore"


func get_target_name() -> String:
	return gate_name


func get_title() -> String:
	return "Explore: %s (behind %s)" % [target_name(), gate_name]


func get_reward_text() -> String:
	return "%s cr" % Fmt.amount(reward)


func get_status_name() -> String:
	if status == Status.CANCELLED and taken():
		return "Cancelled, explorer still out"
	return super.get_status_name()


## "Exploring Ostra (2/5 waypoints)", "Flying to Ostra", "Bringing the
## charts of Ostra home"; "" while open.
func get_activity_text() -> String:
	if not taken():
		return ""
	var who := explorer_name.get_slice(" ", 0)
	match phase:
		Survey.PHASE_SURVEY:
			return "%s exploring %s (%d/%d waypoints)" % [who, target_name(), waypoint, waypoints]
		Survey.PHASE_BACK:
			return "%s bringing the %s charts home" % [who, target_name()]
	return "%s flying to %s" % [who, target_name()]


func get_site_position(_from: Vector3 = Vector3.ZERO) -> Vector3:
	var g := gate()
	return g.global_position if g else Vector3.ZERO


## Paid and done.
func mark_completed() -> void:
	if not is_finished():
		takers.clear()
		_set_status(Status.COMPLETED)

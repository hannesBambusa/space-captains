extends Node
## Autoload "Sector". Owns the game's gate network ([ClusterNetwork]) and
## the state of every generated system ([RemoteSystemState]). Global like
## the other autoloads: the network outlives the game scene, is ready
## before the home system builds (home's gate targets come from it) and is
## saved with the globals (GameSnapshot.capture_globals).
##
## A new game gets a new random seed ([method reset], from
## SaveManager._reset_globals); a load takes the saved seed and rebuilds the
## same network ([method load_state]). Saved under "cluster":
## {seed, generator_version, systems: {id: RemoteSystemState dict}}; the
## SystemDefs are regenerated, never stored. A save without the key (older
## games) keeps the fresh seed of the reset before it.
##
## Ships between gates (GateTransit, stepped by RemoteSim) are data here too:
## [member transits], saved under "cluster"."transits".
##
## Exploration (P3, [Survey]): what explorers revealed goes into each
## state's revealed list ([method reveal], [signal revealed] for the fog of
## war); new clusters, bases, derelicts and gates are also recorded in
## [member discoveries] with the finder and the time, marked delivered when
## the survey reaches home (P4 pays them out). Saved under
## "cluster"."discoveries".

## Names newly revealed in system [param id] (planets with their moons,
## clusters, bases, derelicts, gates).
signal revealed(id: StringName, names: PackedStringArray)
## A survey reached home: [param id] is known now.
signal surveyed(id: StringName)
## An explorer stripped derelict [param item] in system [param id] (DerelictLoot).
signal derelict_looted(id: StringName, item: String)

## A survey older than this is stale: a new explore contract may go there,
## sim seconds.
const STALE_TIME := 600.0

var network: ClusterNetwork
## RemoteSystemState per remote system id.
var states: Dictionary = {}
## Ships in the jump between two gates: {"ship": ShipCodec dict (with its
## "transit"), "to": system id, "gate": exit gate name, "at": SimClock
## time it comes out}.
var transits: Array = []
## Things explorers found, oldest first: {system: id, kind: "cluster" /
## "den" / "derelict" / "gate", name, detail (the ore, the faction, the
## derelict kind, where the gate leads), time, finder (captain name),
## captain (save id), delivered: bool (the survey reached home), paid: bool
## (P4 bounty paid)}.
var discoveries: Array[Dictionary] = []

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	# scenes/game.tscn started on its own (editor) still has a network.
	reset()


## A new network with a new random seed, every system unknown.
func reset() -> void:
	start(_rng.randi())


## Builds the network of [param net_seed] with fresh (empty) states.
func start(net_seed: int) -> void:
	network = ClusterNetwork.generate(net_seed)
	states.clear()
	transits.clear()
	discoveries.clear()
	for id in network.remote_ids():
		states[id] = RemoteSystemState.new()


func get_seed() -> int:
	return network.seed if network else 0


func state(id: StringName) -> RemoteSystemState:
	return states.get(id) as RemoteSystemState


func system_def(id: StringName) -> SystemDef:
	return network.system_def(id) if network else null


func save_state() -> Dictionary:
	var sys := {}
	for id: StringName in states:
		sys[String(id)] = (states[id] as RemoteSystemState).to_dict()
	var tr := []
	for t: Dictionary in transits:
		var c := t.duplicate(true)
		c["to"] = String(c["to"])
		tr.append(c)
	var disc := []
	for x in discoveries:
		var c := x.duplicate()
		c["system"] = String(c["system"])
		disc.append(c)
	return {"seed": get_seed(), "generator_version": SystemGenerator.VERSION, "systems": sys, "transits": tr, "discoveries": disc}


## [param d]: the "cluster" key of a save. Empty (an older save): keeps the
## network the reset made, so the game gets a seed now and saves it.
func load_state(d: Dictionary) -> void:
	if d.is_empty() or not d.has("seed"):
		return
	start(int(d["seed"]))
	var version := int(d.get("generator_version", SystemGenerator.VERSION))
	if version != SystemGenerator.VERSION:
		push_warning("Sector: save made with generator v%d, regenerated with v%d (same seed, systems may differ)" % [version, SystemGenerator.VERSION])
	var sys: Dictionary = d.get("systems", {})
	for key: String in sys:
		var id := StringName(key)
		if states.has(id):
			states[id] = RemoteSystemState.from_dict(sys[key])
	for t: Dictionary in d.get("transits", []):
		var c := t.duplicate(true)
		c["to"] = StringName(c.get("to", ""))
		transits.append(c)
	for x: Dictionary in d.get("discoveries", []):
		var c := x.duplicate()
		c["system"] = StringName(c.get("system", ""))
		discoveries.append(c)


# --- Exploration ------------------------------------------------------------------

## Adds [param names] to system [param id]'s revealed list. Returns the
## ones that were new (and tells the fog of war).
func reveal(id: StringName, names: PackedStringArray) -> PackedStringArray:
	var st := state(id)
	var fresh := PackedStringArray()
	if st == null:
		return fresh
	for n in names:
		if not st.revealed.has(n) and not fresh.has(n):
			fresh.append(n)
	if fresh.is_empty():
		return fresh
	st.revealed.append_array(fresh)
	revealed.emit(id, fresh)
	return fresh


## True when [param name] is revealed in system [param id] (home: always).
func is_revealed(id: StringName, item: String) -> bool:
	if id == ClusterNetwork.HOME_ID:
		return true
	var st := state(id)
	return st != null and st.revealed.has(item)


## Records a find (see [member discoveries]).
func add_discovery(id: StringName, kind: String, item: String, detail: String, finder: String, captain_id: int) -> Dictionary:
	var x := {"system": id, "kind": kind, "name": item, "detail": detail, "time": SimClock.time, "finder": finder,
			"captain": captain_id, "delivered": false, "paid": false}
	discoveries.append(x)
	return x


## Marks the finds of captain [param captain_id] in [param id] delivered.
## Returns how many.
func deliver_discoveries(id: StringName, captain_id: int) -> int:
	var n := 0
	for x in discoveries:
		if x["system"] == id and int(x.get("captain", 0)) == captain_id and not bool(x.get("delivered", false)):
			x["delivered"] = true
			n += 1
	return n


## Derelict [param item] of [param id] has been stripped (saved in the
## state's looted list).
func mark_looted(id: StringName, item: String) -> void:
	var st := state(id)
	if st == null or st.looted.has(item):
		return
	st.looted.append(item)
	derelict_looted.emit(id, item)


## Unlooted derelicts of [param id] the player knows of (revealed).
func derelicts_left(id: StringName) -> int:
	var def := system_def(id)
	var st := state(id)
	if def == null or st == null:
		return 0
	var n := 0
	for x in def.derelicts:
		if st.revealed.has(x.name) and not st.looted.has(x.name):
			n += 1
	return n


## A survey of [param id] reached home at [param seen] (when it was made).
func mark_surveyed(id: StringName, seen: float) -> void:
	var st := state(id)
	if st == null:
		return
	st.known = true
	st.last_seen = maxf(st.last_seen, seen)
	surveyed.emit(id)


## Never surveyed, or the last survey is older than [constant STALE_TIME].
func is_stale(id: StringName) -> bool:
	var st := state(id)
	if st == null:
		return false
	return not st.known or SimClock.time - st.last_seen >= STALE_TIME


## "danger ? (2 jumps)" or "danger 3 · seen 12 min ago" for menus and panels.
func danger_text(id: StringName) -> String:
	var e := network.entry(id) if network else null
	var st := state(id)
	if e == null or st == null:
		return ""
	if not st.known:
		return "danger ? (%d jump%s out)" % [e.depth, "" if e.depth == 1 else "s"]
	return "danger %d · %s" % [e.danger, seen_text(id)]


## "seen 12 min ago", "seen just now", "never seen".
func seen_text(id: StringName) -> String:
	var st := state(id)
	if st == null or st.last_seen < 0.0:
		return "never seen"
	var mins := floori((SimClock.time - st.last_seen) / 60.0)
	return "seen just now" if mins < 1 else "seen %d min ago" % mins


## The gate in system [param a] that leads to [param b], "" when none.
func gate_between(a: StringName, b: StringName) -> String:
	var l := network.link_between(a, b) if network else null
	if l == null:
		return ""
	return l.gate_a if l.a == a else l.gate_b


## Gates to take from [param from] to [param to] along the shortest path.
func hops_between(from: StringName, to: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	if network == null:
		return out
	var p := network.path(from, to)
	for i in range(p.size() - 1):
		out.append(gate_between(p[i], p[i + 1]))
	return out

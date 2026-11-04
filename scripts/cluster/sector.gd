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
## Planet outposts by "system|planet" (OutpostState), saved under "cluster"."outposts".
var outposts: Dictionary = {}
## The Outposts node's RNG state from the last load ({} = seed it fresh).
var outposts_rng: Dictionary = {}

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	# scenes/game.tscn started on its own (editor) still has a network.
	reset()


## A new network with a new random seed, every system unknown, with a
## rival region per rival of the next new game (Corps.next_rival_count).
func reset() -> void:
	start(_rng.randi(), Corps.regions_for_new_game() if is_inside_tree() and get_node_or_null(^"/root/Corps") else 1)


## Builds the network of [param net_seed] with fresh (empty) states and
## [param regions] rival regions (1 to 3).
func start(net_seed: int, regions: int = -1) -> void:
	if regions < 1:
		regions = network.rival_ids.size() if network and not network.rival_ids.is_empty() else 1
	network = ClusterNetwork.generate(net_seed, regions)
	states.clear()
	transits.clear()
	discoveries.clear()
	outposts.clear()
	outposts_rng = {}
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
	return {"seed": get_seed(), "generator_version": SystemGenerator.VERSION, "regions": network.rival_ids.size() if network else 1,
			"systems": sys, "transits": tr, "discoveries": disc, "outposts": _outposts_out(), "outposts_rng": _outposts_rng_out()}


## [param d]: the "cluster" key of a save. Empty (an older save): keeps the
## network the reset made, so the game gets a seed now and saves it.
func load_state(d: Dictionary) -> void:
	if d.is_empty() or not d.has("seed"):
		return
	start(int(d["seed"]), int(d.get("regions", 1)))
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
	outposts_rng = (d.get("outposts_rng", {}) as Dictionary).duplicate()
	var outs := Outposts.of(get_tree())
	if outs and not outposts_rng.is_empty():
		SaveUtil.set_rng(outs._rng, outposts_rng)
	for od: Dictionary in d.get("outposts", []):
		var o := OutpostState.from_dict(od)
		outposts[o.key()] = o
	for x: Dictionary in d.get("discoveries", []):
		var c := x.duplicate()
		c["system"] = StringName(c.get("system", ""))
		discoveries.append(c)


## Every outpost's dict; the one on screen also carries the hostiles on its
## ground ("ground"), so a save cannot erase a raid in progress.
func _outposts_out() -> Array:
	var out := []
	var outs := Outposts.of(get_tree())
	var sw := SurfaceWorld.current(get_tree())
	for k: String in outposts:
		var o := outposts[k] as OutpostState
		var d := o.to_dict()
		if outs and o == outs.live and sw and not sw.is_queued_for_deletion():
			var left := sw.hostiles_left()
			var ground: Dictionary = (d.get("ground", {}) as Dictionary).duplicate()
			for kind: String in left:
				ground[kind] = float(ground.get(kind, 0.0)) + float(left[kind])
			if not ground.is_empty():
				d["ground"] = ground
		out.append(d)
	return out


func _outposts_rng_out() -> Dictionary:
	var outs := Outposts.of(get_tree())
	return outs.rng_state() if outs else outposts_rng


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

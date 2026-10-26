class_name ClusterNetwork
extends RefCounted
## The gate network of one game, built from a seed ([method generate]):
## home (fixed, data/systems/home_system.tres) plus 6 to 9 generated
## systems 1 to 3 jumps out. Each home gate (Ostra Gate, Kharon Gate) opens
## its own branch, a tree of systems; exactly one cross-link joins the two
## branches at depth 2 to 3. A link is a pair of gates, one in each system,
## named after the system it leads to ("Ostra Gate"; the way back to home
## is "Solace Gate"); each GateDef names its target system and the gate a
## ship comes out of there.
##
## Danger 1..5 per system: depth + rand(-1..1), plus 1 for a third of the
## depth-3 systems, clamped. The SystemDefs are generated with the network
## (SystemGenerator; names unique across the network) and never saved: the
## same seed makes the same network and the same defs.

const HOME_ID := &"home"
const HOME_DEF_PATH := "res://data/systems/home_system.tres"
## The two home gates and the system each opens (the depth-1 systems take
## the names the home gates already show).
const HOME_GATES := ["Ostra Gate", "Kharon Gate"]
const MIN_REMOTE := 6
const MAX_REMOTE := 9
const MAX_DEPTH := 3
## Gates per remote system at most (links to the parent, children, cross-link).
const MAX_LINKS := 4


## One system of the network.
class Entry extends RefCounted:
	var id: StringName
	var name: String
	var depth: int
	var danger: int = 1
	## 0 = behind Ostra Gate, 1 = behind Kharon Gate, -1 = home.
	var branch: int = -1
	var parent: StringName = &""


## One jump lane: gate [member gate_a] in [member a] leads to gate
## [member gate_b] in [member b].
class Link extends RefCounted:
	var a: StringName
	var b: StringName
	var gate_a: String
	var gate_b: String
	## The one link between the two branches.
	var cross := false


var seed: int = 0
## Entry per id, home first, then "s1".. in creation order.
var ids: Array[StringName] = []
var systems: Dictionary = {}
var links: Array[Link] = []
## SystemDef per id (home's is the loaded home_system.tres).
var defs: Dictionary = {}

var _rng := RandomNumberGenerator.new()


## The network of [param net_seed] with every system's def.
static func generate(net_seed: int) -> ClusterNetwork:
	var n := ClusterNetwork.new()
	n._build(net_seed)
	return n


# --- Queries ------------------------------------------------------------------

func entry(id: StringName) -> Entry:
	return systems.get(id) as Entry


func system_def(id: StringName) -> SystemDef:
	return defs.get(id) as SystemDef


## Id of the system called [param system_name], &"" when none.
func id_of(system_name: String) -> StringName:
	for id in ids:
		if (systems[id] as Entry).name == system_name:
			return id
	return &""


## Ids of the systems one jump from [param id], in link order.
func neighbours(id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for l in links:
		if l.a == id:
			out.append(l.b)
		elif l.b == id:
			out.append(l.a)
	return out


## Jumps from home to [param id] (shortest path), -1 when unknown.
func depth(id: StringName) -> int:
	var p := path(HOME_ID, id)
	return p.size() - 1 if not p.is_empty() else -1


## Shortest gate path from [param from] to [param to], both ends included
## ([] when not connected). BFS in link order, so ties pick the same path.
func path(from: StringName, to: StringName) -> Array[StringName]:
	var none: Array[StringName] = []
	if not systems.has(from) or not systems.has(to):
		return none
	var prev := {from: &""}
	var queue: Array[StringName] = [from]
	while not queue.is_empty():
		var cur: StringName = queue.pop_front()
		if cur == to:
			break
		for nb in neighbours(cur):
			if not prev.has(nb):
				prev[nb] = cur
				queue.append(nb)
	if not prev.has(to):
		return none
	var out: Array[StringName] = []
	var at := to
	while at != &"":
		out.push_front(at)
		at = prev[at]
	return out


## The link between [param a] and [param b], null when none.
func link_between(a: StringName, b: StringName) -> Link:
	for l in links:
		if (l.a == a and l.b == b) or (l.a == b and l.b == a):
			return l
	return null


## Where gate [param gate_name] of system [param id] leads:
## {system: id, gate: gate name}, {} when it is no link's gate.
func gate_target(id: StringName, gate_name: String) -> Dictionary:
	for l in links:
		if l.a == id and l.gate_a == gate_name:
			return {"system": l.b, "gate": l.gate_b}
		if l.b == id and l.gate_b == gate_name:
			return {"system": l.a, "gate": l.gate_a}
	return {}


## Remote system ids (everything but home).
func remote_ids() -> Array[StringName]:
	var out := ids.duplicate()
	out.erase(HOME_ID)
	return out


## Writes every home link's target into home's GateDefs (target system
## name and the gate on the far side).
func apply_home_gates() -> void:
	var home := system_def(HOME_ID)
	if home == null:
		return
	for g in home.gates:
		var t := gate_target(HOME_ID, g.name)
		if t.is_empty():
			continue
		g.target_system = entry(t["system"]).name
		g.target_gate = String(t["gate"])


## Stable text of the whole network and every generated def (for
## comparing two builds: same seed, same text).
func dump() -> String:
	var lines: PackedStringArray = ["seed %d" % seed]
	for id in ids:
		var e := entry(id)
		lines.append("sys %s %s depth %d danger %d branch %d parent %s" % [id, e.name, e.depth, e.danger, e.branch, e.parent])
	for l in links:
		lines.append("link %s:%s <-> %s:%s%s" % [l.a, l.gate_a, l.b, l.gate_b, " cross" if l.cross else ""])
	for id in remote_ids():
		lines.append("def %s %s" % [id, _dump_value(system_def(id))])
	return "\n".join(lines)


static func _dump_value(v: Variant) -> String:
	if v is Resource:
		var r := v as Resource
		var parts: PackedStringArray = []
		for p in r.get_property_list():
			if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
				continue
			if int(p["usage"]) & PROPERTY_USAGE_STORAGE == 0:
				continue
			parts.append("%s=%s" % [p["name"], _dump_value(r.get(p["name"]))])
		return "{%s}" % ", ".join(parts)
	if v is Array:
		var parts: PackedStringArray = []
		for x: Variant in v:
			parts.append(_dump_value(x))
		return "[%s]" % ", ".join(parts)
	return var_to_str(v)


# --- Build --------------------------------------------------------------------

func _build(net_seed: int) -> void:
	seed = net_seed
	_rng.seed = hash("net:%d" % net_seed)
	var home_def := load(HOME_DEF_PATH) as SystemDef
	var names := NamePool.Allocator.new(NamePool.load_default(), _rng)
	_reserve_home(names, home_def)

	var home := _add(HOME_ID, home_def.system_name, 0, -1, &"")
	home.danger = 1
	defs[HOME_ID] = home_def
	var remote := _rng.randi_range(MIN_REMOTE, MAX_REMOTE)
	# Depth 1: the systems behind the two home gates, named like the gates.
	for b in HOME_GATES.size():
		var gname := String(HOME_GATES[b])
		var e := _add(_next_id(), gname.trim_suffix(" Gate"), 1, b, HOME_ID)
		names.reserve(e.name)
		_link(HOME_ID, e.id, gname)
	# The rest: one depth-2 system in each branch first, then a third one at
	# depth 3 (so the network always reaches 3 jumps), then anywhere.
	var placed := [0, 0]
	for i in remote - HOME_GATES.size():
		var branch: int
		var want_depth := 0
		if i < 2:
			branch = i
			want_depth = 2
		else:
			if absi(placed[0] - placed[1]) >= 2:
				branch = 0 if placed[0] < placed[1] else 1
			else:
				branch = _rng.randi_range(0, 1)
			if i == 2:
				want_depth = 3
		var parent := _pick_parent(branch, want_depth)
		if parent == &"":
			branch = 1 - branch
			parent = _pick_parent(branch, want_depth)
		var e := _add(_next_id(), names.take(&"system"), entry(parent).depth + 1, branch, parent)
		_link(parent, e.id)
		placed[branch] += 1
	_cross_link()
	for id in ids:
		if id == HOME_ID:
			continue
		var e := entry(id)
		var bonus := 1 if e.depth >= MAX_DEPTH and _rng.randf() < 0.35 else 0
		e.danger = clampi(e.depth + _rng.randi_range(-1, 1) + bonus, 1, 5)
	# Defs in id order (the name allocator hands names out in that order).
	for id in remote_ids():
		var e := entry(id)
		defs[id] = SystemGenerator.generate(seed, id, e.name, e.depth, e.danger, _gate_specs(id), names)
	apply_home_gates()


func _add(id: StringName, system_name: String, d: int, branch: int, parent: StringName) -> Entry:
	var e := Entry.new()
	e.id = id
	e.name = system_name
	e.depth = d
	e.branch = branch
	e.parent = parent
	ids.append(id)
	systems[id] = e
	return e


func _next_id() -> StringName:
	return StringName("s%d" % ids.size())


## A parent in [param branch] with a free gate whose child stays within
## MAX_DEPTH; [param want_depth] > 0 asks for that child depth.
func _pick_parent(branch: int, want_depth: int) -> StringName:
	var cands: Array[StringName] = []
	var weights := PackedFloat32Array()
	for id in ids:
		var e := entry(id)
		if e.branch != branch or e.depth >= MAX_DEPTH or neighbours(id).size() >= MAX_LINKS - 1:
			continue
		if want_depth > 0 and e.depth + 1 != want_depth:
			continue
		cands.append(id)
		weights.append(1.0 if e.depth == 1 else 1.2)
	if cands.is_empty():
		return &""
	return cands[_rng.rand_weighted(weights)]


## Gate pair between [param a] and [param b]; [param gate_a] overrides the
## name of a's gate (home's fixed gates).
func _link(a: StringName, b: StringName, gate_a: String = "", cross: bool = false) -> Link:
	var l := Link.new()
	l.a = a
	l.b = b
	l.gate_a = gate_a if not gate_a.is_empty() else "%s Gate" % entry(b).name
	l.gate_b = "%s Gate" % entry(a).name
	l.cross = cross
	links.append(l)
	return l


## The one link between the branches, both ends at depth 2 or 3.
func _cross_link() -> void:
	var pairs: Array = []
	for a in ids:
		var ea := entry(a)
		if ea.branch != 0 or ea.depth < 2:
			continue
		for b in ids:
			var eb := entry(b)
			if eb.branch != 1 or eb.depth < 2:
				continue
			if neighbours(a).size() >= MAX_LINKS or neighbours(b).size() >= MAX_LINKS:
				continue
			pairs.append([a, b])
	if pairs.is_empty():
		push_error("ClusterNetwork: no cross-link possible (seed %d)" % seed)
		return
	var p: Array = pairs[_rng.randi_range(0, pairs.size() - 1)]
	_link(p[0], p[1], "", true)


## Gate specs of [param id] for the generator, one per link, in link order.
func _gate_specs(id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l in links:
		var mine := ""
		var other := &""
		var theirs := ""
		if l.a == id:
			mine = l.gate_a
			other = l.b
			theirs = l.gate_b
		elif l.b == id:
			mine = l.gate_b
			other = l.a
			theirs = l.gate_a
		else:
			continue
		out.append({"name": mine, "target_system": entry(other).name, "target_gate": theirs,
				"target_danger": entry(other).danger})
	return out


## Home's names are taken: its system, planets, moons, clusters, bases.
func _reserve_home(names: NamePool.Allocator, home_def: SystemDef) -> void:
	names.reserve(home_def.system_name)
	for p in home_def.planets:
		names.reserve(p.name)
		for m: PlanetDef in p.moons:
			names.reserve(m.name)
	for b in home_def.belts:
		names.reserve(b.name)
	for n in home_def.cluster_names:
		names.reserve(n)
	for d in home_def.dens:
		names.reserve(d.gang)

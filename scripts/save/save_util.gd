class_name SaveUtil
extends RefCounted
## Small helpers shared by the save code: plain property lists, random
## number generator states, [Durability] (with its damage tally), and the
## WeakRef stand-in for links to objects that are gone.


## {name: value} for [param names] on [param o].
static func props(o: Object, names: PackedStringArray) -> Dictionary:
	var out := {}
	for n in names:
		out[n] = o.get(n)
	return out


## Sets every saved property of [param d] on [param o]. Typed arrays are
## filled in place (a plain Array cannot be set onto them); missing keys
## keep their current value, so older saves still load.
static func apply_props(o: Object, d: Dictionary) -> void:
	for n: String in d:
		var cur: Variant = o.get(n)
		var v: Variant = d[n]
		if cur is Array and (cur as Array).is_typed() and v is Array:
			(cur as Array).assign(v)
		else:
			o.set(n, v)


static func rng_state(rng: RandomNumberGenerator) -> Dictionary:
	return {"seed": rng.seed, "state": rng.state} if rng else {}


static func set_rng(rng: RandomNumberGenerator, d: Dictionary) -> void:
	if rng == null or d.is_empty():
		return
	rng.seed = int(d["seed"])
	rng.state = int(d["state"])


## Hull, shields, last hit and the per-attacker tally (attackers by save id).
static func durability(d: Durability) -> Dictionary:
	if d == null:
		return {}
	var tally := []
	for key in d.tally:
		var e: Dictionary = d.tally[key]
		var o: Object = (e["ref"] as WeakRef).get_ref()
		if o == null:
			continue
		tally.append({"id": SaveIds.of(o), "damage": float(e["damage"]), "time": float(e["time"])})
	var last := d.get_last_attacker()
	return {"hull": d.hull, "shields": d.shields, "max_hull": d.max_hull, "max_shields": d.max_shields,
			"last_hit_time": d.last_hit_time, "last_attacker": SaveIds.of(last) if last else 0, "tally": tally}


## Applies [method durability] data. Tally entries for attackers that were
## not restored are dropped.
static func set_durability(d: Durability, s: Dictionary, refs: SaveRefs) -> void:
	if d == null or s.is_empty():
		return
	d.hull = clampf(float(s["hull"]), 0.0, d.max_hull) if d.hull > 0.0 else 0.0
	d.shields = clampf(float(s["shields"]), 0.0, d.max_shields)
	d.last_hit_time = float(s.get("last_hit_time", -INF))
	var last := refs.find(int(s.get("last_attacker", 0)))
	d.last_attacker = weakref(last) if last else null
	d.tally.clear()
	for e: Dictionary in s.get("tally", []):
		var o := refs.find(int(e["id"]))
		if o:
			d.tally[o.get_instance_id()] = {"ref": weakref(o), "damage": float(e["damage"]), "time": float(e["time"])}


## [method props] of [param names] on [param o], plus [param d] under
## "durability" ([method durability]).
static func props_and_durability(o: Object, names: PackedStringArray, d: Durability) -> Dictionary:
	var out := props(o, names)
	out["durability"] = durability(d)
	return out


## Applies [method props_and_durability] data: every key but "durability"
## and [param skip] onto [param o], then the durability ([method set_durability]).
static func apply_props_and_durability(o: Object, data: Dictionary, d: Durability, refs: SaveRefs, skip: PackedStringArray = []) -> void:
	var fields := data.duplicate()
	fields.erase("durability")
	for k in skip:
		fields.erase(k)
	apply_props(o, fields)
	set_durability(d, data.get("durability", {}), refs)


## Save ids of the objects in [param list] that still exist; with
## [param skip_dead], also without the ones flagged dead (ships).
static func ids(list: Array, skip_dead: bool = false) -> Array:
	var out := []
	for o in list:
		if is_instance_valid(o) and not (skip_dead and bool((o as Object).get(&"dead"))):
			out.append(SaveIds.of(o))
	return out


## A WeakRef that resolves to nothing (for links to objects that are gone).
static func dead_ref() -> WeakRef:
	var o := Object.new()
	var w: WeakRef = weakref(o)
	o.free()
	return w

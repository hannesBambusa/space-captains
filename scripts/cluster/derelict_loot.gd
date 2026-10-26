class_name DerelictLoot
extends RefCounted
## Salvage from derelict hulks (P4). An explorer that sweeps a derelict
## nobody has stripped yet queues it ([method queue_near], after every
## reveal sweep), flies to it during the survey, hovers there
## [constant HOVER] sim seconds and takes what its loot table gives
## ([method salvage]): credits (data cores, sold), ore and planet goods
## into the explorer's hold (at most [constant HOLD] units, the rest stays
## behind), and now and then a rare module part. The hulk is marked looted
## at once (RemoteSystemState.looted, Sector.derelict_looted); the loot
## rides home in the survey data and is delivered with it at the Explorer
## Outpost ([method deliver]): ore and goods into the station's stock,
## credits as income, a part into the Factory warehouse (it lets the
## Factory make it early, or discounts the next one), sold for half its
## price without a Factory.
##
## The roll is seeded by the network seed, the system and the hulk's name
## ([method roll]), so the live explorer and the abstract one (Survey.step_data)
## get the same loot from the same hulk.
##
## Survey data keys: "salvage" (queued hulk names), "salvaged" (done),
## "visit" (the hulk it is flying to or hovering at), "visit_t" (seconds
## hovered), "hold" (ore per Economy.Ore), "loot_cr", "parts" (module ids),
## "loot_lines" (what each hulk gave, for the delivery line).

## Sim seconds hovering at a hulk.
const HOVER := 10.0
## Explorer hold for ore and goods, units.
const HOLD := 60
## The hover point above the hulk, metres.
const HOVER_HEIGHT := 60.0
## Live: close enough to start hovering, metres.
const REACH := 160.0
## Share of a part's price paid when there is no Factory to take it.
const PART_SALE := 0.5
const INCOME_SOURCE := "Salvage"
## Fill order when the hold runs short: most valuable first.
const VALUE_ORDER := [Economy.Ore.CRYSTAL, Economy.Ore.RARE_METALS, Economy.Ore.TITANIUM, Economy.Ore.FUEL,
		Economy.Ore.WATER, Economy.Ore.SILICATES, Economy.Ore.HEAVY_ORE, Economy.Ore.IRON]


# --- Queue and visit ---------------------------------------------------------------

## Queues every unlooted hulk of [param id] within [param radius] (flat)
## of [param pos] that this survey has not visited yet.
static func queue_near(s: Dictionary, id: StringName, pos: Vector3, radius: float) -> void:
	var def := Sector.system_def(id)
	var st := Sector.state(id)
	if def == null or st == null or def.derelicts.is_empty():
		return
	var q: PackedStringArray = s.get("salvage", PackedStringArray())
	var done: PackedStringArray = s.get("salvaged", PackedStringArray())
	var changed := false
	for x in def.derelicts:
		if st.looted.has(x.name) or q.has(x.name) or done.has(x.name):
			continue
		if SpaceNav.flat_distance(x.position(), pos) <= radius:
			q.append(x.name)
			changed = true
	if changed:
		s["salvage"] = q


## The hulk being visited, else the next queued one ("" = none).
static func next_visit(s: Dictionary) -> String:
	var v := String(s.get("visit", ""))
	if not v.is_empty():
		return v
	var q: PackedStringArray = s.get("salvage", PackedStringArray())
	return q[0] if not q.is_empty() else ""


static func find_def(id: StringName, item: String) -> DerelictDef:
	var def := Sector.system_def(id)
	if def:
		for x in def.derelicts:
			if x.name == item:
				return x
	return null


## Where the explorer hovers over hulk [param item].
static func hover_point(id: StringName, item: String) -> Vector3:
	var x := find_def(id, item)
	return x.position() + Vector3.UP * HOVER_HEIGHT if x else Vector3.ZERO


## The visit is over (looted, or given up): off the queue.
static func end_visit(s: Dictionary, item: String) -> void:
	var q: PackedStringArray = s.get("salvage", PackedStringArray())
	var i := q.find(item)
	if i >= 0:
		q.remove_at(i)
	s["salvage"] = q
	var done: PackedStringArray = s.get("salvaged", PackedStringArray())
	if not done.has(item):
		done.append(item)
	s["salvaged"] = done
	s.erase("visit")
	s.erase("visit_t")


# --- Loot ---------------------------------------------------------------------------

## What hulk [param x] in system [param id] gives with [param room] units
## of hold free: {ore: Array (Economy.Ore order), credits, part (module id
## or ""), left (units left behind)}. Seeded: the same hulk always gives
## the same.
static func roll(id: StringName, x: DerelictDef, room: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%s:%s" % [Sector.get_seed(), id, x.name])
	var k := float(clampi(x.loot_tier, 1, 3))
	var ore: Array = []
	ore.resize(Economy.COUNT)
	ore.fill(0)
	var credits := 0
	var part_chance := 0.0
	match String(x.loot_table):
		"derelict_probe":
			credits = roundi(rng.randf_range(40.0, 90.0) * k)
			ore[Economy.Ore.CRYSTAL] += roundi(rng.randf_range(3.0, 8.0) * k)
			part_chance = 0.15 + 0.1 * k
		"derelict_frigate":
			credits = roundi(rng.randf_range(60.0, 120.0) * k)
			ore[Economy.Ore.TITANIUM] += roundi(rng.randf_range(8.0, 16.0) * k)
			part_chance = 0.25 + 0.15 * k
		"derelict_station":
			credits = roundi(rng.randf_range(150.0, 250.0) * k)
			ore[Economy.Ore.IRON] += roundi(rng.randf_range(15.0, 30.0) * k)
			ore[Economy.Ore.TITANIUM] += roundi(rng.randf_range(8.0, 16.0) * k)
			if rng.randf() < 0.5:
				ore[_good(rng)] += roundi(rng.randf_range(5.0, 10.0) * k)
			part_chance = 0.45 + 0.15 * k
		_:
			# Freighters (and unknown tables): mostly cargo.
			credits = roundi(rng.randf_range(20.0, 60.0) * k)
			var main: int = [Economy.Ore.TITANIUM, Economy.Ore.CRYSTAL, Economy.Ore.CRYSTAL][clampi(x.loot_tier, 1, 3) - 1]
			if x.loot_tier == 1 and rng.randf() < 0.5:
				main = Economy.Ore.IRON
			ore[main] += roundi(rng.randf_range(12.0, 22.0) * k)
			if rng.randf() < 0.6:
				ore[_good(rng)] += roundi(rng.randf_range(4.0, 10.0) * k)
			part_chance = 0.1 * k
	var part := ""
	if rng.randf() < part_chance:
		var want := 3 if x.loot_tier >= 3 and rng.randf() < 0.5 else 2
		var pool: Array[ShipModule] = []
		for m in ModuleCatalog.shared().modules:
			if m.tier == want:
				pool.append(m)
		if not pool.is_empty():
			part = String(pool[rng.randi() % pool.size()].id)
	# Only what fits, most valuable first.
	var left := 0
	var free := maxi(room, 0)
	for t: int in VALUE_ORDER:
		var take := mini(int(ore[t]), free)
		left += int(ore[t]) - take
		ore[t] = take
		free -= take
	return {"ore": ore, "credits": credits, "part": part, "left": left}


static func _good(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(Economy.BASE_COUNT, Economy.COUNT - 1)


## Units in the survey's hold.
static func hold_used(s: Dictionary) -> int:
	var n := 0
	for v in s.get("hold", []):
		n += int(v)
	return n


## Strips hulk [param item] of system [param id] into survey [param s]
## (see the class notes). Returns the loot text ("" when someone else
## already stripped it).
static func salvage(id: StringName, s: Dictionary, item: String) -> String:
	var st := Sector.state(id)
	var x := find_def(id, item)
	end_visit(s, item)
	if st == null or x == null or st.looted.has(item):
		return ""
	var r := roll(id, x, HOLD - hold_used(s))
	var hold: Array = s.get("hold", [])
	if hold.size() < Economy.COUNT:
		hold.resize(Economy.COUNT)
		for i in Economy.COUNT:
			if hold[i] == null:
				hold[i] = 0
	var ore: Array = r["ore"]
	for i in Economy.COUNT:
		hold[i] = int(hold[i]) + int(ore[i])
	s["hold"] = hold
	s["loot_cr"] = int(s.get("loot_cr", 0)) + int(r["credits"])
	if not String(r["part"]).is_empty():
		var parts: PackedStringArray = s.get("parts", PackedStringArray())
		parts.append(String(r["part"]))
		s["parts"] = parts
	Sector.mark_looted(id, item)
	var text := loot_text(ore, int(r["credits"]), PackedStringArray([r["part"]]) if not String(r["part"]).is_empty() else PackedStringArray())
	var def := Sector.system_def(id)
	var where := def.system_name if def else String(id)
	var what := String(Survey.DERELICT_WORDS[clampi(x.kind, 0, 3)])
	var who := String(s.get("finder", "An explorer"))
	var full := " (hold full, %d left behind)" % int(r["left"]) if int(r["left"]) > 0 else ""
	EventLog.post("%s salvaged a derelict %s in %s: %s%s" % [who, what, where, text, full], EventLog.Kind.REWARD, null, Vector3.INF, "salvage:%s:%s" % [id, item])
	var lines: PackedStringArray = s.get("loot_lines", PackedStringArray())
	lines.append("%s: %s" % [item, text])
	s["loot_lines"] = lines
	return text


## "30 crystal, 8 fuel, Armor Plating Mk II, 120 cr".
static func loot_text(ore: Array, credits: int, parts: PackedStringArray) -> String:
	var bits: PackedStringArray = []
	for i in mini(ore.size(), Economy.COUNT):
		if int(ore[i]) > 0:
			bits.append("%d %s" % [int(ore[i]), Economy.ore_name(i).to_lower()])
	for p in parts:
		var m := ModuleCatalog.shared().find(StringName(p))
		bits.append(m.display_name if m else p)
	if credits > 0:
		bits.append("%s cr" % Fmt.amount(credits))
	return ", ".join(bits) if not bits.is_empty() else "nothing of use"


## True when survey [param s] carries salvage.
static func has_loot(s: Dictionary) -> bool:
	return hold_used(s) > 0 or int(s.get("loot_cr", 0)) > 0 or not (s.get("parts", PackedStringArray()) as PackedStringArray).is_empty()


## The explorer [param ship] is home with survey [param s]: the salvage
## goes into the station (see the class notes) and leaves the survey.
## Returns the loot text ("" when there was none).
static func deliver(ship: Ship, s: Dictionary) -> String:
	if not has_loot(s):
		return ""
	var hold: Array = s.get("hold", [])
	var ore := Economy.zero_ore()
	for i in mini(hold.size(), Economy.COUNT):
		ore[i] = int(hold[i])
	var credits := int(s.get("loot_cr", 0))
	var parts: PackedStringArray = s.get("parts", PackedStringArray())
	var factory := Factory.find(ship) if ship else null
	var sold := 0
	for p in parts:
		var m := ModuleCatalog.shared().find(StringName(p))
		if m == null:
			continue
		if factory:
			factory.add_rare_part(m)
		else:
			sold += roundi(float(m.cost) * PART_SALE)
	var text := loot_text(Array(ore), credits, parts)
	if hold_used(s) > 0:
		Economy.receive_cargo(ore, INCOME_SOURCE)
	if credits + sold > 0:
		Economy.add_income(credits + sold, INCOME_SOURCE, "Derelict salvage")
	var who := ship.captain.captain_name if ship and ship.captain else "An explorer"
	var note := " (no Factory: parts sold for %s cr)" % Fmt.amount(sold) if sold > 0 else ""
	EventLog.post("%s brought salvage home: %s%s" % [who, text, note], EventLog.Kind.REWARD, ship)
	for key in ["hold", "loot_cr", "parts", "loot_lines"]:
		s.erase(key)
	return text

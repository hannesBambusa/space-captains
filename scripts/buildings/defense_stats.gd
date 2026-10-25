class_name DefenseStats
extends RefCounted
## Numbers for the build tooltip and the building panel of the station
## defenses: what a Defense Turret or a Shield Generator does, from the
## scripts' own values (DefenseTurret, ShieldGenerator, StationShield) and
## the raider factions' loadouts (data/factions/*.tres), so the text follows
## any retune. "" for other buildings.

static var _cache: Dictionary = {}


## The block of lines for [param def], or "".
static func describe(def: BuildingDef) -> String:
	if def == null or def.service_script == null:
		return ""
	if _cache.has(def.id):
		return _cache[def.id]
	var text := ""
	var probe: Variant = def.service_script.new()
	if probe is DefenseTurret:
		text = _turret(probe as DefenseTurret)
	elif probe is ShieldGenerator:
		text = _shield(probe as ShieldGenerator)
	if probe is Node:
		(probe as Node).free()
	_cache[def.id] = text
	return text


## Damage per second of [param t] against a target that does not dodge.
static func turret_dps(t: DefenseTurret) -> float:
	return t.weapon_damage * t.fire_rate * t.accuracy


static func _turret(t: DefenseTurret) -> String:
	var dps := turret_dps(t)
	var lines: PackedStringArray = []
	lines.append("Guns: %d damage x %.1f shots/s at %d%% accuracy, about %d damage/s" % [roundi(t.weapon_damage), t.fire_rate, roundi(t.accuracy * 100.0), roundi(dps)])
	lines.append("Range %d m (raider guns reach %d to %d m)" % [roundi(t.weapon_range), roundi(_min_range()), roundi(_max_range())])
	lines.append("Hull %d + %d shields, repaired by the station" % [roundi(t.max_hull), roundi(t.max_shields)])
	var kills: PackedStringArray = []
	for id: StringName in [&"scavenger", &"corsair", &"syndicate"]:
		var f := _faction(id)
		if f == null or f.loadout == null:
			continue
		var st := f.loadout.derive()
		var eff := dps * (1.0 - f.ship_dodge)
		var what := "syndicate gunship" if id == &"syndicate" else f.unit_name.to_lower()
		kills.append("%s in about %d s" % [what, roundi((st.max_hull + st.max_shields) / maxf(eff, 0.1))])
	if not kills.is_empty():
		lines.append("One turret alone kills a %s; two take half as long" % ", a ".join(kills))
	return "\n".join(lines)


static func _shield(g: ShieldGenerator) -> String:
	var b := StationShield.new()
	var lines: PackedStringArray = []
	lines.append("Bubble %d HP over the whole complex, regenerates %d HP/s after %d s without hits" % [roundi(b.max_hp), roundi(b.regen), roundi(b.regen_delay)])
	lines.append("Broken, it re-raises after %d s at %d%%" % [roundi(b.cooldown), roundi(b.restore_fraction * 100.0)])
	var sc := _faction(&"scavenger")
	if sc and sc.loadout:
		var st := sc.loadout.derive()
		var raider := st.weapon_damage * st.fire_rate * sc.ship_accuracy
		var two := raider * 2.0
		lines.append("Raiders must break it before they can hit anything inside: 2 scavengers (about %d damage/s) need about %d s, 4 about %d s, while the turrets inside fire out" % [
				roundi(two), roundi(b.max_hp / maxf(two, 0.1)), roundi(b.max_hp / maxf(two * 2.0, 0.1))])
	lines.append("Generator hull %d + %d shields, only exposed while the bubble is down" % [roundi(g.max_hull), roundi(g.max_shields)])
	b.free()
	return "\n".join(lines)


## Loaded without Factions' static cache, so nothing is held at exit.
static func _faction(id: StringName) -> FactionDef:
	var path := "%s%s.tres" % [Factions.DIR, id]
	return load(path) as FactionDef if ResourceLoader.exists(path) else null


static func _min_range() -> float:
	var r := INF
	for id: StringName in [&"scavenger", &"corsair", &"syndicate"]:
		var f := _faction(id)
		if f and f.loadout and f.loadout.tool:
			r = minf(r, f.loadout.tool.weapon_range)
	return r if r < INF else 0.0


static func _max_range() -> float:
	var r := 0.0
	for id: StringName in [&"scavenger", &"corsair", &"syndicate"]:
		var f := _faction(id)
		if f and f.loadout and f.loadout.tool:
			r = maxf(r, f.loadout.tool.weapon_range)
	return r

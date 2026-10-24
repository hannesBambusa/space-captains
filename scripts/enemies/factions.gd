class_name Factions
extends RefCounted
## Looks up FactionDefs by id (res://data/factions/<id>.tres, cached) and
## the faction of any hostile node.

const DIR := "res://data/factions/"
const DEFAULT_ID := &"scavenger"

static var _cache: Dictionary = {}


## The faction with [param faction_id], or the scavengers when unknown.
static func get_def(faction_id: StringName) -> FactionDef:
	if _cache.has(faction_id):
		return _cache[faction_id]
	var path := "%s%s.tres" % [DIR, faction_id]
	var f: FactionDef = null
	if ResourceLoader.exists(path):
		f = load(path) as FactionDef
	if f == null:
		if faction_id != DEFAULT_ID:
			return get_def(DEFAULT_ID)
		f = FactionDef.new()
	_cache[faction_id] = f
	return f


static func scavengers() -> FactionDef:
	return get_def(DEFAULT_ID)


## Faction of a hostile ship or base, null for anything else.
static func of(n: Variant) -> FactionDef:
	if not is_instance_valid(n):
		return null
	if n is ScavengerShip:
		return (n as ScavengerShip).faction_def
	if n is ScavengerDen:
		return (n as ScavengerDen).faction_def
	return null

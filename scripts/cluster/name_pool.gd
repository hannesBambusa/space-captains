class_name NamePool
extends Resource
## Names for the generated systems (data/cluster/name_pool.tres). The
## generator shuffles each list with the network seed and hands names out
## through a [NamePool.Allocator], so every name is used once per network.

const PATH := "res://data/cluster/name_pool.tres"

@export var system_names: PackedStringArray = []
## Planets and moons (unique across the whole network: planet raid records
## are keyed by name).
@export var planet_names: PackedStringArray = []
## Cluster names are "<prefix> <suffix>" ("Flint Shoal").
@export var cluster_prefixes: PackedStringArray = []
@export var cluster_suffixes: PackedStringArray = []
## Gang names of the bases, per faction.
@export var scavenger_gangs: PackedStringArray = []
@export var corsair_gangs: PackedStringArray = []
@export var syndicate_gangs: PackedStringArray = []
## Derelict hulks ("Wreck of the Long Patience").
@export var derelict_names: PackedStringArray = []


static func load_default() -> NamePool:
	return load(PATH) as NamePool


## Hands out names, each once. Lists are shuffled once with the network
## rng; names already in use (home's) are reserved up front. When a list
## runs out, names get a number ("Calder 2").
class Allocator extends RefCounted:
	var _used: Dictionary = {}
	var _lists: Dictionary = {}
	var _next: Dictionary = {}

	func _init(pool: NamePool, rng: RandomNumberGenerator) -> void:
		var clusters: PackedStringArray = []
		for p in pool.cluster_prefixes:
			for s in pool.cluster_suffixes:
				clusters.append("%s %s" % [p, s])
		var src := {&"system": pool.system_names, &"planet": pool.planet_names, &"cluster": clusters,
				&"scavenger": pool.scavenger_gangs, &"corsair": pool.corsair_gangs,
				&"syndicate": pool.syndicate_gangs, &"derelict": pool.derelict_names}
		for kind: StringName in [&"system", &"planet", &"cluster", &"scavenger", &"corsair", &"syndicate", &"derelict"]:
			var list := Array(src[kind] as PackedStringArray)
			# Fisher-Yates with the network rng (Array.shuffle uses the global one).
			for i in range(list.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var t: Variant = list[i]
				list[i] = list[j]
				list[j] = t
			_lists[kind] = list
			_next[kind] = 0

	func reserve(n: String) -> void:
		_used[n] = true

	func is_used(n: String) -> bool:
		return _used.has(n)

	## The next free name of [param kind] (&"system", &"planet", &"cluster",
	## &"scavenger", &"corsair", &"syndicate", &"derelict").
	func take(kind: StringName) -> String:
		var list: Array = _lists.get(kind, [])
		var i: int = _next.get(kind, 0)
		while i < list.size():
			var n := String(list[i])
			i += 1
			if not _used.has(n):
				_next[kind] = i
				_used[n] = true
				return n
		_next[kind] = i
		# Ran out: numbered names from the list.
		var base := String(list[0]) if not list.is_empty() else String(kind).capitalize()
		var k := 2
		while _used.has("%s %d" % [base, k]):
			k += 1
		var out := "%s %d" % [base, k]
		_used[out] = true
		return out

class_name Combat
extends RefCounted
## Shared combat rules and queries. Anything that can be shot joins
## [constant GROUP] and implements the combatant API:
##   get_faction() -> int, is_alive() -> bool, is_targetable() -> bool,
##   get_hit_radius() -> float, get_aim_velocity() -> Vector3,
##   take_hit(damage: float, attacker: Node, at: Vector3) -> void,
##   get_dodge() -> float, get_display_name() -> String
## Ships (Ship) and Scavenger Dens (ScavengerDen) do.

enum Faction { PLAYER, SCAVENGER }

const GROUP := "combatants"
const PLAYER_TRACER := Color(0.45, 0.85, 1.0)
const HOSTILE_TRACER := Color(1.0, 0.42, 0.18)
const HOSTILE_COLOR := Color(1.0, 0.3, 0.24)


## Untyped on purpose: callers pass references that may have been freed.
static func is_live(n: Variant) -> bool:
	if not is_instance_valid(n):
		return false
	var node := n as Node
	return node != null and node.is_inside_tree() and bool(node.call(&"is_alive"))


static func is_live_target(n: Variant) -> bool:
	return is_live(n) and bool((n as Node).call(&"is_targetable"))


## [param n]'s get_display_name(), or [param fallback] when it has none or
## is gone. Untyped: [param n] may have been freed.
static func name_of(n: Variant, fallback: String = "") -> String:
	if is_instance_valid(n) and (n as Object).has_method(&"get_display_name"):
		return String((n as Object).call(&"get_display_name"))
	return fallback


## " by Kestrel" for feed lines, "" when [param killer] is unknown or gone.
static func by_suffix(killer: Variant) -> String:
	return " by %s" % name_of(killer) if is_instance_valid(killer) and (killer as Object).has_method(&"get_display_name") else ""


static func hostile(a: int, b: int) -> bool:
	return a != b


## Live, targetable combatants hostile to [param faction] within
## [param radius] of [param pos] (on the plane), nearest first.
static func hostiles_near(tree: SceneTree, pos: Vector3, radius: float, faction: int) -> Array[Node3D]:
	var found: Array[Node3D] = []
	var dists: Array[float] = []
	var r2 := radius * radius
	for n in tree.get_nodes_in_group(GROUP):
		var c := n as Node3D
		if c == null or not hostile(int(c.call(&"get_faction")), faction) or not is_live_target(c):
			continue
		var d := c.global_position - pos
		var d2 := d.x * d.x + d.z * d.z
		if d2 > r2:
			continue
		var i := dists.bsearch(d2)
		dists.insert(i, d2)
		found.insert(i, c)
	return found


## The node of [param nodes] nearest to [param pos] on the plane (freed
## ones skipped), or null.
static func nearest_of(nodes: Array, pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for n in nodes:
		if not is_instance_valid(n):
			continue
		var d := SpaceNav.flat_distance(pos, (n as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


static func nearest_hostile(tree: SceneTree, pos: Vector3, radius: float, faction: int) -> Node3D:
	var list := hostiles_near(tree, pos, radius, faction)
	return list[0] if not list.is_empty() else null

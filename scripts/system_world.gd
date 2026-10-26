class_name SystemWorld
extends Node3D
## Root of one live star system (scenes/system.tscn). Each live system runs
## in its own SubViewport with its own World3D (scenes/game.tscn), so every
## system-side lookup goes through the system a node is in:
## [method of] reads the "system_world" meta this node puts on its viewport.
## Nodes outside every system (the HUD, the selection and placement
## controllers at the top of game.tscn) get the viewed system
## ([ViewManager]). The members ([member sys], [member combat],
## [member buildings], [member camera]) read null until that node is ready
## (joined its group), like the old tree-wide group lookups.
##
## Group scans: [method nodes_in] returns the group's nodes in the same
## system as the asking node.

const META := &"system_world"
const GROUP := "system_world"

var sys: SolarSystem:
	get:
		return _member(^"SolarSystem", SolarSystem.GROUP) as SolarSystem

var combat: CombatWorld:
	get:
		return _member(^"Combat", CombatWorld.GROUP) as CombatWorld

var buildings: BuildingManager:
	get:
		return _member(^"Buildings", BuildingManager.GROUP) as BuildingManager

var camera: RTSCamera:
	get:
		return _member(^"RTSCamera", RTSCamera.GROUP) as RTSCamera

var contract_markers: ContractMarkers:
	get:
		return _member(^"ContractMarkers", ContractMarkers.GROUP) as ContractMarkers

## The node undocked ships fly under ([method SpaceNav.space_root]).
var ships_root: Node3D:
	get:
		return SpaceNav.space_root(self)

var _members: Dictionary = {}


func _enter_tree() -> void:
	add_to_group(GROUP)
	get_viewport().set_meta(META, self)
	var vm := ViewManager.of(get_tree())
	if vm:
		vm.register(self)


func _exit_tree() -> void:
	var vp := get_viewport()
	if vp.has_meta(META) and vp.get_meta(META) == self:
		vp.remove_meta(META)
	var vm := ViewManager.of(get_tree())
	if vm:
		vm.unregister(self)


## The system [param n] lives in: its viewport's system, else the viewed
## one (UI and controllers outside every system). Null outside the tree.
static func of(n: Node) -> SystemWorld:
	if n == null or not n.is_inside_tree():
		return null
	var vp := n.get_viewport()
	if vp.has_meta(META):
		var w: Variant = vp.get_meta(META)
		if is_instance_valid(w):
			return w as SystemWorld
	var vm := ViewManager.of(n.get_tree())
	return vm.viewed if vm else null


## The home system (for global code: saves, research, the contract board).
static func home(tree: SceneTree) -> SystemWorld:
	if tree == null:
		return null
	var vm := ViewManager.of(tree)
	if vm and is_instance_valid(vm.home):
		return vm.home
	return tree.get_first_node_in_group(GROUP) as SystemWorld


## Every live system.
static func all(tree: SceneTree) -> Array[SystemWorld]:
	var out: Array[SystemWorld] = []
	if tree:
		for n in tree.get_nodes_in_group(GROUP):
			out.append(n as SystemWorld)
	return out


## The active Camera3D of [param n]'s system (for screen-space UI outside
## it: its own viewport has no 3D camera).
static func camera_3d(n: Node) -> Camera3D:
	var w := of(n)
	return w.get_viewport().get_camera_3d() if w else null


## Nodes of [param group] in [param n]'s system (all of them while only one
## system is live).
static func nodes_in(n: Node, group: StringName) -> Array[Node]:
	if n == null or not n.is_inside_tree():
		var none: Array[Node] = []
		return none
	var tree := n.get_tree()
	var list := tree.get_nodes_in_group(group)
	if tree.get_node_count_in_group(GROUP) <= 1:
		return list
	var w := of(n)
	var out: Array[Node] = []
	for x in list:
		if of(x) == w:
			out.append(x)
	return out


## Child at [param path] once it has joined [param group] (cached).
func _member(path: NodePath, group: StringName) -> Node:
	var cached: Variant = _members.get(path)
	if cached != null and is_instance_valid(cached):
		return cached as Node
	var n := get_node_or_null(path)
	if n == null or not n.is_in_group(group):
		return null
	_members[path] = n
	return n

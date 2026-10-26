class_name ViewManager
extends Node
## Root of scenes/game.tscn. Knows the live systems ([SystemWorld], each in
## its own SubViewport under the SystemView container), the home system and
## the one on screen. UI and controllers outside every system act on the
## viewed one ([method SystemWorld.of]). Only home is live for now; the view
## switch comes with the other systems.

signal view_changed(world: SystemWorld)

const GROUP := "view_manager"

## The player's home system (the first one that enters).
var home: SystemWorld
## The system on screen.
var viewed: SystemWorld


static func of(tree: SceneTree) -> ViewManager:
	return tree.get_first_node_in_group(GROUP) as ViewManager if tree else null


func _enter_tree() -> void:
	# Before the systems below enter, so they can register.
	add_to_group(GROUP)


## Called by every [SystemWorld] entering the tree.
func register(world: SystemWorld) -> void:
	if home == null:
		home = world
	if viewed == null:
		viewed = world
		view_changed.emit(world)


func unregister(world: SystemWorld) -> void:
	if home == world:
		home = null
	if viewed == world:
		viewed = home
		view_changed.emit(viewed)

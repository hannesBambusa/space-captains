class_name SystemPreview
extends RefCounted
## Debug only: builds a generated system's scene (scenes/system.tscn with
## the def swapped in, no buildings, no contract markers) in a throwaway
## SubViewport with its own World3D, so it never touches home's world.
## No gameplay use; the real live/data switch is SystemHost.

const SYSTEM_SCENE := "res://scenes/system.tscn"


## A SubViewport under [param parent] showing [param def], rendering
## every frame at [param size]. Free the returned viewport to drop it.
static func build(parent: Node, def: SystemDef, size: Vector2i = Vector2i(1600, 900)) -> SubViewport:
	var vp := SubViewport.new()
	vp.name = "Preview_%s" % def.system_name.validate_node_name()
	vp.own_world_3d = true
	vp.size = size
	vp.audio_listener_enable_3d = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var world := (load(SYSTEM_SCENE) as PackedScene).instantiate()
	# No id: registers nowhere, never home, no directors.
	(world as SystemWorld).system_id = &""
	(world.get_node(^"SolarSystem") as SolarSystem).system_def = def
	for n: NodePath in [^"Buildings", ^"ContractMarkers"]:
		var x := world.get_node_or_null(n)
		if x:
			world.remove_child(x)
			x.free()
	vp.add_child(world)
	parent.add_child(vp)
	return vp

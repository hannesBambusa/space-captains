class_name StaticCombatant
extends Node3D
## Base for the combatants that do not fly (see [Combat]): the structures'
## hulls (StructureHull, DefenseStructure), the station shield and the
## hostile bases (ScavengerDen). They never dodge; by default they are the
## player's and are aimed at with their own motion through space.


func get_faction() -> int:
	if not Corps.has_rival():
		return Combat.Faction.PLAYER
	# The corp of the system it stands in (a structure never moves system).
	if _corp_faction < 0 and is_inside_tree():
		_corp_faction = Combat.faction_of_corp(Corps.corp_of_node(self))
	return _corp_faction if _corp_faction >= 0 else Combat.Faction.PLAYER


var _corp_faction := -1


func get_aim_velocity() -> Vector3:
	return SpaceNav.world_velocity(self)


func get_dodge() -> float:
	return 0.0

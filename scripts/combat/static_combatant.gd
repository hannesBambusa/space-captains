class_name StaticCombatant
extends Node3D
## Base for the combatants that do not fly (see [Combat]): the structures'
## hulls (StructureHull, DefenseStructure), the station shield and the
## hostile bases (ScavengerDen). They never dodge; by default they are the
## player's and are aimed at with their own motion through space.


func get_faction() -> int:
	return Combat.Faction.PLAYER


func get_aim_velocity() -> Vector3:
	return SpaceNav.world_velocity(self)


func get_dodge() -> float:
	return 0.0

class_name TechDef
extends Resource
## One research project (data/research/*.tres, listed in catalog.tres). The
## player funds it at the Science Lab; a hired researcher picks it up and
## works on it for [member research_time] sim seconds (at speed 1: a skill 5
## researcher of the same field). When done it unlocks modules the Factory
## may make and the Outfitter may sell, and buildings the build bar offers.

enum Field { ENGINEERING, WEAPONS, PLANETARY }

const FIELD_NAMES: PackedStringArray = ["Engineering", "Weapons", "Planetary"]
const TIER_NAMES: PackedStringArray = ["", "Tier I", "Tier II", "Tier III"]

@export var id: StringName = &""
@export var display_name: String = "Project"
@export var field: Field = Field.ENGINEERING
@export_range(1, 3) var tier: int = 1
@export var cost_credits: int = 0
@export var cost_iron: int = 0
@export var cost_titanium: int = 0
@export var cost_crystal: int = 0
## Sim seconds of work at speed 1.
@export var research_time: float = 120.0
## Tech ids that must be done first.
@export var prerequisites: Array[StringName] = []
## ShipModule ids the Factory may make once this is done.
@export var unlock_modules: Array[StringName] = []
## BuildingDef ids the build bar offers once this is done.
@export var unlock_buildings: Array[StringName] = []
## Kind of work, read by researcher personalities: "defence", "weapons",
## "economy", "building".
@export var tags: PackedStringArray = []
## Hit chance added to every mercenary's accuracy (0.05 = +5 points).
@export var merc_accuracy: float = 0.0
## Hold added to every miner (0.1 = 10% of a load).
@export var miner_hold: float = 0.0
## Prepared for a later phase: not listed, cannot be funded.
@export var hidden: bool = false
@export_multiline var description: String = ""
## One plain line on what the project is good for (the research tooltip's
## lead line, above the benefits made from the unlocks and numbers).
@export var benefit: String = ""


func cost_ore() -> PackedInt32Array:
	return Economy.cost(cost_iron, cost_titanium, cost_crystal)


func field_name() -> String:
	return FIELD_NAMES[field]


## "650 cr + 40 titanium".
func cost_text() -> String:
	var ore := Economy.cost_text(cost_ore())
	return "%s cr%s" % [Fmt.amount(cost_credits), " + " + ore if not ore.is_empty() else ""]


func has_tag(tag: String) -> bool:
	return tags.has(tag)

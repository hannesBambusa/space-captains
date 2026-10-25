class_name TechCatalog
extends Resource
## Every research project (data/research/catalog.tres, one TechDef .tres per
## tech). Lookups by tech id and by what a tech unlocks.

const PATH := "res://data/research/catalog.tres"

@export var techs: Array[TechDef] = []

static var _shared: TechCatalog


static func shared() -> TechCatalog:
	if _shared == null:
		if ResourceLoader.exists(PATH):
			_shared = load(PATH) as TechCatalog
		if _shared == null:
			_shared = TechCatalog.new()
	return _shared


func find(tech_id: StringName) -> TechDef:
	for t in techs:
		if t and t.id == tech_id:
			return t
	return null


## The tech that unlocks module [param module_id], or null (always available).
func for_module(module_id: StringName) -> TechDef:
	for t in techs:
		if t and t.unlock_modules.has(module_id):
			return t
	return null


## The tech that unlocks building [param building_id], or null.
func for_building(building_id: StringName) -> TechDef:
	for t in techs:
		if t and t.unlock_buildings.has(building_id):
			return t
	return null


## Listed techs of [param field] (hidden ones left out), tier then name.
func of_field(field: int) -> Array[TechDef]:
	var out: Array[TechDef] = []
	for t in techs:
		if t and not t.hidden and t.field == field:
			out.append(t)
	out.sort_custom(func(a: TechDef, b: TechDef) -> bool:
		return a.tier < b.tier if a.tier != b.tier else a.display_name < b.display_name)
	return out

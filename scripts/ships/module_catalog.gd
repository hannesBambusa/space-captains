class_name ModuleCatalog
extends Resource
## Every module the Outfitter can sell (data/modules/catalog.tres, one .tres
## per module and tier). Generated lists stay in data so tuning is a data
## edit; [method for_role] filters by the role that may fit them.

const PATH := "res://data/modules/catalog.tres"

@export var modules: Array[ShipModule] = []

static var _shared: ModuleCatalog


static func shared() -> ModuleCatalog:
	if _shared == null:
		if ResourceLoader.exists(PATH):
			_shared = load(PATH) as ModuleCatalog
		if _shared == null:
			_shared = ModuleCatalog.new()
	return _shared


func for_role(role: String) -> Array[ShipModule]:
	var out: Array[ShipModule] = []
	for m in modules:
		if m and m.fits_role(role):
			out.append(m)
	return out


func find(module_id: StringName) -> ShipModule:
	for m in modules:
		if m and m.id == module_id:
			return m
	return null

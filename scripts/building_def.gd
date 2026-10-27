class_name BuildingDef
extends Resource
## Data for one building type. The build menu shows one button per def;
## Building instances the model and runs construction from these values.
## Times are sim seconds, distances metres.

@export var id: StringName = &""
@export var display_name: String = "Building"
## Short label for the build menu button.
@export var short_label: String = ""
@export_multiline var description: String = ""
## .glb or .tscn. Missing file = procedural placeholder.
@export_file("*.glb", "*.tscn") var model_path: String = ""
@export var cost_credits: int = 0
## Ore cost: mostly iron; advanced structures also need titanium.
@export var cost_iron: int = 0
@export var cost_titanium: int = 0
## Water (a planet good) for structures that carry people (the Forward Station).
@export var cost_water: int = 0
@export var build_time: float = 20.0
## Clearance radius on the plane, used for placement and picking.
@export var footprint_radius: float = 35.0
## Most of this type the player may own. 0 = no limit.
@export var max_count: int = 0
## Hull and light colour of the placeholder model (alpha 0 = default look).
@export var placeholder_tint: Color = Color(0, 0, 0, 0)
## Optional service node added to the building when placed (e.g. Outfitter).
@export var service_script: Script
## Hull raiders can shoot (StructureHull): at 0 the structure is disabled
## until repaired, never destroyed. 0 = none (addons; turrets and the shield
## generator have their own, DefenseStructure).
@export var structure_hull: float = 0.0
## False: listed in the build bar (locked) but not buildable yet, for
## structures a later phase brings in (the Raider Dock).
@export var in_service: bool = true
## Buildable at a forward station (BuildingManager.forward). Only the
## Science Lab (and the Forward Station itself) are home only.
@export var allowed_forward: bool = true
## Most of this type per forward station; -1 = [member max_count].
@export var forward_max_count: int = -1

@export_group("Placement")
## Stands on its own (defense turrets): placed anywhere in the build zone
## clear of other footprints and docking lanes; not part of the complex
## bounds (the shield bubble does not stretch for it).
@export var standalone: bool = false
## Radius of a range ring shown around the placement ghost, m (0 = none).
@export var preview_range: float = 0.0
## Clear gap kept to other structures, m. -1 = BuildingManager.min_gap.
## Small structures (turrets) may sit closer.
@export var min_gap: float = -1.0

@export_group("Cargo shuttles")
## Most cargo shuttles this structure runs to the station (CargoDepot). 0 =
## none: deliveries go straight into the player's stock.
@export var max_shuttles: int = 0
## Units one shuttle carries per trip.
@export var shuttle_capacity: int = 60
## > 0: no cargo, the shuttle flies a cosmetic supply run this often, sim
## seconds (the Mercenary Outpost).
@export var shuttle_supply_interval: float = 0.0

@export_group("Station addon")
## Built onto one of the station's addon bays (BuildingManager.bay_count)
## instead of standing on the plane: no footprint or zone checks. The
## model's origin is the attach point, its body along +Z (radially outward). The build menu lists addons in their own group.
@export var station_addon: bool = false
## Used while [member model_path] is missing (e.g. the old standalone model),
## scaled by [member addon_fallback_scale] and moved by
## [member addon_fallback_offset] so it sits outward of the bay.
@export_file("*.glb", "*.tscn") var addon_fallback_model_path: String = ""
@export var addon_fallback_scale: float = 1.0
@export var addon_fallback_offset: Vector3 = Vector3.ZERO

@export_group("Hiring")
## Max ships this building can hold. 0 = no hiring.
@export var max_hires: int = 0
@export var hire_cost_credits: int = 0
## Role shown in the UI, e.g. "Miner".
@export var hire_role: String = ""
## Ship model for hired captains (.glb). Missing file = placeholder.
@export_file("*.glb", "*.tscn") var hire_ship_path: String = ""
## Ship class for hired captains (a Ship subclass). Null = MinerShip.
@export var hire_ship_script: Script
## Price of a new ship here (replacements, career switches), credits.
@export var ship_cost: int = 400

@export_group("Berths")
## Berths inside the hangar; the rest wait beside the apron. -1 = Building default.
@export var inner_berths: int = -1
@export var berth_spacing: float = -1.0
@export var berth_depth: float = -1.0
@export var outer_berth_side: float = -1.0
## Gap between outer berths on the same side, metres.
@export var outer_berth_step: float = 12.0


## Ore cost in Economy.Ore order.
func cost_ore() -> PackedInt32Array:
	var c := Economy.cost(cost_iron, cost_titanium)
	if cost_water > 0:
		c = Economy.padded(c)
		c[Economy.Ore.WATER] = cost_water
	return c


## The building's model: [member model_path], else (addons) the scaled
## fallback model, else the procedural placeholder.
func instantiate_model() -> Node3D:
	var placeholder := ModelLoader.building_placeholder.bind(footprint_radius, placeholder_tint)
	if not station_addon or (not model_path.is_empty() and ResourceLoader.exists(model_path)):
		return ModelLoader.instantiate(model_path, placeholder)
	var inner := ModelLoader.instantiate(addon_fallback_model_path, placeholder)
	inner.scale = Vector3.ONE * addon_fallback_scale
	inner.position = addon_fallback_offset
	var root := Node3D.new()
	root.name = "addon_fallback"
	root.add_child(inner)
	return root


func can_hire() -> bool:
	return max_hires > 0 and not hire_role.is_empty()

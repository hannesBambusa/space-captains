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
@export var cost_materials: int = 0
@export var build_time: float = 20.0
## Clearance radius on the plane, used for placement and picking.
@export var footprint_radius: float = 35.0
## Most of this type the player may own. 0 = no limit.
@export var max_count: int = 0
## Hull and light colour of the placeholder model (alpha 0 = default look).
@export var placeholder_tint: Color = Color(0, 0, 0, 0)
## Optional service node added to the building when placed (e.g. Outfitter).
@export var service_script: Script

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


func can_hire() -> bool:
	return max_hires > 0 and not hire_role.is_empty()

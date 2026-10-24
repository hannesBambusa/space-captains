class_name DenArrivalSite
extends Node3D
## Where a hostile base is about to arrive (ThreatDirector, during the
## long-range scan warning): a faint hologram of the base in its faction
## colour (the construction look's grid, nothing built yet) at the den's
## real spot. The map markers, minimap and overview show it as "Arriving"
## with a countdown. Has no hull and cannot be targeted; freed when the
## base arrives.

const GROUP := "den_arrivals"

var def: DenDef
var faction_def: FactionDef
## SimClock.time the base arrives.
var arrive_at: float = 0.0


func setup(den_def: DenDef, at_time: float) -> void:
	def = den_def
	faction_def = den_def.get_faction()
	arrive_at = at_time
	name = StringName("Arriving" + def.name.validate_node_name().replace(" ", ""))


func _ready() -> void:
	add_to_group(GROUP)
	var k := faction_def.den_hit_radius / 42.0
	set_meta(&"focus_radius", 60.0 * k)
	set_meta(&"focus_distance", 520.0 * k)
	var path := FactionDef.pick_model(faction_def.den_model_path, ScavengerDen.MODEL_PATH)
	var model := ModelLoader.instantiate(path, ModelLoader.building_placeholder.bind(50.0 * k, faction_def.color))
	model.name = "Hologram"
	add_child(model)
	if path != faction_def.den_model_path:
		model.scale *= faction_def.den_fallback_scale
	MeshUtil.set_layers_recursive(model, ScavengerDen.RENDER_LAYER)
	var mat := ShaderMaterial.new()
	mat.shader = Building.CONSTRUCTION_SHADER
	mat.set_shader_parameter("grid_size", 6.0 * k)
	mat.set_shader_parameter("holo_color", faction_def.color.lerp(Color.WHITE, 0.2))
	mat.set_shader_parameter("seam_color", faction_def.light_color)
	mat.set_shader_parameter("fill_y", -1.0e6)
	for mi in ModelLoader.meshes_of(model):
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func time_left() -> float:
	return maxf(arrive_at - SimClock.time, 0.0)


## "1:05"
func countdown_text() -> String:
	var s := ceili(time_left())
	return "%d:%02d" % [s / 60, s % 60]


## "Unknown corsair nest" (the faction is known from the warning, the base is not).
func get_display_name() -> String:
	return "Unknown %s" % faction_def.den_kind


func get_status_text() -> String:
	return "Arriving in %s" % countdown_text()

class_name Derelict
extends Node3D
## A derelict hulk in a generated system (P4), built by SolarSystem from a
## DerelictDef at its fixed spot. Looks only: a ship or station model by
## kind (probe: an escape pod, freighter: a cargo shuttle hull, frigate: a
## gunship, station hulk: a garrison frame), scaled up, darkened and burnt
## (its lights out), tilted and tumbling slowly, a few drifting pieces and
## a red distress beacon that blinks until an explorer strips it
## (DerelictLoot, Sector.derelict_looted). Hidden by the FogOfWar until
## revealed (FogOfWar.key_of: the def's name).

const GROUP := "derelicts"
const MODELS := ["res://assets/models/ships/escape_pod.glb", "res://assets/models/ships/cargo_shuttle.glb",
		"res://assets/models/ships/syndicate_gunship.glb", "res://assets/models/buildings/claim_garrison.glb"]
const SCALES := [3.0, 3.5, 2.2, 0.7]
## Rough size for the label offset and camera focus, metres.
const SIZES := [14.0, 40.0, 45.0, 62.0]
const BURNT := Color(0.3, 0.26, 0.23)
const BEACON := Color(1.0, 0.25, 0.18)
## Tumble rate, degrees per sim second.
const TUMBLE_DEG := 1.6

var def: DerelictDef

var _model: Node3D
var _beacon: OmniLight3D
var _beacon_mat: StandardMaterial3D
var _looted := false


func setup(d: DerelictDef) -> void:
	def = d
	name = StringName(("Derelict_" + d.name).validate_node_name().replace(" ", ""))


func size() -> float:
	return float(SIZES[clampi(def.kind, 0, 3)]) if def else 30.0


func _ready() -> void:
	add_to_group(GROUP)
	position = def.position()
	var k := clampi(def.kind, 0, 3)
	var h := hash(def.name)
	_model = ModelLoader.instantiate(String(MODELS[k]), ModelLoader.ship_placeholder)
	_model.name = "Model"
	add_child(_model)
	_model.scale *= float(SCALES[k])
	# Lying dead in space: rolled over and pitched, a slow tumble.
	_model.rotation = Vector3(deg_to_rad(float(h % 50) - 25.0), deg_to_rad(float(h % 360)), deg_to_rad(float((h / 7) % 80) + 20.0))
	ModelLoader.tint(_model, BURNT, 0.75)
	ModelLoader.dim_emission(_model, 0.0)
	_add_debris(h)
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beacon_mat.albedo_color = BEACON
	_beacon_mat.emission_enabled = true
	_beacon_mat.emission = BEACON
	var bulb := MeshInstance3D.new()
	bulb.name = "Beacon"
	var sm := SphereMesh.new()
	sm.radius = 1.6
	sm.height = 3.2
	bulb.mesh = sm
	bulb.material_override = _beacon_mat
	bulb.position = Vector3.UP * size() * 0.35
	add_child(bulb)
	_beacon = OmniLight3D.new()
	_beacon.light_color = BEACON
	_beacon.omni_range = size() * 2.0
	_beacon.position = bulb.position
	add_child(_beacon)
	set_meta(&"focus_radius", size() * 0.6)
	set_meta(&"focus_distance", size() * 6.0)
	Sector.derelict_looted.connect(_on_looted)
	var w := SystemWorld.of(self)
	var st := Sector.state(w.system_id) if w else null
	_set_looted(st != null and st.looted.has(def.name))


func _exit_tree() -> void:
	if Sector.derelict_looted.is_connected(_on_looted):
		Sector.derelict_looted.disconnect(_on_looted)


func get_display_name() -> String:
	return def.name if def else "Derelict"


func is_looted() -> bool:
	return _looted


func _on_looted(id: StringName, item: String) -> void:
	var w := SystemWorld.of(self)
	if w and w.system_id == id and def and item == def.name:
		_set_looted(true)


func _set_looted(on: bool) -> void:
	_looted = on
	var bulb := get_node_or_null(^"Beacon") as Node3D
	if bulb:
		bulb.visible = not on
	if _beacon:
		_beacon.visible = not on
	var l := get_node_or_null(^"Label") as Label3D
	if l and def:
		l.text = def.name.to_upper() + ("  (STRIPPED)" if on else "")


func _process(_delta: float) -> void:
	if _model:
		_model.rotation.y = fmod(SimClock.time * deg_to_rad(TUMBLE_DEG) + float(hash(def.name) % 360), TAU)
	if not _looted and _beacon:
		var on := fmod(Time.get_ticks_msec() / 1000.0, 1.6) < 0.25
		_beacon.light_energy = 3.0 if on else 0.0
		_beacon_mat.emission_energy_multiplier = 4.0 if on else 0.3


## A few torn plates drifting around the hulk.
func _add_debris(h: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = h
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.2, 0.19)
	mat.metallic = 0.6
	mat.roughness = 0.7
	var r := size()
	for i in rng.randi_range(5, 9):
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(rng.randf_range(1.0, 4.0), rng.randf_range(0.2, 0.8), rng.randf_range(1.0, 5.0)) * (r / 30.0)
		mi.mesh = b
		mi.material_override = mat
		var a := rng.randf() * TAU
		mi.position = Vector3(cos(a), rng.randf_range(-0.4, 0.4), sin(a)) * r * rng.randf_range(0.6, 1.4)
		mi.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		add_child(mi)

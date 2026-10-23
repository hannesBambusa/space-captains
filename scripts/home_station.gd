class_name HomeStation
extends Node3D
## Home station at the sector origin. Instances the Blender glb at runtime so the
## scene still loads when the file is missing, then falls back to a placeholder.

const STATION_PATH := "res://assets/models/station/station_home.glb"
const RING_NODE := "station_ring"

## Whole-station yaw speed in degrees per second. 0: the core, docks and
## solar arms stay still, so corridors to the station complex
## (CorridorNetwork) stay attached to the core.
@export var station_spin_deg: float = 0.0
## Habitat ring yaw speed in degrees per second, on top of the station spin.
@export var ring_spin_deg: float = 3.0

var _model: Node3D
var _ring: Node3D


func _ready() -> void:
	_model = _load_model()
	add_child(_model)
	_ring = _model.find_child(RING_NODE, true, false) as Node3D


## The instanced model (glb or placeholder).
func get_model() -> Node3D:
	return _model


## The spinning habitat ring inside the model, or null.
func get_ring() -> Node3D:
	return _ring


func _process(delta: float) -> void:
	if _model and station_spin_deg != 0.0:
		_model.rotate_y(deg_to_rad(station_spin_deg) * delta)
	if _ring:
		_ring.rotate_y(deg_to_rad(ring_spin_deg) * delta)


func _load_model() -> Node3D:
	if ResourceLoader.exists(STATION_PATH):
		var packed := load(STATION_PATH) as PackedScene
		if packed:
			var inst := packed.instantiate() as Node3D
			if inst:
				ModelLoader.dim_emission(inst)
				return inst
	print("HomeStation: %s not found, using placeholder" % STATION_PATH)
	return _build_placeholder()


func _build_placeholder() -> Node3D:
	var root := Node3D.new()
	root.name = "station_placeholder"
	var hull := StandardMaterial3D.new()
	hull.albedo_color = Color(0.6, 0.62, 0.66)
	hull.metallic = 0.4
	hull.roughness = 0.5
	var lights := StandardMaterial3D.new()
	lights.albedo_color = Color(1.0, 0.75, 0.4)
	lights.emission_enabled = true
	lights.emission = Color(1.0, 0.7, 0.35)
	lights.emission_energy_multiplier = 4.0

	var core := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 12.0
	cyl.bottom_radius = 14.0
	cyl.height = 36.0
	cyl.material = hull
	core.mesh = cyl
	root.add_child(core)

	var ring := MeshInstance3D.new()
	ring.name = RING_NODE
	var torus := TorusMesh.new()
	torus.inner_radius = 34.0
	torus.outer_radius = 40.0
	torus.rings = 64
	torus.material = hull
	ring.mesh = torus
	root.add_child(ring)

	var band := MeshInstance3D.new()
	var band_mesh := TorusMesh.new()
	band_mesh.inner_radius = 14.0
	band_mesh.outer_radius = 15.0
	band_mesh.material = lights
	band.mesh = band_mesh
	band.position.y = 6.0
	root.add_child(band)
	return root

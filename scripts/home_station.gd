class_name HomeStation
extends Node3D
## A station: the class for every station, the home one and forward ones
## (SolarSystem.add_station; the name stays from when home was the only one).
## Instances the Blender glb at runtime ([member model_path]) so the scene
## still loads when the file is missing: then [member fallback_path] scaled
## by [member fallback_scale], then a placeholder. Set the fields before it
## enters the tree.

const STATION_PATH := "res://assets/models/station/station_home.glb"
const FORWARD_PATH := "res://assets/models/station/station_forward.glb"
const RING_NODE := "station_ring"
## Docking pad empties "dock_pad_1", "dock_pad_2" in the model, or these
## (station space; the arms point at 15 and 195 degrees in Blender).
const DOCK_PAD_NODE := "dock_pad_%d"
const DOCK_PAD_FALLBACK: Array[Vector3] = [Vector3(55.5, 0.0, -14.9), Vector3(-55.5, 0.0, 14.9)]

## Whole-station yaw speed in degrees per second. 0: the core, docks and
## solar arms stay still, so the addon bays, docking pads (cargo shuttles)
## and keep-outs (StationKeepouts) keep their place.
@export var station_spin_deg: float = 0.0
## Habitat ring yaw speed in degrees per second, on top of the station spin.
@export var ring_spin_deg: float = 3.0

## Station model (glb); [member fallback_path] while it does not load.
var model_path: String = STATION_PATH
## Model used when [member model_path] does not load, scaled by
## [member fallback_scale] (and so are its pads and bays). "" = placeholder.
var fallback_path: String = ""
var fallback_scale: float = 1.0
## Addon bays on the core ("addon_bay_1".., BuildingManager) and docking
## pads ("dock_pad_1".., CargoShuttle).
var bay_count: int = 6
var dock_pad_count: int = 2
## Keep-out radius cargo shuttles route round the hub, m.
var hub_clearance: float = 120.0
## Display name ("Home Station" or the forward station's name).
var station_name: String = "Home Station"
## Keep-outs and edges for the BuildingManager ([method apply_forward_profile]);
## < 0 or empty = the manager's own (home's) values.
var structure_clearance: float = -1.0
var edge_radius: float = -1.0
var hull_radius: float = -1.0
var solar_wing_dirs: PackedVector3Array = PackedVector3Array()
var solar_wing_span: Vector2 = Vector2.ZERO
var solar_wing_half_width: float = -1.0
## Pad distance from the centre when the model has no "dock_pad_N"
## empties, m; 0 = [constant DOCK_PAD_FALLBACK] as is.
var dock_pad_radius: float = 0.0

var _model: Node3D
var _ring: Node3D


func _ready() -> void:
	_model = _load_model()
	add_child(_model)
	_ring = _model.find_child(RING_NODE, true, false) as Node3D


## The instanced model (glb or placeholder).
func get_model() -> Node3D:
	return _model


## Station-space position of docking pad [param index] (0 ..
## [member dock_pad_count] - 1).
func dock_pad(index: int) -> Vector3:
	var n := _model.find_child(DOCK_PAD_NODE % (index + 1), true, false) as Node3D if _model else null
	if n:
		return ModelLoader.relative_transform(self, n).origin
	var s := _model.scale.x if _model else 1.0
	var p := DOCK_PAD_FALLBACK[clampi(index, 0, DOCK_PAD_FALLBACK.size() - 1)]
	if dock_pad_radius > 0.0:
		p = p.normalized() * dock_pad_radius
	return p * s


## The forward station's layout (station_forward.glb: hub ring r ~25, bay
## collars r 30, pads r 40, solar tips r ~60 at -60 / 120 degrees). Also
## fits the home model scaled ~0.65 (the fallback). Before _ready.
func apply_forward_profile() -> void:
	bay_count = 2
	dock_pad_count = 2
	hub_clearance = 85.0
	structure_clearance = 80.0
	edge_radius = 75.0
	hull_radius = 28.0
	solar_wing_dirs = PackedVector3Array([Vector3(0.5, 0.0, -0.866), Vector3(-0.5, 0.0, 0.866)])
	solar_wing_span = Vector2(26.0, 62.0)
	solar_wing_half_width = 10.0
	dock_pad_radius = 40.0


## The spinning habitat ring inside the model, or null.
func get_ring() -> Node3D:
	return _ring


func _process(delta: float) -> void:
	if _model and station_spin_deg != 0.0:
		_model.rotate_y(deg_to_rad(station_spin_deg) * delta)
	if _ring:
		_ring.rotate_y(deg_to_rad(ring_spin_deg) * delta)


func _load_model() -> Node3D:
	var m := ModelLoader.instantiate(model_path, func() -> Node3D:
		var f := ModelLoader.instantiate(fallback_path, func() -> Node3D:
			print("HomeStation: %s not found, using placeholder" % model_path)
			return _build_placeholder())
		if f.name != "station_placeholder":
			f.scale = Vector3.ONE * fallback_scale
		return f)
	if m.name != "station_placeholder":
		ModelLoader.dim_emission(m)
	return m


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

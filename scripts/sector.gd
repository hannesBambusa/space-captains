@tool
extends Node3D
## Sector root. Keeps the visible sun, the sun light and the planet/moon
## terminators consistent. Previewed in the editor.
##
## The visible sun sits below the play plane (in space there is no horizon, and a
## 50-60 degree RTS camera cannot see above it). Its azimuth drives the light
## direction; the light itself comes from [member light_elevation_deg] above the
## plane so the play area is lit from the top of the screen. Planet and moon use
## the true direction toward the visible sun, so their phase matches what you see.

## Sun bearing in degrees: 0 = straight ahead (-Z) at default yaw, + = to the right (+X).
@export_range(-180.0, 180.0, 0.5) var sun_azimuth_deg: float = -24.0:
	set(v):
		sun_azimuth_deg = v
		_update_sun()
## Elevation of the visible sun, degrees. Negative = below the play plane.
@export_range(-89.0, 89.0, 0.5) var sun_elevation_deg: float = -30.5:
	set(v):
		sun_elevation_deg = v
		_update_sun()
@export var sun_distance: float = 32000.0:
	set(v):
		sun_distance = v
		_update_sun()
@export var sun_radius: float = 650.0:
	set(v):
		sun_radius = v
		_update_sun()
## Elevation the sun light shines down from, degrees above the plane.
@export_range(5.0, 89.0, 0.5) var light_elevation_deg: float = 52.0:
	set(v):
		light_elevation_deg = v
		_update_sun()
## Bearing of the cool fill light relative to the sun.
@export_range(-180.0, 180.0, 0.5) var fill_azimuth_offset_deg: float = 150.0:
	set(v):
		fill_azimuth_offset_deg = v
		_update_sun()
@export_range(0.0, 89.0, 0.5) var fill_elevation_deg: float = 35.0:
	set(v):
		fill_elevation_deg = v
		_update_sun()

## Bodies whose ShaderMaterials get a "sun_direction" uniform toward the visible sun.
@export var lit_bodies: Array[NodePath] = [
	^"Planet/Surface", ^"Planet/Atmosphere", ^"Moon",
]


func _ready() -> void:
	_update_sun()


func _bearing(azimuth_deg: float, elevation_deg: float) -> Vector3:
	var az := deg_to_rad(azimuth_deg)
	var el := deg_to_rad(elevation_deg)
	return Vector3(cos(el) * sin(az), sin(el), -cos(el) * cos(az))


func _update_sun() -> void:
	if not is_inside_tree():
		return
	var sun_dir := _bearing(sun_azimuth_deg, sun_elevation_deg)
	var sun_pos := sun_dir * sun_distance

	var visual := get_node_or_null(^"SunVisual") as Node3D
	if visual:
		visual.position = sun_pos
		visual.scale = Vector3.ONE * sun_radius

	var light := get_node_or_null(^"SunLight") as DirectionalLight3D
	if light:
		var toward_light := _bearing(sun_azimuth_deg, light_elevation_deg)
		light.basis = Basis.looking_at(-toward_light, Vector3.UP)

	var fill := get_node_or_null(^"FillLight") as DirectionalLight3D
	if fill:
		var toward_fill := _bearing(sun_azimuth_deg + fill_azimuth_offset_deg, fill_elevation_deg)
		fill.basis = Basis.looking_at(-toward_fill, Vector3.UP)

	for path in lit_bodies:
		var body := get_node_or_null(path) as GeometryInstance3D
		if body == null:
			continue
		var mat: Material = body.material_override
		if mat == null and body is MeshInstance3D and (body as MeshInstance3D).mesh:
			mat = (body as MeshInstance3D).mesh.surface_get_material(0)
		if mat is ShaderMaterial:
			(mat as ShaderMaterial).set_shader_parameter("sun_direction",
					(sun_pos - body.global_position).normalized())

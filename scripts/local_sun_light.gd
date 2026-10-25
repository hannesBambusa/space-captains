class_name LocalSunLight
extends DirectionalLight3D
## Shadow-casting stand-in for the star near the camera. Points from the star
## toward the camera pivot, lights only layer 2 (station, gates; the star's
## OmniLight3D skips that layer) and scales its shadow range with zoom.
## Shadows switch off when zoomed out past [member shadow_off_distance].

@export var star_position: Vector3 = Vector3.ZERO
## Shadow max distance = camera distance * this, clamped.
@export var shadow_range_factor: float = 1.8
@export var shadow_range_min: float = 300.0
@export var shadow_range_max: float = 6000.0
@export var shadow_off_distance: float = 9000.0


func _ready() -> void:
	light_cull_mask = 2
	shadow_caster_mask = 2
	sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	var cam := RTSCamera.of(get_tree())
	if cam and cam.has_signal("view_changed"):
		cam.view_changed.connect(_on_view_changed)


func _on_view_changed(pivot: Vector3, distance: float, _yaw_deg: float) -> void:
	var dir := pivot - star_position
	if dir.length_squared() < 1.0:
		dir = Vector3(0.0, -1.0, 0.001)
	dir = dir.normalized()
	if absf(dir.y) < 0.999:
		basis = Basis.looking_at(dir, Vector3.UP)
	shadow_enabled = distance < shadow_off_distance
	directional_shadow_max_distance = clampf(distance * shadow_range_factor, shadow_range_min, shadow_range_max)

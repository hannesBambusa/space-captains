class_name MenuBackdrop
extends Node3D
## Main menu background: the Home Station turning slowly in front of its
## planet, lit by a far sun, under the system sky. Cheap: one station model,
## one planet, one light, no simulation.

## The system the backdrop borrows its station planet and sky from.
@export var system_def: SystemDef
## Station turn speed, degrees per second.
@export var spin_deg: float = 2.0
## Slow camera drift around the station, degrees per second.
@export var drift_deg: float = 0.6
@export var camera_distance: float = 210.0
@export var camera_height: float = 42.0

var _pivot: Node3D
var _camera: Camera3D
var _angle := 0.0


func _ready() -> void:
	var sun_dir := Vector3(0.75, 0.25, 0.45).normalized()
	var star_color := system_def.get_star_color() if system_def else Color(1.0, 0.92, 0.8)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = star_color.lerp(Color.WHITE, 0.35)
	sun.light_energy = system_def.light_energy if system_def else 1.4
	sun.shadow_enabled = true
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, -sun_dir, Vector3.UP)

	_pivot = Node3D.new()
	_pivot.name = "StationPivot"
	add_child(_pivot)
	var station := HomeStation.new()
	station.name = "Station"
	_pivot.add_child(station)

	if system_def:
		var pdef := _station_planet()
		if pdef:
			var planet := PlanetBody.new()
			add_child(planet)
			planet.build(pdef, sun_dir * 60000.0, star_color)
			planet.position = Vector3(-900.0, -380.0, -1700.0)
		_apply_sky(system_def.sky_seed)

	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = 50.0
	_camera.far = 100000.0
	add_child(_camera)
	_camera.make_current()
	_place_camera()


func _process(delta: float) -> void:
	_pivot.rotate_y(deg_to_rad(spin_deg) * delta)
	_angle += deg_to_rad(drift_deg) * delta
	_place_camera()


func _place_camera() -> void:
	var a := deg_to_rad(-35.0) + _angle
	var pos := Vector3(sin(a), 0.0, cos(a)) * camera_distance + Vector3.UP * camera_height
	# Look a little to the left of the station so it sits right of the menu.
	var right := Vector3(cos(a), 0.0, -sin(a))
	_camera.look_at_from_position(pos, -right * 55.0 + Vector3.UP * 6.0, Vector3.UP)


func _station_planet() -> PlanetDef:
	for p in system_def.planets:
		if p.name == system_def.station_planet:
			return p
	return system_def.planets[0] if not system_def.planets.is_empty() else null


func _apply_sky(seed_value: float) -> void:
	var env := get_viewport().find_world_3d().environment if get_viewport() else null
	if env and env.sky and env.sky.sky_material is ShaderMaterial:
		(env.sky.sky_material as ShaderMaterial).set_shader_parameter("noise_seed", seed_value)

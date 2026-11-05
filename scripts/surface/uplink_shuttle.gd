class_name UplinkShuttle
extends Node3D
## A planet outpost's flight seen in the station's system (planet outposts
## plan), visual only:
## - a lift ([method setup]): a cargo shuttle climbs out of the planet's
##   atmosphere, glides to the station and settles on a docking pad. The
##   goods are delivered by the outpost's lift timer (Outposts._shuttles), so
##   a lift missed on screen still lands.
## - the founding lander ([method setup_lander]): a dropship lifts off a
##   docking pad, glides to the planet and drops into its atmosphere. The
##   outpost is founded by its timer (Outposts._common_step).
## Both follow the moving planet and station every frame. [param elapsed]
## starts a flight part way through (a lander shown again after a load or a
## view switch).

const LANDER_MODEL := "res://assets/models/ships/dropship.glb"
## Height over the pad where the glide ends and the vertical settle starts, m.
const PAD_APPROACH := 45.0
## Resting height over the pad's origin, m.
const PAD_REST := 4.0
## Share of the flight spent in the atmosphere / on the pad leg.
const ATMO_SHARE := 0.2
const PAD_SHARE := 0.12

var _planet: Node3D
## The station (a HomeStation has docking pads; anything else: its centre).
var _station: Node3D
var _pad := 0
var _time := 70.0
var _t := 0.0
var _radius := 400.0
var _down := false
var _model_path := CargoShuttle.MODEL_PATH


## A lift from [param planet] up to [param station]'s pad [param pad].
func setup(planet: PlanetBody, station: Node3D, seconds: float, pad: int = 0) -> void:
	_init_flight(planet, station, seconds, pad, 0.0)
	name = "UplinkShuttle"


## The founding lander from [param station]'s pad [param pad] down to [param planet].
func setup_lander(planet: PlanetBody, station: Node3D, seconds: float, elapsed: float = 0.0, pad: int = 0) -> void:
	_init_flight(planet, station, seconds, pad, elapsed)
	_down = true
	_model_path = LANDER_MODEL
	name = "OutpostLander"


func _init_flight(planet: PlanetBody, station: Node3D, seconds: float, pad: int, elapsed: float) -> void:
	_planet = planet
	_station = station
	_pad = pad
	_time = maxf(seconds, 5.0)
	_t = clampf(elapsed / _time, 0.0, 0.99)
	_radius = planet.def.radius if planet.def else 400.0


func _ready() -> void:
	var m := ModelLoader.instantiate(_model_path, func() -> Node3D:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(4.0, 2.0, 7.0)
		mi.mesh = box
		return mi)
	add_child(m)
	MeshUtil.set_layers_recursive(m, Ship.RENDER_LAYER)
	_place()


func _process(delta: float) -> void:
	if SimClock.paused:
		return
	_t += delta * SimClock.speed / _time
	if _t >= 1.0 or not is_instance_valid(_planet) or not is_instance_valid(_station):
		queue_free()
		return
	_place()


## Position along the flight at [param u] (0 at the planet, 1 on the pad):
## out of the atmosphere, the glide with an arc, then down onto the pad.
func _path(u: float) -> Vector3:
	var a := _planet.global_position
	# SolarSystem.home_station is the orbiter; the HomeStation is its "Station" child.
	var hs := _station as HomeStation
	if hs == null:
		hs = _station.get_node_or_null(^"Station") as HomeStation
	var pad := hs.to_global(hs.dock_pad(_pad % maxi(hs.dock_pad_count, 1))) if hs else _station.global_position
	var over := pad + Vector3.UP * PAD_APPROACH
	var dir := (over - a).normalized() if over.distance_to(a) > 1.0 else Vector3.FORWARD
	var start := a + dir * _radius * 1.15
	if u < ATMO_SHARE:
		return a.lerp(start, smoothstep(0.0, 1.0, u / ATMO_SHARE))
	if u < 1.0 - PAD_SHARE:
		var k := smoothstep(0.0, 1.0, (u - ATMO_SHARE) / (1.0 - ATMO_SHARE - PAD_SHARE))
		return start.lerp(over, k) + Vector3.UP * sin(k * PI) * 400.0
	var k2 := smoothstep(0.0, 1.0, (u - 1.0 + PAD_SHARE) / PAD_SHARE)
	return over.lerp(pad + Vector3.UP * PAD_REST, k2)


func _place() -> void:
	if not is_instance_valid(_planet) or not is_instance_valid(_station):
		return
	var u := 1.0 - _t if _down else _t
	var p := _path(u)
	var prev := global_position
	global_position = p
	var step := p - prev
	# Aim 10 m ahead: far from the origin a tiny step rounds to nothing. On
	# the vertical pad leg there is no flat step: it keeps its heading.
	if step.length() > 0.01 and Vector2(step.x, step.z).length() > 0.05 * step.length():
		look_at(p + step.normalized() * 10.0, Vector3.UP)

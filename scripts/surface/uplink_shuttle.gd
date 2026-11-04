class_name UplinkShuttle
extends Node3D
## A planet outpost's cargo shuttle seen in the station's system (planet
## outposts plan): it climbs out of the planet's atmosphere and glides to
## the station over the lift time, then is gone. Visual only: the goods are
## delivered by the outpost's lift timer (Outposts._shuttles), so a lift
## missed on screen still lands.

var _from: Node3D
var _to: Node3D
var _time := 70.0
var _t := 0.0
var _radius := 400.0


func setup(planet: PlanetBody, station: Node3D, seconds: float) -> void:
	_from = planet
	_to = station
	_time = maxf(seconds, 5.0)
	_radius = planet.def.radius if planet.def else 400.0
	name = "UplinkShuttle"


func _ready() -> void:
	var m := ModelLoader.instantiate(CargoShuttle.MODEL_PATH, func() -> Node3D:
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
	if _t >= 1.0 or not is_instance_valid(_from) or not is_instance_valid(_to):
		queue_free()
		return
	_place()


func _place() -> void:
	if not is_instance_valid(_from) or not is_instance_valid(_to):
		return
	var a := _from.global_position
	var b := _to.global_position
	var dir := (b - a).normalized() if b.distance_to(a) > 1.0 else Vector3.FORWARD
	# Out of the atmosphere first (the first fifth), then the glide.
	var start := a + dir * _radius * 1.15
	var p: Vector3
	if _t < 0.2:
		p = a.lerp(start, smoothstep(0.0, 1.0, _t / 0.2))
	else:
		var k := smoothstep(0.0, 1.0, (_t - 0.2) / 0.8)
		p = start.lerp(b, k) + Vector3.UP * sin(k * PI) * 400.0
	var prev := global_position
	global_position = p
	var step := p - prev
	# Aim 10 m ahead: far from the origin a tiny step rounds to nothing.
	if step.length() > 0.01 and Vector2(step.x, step.z).length() > 0.05 * step.length():
		look_at(p + step.normalized() * 10.0, Vector3.UP)

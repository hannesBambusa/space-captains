class_name RaidDropship
extends Node3D
## A ground raid's dropship on a live surface (planet outposts plan), visual
## only: it comes in from the zone edge, sets down at the drop point exactly
## when the raid lands (the tanks are spawned by Outposts._raid_clock ->
## SurfaceWorld.spawn_raid at that time), waits while they roll out, then
## lifts off and leaves. Timed on sim time, so pausing and sim speed hold,
## and a dropship made part way through (entering the surface during the
## descent) starts where it would be.

const MODEL := "res://assets/models/ships/dropship.glb"
## Model length on the surface, m (carries up to three tanks).
const LENGTH := 44.0
## Sim seconds from first sight to touchdown.
const DESCENT := 14.0
const HOVER_AT := 3.0
const GROUND_WAIT := 5.0
const LIFT := 3.5
const LEAVE := 10.0

var _land := Vector3.ZERO
var _dir := Vector3.FORWARD
var _land_time := 0.0
var _engine: OmniLight3D


## Sets down at [param land] at sim time [param land_time], coming in along
## the flat direction [param from_dir] (from the zone edge inward).
func setup(land: Vector3, land_time: float, from_dir: Vector3) -> void:
	_land = land
	_land_time = land_time
	var d := Vector3(from_dir.x, 0.0, from_dir.z)
	_dir = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
	name = "RaidDropship"


func _ready() -> void:
	var m := ModelLoader.instantiate(MODEL, func() -> Node3D:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(14.0, 7.0, LENGTH)
		mi.mesh = box
		return mi)
	add_child(m)
	var box := _aabb(m)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	if longest > 0.01:
		m.scale = Vector3.ONE * LENGTH / longest
	_engine = OmniLight3D.new()
	_engine.light_color = Color(1.0, 0.55, 0.25)
	_engine.omni_range = 70.0
	_engine.position = Vector3(0.0, -4.0, 0.0)
	add_child(_engine)
	_place()


func _process(_delta: float) -> void:
	if SimClock.time >= _land_time + GROUND_WAIT + LIFT + LEAVE:
		queue_free()
		return
	_place()


## Where the ship is at sim time [param t] (and how hard its engines burn).
func _pose(t: float) -> Array:
	var hover := _land + Vector3.UP * 30.0
	var rest := _land + Vector3.UP * 5.0
	if t < _land_time - HOVER_AT:
		var start := _land - _dir * 1100.0 + Vector3.UP * 650.0
		var k := clampf((t - (_land_time - DESCENT)) / (DESCENT - HOVER_AT), 0.0, 1.0)
		var e := 1.0 - (1.0 - k) * (1.0 - k)
		return [start.lerp(hover, e) + Vector3.UP * sin(k * PI) * 60.0, 1.0 + k * 2.0]
	if t < _land_time:
		var k2 := (t - (_land_time - HOVER_AT)) / HOVER_AT
		return [hover.lerp(rest, smoothstep(0.0, 1.0, k2)), 3.0]
	if t < _land_time + GROUND_WAIT:
		return [rest, 0.6]
	var lift := rest + Vector3.UP * 70.0
	if t < _land_time + GROUND_WAIT + LIFT:
		var k3 := (t - _land_time - GROUND_WAIT) / LIFT
		return [rest.lerp(lift, smoothstep(0.0, 1.0, k3)), 3.0]
	var k4 := clampf((t - _land_time - GROUND_WAIT - LIFT) / LEAVE, 0.0, 1.0)
	var away := lift - _dir * 1400.0 + Vector3.UP * 900.0
	return [lift.lerp(away, k4 * k4), 2.5]


func _place() -> void:
	var p: Array = _pose(SimClock.time)
	position = p[0]
	# Nose along the flight line: in toward the drop point, then turned back
	# out the way it came once the tanks are off.
	var out := SimClock.time >= _land_time + GROUND_WAIT
	look_at(position + (-_dir if out else _dir) * 10.0, Vector3.UP)
	_engine.light_energy = float(p[1])


static func _aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var b := ModelLoader.relative_transform(n, mi) * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out

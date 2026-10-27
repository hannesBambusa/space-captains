class_name ImpactFx
extends Node3D
## Hull hits: a white-hot glint (FlashPool), a spray of thin spark streaks
## bouncing back off the plating and, close up, a few dark metal flecks
## tumbling away. Shield hits: a ShieldRipple on the target's bubble and a
## cold glint. Pooled emitters, reused round-robin; LOD by the hit's size on
## screen (far hits are a glint only). Visual clock (Vfx).

const SPARK_POOL := 20
const FLECK_POOL := 8
## A hit smaller than this on screen (px per metre of hull) shows only the glint.
const SPARK_MIN_PX := 1.2
const FLECK_MIN_PX := 3.5
const GLINT_HOT := Color(3.2, 2.5, 1.7, 1.0)
const GLINT_COLD := Color(1.3, 2.2, 3.4, 1.0)

var flashes: FlashPool
var ripples: ShieldRipple
var hull_hits: int = 0
var shield_hits: int = 0

var _sparks: Array[GPUParticles3D] = []
var _flecks: Array[GPUParticles3D] = []
var _next_spark := 0
var _next_fleck := 0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	var spm := VfxParts.process(65.0, 18.0, 70.0, 6.0)
	spm.color_ramp = VfxParts.ramp([[0.0, Color(1.0, 0.95, 0.85, 1.0)], [0.35, Color(1.0, 0.6, 0.25, 0.9)], [1.0, Color(0.8, 0.25, 0.05, 0.0)]])
	spm.scale_min = 0.5
	spm.scale_max = 1.2
	for i in SPARK_POOL:
		var p := VfxParts.streaks(10, 0.42, spm, 0.11, 1.6)
		add_child(p)
		_sparks.append(p)
	var fpm := VfxParts.process(80.0, 4.0, 16.0, 0.0)
	fpm.scale_min = 0.25
	fpm.scale_max = 0.6
	fpm.color_ramp = VfxParts.ramp([[0.0, Color(1.0, 0.75, 0.5, 1.0)], [0.2, Color(0.5, 0.48, 0.46, 1.0)], [1.0, Color(0.4, 0.4, 0.4, 0.0)]])
	for i in FLECK_POOL:
		var p := VfxParts.chunks(5, 1.4, fpm, 0.25)
		add_child(p)
		_flecks.append(p)


## A round hitting hull at [param pos], flying along [param dir];
## [param px] = screen pixels per metre there.
func hull(pos: Vector3, dir: Vector3, px: float, scale_m: float = 1.0) -> void:
	hull_hits += 1
	flashes.add(pos, 0.9 * scale_m, GLINT_HOT, 0.09, 1.6, Vector3.ZERO, 0.0, 0.8)
	if px < SPARK_MIN_PX:
		return
	var back := -dir.normalized()
	var p := _sparks[_next_spark]
	_next_spark = (_next_spark + 1) % _sparks.size()
	VfxParts.aim(p, pos, back)
	p.speed_scale = Vfx.vis_speed()
	p.restart()
	if px < FLECK_MIN_PX:
		return
	var f := _flecks[_next_fleck]
	_next_fleck = (_next_fleck + 1) % _flecks.size()
	VfxParts.aim(f, pos, back)
	f.speed_scale = Vfx.vis_speed()
	f.restart()


## A round stopped by [param target]'s shield at [param pos].
func shield(pos: Vector3, dir: Vector3, target: Node3D, radius: float) -> void:
	shield_hits += 1
	flashes.add(pos, 0.7, GLINT_COLD, 0.08, 1.4, Vector3.ZERO, 0.0, 0.5)
	ripples.ripple(target, pos - dir.normalized() * 0.5, radius)


## Small generic burst (station shield surface, misc): glint and sparks.
func burst(pos: Vector3, dir: Vector3, px: float) -> void:
	flashes.add(pos, 0.8, GLINT_HOT, 0.08, 1.5)
	if px < SPARK_MIN_PX:
		return
	var p := _sparks[_next_spark]
	_next_spark = (_next_spark + 1) % _sparks.size()
	VfxParts.aim(p, pos, -dir if dir.length_squared() > 1e-6 else Vector3.UP)
	p.speed_scale = Vfx.vis_speed()
	p.restart()


func set_speed(s: float) -> void:
	for p in _sparks:
		p.speed_scale = s
	for p in _flecks:
		p.speed_scale = s

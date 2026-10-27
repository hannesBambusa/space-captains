class_name CombatFx
extends Node3D
## The combat effects of one system, pooled (the parts live in scripts/vfx/):
## muzzle flashes and hit glints (FlashPool, one MultiMesh), hull-hit spark
## streaks and metal flecks (ImpactFx), ship shield ripples (ShieldRipple),
## explosions (ExplosionFx: flash, short fireball, spark streaks, debris,
## gas; big ones add a shock shell and secondary pops) and den death chains.
## Nothing is spawned headless or while this system is not on screen
## (Vfx.live); muzzle flashes, hit sparks and ripples are skipped above
## Vfx.BUSY_SPEED; LOD by the effect's size on screen. Effects run on the
## visual clock (Vfx.vis_dt: sim time capped at 3x, frozen while paused);
## den chains are queued on sim time ([method sim_step]).

const EXPLOSION_POOL := 12
## Muzzle flashes and hits farther than this on screen (metres per pixel) are skipped.
const SMALL_MAX_MPP := 9.0
## A shield ripple needs at least this many pixels per metre.
const RIPPLE_MIN_PX := 0.12
## Ship-sized shields only: bigger targets (dens) spark like hull.
const RIPPLE_MAX_RADIUS := 40.0
const MUZZLE_COLOR := Color(3.4, 2.7, 1.8, 1.0)

var explosions_played: int = 0
var muzzles_played: int = 0
var flashes: FlashPool
var impacts: ImpactFx
var ripples: ShieldRipple

var _booms: Array[ExplosionFx] = []
var _next_boom: int = 0
## Delayed explosions (den death): {at, pos, size}, sim time.
var _queued: Array[Dictionary] = []
## Secondary pops of big explosions: {at, pos, size}, visual time.
var _subs: Array[Dictionary] = []
var _speed := -1.0
var _live := false
var _cam: Camera3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(SimStepper.GROUP)
	top_level = true
	global_transform = Transform3D.IDENTITY
	_rng.randomize()
	if Vfx.headless():
		return
	flashes = FlashPool.new()
	flashes.name = "Flashes"
	add_child(flashes)
	ripples = ShieldRipple.new()
	ripples.name = "ShieldRipples"
	add_child(ripples)
	impacts = ImpactFx.new()
	impacts.name = "Impacts"
	impacts.flashes = flashes
	impacts.ripples = ripples
	add_child(impacts)
	for i in EXPLOSION_POOL:
		var b := ExplosionFx.new()
		b.name = "Explosion%d" % i
		add_child(b)
		_booms.append(b)


func _process(delta: float) -> void:
	if flashes == null:
		if not SimClock.paused:
			sim_step(delta * SimClock.speed)
		return
	_live = Vfx.viewed(self)
	_cam = get_viewport().get_camera_3d()
	var s := Vfx.vis_speed()
	if s != _speed:
		_speed = s
		impacts.set_speed(s)
		for b in _booms:
			b.set_speed(s)
	if not SimClock.paused:
		sim_step(delta * SimClock.speed)
	var vdt := Vfx.vis_dt(delta)
	if vdt <= 0.0:
		return
	for b in _booms:
		b.step(vdt)
	var i := _subs.size() - 1
	while i >= 0:
		var q := _subs[i]
		q["at"] = float(q["at"]) - vdt
		if float(q["at"]) <= 0.0:
			_play(q["pos"], q["size"], false)
			_subs.remove_at(i)
		i -= 1


func sim_step(dt: float) -> void:
	if dt <= 0.0:
		return
	var i := _queued.size() - 1
	while i >= 0:
		var q := _queued[i]
		q["at"] = float(q["at"]) - dt
		if float(q["at"]) <= 0.0:
			explode(q["pos"], q["size"])
			_queued.remove_at(i)
		i -= 1


## Screen metres per pixel at [param pos] (INF headless or without a camera).
func _mpp(pos: Vector3) -> float:
	return Vfx.metres_per_px(_cam, pos) if _cam else INF


func _small_ok(pos: Vector3) -> bool:
	return _live and not Vfx.busy() and _mpp(pos) <= SMALL_MAX_MPP


## A cannon shot leaves [param pos] along [param dir]: a small hot flash
## running a few metres forward (one or two frames long).
func muzzle(pos: Vector3, dir: Vector3, _color: Color) -> void:
	if flashes == null or not _small_ok(pos):
		return
	muzzles_played += 1
	var d := dir.normalized()
	flashes.add(pos + d * 0.4, 0.6, MUZZLE_COLOR, 0.07, 1.3, d, 3.2, 0.9)


## A round lands on [param target] at [param pos], flying along
## [param dir]: a ripple on its shield bubble while the shield holds, else
## hull sparks and flecks.
func hit(pos: Vector3, dir: Vector3, target: Node3D, _color: Color) -> void:
	if flashes == null or not _small_ok(pos):
		return
	var px := 1.0 / _mpp(pos)
	var radius := float(target.call(&"get_hit_radius")) if is_instance_valid(target) and target.has_method(&"get_hit_radius") else 8.0
	var shielded := is_instance_valid(target) and target.has_method(&"shield_fraction") and float(target.call(&"shield_fraction")) > 0.0
	if shielded and radius <= RIPPLE_MAX_RADIUS and px >= RIPPLE_MIN_PX:
		impacts.shield(pos, dir, target, radius)
	elif shielded:
		flashes.add(pos, 0.7, ImpactFx.GLINT_COLD, 0.08, 1.4)
	else:
		impacts.hull(pos, dir, px)


## Small burst of sparks at a hit (station shield surface, misc).
func spark(pos: Vector3, _color: Color) -> void:
	if flashes == null or not _small_ok(pos):
		return
	impacts.burst(pos, Vector3.ZERO, 1.0 / _mpp(pos))


## A missile leaves its rail at [param pos] along [param dir]: a bright
## launch flare thrown back and a puff of sparks (no missile weapon fires yet).
func missile_launch(pos: Vector3, dir: Vector3) -> void:
	if flashes == null or not _small_ok(pos):
		return
	var d := dir.normalized()
	flashes.add(pos, 1.0, Color(3.4, 3.0, 2.4, 1.0), 0.16, 1.8, -d, 4.0, 0.8)
	impacts.burst(pos, d, 1.0 / _mpp(pos))


## An explosion of [param size] metres (a ship ~ 8, a den ~ 40).
func explode(pos: Vector3, size: float = 8.0) -> void:
	Sfx.play_at(&"explosion_big" if size >= 30.0 else &"explosion_small", pos, self)
	explosions_played += 1
	_play(pos, size, true)


func _play(pos: Vector3, size: float, with_pops: bool) -> void:
	if flashes == null or not _live:
		return
	var mpp := _mpp(pos)
	var b := _booms[_next_boom]
	_next_boom = (_next_boom + 1) % _booms.size()
	b.play(pos, size, size / maxf(mpp, 1e-4), flashes)
	if with_pops and size >= ExplosionFx.BIG and size < 60.0 and _subs.size() < 12:
		# Secondary pops: fuel and ammunition going up a beat later.
		for i in 3:
			var off := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.5, 0.5), _rng.randf_range(-1.0, 1.0)) * size * 0.45
			_subs.append({"at": _rng.randf_range(0.12, 0.7), "pos": pos + off, "size": size * _rng.randf_range(0.22, 0.38)})


## A chain of explosions over [param seconds] around [param pos] (dens).
func explode_chain(pos: Vector3, radius: float, count: int, seconds: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in count:
		var off := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.2, 0.5), rng.randf_range(-1.0, 1.0)) * radius
		_queued.append({"at": seconds * float(i) / maxf(float(count - 1), 1.0), "pos": pos + off, "size": rng.randf_range(10.0, 22.0)})
	_queued.append({"at": seconds + 0.2, "pos": pos, "size": radius * 0.9})

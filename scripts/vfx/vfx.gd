class_name Vfx
extends RefCounted
## Shared gates for the visual effects (scripts/vfx/, CombatFx): nothing is
## spawned headless or in a system that is not on screen (each live system
## has its own World3D, only the viewed one renders), small effects are
## skipped at high sim speeds, and effects play on a visual clock that
## follows the sim clock but never runs faster than [constant VIS_SPEED_MAX]
## (an explosion at 24x still reads). Hook helpers are one-liners for the
## gameplay code.

## Above this sim speed muzzle flashes, hit sparks and shield ripples are skipped.
const BUSY_SPEED := 8.0
## Effects run at most this many times real speed.
const VIS_SPEED_MAX := 3.0

static var _headless := -1


static func headless() -> bool:
	if _headless < 0:
		_headless = 1 if DisplayServer.get_name() == "headless" else 0
	return _headless == 1


## True when [param ctx]'s system is the one on screen (or there is no view switch).
static func viewed(ctx: Node) -> bool:
	if ctx == null or not ctx.is_inside_tree():
		return false
	var vm := ViewManager.of(ctx.get_tree())
	if vm == null or vm.viewed == null:
		return true
	var w := SystemWorld.of(ctx)
	return w == null or w == vm.viewed


## Effects are worth spawning in [param ctx]'s system right now.
static func live(ctx: Node) -> bool:
	return not headless() and viewed(ctx)


## Sim fast enough that small, frequent effects are noise (and cost).
static func busy() -> bool:
	return SimClock.speed > BUSY_SPEED


## Visual seconds for a frame of [param delta] real seconds (0 while paused).
static func vis_dt(delta: float) -> float:
	return 0.0 if SimClock.paused else delta * minf(SimClock.speed, VIS_SPEED_MAX)


## Particle speed scale matching [method vis_dt].
static func vis_speed() -> float:
	return 0.0 if SimClock.paused else minf(SimClock.speed, VIS_SPEED_MAX)


## Metres per screen pixel at [param pos] for [param cam] (INF without a camera).
static func metres_per_px(cam: Camera3D, pos: Vector3) -> float:
	if cam == null:
		return INF
	var h := float(cam.get_viewport().get_visible_rect().size.y)
	var d := cam.global_position.distance_to(pos)
	return 2.0 * d * tan(deg_to_rad(cam.fov) * 0.5) / maxf(h, 1.0)


# --- Hooks (single lines at the gameplay call sites) ------------------------------

## A cannon shot leaves [param from] along [param dir] (ProjectilePool.fire).
static func muzzle(ctx: Node, from: Vector3, dir: Vector3, color: Color) -> void:
	var fx := CombatWorld.fx_of(ctx)
	if fx:
		fx.muzzle(from, dir, color)


## A missile leaves its rail (no missile weapon fires yet: ready for one).
static func missile_launch(ctx: Node, from: Vector3, dir: Vector3) -> void:
	var fx := CombatWorld.fx_of(ctx)
	if fx:
		fx.missile_launch(from, dir)

class_name ExplosionFx
extends Node3D
## One pooled explosion (CombatFx owns the pool), grounded vacuum look:
## a white-hot flash that is gone in a blink (FlashPool), a short light, a
## small fireball that cools from white to deep red and dies fast, hot spark
## streaks flying straight out, tumbling hull debris that keeps going, and a
## thin lit gas cloud that spreads and fades over a few seconds. Big ones
## (stations, dens, buildings: size >= [constant BIG]) add a faint shock
## shell (WarpFx ring), more and slower debris, a longer cloud and a few
## secondary pops (queued by CombatFx). LOD: layers drop out by the
## explosion's size on screen. Visual clock (Vfx).

const BIG := 18.0
const LIGHT_COLOR := Color(1.0, 0.62, 0.32)
## Layers by the explosion's radius on screen, pixels.
const PX_FIREBALL := 1.5
const PX_SPARKS := 3.0
const PX_DEBRIS := 5.0
const PX_GAS := 4.0

var active := false
var size := 9.0

var _t := 0.0
var _dur := 0.6
var _light: OmniLight3D
var _fire: GPUParticles3D
var _sparks: GPUParticles3D
var _debris: GPUParticles3D
var _gas: GPUParticles3D


func _ready() -> void:
	visible = false
	_light = OmniLight3D.new()
	_light.light_color = LIGHT_COLOR
	_light.omni_attenuation = 1.8
	_light.shadow_enabled = false
	_light.visible = false
	add_child(_light)
	var fpm := VfxParts.process(180.0, 1.0, 2.0, 2.0)
	fpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	fpm.scale_min = 0.6
	fpm.scale_max = 1.3
	fpm.scale_curve = VfxParts.curve([Vector2(0.0, 0.45), Vector2(0.2, 1.0), Vector2(1.0, 1.35)])
	fpm.color_ramp = VfxParts.ramp([[0.0, Color(1.0, 0.97, 0.88, 1.0)], [0.12, Color(1.0, 0.72, 0.32, 0.95)],
			[0.35, Color(0.85, 0.3, 0.08, 0.6)], [0.7, Color(0.35, 0.08, 0.03, 0.18)], [1.0, Color(0.1, 0.02, 0.01, 0.0)]])
	_fire = VfxParts.glow_puffs(16, 0.75, fpm, Color(2.6, 1.9, 1.3, 1.0))
	add_child(_fire)
	var spm := VfxParts.process(180.0, 1.0, 2.0, 0.0)
	spm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	spm.scale_min = 0.5
	spm.scale_max = 1.3
	spm.color_ramp = VfxParts.ramp([[0.0, Color(1.0, 0.95, 0.8, 1.0)], [0.3, Color(1.0, 0.62, 0.28, 0.9)], [1.0, Color(0.7, 0.2, 0.05, 0.0)]])
	_sparks = VfxParts.streaks(34, 1.0, spm, 0.15, 2.2)
	add_child(_sparks)
	var dpm := VfxParts.process(180.0, 1.0, 2.0, 0.0)
	dpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	dpm.scale_min = 0.4
	dpm.scale_max = 1.6
	dpm.color_ramp = VfxParts.ramp([[0.0, Color(1.0, 0.7, 0.45, 1.0)], [0.08, Color(0.3, 0.29, 0.28, 1.0)], [0.8, Color(0.26, 0.25, 0.25, 1.0)], [1.0, Color(0.22, 0.22, 0.22, 0.0)]])
	_debris = VfxParts.chunks(20, 3.2, dpm, 0.12)
	add_child(_debris)
	var gpm := VfxParts.process(180.0, 1.0, 2.0, 0.6)
	gpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	gpm.scale_min = 0.7
	gpm.scale_max = 1.3
	gpm.scale_curve = VfxParts.curve([Vector2(0.0, 0.5), Vector2(1.0, 2.2)])
	gpm.color_ramp = VfxParts.ramp([[0.0, Color(0.5, 0.45, 0.4, 0.0)], [0.1, Color(0.55, 0.5, 0.46, 0.32)], [0.5, Color(0.5, 0.48, 0.46, 0.14)], [1.0, Color(0.45, 0.45, 0.45, 0.0)]])
	_gas = VfxParts.gas_puffs(10, 3.0, gpm)
	add_child(_gas)


## Starts at [param pos]; [param px] = the explosion's radius on screen in
## pixels (LOD), [param flashes] the shared flash pool.
func play(pos: Vector3, s: float, px: float, flashes: FlashPool) -> void:
	active = true
	size = s
	_t = 0.0
	var big := s >= BIG
	_dur = 0.35 + s * 0.012
	global_position = pos
	visible = true
	# Flash: a white core gone in a blink, a warm halo a little longer.
	flashes.add(pos, s * 0.55, Color(5.0, 4.6, 4.0, 1.0), 0.1 + s * 0.002, 1.6, Vector3.ZERO, 0.0, 1.0)
	flashes.add(pos, s * 1.3, Color(1.4, 0.7, 0.3, 0.5), 0.26 + s * 0.005, 1.25, Vector3.ZERO, 0.0, 0.0)
	_light.visible = true
	_light.omni_range = s * 10.0
	_light.light_energy = 0.0
	var vs := Vfx.vis_speed()
	if px >= PX_FIREBALL:
		_emit(_fire, s * 0.22, s * 0.7, s * 1.9, Vector2.ONE * s * 0.9, vs)
	if px >= PX_SPARKS:
		_emit(_sparks, s * 0.15, s * 5.0, s * 13.0, Vector2(maxf(s * 0.025, 0.12), s * 0.5), vs)
	if px >= PX_DEBRIS:
		var dv := 0.6 if big else 1.0
		_debris.lifetime = 5.0 if big else 3.2
		(_debris.draw_pass_1 as BoxMesh).size = Vector3(0.6, 0.32, 0.9) * maxf(s * (0.08 if big else 0.1), 0.5)
		_emit(_debris, s * 0.25, s * 1.2 * dv, s * 4.5 * dv, Vector2.ZERO, vs)
	if px >= PX_GAS:
		_gas.lifetime = 5.5 if big else 3.0
		_emit(_gas, s * 0.3, s * 0.35, s * 1.1, Vector2.ONE * s * (1.3 if big else 1.0), vs)
	if big:
		WarpFx.flash(self, pos, s * 2.2, Color(1.0, 0.66, 0.4), 0.45 + s * 0.004)


func _emit(p: GPUParticles3D, radius: float, v_min: float, v_max: float, quad: Vector2, vs: float) -> void:
	var pm := p.process_material as ParticleProcessMaterial
	pm.emission_sphere_radius = maxf(radius, 0.1)
	pm.initial_velocity_min = v_min
	pm.initial_velocity_max = v_max
	if quad != Vector2.ZERO and p.draw_pass_1 is QuadMesh:
		(p.draw_pass_1 as QuadMesh).size = quad
	var reach := v_max * p.lifetime + radius + quad.y
	p.visibility_aabb = AABB(-Vector3.ONE * reach, Vector3.ONE * reach * 2.0)
	p.speed_scale = vs
	p.restart()


func step(dt: float) -> void:
	if not active:
		return
	_t += dt
	var k := clampf(_t / _dur, 0.0, 1.0)
	# The light snaps on and falls off with the fireball.
	_light.light_energy = smoothstep(0.0, 0.04, k) * pow(1.0 - k, 2.0) * 7.0 * minf(size / 8.0, 3.0)
	if k >= 1.0:
		_light.visible = false
	if _t > 6.0:
		active = false
		visible = false


func set_speed(s: float) -> void:
	for p in [_fire, _sparks, _debris, _gas]:
		(p as GPUParticles3D).speed_scale = s

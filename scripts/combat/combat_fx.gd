class_name CombatFx
extends Node3D
## Cheap pooled combat effects in world space: hit sparks (small one-shot
## particle bursts) and explosions (a hot flash, a short light, fireball puffs
## and tumbling debris). Everything runs on sim time: particles freeze while
## paused, flashes advance only with the sim clock.

const SPARK_POOL := 24
const EXPLOSION_POOL := 10

var explosions_played: int = 0

var _sparks: Array[GPUParticles3D] = []
var _next_spark: int = 0
var _booms: Array[Dictionary] = []
var _next_boom: int = 0
## Delayed explosions (den death): {at, pos, size}
var _queued: Array[Dictionary] = []
var _flash_mesh: SphereMesh
var _spark_mat: ParticleProcessMaterial
var _was_paused := false


func _ready() -> void:
	add_to_group(SimStepper.GROUP)
	top_level = true
	global_transform = Transform3D.IDENTITY
	_flash_mesh = SphereMesh.new()
	_flash_mesh.radius = 1.0
	_flash_mesh.height = 2.0
	_flash_mesh.radial_segments = 16
	_flash_mesh.rings = 8
	_spark_mat = _make_spark_process()
	for i in SPARK_POOL:
		_sparks.append(_make_sparks())
	for i in EXPLOSION_POOL:
		_booms.append(_make_boom())


func _process(delta: float) -> void:
	var paused := SimClock.paused
	if paused != _was_paused:
		_was_paused = paused
		_set_particle_speed(0.0 if paused else SimClock.speed)
	if not paused:
		sim_step(delta * SimClock.speed)


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
	for b in _booms:
		if not b["active"]:
			continue
		b["t"] = float(b["t"]) + dt
		var t: float = b["t"]
		var dur: float = b["dur"]
		var k := clampf(t / dur, 0.0, 1.0)
		var size: float = b["size"]
		var flash := b["flash"] as MeshInstance3D
		var mat := flash.material_override as StandardMaterial3D
		flash.scale = Vector3.ONE * size * lerpf(0.3, 1.3, sqrt(k))
		mat.albedo_color = Color(Color(1.0, 0.7, 0.4) * lerpf(2.4, 0.1, k), (1.0 - k) * 0.85)
		var light := b["light"] as OmniLight3D
		light.light_energy = lerpf(6.0, 0.0, clampf(k * 1.6, 0.0, 1.0)) * minf(size / 8.0, 3.0)
		if k >= 1.0 and t > dur + 2.5:
			b["active"] = false
			(b["node"] as Node3D).visible = false
		elif k >= 1.0:
			flash.visible = false
			light.visible = false


## Small burst of sparks at a hit.
func spark(pos: Vector3, _color: Color) -> void:
	var p := _sparks[_next_spark]
	_next_spark = (_next_spark + 1) % _sparks.size()
	p.global_position = pos
	p.speed_scale = 0.0 if SimClock.paused else SimClock.speed
	p.restart()


## An explosion of [param size] metres (a ship ~ 8, a den ~ 40).
func explode(pos: Vector3, size: float = 8.0) -> void:
	var b := _booms[_next_boom]
	_next_boom = (_next_boom + 1) % _booms.size()
	var node := b["node"] as Node3D
	node.visible = true
	node.global_position = pos
	b["active"] = true
	b["t"] = 0.0
	b["size"] = size
	b["dur"] = 0.55 + size * 0.02
	var flash := b["flash"] as MeshInstance3D
	flash.visible = true
	var light := b["light"] as OmniLight3D
	light.visible = true
	light.omni_range = size * 9.0
	for key in ["fire", "debris"]:
		var p := b[key] as GPUParticles3D
		p.scale = Vector3.ONE
		(p.process_material as ParticleProcessMaterial).emission_sphere_radius = size * 0.25
		(p.process_material as ParticleProcessMaterial).initial_velocity_min = size * (1.0 if key == "fire" else 2.0)
		(p.process_material as ParticleProcessMaterial).initial_velocity_max = size * (2.4 if key == "fire" else 5.5)
		var q := p.draw_pass_1 as PrimitiveMesh
		if q is QuadMesh:
			(q as QuadMesh).size = Vector2.ONE * size * 0.8
		elif q is BoxMesh:
			(q as BoxMesh).size = Vector3(0.6, 0.35, 0.9) * maxf(size * 0.14, 0.8)
		p.speed_scale = 0.0 if SimClock.paused else SimClock.speed
		p.restart()
	explosions_played += 1


## A chain of explosions over [param seconds] around [param pos] (dens).
func explode_chain(pos: Vector3, radius: float, count: int, seconds: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in count:
		var off := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.2, 0.5), rng.randf_range(-1.0, 1.0)) * radius
		_queued.append({"at": seconds * float(i) / maxf(float(count - 1), 1.0), "pos": pos + off, "size": rng.randf_range(10.0, 22.0)})
	_queued.append({"at": seconds + 0.2, "pos": pos, "size": radius * 0.9})


func _set_particle_speed(s: float) -> void:
	for p in _sparks:
		p.speed_scale = s
	for b in _booms:
		(b["fire"] as GPUParticles3D).speed_scale = s
		(b["debris"] as GPUParticles3D).speed_scale = s


# --- Builders -----------------------------------------------------------------

func _additive(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.disable_receive_shadows = true
	return m


func _make_spark_process() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 10.0
	pm.initial_velocity_max = 34.0
	pm.gravity = Vector3.ZERO
	pm.damping_min = 20.0
	pm.damping_max = 40.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	ramp.set_color(1, Color(1.0, 0.6, 0.3, 0.0))
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	pm.color_ramp = tex
	return pm


func _make_sparks() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 12
	p.lifetime = 0.45
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	p.process_material = _spark_mat
	var quad := QuadMesh.new()
	quad.size = Vector2(1.1, 1.1)
	var qm := _additive(Color(3.0, 2.2, 1.4, 1.0))
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.vertex_color_use_as_albedo = true
	quad.material = qm
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.layers = 2
	add_child(p)
	return p


func _make_boom() -> Dictionary:
	var node := Node3D.new()
	node.name = "Explosion"
	node.visible = false
	add_child(node)
	var flash := MeshInstance3D.new()
	flash.mesh = _flash_mesh
	flash.material_override = _additive(Color(4.0, 3.0, 2.0, 1.0))
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(flash)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.62, 0.32)
	light.omni_attenuation = 1.6
	light.shadow_enabled = false
	node.add_child(light)
	# Fireball puffs.
	var fire := GPUParticles3D.new()
	fire.amount = 18
	fire.lifetime = 1.1
	fire.one_shot = true
	fire.explosiveness = 0.92
	fire.emitting = false
	fire.visibility_aabb = AABB(Vector3(-200, -200, -200), Vector3(400, 400, 400))
	var fpm := ParticleProcessMaterial.new()
	fpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	fpm.direction = Vector3.UP
	fpm.spread = 180.0
	fpm.gravity = Vector3.ZERO
	fpm.damping_min = 6.0
	fpm.damping_max = 12.0
	fpm.scale_min = 0.6
	fpm.scale_max = 1.5
	var fcurve := Curve.new()
	fcurve.add_point(Vector2(0.0, 0.5))
	fcurve.add_point(Vector2(0.25, 1.0))
	fcurve.add_point(Vector2(1.0, 1.25))
	var fct := CurveTexture.new()
	fct.curve = fcurve
	fpm.scale_curve = fct
	var framp := Gradient.new()
	framp.set_color(0, Color(1.0, 0.95, 0.75, 1.0))
	framp.add_point(0.3, Color(1.0, 0.5, 0.18, 0.85))
	framp.set_color(framp.get_point_count() - 1, Color(0.25, 0.2, 0.2, 0.0))
	var ftex := GradientTexture1D.new()
	ftex.gradient = framp
	fpm.color_ramp = ftex
	fire.process_material = fpm
	var fq := QuadMesh.new()
	var fqm := _additive(Color(2.6, 1.8, 1.2, 1.0))
	fqm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fqm.vertex_color_use_as_albedo = true
	fqm.albedo_texture = _soft_dot()
	fq.material = fqm
	fire.draw_pass_1 = fq
	fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fire.layers = 2
	node.add_child(fire)
	# Tumbling debris chunks (lit, dark metal with hot edges).
	var debris := GPUParticles3D.new()
	debris.amount = 22
	debris.lifetime = 3.0
	debris.one_shot = true
	debris.explosiveness = 1.0
	debris.emitting = false
	debris.visibility_aabb = AABB(Vector3(-300, -300, -300), Vector3(600, 600, 600))
	var dpm := ParticleProcessMaterial.new()
	dpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	dpm.direction = Vector3.UP
	dpm.spread = 180.0
	dpm.gravity = Vector3.ZERO
	dpm.damping_min = 1.0
	dpm.damping_max = 3.0
	dpm.angular_velocity_min = -220.0
	dpm.angular_velocity_max = 220.0
	dpm.scale_min = 0.5
	dpm.scale_max = 1.6
	var dramp := Gradient.new()
	dramp.set_color(0, Color(1.0, 0.7, 0.4, 1.0))
	dramp.add_point(0.15, Color(0.5, 0.45, 0.42, 1.0))
	dramp.set_color(dramp.get_point_count() - 1, Color(0.35, 0.33, 0.32, 0.0))
	var dtex := GradientTexture1D.new()
	dtex.gradient = dramp
	dpm.color_ramp = dtex
	debris.process_material = dpm
	var box := BoxMesh.new()
	var bm := StandardMaterial3D.new()
	bm.vertex_color_use_as_albedo = true
	bm.albedo_color = Color(0.7, 0.68, 0.66)
	bm.metallic = 0.6
	bm.roughness = 0.5
	bm.emission_enabled = true
	bm.emission = Color(1.0, 0.45, 0.15)
	bm.emission_energy_multiplier = 0.6
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	box.material = bm
	debris.draw_pass_1 = box
	debris.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	debris.layers = 2
	node.add_child(debris)
	return {"node": node, "flash": flash, "light": light, "fire": fire, "debris": debris, "active": false, "t": 0.0, "dur": 0.6, "size": 8.0}


static var _dot_tex: ImageTexture


static func _soft_dot() -> ImageTexture:
	if _dot_tex:
		return _dot_tex
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a))
	_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex

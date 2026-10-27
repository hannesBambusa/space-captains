class_name VfxParts
extends RefCounted
## Builders for the pooled particle emitters of scripts/vfx/ (sparks,
## debris, fireball and gas puffs). All one-shot GPUParticles3D in world
## space, no shadows, on the ships' render layer; the callers set sizes,
## speeds and restart them.

static var _dot_tex: ImageTexture


## A soft round dot (alpha falls off squared), shared.
static func soft_dot() -> ImageTexture:
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


static func ramp(stops: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in stops:
		offs.append(float(s[0]))
		cols.append(s[1] as Color)
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	for p in points:
		c.add_point(p as Vector2)
	var t := CurveTexture.new()
	t.curve = c
	return t


static func emitter(amount: int, lifetime: float, pm: ParticleProcessMaterial, mesh: Mesh, explosiveness: float = 1.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = explosiveness
	p.randomness = 0.3
	p.emitting = false
	p.local_coords = false
	p.fixed_fps = 0
	p.interpolate = false
	p.process_material = pm
	p.draw_pass_1 = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.layers = Ship.RENDER_LAYER
	p.visibility_aabb = AABB(Vector3(-50, -50, -50), Vector3(100, 100, 100))
	return p


static func process(spread: float, v_min: float, v_max: float, damping: float = 0.0) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 0.0, -1.0)
	pm.spread = spread
	pm.initial_velocity_min = v_min
	pm.initial_velocity_max = v_max
	pm.gravity = Vector3.ZERO
	pm.damping_min = damping * 0.5
	pm.damping_max = damping
	return pm


## Thin hot streaks that stretch along their velocity (a QuadMesh whose
## height is the streak length).
static func streaks(amount: int, lifetime: float, pm: ParticleProcessMaterial, width: float, length: float) -> GPUParticles3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(width, length)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_dot()
	m.albedo_color = Color(3.2, 2.4, 1.6, 1.0)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	quad.material = m
	var p := emitter(amount, lifetime, pm, quad)
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	return p


## Additive camera-facing puffs (fireball).
static func glow_puffs(amount: int, lifetime: float, pm: ParticleProcessMaterial, energy: Color) -> GPUParticles3D:
	var quad := QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_dot()
	m.albedo_color = energy
	m.disable_receive_shadows = true
	quad.material = m
	return emitter(amount, lifetime, pm, quad, 0.95)


## Lit, alpha-blended gas puffs: the sun side of the cloud reads.
static func gas_puffs(amount: int, lifetime: float, pm: ParticleProcessMaterial) -> GPUParticles3D:
	var quad := QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_dot()
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.disable_receive_shadows = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	quad.material = m
	return emitter(amount, lifetime, pm, quad, 0.9)


## Tumbling lit chunks (dark metal, a little heat glow).
static func chunks(amount: int, lifetime: float, pm: ParticleProcessMaterial, heat: float) -> GPUParticles3D:
	var box := BoxMesh.new()
	box.size = Vector3(0.6, 0.3, 0.9)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.62, 0.6, 0.58)
	m.metallic = 0.65
	m.roughness = 0.45
	m.emission_enabled = heat > 0.0
	m.emission = Color(1.0, 0.42, 0.12)
	m.emission_energy_multiplier = heat
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	box.material = m
	pm.angular_velocity_min = -260.0
	pm.angular_velocity_max = 260.0
	pm.particle_flag_rotate_y = true
	return emitter(amount, lifetime, pm, box)


## Orients a node so its local -Z points along [param dir].
static func aim(n: Node3D, pos: Vector3, dir: Vector3) -> void:
	var d := dir.normalized() if dir.length_squared() > 1e-8 else Vector3.FORWARD
	var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
	n.global_transform = Transform3D(Basis.looking_at(d, up), pos)

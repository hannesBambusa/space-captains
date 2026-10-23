class_name PlanetBody
extends Orbiter
## One planet or moon built from a PlanetDef: a tilted, spinning surface sphere
## (shaders/planet.gdshader, look picked by type), an optional atmosphere shell
## and an optional ring. The node itself only orbits; children carry tilt/spin.
## Light comes from the star position, computed per fragment in the shaders.

const PLANET_SHADER: Shader = preload("res://shaders/planet.gdshader")
const ATMO_SHADER: Shader = preload("res://shaders/atmosphere.gdshader")
const RING_SHADER: Shader = preload("res://shaders/planet_ring.gdshader")
const ATMO_INNER_RATIO := 0.966

var def: PlanetDef
var surface: MeshInstance3D
var atmosphere: MeshInstance3D
var ring: MeshInstance3D

var _tilt: Node3D
var _surface_mat: ShaderMaterial


func build(planet_def: PlanetDef, star_position: Vector3, star_color: Color) -> void:
	def = planet_def
	name = StringName(def.name.validate_node_name())

	_tilt = Node3D.new()
	_tilt.name = "Tilt"
	_tilt.rotation = Vector3(0.0, 0.0, deg_to_rad(def.axial_tilt_deg))
	add_child(_tilt)

	surface = MeshInstance3D.new()
	surface.name = "Surface"
	var segs := 192 if def.radius >= 1000.0 else (128 if def.radius >= 250.0 else 64)
	surface.mesh = MeshUtil.unit_sphere(segs)
	surface.scale = Vector3.ONE * def.radius
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_surface_mat = ShaderMaterial.new()
	_surface_mat.shader = PLANET_SHADER
	_surface_mat.set_shader_parameter("use_star_position", true)
	_surface_mat.set_shader_parameter("star_position", star_position)
	_surface_mat.set_shader_parameter("star_color", Color(star_color, 1.0).lerp(Color.WHITE, 0.5))
	_surface_mat.set_shader_parameter("use_anim_time", true)
	_surface_mat.set_shader_parameter("seed", def.seed)
	_surface_mat.set_shader_parameter("tint", def.tint)
	_apply_type(_surface_mat)
	surface.material_override = _surface_mat
	_tilt.add_child(surface)

	if def.atmosphere_color.a > 0.0:
		atmosphere = MeshInstance3D.new()
		atmosphere.name = "Atmosphere"
		atmosphere.mesh = MeshUtil.unit_sphere(segs)
		atmosphere.scale = Vector3.ONE * def.radius / ATMO_INNER_RATIO
		atmosphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var am := ShaderMaterial.new()
		am.shader = ATMO_SHADER
		am.render_priority = 1
		am.set_shader_parameter("use_star_position", true)
		am.set_shader_parameter("star_position", star_position)
		am.set_shader_parameter("inner_ratio", ATMO_INNER_RATIO)
		am.set_shader_parameter("atmosphere_color", Color(def.atmosphere_color, 1.0))
		am.set_shader_parameter("intensity", 1.6 * def.atmosphere_color.a)
		am.set_shader_parameter("sunset_strength", 0.15)
		if def.type == PlanetDef.Type.LAVA:
			am.set_shader_parameter("sunset_color", Color(1.0, 0.35, 0.1))
		atmosphere.material_override = am
		_tilt.add_child(atmosphere)

	if def.has_rings:
		ring = MeshInstance3D.new()
		ring.name = "Ring"
		ring.mesh = MeshUtil.make_annulus(def.ring_inner, def.ring_outer, 256, 1)
		ring.scale = Vector3.ONE * def.radius
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var rm := ShaderMaterial.new()
		rm.shader = RING_SHADER
		rm.render_priority = 2
		rm.set_shader_parameter("star_position", star_position)
		rm.set_shader_parameter("star_color", Color(star_color, 1.0).lerp(Color.WHITE, 0.5))
		rm.set_shader_parameter("inner", def.ring_inner)
		rm.set_shader_parameter("outer", def.ring_outer)
		rm.set_shader_parameter("ring_color", Color(def.ring_color, 1.0))
		rm.set_shader_parameter("ring_color_b", Color(def.ring_color, 1.0).darkened(0.35))
		rm.set_shader_parameter("opacity", def.ring_color.a * 0.9)
		rm.set_shader_parameter("seed", def.seed * 3.7)
		ring.material_override = rm
		_tilt.add_child(ring)
		_surface_mat.set_shader_parameter("ring_shadow", 0.8)
		_surface_mat.set_shader_parameter("ring_inner", def.ring_inner)
		_surface_mat.set_shader_parameter("ring_outer", def.ring_outer)
	setup_orbit(def.orbit_radius, def.orbit_period, def.start_angle_deg)


func update_sim(sim_time: float) -> void:
	super.update_sim(sim_time)
	if surface == null:
		return
	if def.spin_period != 0.0:
		surface.rotation.y = -TAU * fposmod(sim_time / def.spin_period, 1.0)
	_surface_mat.set_shader_parameter("anim_time", sim_time)


## Type look presets. Colours are multiplied by def.tint in the shader.
func _apply_type(m: ShaderMaterial) -> void:
	m.set_shader_parameter("planet_type", int(def.type))
	m.set_shader_parameter("terminator_strength", 0.3)
	var atmo := Color(def.atmosphere_color, 1.0)
	m.set_shader_parameter("rim_color", atmo)
	m.set_shader_parameter("rim_intensity", 0.55 * def.atmosphere_color.a)
	match def.type:
		PlanetDef.Type.OCEAN:
			m.set_shader_parameter("continent_scale", 2.0)
			m.set_shader_parameter("land_low", Color(0.10, 0.19, 0.07))
			m.set_shader_parameter("land_mid", Color(0.27, 0.29, 0.15))
			m.set_shader_parameter("land_high", Color(0.50, 0.42, 0.32))
			m.set_shader_parameter("cloud_amount", 0.5)
			m.set_shader_parameter("cloud_speed", 0.004)
			m.set_shader_parameter("city_intensity", 0.35)
			m.set_shader_parameter("bump_strength", 0.006)
		PlanetDef.Type.ROCKY:
			_palette(m, Color(0.12, 0.11, 0.10), Color(0.30, 0.28, 0.26), Color(0.46, 0.43, 0.40), Color(0.64, 0.62, 0.58))
			m.set_shader_parameter("continent_scale", 2.6)
			m.set_shader_parameter("crater_amount", 1.0)
			m.set_shader_parameter("cloud_amount", 0.0)
			m.set_shader_parameter("city_intensity", 0.0)
			m.set_shader_parameter("ocean_specular", 0.0)
			m.set_shader_parameter("bump_strength", 0.035)
			m.set_shader_parameter("night_ambient", 0.01)
		PlanetDef.Type.DESERT:
			_palette(m, Color(0.24, 0.12, 0.07), Color(0.42, 0.25, 0.14), Color(0.72, 0.48, 0.28), Color(0.88, 0.68, 0.44))
			m.set_shader_parameter("continent_scale", 2.2)
			m.set_shader_parameter("ice_latitude", 0.9)
			m.set_shader_parameter("ice_color", Color(0.92, 0.88, 0.84))
			m.set_shader_parameter("cloud_amount", 0.16)
			m.set_shader_parameter("cloud_scale", 2.5)
			m.set_shader_parameter("cloud_color", Color(0.92, 0.82, 0.68))
			m.set_shader_parameter("city_intensity", 0.0)
			m.set_shader_parameter("ocean_specular", 0.0)
			m.set_shader_parameter("bump_strength", 0.02)
			m.set_shader_parameter("terminator_color", Color(1.0, 0.5, 0.25))
		PlanetDef.Type.ICE:
			_palette(m, Color(0.22, 0.33, 0.45), Color(0.48, 0.60, 0.72), Color(0.68, 0.78, 0.88), Color(0.88, 0.93, 0.98))
			m.set_shader_parameter("pal_accent", Color(0.55, 0.36, 0.26))
			m.set_shader_parameter("continent_scale", 2.4)
			m.set_shader_parameter("cloud_amount", 0.0)
			m.set_shader_parameter("cloud_scale", 3.0)
			m.set_shader_parameter("city_intensity", 0.0)
			m.set_shader_parameter("ocean_specular", 0.45)
			m.set_shader_parameter("bump_strength", 0.012)
			m.set_shader_parameter("sun_intensity", 1.05)
			m.set_shader_parameter("terminator_color", Color(0.7, 0.75, 1.0))
		PlanetDef.Type.LAVA:
			_palette(m, Color(0.06, 0.05, 0.045), Color(0.24, 0.18, 0.15), Color(0.3, 0.25, 0.2), Color(0.4, 0.35, 0.3))
			m.set_shader_parameter("pal_accent", Color(1.0, 0.32, 0.06))
			m.set_shader_parameter("emission_strength", 1.5)
			m.set_shader_parameter("continent_scale", 2.4)
			m.set_shader_parameter("cloud_amount", 0.0)
			m.set_shader_parameter("city_intensity", 0.0)
			m.set_shader_parameter("ocean_specular", 0.0)
			m.set_shader_parameter("bump_strength", 0.025)
		PlanetDef.Type.GAS_GIANT:
			_palette(m, Color(0.52, 0.38, 0.27), Color(0.76, 0.62, 0.47), Color(0.90, 0.84, 0.72), Color(0.97, 0.94, 0.87))
			m.set_shader_parameter("pal_accent", Color(0.78, 0.36, 0.20))
			m.set_shader_parameter("flow_speed", 0.004)
			m.set_shader_parameter("cloud_amount", 0.0)
			m.set_shader_parameter("city_intensity", 0.0)
			m.set_shader_parameter("ocean_specular", 0.0)
			m.set_shader_parameter("sun_intensity", 1.15)


static func _palette(m: ShaderMaterial, a: Color, b: Color, c: Color, d: Color) -> void:
	m.set_shader_parameter("pal_a", a)
	m.set_shader_parameter("pal_b", b)
	m.set_shader_parameter("pal_c", c)
	m.set_shader_parameter("pal_d", d)

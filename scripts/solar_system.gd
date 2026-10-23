class_name SolarSystem
extends Node3D
## Builds a whole star system from a SystemDef and keeps it moving with the sim
## clock (autoload SimClock). Star at the origin. A thick disc: planets orbit
## on inclined planes (moons more), belts are thick rock bands around y = 0,
## gates sit on the plane and dens above or below it (DenDef.height).
##
## Children built at runtime: Star, one PlanetBody per planet (moons and the
## home station orbit inside their planet's node), SystemBelts, JumpGates,
## orbit lines and name labels. Orbit lines and labels fade with camera zoom.

const ORBIT_SHADER: Shader = preload("res://shaders/orbit_line.gdshader")

signal built

const GROUP := "solar_system"

@export var system_def: SystemDef

@export_group("Camera")
## Camera distance when following the home station.
@export var station_view_distance: float = 3000.0
## Yaw offset (degrees) from looking straight at the star in the default view.
@export var default_view_yaw_offset_deg: float = 28.0

@export_group("Zoom fades")
## Planet/belt/gate orbit lines fade in between these camera distances.
@export var orbit_fade_in: Vector2 = Vector2(2600.0, 7000.0)
## Moon orbit lines fade in, then out again far away.
@export var moon_orbit_fade_in: Vector2 = Vector2(2800.0, 6000.0)
@export var moon_orbit_fade_out: Vector2 = Vector2(16000.0, 30000.0)
## Name labels fade in between these camera distances.
@export var label_fade_in: Vector2 = Vector2(5000.0, 9500.0)

var star: Star
var planets: Array[PlanetBody] = []
var belts: Array[SystemBelt] = []
var gates: Array[JumpGate] = []
var dens: Array[ScavengerDen] = []
var home_station: Orbiter
## Per belt (same order as [member belts]): a point on the belt's centre line
## used as its camera focus target (the belt itself is centred on the star).
var belt_anchors: Array[Node3D] = []

var _orbiters: Array[Orbiter] = []
var _labels: Array[Label3D] = []
## Per label: world radius of the body it sits under (keeps the text below the disc).
var _label_radii: PackedFloat32Array = []
var _orbit_mat: ShaderMaterial
var _moon_orbit_mat: ShaderMaterial
var _star_color := Color.WHITE


func _ready() -> void:
	process_priority = -10
	add_to_group(GROUP)
	if system_def == null:
		push_warning("SolarSystem: no system_def set")
		return
	var t0 := Time.get_ticks_msec()
	_build()
	_update_bodies(SimClock.time)
	print("SolarSystem: built '%s' in %d ms" % [system_def.system_name, Time.get_ticks_msec() - t0])
	_configure_camera.call_deferred()
	built.emit()


func _process(_delta: float) -> void:
	_update_bodies(SimClock.time)


## Places every orbiting body and belt for sim time [param t] (fast-forward).
func update_bodies(t: float) -> void:
	_update_bodies(t)


## Finds a built body (planet, moon, station, gate, belt, star) by node name.
func find_body(body_name: String) -> Node3D:
	if star and star.name == body_name:
		return star
	return find_child(body_name, true, false) as Node3D


func get_extent() -> float:
	return system_def.get_extent() if system_def else 0.0


func _update_bodies(t: float) -> void:
	for o in _orbiters:
		o.update_sim(t)
	for b in belts:
		b.update_sim(t)


# --- Build --------------------------------------------------------------------

func _build() -> void:
	var def := system_def
	_star_color = def.get_star_color()
	var extent := def.get_extent()

	_orbit_mat = _make_orbit_material(1.3)
	_moon_orbit_mat = _make_orbit_material(1.2)

	star = Star.new()
	star.name = "Star"
	add_child(star)
	star.build(def.star_radius, _star_color, def.light_energy, extent * 3.0)

	var sun := LocalSunLight.new()
	sun.name = "LocalSunLight"
	sun.light_color = _star_color.lerp(Color.WHITE, 0.35)
	sun.light_energy = def.light_energy
	sun.light_specular = 0.6
	sun.light_angular_distance = 0.5
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.25
	add_child(sun)

	var lines := Node3D.new()
	lines.name = "OrbitLines"
	add_child(lines)

	for pdef in def.planets:
		var body := _add_planet(pdef, self)
		_add_orbit_line(lines, pdef.orbit_radius, _orbit_mat, Color(0.55, 0.72, 1.0, 0.12), body.orbit_basis)
		_add_label(body, pdef.name.to_upper(), pdef.radius * (pdef.ring_outer if pdef.has_rings else 1.0), 1.0)
		for mdef: PlanetDef in pdef.moons:
			var moon := _add_planet(mdef, body)
			_add_orbit_line(body, mdef.orbit_radius, _moon_orbit_mat, Color(0.6, 0.7, 0.9, 0.12), moon.orbit_basis)

	if not def.station_planet.is_empty():
		_add_station(def)

	for bdef in def.belts:
		var belt := SystemBelt.new()
		add_child(belt)
		belt.build(bdef, Vector3.ZERO, _star_color)
		belts.append(belt)
		var label_angle := deg_to_rad(fposmod(float(bdef.seed) * 47.0, 360.0))
		var anchor := Node3D.new()
		anchor.name = "%sLabel" % belt.name
		anchor.position = Vector3(cos(label_angle), 0.0, sin(label_angle)) * (bdef.orbit_radius + bdef.width * 0.5)
		anchor.set_meta(&"focus_radius", bdef.width * 0.5)
		anchor.set_meta(&"focus_distance", bdef.width * 2.4)
		# Clicking the anchor (the belt's label) selects the belt.
		anchor.set_meta(&"belt", belt)
		anchor.add_to_group(RTSCamera.FOCUS_GROUP)
		add_child(anchor)
		belt_anchors.append(anchor)
		var tint := Color(0.85, 0.75, 0.6) if bdef.ore_type != AsteroidBelt.OreType.CRYSTAL else Color(0.55, 0.9, 1.0)
		_add_label(anchor, bdef.name.to_upper(), 0.0, 0.85, tint)

	for gdef in def.gates:
		var gate := JumpGate.new()
		add_child(gate)
		gate.build(gdef)
		gates.append(gate)
		_orbiters.append(gate)
		_add_label(gate, "%s  >  %s" % [gdef.name.to_upper(), gdef.target_system.to_upper()], 150.0, 0.9, Color(0.55, 0.85, 1.0))

	for ddef in def.dens:
		_add_den(ddef)

	_apply_sky_seed(def.sky_seed)


## Places a Scavenger Den next to its belt, mouth turned toward the star.
func _add_den(ddef: DenDef) -> void:
	var belt: SystemBelt = null
	for b in belts:
		if b.def.name == ddef.belt_name:
			belt = b
	var r := (belt.def.orbit_radius if belt else 10000.0) + ddef.radial_offset
	var a := deg_to_rad(ddef.angle_deg)
	var den := ScavengerDen.new()
	den.setup(ddef, belt)
	den.position = Vector3(cos(a), 0.0, sin(a)) * r + Vector3.UP * ddef.height
	var inward := -Vector3(den.position.x, 0.0, den.position.z) * signf(ddef.radial_offset if ddef.radial_offset != 0.0 else 1.0)
	den.rotation.y = atan2(inward.x, inward.z)
	add_child(den)
	dens.append(den)
	_add_label(den, ddef.name.to_upper(), 70.0, 0.8, Color(1.0, 0.45, 0.35))


func _add_planet(pdef: PlanetDef, parent: Node3D) -> PlanetBody:
	var body := PlanetBody.new()
	parent.add_child(body)
	body.build(pdef, Vector3.ZERO, _star_color)
	var is_moon := parent != self
	body.make_focusable(pdef.radius, pdef.radius * (6.0 if is_moon else 4.2))
	_orbiters.append(body)
	if not is_moon:
		planets.append(body)
	return body


func _add_station(def: SystemDef) -> void:
	var host := find_child(def.station_planet.validate_node_name(), false, false) as PlanetBody
	if host == null:
		push_warning("SolarSystem: station planet '%s' not found" % def.station_planet)
		return
	home_station = Orbiter.new()
	home_station.name = "HomeStation"
	host.add_child(home_station)
	home_station.setup_orbit(def.station_orbit_radius, def.station_orbit_period, def.station_start_angle_deg)
	home_station.make_focusable(60.0, 420.0)
	_orbiters.append(home_station)
	_add_orbit_line(host, def.station_orbit_radius, _moon_orbit_mat, Color(1.0, 0.78, 0.5, 0.12))

	var station := HomeStation.new()
	station.name = "Station"
	home_station.add_child(station)
	MeshUtil.set_layers_recursive(station, 2)
	var core := OmniLight3D.new()
	core.name = "CoreLight"
	core.position = Vector3(0.0, 40.0, 0.0)
	core.light_color = Color(1.0, 0.78, 0.5)
	core.light_energy = 3.0
	core.omni_range = 150.0
	core.omni_attenuation = 1.4
	core.light_cull_mask = 2
	home_station.add_child(core)
	var dock := OmniLight3D.new()
	dock.name = "DockLight"
	# Over the first docking pad (read from the station model when it has one).
	dock.position = station.transform * station.dock_pad(0) + Vector3(0.0, 12.0, 0.0)
	dock.light_color = Color(1.0, 0.7, 0.42)
	dock.light_energy = 2.0
	dock.omni_range = 90.0
	dock.omni_attenuation = 1.6
	dock.light_cull_mask = 2
	home_station.add_child(dock)


func _make_orbit_material(px: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ORBIT_SHADER
	m.set_shader_parameter("line_px", px)
	m.set_shader_parameter("opacity", 0.0)
	return m


func _add_orbit_line(parent: Node3D, radius: float, mat: ShaderMaterial, color: Color, plane: Basis = Basis.IDENTITY) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Orbit"
	mi.basis = plane
	mi.mesh = MeshUtil.make_orbit_strip(radius, clampi(int(radius / 25.0), 128, 1024))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("line_color", color)
	parent.add_child(mi)


func _add_label(parent: Node3D, text: String, body_radius: float, size_scale: float, tint: Color = Color(0.82, 0.88, 1.0)) -> void:
	var l := Label3D.new()
	l.name = "Label"
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.00042 * size_scale
	l.font_size = 30
	l.outline_size = 10
	l.outline_modulate = Color(0.0, 0.0, 0.0, 0.0)
	l.modulate = Color(tint, 0.0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.no_depth_test = true
	l.shaded = false
	l.double_sided = true
	l.render_priority = 10
	l.outline_render_priority = 9
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.visible = false
	parent.add_child(l)
	_labels.append(l)
	_label_radii.append(body_radius)


func _apply_sky_seed(seed_value: float) -> void:
	var env := get_viewport().find_world_3d().environment if get_viewport() else null
	if env and env.sky and env.sky.sky_material is ShaderMaterial:
		(env.sky.sky_material as ShaderMaterial).set_shader_parameter("noise_seed", seed_value)


# --- Camera and zoom fades ----------------------------------------------------

func _configure_camera() -> void:
	var cam := get_tree().get_first_node_in_group("rts_camera") as RTSCamera
	if cam == null:
		return
	var extent := get_extent()
	cam.bounds_radius = extent
	cam.far_extent = extent * 2.6
	cam.home_target = home_station
	cam.default_distance = station_view_distance
	if home_station:
		var to_star := -home_station.global_position
		to_star.y = 0.0
		var yaw := atan2(-to_star.x, -to_star.z)
		cam.default_yaw_deg = rad_to_deg(yaw) + default_view_yaw_offset_deg
	cam.view_changed.connect(_on_view_changed)
	cam.reset_view(true)


func _on_view_changed(_pivot: Vector3, distance: float, _yaw_deg: float) -> void:
	var a := smoothstep(orbit_fade_in.x, orbit_fade_in.y, distance)
	_orbit_mat.set_shader_parameter("opacity", a)
	var m := smoothstep(moon_orbit_fade_in.x, moon_orbit_fade_in.y, distance) \
			* (1.0 - smoothstep(moon_orbit_fade_out.x, moon_orbit_fade_out.y, distance))
	_moon_orbit_mat.set_shader_parameter("opacity", m)
	var la := smoothstep(label_fade_in.x, label_fade_in.y, distance)
	var cam := get_viewport().get_camera_3d()
	var px_per_rad := 1.0
	if cam:
		px_per_rad = get_viewport().get_visible_rect().size.y / (2.0 * tan(deg_to_rad(cam.fov) * 0.5))
	var px_per_m := px_per_rad / maxf(distance, 1.0)
	for i in _labels.size():
		var l := _labels[i]
		l.visible = la > 0.01
		if not l.visible:
			continue
		l.modulate.a = la
		l.outline_modulate.a = la * 0.7
		# A fixed-size Label3D maps one font pixel to pixel_size * px_per_rad screen pixels.
		var below_px := _label_radii[i] * px_per_m + 8.0
		l.offset = Vector2(0.0, -below_px / (l.pixel_size * px_per_rad))

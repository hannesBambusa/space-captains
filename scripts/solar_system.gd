class_name SolarSystem
extends Node3D
## Builds a whole star system from a SystemDef and keeps it moving with the sim
## clock (autoload SimClock). Star at the origin. A thick disc: planets orbit
## on inclined planes (moons more), asteroid clusters are thick clumps on
## slow inclined orbits, gates sit on the plane and dens above or below it
## (DenDef.height).
##
## Children built at runtime: Star, one PlanetBody per planet (moons and the
## home station orbit inside their planet's node), asteroid clusters
## (AsteroidCluster; the starting set from SystemDef.belts, then ClusterSpawner
## replaces mined-out ones: [method add_cluster], [method remove_cluster]), JumpGates,
## orbit lines and name labels. Orbit lines and labels fade with camera zoom.
## Dens: only those there from the start (DenDef.starts_present) are built
## with the system; the ThreatDirector brings the others in later
## ([method arrive_den]). [member dens] holds the arrived ones only.

const ORBIT_SHADER: Shader = preload("res://shaders/orbit_line.gdshader")

signal built
## A den arrived after the start ([method arrive_den]).
signal den_added(den: ScavengerDen)
## An asteroid cluster appeared (also the starting ones) or was removed.
signal cluster_added(belt: AsteroidCluster)
signal cluster_removed(belt: AsteroidCluster)

const GROUP := "solar_system"

@export var system_def: SystemDef

@export_group("Camera")
## Camera distance when following the home station.
@export var station_view_distance: float = 3000.0
## Yaw offset (degrees) from looking straight at the star in the default view.
@export var default_view_yaw_offset_deg: float = 28.0

@export_group("Zoom fades")
## Planet/gate orbit lines fade in between these camera distances.
@export var orbit_fade_in: Vector2 = Vector2(2600.0, 7000.0)
## Moon orbit lines fade in, then out again far away.
@export var moon_orbit_fade_in: Vector2 = Vector2(2800.0, 6000.0)
@export var moon_orbit_fade_out: Vector2 = Vector2(16000.0, 30000.0)
## Name labels fade in between these camera distances.
@export var label_fade_in: Vector2 = Vector2(5000.0, 9500.0)

var star: Star
var planets: Array[PlanetBody] = []
var belts: Array[AsteroidCluster] = []
var gates: Array[JumpGate] = []
var dens: Array[ScavengerDen] = []
## Derelict hulks of a generated system (P4, [Derelict]).
var derelicts: Array[Derelict] = []
var home_station: Orbiter
## Spawns new clusters when one is mined out (child node, saved by GameSnapshot).
var cluster_spawner: ClusterSpawner

var _orbiters: Array[Orbiter] = []
## Planet -> its orbit line (the fog of war hides both, FogOfWar).
var _planet_lines: Dictionary = {}
var _labels: Array[Label3D] = []
## Per label: world radius of the body it sits under (keeps the text below the disc).
var _label_radii: PackedFloat32Array = []
var _orbit_mat: ShaderMaterial
var _moon_orbit_mat: ShaderMaterial
var _star_color := Color.WHITE
var _view_args: Array = []


## The system [param n] is in (see [method SystemWorld.of]).
static func of(n: Node) -> SolarSystem:
	var w := SystemWorld.of(n)
	return w.sys if w else null


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


## Places every orbiting body and cluster for sim time [param t] (fast-forward).
func update_bodies(t: float) -> void:
	_update_bodies(t)


## The orbit line of planet [param body], or null.
func orbit_line_of(body: PlanetBody) -> MeshInstance3D:
	return _planet_lines.get(body) as MeshInstance3D


## Finds a built body (planet, moon, station, gate, cluster, star) by node name.
func find_body(body_name: String) -> Node3D:
	if star and star.name == body_name:
		return star
	return find_child(body_name, true, false) as Node3D


func get_extent() -> float:
	return system_def.get_extent() if system_def else 0.0


func _update_bodies(t: float) -> void:
	for o in _orbiters:
		o.update_sim(t)
	for b in belts.duplicate():
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
	sun.shadow_normal_bias = 2.0
	sun.shadow_blur = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.25
	add_child(sun)

	var lines := Node3D.new()
	lines.name = "OrbitLines"
	add_child(lines)

	for pdef in def.planets:
		var body := _add_planet(pdef, self)
		_planet_lines[body] = _add_orbit_line(lines, pdef.orbit_radius, _orbit_mat, Color(0.55, 0.72, 1.0, 0.12), body.orbit_basis)
		_add_label(body, pdef.name.to_upper(), pdef.radius * (pdef.ring_outer if pdef.has_rings else 1.0), 1.0)
		for mdef: PlanetDef in pdef.moons:
			var moon := _add_planet(mdef, body)
			_add_orbit_line(body, mdef.orbit_radius, _moon_orbit_mat, Color(0.6, 0.7, 0.9, 0.12), moon.orbit_basis)

	if not def.station_planet.is_empty():
		_add_station(def)

	for bdef in def.belts:
		add_cluster(bdef.duplicate() as ClusterDef)
	cluster_spawner = ClusterSpawner.new()
	cluster_spawner.name = "ClusterSpawner"
	add_child(cluster_spawner)
	cluster_spawner.setup(self)

	for gdef in def.gates:
		var gate := JumpGate.new()
		add_child(gate)
		gate.build(gdef)
		gates.append(gate)
		_orbiters.append(gate)
		_add_label(gate, "%s  >  %s" % [gdef.name.to_upper(), gdef.target_system.to_upper()], 150.0, 0.9, Color(0.55, 0.85, 1.0))

	for ddef in def.dens:
		if ddef.starts_present():
			_add_den(ddef)

	for xdef in def.derelicts:
		var x := Derelict.new()
		x.setup(xdef)
		_add_label(x, xdef.name.to_upper(), 60.0, 0.75, Color(0.9, 0.62, 0.45))
		add_child(x)
		derelicts.append(x)

	_apply_sky_seed(def.sky_seed)


## The built den of [param ddef], or null while it has not arrived.
func den_of(ddef: DenDef) -> ScavengerDen:
	for d in dens:
		if is_instance_valid(d) and d.def == ddef:
			return d
	return null


# --- Clusters -----------------------------------------------------------------

## The hulk named [param item], or null.
func derelict_named(item: String) -> Derelict:
	for x in derelicts:
		if is_instance_valid(x) and x.def and x.def.name == item:
			return x
	return null


## Builds an asteroid cluster from [param bdef] with its name label.
func add_cluster(bdef: ClusterDef) -> AsteroidCluster:
	var belt := AsteroidCluster.new()
	belt.name = StringName(bdef.name.validate_node_name())
	add_child(belt)
	belt.build(bdef, Vector3.ZERO, _star_color)
	belt.update_sim(SimClock.time)
	belts.append(belt)
	# Clicking the cluster (its label) selects it; double click follows it.
	belt.set_meta(&"belt", belt)
	belt.make_focusable(bdef.radius() * 0.6, bdef.size * 2.2)
	var tint := Color(0.85, 0.75, 0.6) if bdef.ore_type != AsteroidBelt.OreType.CRYSTAL else Color(0.55, 0.9, 1.0)
	_add_label(belt, bdef.name.to_upper(), bdef.radius() * 0.5, 0.85, tint)
	belt.faded.connect(remove_cluster)
	if not _view_args.is_empty():
		_on_view_changed.callv(_view_args)
	cluster_added.emit(belt)
	return belt


## Takes a cluster out of the system (mined out and faded, or replaced on load).
func remove_cluster(belt: AsteroidCluster) -> void:
	var i := belts.find(belt)
	if i < 0:
		return
	belts.remove_at(i)
	for j in range(_labels.size() - 1, -1, -1):
		var l := _labels[j]
		if not is_instance_valid(l) or l.get_parent() == belt:
			_labels.remove_at(j)
			_label_radii.remove_at(j)
	cluster_removed.emit(belt)
	# Contracts pointing at it (escorts linked to its mining) lose the target.
	for c in ContractBoard.get_listed():
		if c.target == belt:
			c.target = null
	remove_child(belt)
	belt.queue_free()


## The cluster named [param cluster_name] (old belt names map to their
## starting cluster), or null.
func find_cluster(cluster_name: String) -> AsteroidCluster:
	for b in belts:
		if b.def.name == cluster_name:
			return b
	var alias := cluster_name.replace(" Belt", " Cluster")
	for b in belts:
		if b.def.name == alias:
			return b
	return null


## The nearest cluster whose rim lies within [param reach] of [param pos]
## (flat), or null.
func cluster_near(pos: Vector3, reach: float = INF) -> AsteroidCluster:
	var best: AsteroidCluster = null
	var best_d := reach
	for b in belts:
		if b.is_depleted:
			continue
		var d := b.distance_to(pos)
		if d <= best_d:
			best_d = d
			best = b
	return best


## Where [param ddef]'s base sits (system space = world, the system is at the
## origin): a fixed spot at [member DenDef.anchor_radius] plus its offset.
func den_position(ddef: DenDef) -> Vector3:
	var r := (ddef.anchor_radius if ddef.anchor_radius > 0.0 else 10000.0) + ddef.radial_offset
	var a := deg_to_rad(ddef.angle_deg)
	return Vector3(cos(a), 0.0, sin(a)) * r + Vector3.UP * ddef.height


## Yaw that turns [param ddef]'s base mouth toward the star.
func den_yaw(ddef: DenDef) -> float:
	var p := den_position(ddef)
	var inward := -Vector3(p.x, 0.0, p.z) * signf(ddef.radial_offset if ddef.radial_offset != 0.0 else 1.0)
	return atan2(inward.x, inward.z)


## Builds a den that was not there at the start (nearby clusters' danger
## rises by its bonus). [param effect] plays the warp-in (not on load).
## Returns the den (the existing one when it is already built).
func arrive_den(ddef: DenDef, effect: bool = true) -> ScavengerDen:
	var have := den_of(ddef)
	if have:
		return have
	var den := _add_den(ddef)
	if effect:
		den.play_arrival()
	if not _view_args.is_empty():
		_on_view_changed.callv(_view_args)
	den_added.emit(den)
	return den


## Places a hostile base (any faction) at its fixed spot, mouth turned toward the star.
func _add_den(ddef: DenDef) -> ScavengerDen:
	var den := ScavengerDen.new()
	den.setup(ddef)
	den.position = den_position(ddef)
	den.rotation.y = den_yaw(ddef)
	add_child(den)
	dens.append(den)
	var fac := ddef.get_faction()
	var tone := Color(1.0, 0.45, 0.35) if fac.id == Factions.DEFAULT_ID else fac.color.lerp(Color.WHITE, 0.15)
	_add_label(den, ddef.name.to_upper(), 70.0 * fac.den_hit_radius / 42.0, 0.8, tone)
	return den


## A planet claim's garrison joins the hostile bases ([member dens]) with
## its name label (PlanetClaims; it is already a child of its planet).
func add_garrison(g: ClaimGarrison) -> void:
	if dens.has(g):
		return
	dens.append(g)
	var fac := g.faction_def
	_add_label(g, g.get_display_name().to_upper(), 70.0, 0.75, fac.color.lerp(Color.WHITE, 0.15))
	if not _view_args.is_empty():
		_on_view_changed.callv(_view_args)
	den_added.emit(g)


## Takes a destroyed garrison out of [member dens] and drops its label.
func remove_garrison(g: ClaimGarrison) -> void:
	dens.erase(g)
	for i in range(_labels.size() - 1, -1, -1):
		var l := _labels[i]
		if not is_instance_valid(l) or l.get_parent() == g:
			_labels.remove_at(i)
			_label_radii.remove_at(i)
	den_added.emit(g)


## Tints a planet's name label (a claim's faction colour); [param color]
## with alpha 0 restores the default.
func tint_body_label(body: PlanetBody, color: Color) -> void:
	var l := body.get_node_or_null(^"Label") as Label3D
	if l == null:
		return
	var c := color if color.a > 0.0 else Color(0.82, 0.88, 1.0)
	l.modulate = Color(c.r, c.g, c.b, l.modulate.a)


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


func _add_orbit_line(parent: Node3D, radius: float, mat: ShaderMaterial, color: Color, plane: Basis = Basis.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Orbit"
	mi.basis = plane
	mi.mesh = MeshUtil.make_orbit_strip(radius, clampi(int(radius / 25.0), 128, 1024))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("line_color", color)
	parent.add_child(mi)
	return mi


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
	var cam := RTSCamera.of(self)
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
	_view_args = [_pivot, distance, _yaw_deg]
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

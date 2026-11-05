class_name SurfaceWorld
extends Node3D
## The live landing zone of one planet outpost (planet outposts plan), built
## in its own SubViewport (own World3D) by [SurfaceMode] while the player
## views it, freed on leaving. It works directly on the outpost's data
## ([OutpostState]): stock, deposits, crew hull, building hull; so leaving
## needs no write-back and the data sim ([Outposts]) carries on from there.
##
## Live: harvesters drive (hovering over [SurfaceTerrain]) to the deposits
## with a posted harvest contract, harvest, bring the load to the pad and
## are paid (Outposts.deliver_load); they run for the pad from hostiles.
## Soldiers guard the base, fight critters and raiders, clear nests with a
## bounty and repair at the garrison. Critter waves leave a nest whose
## agitation is up; ground raids land at the zone edge (Outposts calls
## [method spawn_raid]). Turrets shoot, the shield dome takes the hits on
## buildings in its reach. Shots are hitscan with short tracers.

const GROUP := "surface_world"
const HOVER := 3.0
## Gas giants: building decks and the drones' flying height over the clouds.
const PLATFORM_DECK := 60.0
const DRONE_HEIGHT := 45.0
const SOLDIER_DPS := 18.0
const SOLDIER_RANGE := 380.0
const RAIDER_HULL := 420.0
const RAIDER_DPS := 14.0
const RAIDER_RANGE := 330.0
const RAIDER_SPEED := 24.0
const CRITTER_HULL := 130.0
const CRITTER_DPS := 12.0
const CRITTER_RANGE := 26.0
const CRITTER_SPEED := 34.0
const TURRET_DPS := 22.0
const TURRET_RANGE := 520.0
const DOME_REACH := 420.0
const DOME_SHIELD := 2500.0
const DOME_REGEN := 30.0
## Soldiers answer hostiles this close to the pad.
const GUARD_REACH := 1200.0
## Harvesters run for the pad from hostiles this close.
const FLEE_REACH := 240.0
const REPAIR_RATE := 8.0

## One vehicle or critter.
class Unit extends RefCounted:
	var kind := ""
	var node: Node3D
	var pos := Vector2.ZERO
	var heading := 0.0
	var hull := 100.0
	var max_hull := 100.0
	var speed := 30.0
	## The crew entry (harvesters, soldiers) it stands for.
	var crew: Dictionary = {}
	var state := "idle"
	var timer := 0.0
	var target: Variant = null
	var shot_clock := 0.0
	var deposit := -1
	var dead := false
	var leave_at := 0.0
	## A harvester carrying a load to the pad.
	var loaded := false

var outpost: OutpostState
var terrain: SurfaceTerrain
var units: Array[Unit] = []
var camera: Camera3D
## Building dict -> its node; deposit / nest index -> node.
## [building dict, its node] pairs. Not a Dictionary keyed by the building:
## Godot hashes Dictionary keys by content, and building dicts change (hull,
## built, shield) every step.
var _bnodes: Array = []
var _dnodes := {}
var _nnodes := {}
var _nest_clock := {}
var _tracers: Array = []
var _sync := 0.0
## Landing time of the raid whose dropships are already shown.
var _drops_for := -1.0


static func current(tree: SceneTree) -> SurfaceWorld:
	return tree.get_first_node_in_group(GROUP) as SurfaceWorld if tree else null


func setup(o: OutpostState) -> void:
	outpost = o
	terrain = SurfaceTerrain.new(o.seed, o.planet_type)
	name = "SurfaceWorld"


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(SimStepper.GROUP)
	_build_environment()
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = terrain.build_mesh()
	var gm := ShaderMaterial.new()
	gm.shader = load("res://shaders/terrain_surface.gdshader")
	gm.set_shader_parameter("terrain_type", outpost.planet_type)
	gm.set_shader_parameter("amp", 80.0)
	ground.material_override = gm
	add_child(ground)
	if terrain.has_liquid():
		var sea := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2.ONE * (OutpostState.ZONE_SIZE + SurfaceTerrain.MARGIN * 2.0)
		sea.mesh = plane
		sea.position.y = SurfaceTerrain.LIQUID_LEVEL
		var sm := StandardMaterial3D.new()
		if outpost.planet_type == PlanetDef.Type.LAVA:
			sm.albedo_color = Color(0.5, 0.1, 0.02)
			sm.emission_enabled = true
			sm.emission = Color(1.0, 0.35, 0.06)
			sm.emission_energy_multiplier = 3.0
		else:
			sm.albedo_color = Color(0.05, 0.16, 0.22, 0.86)
			sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			sm.metallic = 0.3
			sm.roughness = 0.08
		sea.material_override = sm
		add_child(sea)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.far = 20000.0
	camera.near = 1.0
	add_child(camera)
	camera.current = true
	for b in outpost.buildings:
		_add_building_node(b)
	for i in outpost.deposits.size():
		_add_deposit_node(i)
	for i in outpost.nests.size():
		_add_nest_node(i)
	for c in outpost.crew:
		_spawn_crew(c)
	_spawn_pending()


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	var tones := {
		PlanetDef.Type.ROCKY: [Color(0.03, 0.03, 0.05), Color(0.32, 0.28, 0.25)],
		PlanetDef.Type.OCEAN: [Color(0.12, 0.3, 0.55), Color(0.55, 0.7, 0.85)],
		PlanetDef.Type.DESERT: [Color(0.35, 0.22, 0.12), Color(0.85, 0.6, 0.38)],
		PlanetDef.Type.ICE: [Color(0.1, 0.18, 0.32), Color(0.65, 0.78, 0.9)],
		PlanetDef.Type.LAVA: [Color(0.05, 0.02, 0.02), Color(0.4, 0.14, 0.06)],
		PlanetDef.Type.GAS_GIANT: [Color(0.12, 0.16, 0.3), Color(0.85, 0.66, 0.45)],
	}
	var t: Array = tones.get(outpost.planet_type, tones[PlanetDef.Type.ROCKY])
	mat.sky_top_color = t[0]
	mat.sky_horizon_color = t[1]
	mat.ground_horizon_color = t[1]
	mat.ground_bottom_color = (t[0] as Color).darkened(0.5)
	sky.sky_material = mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.3
	env.tonemap_exposure = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.fog_enabled = true
	env.fog_light_color = t[1]
	env.fog_density = 0.0002 if terrain.is_gas() else 0.00012
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 35.0, 0.0)
	sun.light_energy = 1.15 if outpost.planet_type != PlanetDef.Type.LAVA else 0.8
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 3000.0
	add_child(sun)
	_build_sky(sun)


## Sky distance of the star disc and the parent planet, m (inside camera.far).
const SKY_DIST := 16000.0
## Elevation of the star disc and the parent planet over the horizon. Low on
## purpose: the camera only sees the sky when it levels out close to the
## ground (SurfaceMode.PITCH_LOW). The sun light itself stays higher, for
## readable shadows.
const SKY_ELEVATION := deg_to_rad(11.0)


## The system's star as a glowing disc on the sun's bearing and, on a moon,
## its parent planet hanging low in the sky (the planet's own shader, lit
## from the sun's side), in the camera's starting direction.
func _build_sky(sun: DirectionalLight3D) -> void:
	var outposts := Outposts.of(get_tree())
	var w := outposts.station_world(outpost) if outposts else null
	var to_sun := sun.basis.z
	var sun_flat := Vector2(to_sun.x, to_sun.z).normalized()
	var star_color := Color(1.0, 0.92, 0.8)
	if w and w.sys and w.sys.star:
		star_color = w.sys.star.color
	sun.light_color = star_color.lerp(Color.WHITE, 0.6)
	var star := MeshInstance3D.new()
	star.name = "SkyStar"
	var disc := SphereMesh.new()
	disc.radius = 330.0
	disc.height = 660.0
	star.mesh = disc
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Star.surface_color(star_color).lerp(Color.WHITE, 0.5)
	sm.emission_enabled = true
	sm.emission = sm.albedo_color
	sm.emission_energy_multiplier = 6.0
	sm.disable_fog = true
	star.material_override = sm
	star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	star.position = _sky_point(sun_flat)
	add_child(star)
	var body := PlanetInfo.find_planet(w, outpost.planet) if w else null
	var parent := body.get_parent() as PlanetBody if body else null
	if parent == null or parent.surface == null:
		return
	var pm := parent.surface.material_override as ShaderMaterial
	if pm == null:
		return
	var mat := pm.duplicate() as ShaderMaterial
	mat.set_shader_parameter("use_star_position", false)
	mat.set_shader_parameter("sun_direction", to_sun.normalized())
	var sky := MeshInstance3D.new()
	sky.name = "SkyParent"
	sky.mesh = parent.surface.mesh
	sky.material_override = mat
	sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# About 18 degrees across for a gas giant, 13 for anything else, its
	# lower edge just over the horizon.
	var r := 2600.0 if parent.def.type == PlanetDef.Type.GAS_GIANT else 1800.0
	sky.scale = Vector3.ONE * r
	# Where SurfaceMode's camera looks at the start (yaw 0.6), a little aside.
	var look := Vector2(-sin(0.6), -cos(0.6)).rotated(deg_to_rad(-14.0))
	sky.position = _sky_point(look)
	add_child(sky)


func _sky_point(flat_dir: Vector2) -> Vector3:
	var d := flat_dir.normalized() * cos(SKY_ELEVATION)
	return Vector3(d.x, sin(SKY_ELEVATION), d.y) * SKY_DIST


# --- Nodes -------------------------------------------------------------------------

func ground_at(x: float, z: float) -> Vector3:
	return Vector3(x, terrain.height(x, z), z)


## Where a building stands: on the ground, or on gas giants on its own
## floating platform deck above the clouds.
func deck_at(x: float, z: float) -> Vector3:
	if terrain.is_gas():
		return Vector3(x, PLATFORM_DECK, z)
	return ground_at(x, z)


func _add_building_node(b: Dictionary) -> void:
	var n := SurfaceModels.make(String(b["kind"]))
	n.position = deck_at(float(b["x"]), float(b["z"]))
	if terrain.is_gas():
		var deck := SurfaceModels.make("platform")
		deck.name = "PlatformDeck"
		var ds := (float(OutpostState.BUILDINGS[StringName(b["kind"])]["radius"]) + 12.0) / 60.0
		deck.scale = Vector3.ONE * ds
		deck.set_meta(&"deck_scale", ds)
		n.add_child(deck)
	add_child(n)
	_bnodes.append([b, n])
	_update_building_look(b)


## The node standing for building [param b] (same dict, by identity), or null.
func _node_of(b: Dictionary) -> Node3D:
	for pair: Array in _bnodes:
		if is_same(pair[0], b):
			return pair[1] as Node3D
	return null


func _update_building_look(b: Dictionary) -> void:
	var n := _node_of(b)
	if n == null:
		return
	var k := clampf(float(b.get("built", 1.0)), 0.05, 1.0)
	n.scale = Vector3(1.0, k, 1.0)
	# The gas giant deck under it is finished from the start: undo the build
	# squash on it (its top sits at the node's origin, so only its depth scales).
	var deck := n.get_node_or_null(^"PlatformDeck") as Node3D
	if deck:
		var ds := float(deck.get_meta(&"deck_scale", 1.0))
		deck.scale = Vector3(ds, ds / k, ds)


func _add_deposit_node(i: int) -> void:
	var d: Dictionary = outpost.deposits[i]
	var n := SurfaceModels.make("deposit_" + Economy.ORE_ICONS[outpost.good])
	n.position = ground_at(float(d["x"]), float(d["z"]))
	add_child(n)
	_dnodes[i] = n


func _add_nest_node(i: int) -> void:
	var n := SurfaceModels.make("storm_cell" if terrain.is_gas() else "nest")
	var d: Dictionary = outpost.nests[i]
	n.position = ground_at(float(d["x"]), float(d["z"]))
	add_child(n)
	_nnodes[i] = n


## A building placed from the HUD (already in the data).
func add_building(b: Dictionary) -> void:
	_add_building_node(b)


func _spawn_crew(c: Dictionary) -> Unit:
	var u := Unit.new()
	u.crew = c
	var harvester := String(c["role"]) == OutpostState.HARVESTER
	u.kind = "harvester" if harvester else "soldier"
	u.max_hull = OutpostState.max_hull(String(c["role"]))
	u.hull = float(c.get("hull", u.max_hull))
	u.speed = OutpostState.HARVESTER_SPEED if harvester else OutpostState.SOLDIER_SPEED
	var home := outpost.building(OutpostState.BAY if harvester else OutpostState.GARRISON)
	var at := Vector2(float(home.get("x", 0.0)), float(home.get("z", 0.0))) + Vector2(randf_range(-40, 40), randf_range(-40, 40))
	return _add_unit(u, "harvester" if harvester else "hover_tank", at)


func _add_unit(u: Unit, model: String, at: Vector2) -> Unit:
	u.pos = at
	u.node = SurfaceModels.make(model)
	add_child(u.node)
	_place(u)
	units.append(u)
	return u


## A crew member hired from the HUD.
func add_crew(c: Dictionary) -> void:
	_spawn_crew(c)


## Ground raid of [param size] tanks at the drop point on bearing [param a]
## (radians round the pad; below 0 picks one), where its dropships set down.
func spawn_raid(size: int, source: String, a: float = -1.0) -> void:
	if a < 0.0:
		a = randf() * TAU
	var at := drop_point(a)
	for i in size:
		var u := Unit.new()
		u.kind = "raider"
		u.max_hull = RAIDER_HULL
		u.hull = RAIDER_HULL
		u.speed = RAIDER_SPEED
		u.leave_at = SimClock.time + 240.0
		_add_unit(u, "raider_tank", at + Vector2(randf_range(-60, 60), randf_range(-60, 60)))
	EventLog.post("%s raiders landed on %s: %d tanks" % [source, outpost.planet, size], EventLog.Kind.THREAT)


## A raid's drop point on bearing [param a], near the zone edge.
static func drop_point(a: float) -> Vector2:
	return Vector2(cos(a), sin(a)) * (OutpostState.ZONE_SIZE * 0.47)


## The coming raid's dropships, shown [constant RaidDropship.DESCENT] sim
## seconds before it lands (one per three tanks, side by side).
func _drop_step() -> void:
	var r := outpost.raid
	if r.is_empty():
		return
	var at := float(r["at"])
	if SimClock.time < at - RaidDropship.DESCENT or SimClock.time >= at or is_equal_approx(_drops_for, at):
		return
	_drops_for = at
	if not r.has("a"):
		r["a"] = randf() * TAU      # a raid formed before drop bearings were saved
	var a := float(r["a"])
	var c := drop_point(a)
	var inward := Vector3(-cos(a), 0.0, -sin(a))
	var side := Vector2(-sin(a), cos(a))
	var n := ceili(int(r["size"]) / 3.0)
	for i in n:
		var p := c + side * (float(i) - (n - 1) * 0.5) * 70.0
		var land := ground_at(p.x, p.y)
		if terrain.has_liquid():
			land.y = maxf(land.y, SurfaceTerrain.LIQUID_LEVEL)
		if terrain.is_gas():
			land.y = maxf(land.y, 0.0) + DRONE_HEIGHT
		var ship := RaidDropship.new()
		ship.setup(land, at, inward)
		add_child(ship)


## Hostiles saved on the ground (OutpostState.pending_ground) come back live.
func _spawn_pending() -> void:
	var left := outpost.pending_ground
	if left.is_empty():
		return
	outpost.pending_ground = {}
	var raiders := roundi(float(left.get("raiders", 0.0)) / 0.8)
	if raiders > 0:
		spawn_raid(raiders, "Returning")
	var critters := roundi(float(left.get("critters", 0.0)) / 0.3)
	if critters > 0 and not outpost.nests.is_empty():
		_spawn_wave(0, critters)


func _spawn_wave(nest_i: int, size: int) -> void:
	var n: Dictionary = outpost.nests[nest_i]
	for i in size:
		var u := Unit.new()
		u.kind = "critter"
		u.max_hull = CRITTER_HULL
		u.hull = CRITTER_HULL
		u.speed = CRITTER_SPEED
		u.leave_at = SimClock.time + 300.0
		_add_unit(u, "floater" if terrain.is_gas() else "critter", Vector2(float(n["x"]), float(n["z"])) + Vector2(randf_range(-30, 30), randf_range(-30, 30)))
	EventLog.post("%d critters swarm out of a nest on %s" % [size, outpost.planet], EventLog.Kind.THREAT)


# --- Step --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if SimClock.paused:
		_fade_tracers(delta)
		return
	var dt := delta * SimClock.speed
	# Short steps at high speed (combat and steering).
	var left := dt
	while left > 0.0:
		var h := minf(left, 0.1)
		sim_step(h)
		left -= h
	_fade_tracers(delta)


func sim_step(dt: float) -> void:
	if outpost == null or outpost.lost:
		return
	for b in outpost.buildings:
		if _node_of(b) == null:
			_add_building_node(b)
		else:
			_update_building_look(b)
	_nests_step(dt)
	_dome_step(dt)
	_drop_step()
	for u in units.duplicate():
		if u.dead:
			continue
		match u.kind:
			"harvester":
				_harvester_step(u, dt)
			"soldier":
				_soldier_step(u, dt)
			"critter":
				_hostile_step(u, dt, CRITTER_DPS, CRITTER_RANGE)
			"raider":
				_hostile_step(u, dt, RAIDER_DPS, RAIDER_RANGE)
		if not u.dead:
			_place(u)
	_turrets_step(dt)
	for i in outpost.nests.size():
		var nn: Node3D = _nnodes.get(i)
		if nn:
			nn.visible = float(outpost.nests[i].get("dead_until", -1.0)) < 0.0
	for i in outpost.deposits.size():
		if not _dnodes.has(i):
			_add_deposit_node(i)
		var dn: Node3D = _dnodes[i]
		var d: Dictionary = outpost.deposits[i]
		var f := float(d["loads"]) / maxf(float(d["total"]), 1.0)
		dn.visible = int(d["loads"]) > 0
		dn.scale = Vector3.ONE * lerpf(0.45, 1.0, f)
	if not outpost.pad_alive():
		Outposts.of(get_tree()).lose(outpost, "its landing pad was destroyed")
		var sm := SurfaceMode.of(get_tree())
		if sm:
			sm.leave.call_deferred()


func _place(u: Unit) -> void:
	var y := terrain.height(u.pos.x, u.pos.y)
	if terrain.has_liquid():
		y = maxf(y, SurfaceTerrain.LIQUID_LEVEL)
	if terrain.is_gas():
		# Everything flies: drones and tanks over the clouds, floaters a bit lower.
		y = maxf(y, 0.0) + (DRONE_HEIGHT if u.kind != "critter" else DRONE_HEIGHT * 0.6)
	else:
		y += HOVER if u.kind != "critter" else 0.0
	u.node.position = Vector3(u.pos.x, y, u.pos.y)
	u.node.rotation = Vector3(0.0, u.heading, 0.0)


## Moves [param u] toward [param to]; true when there (within [param reach]).
func _move(u: Unit, to: Vector2, dt: float, reach: float = 10.0) -> bool:
	var d := to - u.pos
	var dist := d.length()
	if dist <= reach:
		return true
	var step := minf(u.speed * dt, dist)
	u.pos += d / dist * step
	u.heading = lerp_angle(u.heading, atan2(-d.x, -d.y), clampf(dt * 4.0, 0.0, 1.0))
	return false


func _harvester_step(u: Unit, dt: float) -> void:
	var pad := Vector2.ZERO
	var threat: Variant = _nearest_hostile(u.pos, FLEE_REACH)
	if threat and u.state != "flee" and u.state != "home":
		u.state = "flee"
	match u.state:
		"idle":
			u.timer -= dt
			if u.timer > 0.0:
				return
			u.timer = 3.0
			var di := Outposts.of(get_tree()).pick_deposit(outpost, u.crew)
			if di >= 0:
				u.deposit = di
				u.crew["deposit"] = di
				u.state = "go"
		"go":
			if u.deposit < 0 or u.deposit >= outpost.deposits.size() or int(outpost.deposits[u.deposit]["loads"]) <= 0 or not outpost.contracts.has(u.deposit):
				u.state = "home"
				return
			var d: Dictionary = outpost.deposits[u.deposit]
			if _move(u, Vector2(float(d["x"]), float(d["z"])), dt, 30.0):
				u.state = "harvest"
				u.timer = OutpostState.HARVEST_TIME
		"harvest":
			u.timer -= dt
			if u.timer <= 0.0:
				u.state = "return"
				u.loaded = true
		"return":
			if _move(u, pad, dt, 45.0):
				_unload(u)
				u.state = "idle"
				u.timer = 2.0
		"flee", "home":
			if _move(u, pad, dt, 45.0):
				_unload(u)
				u.state = "idle"
				u.timer = 6.0


## A harvester at the pad hands over the load it carries, if any.
func _unload(u: Unit) -> void:
	if u.loaded and u.deposit >= 0 and u.deposit < outpost.deposits.size():
		Outposts.of(get_tree()).deliver_load(outpost, u.crew, u.deposit)
	u.loaded = false
	u.crew["trip"] = 0.0


## Leaving: each harvester's trip progress goes back into its crew entry, so
## the data sim carries on from there (a load on the way home is not lost).
func sync_trips() -> void:
	for u in units:
		if u.dead or u.kind != "harvester":
			continue
		match u.state:
			"return":
				u.crew["trip"] = 0.8 if u.loaded else 0.0
			"flee", "home":
				u.crew["trip"] = 0.8 if u.loaded else 0.0
			"harvest":
				u.crew["trip"] = 0.45
			"go":
				u.crew["trip"] = 0.15
			_:
				u.crew["trip"] = 0.0
		u.crew["deposit"] = u.deposit


func _soldier_step(u: Unit, dt: float) -> void:
	var garrison := outpost.active_building(OutpostState.GARRISON)
	var post := Vector2(float(garrison.get("x", 0.0)), float(garrison.get("z", 0.0)))
	# Repairs need a working garrison (the data sim heals the same way).
	if not garrison.is_empty() and (u.hull < u.max_hull * 0.3 or u.state == "repair"):
		u.state = "repair"
		if _move(u, post, dt, 30.0):
			u.hull = minf(u.hull + REPAIR_RATE * dt, u.max_hull)
			u.crew["hull"] = u.hull
			if u.hull >= u.max_hull * 0.95:
				u.state = "idle"
		return
	var t: Variant = _nearest_hostile(u.pos, 700.0)
	if t == null:
		t = _nearest_hostile(Vector2.ZERO, GUARD_REACH)
	var target_pos := Vector2.ZERO
	var nest := -1
	if t == null:
		# A nest with a bounty, when two soldiers or more stand.
		if _soldiers() >= 2:
			for i: int in outpost.bounties:
				if i < outpost.nests.size() and float(outpost.nests[i].get("dead_until", -1.0)) < 0.0:
					nest = i
					break
	if t != null:
		target_pos = (t as Unit).pos
	elif nest >= 0:
		target_pos = Vector2(float(outpost.nests[nest]["x"]), float(outpost.nests[nest]["z"]))
	else:
		var a := float(hash(u.crew.get("name", ""))) * 0.001
		_move(u, post + Vector2(cos(a), sin(a)) * 120.0, dt, 15.0)
		return
	var dist := u.pos.distance_to(target_pos)
	if dist > SOLDIER_RANGE * 0.8:
		_move(u, target_pos, dt, SOLDIER_RANGE * 0.7)
		return
	u.heading = lerp_angle(u.heading, atan2(-(target_pos - u.pos).x, -(target_pos - u.pos).y), clampf(dt * 5.0, 0.0, 1.0))
	if t != null:
		_damage_unit(t as Unit, SOLDIER_DPS * dt, u)
	else:
		var n: Dictionary = outpost.nests[nest]
		n["hull"] = float(n["hull"]) - SOLDIER_DPS * dt
		if float(n["hull"]) <= 0.0:
			Outposts.of(get_tree()).kill_nest(outpost, nest)
	_tracer(u, target_pos, Color(0.4, 0.85, 1.0))


func _soldiers() -> int:
	var n := 0
	for u in units:
		if not u.dead and u.kind == "soldier":
			n += 1
	return n


## Critters and raiders: the nearest harvester, soldier or building in reach.
func _hostile_step(u: Unit, dt: float, dps: float, rng: float) -> void:
	if SimClock.time > u.leave_at:
		_remove_unit(u)
		return
	var best: Variant = null
	var best_pos := Vector2.ZERO
	var best_d := INF
	for o in units:
		if o.dead or o.kind == "critter" or o.kind == "raider":
			continue
		var d := u.pos.distance_to(o.pos)
		if d < best_d:
			best_d = d
			best = o
			best_pos = o.pos
	for b in outpost.buildings:
		if float(b["hull"]) <= 0.0:
			continue
		var bp := Vector2(float(b["x"]), float(b["z"]))
		var d := u.pos.distance_to(bp) - float(OutpostState.BUILDINGS[StringName(b["kind"])]["radius"])
		# Raiders go for the buildings, critters for whatever is nearest.
		if u.kind == "raider":
			d *= 0.6
		if d < best_d:
			best_d = d
			best = b
			best_pos = bp
	if best == null:
		return
	if best_d > rng:
		_move(u, best_pos, dt, rng * 0.8)
		return
	if best is Unit:
		_damage_unit(best as Unit, dps * dt, u)
	else:
		_damage_building(best as Dictionary, dps * dt)
	if u.kind == "raider":
		_tracer(u, best_pos, Color(1.0, 0.45, 0.2))


func _turrets_step(dt: float) -> void:
	for b in outpost.buildings:
		if StringName(b["kind"]) != OutpostState.TURRET or float(b.get("built", 1.0)) < 1.0 or bool(b.get("disabled", false)):
			continue
		var at := Vector2(float(b["x"]), float(b["z"]))
		var t: Variant = _nearest_hostile(at, TURRET_RANGE)
		if t == null:
			continue
		_damage_unit(t as Unit, TURRET_DPS * dt, null)
		var n := _node_of(b)
		if n:
			_tracer_from(n.position + Vector3.UP * 10.0, (t as Unit).pos, Color(0.5, 0.9, 1.0), n)


func _nests_step(dt: float) -> void:
	for i in outpost.nests.size():
		var n: Dictionary = outpost.nests[i]
		if float(n.get("dead_until", -1.0)) >= 0.0:
			continue
		var t := float(_nest_clock.get(i, 0.0)) + dt
		_nest_clock[i] = t
		if t < Outposts.NEST_CHECK:
			continue
		_nest_clock[i] = 0.0
		var ag := float(n["agitation"])
		if ag >= OutpostState.AGITATION_ATTACK:
			n["agitation"] = ag - OutpostState.AGITATION_ATTACK
			_spawn_wave(i, mini(2 + floori(ag / 25.0), 2 + outpost.danger))


func _dome_step(dt: float) -> void:
	var dome := outpost.building(OutpostState.DOME)
	if not _dome_up(dome):
		if not dome.is_empty() and bool(dome.get("disabled", false)):
			dome["shield"] = 0.0
		return
	if not dome.has("shield"):
		dome["shield"] = DOME_SHIELD
	if SimClock.time - float(dome.get("shield_hit", -99.0)) > 5.0:
		dome["shield"] = minf(float(dome["shield"]) + DOME_REGEN * dt, DOME_SHIELD)


## The dome stands, is finished and is not disabled.
static func _dome_up(dome: Dictionary) -> bool:
	return not dome.is_empty() and float(dome.get("built", 1.0)) >= 1.0 and not bool(dome.get("disabled", false))


func _nearest_hostile(at: Vector2, reach: float) -> Variant:
	var best: Variant = null
	var best_d := reach
	for u in units:
		if u.dead or (u.kind != "critter" and u.kind != "raider"):
			continue
		var d := at.distance_to(u.pos)
		if d < best_d:
			best_d = d
			best = u
	return best


func _damage_unit(u: Unit, amount: float, by: Variant) -> void:
	if u.dead:
		return
	u.hull -= amount
	if not u.crew.is_empty():
		u.crew["hull"] = maxf(u.hull, 0.0)
	if u.hull <= 0.0:
		if not u.crew.is_empty():
			outpost.crew.erase(u.crew)
			EventLog.post("%s was destroyed on %s" % [u.crew.get("name", "A vehicle"), outpost.planet], EventLog.Kind.LOSS)
			var o := Outposts.of(get_tree())
			if o:
				o.changed.emit(outpost)
		elif by is Unit and not (by as Unit).crew.is_empty():
			(by as Unit).crew["kills"] = int((by as Unit).crew.get("kills", 0)) + 1
		_remove_unit(u)


func _damage_building(b: Dictionary, amount: float) -> void:
	var dome := outpost.building(OutpostState.DOME)
	if _dome_up(dome) and float(dome.get("shield", 0.0)) > 0.0 and not is_same(b, dome):
		var dp := Vector2(float(dome["x"]), float(dome["z"]))
		if dp.distance_to(Vector2(float(b["x"]), float(b["z"]))) < DOME_REACH:
			dome["shield"] = float(dome["shield"]) - amount
			dome["shield_hit"] = SimClock.time
			return
	b["hull"] = maxf(float(b["hull"]) - amount, 0.0)
	b["hit_at"] = SimClock.time
	if float(b["hull"]) <= 0.0 and not bool(b.get("disabled", false)):
		b["disabled"] = true
		EventLog.post("%s on %s disabled" % [OutpostState.BUILDINGS[StringName(b["kind"])]["name"], outpost.planet], EventLog.Kind.LOSS)


## Hostiles still on the ground when the view leaves, as a data attack
## (so leaving the surface does not end a fight): [{kind, power}] by kind.
func hostiles_left() -> Dictionary:
	var out := {}
	for u in units:
		if u.dead:
			continue
		if u.kind == "critter":
			out["critters"] = float(out.get("critters", 0.0)) + 0.3 * u.hull / CRITTER_HULL
		elif u.kind == "raider":
			out["raiders"] = float(out.get("raiders", 0.0)) + 0.8 * u.hull / RAIDER_HULL
	return out


func _remove_unit(u: Unit) -> void:
	u.dead = true
	if is_instance_valid(u.node):
		u.node.queue_free()
	units.erase(u)


# --- Tracers -------------------------------------------------------------------------

func _tracer(u: Unit, to: Vector2, color: Color) -> void:
	u.shot_clock -= 0.1
	if u.shot_clock > 0.0:
		return
	u.shot_clock = 0.45
	_tracer_from(u.node.position + Vector3.UP * 4.0, to, color, null)


## [param shooter]: a node whose "shot" meta paces its tracers, or null.
func _tracer_from(from: Vector3, to2: Vector2, color: Color, shooter: Node) -> void:
	if shooter != null:
		var c := float(shooter.get_meta(&"shot", 0.0)) - 0.1
		shooter.set_meta(&"shot", c)
		if c > 0.0:
			return
		shooter.set_meta(&"shot", 0.35)
	var to := ground_at(to2.x, to2.y) + Vector3.UP * 4.0
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	var len := from.distance_to(to)
	box.size = Vector3(0.8, 0.8, len)
	mi.mesh = box
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 4.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	add_child(mi)
	mi.position = (from + to) * 0.5
	var flat := Vector2(to.x - mi.position.x, to.z - mi.position.z).length()
	if len > 0.1:
		mi.look_at(to, Vector3.UP if flat > 0.05 * len else Vector3.FORWARD)
	_tracers.append([mi, 0.12])


func _fade_tracers(delta: float) -> void:
	for t in _tracers.duplicate():
		t[1] = float(t[1]) - delta
		if float(t[1]) <= 0.0:
			(t[0] as Node).queue_free()
			_tracers.erase(t)


# --- Picking ----------------------------------------------------------------------------

## What lies at ground point [param p]: {kind: "building"/"deposit"/"nest"/"unit", ref}, {} for nothing.
func pick(p: Vector3) -> Dictionary:
	var at := Vector2(p.x, p.z)
	for u in units:
		if not u.dead and at.distance_to(u.pos) < 18.0:
			return {"kind": "unit", "ref": u}
	for b in outpost.buildings:
		if at.distance_to(Vector2(float(b["x"]), float(b["z"]))) < float(OutpostState.BUILDINGS[StringName(b["kind"])]["radius"]) + 8.0:
			return {"kind": "building", "ref": b}
	for i in outpost.deposits.size():
		var d: Dictionary = outpost.deposits[i]
		if int(d["loads"]) > 0 and at.distance_to(Vector2(float(d["x"]), float(d["z"]))) < 70.0:
			return {"kind": "deposit", "ref": i}
	for i in outpost.nests.size():
		var n: Dictionary = outpost.nests[i]
		if float(n.get("dead_until", -1.0)) < 0.0 and at.distance_to(Vector2(float(n["x"]), float(n["z"]))) < 60.0:
			return {"kind": "nest", "ref": i}
	return {}

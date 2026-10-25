class_name ClaimGarrison
extends ScavengerDen
## A faction's orbital garrison over a claimed planet or moon (phase C3,
## PlanetClaims). A ScavengerDen in everything the rest of the game sees
## (combatant, bounty target, alarm and defenders, map markers, save), but
## it rides with its planet (a child of the PlanetBody at a fixed offset:
## Orbiters never rotate), shoots with four flak turrets of its own and
## launches patrols that guard the planet ([method spawn]: ScavengerBrain
## guard mode). It sends no raids and does not count for the threat clock.
## Hull, shields, turrets and patrols come from the faction
## (FactionDef "Planet claims" group); a runtime DenDef carries them for the
## den code.
## Model: res://assets/models/buildings/claim_garrison.glb (89 m across,
## 67 m tall): garrison_hull, garrison_lights, beacon_light (pulsed),
## garrison_hangar_glow, flak_turret_1..4 (yaw nodes, local -Z along the
## barrels, muzzles flak_N_muzzle_l/r), spawn_point (local -Z points out of
## the launch bay). The "faction_paint" material is tinted per instance in
## the faction colour.

const MODEL := "res://assets/models/buildings/claim_garrison.glb"
const PAINT_MATERIAL := "faction_paint"
const HIT_RADIUS := 46.0
## Gap between the planet's visible reach and the garrison, and its height
## over the planet's centre, metres.
const STAND_OFF := 650.0
const HEIGHT := 220.0
## Clearance kept from a moon's orbit, metres (past the moon's own radius).
const MOON_CLEARANCE := 600.0
## A turret swings this far either side of its rest heading, radians.
const TURRET_ARC := 2.0
const TURRET_TURN := 2.2
const TURRET_ACCURACY := 0.5
const RETARGET := 0.5

var planet: PlanetBody
var gang: String = ""
## Direction from the planet's centre to the garrison, radians (0 = +X, toward +Z).
var site_angle: float = 0.0
var claimed_at: float = 0.0
## Patrols fight player ships this close to the planet's centre, metres.
var guard_radius: float = 4000.0

var _turrets: Array[Dictionary] = []
var _beacon_mats: Array[StandardMaterial3D] = []
var _beacon_base: Array[float] = []
var _beacon_light: OmniLight3D
var _paint: StandardMaterial3D


## Call before adding it to the planet.
func setup_claim(body: PlanetBody, fdef: FactionDef, gang_name: String, angle: float) -> void:
	planet = body
	gang = gang_name
	site_angle = angle
	var d := DenDef.new()
	d.name = "%s Garrison" % body.def.name
	d.faction = fdef
	d.gang = gang_name
	d.spawn_cap = fdef.garrison_patrols
	d.respawn_time = fdef.garrison_respawn
	d.initial_spawns = fdef.garrison_patrols
	d.hull = fdef.garrison_hull
	d.shields = fdef.garrison_shields
	d.shield_regen = fdef.garrison_shield_regen
	d.danger_bonus = 0
	setup(d, null)
	guard_radius = site_distance(body) + fdef.garrison_guard_reach


# --- Placement --------------------------------------------------------------------

## Distance of a garrison from [param body]'s centre: past its atmosphere or
## rings, and clear of its moons' orbits.
static func site_distance(body: PlanetBody) -> float:
	var d := SpaceNav.body_reach(body.def) + STAND_OFF
	for c in body.get_children():
		var m := c as PlanetBody
		if m and absf(m.def.orbit_radius - d) < m.def.radius + MOON_CLEARANCE:
			d = maxf(d, m.def.orbit_radius + m.def.radius + MOON_CLEARANCE)
	return d


## Offset of the garrison in [param body]'s frame for [param angle].
static func site_local(body: PlanetBody, angle: float) -> Vector3:
	return Vector3(cos(angle), 0.0, sin(angle)) * site_distance(body) + Vector3.UP * HEIGHT


## Yaw that turns the launch bay away from the planet.
static func site_yaw(angle: float) -> float:
	var out := Vector3(cos(angle), 0.0, sin(angle))
	return atan2(out.x, out.z)


## The default side: toward the star (the lit side), a little off the line.
static func default_angle(body: PlanetBody) -> float:
	var p := body.global_position
	return atan2(-p.z, -p.x) + 0.35


## Tints every "faction_paint" surface under [param model] in [param color]
## (one copy per call: materials are shared between instances). Returns it.
static func paint(model: Node3D, color: Color) -> StandardMaterial3D:
	var made: StandardMaterial3D = null
	for mi in ModelLoader.meshes_of(model):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i) as StandardMaterial3D
			if src == null or src.resource_name != PAINT_MATERIAL:
				continue
			if made == null:
				made = src.duplicate() as StandardMaterial3D
				made.albedo_color = Color(color.r, color.g, color.b, 1.0).lerp(src.albedo_color, 0.15)
			mi.set_surface_override_material(i, made)
	return made


# --- Build --------------------------------------------------------------------------

func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(Combat.GROUP)
	add_to_group(SimStepper.GROUP)
	_rng.seed = hash(def.name + str(claimed_at))
	durability = Durability.new(def.get_hull(), def.get_shields(), def.get_shield_regen())
	durability.shield_delay = 6.0
	_model = ModelLoader.instantiate(MODEL, ModelLoader.building_placeholder.bind(64.0, faction_def.color))
	_model.name = "Model"
	add_child(_model)
	ModelLoader.dim_emission(_model)
	_paint = paint(_model, faction_def.color)
	MeshUtil.set_layers_recursive(_model, RENDER_LAYER)
	_collect_mats("garrison_hangar_glow", _glow_mats, _glow_base)
	_collect_mats("garrison_lights", _light_mats, _light_base)
	_collect_mats("beacon_light", _beacon_mats, _beacon_base)
	_hangar_light = OmniLight3D.new()
	_hangar_light.name = "HangarLight"
	_hangar_light.light_color = faction_def.light_color
	_hangar_light.light_energy = 3.0
	_hangar_light.omni_range = 120.0
	_hangar_light.omni_attenuation = 1.5
	_hangar_light.light_cull_mask = RENDER_LAYER
	_hangar_light.position = Vector3(0.0, 3.0, 54.0)
	add_child(_hangar_light)
	_beacon_light = OmniLight3D.new()
	_beacon_light.name = "BeaconLight"
	_beacon_light.light_color = faction_def.light_color.lerp(Color(1.0, 0.25, 0.2), 0.4)
	_beacon_light.light_energy = 0.0
	_beacon_light.omni_range = 70.0
	_beacon_light.light_cull_mask = RENDER_LAYER
	var bp := _model.find_child("beacon_point", true, false) as Node3D
	_beacon_light.position = ModelLoader.relative_transform(self, bp).origin if bp else Vector3(0.0, 50.0, 0.0)
	add_child(_beacon_light)
	_setup_turrets()
	set_meta(&"focus_radius", 70.0)
	set_meta(&"focus_distance", 640.0)
	add_to_group(RTSCamera.FOCUS_GROUP)
	_respawn_clock = def.respawn_time
	_initial_spawns.call_deferred()


func _setup_turrets() -> void:
	for i in range(1, 5):
		var n := _model.find_child("flak_turret_%d" % i, true, false) as Node3D
		if n == null:
			continue
		var muzzles: Array[Node3D] = []
		for side in ["l", "r"]:
			var m := n.find_child("flak_%d_muzzle_%s" % [i, side], true, false) as Node3D
			if m:
				muzzles.append(m)
		_turrets.append({"node": n, "rest": n.rotation.y, "target": null, "cooldown": _rng.randf() * 0.6, "side": 0, "muzzles": muzzles})


# --- Combatant API ------------------------------------------------------------------

func get_hit_radius() -> float:
	return HIT_RADIUS


## Rides with its planet: attackers lead their shots.
func get_aim_velocity() -> Vector3:
	return SpaceNav.world_velocity(self)


func info_text() -> String:
	var where := planet.def.name if is_instance_valid(planet) else "a planet"
	return "Orbital garrison of %s (%s), holding %s. Four flak turrets cover it and it keeps up to %d patrol ships around the planet. Landers will not raid %s while it stands. Destroy it to break the claim." % [
			gang, faction_def.display_name, where, def.spawn_cap, where]


func kind_name() -> String:
	return "%s garrison" % faction_def.unit_name.to_lower()


func claim_text() -> String:
	return "holds %s" % (planet.def.name if is_instance_valid(planet) else "?")


func gun_dps() -> float:
	return faction_def.garrison_gun_dps()


func is_raid_base() -> bool:
	return false


## Short strength line: "Hull 82%, shields 40%, 2/3 patrols out".
func strength_text() -> String:
	if dead:
		return "Destroyed"
	var sh := durability.shields / durability.max_shields if durability.max_shields > 0.0 else 0.0
	return "Hull %d%%, shields %d%%" % [roundi(hull_fraction() * 100.0), roundi(sh * 100.0)]


func patrols_out() -> int:
	var n := 0
	for s in spawns:
		if is_instance_valid(s) and not s.dead:
			n += 1
	return n


# --- Patrols --------------------------------------------------------------------------

## A den launch, then the ship guards the planet.
func spawn(raid: bool = false, out_already: bool = false) -> ScavengerShip:
	var s := super.spawn(raid, out_already)
	if s and s.ai and is_instance_valid(planet):
		s.ai.set_guard(planet, guard_radius, SpaceNav.body_reach(planet.def) + 300.0)
	return s


## A ship of the claim group joins the garrison as a patrol.
func adopt(s: ScavengerShip) -> void:
	if s == null or s.dead:
		return
	s.den = self
	if not spawns.has(s):
		spawns.append(s)
	if s.ai:
		s.ai.withdraw = false
		s.ai.set_guard(planet, guard_radius, SpaceNav.body_reach(planet.def) + 300.0)


## After load: the patrols guard the planet again.
func restore_ships(d: Dictionary, refs: SaveRefs) -> void:
	super.restore_ships(d, refs)
	for s in spawns:
		if is_instance_valid(s) and s.ai and is_instance_valid(planet):
			s.ai.set_guard(planet, guard_radius, SpaceNav.body_reach(planet.def) + 300.0)


# --- Turrets ----------------------------------------------------------------------------

func _guns(dt: float) -> void:
	_gun_timer -= dt
	var retarget := _gun_timer <= 0.0
	var near: Array[Node3D] = []
	if retarget:
		_gun_timer = RETARGET
		near = Combat.hostiles_near(get_tree(), global_position, faction_def.garrison_turret_range + HIT_RADIUS, faction)
	var pool := CombatWorld.projectiles_of(get_tree())
	for ti in _turrets.size():
		var t := _turrets[ti]
		var node := t["node"] as Node3D
		if retarget:
			t["target"] = _pick_for(t, near, ti)
		var tg := t["target"] as Node3D
		var want := float(t["rest"])
		var ok := false
		if Combat.is_live_target(tg):
			var y := _yaw_to(node, tg.global_position)
			if absf(angle_difference(float(t["rest"]), y)) <= TURRET_ARC:
				want = y
				ok = true
		node.rotation.y = rotate_toward(node.rotation.y, want, TURRET_TURN * dt)
		t["cooldown"] = float(t["cooldown"]) - dt
		if not ok or float(t["cooldown"]) > 0.0 or absf(angle_difference(node.rotation.y, want)) > 0.12 or pool == null:
			continue
		t["cooldown"] = 1.0 / faction_def.garrison_turret_rate
		var muzzles: Array[Node3D] = t["muzzles"]
		var from := node.global_position + Vector3.UP * 5.0
		if not muzzles.is_empty():
			t["side"] = (int(t["side"]) + 1) % muzzles.size()
			from = muzzles[int(t["side"])].global_position
		var tp := tg.global_position
		var hits := _rng.randf() < TURRET_ACCURACY * (1.0 - float(tg.call(&"get_dodge")))
		var aim := tp + ((tg.call(&"get_aim_velocity") as Vector3) - get_aim_velocity()) * (from.distance_to(tp) / ProjectilePool.SPEED)
		if not hits:
			aim += Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.4, 0.4), _rng.randf_range(-1.0, 1.0)).normalized() * 28.0
		pool.fire(from, aim, tg, faction_def.garrison_turret_damage, hits, self, Combat.HOSTILE_TRACER)


## A hostile inside the turret's arc (its last target while still valid).
## The turrets spread out: turret [param index] takes the index-th of the
## nearest ones in its arc, so several attackers share the flak.
func _pick_for(t: Dictionary, near: Array[Node3D], index: int) -> Node3D:
	var node := t["node"] as Node3D
	var cur := t["target"] as Node3D
	if Combat.is_live_target(cur) and near.has(cur) and absf(angle_difference(float(t["rest"]), _yaw_to(node, cur.global_position))) <= TURRET_ARC:
		return cur
	var in_arc: Array[Node3D] = []
	for h in near:
		if absf(angle_difference(float(t["rest"]), _yaw_to(node, h.global_position))) <= TURRET_ARC:
			in_arc.append(h)
	if in_arc.is_empty():
		return null
	return in_arc[index % mini(in_arc.size(), 3)]


## Turret yaw (in its parent's frame) that points local -Z at [param world_pos].
func _yaw_to(node: Node3D, world_pos: Vector3) -> float:
	var parent := node.get_parent() as Node3D
	var local := parent.to_local(world_pos) - node.position
	return atan2(-local.x, -local.z)


# --- Look ---------------------------------------------------------------------------------

func _animate() -> void:
	if dead:
		return
	var t := Time.get_ticks_msec() * 0.001
	var pulse := 0.65 + 0.35 * sin(t * 1.5)
	for i in _glow_mats.size():
		_glow_mats[i].emission_energy_multiplier = _glow_base[i] * pulse
	_hangar_light.light_energy = 2.0 + 2.5 * pulse
	# Beacon: a short bright blink every 1.6 s with a soft afterglow.
	var k := fposmod(t / 1.6, 1.0)
	var blink := 1.0 if k < 0.12 else maxf(0.0, 1.0 - (k - 0.12) * 4.0) * 0.5 + 0.08
	for i in _beacon_mats.size():
		_beacon_mats[i].emission_energy_multiplier = _beacon_base[i] * (0.3 + 3.2 * blink)
	_beacon_light.light_energy = 3.0 * blink
	var f := 0.92 + 0.08 * sin(t * 3.1)
	for i in _light_mats.size():
		_light_mats[i].emission_energy_multiplier = _light_base[i] * f


func _apply_ruined_look() -> void:
	for path in ["garrison_lights", "garrison_hangar_glow", "beacon_light"]:
		var n := _model.find_child(path, true, false) as Node3D if _model else null
		if n:
			n.visible = false
	_hangar_light.visible = false
	_beacon_light.visible = false
	for mi in ModelLoader.meshes_of(_model):
		if mi.visible:
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.14, 0.13, 0.13)
			m.roughness = 1.0
			m.emission_enabled = true
			m.emission = Color(1.0, 0.3, 0.08)
			m.emission_energy_multiplier = 0.12
			mi.material_override = m

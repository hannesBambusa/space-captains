class_name PlanetClaims
extends Node
## Faction planet claims (phase C3). Lives under CombatWorld.
##
## A claim is a ClaimGarrison in orbit of a planet or moon (one per body).
## While it stands landers refuse planet raids there ([method claim_reason]),
## the planet panel shows the owner, the garrison and its patrols, and the
## planet's label is tinted in the faction colour.
##
## Claims come from the ThreatDirector (a new faction claims its
## DenDef.claim_planet before its base arrives: [method claim]) and from
## re-claims: when a garrison is destroyed the planet is unclaimed and the
## faction comes back after FactionDef.reclaim_delay (only while it still
## has a base in the system; otherwise it checks again every
## [constant RETRY_CHECK] s). [constant WARN_LEAD] s ahead a "Long-range
## scans" line and toast warn; then a claim group warps in
## [constant GROUP_DISTANCE] from the claim site, on the side of the
## faction's nearest base: a ClaimConstructor and FactionDef.claim_escorts
## escorts that guard it. At the site it deploys for
## ClaimConstructor.DEPLOY_TIME s (a hologram of the garrison fills up);
## then the garrison stands and the escorts become its patrols. Shooting
## the constructor down ends the attempt and the faction tries again
## after a new delay. Destroyed garrisons stay as wrecks for
## [constant WRECK_TIME] s; their patrols withdraw (warp out once clear).

signal changed

const GROUP := "planet_claims"
const WARN_LEAD := 90.0
const GROUP_DISTANCE := 5500.0
const WRECK_TIME := 120.0
const RETRY_CHECK := 60.0
## Escorts guard their constructor this far out, metres.
const ESCORT_RADIUS := 1500.0

enum Phase { WAITING, EN_ROUTE, DEPLOYING }

var garrisons: Array[ClaimGarrison] = []
## Pending re-claims: {planet: String, faction: StringName, gang: String,
## angle: float, at: float (SimClock.time the group arrives), warned: bool,
## attempt: int, phase: Phase, constructor: ClaimConstructor, escorts:
## Array[ScavengerShip], hologram: Node3D}.
var reclaims: Array[Dictionary] = []
## [garrison, SimClock.time to free it].
var _wrecks: Array = []
var _rng := RandomNumberGenerator.new()


static func of(n: Node) -> PlanetClaims:
	var w := CombatWorld.of(n)
	return w.claims if w and w.claims and w.claims.is_in_group(GROUP) else null


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(SimStepper.GROUP)
	_rng.randomize()


func _process(_delta: float) -> void:
	if not SimClock.paused:
		sim_step(0.0)


# --- Queries ------------------------------------------------------------------

## The live garrison holding [param body], or null.
func garrison_of(body: Node3D) -> ClaimGarrison:
	for g in garrisons:
		if is_instance_valid(g) and g.is_alive() and g.planet == body:
			return g
	return null


## "Claimed by Redwake Corsairs, garrison in orbit", or "" when [param body] is free.
static func claim_reason(body: Node3D) -> String:
	if body == null or not body.is_inside_tree():
		return ""
	var pc := of(body)
	var g := pc.garrison_of(body) if pc else null
	if g == null:
		return ""
	return "Claimed by %s, garrison in orbit" % owner_name(g)


## "Redwake Corsairs" (gang and faction).
static func owner_name(g: ClaimGarrison) -> String:
	if g.gang.is_empty() or g.gang == g.faction_def.display_name:
		return g.faction_def.display_name
	return "%s %s" % [g.gang, g.faction_def.display_name]


## The re-claim pending on [param body] ({} when none).
func reclaim_of(body: Node3D) -> Dictionary:
	var pb := body as PlanetBody
	if pb == null:
		return {}
	for r in reclaims:
		if String(r["planet"]) == pb.def.name:
			return r
	return {}


## Planet panel line for a pending re-claim on [param body] ("" when none).
func reclaim_text(body: Node3D) -> String:
	var r := reclaim_of(body)
	if r.is_empty():
		return ""
	match int(r["phase"]):
		Phase.DEPLOYING:
			var c := r.get("constructor") as ClaimConstructor
			return "%s is deploying a garrison, %d%%" % [r["gang"], roundi(c.deploy_progress * 100.0) if is_instance_valid(c) else 0]
		Phase.EN_ROUTE:
			return "%s claim group on its way to the claim site" % r["gang"]
	if bool(r["warned"]):
		return "%s claim group expected in %s" % [r["gang"], Fmt.clock(maxf(float(r["at"]) - SimClock.time, 0.0))]
	return "%s will try to re-claim it, in about %d min" % [r["gang"], maxi(roundi((float(r["at"]) - SimClock.time) / 60.0), 1)]


# --- Claiming -----------------------------------------------------------------

## Puts a garrison of [param fdef] over [param body] ([param angle] NAN =
## the lit side). [param effect] plays the warp-in look. Null when the body
## is claimed already.
func claim(body: PlanetBody, fdef: FactionDef, gang: String, effect: bool = true, angle: float = NAN, initial_patrols: bool = true) -> ClaimGarrison:
	if body == null or garrison_of(body) != null:
		return null
	var a := ClaimGarrison.default_angle(body) if is_nan(angle) else angle
	var g := ClaimGarrison.new()
	g.setup_claim(body, fdef, gang, a)
	g.claimed_at = SimClock.time
	g.skip_initial_spawns = not initial_patrols
	g.position = ClaimGarrison.site_local(body, a)
	g.rotation.y = ClaimGarrison.site_yaw(a)
	body.add_child(g)
	_register(g)
	if effect:
		g.play_arrival()
	_abort_landers(body)
	changed.emit()
	return g


func _register(g: ClaimGarrison) -> void:
	garrisons.append(g)
	g.destroyed.connect(_on_garrison_destroyed)
	var sys := _system()
	if sys:
		sys.add_garrison(g)
		sys.tint_body_label(g.planet, g.faction_def.color.lerp(Color.WHITE, 0.25))


## Landers on their way to a newly claimed world turn back.
func _abort_landers(body: PlanetBody) -> void:
	for n in SystemWorld.nodes_in(self, Ship.GROUP):
		var lb := (n as Ship).brain as LanderBrain if n is Ship else null
		if lb:
			lb.check_claim(body)


func _on_garrison_destroyed(den: ScavengerDen, killer: Node3D) -> void:
	var g := den as ClaimGarrison
	if g == null:
		return
	garrisons.erase(g)
	var sys := _system()
	if sys:
		sys.remove_garrison(g)
		if is_instance_valid(g.planet):
			sys.tint_body_label(g.planet, Color(0, 0, 0, 0))
	for s in g.spawns + g.raiders:
		if is_instance_valid(s) and s.ai:
			s.ai.withdraw = true
	_wrecks.append([g, SimClock.time + WRECK_TIME])
	var where := g.planet.def.name if is_instance_valid(g.planet) else "?"
	var by := Combat.by_suffix(killer)
	EventLog.post("%s is unclaimed: the %s garrison was destroyed%s" % [where, g.gang, by], EventLog.Kind.REWARD, g.planet, Vector3.INF, "", g.faction_def.id)
	_toast("Claim broken: %s is unclaimed" % where)
	reclaims.append({"planet": where, "faction": g.faction_def.id, "gang": g.gang, "angle": g.site_angle,
			"at": SimClock.time + _delay(g.faction_def, 1), "warned": false, "attempt": 1, "phase": Phase.WAITING})
	changed.emit()


func _delay(fdef: FactionDef, attempt: int) -> float:
	var r := fdef.reclaim_delay
	return _rng.randf_range(r.x, maxf(r.y, r.x)) * (1.0 + 0.15 * float(maxi(attempt - 1, 0)))


# --- Stepping -----------------------------------------------------------------

func sim_step(_dt: float) -> void:
	var now := SimClock.time
	for i in range(_wrecks.size() - 1, -1, -1):
		var w: Array = _wrecks[i]
		if now >= float(w[1]):
			if is_instance_valid(w[0]):
				(w[0] as Node).queue_free()
			_wrecks.remove_at(i)
	for r in reclaims.duplicate():
		match int(r["phase"]):
			Phase.WAITING:
				_step_waiting(r, now)
			Phase.EN_ROUTE, Phase.DEPLOYING:
				var c := r.get("constructor") as ClaimConstructor
				if not is_instance_valid(c) or c.dead:
					_fail(r, null)
				elif int(r["phase"]) == Phase.DEPLOYING:
					_update_hologram(r)


func _step_waiting(r: Dictionary, now: float) -> void:
	var fdef := Factions.get_def(StringName(r["faction"]))
	var body := PlanetRaidContract.find_planet(self, String(r["planet"]))
	if body == null or garrison_of(body) != null:
		reclaims.erase(r)
		changed.emit()
		return
	if not bool(r["warned"]):
		if now < float(r["at"]) - WARN_LEAD:
			return
		if not _faction_present(fdef):
			r["at"] = now + WARN_LEAD + RETRY_CHECK
			return
		r["warned"] = true
		var text := "Long-range scans: %s is moving to re-claim %s, claim group in %s" % [r["gang"], body.def.name, Fmt.clock(maxf(float(r["at"]) - now, 0.0))]
		EventLog.post(text, EventLog.Kind.THREAT, body, Vector3.INF, "", fdef.id)
		_toast(text)
		changed.emit()
		return
	if now >= float(r["at"]):
		_launch(r, body, fdef)


## Has [param fdef] a base (not a garrison) standing in the system?
func _faction_present(fdef: FactionDef) -> bool:
	var sys := _system()
	if sys == null:
		return false
	for d in sys.dens:
		if is_instance_valid(d) and d.is_alive() and d.is_raid_base() and d.faction_def.id == fdef.id:
			return true
	return false


## Warps the claim group in (see the class notes).
func _launch(r: Dictionary, body: PlanetBody, fdef: FactionDef) -> void:
	var site := body.to_global(ClaimGarrison.site_local(body, float(r["angle"])))
	var dir := Vector3(cos(float(r["angle"])), 0.0, sin(float(r["angle"])))
	var base := _nearest_base(fdef, site)
	if base:
		var to := base.global_position - site
		to.y = 0.0
		if to.length() > 1.0:
			dir = to.normalized()
	var at := site + dir * GROUP_DISTANCE + Vector3.UP * 250.0
	var root := SpaceNav.space_root(self)
	WarpFx.flash(self, at, 90.0)
	var c := ClaimConstructor.new()
	c.setup_constructor(body, float(r["angle"]), fdef, String(r["gang"]))
	root.add_child(c)
	c.global_position = at
	c.set_heading(ShipMover.yaw_for(-dir))
	c.mover.avoid_enabled = true
	var world := CombatWorld.of(self)
	if world:
		world.notify_spawned(c)
	var escorts: Array[ScavengerShip] = []
	var pool := fdef.name_pool
	for i in fdef.claim_escorts:
		var s := ScavengerShip.new()
		var word: String = pool[_rng.randi() % pool.size()] if not pool.is_empty() else String(r["gang"])
		s.setup_scavenger(null, "%s-%d" % [word, 70 + i + 3 * int(r["attempt"])], false, fdef)
		root.add_child(s)
		var off := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized() * _rng.randf_range(120.0, 260.0)
		s.global_position = at + off
		s.set_heading(c.mover.yaw)
		s.mover.avoid_enabled = true
		if s.ai:
			s.ai.state = ScavengerBrain.State.ROAMING
			s.ai.set_guard(c, ESCORT_RADIUS)
		escorts.append(s)
		if world:
			world.notify_spawned(s)
	_link(r, c, escorts)
	r["phase"] = Phase.EN_ROUTE
	EventLog.post("%s claim group arrived near %s: a constructor and %d escorts" % [r["gang"], body.def.name, escorts.size()], EventLog.Kind.THREAT, c, Vector3.INF, "", fdef.id)
	changed.emit()


func _link(r: Dictionary, c: ClaimConstructor, escorts: Array[ScavengerShip]) -> void:
	r["constructor"] = c
	r["escorts"] = escorts
	c.deploy_started.connect(_on_deploy_started.bind(r))
	c.deployed.connect(_on_deployed.bind(r))
	c.destroyed.connect(func(_s: Ship, killer: Node3D) -> void: _fail(r, killer))


func _nearest_base(fdef: FactionDef, from: Vector3) -> ScavengerDen:
	var sys := _system()
	var best: ScavengerDen = null
	var best_d := INF
	if sys:
		for d in sys.dens:
			if is_instance_valid(d) and d.is_alive() and d.is_raid_base() and d.faction_def.id == fdef.id:
				var dist := d.global_position.distance_to(from)
				if dist < best_d:
					best_d = dist
					best = d
	return best


func _on_deploy_started(c: ClaimConstructor, r: Dictionary) -> void:
	if not reclaims.has(r):
		return
	r["phase"] = Phase.DEPLOYING
	_make_hologram(r, c)
	var text := "Faction claim: %s is deploying a garrison over %s (%d s)" % [r["gang"], c.planet.def.name, roundi(ClaimConstructor.DEPLOY_TIME * (1.0 - c.deploy_progress))]
	EventLog.post(text, EventLog.Kind.THREAT, c, Vector3.INF, "", c.faction_def.id)
	_toast(text)
	changed.emit()


func _on_deployed(c: ClaimConstructor, r: Dictionary) -> void:
	if not reclaims.has(r):
		return
	reclaims.erase(r)
	_free_hologram(r)
	var live: Array[ScavengerShip] = []
	for o in r.get("escorts", []):
		if is_instance_valid(o) and not (o as ScavengerShip).dead:
			live.append(o as ScavengerShip)
	var g := claim(c.planet, c.faction_def, c.gang, false, c.site_angle, live.is_empty())
	WarpFx.flash(self, c.global_position, 60.0)
	c.leave_map()
	if g == null:
		return
	g.play_arrival()
	for s in live:
		g.adopt(s)
	var text := "Faction claim: %s re-claimed %s, garrison in orbit" % [g.gang, g.planet.def.name]
	EventLog.post(text, EventLog.Kind.THREAT, g, Vector3.INF, "", g.faction_def.id)
	_toast(text)


## The constructor is gone before it deployed: the re-claim fails and the
## faction tries again later.
func _fail(r: Dictionary, killer: Node3D) -> void:
	if not reclaims.has(r) or int(r["phase"]) == Phase.WAITING:
		return
	_free_hologram(r)
	for o in r.get("escorts", []):
		if is_instance_valid(o) and (o as ScavengerShip).ai:
			(o as ScavengerShip).ai.withdraw = true
	r.erase("constructor")
	r.erase("escorts")
	var by := Combat.by_suffix(killer)
	var fdef := Factions.get_def(StringName(r["faction"]))
	EventLog.post("%s held: the %s constructor was shot down%s" % [r["planet"], r["gang"], by], EventLog.Kind.REWARD, null, Vector3.INF, "", fdef.id)
	_toast("%s held: the %s re-claim was stopped" % [r["planet"], r["gang"]])
	r["attempt"] = int(r["attempt"]) + 1
	r["at"] = SimClock.time + _delay(fdef, int(r["attempt"]))
	r["warned"] = false
	r["phase"] = Phase.WAITING
	changed.emit()


# --- Deploy hologram ---------------------------------------------------------------

func _make_hologram(r: Dictionary, c: ClaimConstructor) -> void:
	_free_hologram(r)
	var holo := Node3D.new()
	holo.name = "ClaimHologram"
	var model := ModelLoader.instantiate(ClaimGarrison.MODEL, ModelLoader.building_placeholder.bind(64.0, c.faction_def.color))
	holo.add_child(model)
	MeshUtil.set_layers_recursive(model, ScavengerDen.RENDER_LAYER)
	var mat := c.faction_def.holo_material(5.0)
	for mi in ModelLoader.meshes_of(model):
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holo.set_meta(&"mat", mat)
	holo.position = ClaimGarrison.site_local(c.planet, c.site_angle)
	holo.rotation.y = ClaimGarrison.site_yaw(c.site_angle)
	c.planet.add_child(holo)
	r["hologram"] = holo
	_update_hologram(r)


func _update_hologram(r: Dictionary) -> void:
	var holo := r.get("hologram") as Node3D
	var c := r.get("constructor") as ClaimConstructor
	if not is_instance_valid(holo) or not is_instance_valid(c):
		return
	var mat := holo.get_meta(&"mat") as ShaderMaterial
	mat.set_shader_parameter("fill_y", holo.global_position.y + lerpf(-20.0, 52.0, c.deploy_progress))


func _free_hologram(r: Dictionary) -> void:
	var holo := r.get("hologram") as Node3D
	if is_instance_valid(holo):
		holo.queue_free()
	r.erase("hologram")


# --- Save ---------------------------------------------------------------------

## Claim metadata; the garrisons' own state is saved with the dens
## (SolarSystem.dens), their ships with the other ships.
func save_state() -> Dictionary:
	var gs := []
	for g in garrisons:
		if is_instance_valid(g) and g.is_alive():
			gs.append({"name": g.def.name, "planet": g.planet.def.name, "faction": String(g.faction_def.id), "gang": g.gang,
					"angle": g.site_angle, "claimed_at": g.claimed_at})
	var rs := []
	for r in reclaims:
		var d := {}
		for k in ["planet", "gang", "angle", "at", "warned", "attempt", "phase"]:
			d[k] = r[k]
		d["faction"] = String(r["faction"])
		var c := r.get("constructor") as ClaimConstructor
		d["constructor"] = SaveIds.of(c) if is_instance_valid(c) and not c.dead else 0
		d["escorts"] = SaveUtil.ids(r.get("escorts", []), true)
		rs.append(d)
	return {"garrisons": gs, "reclaims": rs}


## Before the dens are matched (GameSnapshot): rebuilds the garrisons so
## their saved den state, ships and bounties find them.
func load_state(d: Dictionary) -> void:
	for g in garrisons:
		if is_instance_valid(g):
			g.queue_free()
	garrisons.clear()
	reclaims.clear()
	for gd: Dictionary in d.get("garrisons", []):
		var body := PlanetRaidContract.find_planet(self, String(gd.get("planet", "")))
		if body == null:
			continue
		var g := ClaimGarrison.new()
		g.setup_claim(body, Factions.get_def(StringName(gd.get("faction", ""))), String(gd.get("gang", "")), float(gd.get("angle", 0.0)))
		g.claimed_at = float(gd.get("claimed_at", 0.0))
		g.skip_initial_spawns = true
		g.position = ClaimGarrison.site_local(body, g.site_angle)
		g.rotation.y = ClaimGarrison.site_yaw(g.site_angle)
		body.add_child(g)
		_register(g)
	for rd: Dictionary in d.get("reclaims", []):
		var r := {}
		for k in ["planet", "gang", "angle", "at", "warned", "attempt", "phase"]:
			r[k] = rd.get(k)
		r["faction"] = StringName(rd.get("faction", ""))
		r["phase"] = int(r["phase"]) if r["phase"] != null else Phase.WAITING
		r["_constructor_id"] = int(rd.get("constructor", 0))
		r["_escort_ids"] = rd.get("escorts", [])
		reclaims.append(r)
	changed.emit()


## After the ships exist: links claim groups to their constructor and
## escorts. A group whose constructor is gone tries again later.
func restore_links(refs: SaveRefs) -> void:
	for r in reclaims.duplicate():
		var cid := int(r.get("_constructor_id", 0))
		var ids: Array = r.get("_escort_ids", [])
		r.erase("_constructor_id")
		r.erase("_escort_ids")
		if int(r["phase"]) == Phase.WAITING:
			continue
		var c := refs.ship(cid) as ClaimConstructor
		if c == null:
			r["phase"] = Phase.WAITING
			r["warned"] = false
			r["at"] = SimClock.time + RETRY_CHECK
			continue
		var escorts: Array[ScavengerShip] = []
		for id in ids:
			var s := refs.ship(int(id)) as ScavengerShip
			if s:
				escorts.append(s)
				if s.ai:
					s.ai.set_guard(c, ESCORT_RADIUS)
		_link(r, c, escorts)
		if int(r["phase"]) == Phase.DEPLOYING:
			_make_hologram(r, c)


func _system() -> SolarSystem:
	return SolarSystem.of(self)


func _toast(text: String) -> void:
	var pm := get_tree().root.get_node_or_null(^"PauseMenu")
	if pm and pm.has_method(&"toast"):
		pm.call(&"toast", text)

class_name LanderShip
extends MinerShip
## A hired lander: a Raider Dock pilot flying a dropship on planet raid
## contracts (PlanetRaidContract, phase C2). The trip is the miner's
## (undock, cruise, work, return, unload into the dock's stock, rest; flee
## and lose cargo to scavengers on the way), the work is a landing:
## - approach: cruise to an entry point just outside the planet's
##   atmosphere, on the side facing home and lifted toward the camera
##   ([constant ENTRY_LIFT_DEG]), riding along with the planet's orbit;
## - descent ([member PlanetRaidRules.descent_time]): a dive along the
##   curve of the planet down to the surface, heating up (a re-entry glow
##   and an orange trail that read from the RTS camera), the model
##   shrinking a little as it sinks into the haze;
## - surface ([member PlanetRaidRules.surface_time], scaled by the Landing
##   skill and the hold): parked on the surface, the cargo pod lowered,
##   a dust ring at touchdown;
## - climb ([member PlanetRaidRules.climb_time]): back up to the entry point
##   with a hot engine trail, then home like a miner.
## The landing is flown here (positions relative to the moving planet), not
## by the ShipMover. Landed or in the atmosphere the dropship cannot be shot
## and does not flee (planet defences come in C4). One load is the planet's
## yield (PlanetRaidRules.base_yield) times the cargo stat.
## Model: assets/models/ships/dropship.glb (nose -Z, "dropship_pod" under
## the hull, "engine_glow" plume on +Z).

const POD_NODE := "dropship_pod"
## Entry point lift above the planet's orbit plane, degrees (top-down camera).
const ENTRY_LIFT_DEG := 38.0
## How far the landing site lies from the entry direction, toward the top.
const SITE_TILT := 0.35
## Entry point gap outside the planet's visible reach, metres.
const ENTRY_GAP := 70.0
## Hover height over the surface while landed, metres.
const SURFACE_HOVER := 3.0
## Pod drop while landed, metres, and the time it takes, sim seconds.
const POD_DROP := 2.6
const POD_TIME := 2.5
## Model scale at the surface (it shrinks into the haze on the way down).
const SURFACE_SCALE := 0.75

const PHASE_APPROACH := "approach"
const PHASE_DESCENT := "descent"
const PHASE_SURFACE := "surface"
const PHASE_CLIMB := "climb"

var _pod: Node3D
var _pod_base := Vector3.ZERO
var _land_basis := Basis.IDENTITY
var _heat: MeshInstance3D
var _heat_mat: StandardMaterial3D
var _trail: MeshInstance3D
var _trail_mat: StandardMaterial3D
var _dust: MeshInstance3D
var _dust_mat: StandardMaterial3D


func _init() -> void:
	role = Role.LANDER


func _make_brain() -> CaptainBrain:
	return LanderBrain.new(self, LanderEvaluator.new())


func _on_ready_ship() -> void:
	super._on_ready_ship()
	role = Role.LANDER
	_pod = _model.find_child(POD_NODE, true, false) as Node3D if _model else null
	if _pod:
		_pod_base = _pod.position
	_make_fx()
	if not Research.tech_completed.is_connected(_on_tech_completed):
		Research.tech_completed.connect(_on_tech_completed)


## Heavy dropships and armoured hulls apply at once (ShipLoadout.derive).
func _on_tech_completed(t: TechDef) -> void:
	if t and (t.id == ShipLoadout.HEAVY_DROPSHIPS or t.id == ShipLoadout.ARMOURED_DROPSHIPS) and not dead:
		refit()


# --- Job hooks ----------------------------------------------------------------

func _raid(trip: CaptainBrain.Trip) -> PlanetRaidContract:
	return trip.contract as PlanetRaidContract if trip else null


func _planet(trip: CaptainBrain.Trip) -> PlanetBody:
	var rc := _raid(trip)
	return rc.planet if rc and is_instance_valid(rc.planet) and rc.planet.is_inside_tree() else null


func job_begin(trip: CaptainBrain.Trip) -> bool:
	var p := _planet(trip)
	if p == null:
		return false
	var rules := PlanetRaidContract.rules()
	var flat := global_position - p.global_position
	flat.y = 0.0
	if flat.length() < 1.0:
		flat = Vector3.RIGHT
	flat = flat.normalized().rotated(Vector3.UP, _rng.randf_range(-0.5, 0.5))
	var lift := deg_to_rad(ENTRY_LIFT_DEG + _rng.randf_range(-8.0, 8.0))
	var n := (flat * cos(lift) + Vector3.UP * sin(lift)).normalized()
	var n2 := n.slerp(Vector3.UP, SITE_TILT).rotated(Vector3.UP, _rng.randf_range(-0.35, 0.35)).normalized()
	var cargo_full := stats.cargo if stats else 1.0
	trip.meta["phase"] = PHASE_APPROACH
	trip.meta["t"] = 0.0
	trip.meta["n"] = n
	trip.meta["n2"] = n2
	trip.meta["cargo_full"] = cargo_full
	trip.meta["units"] = roundi(float(rules.base_yield(p.def)) * cargo_full)
	trip.ore = _raid(trip).loot
	trip.work_time = rules.surface_time_of(p.def) * (stats.drill_mult if stats else 1.0) * load_time_scale()
	trip.progress = 0.0
	trip.cargo = cargo_full
	return true


## Distance of the entry point from the planet's centre, metres.
func entry_radius(p: PlanetBody) -> float:
	return SpaceNav.body_reach(p.def) + SpaceNav.SHIP_MARGIN + ENTRY_GAP


func entry_point(trip: CaptainBrain.Trip) -> Vector3:
	var p := _planet(trip)
	if p == null or not trip.meta.has("n"):
		return global_position
	return p.global_position + (trip.meta["n"] as Vector3) * entry_radius(p)


func job_target(trip: CaptainBrain.Trip, _working: bool) -> Dictionary:
	var p := _planet(trip)
	if p == null or not trip.meta.has("n"):
		return {}
	var pos := entry_point(trip)
	var out := {"pos": pos, "vel": SpaceNav.world_velocity(p)}
	if SpaceNav.flat_distance(pos, global_position) < 200.0:
		out["face"] = Vector3(p.global_position.x - pos.x, 0.0, p.global_position.z - pos.z)
	return out


## Close enough to the entry point to start the descent.
func near_entry(trip: CaptainBrain.Trip) -> bool:
	return _planet(trip) != null and global_position.distance_to(entry_point(trip)) < 45.0


func phase_of(trip: CaptainBrain.Trip) -> String:
	return String(trip.meta.get("phase", PHASE_APPROACH)) if trip else ""


## True while the landing flies the ship (descent, surface, climb).
func landing_active() -> bool:
	if brain == null or brain.state != CaptainBrain.State.MINING or brain.trip == null:
		return false
	var ph := phase_of(brain.trip)
	return ph == PHASE_DESCENT or ph == PHASE_SURFACE or ph == PHASE_CLIMB


func job_work(trip: CaptainBrain.Trip, dt: float) -> bool:
	var p := _planet(trip)
	if p == null:
		return false
	var rules := PlanetRaidContract.rules()
	var t := float(trip.meta.get("t", 0.0)) + dt
	match phase_of(trip):
		PHASE_APPROACH:
			trip.meta["phase"] = PHASE_DESCENT
			trip.meta["from"] = global_position - p.global_position
			t = 0.0
		PHASE_DESCENT:
			if t >= rules.descent_time:
				trip.meta["phase"] = PHASE_SURFACE
				t = 0.0
		PHASE_SURFACE:
			trip.progress = clampf(trip.progress + dt / maxf(trip.work_time, 0.1), 0.0, 1.0)
			hold_fill = trip.progress
			hold_ore = trip.ore
			if trip.progress >= 1.0:
				trip.meta["phase"] = PHASE_CLIMB
				t = 0.0
		PHASE_CLIMB:
			if t >= rules.climb_time:
				trip.meta["t"] = 0.0
				trip.meta["phase"] = PHASE_APPROACH
				_leave_orbit(p, trip)
				return true
	trip.meta["t"] = t
	if landing_active():
		_place_landing()
	return false


## Back at the entry point, flying on with the planet.
func _leave_orbit(p: PlanetBody, trip: CaptainBrain.Trip) -> void:
	var out := entry_point(trip)
	global_position = out
	var v := SpaceNav.world_velocity(p)
	mover.velocity = Vector3(v.x, 0.0, v.z)
	mover.climb_rate = v.y
	var away := (trip.meta["n"] as Vector3)
	away.y = 0.0
	if away.length() > 0.01:
		mover.yaw = ShipMover.yaw_for(away.normalized())
		rotation = Vector3(0.0, mover.yaw, 0.0)
	mover.hold()
	_land_basis = Basis.IDENTITY
	hold_fill = 1.0


func job_end(trip: CaptainBrain.Trip) -> void:
	super.job_end(trip)
	if trip and trip.meta.has("phase") and phase_of(trip) != PHASE_APPROACH:
		# Aborted mid-landing (contract gone): back out at the entry point.
		var p := _planet(trip)
		if p:
			_leave_orbit(p, trip)
		trip.meta["phase"] = PHASE_APPROACH
	_set_fx(0.0, 0.0, Color.WHITE, 0.0)


## Where the landing puts the ship now, relative to the moving planet:
## {pos, fwd (motion), up, k (0 at the entry point .. 1 on the surface)}.
func landing_pose(trip: CaptainBrain.Trip) -> Dictionary:
	var p := _planet(trip)
	if p == null:
		return {}
	var rules := PlanetRaidContract.rules()
	var c := p.global_position
	var n: Vector3 = trip.meta["n"]
	var n2: Vector3 = trip.meta["n2"]
	var r_top := entry_radius(p)
	var r_low := p.def.radius + SURFACE_HOVER
	var t := float(trip.meta.get("t", 0.0))
	match phase_of(trip):
		PHASE_DESCENT:
			var from: Vector3 = trip.meta.get("from", n * r_top)
			var k := clampf(t / maxf(rules.descent_time, 0.1), 0.0, 1.0)
			return _arc_pose(c, from, n2 * r_low, k, false)
		PHASE_CLIMB:
			var k2 := clampf(t / maxf(rules.climb_time, 0.1), 0.0, 1.0)
			return _arc_pose(c, n2 * r_low, n * r_top, k2, true)
		PHASE_SURFACE:
			var fwd := (n - n2 * n.dot(n2))
			fwd = -fwd.normalized() if fwd.length() > 0.01 else n2.cross(Vector3.RIGHT).normalized()
			return {"pos": c + n2 * r_low, "fwd": fwd, "up": n2, "k": 1.0}
	return {}


## Pose on the dive (or climb) between two offsets from the planet centre:
## the direction swings along the sphere, the height falls (rises) late
## (early), so the ship skims the atmosphere before it drops.
func _arc_pose(c: Vector3, a: Vector3, b: Vector3, k: float, climbing: bool) -> Dictionary:
	var pos := _arc_at(c, a, b, k, climbing)
	var ahead := _arc_at(c, a, b, minf(k + 0.02, 1.0), climbing)
	var behind := _arc_at(c, a, b, maxf(k - 0.02, 0.0), climbing)
	var fwd := ahead - behind
	fwd = fwd.normalized() if fwd.length() > 0.001 else (b - a).normalized()
	var up := (pos - c).normalized()
	var depth := 1.0 - (pos - c).length() / maxf(a.length() if not climbing else b.length(), 1.0)
	var top := maxf(a.length(), b.length())
	var low := minf(a.length(), b.length())
	var kk := clampf((top - (pos - c).length()) / maxf(top - low, 1.0), 0.0, 1.0)
	return {"pos": pos, "fwd": fwd, "up": up, "k": kk, "depth": depth}


static func _arc_at(c: Vector3, a: Vector3, b: Vector3, k: float, climbing: bool) -> Vector3:
	var e := k * k * (3.0 - 2.0 * k)
	var dir := a.normalized().slerp(b.normalized(), e)
	var h := pow(k, 1.6) if not climbing else 1.0 - pow(1.0 - k, 1.6)
	return c + dir * lerpf(a.length(), b.length(), h)


func _place_landing() -> void:
	var trip := brain.trip
	var pose := landing_pose(trip)
	if pose.is_empty():
		return
	global_position = pose["pos"]
	var fwd: Vector3 = pose["fwd"]
	var up: Vector3 = pose["up"]
	if absf(fwd.dot(up)) > 0.98:
		up = Vector3.UP if absf(fwd.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	_land_basis = Basis.looking_at(fwd, up)
	var p := _planet(trip)
	var v := SpaceNav.world_velocity(p) if p else Vector3.ZERO
	mover.velocity = Vector3(v.x, 0.0, v.z)
	mover.climb_rate = v.y
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	if flat.length() > 0.05:
		mover.yaw = ShipMover.yaw_for(flat.normalized())


## Flown by the landing while it lasts: no mover, no separation, no shots.
func sim_step(dt: float) -> void:
	if dead:
		return
	if not landing_active():
		super.sim_step(dt)
		return
	durability.step(dt)
	if weapon:
		weapon.step(dt)
	brain.update(dt)
	if not dead and landing_active():
		_place_landing()


## Landed or in the atmosphere: safe until planet defences (C4).
func is_targetable() -> bool:
	return super.is_targetable() and not landing_active()


func _update_beam() -> void:
	_beam.set_active(false)


# --- Visuals ------------------------------------------------------------------

func _apply_visuals(dt: float) -> void:
	super._apply_visuals(dt)
	if _model == null:
		return
	if not landing_active():
		_model.scale = Vector3.ONE
		if _pod:
			_pod.position = _pod_base
		_set_fx(0.0, 0.0, Color.WHITE, 0.0)
		return
	var trip := brain.trip
	var pose := landing_pose(trip)
	if pose.is_empty():
		return
	global_basis = _land_basis
	_model.position = Vector3.ZERO
	_model.rotation = Vector3.ZERO
	var k := float(pose.get("k", 0.0))
	_model.scale = Vector3.ONE * lerpf(1.0, SURFACE_SCALE, k)
	var ph := phase_of(trip)
	var t := float(trip.meta.get("t", 0.0))
	var rules := PlanetRaidContract.rules()
	if _pod:
		var drop := 0.0
		if ph == PHASE_SURFACE:
			var left := trip.work_time * (1.0 - trip.progress)
			drop = clampf(minf(t, left) / POD_TIME, 0.0, 1.0)
		_pod.position = _pod_base + Vector3(0.0, -POD_DROP * drop, 0.0)
	match ph:
		PHASE_DESCENT:
			# Heat peaks in the thick of the atmosphere, then fades near the ground.
			var x := clampf(t / maxf(rules.descent_time, 0.1), 0.0, 1.0)
			var heat := clampf(sin(x * PI) * 1.3, 0.0, 1.0) * (1.0 - smoothstep(0.85, 1.0, x))
			_set_fx(heat, heat, Color(1.0, 0.5, 0.18), 0.0)
		PHASE_CLIMB:
			var y := clampf(t / maxf(rules.climb_time, 0.1), 0.0, 1.0)
			var burn := clampf(0.4 + sin(y * PI) * 0.8, 0.0, 1.0)
			_set_fx(burn * 0.35, burn, Color(0.7, 0.85, 1.0), 0.0)
		PHASE_SURFACE:
			_set_fx(0.0, 0.0, Color.WHITE, clampf(1.0 - t / 2.5, 0.0, 1.0) if t < 2.5 else 0.0, t / 2.5)


func _make_fx() -> void:
	_heat_mat = _additive(Color(1.0, 0.55, 0.2, 0.0))
	_heat = MeshInstance3D.new()
	_heat.name = "ReentryGlow"
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 16
	sph.rings = 8
	_heat.mesh = sph
	_heat.material_override = _heat_mat
	_heat.scale = Vector3(7.0, 5.0, 11.0)
	_heat.position = Vector3(0.0, 0.0, -3.0)
	_heat.visible = false
	_heat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_heat.layers = RENDER_LAYER
	add_child(_heat)
	_trail_mat = _additive(Color(1.0, 0.5, 0.2, 0.0))
	_trail = MeshInstance3D.new()
	_trail.name = "ReentryTrail"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.4
	cyl.bottom_radius = 3.0
	cyl.height = 1.0
	cyl.radial_segments = 10
	cyl.rings = 1
	_trail.mesh = cyl
	_trail.material_override = _trail_mat
	_trail.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	_trail.visible = false
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail.layers = RENDER_LAYER
	add_child(_trail)
	_dust_mat = _additive(Color(0.95, 0.85, 0.7, 0.0))
	_dust = MeshInstance3D.new()
	_dust.name = "TouchdownDust"
	var ring := SphereMesh.new()
	ring.radius = 1.0
	ring.height = 0.6
	ring.radial_segments = 20
	ring.rings = 6
	_dust.mesh = ring
	_dust.material_override = _dust_mat
	_dust.visible = false
	_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dust.layers = RENDER_LAYER
	add_child(_dust)


static func _additive(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
	return m


## Re-entry glow [param heat] 0..1, trail [param trail] 0..1 in
## [param color], touchdown dust alpha [param dust] at growth [param grow].
func _set_fx(heat: float, trail: float, color: Color, dust: float, grow: float = 0.0) -> void:
	if _heat == null:
		return
	_heat.visible = heat > 0.02
	if _heat.visible:
		_heat_mat.albedo_color = Color(color, 0.32 * heat)
		_heat.scale = Vector3(4.5, 3.2, 8.0) * (0.8 + 0.3 * heat)
	_trail.visible = trail > 0.02
	if _trail.visible:
		var length := lerpf(30.0, 160.0, trail)
		_trail_mat.albedo_color = Color(color, 0.32 * trail)
		_trail.scale = Vector3(1.0 + trail * 1.5, length, 1.0 + trail * 1.5)
		_trail.position = Vector3(0.0, 0.0, length * 0.5 + 4.0)
	_dust.visible = dust > 0.02
	if _dust.visible:
		var r := lerpf(6.0, 40.0, clampf(grow, 0.0, 1.0))
		_dust.scale = Vector3(r, r * 0.12, r)
		_dust.position = Vector3(0.0, -2.0, 0.0)
		_dust_mat.albedo_color = Color(0.8, 0.7, 0.58, 0.22 * dust)

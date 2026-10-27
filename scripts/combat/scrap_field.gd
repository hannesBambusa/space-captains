class_name ScrapField
extends Node3D
## Debris left by a destroyed ship or den: a cloud of tumbling, glinting
## chunks (one MultiMesh, shaders/scrap.gdshader) holding [member amount]
## scrap. Fades out and frees itself after [member lifetime] sim seconds.
## Selectable and focusable; listed in the overview.
## Stage 3: salvagers call [method take] (free salvage, or a posted salvage
## contract). While a salvage contract is open on it, or a salvager is on a
## trip to it, the field does not age; a stripped field fades out quickly.
## Den ruins also hold the den's stash ([method add_scrap]).
## Wrecks move with the frame they were made in ([member anchor]): the frame
## the dying ship flew in (station approach, a planet), else the station
## within [constant STATION_REACH], a cluster within [constant CLUSTER_REACH]
## of its rim, or a planet or moon within [constant PLANET_REACH] of its
## reach ([method pick_anchor]); deep space stays fixed. The field stays
## under CombatWorld's ScrapFields node and follows its anchor at a fixed
## anchor-local offset (no reparenting: contracts and the selection watch
## tree_exiting). A lost anchor (a mined-out cluster faded) leaves it fixed
## where it is. Saved by anchor id ("station", "planet:Tavros",
## "cluster:Cinder Cluster") plus the offset.

signal depleted(field: ScrapField)

const GROUP := "scrap_fields"
const SHADER: Shader = preload("res://shaders/scrap.gdshader")
## The last part of the life during which the chunks shrink away, seconds.
const FADE_TIME := 25.0
## Fresh wrecks glow for this long, seconds.
const HOT_TIME := 25.0
## Sim seconds between checks for an open salvage contract or salvager.
const CLAIM_CHECK := 1.0
## Anchor reach: flat distance to the station, to a cluster's rim, and past a
## planet's or moon's reach (rings included), metres.
const STATION_REACH := 5000.0
const CLUSTER_REACH := 1500.0
const PLANET_REACH := 3500.0

var amount: int = 0
var initial_amount: int = 0
var lifetime: float = 180.0
var radius: float = 30.0
var display_name: String = "Scrap field"
var created_at: float = 0.0
## The frame the field moves with (station Structures, PlanetBody,
## AsteroidCluster), null = fixed in space; [member anchor_offset] is
## anchor-local.
var anchor: Node3D
var anchor_offset := Vector3.ZERO

var _age: float = 0.0
var _claimed := false
var _claim_timer := 0.0
var _mat: ShaderMaterial
var _mmi: MultiMeshInstance3D


func setup(scrap: int, life: float, field_radius: float, label: String) -> void:
	amount = scrap
	initial_amount = scrap
	lifetime = life
	radius = field_radius
	display_name = label
	name = StringName(("Scrap_%s" % label).validate_node_name().replace(" ", ""))


static func all(ctx: Node) -> Array[ScrapField]:
	var out: Array[ScrapField] = []
	for n in SystemWorld.nodes_in(ctx, GROUP):
		if n is ScrapField and not n.is_queued_for_deletion():
			out.append(n as ScrapField)
	return out


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(SimStepper.GROUP)
	created_at = SimClock.time
	set_meta(&"focus_radius", radius)
	set_meta(&"focus_distance", maxf(radius * 6.0, 220.0))
	add_to_group(RTSCamera.FOCUS_GROUP)
	_build()


func _process(delta: float) -> void:
	if not SimClock.paused:
		sim_step(delta * SimClock.speed)
	_follow()


func sim_step(dt: float) -> void:
	if dt <= 0.0 or is_queued_for_deletion():
		return
	_follow()
	_claim_timer -= dt
	if _claim_timer <= 0.0:
		_claim_timer = CLAIM_CHECK
		_claimed = amount > 0 and (not ContractBoard.get_for_target(self).is_empty() or SalvageContract.free_in_use(self))
	if not _claimed:
		_age += dt
	var spread := 0.12 + 0.88 * (1.0 - exp(-_age * 0.9))
	if _mmi:
		_mmi.scale = Vector3(spread, 1.0, spread)
	if _mat:
		_mat.set_shader_parameter("fade", clampf((lifetime - _age) / FADE_TIME, 0.0, 1.0))
		_mat.set_shader_parameter("hot", clampf(1.0 - _age / HOT_TIME, 0.0, 1.0))
	if _age >= lifetime:
		queue_free()


func remaining_time() -> float:
	return maxf(lifetime - _age, 0.0)


# --- Anchor -------------------------------------------------------------------

## Makes the field move with [param frame] from where it is now (null = fixed in space).
func anchor_to(frame: Node3D) -> void:
	anchor = frame if is_instance_valid(frame) and frame.is_inside_tree() else null
	if anchor:
		anchor_offset = anchor.to_local(global_position)


## Velocity (m/s, world axes) of the field's frame.
func frame_velocity() -> Vector3:
	return SpaceNav.world_velocity(anchor) if _anchor_live() else Vector3.ZERO


## "Moves with the station", "Moves with Cinder Cluster" or "Fixed in space".
func anchor_text() -> String:
	if not _anchor_live():
		return "Fixed in space"
	if anchor is PlanetBody:
		return "Moves with %s" % (anchor as PlanetBody).def.name
	if anchor is AsteroidCluster:
		return "Moves with %s" % (anchor as AsteroidCluster).def.name
	return "Moves with the station"


func _anchor_live() -> bool:
	return anchor != null and is_instance_valid(anchor) and anchor.is_inside_tree() and not anchor.is_queued_for_deletion()


func _follow() -> void:
	if anchor == null:
		return
	if not _anchor_live():
		# Gone (a cluster faded): stay where it was.
		anchor = null
		return
	global_position = anchor.to_global(anchor_offset)


## The frame a wreck at [param pos] (world) moves with, or null (deep space).
## [param source] is the dying node: the frame it flew in wins; else the
## nearest of the station, a cluster and a planet or moon in reach, by gap
## (a wreck inside a cluster's rim goes with the cluster).
static func pick_anchor(ctx: Node, pos: Vector3, source: Node = null) -> Node3D:
	var mgr := BuildingManager.of(ctx)
	var station: Node3D = mgr.frame if mgr and mgr.frame and mgr.frame.is_inside_tree() else null
	var sys := SolarSystem.of(ctx)
	var n := source.get_parent() if source else null
	while n != null and n != sys:
		if station and (n == station or n == station.get_parent()):
			return station
		if n is PlanetBody or n is AsteroidCluster:
			return n as Node3D
		n = n.get_parent()
	# Nearest by gap (to the station, past a cluster's rim, past a body's reach).
	var best: Node3D = null
	var best_gap := INF
	if station:
		var gap := SpaceNav.flat_distance(pos, station.global_position)
		if gap <= STATION_REACH:
			best_gap = gap
			best = station
	if sys == null:
		return best
	for b in sys.belts:
		if is_instance_valid(b) and b.def and b.is_inside_tree():
			var gap := b.distance_to(pos)
			if gap <= CLUSTER_REACH and gap < best_gap:
				best_gap = gap
				best = b
	for p in sys.planets:
		var bodies: Array[PlanetBody] = [p]
		for c in p.get_children():
			if c is PlanetBody:
				bodies.append(c as PlanetBody)
		for b in bodies:
			var gap := maxf(SpaceNav.flat_distance(pos, b.global_position) - SpaceNav.body_reach(b.def), 0.0)
			if gap <= PLANET_REACH and gap < best_gap:
				best_gap = gap
				best = b
	return best


## Stable save id of [param frame] ("" = fixed in space).
static func anchor_id(frame: Node3D) -> String:
	if frame == null or not is_instance_valid(frame):
		return ""
	if frame is PlanetBody:
		return "planet:" + (frame as PlanetBody).def.name
	if frame is AsteroidCluster:
		return "cluster:" + (frame as AsteroidCluster).def.name
	return "station"


## The frame saved as [param id] in [param ctx]'s system, or null.
static func find_anchor(ctx: Node, id: String) -> Node3D:
	if id == "station":
		var mgr := BuildingManager.of(ctx)
		return mgr.frame if mgr else null
	if id.begins_with("planet:"):
		return PlanetRaidContract.find_planet(ctx, id.trim_prefix("planet:"))
	if id.begins_with("cluster:"):
		var sys := SolarSystem.of(ctx)
		return sys.find_cluster(id.trim_prefix("cluster:")) if sys else null
	return null


func get_display_name() -> String:
	return display_name


func get_status_text() -> String:
	if _claimed:
		return "%d scrap, being salvaged" % amount
	return "%d scrap, fades in %s" % [amount, Fmt.clock(remaining_time())]


func is_claimed() -> bool:
	return _claimed


## Adds scrap (a den's stash spilling into its ruins).
func add_scrap(extra: int) -> void:
	amount += maxi(extra, 0)
	initial_amount += maxi(extra, 0)


## Removes up to [param want] scrap (stage 3 salvage). Returns what was taken.
func take(want: int) -> int:
	var got := mini(want, amount)
	amount -= got
	if amount <= 0 and got > 0:
		_claimed = false
		lifetime = minf(lifetime, _age + FADE_TIME)
		depleted.emit(self)
	return got


func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name) ^ int(SimClock.time * 1000.0)
	var n := clampi(int(radius * 0.9), 18, 120)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mm.mesh = box
	mm.instance_count = n
	for i in n:
		var a := rng.randf() * TAU
		var r := radius * sqrt(rng.randf())
		var p := Vector3(cos(a) * r, rng.randf_range(-4.0, 4.0), sin(a) * r)
		var s := rng.randf_range(0.6, 2.6) * (1.0 if radius < 60.0 else 1.8)
		if rng.randf() < 0.12:
			s *= 2.2
		var b := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU))
		b = b.scaled(Vector3(s * rng.randf_range(0.6, 1.6), s * rng.randf_range(0.2, 0.6), s * rng.randf_range(0.6, 1.4)))
		mm.set_instance_transform(i, Transform3D(b, p))
		var tint := [Color(1, 1, 1), Color(0.8, 0.62, 0.5), Color(0.6, 0.62, 0.56), Color(0.9, 0.9, 0.95)][rng.randi() % 4] as Color
		mm.set_instance_color(i, tint)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Chunks"
	_mmi.multimesh = mm
	_mmi.material_override = _mat
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.layers = 2
	_mmi.custom_aabb = AABB(Vector3(-radius - 10.0, -15.0, -radius - 10.0), Vector3(radius * 2.0 + 20.0, 30.0, radius * 2.0 + 20.0))
	add_child(_mmi)


# --- Save ---------------------------------------------------------------------

func save_state() -> Dictionary:
	var d := SaveUtil.props(self, ["amount", "initial_amount", "lifetime", "radius", "display_name", "created_at", "_age"])
	d["id"] = SaveIds.of(self)
	d["position"] = global_position
	# "" = fixed in space (no key: an older save, anchored again on load).
	d["anchor"] = anchor_id(anchor) if _anchor_live() else ""
	if _anchor_live():
		d["offset"] = anchor_offset
	d["den_ruins"] = bool(get_meta(&"den_ruins", false))
	return d


## A field from [method save_state] (the chunks are rebuilt, not the same
## scatter). Back on its saved anchor at the saved offset; a save without
## one (older, or fixed) is anchored by [method pick_anchor] from its
## position; a saved anchor that is gone leaves it fixed at that position.
static func restore(world: CombatWorld, d: Dictionary) -> ScrapField:
	var sys := SolarSystem.of(world)
	if sys:
		# Bodies where the saved time has them, before positions are compared.
		sys.update_bodies(SimClock.time)
	var pos := d["position"] as Vector3
	var frame: Node3D = null
	var id := String(d.get("anchor", ""))
	if not d.has("anchor"):
		frame = pick_anchor(world, pos)
	elif not id.is_empty():
		frame = find_anchor(world, id)
		if frame and frame.is_inside_tree():
			pos = frame.to_global(d.get("offset", frame.to_local(pos)) as Vector3)
	var f := world.spawn_scrap(pos, int(d["amount"]), float(d["lifetime"]), float(d["radius"]), String(d["display_name"]))
	f.anchor_to(frame)
	f.initial_amount = int(d.get("initial_amount", f.amount))
	f.created_at = float(d.get("created_at", SimClock.time))
	f._age = float(d.get("_age", 0.0))
	if bool(d.get("den_ruins", false)):
		f.set_meta(&"den_ruins", true)
	return f

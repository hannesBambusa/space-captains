class_name ClusterSpawner
extends Node
## Keeps the system stocked with asteroid clusters (AsteroidCluster). When one is
## mined out, a survey finds a new one SystemDef.cluster_respawn sim seconds
## later (sometimes two, up to SystemDef.cluster_max); whenever fewer than
## SystemDef.cluster_min are left, one is on its way. The new cluster takes
## a free orbit (its band clear of every planet, its moons and the home
## station's orbit, so they never meet), a spot clear of the gates and the
## hostile bases, as far as it gets from the other clusters, and a name from
## SystemDef.cluster_names. Rarer ore sits further out: iron inside about
## 16 km, titanium 12 to 31 km, crystal past 24 km. Announced in the feed and
## with a toast ("Survey signal: new iron cluster near Khepri").
## Child of SolarSystem; GameSnapshot saves [method save_state].

## Gap between a cluster's rim and a planet system's reach (orbit bands), metres.
const BAND_MARGIN := 300.0
## Gap kept from gates and hostile bases at the spawn spot, metres.
const POINT_MARGIN := 2500.0
## Rim to rim, at least, from the other clusters at the spawn spot, metres.
const CLUSTER_GAP := 4000.0
## Preferred orbit radius per ore (IRON, TITANIUM, CRYSTAL), metres.
const ORE_RANGES := {
	AsteroidBelt.OreType.IRON: Vector2(9500.0, 20000.0),
	AsteroidBelt.OreType.TITANIUM: Vector2(16000.0, 33000.0),
	AsteroidBelt.OreType.CRYSTAL: Vector2(27000.0, 44000.0),
}
const ORE_WORD := ["rock", "iron", "titanium", "crystal"]

var system: SolarSystem
## Sim times new clusters are due, soonest first.
var due: Array[float] = []
## Next name in SystemDef.cluster_names to try.
var name_index: int = 0
## Clusters surveyed so far (seeds and fallback names).
var spawned: int = 0
var rng := RandomNumberGenerator.new()
## False outside home: nothing new is surveyed.
var enabled := true


func setup(owner_system: SolarSystem) -> void:
	system = owner_system
	# Systems without a station keep their generated clusters (no mining there).
	var w := SystemWorld.of(owner_system)
	enabled = w == null or w.has_station
	rng.randomize()
	system.cluster_added.connect(_on_cluster_added)
	for b in system.belts:
		_on_cluster_added(b)


func _ready() -> void:
	add_to_group(SimStepper.GROUP)


func _process(delta: float) -> void:
	if not SimClock.paused:
		sim_step(delta * SimClock.speed)


func sim_step(_dt: float) -> void:
	if not enabled or system == null or system.system_def == null:
		return
	var sdef := system.system_def
	if active_count() + due.size() < sdef.cluster_min:
		_schedule()
	while not due.is_empty() and SimClock.time >= due[0]:
		due.pop_front()
		if active_count() < sdef.cluster_max:
			spawn()


## Clusters not yet mined out.
func active_count() -> int:
	var n := 0
	for b in system.belts:
		if not b.is_depleted:
			n += 1
	return n


## Sim seconds until the next survey, or -1 when none is due.
func next_in() -> float:
	return due[0] - SimClock.time if not due.is_empty() else -1.0


func _schedule() -> void:
	var r := system.system_def.cluster_respawn
	due.append(SimClock.time + rng.randf_range(r.x, maxf(r.x, r.y)))
	due.sort()


func _on_cluster_added(b: AsteroidCluster) -> void:
	if not b.depleted.is_connected(_on_depleted):
		b.depleted.connect(_on_depleted)


func _on_depleted(b: AsteroidCluster) -> void:
	EventLog.post("%s is mined out" % b.def.name, EventLog.Kind.INFO, null, b.global_position)
	_schedule()
	# Now and then the survey turns up two.
	if active_count() + due.size() + 1 <= system.system_def.cluster_max and rng.randf() < 0.3:
		_schedule()


# --- Spawning -----------------------------------------------------------------

## Surveys a new cluster now and announces it. Returns it (null when no
## spot fits).
func spawn(ore: int = -1) -> AsteroidCluster:
	if ore < 0:
		ore = _pick_ore()
	var bdef := _make_def(ore)
	if bdef == null:
		return null
	var belt := system.add_cluster(bdef)
	var near := _nearest_body_name(belt.global_position)
	var text := "Survey signal: new %s cluster near %s" % [ORE_WORD[ore], near]
	EventLog.post("%s (%s)" % [text, bdef.name], EventLog.Kind.REWARD, belt)
	var pm := get_tree().root.get_node_or_null(^"PauseMenu") if is_inside_tree() else null
	if pm and pm.has_method(&"toast"):
		pm.call(&"toast", text)
	return belt


## Favours the ore the system has fewest clusters of.
func _pick_ore() -> int:
	var have := {AsteroidBelt.OreType.IRON: 0, AsteroidBelt.OreType.TITANIUM: 0, AsteroidBelt.OreType.CRYSTAL: 0}
	for b in system.belts:
		if not b.is_depleted and have.has(b.def.ore_type):
			have[b.def.ore_type] += 1
	var weights := {AsteroidBelt.OreType.IRON: 0.45, AsteroidBelt.OreType.TITANIUM: 0.33, AsteroidBelt.OreType.CRYSTAL: 0.22}
	var total := 0.0
	for o: int in weights:
		weights[o] = float(weights[o]) / float(1 + int(have[o]) * 2)
		total += float(weights[o])
	var pick := rng.randf() * total
	for o: int in weights:
		pick -= float(weights[o])
		if pick <= 0.0:
			return o
	return AsteroidBelt.OreType.IRON


func _make_def(ore: int) -> ClusterDef:
	var bdef := ClusterDef.new()
	bdef.ore_type = ore as AsteroidBelt.OreType
	match ore:
		AsteroidBelt.OreType.IRON:
			bdef.size = rng.randf_range(1200.0, 2200.0)
			bdef.richness = rng.randf_range(0.2, 0.35)
			bdef.vertical_spread = rng.randf_range(220.0, 320.0)
			bdef.max_scale = 18.0
			if rng.randf() < 0.35:
				bdef.secondary_ore = AsteroidBelt.OreType.TITANIUM
				bdef.secondary_share = 0.15
			bdef.dust_color = Color(0.66, 0.52, 0.42, 1.0)
		AsteroidBelt.OreType.TITANIUM:
			bdef.size = rng.randf_range(1400.0, 2600.0)
			bdef.richness = rng.randf_range(0.4, 0.6)
			bdef.vertical_spread = rng.randf_range(320.0, 480.0)
			bdef.secondary_ore = AsteroidBelt.OreType.IRON
			bdef.secondary_share = 0.3
			bdef.dust_color = Color(0.6, 0.6, 0.62, 1.0)
		_:
			bdef.size = rng.randf_range(1800.0, 3000.0)
			bdef.richness = rng.randf_range(0.6, 0.85)
			bdef.vertical_spread = rng.randf_range(500.0, 700.0)
			bdef.max_scale = 23.0
			bdef.glow = rng.randf_range(1.2, 1.6)
			if rng.randf() < 0.5:
				bdef.secondary_ore = AsteroidBelt.OreType.TITANIUM
				bdef.secondary_share = 0.3
			bdef.dust_color = Color(0.5, 0.62, 0.72, 1.0)
	bdef.inclination_deg = rng.randf_range(0.4, 2.2)
	bdef.ascending_node_deg = rng.randf_range(0.0, 360.0)
	var spot := Vector2.ZERO
	for _shrink in 4:
		spot = _pick_spot(bdef, ore)
		if spot.x > 0.0:
			break
		bdef.size = maxf(bdef.size * 0.8, 1000.0)
	if spot.x <= 0.0:
		push_warning("ClusterSpawner: no free spot for a new cluster")
		return null
	bdef.orbit_radius = spot.x
	bdef.start_angle_deg = spot.y
	# Base danger: rarer ore and the outer system are riskier.
	bdef.danger = 1 + (1 if ore == AsteroidBelt.OreType.CRYSTAL else 0) + (1 if bdef.orbit_radius > 30000.0 else 0)
	spawned += 1
	bdef.seed = 1000 + spawned * 37 + rng.randi() % 997
	bdef.name = _next_name()
	return bdef


## (orbit radius, start angle at sim time 0, degrees), x = 0 when nothing fits.
func _pick_spot(bdef: ClusterDef, ore: int) -> Vector2:
	var big_r := bdef.radius()
	var free := free_bands(big_r)
	var want: Vector2 = ORE_RANGES.get(ore, system.system_def.cluster_orbit_range)
	var bands := _clip(free, want)
	if bands.is_empty():
		bands = free
	if bands.is_empty():
		return Vector2.ZERO
	var best := Vector2.ZERO
	var best_score := -INF
	for _try in 40:
		var r := _sample(bands)
		var now_deg := rng.randf_range(0.0, 360.0)
		var a := deg_to_rad(now_deg)
		var pos := Orbiter.inclined_basis(bdef.inclination_deg, bdef.ascending_node_deg) * Vector3(cos(a), 0.0, sin(a)) * r
		if not _clear_of_points(pos, big_r):
			continue
		var gap := INF
		for b in system.belts:
			if b.is_depleted:
				continue
			gap = minf(gap, SpaceNav.flat_distance(pos, b.global_position) - big_r - b.rock_half_width())
		if gap < CLUSTER_GAP:
			continue
		var score := minf(gap, 30000.0)
		if score > best_score:
			best_score = score
			# Start angle such that the orbit puts it at now_deg now.
			var start := now_deg - 360.0 * SimClock.time / (r * ClusterDef.PERIOD_PER_M)
			best = Vector2(r, fposmod(start, 360.0))
	return best


## Radial intervals (x = inner, y = outer) where a cluster of radius
## [param big_r] can orbit without its band meeting a planet, its moons, the
## home station orbit or the star.
func free_bands(big_r: float) -> Array[Vector2]:
	var sdef := system.system_def
	var blocked: Array[Vector2] = []
	blocked.append(Vector2(0.0, sdef.star_radius * 1.25 + big_r + BAND_MARGIN))
	for p in sdef.planets:
		var reach := SpaceNav.body_reach(p)
		for m: PlanetDef in p.moons:
			reach = maxf(reach, m.orbit_radius + SpaceNav.body_reach(m))
		if p.name == sdef.station_planet:
			reach = maxf(reach, sdef.station_orbit_radius + SpaceNav.STATION_PLAN_RADIUS)
		var pad := reach + big_r + BAND_MARGIN
		blocked.append(Vector2(p.orbit_radius - pad, p.orbit_radius + pad))
	var range_v := sdef.cluster_orbit_range
	var out: Array[Vector2] = [Vector2(range_v.x, range_v.y)]
	for blk in blocked:
		var next: Array[Vector2] = []
		for f in out:
			if blk.y <= f.x or blk.x >= f.y:
				next.append(f)
				continue
			if blk.x > f.x:
				next.append(Vector2(f.x, blk.x))
			if blk.y < f.y:
				next.append(Vector2(blk.y, f.y))
		out = next
	return out


func _clip(bands: Array[Vector2], want: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for b in bands:
		var lo := maxf(b.x, want.x)
		var hi := minf(b.y, want.y)
		if hi > lo:
			out.append(Vector2(lo, hi))
	return out


func _sample(bands: Array[Vector2]) -> float:
	var total := 0.0
	for b in bands:
		total += b.y - b.x
	var pick := rng.randf() * total
	for b in bands:
		var w := b.y - b.x
		if pick <= w:
			return b.x + pick
		pick -= w
	return bands[-1].y


## Clear of the gates, the hostile bases (built or still to come) and the
## home station right now.
func _clear_of_points(pos: Vector3, big_r: float) -> bool:
	for g in system.gates:
		if SpaceNav.flat_distance(pos, g.global_position) < big_r + POINT_MARGIN:
			return false
	for ddef in system.system_def.dens:
		if SpaceNav.flat_distance(pos, system.den_position(ddef)) < big_r + POINT_MARGIN:
			return false
	for den in system.dens:
		if is_instance_valid(den) and SpaceNav.flat_distance(pos, den.global_position) < big_r + POINT_MARGIN:
			return false
	if system.home_station and SpaceNav.flat_distance(pos, system.home_station.global_position) < big_r + 4000.0:
		return false
	return true


func _next_name() -> String:
	var names := system.system_def.cluster_names
	var used := {}
	for b in system.belts:
		used[b.def.name] = true
	for _i in names.size():
		var n := names[name_index % names.size()]
		name_index += 1
		if not used.has(n):
			return n
	return "Survey Cluster %d" % spawned


## Nearest planet or moon by name (the star when nothing is closer).
func _nearest_body_name(pos: Vector3) -> String:
	var best := system.system_def.system_name
	var best_d := INF
	for p in system.planets:
		var d := SpaceNav.flat_distance(pos, p.global_position)
		if d < best_d:
			best_d = d
			best = p.def.name
		for c in p.get_children():
			var m := c as PlanetBody
			if m:
				var dm := SpaceNav.flat_distance(pos, m.global_position)
				if dm < best_d:
					best_d = dm
					best = m.def.name
	return best


# --- Save ---------------------------------------------------------------------

func save_state() -> Dictionary:
	return {"due": due.duplicate(), "name_index": name_index, "spawned": spawned, "rng": SaveUtil.rng_state(rng)}


func load_state(d: Dictionary) -> void:
	due.clear()
	for t in d.get("due", []):
		due.append(float(t))
	due.sort()
	name_index = int(d.get("name_index", 0))
	spawned = int(d.get("spawned", 0))
	if d.has("rng"):
		SaveUtil.set_rng(rng, d["rng"])

class_name SystemGenerator
extends RefCounted
## Builds the SystemDef of one generated star system: a star, 3 to 8
## planets (moons on inclined orbits, like home), 3 to 6 asteroid clusters,
## one gate per link of the network, the hostile bases there from the start
## and derelict hulks (data only). Same seed, id and inputs = same def:
## every random pick comes from one rng seeded with the network seed and
## the system id; names come from the network's [NamePool.Allocator] (so
## they stay unique across the network) in a fixed order.
##
## Deeper systems are richer and more dangerous: more titanium and crystal,
## more loads per cluster, more and tougher bases (count and faction by the
## system's danger), better derelicts.

## Bump when the same seed would make different systems (saves keep their
## seed and regenerate; the save notes the version it was made with).
const VERSION := 2

## Gates sit past every body: at least this far out, metres.
const GATE_RADIUS_MIN := 30000.0
## Planets stay inside this radius (the outermost body's reach adds to it).
const PLANET_RADIUS_MAX := 44000.0
## Nothing orbits closer to the star than this: the innermost planet,
## clusters and derelicts, metres.
const INNER_RADIUS_MIN := 8500.0
## Radial gap kept between neighbouring planets' reaches, metres.
const PLANET_GAP := 500.0
## Home's orbit law: period = PERIOD_AT_REF * (r / REF_RADIUS)^1.5.
const PERIOD_AT_REF := 760.0
const REF_RADIUS := 8600.0

## Spectral classes: weight, temperature (K), star radius (m), light energy.
const STARS := [
	{"cls": "M", "w": 0.22, "temp": Vector2(2900.0, 3600.0), "radius": Vector2(340.0, 440.0), "light": 0.85},
	{"cls": "K", "w": 0.28, "temp": Vector2(3900.0, 5100.0), "radius": Vector2(440.0, 560.0), "light": 0.92},
	{"cls": "G", "w": 0.24, "temp": Vector2(5300.0, 6000.0), "radius": Vector2(540.0, 660.0), "light": 1.0},
	{"cls": "F", "w": 0.14, "temp": Vector2(6100.0, 7400.0), "radius": Vector2(640.0, 780.0), "light": 1.08},
	{"cls": "A", "w": 0.08, "temp": Vector2(7600.0, 9800.0), "radius": Vector2(760.0, 920.0), "light": 1.15},
	{"cls": "B", "w": 0.04, "temp": Vector2(11000.0, 18000.0), "radius": Vector2(880.0, 1080.0), "light": 1.25},
]

## Primary ore weights (iron, titanium, crystal) by gate depth 1..3.
const ORE_WEIGHTS := [[0.5, 0.35, 0.15], [0.3, 0.4, 0.3], [0.15, 0.4, 0.45]]
## Base faction weights (scavenger, corsair, syndicate) by danger 1..5.
const FACTION_WEIGHTS := [[1.0, 0.0, 0.0], [1.0, 0.15, 0.0], [0.6, 0.4, 0.0], [0.45, 0.4, 0.15], [0.3, 0.4, 0.3]]
const FACTION_IDS := [&"scavenger", &"corsair", &"syndicate"]

const T := PlanetDef.Type
const ORE := AsteroidBelt.OreType

var _rng := RandomNumberGenerator.new()
var _names: NamePool.Allocator
var _def: SystemDef
var _depth := 1


## The def of system [param id] (display name [param system_name], gate
## depth [param depth] from home, [param danger] 1..5). [param gates]: one
## Dictionary per link, {name, target_system, target_gate, target_danger}.
static func generate(net_seed: int, id: StringName, system_name: String, depth: int, danger: int,
		gates: Array[Dictionary], names: NamePool.Allocator) -> SystemDef:
	var g := SystemGenerator.new()
	return g._generate(net_seed, id, system_name, depth, danger, gates, names)


## Stable seed for system [param id] of network [param net_seed].
static func system_seed(net_seed: int, id: StringName) -> int:
	return hash("%d:%s:v%d" % [net_seed, id, VERSION])


func _generate(net_seed: int, id: StringName, system_name: String, depth: int, danger: int,
		gates: Array[Dictionary], names: NamePool.Allocator) -> SystemDef:
	_rng.seed = system_seed(net_seed, id)
	_names = names
	_depth = clampi(depth, 1, 3)
	_def = SystemDef.new()
	_def.system_name = system_name
	_def.danger = clampi(danger, 1, 5)
	_def.sky_seed = snappedf(_rng.randf_range(0.5, 20.0), 0.01)
	_star()
	_planets()
	var gate_r := maxf(GATE_RADIUS_MIN, snappedf(_outer_reach() + 3000.0, 500.0))
	_clusters(gate_r)
	_dens()
	_derelicts(gate_r)
	_gates(gates, gate_r)
	return _def


# --- Star ---------------------------------------------------------------------

func _star() -> void:
	var weights := PackedFloat32Array()
	for s: Dictionary in STARS:
		weights.append(float(s["w"]))
	var s: Dictionary = STARS[_rng.rand_weighted(weights)]
	_def.star_class = String(s["cls"])
	_def.star_temperature = roundf(_rand_v(s["temp"]) / 50.0) * 50.0
	_def.star_radius = roundf(_rand_v(s["radius"]) / 10.0) * 10.0
	_def.light_energy = snappedf(float(s["light"]) * _rng.randf_range(0.95, 1.05), 0.01)


# --- Planets ------------------------------------------------------------------

func _planets() -> void:
	var n := _rng.randi_range(3, 8)
	var r_min := maxf(_def.star_radius * 9.0, _rng.randf_range(INNER_RADIUS_MIN, 10000.0))
	var r_max := _rng.randf_range(maxf(r_min * 3.2, 30000.0), PLANET_RADIUS_MAX - 2000.0)
	for i in n:
		var f := float(i) / float(n - 1)
		var r := r_min * pow(r_max / r_min, f) * _rng.randf_range(0.94, 1.06)
		if i == 0:
			r = maxf(r, INNER_RADIUS_MIN)
		var p := _planet(snappedf(r, 50.0))
		# Clear of the inner neighbour's reach: push the orbit out.
		if not _def.planets.is_empty():
			var q: PlanetDef = _def.planets[-1]
			var need := q.orbit_radius + planet_reach(q) + planet_reach(p) + PLANET_GAP
			if p.orbit_radius < need:
				if need > PLANET_RADIUS_MAX and _def.planets.size() >= 3:
					break
				_set_orbit(p, snappedf(need + 25.0, 50.0))
		_def.planets.append(p)


func _set_orbit(p: PlanetDef, r: float) -> void:
	p.orbit_radius = r
	p.orbit_period = roundf(PERIOD_AT_REF * pow(r / REF_RADIUS, 1.5))


func _planet(r: float) -> PlanetDef:
	var p := PlanetDef.new()
	p.name = _names.take(&"planet")
	p.type = _planet_type(r)
	p.radius = snappedf(_rand_v(_planet_size(p.type)), 10.0)
	p.seed = snappedf(_rng.randf_range(1.0, 20.0), 0.1)
	_set_orbit(p, r)
	p.start_angle_deg = _angle()
	p.inclination_deg = snappedf(_rng.randf_range(2.0, 8.0), 0.5)
	p.ascending_node_deg = _angle()
	p.spin_period = roundf(_rng.randf_range(70.0, 110.0) if p.type == T.GAS_GIANT else _rng.randf_range(140.0, 400.0))
	p.axial_tilt_deg = roundf(_rng.randf_range(2.0, 28.0))
	p.atmosphere_color = _atmosphere(p.type)
	if _rng.randf() < 0.3:
		p.tint = Color(_rng.randf_range(0.75, 1.15), _rng.randf_range(0.8, 1.1), _rng.randf_range(0.8, 1.2))
	if p.type == T.GAS_GIANT and _rng.randf() < 0.45:
		p.has_rings = true
		p.ring_inner = snappedf(_rng.randf_range(1.25, 1.4), 0.01)
		p.ring_outer = snappedf(_rng.randf_range(1.75, 2.05), 0.01)
		p.ring_color = Color(0.84, 0.76, 0.64).lerp(Color(0.7, 0.75, 0.85), _rng.randf())
	var moons := 0
	if p.type == T.GAS_GIANT:
		moons = _rng.randi_range(1, 3)
	elif p.radius >= 450.0:
		moons = 1 if _rng.randf() < 0.5 else 0
	elif _rng.randf() < 0.2:
		moons = 1
	var reach := p.radius * (p.ring_outer if p.has_rings else 1.3) + 400.0
	for k in moons:
		reach += _rng.randf_range(550.0, 850.0)
		p.moons.append(_moon(p, snappedf(reach, 50.0)))
	return p


func _moon(parent: PlanetDef, r: float) -> PlanetDef:
	var m := PlanetDef.new()
	m.name = _names.take(&"planet")
	var outer := parent.orbit_radius > 23000.0
	m.type = T.ICE if outer and _rng.randf() < 0.6 else (T.LAVA if _rng.randf() < 0.1 else T.ROCKY)
	m.radius = snappedf(minf(_rng.randf_range(60.0, 200.0), parent.radius * 0.35), 5.0)
	m.seed = snappedf(_rng.randf_range(1.0, 20.0), 0.1)
	m.orbit_radius = r
	m.orbit_period = roundf(_rng.randf_range(160.0, 450.0))
	m.start_angle_deg = _angle()
	m.inclination_deg = snappedf(_rng.randf_range(5.0, 20.0), 0.5)
	m.ascending_node_deg = _angle()
	m.spin_period = 0.0
	m.axial_tilt_deg = 0.0
	m.atmosphere_color = Color(0, 0, 0, 0)
	return m


func _planet_type(r: float) -> PlanetDef.Type:
	var types: Array
	var w: PackedFloat32Array
	if r < 11500.0:
		types = [T.LAVA, T.ROCKY, T.DESERT]
		w = PackedFloat32Array([0.45, 0.35, 0.2])
	elif r < 18000.0:
		types = [T.ROCKY, T.OCEAN, T.DESERT, T.LAVA]
		w = PackedFloat32Array([0.3, 0.3, 0.3, 0.1])
	elif r < 30500.0:
		types = [T.GAS_GIANT, T.ICE, T.ROCKY, T.OCEAN]
		w = PackedFloat32Array([0.45, 0.25, 0.2, 0.1])
	else:
		types = [T.GAS_GIANT, T.ICE, T.ROCKY]
		w = PackedFloat32Array([0.45, 0.4, 0.15])
	return types[_rng.rand_weighted(w)]


func _planet_size(type: PlanetDef.Type) -> Vector2:
	match type:
		T.OCEAN:
			return Vector2(450.0, 700.0)
		T.DESERT:
			return Vector2(300.0, 560.0)
		T.ICE:
			return Vector2(180.0, 480.0)
		T.LAVA:
			return Vector2(220.0, 420.0)
		T.GAS_GIANT:
			return Vector2(1100.0, 1900.0)
	return Vector2(220.0, 650.0)


func _atmosphere(type: PlanetDef.Type) -> Color:
	match type:
		T.OCEAN:
			return Color(0.3, 0.62, 1.0, 1.0)
		T.DESERT:
			return Color(0.95, 0.65, 0.4, 0.55)
		T.LAVA:
			return Color(1.0, 0.45, 0.2, 0.55)
		T.ICE:
			return Color(0.6, 0.8, 1.0, 0.6) if _rng.randf() < 0.6 else Color(0, 0, 0, 0)
		T.GAS_GIANT:
			return Color(0.95, 0.8, 0.6, 0.6) if _rng.randf() < 0.6 else Color(0.5, 0.75, 1.0, 0.6)
	return Color(0.62, 0.72, 0.95, 0.22) if _rng.randf() < 0.5 else Color(0, 0, 0, 0)


## How far a planet and its moons and rings reach from its orbit, metres.
static func planet_reach(p: PlanetDef) -> float:
	var r := p.radius * (p.ring_outer if p.has_rings else 1.0)
	for m: PlanetDef in p.moons:
		r = maxf(r, m.orbit_radius + m.radius)
	return r


func _outer_reach() -> float:
	var r := 0.0
	for p in _def.planets:
		r = maxf(r, p.orbit_radius + planet_reach(p))
	return r


## Radial distance from orbit radius [param r] to the nearest planet's
## reach (negative inside it).
func _clearance(r: float) -> float:
	var c := INF
	for p in _def.planets:
		c = minf(c, absf(r - p.orbit_radius) - planet_reach(p))
	return c


# --- Asteroid clusters --------------------------------------------------------

func _clusters(gate_r: float) -> void:
	var n := clampi(_rng.randi_range(3, 4 + _depth), 3, 6)
	var ores: Array = [ORE.IRON, ORE.TITANIUM, ORE.CRYSTAL]
	var w := PackedFloat32Array(ORE_WEIGHTS[_depth - 1])
	for i in n:
		var ore: AsteroidBelt.OreType = ores[_rng.rand_weighted(w)]
		var size := snappedf(_rng.randf_range(1500.0, 2800.0) + (200.0 if ore == ORE.CRYSTAL else 0.0), 50.0)
		var r := _cluster_radius(size, gate_r)
		var c := ClusterDef.new()
		c.name = _names.take(&"cluster")
		c.ore_type = ore
		if _rng.randf() < 0.5:
			var other: Array = ores.filter(func(o: AsteroidBelt.OreType) -> bool: return o != ore)
			c.secondary_ore = other[_rng.randi_range(0, other.size() - 1)]
			c.secondary_share = snappedf(_rng.randf_range(0.2, 0.4), 0.05)
		c.orbit_radius = r
		c.start_angle_deg = _angle()
		c.inclination_deg = snappedf(_rng.randf_range(0.6, 2.0), 0.1)
		c.ascending_node_deg = _angle()
		c.size = size
		c.vertical_spread = snappedf(_rng.randf_range(250.0, 700.0), 50.0)
		c.max_scale = roundf(_rng.randf_range(18.0, 25.0))
		c.richness = snappedf(clampf(0.15 + 0.12 * _depth + _rng.randf_range(0.0, 0.2) + (0.15 if ore == ORE.CRYSTAL else 0.0), 0.2, 0.9), 0.05)
		c.danger = clampi(_def.danger - 1 + (1 if ore == ORE.CRYSTAL else 0), 1, 4)
		c.reserve_loads = clampi(roundi(float(c.get_reserve()) * (1.0 + 0.3 * (_depth - 1))), 25, 100)
		c.seed = _rng.randi_range(1, 99999)
		c.glow = snappedf(_rng.randf_range(1.2, 1.7), 0.1) if ore == ORE.CRYSTAL else 1.0
		c.dust_color = _dust(ore)
		_def.belts.append(c)
	var spawn_names: PackedStringArray = []
	for i in 12:
		spawn_names.append(_names.take(&"cluster"))
	_def.cluster_names = spawn_names
	_def.cluster_min = mini(3, _def.belts.size())
	_def.cluster_max = maxi(_def.belts.size(), _def.cluster_min)
	_def.cluster_orbit_range = Vector2(INNER_RADIUS_MIN + 1000.0, gate_r - 4000.0)


## An orbit radius for a cluster of [param size]: clear of every planet's
## reach and the other clusters when one of the tries fits, else the try
## with the most room (clusters drift slower than the planets, so a near
## orbit only means a pass now and then, like home's Talon Reach).
func _cluster_radius(size: float, gate_r: float) -> float:
	var lo := maxf(INNER_RADIUS_MIN + 1000.0, _def.star_radius * 12.0)
	var hi := gate_r - 3500.0 - size * 0.5
	var best := lo
	var best_room := -INF
	for attempt in 60:
		var r := snappedf(_rng.randf_range(lo, hi), 100.0)
		var room := _clearance(r) - size * 0.5
		for b in _def.belts:
			room = minf(room, absf(b.orbit_radius - r) - (b.size + size) * 0.5)
		if room >= 1200.0:
			return r
		if room > best_room:
			best_room = room
			best = r
	return best


func _dust(ore: AsteroidBelt.OreType) -> Color:
	var base := Color(0.66, 0.52, 0.42)
	if ore == ORE.TITANIUM:
		base = Color(0.6, 0.6, 0.62)
	elif ore == ORE.CRYSTAL:
		base = Color(0.5, 0.62, 0.72) if _rng.randf() < 0.6 else Color(0.56, 0.5, 0.7)
	return Color(base.r * _rng.randf_range(0.95, 1.05), base.g * _rng.randf_range(0.95, 1.05), base.b * _rng.randf_range(0.95, 1.05))


# --- Hostile bases -------------------------------------------------------------

func _dens() -> void:
	if _def.belts.is_empty():
		return
	var count := 0
	match _def.danger:
		1:
			count = 1 if _rng.randf() < 0.5 else 0
		2:
			count = 1
		3:
			count = 2
		4:
			count = _rng.randi_range(2, 3)
		_:
			count = _rng.randi_range(3, 4)
	var w := PackedFloat32Array(FACTION_WEIGHTS[_def.danger - 1])
	# Richest clusters first: the strongest factions sit there.
	var anchors := _def.belts.duplicate()
	anchors.sort_custom(func(a: ClusterDef, b: ClusterDef) -> bool: return a.richness > b.richness)
	for i in count:
		var fi := _rng.rand_weighted(w)
		if _def.danger >= 5 and i == 0:
			fi = 2
		var fid: StringName = FACTION_IDS[fi]
		_def.dens.append(_den(Factions.get_def(fid), anchors[i % anchors.size()]))


func _den(fac: FactionDef, at: ClusterDef) -> DenDef:
	var d := DenDef.new()
	d.faction = fac
	var dg := _def.danger
	match fac.id:
		&"corsair":
			d.gang = _names.take(&"corsair")
			d.name = "%s Corsair Nest" % d.gang
			d.danger_bonus = 1
			d.roam_arc_deg = 40.0
			d.hunt_range = 16000.0
			d.spawn_cap = 3 + floori(dg / 3.0)
			d.respawn_time = 40.0
		&"syndicate":
			d.gang = _names.take(&"syndicate")
			d.name = "%s Syndicate Fortress" % d.gang
			d.danger_bonus = 2
			d.roam_arc_deg = 14.0
			d.hunt_range = 8000.0
			d.spawn_cap = 3
			d.respawn_time = 90.0
		_:
			d.gang = _names.take(&"scavenger")
			d.name = "%s Hideout" % d.gang
			d.danger_bonus = 1 + (1 if dg >= 3 else 0) + (1 if dg >= 5 else 0)
			d.roam_arc_deg = 20.0
			d.hunt_range = 8000.0 + 1000.0 * dg
			d.spawn_cap = 2 + floori((dg + 1) / 2.0)
			d.respawn_time = 56.0 - 4.0 * dg
	d.initial_spawns = mini(d.spawn_cap, 1 + floori(dg / 2.0))
	var tough := 0.75 + 0.1 * dg
	d.hull = roundf(fac.den_hull * tough / 50.0) * 50.0
	d.shields = roundf(fac.den_shields * tough / 50.0) * 50.0
	d.shield_regen = snappedf(fac.den_shield_regen * tough, 0.5)
	d.belt_name = at.name
	d.anchor_radius = at.orbit_radius
	d.angle_deg = fposmod(at.start_angle_deg + _rng.randf_range(-30.0, 30.0), 360.0)
	# The side of the cluster's orbit with more room from the planets.
	var off := snappedf(_rng.randf_range(1100.0, 2000.0), 50.0)
	var out_c := _clearance(at.orbit_radius + off)
	var in_c := _clearance(at.orbit_radius - off)
	d.radial_offset = off if out_c >= in_c else -off
	if maxf(out_c, in_c) < 600.0:
		d.radial_offset = signf(d.radial_offset) * 900.0
	d.height = snappedf(_rng.randf_range(500.0, 900.0) * (1.0 if _rng.randf() < 0.5 else -1.0), 50.0)
	return d


# --- Derelicts ------------------------------------------------------------------

func _derelicts(gate_r: float) -> void:
	var n := _rng.randi_range(1, 2) + (1 if _depth >= 2 and _rng.randf() < 0.5 else 0) + (1 if _depth >= 3 else 0)
	var kinds := PackedFloat32Array([0.25, 0.4, 0.25, 0.1])
	const TABLES := [&"derelict_probe", &"derelict_freighter", &"derelict_frigate", &"derelict_station"]
	for i in mini(n, 4):
		var x := DerelictDef.new()
		x.name = _names.take(&"derelict")
		x.kind = _rng.rand_weighted(kinds) as DerelictDef.Kind
		x.loot_table = TABLES[x.kind]
		x.loot_tier = clampi(_depth + _rng.randi_range(-1, 0) + (1 if x.kind == DerelictDef.Kind.STATION_HULK else 0), 1, 3)
		var r := 0.0
		for attempt in 30:
			r = snappedf(_rng.randf_range(INNER_RADIUS_MIN + 1000.0, gate_r - 2500.0), 100.0)
			if _clearance(r) > 800.0:
				break
		x.orbit_radius = r
		x.angle_deg = _angle()
		x.height = snappedf(_rng.randf_range(-600.0, 600.0), 10.0)
		_def.derelicts.append(x)


# --- Gates ------------------------------------------------------------------------

func _gates(specs: Array[Dictionary], gate_r: float) -> void:
	var angles: Array[float] = []
	var sep := minf(60.0, 300.0 / maxf(specs.size(), 1.0))
	for spec in specs:
		var a := _angle()
		for attempt in 60:
			var ok := true
			for b in angles:
				if absf(angle_difference(deg_to_rad(a), deg_to_rad(b))) < deg_to_rad(sep):
					ok = false
					break
			if ok:
				break
			a = _angle()
		angles.append(a)
		var g := GateDef.new()
		g.name = String(spec["name"])
		g.target_system = String(spec["target_system"])
		g.target_gate = String(spec["target_gate"])
		g.orbit_radius = gate_r
		g.orbit_angle_deg = a
		g.portal_color = portal_color(int(spec.get("target_danger", 1)))
		_def.gates.append(g)


## Portal tint by the danger behind it: blue (1) over violet to red (5).
static func portal_color(danger: int) -> Color:
	var t := clampf((danger - 1) / 4.0, 0.0, 1.0)
	if t < 0.5:
		return Color(0.35, 0.75, 1.0).lerp(Color(0.6, 0.5, 1.0), t * 2.0)
	return Color(0.6, 0.5, 1.0).lerp(Color(1.0, 0.4, 0.35), (t - 0.5) * 2.0)


# --- Helpers ----------------------------------------------------------------------

func _angle() -> float:
	return snappedf(_rng.randf_range(0.0, 360.0), 0.5)


func _rand_v(v: Vector2) -> float:
	return _rng.randf_range(v.x, v.y)

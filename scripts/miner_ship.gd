class_name MinerShip
extends Ship
## A hired miner. Works mining contracts: picks an ore asteroid in the
## contract's cluster (nearest to where it reaches the cluster), hovers next
## to it, drills one load (beam + sparks, hold fills; the load leaves the
## cluster's reserve, AsteroidCluster.take_load), and brings it home. A mined-out
## cluster, or one whose last loads are already being drilled, sends the
## miner home with a log line.
## Cluster lanes: the miner crosses the clump in its lane (over or under, see
## Ship), stops above (below) the hover point, drops to the rock's real
## height beside it and climbs back out the same way. The hover point is
## picked so it and the climb column stay clear of the neighbouring rocks.
## Flight, docking and the decision making live in Ship / ShipMover /
## CaptainBrain; this class only adds the mining work.
## Stage 2: drill time scales with the loadout and the captain's Mining skill;
## scavengers can take part of the load ([method lose_cargo]); being shot
## posts "attacked at" to the event feed.
## Stage 3: a bigger hold (cargo stat) carries a bigger load, which takes a
## little longer to drill. SalvagerShip reuses all of this for scrap.

## Hover gap between the asteroid surface and the ship's centre, metres.
@export var standoff_gap: float = 17.0
## Distance from the ship's origin to the drill tip (nose, -Z), metres.
@export var nose_offset: float = 7.6
## Tangential spread of the asteroid search around the arrival point, metres.
@export var search_spread: float = 300.0
## Gap kept between neighbouring rocks and the hover point (and its climb
## column), surface to ship centre, metres.
@export var hover_clearance: float = 14.0

## Asteroids being drilled right now, "belt:index" -> ship. Keeps miners apart.
static var _claims: Dictionary = {}

## 0..1 ore hold.
var hold_fill: float = 0.0
var hold_ore: int = -1

var _beam: DrillBeam
var _claim_key := ""
var _rng := RandomNumberGenerator.new()


func _make_brain() -> CaptainBrain:
	return CaptainBrain.new(self, MinerEvaluator.new())


func _on_ready_ship() -> void:
	role = Role.MINER
	_rng.randomize()
	_beam = DrillBeam.new()
	_beam.name = "DrillBeam"
	add_child(_beam)


func _exit_tree() -> void:
	_release_claim()


# --- Job hooks ----------------------------------------------------------------

func job_begin(trip: CaptainBrain.Trip) -> bool:
	var mc := trip.contract as MiningContract
	if mc == null or not is_instance_valid(mc.belt):
		return false
	var belt := mc.belt
	if not belt.has_ore_for_new_trip():
		_note_mined_out(mc)
		return false
	var base := SpaceNav.nearest_belt_point(belt, global_position)
	var inward := belt.global_position - base
	inward.y = 0.0
	inward = inward.normalized() if inward.length() > 1.0 else Vector3.RIGHT
	var tangent := inward.cross(Vector3.UP)
	var idx := -1
	for attempt in 5:
		var q := base + tangent * _rng.randf_range(-search_spread, search_spread) \
				+ inward * _rng.randf_range(0.0, 0.35) * belt.rock_half_width()
		# Search on the side of the thick clump this ship comes in from
		# (cluster_side): a rock in that half means a short drop from the lane.
		q.y = belt.global_position.y + cluster_side(belt) * belt.def.vertical_spread * 0.45
		var found := belt.find_nearest_ore(q, mc.ore_type)
		if found < 0:
			found = belt.find_nearest_ore(q, -1)
		if found >= 0 and not _claims.has(_key(belt, found)):
			idx = found
			break
		if found >= 0 and attempt == 4:
			idx = found
	if idx < 0:
		return false
	var ast := belt.get_asteroid(idx)
	trip.asteroid = idx
	trip.ore = int(ast["ore_type"])
	trip.work_time = ContractBoard.mining_rules.mine_time_for(trip.ore) * (stats.drill_mult if stats else 1.0) * load_time_scale()
	trip.progress = 0.0
	trip.cargo = stats.cargo if stats else 1.0
	# Hover point, preferably on the side facing the ship, fixed in cluster space so it drifts with the clump.
	var to_ship := global_position - (ast["position"] as Vector3)
	to_ship.y = 0.0
	if to_ship.length() < 1.0:
		to_ship = -inward
	trip.standoff_local = _pick_standoff(belt, idx, to_ship.normalized())
	_claim(belt, idx)
	return true


func job_target(trip: CaptainBrain.Trip, working: bool) -> Dictionary:
	var mc := trip.contract as MiningContract
	if mc == null or not is_instance_valid(mc.belt) or trip.asteroid < 0:
		return {}
	var belt := mc.belt
	var ast_pos := belt.get_asteroid_position(trip.asteroid)
	var pos := belt.global_transform * trip.standoff_local
	var out := {"pos": pos, "vel": SpaceNav.belt_point_velocity(belt, pos)}
	var dist := SpaceNav.flat_distance(pos, global_position)
	if working or dist < 60.0:
		out["face"] = Vector3(ast_pos.x - pos.x, 0.0, ast_pos.z - pos.z)
	return out


## Belt-local hover point beside asteroid [param idx], at its height. Tries
## directions around the rock (starting from [param toward], world, flat)
## and growing gaps; takes the first whose spot and climb column up (down)
## to the lane keep [member hover_clearance] from every neighbour, else the
## clearest. Only the rocks near this one are checked.
func _pick_standoff(belt: AsteroidCluster, idx: int, toward: Vector3) -> Vector3:
	var c := belt.get_asteroid_local(idx)
	var r := belt.get_asteroid_radius(idx)
	var dir0 := belt.global_basis.inverse() * toward
	dir0.y = 0.0
	dir0 = dir0.normalized() if dir0.length() > 0.01 else Vector3.RIGHT
	var lane_y := lane_sign() * belt.lane_altitude()
	var lo := minf(c.y, lane_y)
	var hi := maxf(c.y, lane_y)
	var gaps: Array[float] = [1.0, 1.4, 1.8]
	var reach := r + standoff_gap * gaps[-1] + hover_clearance + (hi - lo)
	var near := belt.asteroids_near_local(c, reach)
	var best := c + dir0 * (r + standoff_gap)
	var best_clear := -INF
	for g in gaps:
		for k in 12:
			# 0, +30, -30, +60, -60 ... 180 degrees.
			var a := deg_to_rad(30.0 * ceilf(k / 2.0) * (1.0 if k % 2 == 1 else -1.0))
			var p := c + dir0.rotated(Vector3.UP, a) * (r + standoff_gap * g)
			var clear := INF
			for j in near:
				if j == idx:
					continue
				var q := belt.get_asteroid_local(j)
				var col := Vector3(p.x, clampf(q.y, lo, hi), p.z)
				clear = minf(clear, q.distance_to(col) - belt.get_asteroid_radius(j))
			if clear >= hover_clearance:
				return p
			if clear > best_clear:
				best_clear = clear
				best = p
	return best


func job_work(trip: CaptainBrain.Trip, dt: float) -> bool:
	trip.progress = clampf(trip.progress + dt / maxf(trip.work_time, 0.1), 0.0, 1.0)
	hold_fill = trip.progress
	hold_ore = trip.ore
	if trip.progress >= 1.0:
		var mc := trip.contract as MiningContract
		if mc and is_instance_valid(mc.belt):
			mc.belt.take_load()
		return true
	return false


## Logs the turn back from a cluster with no load left for this trip.
func _note_mined_out(mc: MiningContract) -> void:
	if brain == null:
		return
	var where := mc.get_target_name()
	var why := "%s is mined out" % where if mc.depleted or (is_instance_valid(mc.belt) and mc.belt.is_depleted) \
			else "the last loads in %s are already being drilled" % where
	brain.note(CaptainLog.Kind.CONTRACT, CaptainLog.Outcome.FAILED, "Turned back from %s" % where, "Nothing left to mine: %s" % why)


## Work time multiplier for the hold size: half the extra load in time.
func load_time_scale() -> float:
	return 1.0 + 0.5 * maxf((stats.cargo if stats else 1.0) - 1.0, 0.0)


func job_end(_trip: CaptainBrain.Trip) -> void:
	_release_claim()
	if _beam:
		_beam.set_active(false)


func on_cargo_delivered() -> void:
	hold_fill = 0.0
	hold_ore = -1


## True while carrying a mined load.
func is_loaded() -> bool:
	return brain != null and brain.trip != null and brain.trip.loaded and brain.trip.cargo > 0.05


## Gives up [param share] of the load aboard (to scavengers). Returns the
## share of a full load taken.
func lose_cargo(share: float) -> float:
	if not is_loaded():
		return 0.0
	var before := brain.trip.cargo
	brain.trip.cargo = maxf(before * (1.0 - share), 0.0)
	hold_fill = brain.trip.cargo / maxf(stats.cargo if stats else 1.0, 0.01)
	var taken := before - brain.trip.cargo
	show_toast("-%d%% cargo" % roundi(taken * 100.0), Color(1.0, 0.5, 0.4))
	return taken


func _on_damaged(_amount: float, attacker: Node3D) -> void:
	if captain == null or not is_inside_tree():
		return
	var where := SpaceNav.place_name(self, global_position)
	EventLog.post("%s attacked %s" % [captain.captain_name, where], EventLog.Kind.COMBAT, self, Vector3.INF, "attacked:" + captain.captain_name)
	if brain and brain.state != CaptainBrain.State.FLEEING and brain.state != CaptainBrain.State.DOCKING and is_instance_valid(attacker):
		# Everyone runs once the shields are down; the nervous ones sooner.
		var nerve := Captain.unit(captain.nerve)
		if durability.shields <= 0.0 or durability.fraction() < lerpf(0.95, 0.6, nerve) or brain.current_threat(1.0) >= brain.flee_level():
			brain.flee()


# --- Visuals ------------------------------------------------------------------

func _apply_visuals(dt: float) -> void:
	super._apply_visuals(dt)
	if _beam:
		_update_beam()


## Aims the drill beam at the rock while drilling.
func _update_beam() -> void:
	var drilling := brain != null and brain.state == CaptainBrain.State.MINING and brain.trip != null
	if not drilling:
		_beam.set_active(false)
		return
	var mc := brain.trip.contract as MiningContract
	if mc == null or not is_instance_valid(mc.belt):
		_beam.set_active(false)
		return
	var ast := mc.belt.get_asteroid(brain.trip.asteroid)
	if ast.is_empty():
		_beam.set_active(false)
		return
	var nose := global_transform * Vector3(0.0, 0.0, -nose_offset)
	var center: Vector3 = ast["position"]
	var to_nose := (nose - center)
	var contact := center + to_nose.normalized() * float(ast["radius"]) * 0.75
	# Only fire once the nose points at the rock.
	var facing := (global_basis * Vector3.FORWARD).dot((center - global_position).normalized())
	if facing < 0.9:
		_beam.set_active(false)
		return
	_beam.aim(nose, contact)


# --- Claims -------------------------------------------------------------------

## Rocks on [param belt] being drilled (or headed for) right now.
static func claims_on(belt: AsteroidCluster) -> int:
	var prefix := "%d:" % belt.get_instance_id()
	var n := 0
	for k: String in _claims:
		if k.begins_with(prefix):
			n += 1
	return n


static func _key(belt: AsteroidCluster, idx: int) -> String:
	# By instance: cluster names may repeat across live systems.
	return "%d:%d" % [belt.get_instance_id(), idx]


func _claim(belt: AsteroidCluster, idx: int) -> void:
	_release_claim()
	_claim_key = _key(belt, idx)
	_claims[_claim_key] = self


func _release_claim() -> void:
	if not _claim_key.is_empty() and _claims.get(_claim_key) == self:
		_claims.erase(_claim_key)
	_claim_key = ""

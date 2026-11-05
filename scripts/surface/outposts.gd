class_name Outposts
extends Node
## Every planet outpost (planet outposts plan): child of the [ViewManager].
## The outposts themselves are data ([OutpostState] in Sector.outposts,
## saved with the cluster). Every sim step runs the rules every outpost
## shares ([method _common_step]: construction, the founding lander,
## upkeep, shuttle lifts to the station, deposits and nests coming back,
## agitation fading, ground raid timers), and for the outposts nobody is
## viewing the data simulation ([method _data_step]: harvest trips on
## timers, critter and raid attacks rolled from strength). The one on screen
## is run by its live [SurfaceWorld] instead, which reports back here.
##
## Founding ([method found]): only on a planet or moon (no gas giants) in a
## system where the player has a station, with Surface operations
## researched, not on a world a faction garrison holds, one per world.

const GROUP := "outposts"
const MARK := "  [outpost]"
## Seconds between data attack checks per nest.
const NEST_CHECK := 60.0
## Seconds from the raid warning to the drop.
const RAID_WARNING := 30.0
## Upkeep is paid in installments of this many credits.
const UPKEEP_STEP := 15
## Sim seconds after landing in which ground raids bring 2 tanks at most.
const FIRST_RAIDS_GRACE := 1500.0
## Seconds after landing before a claim's ground raid hits a new outpost.
const CLAIM_GRACE := 150.0
## One data attack takes at most this share of a building's full hull.
const MAX_HIT := 0.6
const REPAIR_DELAY := 10.0
const REPAIR_RATE := 0.01
const REPAIR_COST := 0.1

## An outpost changed (founded, lost, a building, a hire): panels refresh.
signal changed(o: OutpostState)

## The outpost whose surface is on screen (its live world runs it), or null.
var live: OutpostState
var _nest_clock := {}
var _rng := RandomNumberGenerator.new()
var _mark_clock := 0.0
## Planet label -> the outpost key it shows (labels of live station systems).
var _marked := {}
## Outpost key -> its founding lander visual (UplinkShuttle) while one flies.
var _landers := {}
## Lifts shown so far: the next one takes the next docking pad.
var _lift_count := 0


static func of(tree: SceneTree) -> Outposts:
	return tree.get_first_node_in_group(GROUP) as Outposts if tree else null


func _enter_tree() -> void:
	# In the group before the HUD's _ready asks for it (ViewManager adds this
	# node in its own _enter_tree, after the HUD).
	add_to_group(GROUP)


func _ready() -> void:
	add_to_group(SimStepper.GROUP)
	_rng.seed = hash("outposts:%d" % Sector.get_seed())
	if not Sector.outposts_rng.is_empty():
		SaveUtil.set_rng(_rng, Sector.outposts_rng)


## The RNG state, saved with the outposts (Sector.save_state).
func rng_state() -> Dictionary:
	return SaveUtil.rng_state(_rng)


func _process(delta: float) -> void:
	if not SimClock.paused:
		sim_step(delta * SimClock.speed)


func all() -> Array[OutpostState]:
	var out: Array[OutpostState] = []
	for k: String in Sector.outposts:
		out.append(Sector.outposts[k] as OutpostState)
	return out


func get_outpost(system_id: StringName, planet_name: String) -> OutpostState:
	return Sector.outposts.get(OutpostState.key_of(system_id, planet_name)) as OutpostState


func outpost_of(body: PlanetBody) -> OutpostState:
	if body == null or body.def == null:
		return null
	var w := SystemWorld.of(body)
	return get_outpost(w.system_id if w else ClusterNetwork.HOME_ID, body.def.name)


## The name label of a planet with an outpost reads "Iru  [outpost]";
## labels whose outpost is gone get their plain name back.
func _mark_planets() -> void:
	for l: Variant in _marked.keys():
		var lbl := l as Label3D
		if not is_instance_valid(lbl):
			_marked.erase(l)
			continue
		if not Sector.outposts.has(_marked[l]):
			lbl.text = lbl.text.trim_suffix(MARK)
			_marked.erase(l)
	var vm := get_parent() as ViewManager
	for o in all():
		var w := SystemWorld.home(get_tree()) if o.system_id == ClusterNetwork.HOME_ID else (vm.world(o.system_id) if vm else null)
		var body := PlanetInfo.find_planet(w, o.planet) if w else null
		var lbl := body.get_node_or_null(^"Label") as Label3D if body else null
		if lbl and not _marked.has(lbl):
			lbl.text += MARK
			_marked[lbl] = o.key()


# --- Founding -----------------------------------------------------------------

## Why an outpost cannot be founded on [param body] now, or "".
func found_problem(body: PlanetBody) -> String:
	if body == null or body.def == null:
		return "Pick a planet or moon"
	if OutpostState.good_of(body.def.type) < 0:
		return "Nothing to harvest there"
	var w := SystemWorld.of(body)
	if w == null or not w.has_station or w.corp_id != Corps.PLAYER:
		return "Only in a system with your station"
	if outpost_of(body) != null:
		return "%s already has an outpost" % body.def.name
	if not Research.is_done(OutpostState.TECH):
		return "Needs research: Surface operations"
	var claim := PlanetClaims.claim_reason(body)
	if not claim.is_empty():
		return "%s: break the claim first" % claim
	return Economy.shortfall_text(OutpostState.FOUND_CREDITS, Economy.cost(OutpostState.FOUND_IRON, OutpostState.FOUND_TITANIUM))


## Founds an outpost on [param body]: pays, and a lander flies down
## ([constant OutpostState.FOUND_TIME]); the outpost is founded when it
## lands. Returns the new state, null when refused.
func found(body: PlanetBody) -> OutpostState:
	if not found_problem(body).is_empty():
		return null
	if not Economy.spend(OutpostState.FOUND_CREDITS, Economy.cost(OutpostState.FOUND_IRON, OutpostState.FOUND_TITANIUM), Ledger.BUILDINGS, "Outpost on %s" % body.def.name, SystemWorld.of(body).system_id):
		return null
	var w := SystemWorld.of(body)
	var o := OutpostState.new()
	o.system_id = w.system_id
	o.planet = body.def.name
	o.planet_type = body.def.type
	o.good = OutpostState.good_of(body.def.type)
	o.seed = hash("%d|%s|%s" % [Sector.get_seed(), o.system_id, o.planet])
	o.danger = PlanetInfo.danger_for(body)
	o.ordered_at = SimClock.time
	o.founded_at = -1.0
	o.buildings.append({"kind": String(OutpostState.PAD), "x": 0.0, "z": 0.0, "hull": float(OutpostState.BUILDINGS[OutpostState.PAD]["hull"]), "built": 0.0, "disabled": false})
	_lay_out(o)
	var st := w.sys.home_station if w.sys else null
	var km := st.global_position.distance_to(body.global_position) / 1000.0 if st else 5.0
	o.raid = {}
	o.next_raid = -1.0
	o.lift_seconds = clampf(30.0 + km * 1.5, 40.0, 110.0)
	Sector.outposts[o.key()] = o
	EventLog.post("Lander on its way down to %s: the outpost lands in %d s" % [o.planet, roundi(OutpostState.FOUND_TIME)], EventLog.Kind.INFO, body)
	_show_lander(o)
	changed.emit(o)
	return o


## Seconds a shuttle lift takes from the surface to the station.
static func lift_time(o: OutpostState) -> float:
	return o.lift_seconds


## Deposits and nests of a new outpost, seeded.
func _lay_out(o: OutpostState) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = o.seed
	var n := rng.randi_range(OutpostState.DEPOSITS.x, OutpostState.DEPOSITS.y)
	for i in n:
		o.deposits.append(_new_deposit(o, rng, i))
	var nests := clampi(1 + floori(o.danger / 2.0) + rng.randi_range(0, 1), 1, 3)
	for i in nests:
		var a := rng.randf() * TAU
		var r := rng.randf_range(1300.0, 1850.0)
		o.nests.append({"x": cos(a) * r, "z": sin(a) * r, "hull": OutpostState.NEST_HULL, "agitation": 0.0, "dead_until": -1.0})


## A deposit at ([param x], [param z]) stays clear of every building.
static func _clear_of_buildings(o: OutpostState, x: float, z: float) -> bool:
	for b in o.buildings:
		if Vector2(x - float(b["x"]), z - float(b["z"])).length() < float(OutpostState.BUILDINGS[StringName(b["kind"])]["radius"]) + 80.0:
			return false
	return true


func _new_deposit(o: OutpostState, rng: RandomNumberGenerator, i: int) -> Dictionary:
	var a := rng.randf() * TAU
	var r := rng.randf_range(OutpostState.DEPOSIT_RANGE.x, OutpostState.DEPOSIT_RANGE.y)
	var loads := rng.randi_range(OutpostState.DEPOSIT_LOADS.x, OutpostState.DEPOSIT_LOADS.y)
	var nm := "%s %s" % [String(OutpostState.DEPOSIT_NAMES.get(o.good, "deposit")).capitalize(), ["A", "B", "C", "D", "E", "F", "G", "H"][i % 8]]
	return {"x": cos(a) * r, "z": sin(a) * r, "loads": loads, "total": loads, "name": nm}


# --- Buildings and hires (the surface HUD and the live world call these) -----------

## Why [param kind] cannot be built in [param o] now, or "".
func build_problem(o: OutpostState, kind: StringName) -> String:
	if not o.is_founded():
		return "The outpost is not founded yet"
	var d: Dictionary = OutpostState.BUILDINGS[kind]
	if d.has("max") and o.count(kind) >= int(d["max"]):
		return "Only %d %s allowed" % [int(d["max"]), d["name"]]
	return Economy.shortfall_text(int(d["credits"]), Economy.cost(int(d["iron"]), int(d["ti"])))


## Why a building of [param kind] cannot stand at ([param x], [param z]), or "".
func spot_problem(o: OutpostState, kind: StringName, x: float, z: float) -> String:
	var r := float(OutpostState.BUILDINGS[kind]["radius"])
	if Vector2(x, z).length() > OutpostState.BASE_RADIUS:
		return "Too far from the landing pad (%d m at most)" % roundi(OutpostState.BASE_RADIUS)
	for b in o.buildings:
		var br := float(OutpostState.BUILDINGS[StringName(b["kind"])]["radius"])
		if Vector2(x - float(b["x"]), z - float(b["z"])).length() < r + br + OutpostState.BUILD_GAP:
			return "Too close to the %s" % OutpostState.BUILDINGS[StringName(b["kind"])]["name"]
	for dp in o.deposits:
		if Vector2(x - float(dp["x"]), z - float(dp["z"])).length() < r + 80.0:
			return "On a deposit"
	return ""


func build(o: OutpostState, kind: StringName, x: float, z: float) -> bool:
	if not build_problem(o, kind).is_empty() or not spot_problem(o, kind, x, z).is_empty():
		return false
	var d: Dictionary = OutpostState.BUILDINGS[kind]
	if not Economy.spend(int(d["credits"]), Economy.cost(int(d["iron"]), int(d["ti"])), Ledger.BUILDINGS, "%s on %s" % [d["name"], o.planet], o.system_id):
		return false
	o.buildings.append({"kind": String(kind), "x": x, "z": z, "hull": float(d["hull"]), "built": 0.0, "disabled": false})
	changed.emit(o)
	return true


## Why a [param role] cannot be hired at [param o] now, or "".
func hire_problem(o: OutpostState, role: String) -> String:
	var kind := OutpostState.BAY if role == OutpostState.HARVESTER else OutpostState.GARRISON
	if o.active(kind) == 0:
		return "Needs a finished %s" % OutpostState.BUILDINGS[kind]["name"]
	if o.crew_of(role).size() >= o.berths(role):
		return "All %d berths are taken" % o.berths(role)
	if o.upkeep_owed > 0:
		return "Upkeep unpaid (%d cr owed): no hiring here" % o.upkeep_owed
	return Economy.shortfall_text(int(OutpostState.BUILDINGS[kind]["hire"]))


func hire(o: OutpostState, role: String) -> Dictionary:
	if not hire_problem(o, role).is_empty():
		return {}
	var kind := OutpostState.BAY if role == OutpostState.HARVESTER else OutpostState.GARRISON
	var cost := int(OutpostState.BUILDINGS[kind]["hire"])
	if not Economy.spend(cost, PackedInt32Array(), Ledger.HIRES, "Hire on %s" % o.planet, o.system_id):
		return {}
	var cap := Captain.generate(_rng, role)
	var c := {"name": cap.captain_name, "personality": int(cap.personality), "role": role,
			"hull": OutpostState.max_hull(role),
			"wallet": 0, "loads": 0, "kills": 0, "deposit": -1, "trip": 0.0}
	o.crew.append(c)
	EventLog.post("%s hired as a %s on %s" % [c["name"], role.to_lower(), o.planet], EventLog.Kind.INFO)
	changed.emit(o)
	return c


## Posts (or changes) the harvest contract on deposit [param i]; 0 cancels.
func set_contract(o: OutpostState, i: int, pay: int) -> void:
	if pay <= 0:
		o.contracts.erase(i)
	else:
		o.contracts[i] = pay
	changed.emit(o)


## Posts a bounty on nest [param i] (reserved now; paid when it dies).
func post_bounty(o: OutpostState, i: int, credits: int) -> bool:
	if o.bounties.has(i) or not Economy.spend(credits, PackedInt32Array(), Ledger.ESCROW, "Reserved: nest bounty on %s" % o.planet, o.system_id):
		return false
	o.bounties[i] = credits
	changed.emit(o)
	return true


# --- Step ----------------------------------------------------------------------

func sim_step(dt: float) -> void:
	if dt <= 0.0:
		return
	_mark_clock -= dt
	if _mark_clock <= 0.0:
		_mark_clock = 2.0
		_mark_planets()
	for o in all():
		_common_step(o, dt)
		if o != live and o.is_founded():
			_data_step(o, dt)
	for k: String in Sector.outposts.keys():
		var o := Sector.outposts[k] as OutpostState
		if o.lost:
			Sector.outposts.erase(k)
			changed.emit(o)


func _common_step(o: OutpostState, dt: float) -> void:
	# The lander.
	if o.founded_at < 0.0:
		_show_lander(o)
		if SimClock.time - o.ordered_at >= OutpostState.FOUND_TIME:
			o.founded_at = SimClock.time
			o.pad()["built"] = 1.0
			o.next_raid = SimClock.time + _raid_gap(o) + 300.0
			EventLog.post("Outpost founded on %s: build a Harvester Bay and post harvest contracts on its deposits" % o.planet, EventLog.Kind.REWARD)
			changed.emit(o)
		return
	if o.lost:
		return
	if not _has_station(o):
		lose(o, "its station in that system is gone")
		return
	if not o.pending_ground.is_empty() and o != live:
		# Hostiles that were on the ground when the game was saved.
		var left := o.pending_ground
		o.pending_ground = {}
		for kind: String in left:
			resolve_attack(o, float(left[kind]), kind, "the %s still on the ground" % kind)
		if o.lost:
			return
	for b in o.buildings:
		if float(b.get("built", 1.0)) < 1.0:
			b["built"] = minf(float(b["built"]) + dt / maxf(float(OutpostState.BUILDINGS[StringName(b["kind"])]["time"]), 1.0), 1.0)
			if float(b["built"]) >= 1.0:
				EventLog.post("%s finished on %s" % [OutpostState.BUILDINGS[StringName(b["kind"])]["name"], o.planet], EventLog.Kind.INFO)
				changed.emit(o)
	_repairs(o, dt)
	_upkeep(o, dt)
	_shuttles(o, dt)
	# Deposits come back while fewer than the minimum have ore.
	var with_ore := 0
	for d in o.deposits:
		if int(d["loads"]) > 0:
			with_ore += 1
	if with_ore < OutpostState.DEPOSITS.x:
		if o.deposit_timer < 0.0:
			o.deposit_timer = OutpostState.DEPOSIT_RESPAWN
		o.deposit_timer -= dt
		if o.deposit_timer <= 0.0:
			o.deposit_timer = -1.0
			var rng := RandomNumberGenerator.new()
			rng.seed = hash("%d:%d" % [o.seed, o.deposits.size()])
			var nd := _new_deposit(o, rng, o.deposits.size())
			for tries in 8:
				if _clear_of_buildings(o, float(nd["x"]), float(nd["z"])):
					break
				nd = _new_deposit(o, rng, o.deposits.size())
			o.deposits.append(nd)
			EventLog.post("A new %s turned up on %s" % [String(OutpostState.DEPOSIT_NAMES.get(o.good, "deposit")), o.planet], EventLog.Kind.INFO)
			changed.emit(o)
	for n in o.nests:
		n["agitation"] = maxf(float(n["agitation"]) - OutpostState.AGITATION_DECAY * dt / 60.0, 0.0)
		var du := float(n.get("dead_until", -1.0))
		if du >= 0.0 and SimClock.time >= du:
			n["dead_until"] = -1.0
			n["hull"] = OutpostState.NEST_HULL
			n["agitation"] = 10.0
			EventLog.post("A critter nest on %s is back" % o.planet, EventLog.Kind.THREAT)
	_raid_clock(o)


## Buildings repair from [constant REPAIR_DELAY] s after the last hit, at
## [constant REPAIR_RATE] of their hull a second, paid like the station's;
## a disabled one is back at 40%.
func _repairs(o: OutpostState, dt: float) -> void:
	for b in o.buildings:
		var mx := float(OutpostState.BUILDINGS[StringName(b["kind"])]["hull"])
		if float(b["hull"]) >= mx or SimClock.time - float(b.get("hit_at", -99.0)) < REPAIR_DELAY:
			continue
		var add := minf(mx * REPAIR_RATE * dt, mx - float(b["hull"]))
		# Owed only once paid: a failed spend leaves the total where it was.
		var acc := float(b.get("repair_acc", 0.0)) + add * REPAIR_COST
		if acc >= 1.0:
			var whole := floori(acc)
			if not Economy.spend(whole, PackedInt32Array(), Ledger.REPAIRS, "Outpost repairs", o.system_id):
				continue
			acc -= whole
		b["repair_acc"] = acc
		b["hull"] = float(b["hull"]) + add
		if bool(b.get("disabled", false)) and float(b["hull"]) >= mx * 0.4:
			b["disabled"] = false
			# A dome comes back with its shield (the live world refills it from here).
			b.erase("shield")
			EventLog.post("%s on %s is back online" % [OutpostState.BUILDINGS[StringName(b["kind"])]["name"], o.planet], EventLog.Kind.INFO)


## The outpost's system still has a station of its corp (home always does).
static func _has_station(o: OutpostState) -> bool:
	if o.system_id == ClusterNetwork.HOME_ID:
		return true
	var st := Sector.state(o.system_id)
	return st != null and not st.station.is_empty() and Corps.corp_of_system(o.system_id) == o.corp


func _upkeep(o: OutpostState, dt: float) -> void:
	o.upkeep_acc += OutpostState.UPKEEP * dt / 60.0
	if o.upkeep_acc < UPKEEP_STEP:
		return
	var due := floori(o.upkeep_acc)
	o.upkeep_acc -= due
	o.upkeep_owed += due
	var was := o.upkeep_owed - due
	if Economy.spend(o.upkeep_owed, PackedInt32Array(), Ledger.UPKEEP, "Upkeep: %s outpost" % o.planet, o.system_id):
		if was > 0:
			EventLog.post("Upkeep for the %s outpost is paid: hiring there again" % o.planet, EventLog.Kind.INFO)
		o.upkeep_owed = 0
	elif was == 0:
		EventLog.post("Upkeep for the %s outpost unpaid: no hiring there until it is paid" % o.planet, EventLog.Kind.LOSS)


## Stock waiting at the pad goes up in shuttle lifts; landed lifts deliver.
func _shuttles(o: OutpostState, dt: float) -> void:
	for l in o.lifts.duplicate():
		l["left"] = float(l["left"]) - dt
		if float(l["left"]) <= 0.0:
			o.lifts.erase(l)
			_deliver(o, PackedInt32Array(l["units"]))
	var total := 0
	for x in o.stock:
		total += x
	if total <= 0:
		o.stock_wait = 0.0
		return
	o.stock_wait += dt
	if o.lifts.size() >= o.shuttles or not o.pad_alive():
		if o.stock_wait > OutpostState.SHUTTLE_WAIT and o.shuttles < OutpostState.MAX_SHUTTLES:
			o.shuttles += 1
			o.stock_wait = 0.0
			EventLog.post("The %s outpost runs %d shuttles now" % [o.planet, o.shuttles], EventLog.Kind.INFO)
		return
	if total < OutpostState.shuttle_load() and o.stock_wait < 40.0:
		return
	var take := Economy.zero_ore()
	var room := OutpostState.shuttle_load()
	for i in o.stock.size():
		var n := mini(o.stock[i], room)
		take[i] = n
		o.stock[i] -= n
		room -= n
	o.lifts.append({"units": take, "left": lift_time(o)})
	o.stock_wait = 0.0
	_show_lift(o, lift_time(o))


## A lift landed at the station: the goods are the corp's.
func _deliver(o: OutpostState, units: PackedInt32Array) -> void:
	var total := 0
	for i in units.size():
		o.delivered[i] += units[i]
		total += units[i]
	if total <= 0:
		return
	Corps.economy_of_corp(o.corp).receive_cargo(units, "Shuttle from %s" % o.planet)
	EventLog.post("Shuttle from %s landed: %s" % [o.planet, Economy.cost_text(units)], EventLog.Kind.REWARD)


## The live world of [param o]'s station system, or null (not live, no station).
## (The surface sky asks it for the star and the parent planet.)
func station_world(o: OutpostState) -> SystemWorld:
	var vm := get_parent() as ViewManager
	var w := vm.world(o.system_id) if vm and o.system_id != ClusterNetwork.HOME_ID else SystemWorld.home(get_tree())
	if w == null or w.sys == null or w.sys.home_station == null:
		return null
	return w


## A shuttle flying up in the station's system (visual only: delivery is the timer).
func _show_lift(o: OutpostState, seconds: float) -> void:
	var w := station_world(o)
	var body := PlanetInfo.find_planet(w, o.planet) if w else null
	if body == null:
		return
	var s := UplinkShuttle.new()
	s.setup(body, w.sys.home_station, seconds, _lift_count)
	_lift_count += 1
	SpaceNav.space_root(w).add_child(s)


## The founding lander flying down in the station's system while [param o]
## is not founded yet (visual only: the founding is the timer). Shown again
## part way through after a load or when its system comes back live.
func _show_lander(o: OutpostState) -> void:
	var k := o.key()
	if is_instance_valid(_landers.get(k)):
		return
	_landers.erase(k)
	var left := OutpostState.FOUND_TIME - (SimClock.time - o.ordered_at)
	if left <= 1.0:
		return
	var w := station_world(o)
	var body := PlanetInfo.find_planet(w, o.planet) if w else null
	if body == null:
		return
	var s := UplinkShuttle.new()
	s.setup_lander(body, w.sys.home_station, OutpostState.FOUND_TIME, SimClock.time - o.ordered_at)
	SpaceNav.space_root(w).add_child(s)
	_landers[k] = s


# --- Data simulation -------------------------------------------------------------------

func _data_step(o: OutpostState, dt: float) -> void:
	if not o.pad_alive():
		lose(o, "its landing pad was destroyed")
		return
	# Soldiers repair at a working garrison between raids (live: SurfaceWorld).
	if o.active(OutpostState.GARRISON) > 0 and o.raid.is_empty():
		for c in o.crew_of(OutpostState.SOLDIER):
			c["hull"] = minf(float(c["hull"]) + SurfaceWorld.REPAIR_RATE * dt, OutpostState.max_hull(OutpostState.SOLDIER))
	# Harvest trips on timers.
	for c in o.crew_of(OutpostState.HARVESTER):
		var di := int(c.get("deposit", -1))
		if di < 0 or di >= o.deposits.size() or int(o.deposits[di]["loads"]) <= 0 or not o.contracts.has(di):
			c["deposit"] = pick_deposit(o, c)
			c["trip"] = 0.0
			continue
		var d: Dictionary = o.deposits[di]
		var dist := Vector2(float(d["x"]), float(d["z"])).length()
		var trip := 2.0 * dist / OutpostState.HARVESTER_SPEED + OutpostState.HARVEST_TIME
		c["trip"] = float(c["trip"]) + dt / trip
		if float(c["trip"]) >= 1.0:
			c["trip"] = 0.0
			deliver_load(o, c, di)
	# Critters.
	for i in o.nests.size():
		var n := o.nests[i]
		if float(n.get("dead_until", -1.0)) >= 0.0:
			continue
		var t := float(_nest_clock.get("%s:%d" % [o.key(), i], 0.0)) + dt
		_nest_clock["%s:%d" % [o.key(), i]] = t
		if t < NEST_CHECK:
			continue
		_nest_clock["%s:%d" % [o.key(), i]] = 0.0
		var ag := float(n["agitation"])
		if ag >= OutpostState.AGITATION_ATTACK:
			n["agitation"] = ag - OutpostState.AGITATION_ATTACK
			var size := mini(2 + floori(ag / 25.0), 2 + o.danger)
			resolve_attack(o, size * 0.3, "critters", "%d critters" % size)
		# Soldiers with a bounty on it clear it.
		if o.bounties.has(i) and o.crew_of(OutpostState.SOLDIER).size() >= 2:
			n["hull"] = float(n["hull"]) - 120.0 * o.crew_of(OutpostState.SOLDIER).size()
			if float(n["hull"]) <= 0.0:
				kill_nest(o, i)


## The deposit a harvester takes: posted contracts only, by pay against fair
## pay and personality (Greedy: the pay, Lazy: near, Cautious: away from
## agitated nests). -1 when none suits.
func pick_deposit(o: OutpostState, c: Dictionary) -> int:
	var best := -1
	var best_s := -INF
	var fair := float(o.fair_pay())
	for di: int in o.contracts:
		if di < 0 or di >= o.deposits.size() or int(o.deposits[di]["loads"]) <= 0:
			continue
		var d: Dictionary = o.deposits[di]
		var pay := float(o.contracts[di])
		var km := Vector2(float(d["x"]), float(d["z"])).length() / 1000.0
		var risk := 0.0
		for n in o.nests:
			if float(n.get("dead_until", -1.0)) < 0.0 and Vector2(float(d["x"]) - float(n["x"]), float(d["z"]) - float(n["z"])).length() < OutpostState.AGITATION_REACH:
				risk += float(n["agitation"]) / 30.0
		var p := int(c.get("personality", 0))
		var s := pay / fair - km * (0.5 if p == Captain.Personality.LAZY else 0.2) - risk * (0.8 if p == Captain.Personality.CAUTIOUS else 0.3)
		if p == Captain.Personality.GREEDY:
			s += (pay / fair - 1.0) * 0.5
		if pay < fair * (0.75 if p == Captain.Personality.BOLD else 0.85):
			continue
		if s > best_s:
			best_s = s
			best = di
	return best


## A load from deposit [param di] reached the pad: stock, pay, agitation.
func deliver_load(o: OutpostState, c: Dictionary, di: int) -> void:
	var d: Dictionary = o.deposits[di]
	if int(d["loads"]) <= 0:
		return
	d["loads"] = int(d["loads"]) - 1
	var units := o.load_units()
	o.stock[o.good] += units
	o.loads_total += 1
	c["loads"] = int(c.get("loads", 0)) + 1
	var pay := mini(int(o.contracts.get(di, 0)), maxi(Economy.credits, 0))
	if pay > 0:
		Economy.spend(pay, PackedInt32Array(), Ledger.CONTRACT_PAY, "Harvest on %s" % o.planet, o.system_id)
		var fee := roundi(pay * 0.25)
		c["wallet"] = int(c.get("wallet", 0)) + pay - fee
		Economy.add_income(fee, Ledger.FEES, "Station fees")
	for n in o.nests:
		if Vector2(float(d["x"]) - float(n["x"]), float(d["z"]) - float(n["z"])).length() < OutpostState.AGITATION_REACH:
			n["agitation"] = float(n["agitation"]) + OutpostState.AGITATION_PER_LOAD
	if int(d["loads"]) <= 0:
		o.contracts.erase(di)
		EventLog.post("The %s on %s is mined out" % [d["name"], o.planet], EventLog.Kind.INFO)
		changed.emit(o)


## A data attack on [param o] of [param power] (soldier equivalents): rolled
## against its defence. Losing costs a harvester, a building's hull or stock.
func resolve_attack(o: OutpostState, power: float, kind: String, what: String) -> void:
	var def := o.defence()
	var win := def / maxf(def + power, 0.01)
	var roll := _rng.randf()
	if roll < win:
		for c in o.crew_of(OutpostState.SOLDIER):
			c["hull"] = maxf(float(c["hull"]) - _rng.randf_range(20.0, 120.0), 60.0)
		EventLog.post("%s attacked the %s outpost and were driven off (defence %.1f against %.1f)" % [what.capitalize(), o.planet, def, power], EventLog.Kind.COMBAT)
		return
	var lines: PackedStringArray = []
	var hs := o.crew_of(OutpostState.HARVESTER)
	if not hs.is_empty() and _rng.randf() < 0.5:
		var victim: Dictionary = hs[_rng.randi() % hs.size()]
		o.crew.erase(victim)
		lines.append("%s was lost" % victim["name"])
	var targets: Array[Dictionary] = []
	for b in o.buildings:
		if float(b["hull"]) > 0.0:
			targets.append(b)
	if not targets.is_empty():
		var b: Dictionary = targets[_rng.randi() % targets.size()]
		var full := float(OutpostState.BUILDINGS[StringName(b["kind"])]["hull"])
		var hit := minf(full * _rng.randf_range(0.2, 0.6) * (power / maxf(def + 1.0, 1.0)), full * MAX_HIT)
		b["hull"] = maxf(float(b["hull"]) - hit, 0.0)
		b["hit_at"] = SimClock.time
		if float(b["hull"]) <= 0.0:
			b["disabled"] = true
			lines.append("the %s is disabled" % OutpostState.BUILDINGS[StringName(b["kind"])]["name"])
		else:
			lines.append("the %s took damage" % OutpostState.BUILDINGS[StringName(b["kind"])]["name"])
	if kind == "raiders":
		var stolen := 0
		for i in o.stock.size():
			var n := o.stock[i] / 2
			o.stock[i] -= n
			stolen += n
		if stolen > 0:
			lines.append("%d units stolen" % stolen)
	EventLog.post("%s overran the defence on %s: %s" % [what.capitalize(), o.planet, ", ".join(lines) if not lines.is_empty() else "no harm done"], EventLog.Kind.LOSS)
	changed.emit(o)
	if not o.pad_alive():
		lose(o, "its landing pad was destroyed")


func kill_nest(o: OutpostState, i: int) -> void:
	var n := o.nests[i]
	n["dead_until"] = SimClock.time + OutpostState.NEST_RESPAWN
	n["hull"] = 0.0
	n["agitation"] = 0.0
	var bounty := int(o.bounties.get(i, 0))
	o.bounties.erase(i)
	var soldiers := o.crew_of(OutpostState.SOLDIER)
	if bounty > 0 and not soldiers.is_empty():
		var each := bounty / soldiers.size()
		for c in soldiers:
			c["wallet"] = int(c.get("wallet", 0)) + each
		Economy.note_escrow_pay(bounty, Ledger.BOUNTIES, "Nest bounty on %s" % o.planet)
	EventLog.post("A critter nest on %s was cleared%s" % [o.planet, " (%d cr bounty)" % bounty if bounty > 0 else ""], EventLog.Kind.REWARD)
	changed.emit(o)


# --- Ground raids ---------------------------------------------------------------------

func _raid_gap(o: OutpostState) -> float:
	return lerpf(1200.0, 600.0, clampf((o.danger - 1) / 4.0, 0.0, 1.0)) * _rng.randf_range(0.85, 1.15)


func _raid_clock(o: OutpostState) -> void:
	if o.next_raid < 0.0:
		return
	if o.raid.is_empty() and SimClock.time >= o.next_raid - RAID_WARNING:
		# Tanks by danger: 1-2: 2, 3: 2-3, 4: 3-4, 5: 4-5; the raids of the
		# first 25 min after landing bring 2 at most.
		var size := clampi(o.danger + _rng.randi_range(-1, 0), 2, 5)
		if SimClock.time - o.founded_at < FIRST_RAIDS_GRACE:
			size = 2
		var source := "Pirate"
		for r in Corps.living_rivals():
			if Corps.corps_at_war(r.id, Corps.PLAYER):
				source = r.display_name
		o.raid = {"at": o.next_raid, "size": size, "source": source, "a": _rng.randf() * TAU}
		EventLog.post("Ground raid forming at %s: %s, %d tanks, landing in %d s" % [o.planet, source, size, roundi(RAID_WARNING)], EventLog.Kind.THREAT)
		_toast("Ground raid on %s in %d s" % [o.planet, roundi(RAID_WARNING)])
	if not o.raid.is_empty() and SimClock.time >= float(o.raid["at"]):
		var r := o.raid
		o.raid = {}
		o.next_raid = SimClock.time + _raid_gap(o)
		if o == live:
			var sw := SurfaceWorld.current(get_tree())
			if sw:
				sw.spawn_raid(int(r["size"]), String(r["source"]), float(r.get("a", -1.0)))
				return
		resolve_attack(o, int(r["size"]) * 0.8, "raiders", "%s raiders" % String(r["source"]))


## A faction that would claim [param body] (a garrison in orbit) finds an
## outpost there: it sends a ground raid of [param size] tanks instead and
## no garrison is set. True when an outpost blocked the claim.
func claim_blocked(body: PlanetBody, size: int, source: String) -> bool:
	var o := outpost_of(body)
	if o == null or o.lost:
		return false
	if o.raid.is_empty():
		# A lander still in flight: the raid comes a while after it is down,
		# so there is time for a turret or a garrison.
		var at := SimClock.time + RAID_WARNING
		if not o.is_founded():
			at = o.ordered_at + OutpostState.FOUND_TIME + CLAIM_GRACE
		o.raid = {"at": at, "size": clampi(size, 2, 6), "source": source, "a": _rng.randf() * TAU}
		var secs := roundi(at - SimClock.time)
		EventLog.post("%s tried to claim %s and found your outpost: a ground raid of %d tanks lands in %d s" % [source, o.planet, int(o.raid["size"]), secs], EventLog.Kind.THREAT, body)
		_toast("Ground raid on %s in %d s" % [o.planet, secs])
	return true


## The outpost is lost: its landing pad was destroyed.
func lose(o: OutpostState, why: String) -> void:
	if o.lost:
		return
	o.lost = true
	for i: int in o.bounties:
		Economy.add_income(int(o.bounties[i]), Ledger.ESCROW, "Returned: nest bounty")
	# Shuttles already in the air still land.
	for l in o.lifts:
		_deliver(o, PackedInt32Array(l["units"]))
	o.lifts.clear()
	if o == live:
		var sm := SurfaceMode.of(get_tree())
		if sm:
			sm.leave.call_deferred()
	EventLog.post("The outpost on %s is lost: %s" % [o.planet, why], EventLog.Kind.LOSS)
	_toast("Outpost on %s lost" % o.planet)


func _toast(text: String) -> void:
	var pm := get_tree().root.get_node_or_null(^"PauseMenu")
	if pm and pm.has_method(&"toast"):
		pm.call(&"toast", text)

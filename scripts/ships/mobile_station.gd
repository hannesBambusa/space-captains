class_name MobileStation
extends Ship
## A forward station on its way (F6): built at home as the Forward Station
## structure (ForwardStationYard turns the finished site into this ship),
## flown with escorts to a planet in another system, where it starts
## orbiting and becomes a real station (ForwardStations.found). No captain,
## never fights, slow ([constant SPEED]), hull [constant HULL]; raiders
## hunt it (ScavengerBrain), at home a hit raises the colony alarm.
## Model: the forward station (HomeStation.FORWARD_PATH) pushed by the
## colony ship hull as its drive tug ([constant TUG_PATH], whose engine
## glow is the station's).
##
## States: PARKED beside home's complex (it rides the structures frame);
## WAITING: a destination is set ([method set_destination]: a planet that
## passes ForwardStations.site_problem) and an escort contract (the
## EscortContract ward form, [member escort_pay] per escort) is posted; it
## leaves once an escort is within [constant ESCORT_JOIN_RANGE]. TRAVEL: a
## [GateTransit] along Sector.hops_between; it holds while its escorts
## fall behind ([constant ESCORT_LOST_RANGE]) and warps only with all of
## them in formation. The escorts near it ([method carried]) go through
## each portal with it: they ride in its ShipCodec dict ("escorts") and
## come out of the far gate beside it. Without escorts left it flies on
## alone. CRUISE: in the target system to the site point on the planet's
## orbit (the angle is set on arrival so the point faces it), DEPLOY:
## [constant DEPLOY_TIME] s riding the orbit with a flash, then the ship
## leaves the world and ForwardStations.found builds the station there;
## its escorts are paid and fly home through the gates.
##
## As data (RemoteSim, not viewed): the transit runs as GateTransit data,
## every system entered as data rolls one ambush ([method ambush_data]:
## danger, bases, escorts), CRUISE and DEPLOY run as timers
## ([method step_data]). The escort contract stays on the board while the
## convoy is data (EscortContract.ward_id) and is linked again when it is
## built live. Destroyed: a feed line, nothing refunded, the contract ends.

enum State { PARKED, WAITING, TRAVEL, CRUISE, DEPLOY }

const STATE_NAMES: PackedStringArray = ["parked", "waiting", "travel", "cruise", "deploy"]
const MOBILE_GROUP := "mobile_stations"
const TUG_PATH := "res://assets/models/ships/colony_ship.glb"
## The tug behind the hub, its nose against the hub (station space).
const TUG_OFFSET := Vector3(0.0, -6.0, 44.0)
const SPEED := 90.0
const HULL := 5000.0
const ESCORT_PAY := 200
const MAX_ESCORTS := 3
## An escort this close lets it leave; farther than the lost range it waits; m.
const ESCORT_JOIN_RANGE := 600.0
const ESCORT_LOST_RANGE := 1500.0
## Escorts this close go through a portal with it (and are saved with it), m.
const CARRY_RANGE := 3000.0
## Formation for warp hops: every escort this close, m.
const FORMATION_RANGE := 900.0
## Close enough to the site point to deploy; from this close the tug
## flies in the point's frame ([method _close_in]); m.
const ARRIVE_RANGE := 120.0
const APPROACH_RANGE := 4000.0
const DEPLOY_TIME := 8.0
## Warp to the site only from this far, m.
const WARP_MIN := 4000.0
## Data ambush: chance per danger level, per standing base, cover per escort, cap.
const AMBUSH_PER_DANGER := 0.06
const AMBUSH_PER_BASE := 0.06
const AMBUSH_ESCORT_COVER := 0.08
const AMBUSH_MAX := 0.6
## Data ambush damage: share of the station's max hull, and of an escort's.
const AMBUSH_HULL := Vector2(0.08, 0.3)
const AMBUSH_ESCORT_HULL := Vector2(0.15, 0.45)

var number: int = 1
var state: State = State.PARKED
## Destination system and site ({planet, orbit_radius, period, angle}).
var dest: StringName = &""
var site: Dictionary = {}
var escort_pay: int = ESCORT_PAY
var contract: EscortContract
## Parking spot in home's structures frame (PARKED, WAITING).
var park_offset := Vector3.INF
## DEPLOY: seconds so far.
var deploy_t: float = 0.0
## A reason the last step could not go on ("" = none), for the status line.
var note: String = ""
## Escorts made from the save dict, finished in [method finish_restore].
var _pending: Array = []
var _contract_sid: int = 0
var _flashed := false


func _init() -> void:
	role = Role.STATION
	hit_radius = 55.0
	bank_max_deg = 3.0
	bob_height = 0.3


## Call before adding to the tree. [param n] <= 0: the next free number
## ([param tree] needed then).
func setup_station(n: int = 0, tree: SceneTree = null) -> void:
	number = n if n > 0 else next_number(tree)
	_model_path = HomeStation.FORWARD_PATH
	name = StringName("MobileStation_%d" % number)
	var l := ShipLoadout.new()
	l.role_name = ROLE_NAMES[Role.STATION]
	l.base_hull = HULL
	l.base_speed = SPEED
	l.base_acceleration = 7.0
	l.base_turn_rate_deg = 14.0
	l.base_sensor_range = 1500.0
	loadout = l


func _on_ready_ship() -> void:
	add_to_group(MOBILE_GROUP)
	set_meta(&"focus_radius", 60.0)
	set_meta(&"focus_distance", 420.0)
	mover.hold()


func _prepare_model(m: Node3D) -> void:
	var tug := ModelLoader.instantiate(TUG_PATH, ModelLoader.ship_placeholder)
	tug.name = "Tug"
	tug.position = TUG_OFFSET
	m.add_child(tug)


func _fallback_model() -> Node3D:
	var inner := ModelLoader.instantiate(HomeStation.STATION_PATH, ModelLoader.ship_placeholder)
	inner.scale = Vector3.ONE * 0.65
	var root := Node3D.new()
	root.name = "station_fallback"
	root.add_child(inner)
	return root


func get_display_name() -> String:
	return "Forward Station %d" % number


func get_status_text() -> String:
	var warp := warp_status_text()
	if not warp.is_empty():
		return warp
	if not note.is_empty():
		return note
	match state:
		State.PARKED:
			return "Parked at home: set a destination"
		State.WAITING:
			return "Waiting for an escort (to %s in %s)" % [String(site.get("planet", "?")), _system_name(dest)]
		State.TRAVEL:
			var t := transit.status_text() if transit else "Travelling"
			return "%s, bound for %s" % [t, _system_name(dest)]
		State.CRUISE:
			return "Flying to %s orbit" % String(site.get("planet", "?"))
		State.DEPLOY:
			return "Deploying at %s (%d%%)" % [String(site.get("planet", "?")), roundi(deploy_t / DEPLOY_TIME * 100.0)]
	return "Idle"


## Danger of the trip (the destination's), for the escort contract.
func route_danger() -> int:
	var e := Sector.network.entry(dest) if Sector.network and not dest.is_empty() else null
	return clampi(e.danger if e else 1, 1, 5)


# --- Combatant ------------------------------------------------------------------

func take_hit(amount: float, attacker: Node3D, at: Vector3) -> void:
	super.take_hit(amount, attacker, at)
	if not dead:
		ColonyAlarm.raise(self, self, get_display_name(), attacker)


func can_warp() -> bool:
	if not _formation_ready():
		return false
	match state:
		State.TRAVEL:
			return transit != null and transit.can_warp()
		State.CRUISE:
			return SpaceNav.flat_distance(global_position, _site_point()) > WARP_MIN
	return false


## Never: it flies straight at its goal's height (a cruise arc keeps a slow
## hull climbing and it never gets level for a warp hop).
func cruise_free() -> bool:
	return false


func warp_destination() -> String:
	if state == State.CRUISE:
		return String(site.get("planet", ""))
	return super.warp_destination()


func _on_destroyed(_killer: Node3D) -> void:
	EventLog.post("%s was destroyed in %s: the station is lost, nothing refunded" % [get_display_name(), _system_name(_here())],
			EventLog.Kind.LOSS, null, global_position)


## Leaving this world (a jump, the system going to data, destroyed): the
## escort contract waits for the ship by save id.
func _leave_world() -> void:
	if contract and not contract.is_finished():
		contract.ward = null
		contract.ward_id = SaveIds.of(self)
		contract.ward_name = get_display_name()
		contract.target = null
	super._leave_world()


# --- Orders -------------------------------------------------------------------------

## Why [method set_destination] would refuse [param planet] of
## [param system_id], or "".
func destination_problem(system_id: StringName, planet: PlanetBody) -> String:
	if state != State.PARKED and state != State.WAITING:
		return "%s is already on its way" % get_display_name()
	var why := ForwardStations.site_problem(get_tree(), system_id, planet, self)
	if not why.is_empty():
		return why
	if contract == null or contract.is_finished():
		why = ContractBoard.post_problem(escort_pay)
	return why


## Sets the destination (a planet in another system) and posts the escort
## contract (kept when one is open). False with a reason in [member note].
func set_destination(system_id: StringName, planet: PlanetBody) -> bool:
	var why := destination_problem(system_id, planet)
	if not why.is_empty():
		push_warning("MobileStation: %s" % why)
		return false
	dest = system_id
	site = ForwardStations.site_on(system_id, planet.def.name)
	if contract == null or contract.is_finished():
		var c := ContractBoard.post_escort(self, escort_pay, MAX_ESCORTS)
		if c == null:
			return false
		_link_contract(c)
	state = State.WAITING
	note = ""
	EventLog.post("%s will fly to %s in %s: escort contract posted (%d cr per escort)" % [get_display_name(), planet.def.name, _system_name(dest), escort_pay],
			EventLog.Kind.INFO, self)
	status_changed.emit(self)
	return true


## Back to PARKED (only before it leaves); the escort contract is cancelled.
func cancel_destination() -> void:
	if state != State.WAITING:
		return
	if contract and not contract.is_finished():
		ContractBoard.cancel(contract)
	contract = null
	state = State.PARKED
	dest = &""
	site = {}
	status_changed.emit(self)


## New escort pay, also for the open contract (nothing is reserved).
func set_escort_pay(pay: int) -> void:
	escort_pay = maxi(pay, 0)
	if contract and not contract.is_finished():
		contract.reward = escort_pay
		contract.changed.emit(contract)


# --- Escorts ------------------------------------------------------------------------

## Live escorts on its contract in this system.
func escorts() -> Array[Ship]:
	var out: Array[Ship] = []
	if contract == null or contract.is_finished():
		return out
	for e in contract.escorts_of(self):
		if is_instance_valid(e) and not e.dead and SystemWorld.of(e) == SystemWorld.of(self):
			out.append(e)
	return out


## Escorts that go through a portal with it (and are saved inside its dict).
func carried() -> Array[Ship]:
	var out: Array[Ship] = []
	for e in escorts():
		if carrier_of(e) == self:
			out.append(e)
	return out


## The mobile station [param s] (an escort) rides with, or null.
static func carrier_of(s: Ship) -> MobileStation:
	var mb := s.brain as MercenaryBrain if s else null
	if mb == null or s.dead or s.transit or s.is_docked() or mb.mode != MercenaryBrain.Mode.ESCORT or mb.trip == null:
		return null
	var ec := mb.trip.contract as EscortContract
	if ec == null or not is_instance_valid(ec.ward):
		return null
	var ms := ec.ward as MobileStation
	if ms == null or ms.dead or not ms.is_inside_tree() or SystemWorld.of(ms) != SystemWorld.of(s):
		return null
	return ms if ms.global_position.distance_to(s.global_position) <= CARRY_RANGE else null


## Through the portal: the carried escorts leave the world too (they are
## in the station's dict already).
func release_carried(where: String) -> void:
	for e in carried():
		GateTransit.detach(e, where)


func _formation_ready() -> bool:
	for e in escorts():
		if e.transit == null and e.global_position.distance_to(global_position) > FORMATION_RANGE:
			return false
	return true


func _escorts_lagging() -> bool:
	for e in escorts():
		if e.transit == null and e.global_position.distance_to(global_position) > ESCORT_LOST_RANGE:
			return true
	return false


func _link_contract(c: EscortContract) -> void:
	contract = c
	if c == null:
		return
	c.ward = self
	c.target = self
	c.ward_id = 0
	c.system_id = _here()
	var keep: Array[Node] = []
	for t in c.takers:
		if is_instance_valid(t) and not (t as Ship).dead:
			keep.append(t)
	c.takers = keep
	for e in c.assignments.keys():
		if not is_instance_valid(e) or not is_instance_valid(c.assignments[e]):
			c.assignments.erase(e)
	ContractBoard.wire_escort(c)
	c.changed.emit(c)


# --- Live ----------------------------------------------------------------------------

func sim_step(dt: float) -> void:
	if dead:
		return
	mover.max_speed = 1.0 if (state == State.TRAVEL or state == State.CRUISE) and _escorts_lagging() else max_speed
	super.sim_step(dt)
	if dead or dt <= 0.0 or not is_inside_tree():
		return
	match state:
		State.PARKED, State.WAITING:
			_park()
			if state == State.WAITING:
				_wait_step()
		State.TRAVEL:
			if transit == null:
				# A transit lost on the way (no gate): the trip ends here.
				on_trip_done()
		State.CRUISE:
			_cruise_step(dt)
		State.DEPLOY:
			_deploy_step(dt)


func _park() -> void:
	var mgr := BuildingManager.of(self)
	if mgr == null or mgr.frame == null:
		mover.hold()
		return
	if park_offset == Vector3.INF:
		park_offset = mgr.frame.to_local(global_position)
	set_world_goal(mgr.frame.to_global(park_offset), SpaceNav.world_velocity(mgr.frame), Vector3.ZERO, 25.0)


func _wait_step() -> void:
	if contract == null or contract.is_finished():
		EventLog.post("%s: escort contract ended, the trip is off" % get_display_name(), EventLog.Kind.INFO, self)
		contract = null
		state = State.PARKED
		status_changed.emit(self)
		return
	var joined: Ship = null
	for e in escorts():
		if e.global_position.distance_to(global_position) <= ESCORT_JOIN_RANGE:
			joined = e
			break
	if joined == null:
		return
	var hops := Sector.hops_between(_here(), dest)
	if hops.is_empty() or GateTransit.start(self, hops) == null:
		note = "No gate route to %s" % _system_name(dest)
		return
	state = State.TRAVEL
	note = ""
	EventLog.post("%s left for %s with %s (%d escort%s)" % [get_display_name(), _system_name(dest), joined.get_display_name(), escorts().size(),
			"" if escorts().size() == 1 else "s"], EventLog.Kind.INFO, self)
	status_changed.emit(self)


## GateTransit: the last hop is done (or the transit gave up).
func on_trip_done() -> void:
	if _here() == dest:
		_begin_cruise()
	else:
		note = "Stranded in %s" % _system_name(_here())


func _begin_cruise() -> void:
	state = State.CRUISE
	site["angle"] = facing_angle(site, _planet_position(_here(), site, SimClock.time), global_position, SimClock.time)
	EventLog.post("%s arrived in %s: flying to %s" % [get_display_name(), _system_name(dest), String(site.get("planet", "?"))], EventLog.Kind.INFO, self)
	status_changed.emit(self)


func _cruise_step(dt: float) -> void:
	var p := _site_point()
	if p == Vector3.INF:
		note = "%s is not in this system" % String(site.get("planet", "?"))
		mover.hold()
		return
	var d := SpaceNav.flat_distance(global_position, p)
	if d > APPROACH_RANGE or mover.warp_state != ShipMover.Warp.IDLE:
		# Far out: fly (and warp) at where the point will be.
		var ahead := clampf(d / SPEED, 0.0, 120.0) * 0.5
		set_world_goal(_site_point(SimClock.time + ahead), _site_velocity(), Vector3.ZERO, 40.0)
	else:
		_close_in(p, d, dt)
	if mover.warp_state == ShipMover.Warp.IDLE and d < ARRIVE_RANGE:
		state = State.DEPLOY
		deploy_t = 0.0
		_flashed = false
		status_changed.emit(self)


## Near the site the tug flies it in the planet's moving frame: at most
## [constant SPEED] relative to the point (the point and the planet move
## about as fast as the station).
func _close_in(p: Vector3, d: float, dt: float) -> void:
	var to := p - global_position
	var stepv := to.limit_length(SPEED * dt)
	mover.velocity = Vector3.ZERO
	mover.hold()
	global_position += stepv + _site_velocity() * dt
	if d > 30.0:
		var want := ShipMover.yaw_for(Vector3(to.x, 0.0, to.z))
		set_heading(lerp_angle(mover.yaw, want, clampf(dt * 0.4, 0.0, 1.0)))


func _deploy_step(dt: float) -> void:
	var p := _site_point()
	if p == Vector3.INF:
		return
	deploy_t += dt
	var k := clampf(deploy_t / DEPLOY_TIME, 0.0, 1.0)
	global_position = global_position.lerp(p, clampf(dt * 1.5, 0.0, 1.0))
	mover.velocity = Vector3.ZERO
	mover.hold()
	if not _flashed and k >= 0.85:
		_flashed = true
		WarpFx.flash(self, global_position, 120.0, Color(1.0, 0.8, 0.5), 1.4)
	if k >= 1.0:
		_found()


func _found() -> void:
	var sid := _here()
	var s := site.duplicate()
	var fs := ForwardStations.of(get_tree())
	var why := fs.found_problem(sid, s) if fs else "No forward stations"
	if not why.is_empty():
		note = "Cannot found here: %s" % why
		state = State.CRUISE
		return
	var tree := get_tree()
	var c := contract
	var at := global_position
	contract = null
	dead = true
	_leave_world()
	var w := fs.found(sid, s)
	finish_convoy(tree, w, c, get_display_name())
	if w and w.sys:
		WarpFx.flash(w.sys, at, 160.0, Color(1.0, 0.8, 0.5), 1.6)


## After the founding: the escorts in [param w] on [param c] are paid and
## the contract is done (they fly home through the gates).
static func finish_convoy(_tree: SceneTree, w: SystemWorld, c: EscortContract, who: String) -> void:
	if c == null or c.is_finished():
		return
	var paid := 0
	var n := 0
	if w:
		for node in SystemWorld.nodes_in(w, Ship.GROUP):
			var e := node as Ship
			var mb := e.brain as MercenaryBrain if e else null
			if mb == null or e.dead or mb.trip == null or mb.trip.contract != c:
				continue
			var pay := ContractBoard.pay_captain(e, c.reward, c)
			paid += pay
			n += 1
			if e.captain:
				e.captain.escorts_completed += 1
				e.captain.add_reputation(Reputation.ESCORT_TRIP)
				e.captain.note_job(true)
			e.show_toast("+%d cr escort" % pay, Ship.TOAST_DELIVERY)
	c.trips_completed += 1
	c._set_status(Contract.Status.COMPLETED)
	if n > 0:
		EventLog.post("%s escorts paid: %d escort%s, %s cr" % [who, n, "" if n == 1 else "s", Fmt.amount(paid)], EventLog.Kind.REWARD)


# --- Site ------------------------------------------------------------------------------

## The site point at sim time [param t] (now by default; later: the planet
## moved on by its velocity), world; INF when the planet is not here.
func _site_point(t: float = -1.0) -> Vector3:
	var sys := SolarSystem.of(self)
	var planet := sys.find_child(String(site.get("planet", "")).validate_node_name(), false, false) as PlanetBody if sys else null
	if planet == null:
		return Vector3.INF
	var at := SimClock.time if t < 0.0 else t
	return planet.global_position + SpaceNav.world_velocity(planet) * (at - SimClock.time) + orbit_offset(site, at)


func _site_velocity() -> Vector3:
	var sys := SolarSystem.of(self)
	var planet := sys.find_child(String(site.get("planet", "")).validate_node_name(), false, false) as PlanetBody if sys else null
	if planet == null:
		return Vector3.ZERO
	var a := orbit_angle(site, SimClock.time)
	var r := float(site.get("orbit_radius", 1600.0))
	var period := maxf(float(site.get("period", ForwardStations.ORBIT_PERIOD)), 1.0)
	return SpaceNav.world_velocity(planet) + Vector3(-sin(a), 0.0, cos(a)) * r * TAU / period


static func orbit_angle(s: Dictionary, t: float) -> float:
	return deg_to_rad(float(s.get("angle", 0.0))) + TAU * t / maxf(float(s.get("period", ForwardStations.ORBIT_PERIOD)), 1.0)


## Offset of the site point from its planet (level, like the station orbiter).
static func orbit_offset(s: Dictionary, t: float) -> Vector3:
	var a := orbit_angle(s, t)
	return Vector3(cos(a), 0.0, sin(a)) * float(s.get("orbit_radius", 1600.0))


## Start angle (deg) that puts the site point on the side of [param planet_pos]
## facing [param from] when the ship gets there at [constant SPEED].
static func facing_angle(s: Dictionary, planet_pos: Vector3, from: Vector3, now: float) -> float:
	var d := from - planet_pos
	var eta := now + RemoteSim.leg_time(SpaceNav.flat_length(d), SPEED)
	return rad_to_deg(atan2(d.z, d.x) - TAU * eta / maxf(float(s.get("period", ForwardStations.ORBIT_PERIOD)), 1.0))


## Where the site's planet is in [param sid] at [param t] (the live body,
## else from its PlanetDef orbit).
static func _planet_position(sid: StringName, s: Dictionary, t: float) -> Vector3:
	var def := Sector.system_def(sid)
	if def == null:
		return Vector3.ZERO
	for p in def.planets:
		if p.name == String(s.get("planet", "")):
			var a := deg_to_rad(p.start_angle_deg) + (TAU * t / p.orbit_period if p.orbit_period != 0.0 else 0.0)
			return p.orbit_plane() * Vector3(cos(a), 0.0, sin(a)) * p.orbit_radius
	return Vector3.ZERO


func _here() -> StringName:
	var w := SystemWorld.of(self) if is_inside_tree() else null
	return w.system_id if w else &""


static func _system_name(id: StringName) -> String:
	var def := Sector.system_def(id) if not id.is_empty() else null
	return def.system_name if def else "?"


# --- Save ---------------------------------------------------------------------------

func save_fields() -> Dictionary:
	return {"number": number, "state": state, "dest": String(dest), "site": site.duplicate(true), "pay": escort_pay,
			"park": park_offset if park_offset != Vector3.INF else null, "deploy_t": deploy_t, "note": note,
			"contract": SaveIds.of(contract) if contract and not contract.is_finished() else 0}


## Step 1 of a restore (ShipCodec.create): the station and its carried
## escorts ([param d] "escorts") in [param ctx]'s system.
static func create_from(ctx: Node, d: Dictionary, refs: SaveRefs) -> MobileStation:
	var md: Dictionary = d.get("mobile", {})
	var s := MobileStation.new()
	s.setup_station(int(md.get("number", 0)))
	s.state = int(md.get("state", State.PARKED)) as State
	s.dest = StringName(md.get("dest", ""))
	s.site = (md.get("site", {}) as Dictionary).duplicate(true)
	s.escort_pay = int(md.get("pay", ESCORT_PAY))
	s.deploy_t = float(md.get("deploy_t", 0.0))
	s.note = String(md.get("note", ""))
	var park: Variant = md.get("park", null)
	s.park_offset = park as Vector3 if park is Vector3 else Vector3.INF
	s._contract_sid = int(md.get("contract", 0))
	SpaceNav.space_root(ctx).add_child(s)
	s.mover.avoid_enabled = true
	ShipCodec._place_in_space(s, d)
	var arriving := d.has("transit") and int((d["transit"] as Dictionary).get("phase", -1)) == GateTransit.Phase.ARRIVE
	var i := 0
	for ed: Dictionary in d.get("escorts", []):
		if arriving:
			# Out of the portal beside the station.
			ed["position"] = (d["position"] as Vector3) + Vector3(70.0 * (1 if i % 2 == 0 else -1), 0.0, 60.0 + 30.0 * floorf(i / 2.0))
			ed["velocity"] = Vector3.ZERO
			ed["docked"] = false
		var e := ShipCodec.create(ctx, ed, refs)
		if e:
			s._pending.append([e, ed])
		i += 1
	return s


## Step 2 (ShipCodec.finish): the escort contract and the escorts' brains.
func finish_restore(_d: Dictionary, refs: SaveRefs) -> void:
	var c := refs.find(_contract_sid) as EscortContract if _contract_sid != 0 else null
	if c == null and _contract_sid != 0:
		c = ContractBoard.find_saved(_contract_sid) as EscortContract
	if c and not c.is_finished():
		_link_contract(c)
	for pair: Array in _pending:
		var e := pair[0] as Ship
		ShipCodec.finish(e, pair[1] as Dictionary, refs)
		if contract and is_instance_valid(e) and not e.dead:
			var mb := e.brain as MercenaryBrain
			if mb and mb.trip and mb.trip.contract == contract:
				if not contract.takers.has(e):
					contract.takers.append(e)
				contract.assign(e, self)
	_pending.clear()


# --- As data (RemoteSim) ---------------------------------------------------------------

static func is_mobile(d: Dictionary) -> bool:
	return String(d.get("kind", "")) == ShipCodec.KIND_MOBILE


## One more than the highest number in use (live, as data, or founded).
static func next_number(tree: SceneTree) -> int:
	var top := 0
	if tree:
		for n in tree.get_nodes_in_group(MOBILE_GROUP):
			top = maxi(top, (n as MobileStation).number)
	for d in _all_dicts():
		top = maxi(top, int((d.get("mobile", {}) as Dictionary).get("number", 0)))
	# Founded ones count too: the second Forward Station is "2".
	var fs := ForwardStations.of(tree) if tree else null
	return maxi(top, fs.count() if fs else 0) + 1


## Live or as data, every mobile station.
static func count_all(tree: SceneTree) -> int:
	return _all_dicts().size() + (tree.get_nodes_in_group(MOBILE_GROUP).filter(func(n: Node) -> bool: return not (n as MobileStation).dead).size() if tree else 0)


## A mobile station (other than [param skip]) is headed for [param id].
static func headed_to(tree: SceneTree, id: StringName, skip: Node = null) -> bool:
	if tree:
		for n in tree.get_nodes_in_group(MOBILE_GROUP):
			var ms := n as MobileStation
			if ms != skip and not ms.dead and ms.dest == id and ms.state != State.PARKED:
				return true
	for d in _all_dicts():
		if StringName((d.get("mobile", {}) as Dictionary).get("dest", "")) == id:
			return true
	return false


## Mobile station dicts in the remote systems and in the jump.
static func _all_dicts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: StringName in Sector.states:
		for d: Dictionary in (Sector.states[id] as RemoteSystemState).ships:
			if is_mobile(d):
				out.append(d)
	for t: Dictionary in Sector.transits:
		if is_mobile(t["ship"]):
			out.append(t["ship"])
	return out


## Came out of a gate in [param sid] while that system is data (the dict
## is in its ships already): the escorts beside it, one ambush roll for
## the system; destroyed there, it leaves the list and its escorts stay.
static func on_data_arrival(sid: StringName, d: Dictionary) -> void:
	for ed: Dictionary in d.get("escorts", []):
		ed["position"] = d["position"]
	if not ambush_data(sid, d):
		return
	var st := Sector.state(sid)
	if st:
		st.ships.erase(d)
		for ed: Dictionary in d.get("escorts", []):
			st.ships.append(ed)
	var c := ContractBoard.find_saved(int((d["mobile"] as Dictionary).get("contract", 0)))
	if c and not c.is_finished():
		ContractBoard.cancel(c)


## The last hop as data is done: CRUISE in [param sid] when it is the
## destination. True when it handled [param d] (a mobile station dict).
static func end_transit_data(sid: StringName, d: Dictionary) -> bool:
	if not is_mobile(d):
		return false
	var td: Dictionary = d.get("transit", {})
	if not PackedStringArray(td.get("hops", PackedStringArray())).is_empty():
		return false
	d.erase("transit")
	var md: Dictionary = d["mobile"]
	md["state"] = State.CRUISE
	var s: Dictionary = md.get("site", {})
	s["angle"] = facing_angle(s, _planet_position(sid, s, SimClock.time), d["position"] as Vector3, SimClock.time)
	EventLog.post("Forward Station %d arrived in %s: flying to %s" % [int(md.get("number", 0)), _system_name(sid), String(s.get("planet", "?"))], EventLog.Kind.INFO)
	return true


## One step of mobile station dict [param d] in system [param sid] (not
## live, no transit): CRUISE and DEPLOY as timers, then the founding. True
## when it left the system's ship list.
static func step_data(sim: RemoteSim, sid: StringName, st: RemoteSystemState, d: Dictionary, dt: float) -> bool:
	if d.has("transit"):
		return false
	var md: Dictionary = d["mobile"]
	var s: Dictionary = md.get("site", {})
	match int(md.get("state", State.PARKED)):
		State.CRUISE:
			if not md.has("left"):
				var p := _planet_position(sid, s, SimClock.time) + orbit_offset(s, SimClock.time)
				md["left"] = RemoteSim.leg_time((d["position"] as Vector3).distance_to(p), SPEED)
			md["left"] = float(md["left"]) - dt
			if float(md["left"]) <= 0.0:
				md.erase("left")
				md["state"] = State.DEPLOY
				md["deploy_t"] = 0.0
		State.DEPLOY:
			md["deploy_t"] = float(md.get("deploy_t", 0.0)) + dt
			d["position"] = _planet_position(sid, s, SimClock.time) + orbit_offset(s, SimClock.time)
			if float(md["deploy_t"]) >= DEPLOY_TIME:
				return _found_data(sim.get_tree(), sid, st, d)
	return false


static func _found_data(tree: SceneTree, sid: StringName, st: RemoteSystemState, d: Dictionary) -> bool:
	var md: Dictionary = d["mobile"]
	var fs := ForwardStations.of(tree)
	var s: Dictionary = (md.get("site", {}) as Dictionary).duplicate(true)
	var why := fs.found_problem(sid, s) if fs else "No forward stations"
	if not why.is_empty():
		md["state"] = State.CRUISE
		md["note"] = "Cannot found here: %s" % why
		return false
	st.ships.erase(d)
	for ed: Dictionary in d.get("escorts", []):
		st.ships.append(ed)
	var c := ContractBoard.find_saved(int(md.get("contract", 0))) as EscortContract
	var w := fs.found(sid, s)
	finish_convoy(tree, w, c, "Forward Station %d" % int(md.get("number", 0)))
	return true


## One ambush roll for a convoy entering [param sid] as data: chance by
## the system's danger and standing bases, less per escort; a hit costs
## the station and each escort part of its hull (an escort keeps at least
## 10%). True when the station is lost (at 0).
static func ambush_data(sid: StringName, d: Dictionary) -> bool:
	var md: Dictionary = d["mobile"]
	var rolled: Array = md.get("rolled", [])
	if rolled.has(String(sid)):
		return false
	rolled.append(String(sid))
	md["rolled"] = rolled
	var e := Sector.network.entry(sid) if Sector.network else null
	var st := Sector.state(sid)
	if e == null or st == null:
		return false
	var bases := 0
	for name: String in st.dens:
		if not bool((st.dens[name] as Dictionary).get("dead", false)):
			bases += 1
	if st.dens.is_empty():
		var def := Sector.system_def(sid)
		bases = def.dens.size() if def else 0
	var escorts: Array = d.get("escorts", [])
	var chance := clampf(AMBUSH_PER_DANGER * e.danger + AMBUSH_PER_BASE * bases - AMBUSH_ESCORT_COVER * escorts.size(), 0.0, AMBUSH_MAX)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Sector.get_seed(), String(sid), int(d.get("id", 0)), rolled.size()])
	var roll := rng.randf()
	md["last_roll"] = {"system": String(sid), "chance": chance, "roll": roll}
	if roll >= chance:
		return false
	var dur: Dictionary = d.get("durability", {})
	var max_hull := float(dur.get("max_hull", HULL))
	var loss := max_hull * rng.randf_range(AMBUSH_HULL.x, AMBUSH_HULL.y) * (0.6 + 0.2 * e.danger)
	dur["hull"] = float(dur.get("hull", max_hull)) - loss
	var hurt := 0
	for ed: Dictionary in escorts:
		var edur: Dictionary = ed.get("durability", {})
		var emax := float(edur.get("max_hull", 300.0))
		edur["hull"] = maxf(float(edur.get("hull", emax)) - emax * rng.randf_range(AMBUSH_ESCORT_HULL.x, AMBUSH_ESCORT_HULL.y), emax * 0.1)
		hurt += 1
	var who := "Forward Station %d" % int(md.get("number", 0))
	if float(dur["hull"]) <= 0.0:
		EventLog.post("%s was destroyed by raiders in %s: the station is lost, nothing refunded" % [who, _system_name(sid)], EventLog.Kind.LOSS)
		return true
	EventLog.post("Raiders ambushed %s in %s: hull -%s%s" % [who, _system_name(sid), Fmt.amount(roundi(loss)),
			", %d escort%s damaged" % [hurt, "" if hurt == 1 else "s"] if hurt > 0 else ", no escort to cover it"], EventLog.Kind.COMBAT)
	return false

class_name ShipCodec
extends RefCounted
## Saves and restores every ship: hired ships (miners, mercenaries,
## salvagers), escape pods, cargo shuttles and scavengers. Restoring runs in
## two steps: [method create] puts the ship back (berth or space, hull,
## loadout) and registers it, [method finish] restores what links to other
## objects (the brain's trip and contract, damage tallies), once every ship
## and contract exists.
##
## Brain states restored exactly: docked states with their timers (docked,
## evaluating, resting, repairing, unloading), undocking (it flies out again
## on the same contract), docking (it delivers the trip's load on arrival),
## a miner travelling to or drilling its rock (same rock, same progress), a
## salvager on its cut (same spot, same progress), returning with or
## without a load, fleeing (cargo kept, runs home), mercenary patrols,
## bounty hunts (fleets included, see [method save_fleet]), escorts and
## trips home for repairs. Re-decided on load: an attack target (picked
## again within a fraction of a second), a fleeing captain's guardian (runs
## home instead), cruise arcs and warp hops in progress (the leg starts
## again from where the ship is), a trip whose contract or target could not
## be restored (the ship heads home empty). Scavengers keep their state
## except hunting and attacking, which roam (or raid) and pick a target
## again; shuttles keep their cargo, and one on or near a pad flies its
## approach again.

const KIND_HIRED := "hired"
const KIND_POD := "pod"
const KIND_SHUTTLE := "shuttle"
const KIND_SCAVENGER := "scavenger"

const SLOTS: Array[int] = [ShipModule.Slot.TOOL, ShipModule.Slot.CARGO, ShipModule.Slot.DEFENSE, ShipModule.Slot.ENGINE, ShipModule.Slot.SENSOR]

const BRAIN_FIELDS: PackedStringArray = ["last_refusal", "last_refusal_target", "last_decision", "_timer", "_resting_on_break", "_calm_time", "_threat_timer"]
const MERC_FIELDS: PackedStringArray = ["retreating", "solo_brave", "_patrol_until", "_patrol_angle", "_patrol_point", "_wait_time", "_ward_was_out", "_passing_timer"]
const SHIP_FIELDS: PackedStringArray = ["trip_lowest_hull", "trip_was_hit", "repair_credit", "repair_session_paid", "repair_from", "_visit_timer", "_visit_pending", "_trait_timer"]


# --- Save ---------------------------------------------------------------------

## Every live ship, ready to save. Contracts the ships' trips are on are
## added to [param contracts] (they may be off the board already).
static func save_all(tree: SceneTree, contracts: Array[Contract]) -> Array:
	var out := []
	for n in tree.get_nodes_in_group(Ship.GROUP):
		var s := n as Ship
		if s == null or s.dead or s.is_queued_for_deletion() or not s.is_inside_tree():
			continue
		var d := save_ship(s, contracts)
		if not d.is_empty():
			out.append(d)
	return out


static func save_ship(s: Ship, contracts: Array[Contract]) -> Dictionary:
	var d := {"id": SaveIds.of(s), "docked": s.is_docked(), "position": s.global_position, "velocity": s.get_world_velocity(),
			"yaw": ShipMover.yaw_for(s.global_basis * Vector3.FORWARD), "durability": SaveUtil.durability(s.durability),
			"fields": SaveUtil.props(s, SHIP_FIELDS)}
	if s is ScavengerShip:
		_save_scavenger(s as ScavengerShip, d)
	elif s is CargoShuttle:
		_save_shuttle(s as CargoShuttle, d)
	elif s is EscapePod:
		d["kind"] = KIND_POD
		d["captain"] = SaveIds.of(s.captain)
		d["home"] = SaveIds.of(s.home) if is_instance_valid(s.home) else 0
	elif s.brain and s.captain and is_instance_valid(s.home):
		_save_hired(s, d, contracts)
	else:
		return {}
	return d


static func _save_hired(s: Ship, d: Dictionary, contracts: Array[Contract]) -> void:
	d["kind"] = KIND_HIRED
	d["captain"] = SaveIds.of(s.captain)
	d["home"] = SaveIds.of(s.home)
	d["slot"] = s.slot_index
	var mods := []
	for slot in SLOTS:
		var m := s.loadout.get_module(slot) if s.loadout else null
		mods.append(m.id if m else &"")
	d["modules"] = mods
	var b := s.brain
	var bd := SaveUtil.props(b, BRAIN_FIELDS)
	bd["state"] = b.state
	bd["rng"] = SaveUtil.rng_state(b.rng)
	if b.trip:
		bd["trip"] = _save_trip(b.trip, contracts)
	var mb := b as MercenaryBrain
	if mb:
		bd["merc"] = SaveUtil.props(mb, MERC_FIELDS)
		bd["mode"] = mb.mode
		bd["fleet"] = SaveIds.of(mb.fleet) if mb.fleet else 0
	d["brain"] = bd
	if s is MinerShip:
		d["hold_fill"] = (s as MinerShip).hold_fill
		d["hold_ore"] = (s as MinerShip).hold_ore
	if s is MercenaryShip:
		d["attack_side"] = (s as MercenaryShip).attack_side


static func _save_trip(t: CaptainBrain.Trip, contracts: Array[Contract]) -> Dictionary:
	if t.contract and not contracts.has(t.contract):
		contracts.append(t.contract)
	return {"contract": SaveIds.of(t.contract), "started_at": t.started_at, "escort_requested": t.escort_requested, "meta": t.meta.duplicate(),
			"progress": t.progress, "asteroid": t.asteroid, "ore": t.ore, "standoff_local": t.standoff_local, "work_time": t.work_time,
			"loaded": t.loaded, "cargo": t.cargo}


static func _save_shuttle(s: CargoShuttle, d: Dictionary) -> void:
	d["kind"] = KIND_SHUTTLE
	d["home"] = SaveIds.of(s.home)
	d["slot"] = s.slot_index
	d["shuttle"] = SaveUtil.props(s, ["phase", "cargo", "supplies", "number", "min_station_distance", "total_delivered", "_timer"])


static func _save_scavenger(s: ScavengerShip, d: Dictionary) -> void:
	d["kind"] = KIND_SCAVENGER
	d["den"] = SaveIds.of(s.den) if is_instance_valid(s.den) else 0
	d["scavenger"] = {"callsign": s.callsign, "raider": s.is_raider, "loot": s.loot, "attack_side": s.attack_side,
			"faction": String(s.faction_def.id) if s.faction_def else String(Factions.DEFAULT_ID)}
	if s.ai and s.ai.lead():
		d["scavenger"]["lead"] = SaveIds.of(s.ai.lead())
	if s.ai:
		d["ai"] = SaveUtil.props(s.ai, ["state", "stolen_from", "credits_looted", "_loot_clock"])


# --- Restore, step 1 ----------------------------------------------------------

## Puts the ship of [param d] back and registers it. Null when it cannot be
## (its home or captain is gone).
static func create(tree: SceneTree, d: Dictionary, refs: SaveRefs) -> Ship:
	var s: Ship = null
	match String(d.get("kind", "")):
		KIND_HIRED:
			s = _create_hired(d, refs)
		KIND_POD:
			s = _create_pod(tree, d, refs)
		KIND_SHUTTLE:
			s = _create_shuttle(tree, d, refs)
		KIND_SCAVENGER:
			s = _create_scavenger(tree, d, refs)
	if s == null:
		return null
	refs.add(int(d["id"]), s)
	SaveUtil.apply_props(s, d.get("fields", {}))
	var dur: Dictionary = d.get("durability", {})
	if not dur.is_empty() and s.durability:
		s.durability.hull = clampf(float(dur["hull"]), 1.0, s.durability.max_hull)
		s.durability.shields = clampf(float(dur["shields"]), 0.0, s.durability.max_shields)
	return s


## Space placement: position, heading and speed in the world frame.
static func _place_in_space(s: Ship, d: Dictionary) -> void:
	s.global_position = d["position"] as Vector3
	var yaw := float(d.get("yaw", 0.0))
	s.mover.yaw = yaw
	s.rotation.y = yaw
	var v := d.get("velocity", Vector3.ZERO) as Vector3
	s.mover.velocity = Vector3(v.x, 0.0, v.z)
	s.mover.climb_rate = v.y
	s.mover.hold()


static func _create_hired(d: Dictionary, refs: SaveRefs) -> Ship:
	var home := refs.building(int(d["home"]))
	var cap := refs.captain(int(d["captain"]))
	if home == null or cap == null:
		return null
	var def := home.def
	var s: Ship = def.hire_ship_script.new() as Ship if def.hire_ship_script else MinerShip.new()
	s.setup_ship(cap, def.hire_ship_path, home, int(d.get("slot", 0)))
	s.loadout = _loadout(Ship.ROLE_NAMES[s.role], d.get("modules", []))
	if s is MercenaryShip:
		(s as MercenaryShip).attack_side = float(d.get("attack_side", 1.0))
	var docked := bool(d.get("docked", true))
	home.restore_ship(s, docked)
	if not docked:
		_place_in_space(s, d)
	if s is MinerShip:
		(s as MinerShip).hold_fill = float(d.get("hold_fill", 0.0))
		(s as MinerShip).hold_ore = int(d.get("hold_ore", -1))
	return s


## The role's stock loadout with the saved modules fitted (by module id).
static func _loadout(role_name: String, ids: Array) -> ShipLoadout:
	var l := ShipLoadout.default_for(role_name)
	var catalog := ModuleCatalog.shared()
	for i in mini(ids.size(), SLOTS.size()):
		var id := StringName(ids[i])
		var cur := l.get_module(SLOTS[i])
		if cur and cur.id == id:
			continue
		if id.is_empty():
			l.set_module(SLOTS[i], null)
			continue
		var m := catalog.find(id)
		if m:
			l.set_module(SLOTS[i], m.duplicate() as ShipModule)
		else:
			push_warning("ShipCodec: unknown module '%s', keeping the stock part" % id)
	return l


static func _create_pod(tree: SceneTree, d: Dictionary, refs: SaveRefs) -> Ship:
	var cap := refs.captain(int(d["captain"]))
	if cap == null:
		return null
	var pod := EscapePod.new()
	pod.setup_pod(cap, refs.building(int(d.get("home", 0))))
	SpaceNav.space_root(tree).add_child(pod)
	_place_in_space(pod, d)
	return pod


static func _create_shuttle(tree: SceneTree, d: Dictionary, refs: SaveRefs) -> Ship:
	var home := refs.building(int(d["home"]))
	var depot := CargoDepot.of(home)
	if depot == null:
		return null
	var sd: Dictionary = d.get("shuttle", {})
	var s := CargoShuttle.new()
	s.setup_shuttle(depot, int(d.get("slot", 0)), int(sd.get("number", 1)))
	var phase := int(sd.get("phase", CargoShuttle.Phase.PARKED)) as CargoShuttle.Phase
	var at_home := bool(d.get("docked", true))
	if at_home:
		var berth := depot.berth_transform(s.slot_index)
		s.position = berth.origin
		s.rotation.y = ShipMover.yaw_for(-berth.basis.z)
		home.add_child(s)
	else:
		SpaceNav.space_root(tree).add_child(s)
		s.mover.avoid_enabled = true
		_place_in_space(s, d)
	depot.shuttles.append(s)
	s.cargo = PackedInt32Array(sd.get("cargo", [0, 0, 0]))
	s.supplies = bool(sd.get("supplies", false))
	s.min_station_distance = float(sd.get("min_station_distance", INF))
	s.total_delivered = int(sd.get("total_delivered", 0))
	s._timer = float(sd.get("_timer", 0.0))
	match phase:
		CargoShuttle.Phase.PARKED, CargoShuttle.Phase.LOADING:
			s.phase = phase if at_home else CargoShuttle.Phase.RETURNING
		CargoShuttle.Phase.UNDOCKING:
			# Leaves again from the berth.
			s.phase = CargoShuttle.Phase.LOADING if at_home else CargoShuttle.Phase.OUTBOUND
			s._timer = 0.0
		CargoShuttle.Phase.DOCKING:
			# In the berth already: the next step parks it.
			s.phase = CargoShuttle.Phase.DOCKING if at_home else CargoShuttle.Phase.RETURNING
		CargoShuttle.Phase.OUTBOUND, CargoShuttle.Phase.WAITING_PAD, CargoShuttle.Phase.LANDING, CargoShuttle.Phase.UNLOADING:
			# On or near a pad: flies the approach again (the pad is picked anew).
			s.phase = CargoShuttle.Phase.OUTBOUND if not at_home else CargoShuttle.Phase.LOADING
			s.pad = -1
		_:
			s.phase = CargoShuttle.Phase.RETURNING if not at_home else CargoShuttle.Phase.PARKED
	s._update_cargo_look()
	return s


static func _create_scavenger(tree: SceneTree, d: Dictionary, refs: SaveRefs) -> Ship:
	var den := refs.find(int(d.get("den", 0))) as ScavengerDen
	var sd: Dictionary = d.get("scavenger", {})
	var s := ScavengerShip.new()
	s.setup_scavenger(den, String(sd.get("callsign", "?")), bool(sd.get("raider", false)), Factions.get_def(StringName(sd.get("faction", Factions.DEFAULT_ID))))
	SpaceNav.space_root(tree).add_child(s)
	s.mover.avoid_enabled = true
	_place_in_space(s, d)
	s.loot = float(sd.get("loot", 0.0))
	s.attack_side = float(sd.get("attack_side", 1.0))
	var ai: Dictionary = d.get("ai", {})
	if s.ai and not ai.is_empty():
		SaveUtil.apply_props(s.ai, ai)
		match s.ai.state:
			ScavengerBrain.State.HUNTING, ScavengerBrain.State.ATTACKING:
				s.ai.state = ScavengerBrain.State.RAIDING if s.is_raider else ScavengerBrain.State.ROAMING
	var world := CombatWorld.of(tree)
	if world:
		world.notify_spawned(s)
	return s


# --- Restore, step 2 ----------------------------------------------------------

## Links to other objects: the damage tally and, for hired ships, the brain.
static func finish(s: Ship, d: Dictionary, refs: SaveRefs) -> void:
	var dur: Dictionary = d.get("durability", {})
	if not dur.is_empty():
		SaveUtil.set_durability(s.durability, dur, refs)
	if String(d.get("kind", "")) == KIND_HIRED and s.brain:
		_restore_brain(s, d.get("brain", {}), bool(d.get("docked", true)), refs)
	if s is ScavengerShip and (s as ScavengerShip).ai:
		var lead_id := int((d.get("scavenger", {}) as Dictionary).get("lead", 0))
		if lead_id != 0:
			(s as ScavengerShip).ai.set_lead(refs.ship(lead_id) as ScavengerShip)
	s.status_changed.emit(s)


static func _restore_brain(s: Ship, bd: Dictionary, docked: bool, refs: SaveRefs) -> void:
	var b := s.brain
	var fields := {}
	for k in BRAIN_FIELDS:
		if bd.has(k):
			fields[k] = bd[k]
	SaveUtil.apply_props(b, fields)
	SaveUtil.set_rng(b.rng, bd.get("rng", {}))
	var mb := b as MercenaryBrain
	if mb:
		SaveUtil.apply_props(mb, bd.get("merc", {}))
		mb.mode = int(bd.get("mode", MercenaryBrain.Mode.NONE)) as MercenaryBrain.Mode
	var trip := _load_trip(bd.get("trip", {}), refs)
	var state := int(bd.get("state", CaptainBrain.State.DOCKED)) as CaptainBrain.State
	if docked:
		_restore_docked(s, state, trip)
	elif mb:
		_restore_merc_space(s, mb, state, trip)
	else:
		_restore_worker_space(s, state, trip)


static func _load_trip(td: Dictionary, refs: SaveRefs) -> CaptainBrain.Trip:
	if td.is_empty():
		return null
	var c := refs.find(int(td.get("contract", 0))) as Contract
	if c == null:
		return null
	var t := CaptainBrain.Trip.new()
	t.contract = c
	t.started_at = float(td.get("started_at", 0.0))
	t.escort_requested = bool(td.get("escort_requested", false))
	t.meta = (td.get("meta", {}) as Dictionary).duplicate()
	t.progress = float(td.get("progress", 0.0))
	t.asteroid = int(td.get("asteroid", -1))
	t.ore = int(td.get("ore", 0))
	t.standoff_local = td.get("standoff_local", Vector3.ZERO) as Vector3
	t.work_time = float(td.get("work_time", 10.0))
	t.loaded = bool(td.get("loaded", false))
	t.cargo = float(td.get("cargo", 1.0))
	return t


static func _put_state(b: CaptainBrain, state: CaptainBrain.State) -> void:
	b.state = state
	b.state_changed.emit(b)


## In the berth (or on the docking / undocking path).
static func _restore_docked(s: Ship, state: CaptainBrain.State, trip: CaptainBrain.Trip) -> void:
	var b := s.brain
	match state:
		CaptainBrain.State.DOCKED, CaptainBrain.State.EVALUATING, CaptainBrain.State.RESTING, CaptainBrain.State.UNLOADING, \
				CaptainBrain.State.REPAIRING:
			b.trip = null if state != CaptainBrain.State.UNLOADING else trip
			_put_state(b, state)
		CaptainBrain.State.DOCKING:
			# Already in the berth: the next step delivers the trip's load.
			b.trip = trip
			_put_state(b, state)
		CaptainBrain.State.UNDOCKING:
			if trip == null and (b as MercenaryBrain) == null:
				_put_state(b, CaptainBrain.State.DOCKED)
				return
			b.trip = trip
			_put_state(b, state)
			s.start_undock()
		_:
			b.trip = null
			_put_state(b, CaptainBrain.State.DOCKED)


## A miner or salvager out in space.
static func _restore_worker_space(s: Ship, state: CaptainBrain.State, trip: CaptainBrain.Trip) -> void:
	var b := s.brain
	match state:
		CaptainBrain.State.TRAVELING_TO_JOB, CaptainBrain.State.MINING:
			if trip and _reclaim_job(s, trip):
				b.trip = trip
				_put_state(b, state)
				return
			b.trip = null
			_put_state(b, CaptainBrain.State.RETURNING)
		CaptainBrain.State.RETURNING, CaptainBrain.State.FLEEING:
			b.trip = trip if trip and trip.loaded else null
			_put_state(b, state)
		_:
			b.trip = trip if trip and trip.loaded else null
			_put_state(b, CaptainBrain.State.RETURNING)


## Takes back the rock (miners) or the work spot (salvagers) the trip had.
static func _reclaim_job(s: Ship, trip: CaptainBrain.Trip) -> bool:
	if s is SalvagerShip:
		var sc := trip.contract as SalvageContract
		if sc == null or not is_instance_valid(sc.field) or not trip.meta.has("hover"):
			return false
		(s as SalvagerShip)._take_slot(sc.field)
		return true
	var mc := trip.contract as MiningContract
	if mc == null or not is_instance_valid(mc.belt) or trip.asteroid < 0 or trip.asteroid >= mc.belt.get_asteroid_count():
		return false
	(s as MinerShip)._claim(mc.belt, trip.asteroid)
	return true


static func _restore_merc_space(s: Ship, mb: MercenaryBrain, state: CaptainBrain.State, trip: CaptainBrain.Trip) -> void:
	match state:
		CaptainBrain.State.PATROLLING, CaptainBrain.State.ENGAGING, CaptainBrain.State.ESCORTING, CaptainBrain.State.HUNTING:
			var needs_trip := mb.mode == MercenaryBrain.Mode.BOUNTY or mb.mode == MercenaryBrain.Mode.ESCORT
			if mb.mode == MercenaryBrain.Mode.NONE or (needs_trip and trip == null):
				mb.trip = null
				mb.mode = MercenaryBrain.Mode.NONE
				_put_state(mb, CaptainBrain.State.RETURNING)
				return
			mb.trip = trip if needs_trip else null
			mb._enter_work_state()
		_:
			mb.trip = null
			_put_state(mb, CaptainBrain.State.RETURNING)
	s.status_changed.emit(s)


# --- Fleets -------------------------------------------------------------------

static func save_fleet(f: MercFleet) -> Dictionary:
	var members := []
	for m in f.members:
		if is_instance_valid(m):
			members.append(SaveIds.of(m))
	var roster := []
	for key in f.roster:
		var r: Dictionary = f.roster[key]
		var o := (r["ref"] as WeakRef).get_ref() as Ship
		roster.append({"ship": SaveIds.of(o) if o else 0, "name": r["name"], "rank": r["rank"], "left_early": r["left_early"], "lost": r["lost"]})
	return {"id": SaveIds.of(f), "contract": SaveIds.of(f.contract), "leader": SaveIds.of(f.leader) if is_instance_valid(f.leader) else 0,
			"members": members, "roster": roster, "state": f.state, "wanted": f.wanted, "called_at": f.called_at,
			"leader_name": f.leader_name, "next_invite": f._next_invite}


## Rebuilds a fleet and hands it to its contract and members. Null when the
## contract or every member is gone.
static func restore_fleet(d: Dictionary, refs: SaveRefs) -> MercFleet:
	var c := refs.find(int(d.get("contract", 0))) as BountyContract
	if c == null:
		return null
	var f := MercFleet.new()
	f.contract = c
	f.state = int(d.get("state", MercFleet.State.FORMING)) as MercFleet.State
	f.wanted = int(d.get("wanted", 2))
	f.called_at = float(d.get("called_at", SimClock.time))
	f.leader_name = String(d.get("leader_name", ""))
	f._next_invite = float(d.get("next_invite", SimClock.time))
	for id: int in d.get("members", []):
		var s := refs.ship(id)
		var mb := s.brain as MercenaryBrain if s else null
		if mb == null:
			continue
		f.members.append(s)
		mb.fleet = f
	if f.members.is_empty():
		return null
	f.leader = refs.ship(int(d.get("leader", 0)))
	if not f.members.has(f.leader):
		f.leader = f.members[0]
		f.leader_name = f.leader.get_display_name()
	var fake_id := -1
	for r: Dictionary in d.get("roster", []):
		var s := refs.ship(int(r["ship"]))
		# Lost members keep their row (the split skips them) under a stand-in key.
		var key: int = s.get_instance_id() if s else fake_id
		if s == null:
			fake_id -= 1
		f.roster[key] = {"ref": weakref(s) if s else SaveUtil.dead_ref(), "name": r["name"], "rank": r["rank"], "left_early": r["left_early"], "lost": r["lost"]}
	if f.state != MercFleet.State.DONE:
		c.fleet = f
	refs.add(int(d.get("id", 0)), f)
	return f

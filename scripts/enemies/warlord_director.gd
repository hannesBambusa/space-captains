class_name WarlordDirector
extends Node
## Pirate warlords (boss threat, home only; child "WarlordDirector" of home's
## CombatWorld, saved as "warlord"). A named warlord in a [WarlordShip]
## flagship with escorts warps in mid-game, raids the colony and hunts its
## ships. Phases:
## - WAITING: the first warlord comes once the base arrival clock
##   (ThreatDirector.threat_time, so the sector modifier counts) passes
##   [constant FIRST_THREAT] and a pirate base stands; a later one at
##   [member next_at].
## - WARNED: [constant WARN_TIME] s of warning (feed and toast), then it
##   warps in [constant ARRIVE_DIST] out from the station on the side of
##   the strongest base, with [method escort_count] escorts guarding it.
## - PRESENT: it raids (ScavengerBrain raider, objective from the
##   RaidDirector). Below WarlordShip.RETREAT_HULL it breaks off and warps
##   out: AWAY, back after [constant RETURN_TIME] (+- jitter) with full hull
##   and one escort more. Every player captain it kills is counted.
## - Destroyed: a corporate reward ([constant REWARD] + [constant REWARD_STEP]
##   per visit, Ledger.BOUNTIES), a big scrap field, a Mk II or Mk III part
##   for the Factory, reputation for every captain who hit it; the next
##   warlord (a new name, one escort more) comes [constant NEXT_TIME] later.
## The flagship and escorts are saved as ships (ShipCodec, "warlord" dict);
## this node keeps the schedule and the story (name, kills, visits).

signal changed

enum Phase { WAITING, WARNED, PRESENT, AWAY }

const FIRST_THREAT := 2700.0
const WARN_TIME := 90.0
const RETURN_TIME := 720.0
const RETURN_JITTER := 120.0
const NEXT_TIME := 2400.0
const ARRIVE_DIST := 26000.0
const BASE_ESCORTS := 2
const MAX_ESCORTS := 5
const ESCORT_GUARD := 650.0
const REWARD := 3000
const REWARD_STEP := 1000
const SCRAP_MULT := 10
const CHECK_EVERY := 1.0

const NAMES: PackedStringArray = ["Vex Harrow", "Mara Kilgore", "Dagny Iron", "Oskar Venn", "Tamsin Red", "Hollis Crane",
		"Juno Marrow", "Silas Brand", "Kestrel Vaine", "Rook Adair", "Nadia Thorn", "Cassius Grey"]
const TITLES := {&"scavenger": "the Scrap Baron", &"corsair": "Admiral of the Drift", &"syndicate": "the Syndicate Enforcer"}

var phase: Phase = Phase.WAITING
var warlord_name: String = ""
var title: String = ""
var faction_id: StringName = &""
var visit: int = 0
## Warlords so far (each new one brings one escort more).
var generation: int = 0
var kills: int = 0
var warn_at: float = -1.0
var return_at: float = -1.0
var next_at: float = -1.0
var used: PackedStringArray = []
## The arrival point while WARNED (world, on the plane).
var point := Vector3.INF
## Debug and tests: arrive even without a pirate base.
var force := false
## Off while the tutorial game runs (Tutorial._apply_safety): no new warlord.
var enabled := true

var ship: WarlordShip
var _rng := RandomNumberGenerator.new()
var _clock := 0.0


static func of(n: Node) -> WarlordDirector:
	var w := CombatWorld.of(n)
	return w.warlords if w else null


func _ready() -> void:
	_rng.randomize()
	add_to_group(SimStepper.GROUP)
	var w := CombatWorld.of(self)
	if w:
		w.combatant_destroyed.connect(_on_destroyed)


func _process(delta: float) -> void:
	if not SimClock.paused:
		sim_step(delta * SimClock.speed)


func sim_step(dt: float) -> void:
	_clock -= dt
	if _clock > 0.0:
		return
	_clock = CHECK_EVERY
	match phase:
		Phase.WAITING:
			if enabled and _due():
				_warn()
		Phase.WARNED:
			if SimClock.time >= warn_at:
				_arrive()
		Phase.AWAY:
			if SimClock.time >= return_at:
				_warn()
		Phase.PRESENT:
			if not is_instance_valid(ship) or ship.dead:
				# Gone without on_killed / on_escaped (should not happen): start over.
				ship = null
				phase = Phase.AWAY
				return_at = SimClock.time + RETURN_TIME


func _due() -> bool:
	if next_at >= 0.0:
		return SimClock.time >= next_at and (force or _strongest_den() != null)
	var w := CombatWorld.of(self)
	var t := w.threats.threat_time if w and w.threats else SimClock.time
	return t >= FIRST_THREAT and (force or _strongest_den() != null)


func escort_count() -> int:
	return clampi(BASE_ESCORTS + generation - 1 + visit - 1, BASE_ESCORTS, MAX_ESCORTS)


## Text for the overview and the feed: "" while nothing is known.
func outlook_text() -> String:
	match phase:
		Phase.WARNED:
			return "Warlord %s inbound, %s" % [warlord_name, Fmt.clock(maxf(warn_at - SimClock.time, 0.0))]
		Phase.PRESENT:
			return "Warlord %s in the system (%d escorts)" % [warlord_name, _escorts_alive()]
		Phase.AWAY:
			return "Warlord %s licking their wounds, back in ~%s" % [warlord_name, Fmt.clock(maxf(return_at - SimClock.time, 0.0))]
	return ""


# --- Arrival ---------------------------------------------------------------------

func _warn() -> void:
	if phase == Phase.WAITING:
		_new_warlord()
	visit += 1
	phase = Phase.WARNED
	warn_at = SimClock.time + WARN_TIME
	point = _arrival_point()
	var again := visit > 1
	var line := ("Long-range scans: Warlord %s is coming back for revenge with %d escorts, arriving in ~%s" if again
			else "Long-range scans: Warlord %s, %s, is moving on Solace with %d escorts, arriving in ~%s")
	if again:
		line = line % [warlord_name, escort_count(), Fmt.clock(WARN_TIME)]
	else:
		line = line % [warlord_name, title, escort_count(), Fmt.clock(WARN_TIME)]
	EventLog.post(line, EventLog.Kind.THREAT, null, point, "", faction_id)
	_toast("Warlord raid: %s inbound" % warlord_name)
	changed.emit()


func _new_warlord() -> void:
	generation += 1
	visit = 0
	kills = 0
	var den := _strongest_den()
	var fdef: FactionDef = den.faction_def if den else Factions.scavengers()
	faction_id = fdef.id
	var pool: PackedStringArray = []
	for n in NAMES:
		if not used.has(n):
			pool.append(n)
	if pool.is_empty():
		used.clear()
		pool = NAMES
	warlord_name = pool[_rng.randi() % pool.size()]
	used.append(warlord_name)
	title = String(TITLES.get(faction_id, "the Pirate Lord"))


func _arrive() -> void:
	var fdef := Factions.get_def(faction_id)
	var root := SpaceNav.space_root(self)
	var w := WarlordShip.new()
	w.setup_warlord(fdef, warlord_name, title, visit)
	root.add_child(w)
	w.global_position = point
	var home := _station_pos()
	var inward := home - point
	inward.y = 0.0
	w.set_heading(ShipMover.yaw_for(inward.normalized() if inward.length() > 1.0 else Vector3.FORWARD))
	w.mover.avoid_enabled = true
	ship = w
	_aim(w)
	WarpFx.flash(w, point, 90.0)
	var world := CombatWorld.of(self)
	if world:
		world.notify_spawned(w)
	for i in escort_count():
		var e := ScavengerShip.new()
		e.setup_scavenger(null, "%s-%d" % [warlord_name.get_slice(" ", 0), i + 1], true, fdef)
		root.add_child(e)
		var side := Vector3(cos(TAU * i / float(escort_count())), 0.0, sin(TAU * i / float(escort_count()))) * 160.0
		e.global_position = point + side
		e.set_heading(w.mover.yaw if w.mover else 0.0)
		e.mover.avoid_enabled = true
		if e.ai:
			e.ai.set_guard(w, ESCORT_GUARD, 120.0)
		WarpFx.flash(e, e.global_position, 30.0)
		if world:
			world.notify_spawned(e)
	phase = Phase.PRESENT
	EventLog.post("Warlord %s has arrived: the flagship and %d escorts warped in. Post a bounty on the flagship to draw mercenaries" % [warlord_name, escort_count()],
			EventLog.Kind.THREAT, w, Vector3.INF, "", faction_id)
	_toast("Warlord raid: %s has arrived" % warlord_name)
	changed.emit()


## Sends the flagship at the colony like a raid (the RaidDirector's pick).
func _aim(w: WarlordShip) -> void:
	var world := CombatWorld.of(self)
	var raids := world.raids if world else null
	var den := _strongest_den()
	if raids and den and w.ai:
		var o := raids.pick_objective(den)
		var t := o.get("target") as Node3D
		if is_instance_valid(t):
			w.ai.set_raid_objective(t)
			return
	var mgr := BuildingManager.of(self)
	if mgr and mgr.station_hull and w.ai:
		w.ai.set_raid_objective(mgr.station_hull)


func _arrival_point() -> Vector3:
	var home := _station_pos()
	var den := _strongest_den()
	var dir := Vector3.ZERO
	if den:
		dir = den.global_position - home
	dir.y = 0.0
	if dir.length() < 1.0:
		var a := _rng.randf() * TAU
		dir = Vector3(cos(a), 0.0, sin(a))
	return home + dir.normalized() * ARRIVE_DIST


## The pirate base of the toughest faction (Syndicate over Corsairs over
## Scavengers), null when none stands.
func _strongest_den() -> ScavengerDen:
	var best: ScavengerDen = null
	var rank := {&"scavenger": 0, &"corsair": 1, &"syndicate": 2}
	for n in SystemWorld.nodes_in(self, ScavengerDen.GROUP):
		var d := n as ScavengerDen
		if d == null or not d.is_alive() or d is GateRaidDen or d.faction_def == null:
			continue
		if best == null or int(rank.get(d.faction_def.id, 0)) > int(rank.get(best.faction_def.id, 0)):
			best = d
	return best


func _station_pos() -> Vector3:
	var sys := SolarSystem.of(self)
	return sys.home_station.global_position if sys and is_instance_valid(sys.home_station) else Vector3.ZERO


func _escorts_alive() -> int:
	var n := 0
	for s in SystemWorld.nodes_in(self, Ship.GROUP):
		var e := s as ScavengerShip
		if e and not e.dead and not e is WarlordShip and e.ai and e.ai.guard == ship and is_instance_valid(ship):
			n += 1
	return n


# --- Outcomes --------------------------------------------------------------------

func on_escaped(w: WarlordShip) -> void:
	if w != ship:
		return
	ship = null
	phase = Phase.AWAY
	return_at = SimClock.time + RETURN_TIME + _rng.randf_range(-RETURN_JITTER, RETURN_JITTER)
	EventLog.post("Warlord %s warped out to repair. They will be back, with more ships" % warlord_name,
			EventLog.Kind.REWARD, null, w.global_position, "", faction_id)
	_toast("Warlord %s driven off" % warlord_name)
	changed.emit()


func on_killed(w: WarlordShip, killer: Node3D) -> void:
	if w != ship:
		return
	ship = null
	var reward := REWARD + REWARD_STEP * maxi(visit - 1, 0)
	Economy.add(reward, PackedInt32Array(), Ledger.BOUNTIES, "Corporate reward: Warlord %s" % warlord_name)
	var world := CombatWorld.of(self)
	if world:
		world.spawn_scrap(w.global_position, world.ship_scrap * SCRAP_MULT, world.ship_scrap_life * 3.0, 90.0,
				"%s's flagship wreck" % warlord_name, w)
	var part := _part_for(visit)
	var f := Factory.find(self)
	if part and f:
		f.add_rare_part(part)
	var heroes: PackedStringArray = []
	for o in w.durability.attackers(240.0):
		var s := o as Ship
		if s and s.captain and s.faction == Combat.Faction.PLAYER:
			s.captain.add_reputation(Reputation.KILL * 4.0)
			s.captain.add_history("Fought Warlord %s to the end" % warlord_name)
			heroes.append(s.captain.captain_name)
	var k := killer as Ship
	var by := (" by %s" % k.captain.captain_name) if k and k.captain else ""
	var extra := (", %s for the Factory" % part.display_name) if part and f else ""
	EventLog.post("Warlord %s is dead, shot down%s. Corporate reward %s cr%s" % [warlord_name, by, Fmt.amount(reward), extra],
			EventLog.Kind.REWARD, null, w.global_position, "", faction_id)
	_toast("Warlord %s destroyed" % warlord_name)
	phase = Phase.WAITING
	next_at = SimClock.time + NEXT_TIME
	changed.emit()


func _part_for(nth: int) -> ShipModule:
	var want := 3 if nth >= 2 or _rng.randf() < 0.35 else 2
	var pool: Array[ShipModule] = []
	for m in ModuleCatalog.shared().modules:
		if m.tier == want:
			pool.append(m)
	return pool[_rng.randi() % pool.size()] if not pool.is_empty() else null


func _on_destroyed(n: Node3D, killer: Node3D) -> void:
	var s := n as Ship
	if s == null or s.captain == null or s.faction != Combat.Faction.PLAYER:
		return
	if killer != null and is_instance_valid(ship) and killer == ship:
		kills += 1
		EventLog.post("Warlord %s killed %s (%d of your captains so far)" % [warlord_name, s.captain.captain_name, kills],
				EventLog.Kind.THREAT, ship, Vector3.INF, "", faction_id)


func _toast(text: String) -> void:
	var pm := get_tree().root.get_node_or_null(^"PauseMenu") if is_inside_tree() else null
	if pm and pm.has_method(&"toast"):
		pm.call(&"toast", text)


# --- Save ------------------------------------------------------------------------

func save_state() -> Dictionary:
	return {"phase": int(phase), "name": warlord_name, "title": title, "faction": String(faction_id), "visit": visit,
			"generation": generation, "kills": kills, "warn_at": warn_at, "return_at": return_at, "next_at": next_at,
			"used": Array(used), "point": [point.x, point.y, point.z] if point != Vector3.INF else []}


func load_state(d: Dictionary) -> void:
	if d.is_empty():
		return
	phase = clampi(int(d.get("phase", 0)), 0, Phase.AWAY) as Phase
	warlord_name = String(d.get("name", ""))
	title = String(d.get("title", ""))
	faction_id = StringName(d.get("faction", ""))
	visit = int(d.get("visit", 0))
	generation = int(d.get("generation", 0))
	kills = int(d.get("kills", 0))
	warn_at = float(d.get("warn_at", -1.0))
	return_at = float(d.get("return_at", -1.0))
	next_at = float(d.get("next_at", -1.0))
	used = PackedStringArray(d.get("used", []))
	var p: Array = d.get("point", [])
	point = Vector3(float(p[0]), float(p[1]), float(p[2])) if p.size() == 3 else Vector3.INF


## After the ships are loaded: finds the flagship again.
func relink() -> void:
	ship = null
	for n in get_tree().get_nodes_in_group(WarlordShip.WARLORD_GROUP):
		var w := n as WarlordShip
		if w and not w.dead and SystemWorld.of(w) == SystemWorld.of(self):
			ship = w
	if phase == Phase.PRESENT and ship == null:
		phase = Phase.AWAY
		return_at = SimClock.time + RETURN_TIME

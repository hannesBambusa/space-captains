class_name DefenseZones
extends Node
## The player's defence zones ([DefenseZone], up to [constant MAX_ZONES]).
## Lives under CombatWorld.
##
## Placing: a centre anywhere in the system (ZonePlacement) and a radius
## ([constant RADIUS_RANGE]). A centre within [constant ANCHOR_REACH] of the
## Home Station rides the station's Structures frame (it moves with the
## station on its orbit); farther out it stays fixed in space.
##
## Kill bounty: credits per raider killed inside, paid from the zone's
## budget. The budget is reserved from the player's credits like a bounty
## (ContractBoard.reserve, counted in ContractBoard.escrow_total); what is
## left comes back when the player takes it out or removes the zone. A kill
## inside pays the player ships that damaged the raider in the last
## BountyContract.CREDIT_WINDOW seconds (and the killer), split evenly, while
## the budget lasts; turrets earn nothing. No captain on the kill: the
## budget keeps it.
##
## Threats: [method threats_near] gives mercenaries the hostile ships in
## every zone near them (MercenaryBrain). A feed line says when raiders
## enter a zone.

signal zones_changed
signal zone_changed(zone: DefenseZone)

const GROUP := "defense_zones"
const MAX_ZONES := 3
const RADIUS_RANGE := Vector2(800.0, 4000.0)
const RADIUS_STEP := 200.0
const DEFAULT_RADIUS := 1500.0
const BOUNTY_MAX := 300
const BOUNTY_STEP := 10
## A zone centre this close to the station moves with it, m.
const ANCHOR_REACH := 5000.0
## Mercenaries this far past a zone's edge still answer raiders inside it, m.
const ENGAGE_REACH := 2500.0
const NAMES: PackedStringArray = ["Picket Alpha", "Picket Bravo", "Picket Charlie", "Picket Delta"]
const SCAN_INTERVAL := 0.5

var zones: Array[DefenseZone] = []
var _next_uid: int = 1
var _scan_at: float = 0.0


static func of(tree: SceneTree) -> DefenseZones:
	return tree.get_first_node_in_group(GROUP) as DefenseZones if tree else null


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(SimStepper.GROUP)
	var world := get_parent() as CombatWorld
	if world:
		world.combatant_destroyed.connect(_on_combatant_destroyed)


func _process(_delta: float) -> void:
	if not SimClock.paused:
		sim_step(0.0)


## Counts the raiders inside each zone (feed line when they come in).
func sim_step(_dt: float) -> void:
	if SimClock.time < _scan_at:
		return
	_scan_at = SimClock.time + SCAN_INTERVAL
	for z in zones:
		if not is_instance_valid(z):
			continue
		var n := z.hostiles_inside().size()
		if n == z.raiders_inside:
			continue
		var was := z.raiders_inside
		z.raiders_inside = n
		z.refresh_look()
		if was == 0 and n > 0:
			EventLog.post("Raiders entered %s (%d): mercenaries nearby will engage" % [z.zone_name, n], EventLog.Kind.THREAT, z, Vector3.INF, "zone_enter:%d" % z.uid)
		zone_changed.emit(z)


# --- Queries ------------------------------------------------------------------

func count() -> int:
	return zones.size()


func by_id(uid: int) -> DefenseZone:
	for z in zones:
		if is_instance_valid(z) and z.uid == uid:
			return z
	return null


## Credits reserved in every zone's budget.
func budget_total() -> int:
	var t := 0
	for z in zones:
		if is_instance_valid(z):
			t += maxi(z.budget, 0)
	return t


## The zone containing [param p] that pays a kill bounty there (largest
## bounty first), else any zone containing it, else null.
func zone_at(p: Vector3, paying_only: bool = false) -> DefenseZone:
	var best: DefenseZone = null
	for z in zones:
		if not is_instance_valid(z) or not z.contains(p):
			continue
		if paying_only and not z.has_paying_bounty():
			continue
		if best == null or (z.has_paying_bounty() and (not best.has_paying_bounty() or z.kill_bounty > best.kill_bounty)):
			best = z
	return best


## Hostile ships inside every zone whose edge is within [param reach] of
## [param pos] (a mercenary or its outpost), nearest to [param pos] first.
func threats_near(pos: Vector3, reach: float = ENGAGE_REACH) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var dists: Array[float] = []
	for z in zones:
		if not is_instance_valid(z) or z.raiders_inside <= 0:
			continue
		if Combat.flat_distance(pos, z.global_position) > z.radius + reach:
			continue
		for h in z.hostiles_inside():
			if out.has(h):
				continue
			var d := Combat.flat_distance(pos, h.global_position)
			var i := dists.bsearch(d)
			dists.insert(i, d)
			out.insert(i, h)
	return out


## Why a zone cannot be placed with its centre at [param world_pos], or "".
func place_problem(world_pos: Vector3) -> String:
	if zones.size() >= MAX_ZONES:
		return "All %d defence zones are placed (remove one first)" % MAX_ZONES
	var sys := get_tree().get_first_node_in_group(SolarSystem.GROUP) as SolarSystem
	if sys and sys.get_extent() > 0.0 and Vector2(world_pos.x, world_pos.z).length() > sys.get_extent():
		return "Outside the system"
	return ""


## Would a zone at [param world_pos] move with the station?
func anchors_at(world_pos: Vector3) -> bool:
	var mgr := get_tree().get_first_node_in_group(BuildingManager.GROUP) as BuildingManager
	return mgr != null and mgr.frame != null and Combat.flat_distance(world_pos, mgr.frame.global_position) <= ANCHOR_REACH


# --- Changes ------------------------------------------------------------------

## Places a new zone with its centre at [param world_pos] (on the plane
## the camera picked). Null when it cannot ([method place_problem]).
func place(world_pos: Vector3, radius: float = DEFAULT_RADIUS) -> DefenseZone:
	if not place_problem(world_pos).is_empty():
		return null
	var z := _make(_free_name(), anchors_at(world_pos))
	z.uid = _next_uid
	_next_uid += 1
	z.radius = clampf(snappedf(radius, RADIUS_STEP), RADIUS_RANGE.x, RADIUS_RANGE.y)
	z.placed_at = SimClock.time
	_attach(z, world_pos, true)
	EventLog.post("%s placed (%.1f km, %s)" % [z.zone_name, z.radius / 1000.0, "moves with the station" if z.anchored else "fixed in space"], EventLog.Kind.INFO, z)
	zones_changed.emit()
	return z


## Removes [param z]; what is left of its budget comes back.
func remove(z: DefenseZone) -> void:
	if not zones.has(z):
		return
	var back := maxi(z.budget, 0)
	z.budget = 0
	ContractBoard.release(back, "Zone budget refund")
	zones.erase(z)
	EventLog.post("%s removed%s" % [z.zone_name, ", %s cr of its budget came back" % UIUtil.amount(back) if back > 0 else ""], EventLog.Kind.INFO)
	z.queue_free()
	zones_changed.emit()


func set_radius(z: DefenseZone, r: float) -> void:
	z.radius = clampf(snappedf(r, RADIUS_STEP), RADIUS_RANGE.x, RADIUS_RANGE.y)
	_changed(z)


func set_kill_bounty(z: DefenseZone, credits: int) -> void:
	z.kill_bounty = clampi(credits, 0, BOUNTY_MAX)
	_changed(z)


## Reserves [param credits] more for [param z]'s kill bounty. False when the
## player cannot pay it.
func add_budget(z: DefenseZone, credits: int) -> bool:
	if credits <= 0 or not ContractBoard.reserve(credits):
		return false
	z.budget += credits
	z.spent_noted = false
	_changed(z)
	return true


## Takes up to [param credits] back out of [param z]'s budget. Returns what came back.
func withdraw_budget(z: DefenseZone, credits: int) -> int:
	var back := clampi(credits, 0, maxi(z.budget, 0))
	if back <= 0:
		return 0
	z.budget -= back
	ContractBoard.release(back, "Zone budget refund")
	_changed(z)
	return back


func _changed(z: DefenseZone) -> void:
	z.refresh_look()
	zone_changed.emit(z)


func _free_name() -> String:
	for n in NAMES:
		var used := false
		for z in zones:
			if is_instance_valid(z) and z.zone_name == n:
				used = true
		if not used:
			return n
	return "Picket %d" % (zones.size() + 1)


func _make(label: String, anchored: bool) -> DefenseZone:
	var z := DefenseZone.new()
	z.zone_name = label
	z.name = label.validate_node_name().replace(" ", "")
	z.anchored = anchored
	return z


## Puts [param z] in its parent: the Structures frame (anchored, [param pos]
## frame-local unless [param world]) or the space root (world position).
func _attach(z: DefenseZone, pos: Vector3, world: bool) -> void:
	var mgr := get_tree().get_first_node_in_group(BuildingManager.GROUP) as BuildingManager
	if z.anchored and mgr and mgr.frame:
		mgr.frame.add_child(z)
		var local := mgr.frame.to_local(pos) if world else pos
		z.position = Vector3(local.x, 0.0, local.z)
	else:
		z.anchored = false
		SpaceNav.space_root(get_tree()).add_child(z)
		z.global_position = pos
	zones.append(z)


# --- Kill bounty --------------------------------------------------------------

func _on_combatant_destroyed(node: Node3D, killer: Node3D) -> void:
	var raider := node as ScavengerShip
	if raider == null or not is_instance_valid(raider):
		return
	var z := zone_at(raider.global_position, true)
	if z == null:
		return
	pay_kill(z, raider, killer)


## Pays [param z]'s kill bounty for [param raider] (see the class notes).
## Returns the credits paid.
func pay_kill(z: DefenseZone, raider: Ship, killer: Node3D) -> int:
	var earners: Array[Ship] = []
	if raider.durability:
		for o in raider.durability.attackers(BountyContract.CREDIT_WINDOW):
			var s := o as Ship
			if s and not s.dead and s.faction == Combat.Faction.PLAYER and s.captain and not earners.has(s):
				earners.append(s)
	var k := killer as Ship
	if k and not k.dead and k.faction == Combat.Faction.PLAYER and k.captain and not earners.has(k):
		earners.insert(0, k)
	elif k and earners.has(k):
		earners.erase(k)
		earners.insert(0, k)
	if earners.is_empty():
		return 0
	var pot := mini(z.kill_bounty, z.budget)
	if pot <= 0:
		return 0
	var each := floori(float(pot) / float(earners.size()))
	var total := 0
	var names: PackedStringArray = []
	for i in earners.size():
		var s := earners[i]
		var part := each + (pot - each * earners.size() if i == 0 else 0)
		if part <= 0:
			continue
		var got := ContractBoard.pay_from_escrow(s, part)
		total += got
		names.append(s.captain.captain_name if s.captain else s.get_display_name())
		s.show_toast("+%d cr zone bounty" % got, Color(1.0, 0.85, 0.4))
		if s.brain:
			s.brain.note(CaptainLog.Kind.COMBAT, CaptainLog.Outcome.DID, "Earned %s cr zone bounty in %s" % [UIUtil.amount(got), z.zone_name],
					"%s destroyed inside %s, which pays %d cr per kill; split between the %d who hit it in the last %d s" % [raider.get_display_name(), z.zone_name,
					z.kill_bounty, earners.size(), roundi(BountyContract.CREDIT_WINDOW)])
	z.budget -= total
	z.kills += 1
	z.paid_total += total
	EventLog.post("%s destroyed in %s: +%s cr zone bounty (%s)" % [raider.get_display_name(), z.zone_name, UIUtil.amount(total), ", ".join(names)],
			EventLog.Kind.REWARD, null, raider.global_position)
	if z.budget < z.kill_bounty and not z.spent_noted:
		z.spent_noted = true
		EventLog.post("%s budget is spent (%s cr left): add more to keep paying per kill" % [z.zone_name, UIUtil.amount(z.budget)], EventLog.Kind.INFO, z)
	_changed(z)
	return total


# --- Save ---------------------------------------------------------------------

func save_state() -> Dictionary:
	var list := []
	for z in zones:
		if is_instance_valid(z):
			list.append(z.save_state())
	return {"next_uid": _next_uid, "zones": list}


## Rebuilds the saved zones (their budgets were reserved when saved, so the
## credits loaded already leave them out).
func load_state(d: Dictionary) -> void:
	for z in zones:
		if is_instance_valid(z):
			z.queue_free()
	zones.clear()
	_next_uid = int(d.get("next_uid", 1))
	for zd: Dictionary in d.get("zones", []):
		var z := _make(String(zd.get("zone_name", _free_name())), bool(zd.get("anchored", true)))
		z.load_state(zd)
		_attach(z, zd.get("pos", Vector3.ZERO) as Vector3, not z.anchored)
		_next_uid = maxi(_next_uid, z.uid + 1)
	zones_changed.emit()

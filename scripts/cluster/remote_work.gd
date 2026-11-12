class_name RemoteWork
extends Node
## Remote work (child "RemoteWork" of ViewManager): the player's mining and
## bounty contracts in charted systems without a station of theirs. Captains
## based at a station take them from the berth ([method contracts_for]),
## fly there through the gates (CaptainBrain / MercenaryBrain keep the job
## across the jump and take the ship back at the target), work the job
## live, and come home through the gates (miners with the load).
## A system with open remote work stays live: it is pinned
## (ViewManager.pin) while a listed contract or one of the player's ships
## is there or on its way, and let go [constant QUIET_TIME] real s after
## both are gone. At most [constant MAX_SYSTEMS] systems at once: a post
## past that is refunded ([method post_block] tells the panels first).
## Saved with the forward station worlds (GameSnapshot.station_worlds,
## part flag "remote_work"); [member held] is rebuilt from the contracts
## after a load.

const GROUP := "remote_work"
const MAX_SYSTEMS := 3
const QUIET_TIME := 20.0
const CHECK_EVERY := 1.0
## Flight equivalent of one gate jump (approach, run-in, transit, run-out), km.
const JUMP_KM := 22.0

## System id -> true while pinned for remote work.
var held: Dictionary = {}
## System id -> real time it last had work, for the release.
var _last_need: Dictionary = {}
var _clock := 0.0
var _real := 0.0


static func of(tree: SceneTree) -> RemoteWork:
	return tree.get_first_node_in_group(GROUP) as RemoteWork if tree else null


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	ContractBoard.contract_posted.connect(_on_posted)


## True for a system the player has no station in (not home, not a forward
## or rival station site).
static func is_site(id: StringName) -> bool:
	if id.is_empty() or id == ClusterNetwork.HOME_ID:
		return false
	var st := Sector.state(id)
	return st != null and st.station.is_empty()


## Is [param id] held live for remote work?
static func is_held(tree: SceneTree, id: StringName) -> bool:
	var rw := of(tree)
	return rw != null and rw.held.has(id)


## Why a contract on [param target] may not be posted now, "" = fine.
static func post_block(target: Node) -> String:
	var w := SystemWorld.of(target) if target else null
	if w == null or not is_site(w.system_id):
		return ""
	var rw := of(target.get_tree())
	if rw == null or rw.held.has(w.system_id) or rw.held.size() < MAX_SYSTEMS:
		return ""
	return "Remote work runs in %d systems already (the most at once)" % MAX_SYSTEMS


## The remote contracts [param brain] may take from its berth: mining for
## miners, bounties for mercenaries, the player's, in systems without a
## station, targets live. Empty for a ship that is not at its station.
static func contracts_for(brain: CaptainBrain) -> Array[Contract]:
	var out: Array[Contract] = []
	if brain == null or not is_instance_valid(brain.ship) or brain.corp_id() != Corps.PLAYER:
		return out
	var ship := brain.ship
	if not is_instance_valid(ship.home) or SystemWorld.of(ship.home) != SystemWorld.of(ship):
		return out
	var here := brain.system_id()
	for c in ContractBoard.get_available(-1, &"", Corps.PLAYER):
		if c.system_id == here or not is_site(c.system_id):
			continue
		if ship is MinerShip and c is MiningContract and is_instance_valid((c as MiningContract).belt):
			out.append(c)
		elif ship is MercenaryShip and c is BountyContract and Combat.is_live(c.target):
			out.append(c)
	return out


## [param c] is in another system than [param brain]'s ship.
static func is_remote(c: Contract, brain: CaptainBrain) -> bool:
	return c != null and brain != null and not c.system_id.is_empty() and c.system_id != brain.system_id()


## Flight length (km, the evaluators' distance) from [param from] (world
## position in the brain's system) to [param site] (world position in
## [param c]'s system): the way to the first gate, [constant JUMP_KM] per
## jump, and the way from the last gate to the site.
static func trip_km(brain: CaptainBrain, c: Contract, from: Vector3, site: Vector3) -> float:
	var here := brain.system_id()
	var hops := Sector.hops_between(here, c.system_id)
	if hops.is_empty():
		return 9999.0
	var km := float(hops.size()) * JUMP_KM
	var g0 := _gate(brain.ship, hops[0])
	if g0:
		km += SpaceNav.flat_distance(from, g0.global_position) / 1000.0
	var path := Sector.network.path(here, c.system_id) if Sector.network else []
	var last_from: StringName = path[path.size() - 2] if path.size() >= 2 else here
	var tgt := c.target as Node3D
	var g1 := _gate(tgt, Sector.gate_between(c.system_id, last_from)) if is_instance_valid(tgt) else null
	if g1:
		km += SpaceNav.flat_distance(g1.global_position, site) / 1000.0
	return km


static func _gate(ctx: Node, gate_name: String) -> JumpGate:
	if ctx == null or gate_name.is_empty():
		return null
	return GateTransit._gate_in(SystemWorld.of(ctx), gate_name)


# --- Holding systems live -------------------------------------------------------

func _process(delta: float) -> void:
	_real += delta
	_clock -= delta
	if _clock > 0.0:
		return
	_clock = CHECK_EVERY
	refresh()


## Pins every system with remote work, lets go of the quiet ones.
func refresh() -> void:
	var vm := get_parent() as ViewManager
	if vm == null:
		return
	# After a load the saved remote-work systems come back pinned: adopt them.
	for id: StringName in vm.worlds:
		if not held.has(id) and is_site(id) and vm.is_pinned(id):
			held[id] = true
			_last_need[id] = _real
	var need := needed()
	for id: StringName in need:
		_last_need[id] = _real
		if not held.has(id) and (held.size() < MAX_SYSTEMS or need.size() <= MAX_SYSTEMS):
			if vm.pin(id):
				held[id] = true
	for id: StringName in held.keys():
		if need.has(id):
			continue
		if _real - float(_last_need.get(id, 0.0)) >= QUIET_TIME:
			held.erase(id)
			_last_need.erase(id)
			vm.unpin(id)


## Systems that need to be live for remote work now (id -> true).
func needed() -> Dictionary:
	var out := {}
	for c in ContractBoard.get_listed(Corps.PLAYER):
		if (c is MiningContract or c is BountyContract) and is_site(c.system_id):
			out[c.system_id] = true
	# The player's ships there, or in a jump there, with a job there.
	for t: Dictionary in Sector.transits:
		var to := StringName(t.get("to", &""))
		if held.has(to) and _player_dict(t.get("ship", {})):
			out[to] = true
	var vm := get_parent() as ViewManager
	if vm:
		for id: StringName in held:
			var w := vm.world(id)
			if w == null:
				continue
			for n in SystemWorld.nodes_in(w, Ship.GROUP):
				var s := n as Ship
				if s and not s.dead and s.captain and s.faction == Combat.Faction.PLAYER:
					out[id] = true
					break
	return out


static func _player_dict(d: Dictionary) -> bool:
	return int(d.get("captain", 0)) != 0 and String(d.get("corp", "")) in ["", String(Corps.PLAYER)]


## A post in a fourth system: refunded, with a feed line.
func _on_posted(c: Contract) -> void:
	if c.corp != Corps.PLAYER or not (c is MiningContract or c is BountyContract) or not is_site(c.system_id):
		return
	if held.has(c.system_id) or held.size() < MAX_SYSTEMS:
		refresh.call_deferred()
		return
	ContractBoard.cancel(c, true)
	EventLog.post("Contract withdrawn: remote work already runs in %d systems, the most at once" % MAX_SYSTEMS, EventLog.Kind.INFO)

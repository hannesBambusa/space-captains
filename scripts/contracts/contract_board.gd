extends Node
## Autoload "ContractBoard". Every contract the player posts lives here.
## Captains read [method get_available] to pick work; the UI lists
## [method get_listed] and the 3D markers follow [signal contract_posted] /
## [signal contract_removed].
##
## Payment model (mining, escort, salvage bonus): nothing is reserved when
## posting, but a contract can only be posted while the player can pay one
## payment ([method post_problem]). The player pays the per-load reward when
## a miner delivers a load, and the ore goes into the player's stock by type
## (Economy.ore_of_belt). When the player cannot pay a delivery in full, the
## miner sells only the part that can be paid for (credits run to 0,
## materials scale down) and the feed says the station could not pay. While
## the station cannot pay one payment the contract is paused
## (Contract.is_paused, "Station can't pay"): captains refuse new runs, so
## short pay only happens to trips already under way. Cancelling stops new
## takers at once; trips already under way are honoured and paid on delivery.
##
## Bounties are reserved ([member BountyContract.escrow]): posting needs the
## credits and moves them out of the player's credits at once
## ([method escrow_total] is what is held). The payout comes from the escrow
## (split rules as before) and what is left after the kill goes back to the
## player. Cancelling ([method cancel]): a full refund while nobody has
## taken it; once taken, half comes back and the other half is paid to the
## takers as compensation, split evenly ([method cancel_terms]). A bounty
## whose target slips away without dying is refunded in full.
##
## Stage 2: bounties (paid on the target's destruction, split among the
## player ships that damaged it) and escorts (paid per escorted trip, on the
## miner's delivery). Every payment to a captain also collects the station's
## share of it back (Economy.collect_fees).
##
## Phase C2: planet raids (PlanetRaidContract), paid per load like mining;
## the loot is a planet good by planet type.
##
## Stage 3: salvage. Salvagers work scrap fields on their own (free salvage,
## paid by their Salvage Yard, which reprocesses the scrap and sells the ore
## to the player); a posted salvage contract adds a per-load bonus from the
## player. Sometimes a load holds a rare part for the Factory. Also
## reputation for escort trips. Bigger holds deliver bigger loads (more pay
## and materials); prospecting scanners add materials only.
##
## P3: explore contracts (ExploreContract) on a jump gate, reserved like a
## bounty ([method post_explore], [method explore_problem]) and paid once
## when the explorer brings the survey home ([method deliver_survey]).
## One cancelled while its explorer is still out leaves the board but is
## kept in [member held] (saved, and resolvable by save id for ships that
## are data) until the explorer is home or lost.

## Lowering a taken bounty (the target panel's tooltip).
const UPDATE_TAKEN := "Taken: can only raise"

signal contract_posted(contract: Contract)
signal contract_changed(contract: Contract)
## Completed or cancelled: it leaves the lists.
signal contract_removed(contract: Contract)
## [param ore] is the AsteroidBelt.OreType (-1 for salvage).
signal delivery_made(contract: Contract, ship: Node, credits: int, materials: int, ore: int)
## Bounty or escort pay to one captain.
signal payout_made(contract: Contract, ship: Node, credits: int)

const RULES_PATH := "res://data/contracts/mining_rules.tres"
## Share of salvaged materials that comes out as titanium (the rest is iron).
const SALVAGE_TITANIUM := 0.2
## Share of a taken bounty paid to its takers when the player cancels it.
const CANCEL_COMPENSATION := 0.5

var mining_rules: MiningRules
## Open and active contracts, in posting order.
var contracts: Array[Contract] = []
## Off the board but still in use by a ship far away (a cancelled explore
## contract whose explorer is out), see [method hold].
var held: Array[Contract] = []

var _next_id: int = 1


func _ready() -> void:
	mining_rules = load(RULES_PATH) as MiningRules
	if mining_rules == null:
		mining_rules = MiningRules.new()


func post(contract: Contract) -> Contract:
	contract.id = _next_id
	_next_id += 1
	contract.created_time = SimClock.time
	contract.status = Contract.Status.OPEN
	contract.system_id = _system_of(contract)
	contract.changed.connect(_on_contract_changed)
	contracts.append(contract)
	Sfx.ui(&"contract_posted")
	contract_posted.emit(contract)
	return contract


func post_mining(belt: AsteroidCluster, credits_per_load: int, max_loads: int = 0) -> MiningContract:
	if belt == null or not post_problem(credits_per_load).is_empty():
		return null
	return post(MiningContract.new(belt, maxi(credits_per_load, 0), max_loads)) as MiningContract


## Why a contract paying [param credits] (per payment; a bounty's whole
## reward) cannot be posted now, or "". [param reserved] = a bounty, paid
## in full now.
func post_problem(credits: int, reserved: bool = false) -> String:
	if credits <= 0 or Economy.credits >= credits:
		return ""
	if reserved:
		return "Needs %s cr: a bounty is reserved from your credits when posted (you have %s)" % [Fmt.amount(credits), Fmt.amount(Economy.credits)]
	return "Needs %s cr: you must be able to pay one %s (you have %s)" % [Fmt.amount(credits), "payment", Fmt.amount(Economy.credits)]


## Bounty on a scavenger ship or den. Completes when the target dies. The
## reward is reserved now (null when the player cannot pay it). One bounty
## per target: with one already open this updates its reward instead
## ([method update_bounty]) and returns it (null when that is refused).
func post_bounty(on_target: Node3D, credits: int, max_takers: int = 3) -> BountyContract:
	if not Combat.is_live(on_target):
		return null
	var have := bounty_on(on_target)
	if have:
		return have if credits == have.reward or update_bounty(have, credits) else null
	credits = maxi(credits, 0)
	if not post_problem(credits, true).is_empty() or not Economy.spend(credits, PackedInt32Array(), Ledger.ESCROW, "Reserved: bounty on %s" % _name_of(on_target)):
		return null
	var c := BountyContract.new(on_target, credits, max_takers)
	c.escrow = credits
	post(c)
	_wire(c)
	return c


## The open bounty on [param target], or null.
func bounty_on(target: Node) -> BountyContract:
	for c in contracts:
		var bc := c as BountyContract
		if bc and bc.target == target and not bc.is_finished():
			return bc
	return null


## Why [param bc]'s reward cannot be set to [param credits] now, or "":
## lowering only while nobody has taken it, raising only with the
## difference in credits.
func update_problem(bc: BountyContract, credits: int) -> String:
	var diff := maxi(credits, 0) - bc.reward
	if diff < 0 and bc.is_taken():
		return UPDATE_TAKEN
	if diff > 0 and Economy.credits < diff:
		return "Needs %s cr more: the raise is reserved from your credits now (you have %s)" % [Fmt.amount(diff), Fmt.amount(Economy.credits)]
	return ""


## Sets [param bc]'s reward to [param credits]: a raise reserves the
## difference ("Reserved: bounty raised on Rustjaw Hideout +300"), a cut
## gives it back (only while nobody has taken it). Takers and its fleet go
## on; the split at the kill uses the new reward. Mercenaries forget their
## refusals of it and judge it again with the new pay. False when refused
## ([method update_problem]) or unchanged.
func update_bounty(bc: BountyContract, credits: int) -> bool:
	credits = maxi(credits, 0)
	var diff := credits - bc.reward
	if diff == 0 or bc.is_finished() or not update_problem(bc, credits).is_empty():
		return false
	var tname := bc.get_target_name()
	if diff > 0:
		if not reserve(diff, "bounty raised on %s +%d" % [tname, diff]):
			return false
	else:
		release(-diff, "bounty lowered on %s" % tname)
	bc.reward = credits
	bc.escrow += diff
	EventLog.post("Bounty on %s %s to %s cr" % [tname, "raised" if diff > 0 else "lowered", Fmt.amount(credits)], EventLog.Kind.INFO,
			bc.target as Node3D if is_instance_valid(bc.target) else null)
	if bc.fleet:
		bc.fleet.declined.clear()
	for n in get_tree().get_nodes_in_group(Ship.GROUP):
		var mb := (n as Ship).brain as MercenaryBrain if n is Ship else null
		if mb:
			mb.refusal_lines.erase(tname)
	bc.changed.emit(bc)
	return true


## Old saves may hold more than one open bounty on a target: they become
## one (rewards and escrow added up, takers and their trips kept, the first
## fleet kept). Returns how many were merged away.
func merge_duplicate_bounties() -> int:
	var first := {}
	var merged := 0
	for c in contracts.duplicate():
		var bc := c as BountyContract
		if bc == null or bc.is_finished() or not is_instance_valid(bc.target):
			continue
		var id := bc.target.get_instance_id()
		if not first.has(id):
			first[id] = bc
			continue
		var keep: BountyContract = first[id]
		keep.reward += bc.reward
		keep.escrow += bc.escrow
		for t in bc.takers:
			if not keep.takers.has(t):
				keep.takers.append(t)
			var brain := (t as Ship).brain if t is Ship else null
			if brain and brain.trip and brain.trip.contract == bc:
				brain.trip.contract = keep
		if keep.fleet == null and bc.fleet:
			keep.fleet = bc.fleet
			bc.fleet.contract = keep
		bc.fleet = null
		bc.takers.clear()
		bc.escrow = 0
		bc.status = Contract.Status.CANCELLED
		if bc.changed.is_connected(_on_contract_changed):
			bc.changed.disconnect(_on_contract_changed)
		contracts.erase(bc)
		contract_removed.emit(bc)
		merged += 1
	for id in first:
		(first[id] as BountyContract).changed.emit(first[id])
	return merged


## Credits held for open bounties, explore contracts and defence zone budgets.
func escrow_total() -> int:
	return bounty_escrow_total() + explore_escrow_total() + zone_escrow_total()


## Credits held for explore contracts (on the board or held for an explorer out).
func explore_escrow_total() -> int:
	var t := 0
	for c in contracts + held:
		var ec := c as ExploreContract
		if ec and (not ec.is_finished() or held.has(ec)):
			t += ec.escrow
	return t


## Credits held for open bounties.
func bounty_escrow_total() -> int:
	var t := 0
	for c in contracts:
		var bc := c as BountyContract
		if bc and not bc.is_finished():
			t += bc.escrow
	return t


## Credits held in defence zone kill budgets (DefenseZones), every system.
func zone_escrow_total() -> int:
	var t := 0
	for w in SystemWorld.all(get_tree()):
		var zones := DefenseZones.of(w)
		t += zones.budget_total() if zones else 0
	return t


## Reserves [param credits] from the player's credits into an escrow held
## outside a contract (defence zone budgets). False when they cannot pay.
## [param what] names it in the ledger ("Reserved: zone budget").
func reserve(credits: int, what: String = "zone budget") -> bool:
	return credits <= 0 or (Economy.credits >= credits and Economy.spend(credits, PackedInt32Array(), Ledger.ESCROW, "Reserved: " + what))


## Gives [param credits] of an escrow back to the player (bounties,
## defence zone budgets; nothing for 0). [param source] is the ledger
## label after "Returned: ".
func release(credits: int, source: String) -> void:
	Economy.add_income(credits, Ledger.ESCROW, "Returned: " + source.to_lower())


## A target's name for the ledger.
static func _name_of(n: Node) -> String:
	if n == null or not is_instance_valid(n):
		return "?"
	return String(n.call(&"get_display_name")) if n.has_method(&"get_display_name") else String(n.name)


## Salvage bonus on a scrap field, paid per delivered load on top of the
## yard's pay. Completes when the field is stripped or gone.
func post_salvage(field: ScrapField, credits_per_load: int, max_takers: int = 3) -> SalvageContract:
	if field == null or not is_instance_valid(field) or field.amount <= 0 or not post_problem(credits_per_load).is_empty():
		return null
	var c := post(SalvageContract.new(field, maxi(credits_per_load, 0), max_takers)) as SalvageContract
	_wire(c)
	return c


## Planet raid on a planet or moon, paid per delivered load (phase C2).
func post_planet_raid(body: PlanetBody, credits_per_load: int, max_loads: int = 0) -> PlanetRaidContract:
	if body == null or not is_instance_valid(body) or not post_problem(credits_per_load).is_empty():
		return null
	return post(PlanetRaidContract.new(body, maxi(credits_per_load, 0), max_loads)) as PlanetRaidContract


## Why an explore contract on gate [param gate] of system [param from]
## cannot be posted now (any pay), or "".
func explore_problem(from: StringName, gate: String) -> String:
	if Sector.network == null:
		return "No gate network"
	var t := Sector.network.gate_target(from, gate)
	if t.is_empty():
		return "This gate leads nowhere"
	var to: StringName = t["system"]
	if to == ClusterNetwork.HOME_ID:
		return "This gate leads home"
	if from != ClusterNetwork.HOME_ID and not (Sector.state(from) and Sector.state(from).known):
		return "Survey %s first: explorers only go on from charted systems" % Sector.system_def(from).system_name
	for c in contracts:
		var ec := c as ExploreContract
		if ec and not ec.is_finished() and ec.target_system == to:
			return "%s already has an explore contract" % ec.target_name()
	if not Sector.is_stale(to):
		return "%s was surveyed %s: nothing new to chart yet" % [Sector.system_def(to).system_name, Sector.seen_text(to).trim_prefix("seen ")]
	return ""


## Explore contract on gate [param gate] of [param from] (P3). The reward
## is reserved now (null when it cannot be posted or paid).
## [param exit]: the target's gate to leave by ("" = the way in).
func post_explore(from: StringName, gate: String, credits: int, exit: String = "") -> ExploreContract:
	credits = maxi(credits, 0)
	if not explore_problem(from, gate).is_empty() or not post_problem(credits, true).is_empty() or not Economy.spend(credits, PackedInt32Array(), Ledger.ESCROW, "Reserved: explore %s" % gate):
		return null
	var c := ExploreContract.new(from, gate, credits, exit)
	c.escrow = credits
	c.refresh_target()
	post(c)
	return c


## The explorer of [param c] is home with the survey: the charts go in
## (the system is known, its finds delivered) and the reward is paid once
## from the escrow. Returns the credits paid.
func deliver_survey(c: ExploreContract, ship: Ship, survey: Dictionary) -> int:
	if c == null or ship == null:
		return 0
	var id := StringName(survey.get("target", c.target_system))
	Sector.mark_surveyed(id, float(survey.get("done_at", SimClock.time)))
	var finds := Sector.deliver_discoveries(id, SaveIds.of(ship.captain))
	var pay := mini(c.reward, maxi(c.escrow, 0))
	c.escrow -= pay
	if pay > 0:
		c.credits_paid += pay
		Economy.note_escrow_pay(pay, Ledger.CONTRACT_PAY, c.get_title())
		_credit_captain(ship, pay, c)
	var back := maxi(c.escrow, 0)
	c.escrow = 0
	if back > 0:
		release(back, "Explore leftover")
	if ship.captain:
		ship.captain.surveys += 1
		ship.captain.discoveries += finds
	var def := Sector.system_def(id)
	var text := "Survey of %s complete" % (def.system_name if def else String(id))
	EventLog.post("%s: %s charted %s (+%s cr)" % [text, ship.get_display_name(), Survey.tally_text(id), Fmt.amount(pay)], EventLog.Kind.REWARD, ship)
	# P4: the corporation pays the station for the new finds (once each).
	var bounty := DiscoveryBounty.pay(id, SaveIds.of(ship.captain), ship.captain)
	var extra := DiscoveryBounty.short_text(bounty)
	if not extra.is_empty():
		text += ": " + extra
	var pm := get_tree().root.get_node_or_null(^"PauseMenu") if is_inside_tree() else null
	if pm and pm.has_method(&"toast"):
		pm.call(&"toast", text)
	held.erase(c)
	c.mark_completed()
	return pay


## Keeps [param c] resolvable off the board (see [member held]).
func hold(c: Contract) -> void:
	if c and not held.has(c):
		held.append(c)


## A held contract nobody needs any more (its explorer was lost): what is
## left of its escrow comes back.
func drop_held(c: Contract) -> void:
	if not held.has(c):
		return
	held.erase(c)
	var ec := c as ExploreContract
	if ec and ec.escrow > 0:
		release(ec.escrow, "Explore refund")
		ec.escrow = 0


## The contract with save id [param sid] on the board or held, or null.
func find_saved(sid: int) -> Contract:
	if sid <= 0:
		return null
	for c in contracts:
		if SaveIds.of(c) == sid:
			return c
	for c in held:
		if SaveIds.of(c) == sid:
			return c
	return null


## Escort on one miner.
func post_escort(ward: Ship, pay_per_trip: int, max_escorts: int = 2) -> EscortContract:
	if ward == null or ward.dead or not post_problem(pay_per_trip).is_empty():
		return null
	var c := post(EscortContract.new(ward, null, maxi(pay_per_trip, 0), max_escorts)) as EscortContract
	_wire(c)
	return c


## Escort linked to a mining contract: every trip on it can be escorted.
func post_escort_for_mining(mc: MiningContract, pay_per_trip: int, max_escorts: int = 2) -> EscortContract:
	if mc == null or mc.is_finished() or not post_problem(pay_per_trip).is_empty():
		return null
	var c := post(EscortContract.new(null, mc, maxi(pay_per_trip, 0), max_escorts)) as EscortContract
	_wire(c)
	return c


## Hooks a posted contract to its target: a bounty resolves when the target
## dies (and is cancelled when it slips away), salvage ends with its field,
## an escort with its ward or its mining contract.
func _wire(c: Contract) -> void:
	if c is BountyContract and is_instance_valid(c.target):
		var on_target := c.target
		var bc := c as BountyContract
		on_target.connect(&"destroyed", func(_n: Node3D, killer: Node3D) -> void: _resolve_bounty(bc, killer))
		# Leaving the tree without dying (a scavenger slipping into its den) ends it.
		var tw: WeakRef = weakref(on_target)
		var check_gone := func() -> void:
			var t := tw.get_ref() as Node
			if not bc.is_finished() and (t == null or not t.is_inside_tree()):
				cancel(bc, true)
		on_target.tree_exiting.connect(func() -> void: check_gone.call_deferred())
	elif c is SalvageContract and is_instance_valid((c as SalvageContract).field):
		var sc := c as SalvageContract
		sc.field.depleted.connect(func(_f: ScrapField) -> void: sc.mark_done())
		sc.field.tree_exiting.connect(func() -> void: sc.mark_done())
	elif c is EscortContract:
		var ec := c as EscortContract
		if is_instance_valid(ec.ward):
			wire_escort(ec)
		elif ec.mining_contract:
			var mc := ec.mining_contract
			mc.changed.connect(func(_m: Contract) -> void:
				if mc.is_finished():
					cancel(ec))


## An escort contract ends when its ward is destroyed (again for a ward
## built anew: a mobile station out of a gate).
func wire_escort(ec: EscortContract) -> void:
	if not is_instance_valid(ec.ward):
		return
	var cb := func(_s: Ship, _k: Node3D) -> void: cancel(ec)
	ec.ward.destroyed.connect(cb)


# --- Save ---------------------------------------------------------------------

## A new game: no contracts.
func reset() -> void:
	for c in contracts.duplicate():
		if c.changed.is_connected(_on_contract_changed):
			c.changed.disconnect(_on_contract_changed)
		if c is BountyContract and (c as BountyContract).fleet:
			# Fleet and contract point at each other: break it so both free.
			(c as BountyContract).fleet.members.clear()
			(c as BountyContract).fleet = null
	contracts.clear()
	held.clear()
	_next_id = 1


func next_id() -> int:
	return _next_id


## Puts a loaded contract back. [param listed] = it is open or active (on
## the board, wired to its target); finished ones are only kept for the
## trips still on them.
func restore(c: Contract, listed: bool, next: int) -> void:
	_next_id = maxi(_next_id, next)
	if not listed:
		return
	c.changed.connect(_on_contract_changed)
	contracts.append(c)
	_wire(c)
	contract_posted.emit(c)


## The open escort contract linked to [param mc], or null.
func escort_for_mining(mc: Contract) -> EscortContract:
	for c in contracts:
		var e := c as EscortContract
		if e and e.mining_contract == mc and not e.is_finished():
			return e
	return null


## Open escort contracts on one miner.
func escorts_for_ship(ship: Ship) -> Array[EscortContract]:
	var out: Array[EscortContract] = []
	for c in contracts:
		var e := c as EscortContract
		if e and e.ward == ship and not e.is_finished():
			out.append(e)
	return out


## Pays [param amount] to a captain's ship and collects the station fee
## back: from a bounty's escrow, else from the player's credits (partial when
## short, and the feed says so). Returns the credits paid.
func pay_captain(ship: Ship, amount: int, contract: Contract = null) -> int:
	var bc := contract as BountyContract
	var pay := 0
	if bc:
		pay = mini(amount, maxi(bc.escrow, 0))
		bc.escrow -= pay
		Economy.note_escrow_pay(pay, Ledger.BOUNTIES, bc.get_title())
	else:
		pay = mini(amount, maxi(Economy.credits, 0))
		if pay < amount and contract:
			note_short_pay(contract, amount, pay)
		if pay > 0:
			Economy.spend(pay, PackedInt32Array(), Ledger.CONTRACT_PAY, contract.get_title() if contract else "Captain pay")
	if pay <= 0:
		return 0
	if contract:
		contract.credits_paid += pay
	_credit_captain(ship, pay, contract)
	return pay


## Pays [param amount] that was already reserved outside a contract (a
## defence zone budget): nothing leaves the player's credits now, the
## station fee comes back as usual.
func pay_from_escrow(ship: Ship, amount: int) -> int:
	if amount <= 0:
		return 0
	Economy.note_escrow_pay(amount, Ledger.ZONES, "Zone kill bounty")
	_credit_captain(ship, amount, null)
	return amount


func _credit_captain(ship: Ship, pay: int, contract: Contract) -> void:
	if ship and ship.captain:
		ship.captain.credits_earned += pay
		Economy.collect_fees(ship.captain, pay)
	payout_made.emit(contract, ship, pay)


## The feed line when a payment could not be paid in full (once a minute
## per contract): the contract is paused until credits come in.
func note_short_pay(contract: Contract, due: int, paid: int) -> void:
	EventLog.post("Station can't pay %s in full (%s of %s cr): paused until credits come in" % [contract.get_title(), Fmt.amount(paid), Fmt.amount(due)],
			EventLog.Kind.LOSS, null, contract.get_site_position(), "short_pay:%d" % contract.id)


## What cancelling [param contract] does with its escrow now: {refund,
## compensation, takers} (zeros for contracts that hold nothing).
func cancel_terms(contract: Contract) -> Dictionary:
	var ec := contract as ExploreContract
	if ec:
		if ec.is_finished() or ec.escrow <= 0:
			return {"refund": 0, "compensation": 0, "takers": 0}
		if not ec.taken():
			return {"refund": ec.escrow, "compensation": 0, "takers": 0}
		var keep := mini(roundi(float(ec.reward) * CANCEL_COMPENSATION), ec.escrow)
		return {"refund": ec.escrow - keep, "compensation": keep, "takers": 1}
	var bc := contract as BountyContract
	if bc == null or bc.is_finished() or bc.escrow <= 0:
		return {"refund": 0, "compensation": 0, "takers": 0}
	var ships := _bounty_takers(bc)
	if ships.is_empty():
		return {"refund": bc.escrow, "compensation": 0, "takers": 0}
	var comp := mini(roundi(float(bc.reward) * CANCEL_COMPENSATION), bc.escrow)
	return {"refund": bc.escrow - comp, "compensation": comp, "takers": ships.size()}


## "Cancel: refunds all 800 cr (nobody has taken it)" and the like.
func cancel_text(contract: Contract) -> String:
	if contract is ExploreContract:
		var e := cancel_terms(contract)
		if int(e["takers"]) == 0:
			return "Cancel: refunds all %s cr (nobody has taken it yet)." % Fmt.amount(int(e["refund"]))
		return "Cancel: refunds %s cr now. %s is already out: they still bring the survey home and are paid the other %s cr." % [
				Fmt.amount(int(e["refund"])), (contract as ExploreContract).explorer_name, Fmt.amount(int(e["compensation"]))]
	if not (contract is BountyContract):
		return "Cancel this contract. Trips already under way are still paid."
	var t := cancel_terms(contract)
	if int(t["takers"]) == 0:
		return "Cancel: refunds all %s cr (nobody has taken it yet)." % Fmt.amount(int(t["refund"]))
	return "Cancel: refunds %s cr (%d%%). %d captain%s took it: they share %s cr as compensation." % [Fmt.amount(int(t["refund"])),
			roundi((1.0 - CANCEL_COMPENSATION) * 100.0), int(t["takers"]), "" if int(t["takers"]) == 1 else "s", Fmt.amount(int(t["compensation"]))]


## Withdraws a contract: no new takers. Ships already on a trip finish it.
## A bounty gives back its escrow: all of it while nobody has taken it,
## else half, the other half paid to the takers evenly (see the class notes).
## [param refund_all] = the target slipped away: everything comes back.
func cancel(contract: Contract, refund_all: bool = false) -> void:
	if contract == null or contract.is_finished():
		return
	var ec := contract as ExploreContract
	if ec:
		var e := cancel_terms(ec)
		if int(e["refund"]) > 0:
			ec.escrow -= int(e["refund"])
			release(int(e["refund"]), "Explore refund")
		if ec.taken():
			# The explorer is out: it is paid the rest on its return.
			ec.reward = ec.escrow
			hold(ec)
		else:
			ec.escrow = 0
		contract.mark_cancelled()
		return
	var bc := contract as BountyContract
	if bc and bc.escrow > 0:
		var ships := _bounty_takers(bc)
		if not refund_all and not ships.is_empty():
			var comp := mini(roundi(float(bc.reward) * CANCEL_COMPENSATION), bc.escrow)
			var parts := Economy.split_evenly(comp, ships.size())
			var paid_total := 0
			for i in ships.size():
				var s := ships[i]
				var got := pay_captain(s, parts[i], bc)
				paid_total += got
				s.show_toast("+%d cr compensation" % got, Ship.TOAST_REWARD)
				if s.brain:
					s.brain.note(CaptainLog.Kind.COMBAT, CaptainLog.Outcome.DID, "Got %s cr compensation: the %s was cancelled" % [Fmt.amount(got), DecisionNotes.job_name(bc)],
							"The station cancelled a bounty we had taken: half of the %s cr goes back, the other half is split evenly between the %d on it" % [Fmt.amount(bc.reward), ships.size()])
			EventLog.post("Bounty on %s cancelled: %s cr back, %s cr compensation to %d captain%s" % [bc.get_target_name(), Fmt.amount(bc.escrow), Fmt.amount(paid_total),
					ships.size(), "" if ships.size() == 1 else "s"], EventLog.Kind.INFO)
		_refund_escrow(bc, "Bounty refund")
	contract.mark_cancelled()


## Hired ships on [param bc] now (its takers and fleet members).
func _bounty_takers(bc: BountyContract) -> Array[Ship]:
	var out: Array[Ship] = []
	for t in bc.takers:
		# Freed takers (scene teardown) can't be cast, so check first.
		if not is_instance_valid(t):
			continue
		var s := t as Ship
		if s and not s.dead and s.captain and not out.has(s):
			out.append(s)
	if bc.fleet:
		for s in bc.fleet.members:
			if is_instance_valid(s) and not s.dead and s.captain and not out.has(s):
				out.append(s)
	return out


## What is left of a bounty's escrow goes back to the player.
func _refund_escrow(bc: BountyContract, source: String) -> int:
	var left := maxi(bc.escrow, 0)
	bc.escrow = 0
	release(left, source)
	return left


## Contracts a new taker could start on now, optionally of one type and
## in one system ([param system_id] "" = any).
func get_available(type: int = -1, system_id: StringName = &"") -> Array[Contract]:
	var out: Array[Contract] = []
	for c in contracts:
		if (type < 0 or c.type == type) and (system_id.is_empty() or c.system_id == system_id) and c.is_available():
			out.append(c)
	return out


## The system [param c]'s work is in: its target's, home when unknown.
static func _system_of(c: Contract) -> StringName:
	var ec := c as ExploreContract
	if ec:
		return ec.from_system
	var w := SystemWorld.of(c.target) if is_instance_valid(c.target) else null
	return w.system_id if w and not w.system_id.is_empty() else ClusterNetwork.HOME_ID


## Open and active contracts (what the UI lists).
func get_listed() -> Array[Contract]:
	return contracts.duplicate()


func get_for_target(target: Node) -> Array[Contract]:
	var out: Array[Contract] = []
	for c in contracts:
		if c.target == target:
			out.append(c)
	return out


## Pays for one delivered mining load. Returns {credits, materials}. The
## ore goes into the miner's outpost stock (CargoDepot) and reaches the
## player by cargo shuttle; without a depot straight into Economy.
## Partial payment when credits run short (see the class notes).
## [param fraction] < 1 when scavengers took part of the load.
func deliver_mining_load(contract: MiningContract, ship: Node, ore: int, fraction: float = 1.0) -> Dictionary:
	fraction = clampf(fraction, 0.0, 2.0)
	var s := ship as Ship
	var yield_mult := s.stats.yield_mult if s and s.stats else 1.0
	var full_pay := roundi(float(contract.reward) * fraction)
	var full_mat := roundi(float(mining_rules.materials_for(ore)) * fraction * yield_mult)
	var pay := _pay_for_load(contract, full_pay)
	var mat := _paid_share(full_mat, pay, full_pay)
	_stock_materials(ship, Economy.ore_of_belt(ore), mat)
	contract.credits_paid += pay
	contract.materials_delivered += mat
	var escorted := _finish_delivery(contract, ship, pay, mat, ore)
	return {"credits": pay, "materials": mat, "partial": pay < full_pay, "escorted": escorted}


## One delivered salvage load of [param scrap]: the scrap goes to the
## salvager's Salvage Yard, which pays the captain (SalvageYard.accept_load);
## a posted contract also pays its bonus from the player's credits (partial
## when short). Without a yard the scrap turns into ore for the player
## straight away (iron plus [constant SALVAGE_TITANIUM] titanium). Returns
## {credits (total paid now), bonus, yard, owed, scrap, materials (ore to the
## player), escorted, rare (module name or "")}.
func deliver_salvage_load(contract: SalvageContract, ship: Node, scrap: int) -> Dictionary:
	var s := ship as Ship
	var fraction := clampf(float(scrap) / float(SalvageContract.LOAD_SCRAP), 0.0, 2.0)
	var yield_mult := s.stats.yield_mult if s and s.stats else 1.0
	var sorted := roundi(float(scrap) * SalvageContract.MATERIALS_PER_SCRAP * yield_mult)
	var bonus := _pay_for_load(contract, roundi(float(contract.reward) * fraction))
	if bonus > 0 and s and s.captain:
		Economy.collect_fees(s.captain, bonus)
	contract.credits_paid += bonus
	var rare := ""
	if scrap > 0 and s and SalvageContract.rng.randf() < contract.rare_chance:
		rare = _find_rare_part(s)
	var yard := SalvageYard.of(s)
	var yard_pay := 0
	var owed := 0
	var mat := 0
	if yard:
		var before := yard.owed_total()
		yard_pay = yard.accept_load(s, sorted, fraction, bool(contract.field.get_meta(&"den_ruins", false)) if is_instance_valid(contract.field) else false, rare)
		owed = yard.owed_total() - before
	elif sorted > 0:
		mat = sorted
		var ti := roundi(float(mat) * SALVAGE_TITANIUM)
		Economy.add(0, Economy.cost(mat - ti, ti))
	contract.materials_delivered += sorted
	contract.finish_trip(ship, true)
	delivery_made.emit(contract, ship, bonus, mat, -1)
	var escorted := _pay_escorts(s, contract) > 0 if s else false
	return {"credits": bonus + yard_pay, "bonus": bonus, "yard": yard_pay, "owed": owed, "scrap": sorted, "materials": mat, "escorted": escorted, "rare": rare}


## Pays for one delivered planet raid load of [param units] (already
## scaled by what scavengers left aboard; [param fraction] of a full load).
## Partial payment when credits run short, like a mining load. The loot
## goes into the lander's dock stock (a cargo shuttle brings it to the
## station), else straight into the player's stock. Returns {credits,
## materials, partial, escorted}.
func deliver_raid_load(contract: PlanetRaidContract, ship: Node, units: int, fraction: float = 1.0) -> Dictionary:
	fraction = clampf(fraction, 0.0, 2.0)
	var s := ship as Ship
	var full_pay := roundi(float(contract.reward) * fraction)
	var pay := _pay_for_load(contract, full_pay)
	var mat := _paid_share(units, pay, full_pay)
	_stock_materials(ship, contract.loot, mat)
	contract.credits_paid += pay
	contract.units_delivered += mat
	PlanetRaidContract.note_raid(contract.planet, mat, pay)
	var escorted := _finish_delivery(contract, ship, pay, mat, -1)
	return {"credits": pay, "materials": mat, "partial": pay < full_pay, "escorted": escorted}


## Pays what the player can of [param full_pay] for a delivered load from
## their credits; when short, the feed says so (see the class notes).
## Returns the credits paid.
func _pay_for_load(contract: Contract, full_pay: int) -> int:
	var pay := mini(full_pay, maxi(Economy.credits, 0))
	if pay < full_pay:
		note_short_pay(contract, full_pay, pay)
	if pay > 0:
		Economy.spend(pay, PackedInt32Array(), Ledger.CONTRACT_PAY, contract.get_title())
	return pay


## The part of [param amount] that [param pay] of [param full_pay] covers
## (all of it when paid in full).
static func _paid_share(amount: int, pay: int, full_pay: int) -> int:
	if pay >= full_pay:
		return amount
	return floori(float(amount) * float(pay) / maxf(float(full_pay), 1.0))


## Puts [param amount] of [param ore] (Economy.Ore) into the ship's home
## stock (CargoDepot; a cargo shuttle brings it to the station), else
## straight into the player's.
func _stock_materials(ship: Node, ore: int, amount: int) -> void:
	if amount <= 0:
		return
	var depot := CargoDepot.of_ship(ship)
	if depot:
		depot.add_stock(ore, amount)
	else:
		Economy.add_ore_of(ore as Economy.Ore, amount)


## The station's fee on [param pay], the trip ends, the escorts are paid.
## Returns true when an escort was.
func _finish_delivery(contract: LoadContract, ship: Node, pay: int, mat: int, ore: int) -> bool:
	var s := ship as Ship
	if s and s.captain and pay > 0:
		Economy.collect_fees(s.captain, pay)
	contract.finish_trip(ship, true)
	delivery_made.emit(contract, ship, pay, mat, ore)
	return _pay_escorts(s, contract) > 0 if s else false


## A rare Mk II/III part in the haul: it goes into the Factory warehouse and
## lets the Factory make it early, or discounts it when already tooled.
## Returns the module name ("" without a Factory).
func _find_rare_part(ship: Ship) -> String:
	var o := Factory.find(ship)
	if o == null:
		return ""
	var pool: Array[ShipModule] = []
	for m in ModuleCatalog.shared().modules:
		if m.tier >= 2:
			pool.append(m)
	if pool.is_empty():
		return ""
	var m := pool[SalvageContract.rng.randi() % pool.size()]
	var kind := o.add_rare_part(m)
	var cap_name := ship.captain.captain_name if ship.captain else ship.get_display_name()
	if kind == "stocked":
		EventLog.post("%s salvaged a rare %s: the Factory can now make it" % [cap_name, m.display_name], EventLog.Kind.REWARD, ship)
	else:
		EventLog.post("%s salvaged a rare %s: %d%% off the next one" % [cap_name, m.display_name, roundi(Factory.RARE_DISCOUNT * 100.0)], EventLog.Kind.REWARD, ship)
	return m.display_name


## Pays every escort that flew this miner's trip and is still near it.
## Returns how many were paid.
func _pay_escorts(miner: Ship, contract: Contract) -> int:
	var paid := 0
	for c in contracts.duplicate():
		var e := c as EscortContract
		if e == null or not e.covers(miner, contract):
			continue
		var paid_any := false
		for escort in e.escorts_of(miner):
			if escort.dead or escort.global_position.distance_to(miner.global_position) > EscortContract.PAY_DISTANCE:
				continue
			var pay := pay_captain(escort, e.reward, e)
			paid_any = true
			paid += 1
			if escort.captain:
				escort.captain.escorts_completed += 1
				escort.captain.add_reputation(Reputation.ESCORT_TRIP)
				escort.captain.note_job(true)
			escort.show_toast("+%d cr escort" % pay, Ship.TOAST_DELIVERY)
			if escort.brain:
				escort.brain.call(&"on_escort_trip_completed", e, miner)
		if paid_any:
			e.note_trip_completed()
	return paid


func _resolve_bounty(c: BountyContract, killer: Node3D) -> void:
	if c.is_finished():
		return
	var target := c.target
	var d := target.get(&"durability") as Durability if is_instance_valid(target) else null
	if c.fleet and c.fleet.state != MercFleet.State.DONE and _resolve_fleet_bounty(c, killer, d):
		return
	var earners: Array[Ship] = []
	if d:
		for o in d.attackers(BountyContract.CREDIT_WINDOW):
			var s := o as Ship
			if s and not s.dead and s.faction == Combat.Faction.PLAYER and s.captain:
				earners.append(s)
	var k := killer as Ship
	if k and not k.dead and k.faction == Combat.Faction.PLAYER and not earners.has(k):
		earners.append(k)
	if k and k.captain:
		c.killer_name = k.captain.captain_name
	var share := roundi(float(c.reward) / float(maxi(earners.size(), 1)))
	var total := 0
	for s in earners:
		var pay := pay_captain(s, share, c)
		total += pay
		c.payouts.append({"ship_name": s.get_display_name(), "credits": pay})
		s.show_toast("+%d cr bounty" % pay, Ship.TOAST_REWARD)
	var who := c.killer_name if not c.killer_name.is_empty() else ("%d mercenaries" % earners.size() if earners.size() > 1 else "")
	var solo := c.solo_runner()
	if earners.size() == 1 and solo == earners[0]:
		who = "%s, alone" % solo.get_display_name()
	if earners.size() > 1:
		who = "%s and %d more" % [earners[0].get_display_name() if c.killer_name.is_empty() else c.killer_name, earners.size() - 1]
	var tname := c.get_target_name()
	if not who.is_empty():
		EventLog.post("%s destroyed by %s (+%d cr bounty)" % [tname, who, total], EventLog.Kind.REWARD, null, target.global_position if is_instance_valid(target) else Vector3.INF)
	var back := _refund_escrow(c, "Bounty leftover")
	if back > 0:
		EventLog.post("%s cr of the bounty on %s came back: %s" % [Fmt.amount(back), tname, "nobody earned it" if earners.is_empty() else "left over after the split"],
				EventLog.Kind.INFO)
	c.mark_completed()


## A fleet's kill: the reward split by rank and damage (MercFleet.split).
## False when nobody in the fleet can be paid (then the usual split runs).
func _resolve_fleet_bounty(c: BountyContract, killer: Node3D, d: Durability) -> bool:
	var f := c.fleet
	var k := killer as Ship
	if k and k.captain:
		c.killer_name = k.captain.captain_name
	var parts := f.split(c.reward, d.tally if d else {})
	if parts.is_empty():
		return false
	var total := 0
	var lines: PackedStringArray = []
	for p in parts:
		var s := p["ship"] as Ship
		var pay := pay_captain(s, int(p["credits"]), c)
		total += pay
		c.payouts.append({"ship_name": s.get_display_name(), "credits": pay})
		lines.append("%s %s%s" % [String(p["name"]).get_slice(" ", 0), Fmt.amount(pay), " (left early)" if bool(p["left_early"]) else ""])
		s.show_toast("+%d cr fleet share" % pay, Ship.TOAST_REWARD)
		if s.captain:
			s.captain.note_job(true)
	var target := c.target
	EventLog.post("%s's fleet (%d) destroyed %s, %s cr split: %s" % [f.leader_name, f.roster.size(), c.get_target_name(), Fmt.amount(total), ", ".join(lines)],
			EventLog.Kind.REWARD, null, target.global_position if is_instance_valid(target) else Vector3.INF)
	f.finish()
	c.fleet = null
	_refund_escrow(c, "Bounty leftover")
	c.mark_completed()
	return true


func _on_contract_changed(contract: Contract) -> void:
	contract_changed.emit(contract)
	if contract.is_finished() and contracts.has(contract):
		contracts.erase(contract)
		contract_removed.emit(contract)

extends Node
## Autoload "ContractBoard". Every contract the player posts lives here.
## Captains read [method get_available] to pick work; the UI lists
## [method get_listed] and the 3D markers follow [signal contract_posted] /
## [signal contract_removed].
##
## Payment model (mining): nothing is reserved when posting. The player pays
## the per-load reward when a miner delivers a load, and the ore goes into
## the player's stock by type (Economy.ore_of_belt). When the player cannot pay a delivery in full, the miner sells
## only the part that can be paid for (credits run to 0, materials scale
## down). Captains also refuse new runs while the station cannot pay one full
## load ("Station can't pay"), so this only happens to loads already mined.
## Cancelling stops new takers at once; trips already under way are honoured
## and paid on delivery.
##
## Stage 2: bounties (paid on the target's destruction, split among the
## player ships that damaged it) and escorts (paid per escorted trip, on the
## miner's delivery). Every payment to a captain also collects the station's
## share of it back (Economy.collect_fees).
##
## Stage 3: salvage. Salvagers work scrap fields on their own (free salvage,
## paid by their Salvage Yard, which reprocesses the scrap and sells the ore
## to the player); a posted salvage contract adds a per-load bonus from the
## player. Sometimes a load holds a rare part for the Factory. Also
## reputation for escort trips. Bigger holds deliver bigger loads (more pay
## and materials); prospecting scanners add materials only.

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

var mining_rules: MiningRules
## Open and active contracts, in posting order.
var contracts: Array[Contract] = []

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
	contract.changed.connect(_on_contract_changed)
	contracts.append(contract)
	contract_posted.emit(contract)
	return contract


func post_mining(belt: SystemBelt, credits_per_load: int, max_loads: int = 0) -> MiningContract:
	if belt == null:
		return null
	return post(MiningContract.new(belt, maxi(credits_per_load, 0), max_loads)) as MiningContract


## Bounty on a scavenger ship or den. Completes when the target dies.
func post_bounty(on_target: Node3D, credits: int, max_takers: int = 3) -> BountyContract:
	if not Combat.is_live(on_target):
		return null
	var c := post(BountyContract.new(on_target, maxi(credits, 0), max_takers)) as BountyContract
	_wire(c)
	return c


## Salvage bonus on a scrap field, paid per delivered load on top of the
## yard's pay. Completes when the field is stripped or gone.
func post_salvage(field: ScrapField, credits_per_load: int, max_takers: int = 3) -> SalvageContract:
	if field == null or not is_instance_valid(field) or field.amount <= 0:
		return null
	var c := post(SalvageContract.new(field, maxi(credits_per_load, 0), max_takers)) as SalvageContract
	_wire(c)
	return c


## Escort on one miner.
func post_escort(ward: Ship, pay_per_trip: int, max_escorts: int = 2) -> EscortContract:
	if ward == null or ward.dead:
		return null
	var c := post(EscortContract.new(ward, null, maxi(pay_per_trip, 0), max_escorts)) as EscortContract
	_wire(c)
	return c


## Escort linked to a mining contract: every trip on it can be escorted.
func post_escort_for_mining(mc: MiningContract, pay_per_trip: int, max_escorts: int = 2) -> EscortContract:
	if mc == null or mc.is_finished():
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
				cancel(bc)
		on_target.tree_exiting.connect(func() -> void: check_gone.call_deferred())
	elif c is SalvageContract and is_instance_valid((c as SalvageContract).field):
		var sc := c as SalvageContract
		sc.field.depleted.connect(func(_f: ScrapField) -> void: sc.mark_done())
		sc.field.tree_exiting.connect(func() -> void: sc.mark_done())
	elif c is EscortContract:
		var ec := c as EscortContract
		if is_instance_valid(ec.ward):
			ec.ward.destroyed.connect(func(_s: Ship, _k: Node3D) -> void: cancel(ec))
		elif ec.mining_contract:
			var mc := ec.mining_contract
			mc.changed.connect(func(_m: Contract) -> void:
				if mc.is_finished():
					cancel(ec))


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


## Pays [param amount] to a captain's ship from the player's credits
## (partial when short) and collects the station fee back. Returns the
## credits paid.
func pay_captain(ship: Ship, amount: int, contract: Contract = null) -> int:
	var pay := mini(amount, maxi(Economy.credits, 0))
	if pay <= 0:
		return 0
	Economy.spend(pay)
	if contract:
		contract.credits_paid += pay
	if ship and ship.captain:
		ship.captain.credits_earned += pay
		Economy.collect_fees(ship.captain, pay)
	payout_made.emit(contract, ship, pay)
	return pay


## Withdraws a contract: no new takers. Ships already on a trip finish it.
func cancel(contract: Contract) -> void:
	if contract == null or contract.is_finished():
		return
	contract.mark_cancelled()


## Contracts a new taker could start on now, optionally of one type.
func get_available(type: int = -1) -> Array[Contract]:
	var out: Array[Contract] = []
	for c in contracts:
		if (type < 0 or c.type == type) and c.is_available():
			out.append(c)
	return out


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
	var pay := mini(full_pay, maxi(Economy.credits, 0))
	var mat := full_mat
	if pay < full_pay:
		mat = floori(float(full_mat) * float(pay) / maxf(float(full_pay), 1.0))
	if pay > 0:
		Economy.spend(pay)
	if mat > 0:
		# Into the outpost's stock; a cargo shuttle brings it to the station.
		var depot := CargoDepot.of_ship(ship)
		if depot:
			depot.add_stock(Economy.ore_of_belt(ore), mat)
		else:
			Economy.add_ore_of(Economy.ore_of_belt(ore), mat)
	contract.credits_paid += pay
	contract.materials_delivered += mat
	if s and s.captain and pay > 0:
		Economy.collect_fees(s.captain, pay)
	contract.finish_trip(ship, true)
	delivery_made.emit(contract, ship, pay, mat, ore)
	var escorted := _pay_escorts(s, contract) > 0 if s else false
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
	var full_bonus := roundi(float(contract.reward) * fraction)
	var bonus := mini(full_bonus, maxi(Economy.credits, 0))
	if bonus > 0:
		Economy.spend(bonus)
		if s and s.captain:
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


## A rare Mk II/III part in the haul: it goes into the Factory warehouse and
## lets the Factory make it early, or discounts it when already tooled.
## Returns the module name ("" without a Factory).
func _find_rare_part(ship: Ship) -> String:
	var o := Factory.find(ship.get_tree())
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
			escort.show_toast("+%d cr escort" % pay, Color(0.55, 1.0, 0.65))
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
		s.show_toast("+%d cr bounty" % pay, Color(1.0, 0.85, 0.4))
	var who := c.killer_name if not c.killer_name.is_empty() else ("%d mercenaries" % earners.size() if earners.size() > 1 else "")
	var solo := c.solo_runner()
	if earners.size() == 1 and solo == earners[0]:
		who = "%s, alone" % solo.get_display_name()
	if earners.size() > 1:
		who = "%s and %d more" % [earners[0].get_display_name() if c.killer_name.is_empty() else c.killer_name, earners.size() - 1]
	var tname := c.get_target_name()
	if not who.is_empty():
		EventLog.post("%s destroyed by %s (+%d cr bounty)" % [tname, who, total], EventLog.Kind.REWARD, null, target.global_position if is_instance_valid(target) else Vector3.INF)
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
		lines.append("%s %s%s" % [String(p["name"]).get_slice(" ", 0), UIUtil.amount(pay), " (left early)" if bool(p["left_early"]) else ""])
		s.show_toast("+%d cr fleet share" % pay, Color(1.0, 0.85, 0.4))
		if s.captain:
			s.captain.note_job(true)
	var target := c.target
	EventLog.post("%s's fleet (%d) destroyed %s, %s cr split: %s" % [f.leader_name, f.roster.size(), c.get_target_name(), UIUtil.amount(total), ", ".join(lines)],
			EventLog.Kind.REWARD, null, target.global_position if is_instance_valid(target) else Vector3.INF)
	f.state = MercFleet.State.DONE
	c.fleet = null
	c.mark_completed()
	return true


func _on_contract_changed(contract: Contract) -> void:
	contract_changed.emit(contract)
	if contract.is_finished() and contracts.has(contract):
		contracts.erase(contract)
		contract_removed.emit(contract)

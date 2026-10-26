class_name ContractCodec
extends RefCounted
## Saves and restores contracts: the board's open and active ones, finished
## ones that a trip is still on, and free salvage contracts in use. Links
## (targets, takers, escort assignments, the mining contract of a linked
## escort) are saved by save id. Restoring builds every contract first and
## links them in a second pass ([method restore_all]), after the ships, dens
## and scrap fields exist. A bounty keeps its escrow (the credits reserved
## for it); a bounty from a save made before escrow reserves its reward from
## the loaded credits (what they cover).

const BASE_FIELDS: PackedStringArray = ["id", "reward", "status", "max_takers", "created_time", "credits_paid", "times_taken"]


## Every contract worth keeping: the board's plus [param extra] (trips) plus
## the free salvage contracts with takers.
static func save_all(extra: Array[Contract]) -> Dictionary:
	var all: Array[Contract] = []
	for c in ContractBoard.contracts:
		all.append(c)
	for c in extra:
		if c and not all.has(c):
			all.append(c)
	for c in SalvageContract._free.values():
		var sc := c as SalvageContract
		if sc and not sc.takers.is_empty() and not all.has(sc):
			all.append(sc)
	var list := []
	for c in all:
		list.append(save_contract(c, ContractBoard.contracts.has(c)))
	return {"next_id": ContractBoard.next_id(), "free_next": SalvageContract._next_free_id, "contracts": list}


static func save_contract(c: Contract, listed: bool) -> Dictionary:
	var d := SaveUtil.props(c, BASE_FIELDS)
	d["sid"] = SaveIds.of(c)
	d["type"] = c.type
	d["listed"] = listed
	d["target"] = SaveIds.of(c.target) if is_instance_valid(c.target) else 0
	d["takers"] = SaveUtil.ids(c.takers)
	if c is MiningContract:
		var mc := c as MiningContract
		d["belt"] = mc.belt.def.name if is_instance_valid(mc.belt) else ""
		d["mining"] = SaveUtil.props(mc, ["ore_type", "max_loads", "loads_delivered", "loads_in_flight", "materials_delivered", "depleted", "site_name"])
	elif c is BountyContract:
		var bc := c as BountyContract
		var solo := bc.solo_runner()
		d["bounty"] = {"payouts": bc.payouts, "killer_name": bc.killer_name, "solo": SaveIds.of(solo) if solo else 0, "escrow": bc.escrow}
	elif c is EscortContract:
		var ec := c as EscortContract
		var pairs := []
		for e in ec.assignments:
			var m: Variant = ec.assignments[e]
			if is_instance_valid(e) and is_instance_valid(m):
				pairs.append([SaveIds.of(e), SaveIds.of(m)])
		d["escort"] = {"ward": SaveIds.of(ec.ward) if is_instance_valid(ec.ward) else 0, "mining": SaveIds.of(ec.mining_contract) if ec.mining_contract else 0,
				"max_escorts": ec.max_escorts, "trips_completed": ec.trips_completed, "assignments": pairs}
	elif c is PlanetRaidContract:
		var rc := c as PlanetRaidContract
		d["planet"] = rc.planet.def.name if is_instance_valid(rc.planet) else ""
		d["raid"] = SaveUtil.props(rc, ["loot", "max_loads", "loads_delivered", "loads_in_flight", "units_delivered"])
	elif c is SalvageContract:
		var sc := c as SalvageContract
		d["salvage"] = SaveUtil.props(sc, ["loads_delivered", "loads_in_flight", "materials_delivered", "rare_chance", "free"])
	return d


## Builds, links and lists every saved contract. Needs the ships, dens,
## scrap fields and clusters registered in [param refs] (clusters by name in
## [param belts], old belt names included). [param ctx]: a node in the
## contracts' system (planet raids find their planet there).
static func restore_all(d: Dictionary, refs: SaveRefs, belts: Dictionary, ctx: Node = null) -> void:
	var made: Array[Array] = []
	for s: Dictionary in d.get("contracts", []):
		var c := _make(s, refs, belts, ctx)
		if c:
			refs.add(int(s["sid"]), c)
			made.append([c, s])
	for pair in made:
		_link(pair[0] as Contract, pair[1] as Dictionary, refs)
	var next := int(d.get("next_id", 1))
	for pair in made:
		var c := pair[0] as Contract
		var s := pair[1] as Dictionary
		var listed := bool(s.get("listed", false)) and not c.is_finished() and is_instance_valid(c.target)
		if c is SalvageContract and (c as SalvageContract).free:
			SalvageContract.restore_free((c as SalvageContract).field, c as SalvageContract)
			continue
		ContractBoard.restore(c, listed, next)
	SalvageContract._next_free_id = mini(SalvageContract._next_free_id, int(d.get("free_next", -1)))


static func _make(s: Dictionary, refs: SaveRefs, belts: Dictionary, ctx: Node) -> Contract:
	var target := refs.node3d(int(s.get("target", 0)))
	var c: Contract
	match int(s["type"]):
		Contract.Type.MINING:
			# Old saves name the belt ("Cinder Belt"): the map holds those
			# names for their starting clusters too. A cluster that is gone
			# (mined out) leaves the contract without a target: trips on it
			# still deliver, then it completes.
			var belt := belts.get(String(s.get("belt", ""))) as AsteroidCluster
			var mc := MiningContract.new(belt, int(s["reward"]))
			SaveUtil.apply_props(mc, s.get("mining", {}))
			if mc.site_name.is_empty():
				mc.site_name = String(s.get("belt", ""))
			if belt == null:
				mc.depleted = true
			c = mc
		Contract.Type.BOUNTY:
			var bc := BountyContract.new(target, int(s["reward"]), int(s["max_takers"]))
			var bd: Dictionary = s.get("bounty", {})
			bc.payouts.assign(bd.get("payouts", []))
			bc.killer_name = String(bd.get("killer_name", ""))
			if bd.has("escrow"):
				bc.escrow = int(bd["escrow"])
			elif bool(s.get("listed", false)) and int(s.get("status", 0)) < Contract.Status.COMPLETED:
				# Saved before escrow: reserve it now from the loaded credits.
				var held := mini(int(s["reward"]), maxi(Economy.credits, 0))
				if held > 0 and Economy.spend(held):
					bc.escrow = held
			c = bc
		Contract.Type.ESCORT:
			var ed: Dictionary = s.get("escort", {})
			var ward := refs.ship(int(ed.get("ward", 0)))
			if int(ed.get("ward", 0)) != 0 and ward == null:
				# The escorted ship is gone: nothing left to protect.
				return null
			var ec := EscortContract.new(ward, null, int(s["reward"]), int(ed.get("max_escorts", 2)))
			ec.trips_completed = int(ed.get("trips_completed", 0))
			c = ec
		Contract.Type.PLANET_RAID:
			var body := PlanetRaidContract.find_planet(ctx, String(s.get("planet", ""))) if ctx else null
			if body == null:
				return null
			var rc := PlanetRaidContract.new(body, int(s["reward"]))
			SaveUtil.apply_props(rc, s.get("raid", {}))
			c = rc
		Contract.Type.SALVAGE:
			var field := target as ScrapField
			if field == null:
				return null
			var sc := SalvageContract.new(field, int(s["reward"]), int(s["max_takers"]))
			SaveUtil.apply_props(sc, s.get("salvage", {}))
			c = sc
		_:
			return null
	var base := {}
	for k in BASE_FIELDS:
		if s.has(k):
			base[k] = s[k]
	SaveUtil.apply_props(c, base)
	if c is EscortContract and target and (c as EscortContract).ward == null:
		c.target = target
	return c


## Takers, escort assignments and links between contracts.
static func _link(c: Contract, s: Dictionary, refs: SaveRefs) -> void:
	c.takers.clear()
	for id: int in s.get("takers", []):
		var t := refs.ship(id)
		if t:
			c.takers.append(t)
	if c is BountyContract:
		var solo := refs.ship(int((s.get("bounty", {}) as Dictionary).get("solo", 0)))
		if solo:
			(c as BountyContract).claim_solo(solo)
	elif c is EscortContract:
		var ec := c as EscortContract
		var ed: Dictionary = s.get("escort", {})
		var mc := refs.find(int(ed.get("mining", 0))) as MiningContract
		if mc:
			ec.mining_contract = mc
			if ec.ward == null:
				ec.target = mc.belt
		for pair: Array in ed.get("assignments", []):
			var e := refs.ship(int(pair[0]))
			var m := refs.ship(int(pair[1]))
			if e and m:
				ec.assign(e, m)
		if ec.ward == null and ec.mining_contract == null:
			ec.status = Contract.Status.CANCELLED

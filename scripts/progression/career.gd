class_name Career
extends RefCounted
## Career switching. A docked captain with enough reputation may decide to
## change role: miner -> mercenary, miner or mercenary -> salvager. They need
## a free berth at an outpost of the new role and buy the new ship from their
## wallet (that outpost's BuildingDef.ship_cost; part of it comes back to the
## player). Rank, traits and reputation carry over; the new specialty skill
## starts at 2-3 and the old ship's modules stay with the old ship.
##
## Appeal of a role ([method appeal], >= [constant WANT] to go):
##   Mercenary  Bold +0.35, Nerve and Piloting, Grudge +0.3, Cautious -0.3,
##              Shaken -0.4
##   Salvager   Cautious +0.25, Greedy +0.2, Lazy +0.1, Survivor +0.3,
##              Shaken +0.2, Bold -0.15
##   both       +0.08 per rank above Licensed
## A player offer ("Offer transfer" in the captain panel) adds
## [constant OFFER_BONUS], but the captain still decides.

## Rank needed to switch.
const MIN_RANK := Reputation.Rank.LICENSED
## Chance per visit home that a captain thinks about it at all.
const THINK_CHANCE := 0.15
## Sim seconds after a hire or switch before the next one.
const COOLDOWN := 600.0
const WANT := 0.5
const OFFER_BONUS := 0.35
const NEW_SKILL := Vector2i(2, 3)

static var rng := RandomNumberGenerator.new()


## Roles [param captain] could move to.
static func targets_for(captain: Captain) -> PackedStringArray:
	match captain.role:
		"Miner":
			return PackedStringArray(["Mercenary", "Salvager"])
		"Mercenary":
			return PackedStringArray(["Salvager"])
	return PackedStringArray()


static func appeal(captain: Captain, target: String) -> float:
	var a := 0.08 * float(maxi(captain.rank - MIN_RANK, 0))
	var p := captain.personality
	match target:
		"Mercenary":
			a += 0.35 if p == Captain.Personality.BOLD else 0.0
			a -= 0.3 if p == Captain.Personality.CAUTIOUS else 0.0
			a += 0.25 * Captain.factor(captain.effective_nerve()) + 0.15 * Captain.factor(captain.piloting)
			a += 0.3 if captain.has_trait(CaptainTraits.GRUDGE) else 0.0
			a -= 0.4 if captain.has_trait(CaptainTraits.SHAKEN) else 0.0
		"Salvager":
			a += 0.25 if p == Captain.Personality.CAUTIOUS else 0.0
			a += 0.2 if p == Captain.Personality.GREEDY else 0.0
			a += 0.1 if p == Captain.Personality.LAZY else 0.0
			a -= 0.15 if p == Captain.Personality.BOLD else 0.0
			a += 0.3 if captain.has_trait(CaptainTraits.SURVIVOR) else 0.0
			a += 0.2 if captain.has_trait(CaptainTraits.SHAKEN) else 0.0
	return a


## Active outpost of [param role] with a free berth, or null.
static func find_berth(tree: SceneTree, role: String) -> Building:
	var mgr := tree.get_first_node_in_group(BuildingManager.GROUP) as BuildingManager
	if mgr == null:
		return null
	for b in mgr.buildings:
		if is_instance_valid(b) and b.is_active() and b.def.hire_role == role and b.captains.size() < b.def.max_hires:
			return b
	return null


## Why [param ship]'s captain will not move to [param target] now, or "".
static func block_reason(ship: Ship, target: String, offered: bool) -> String:
	var c := ship.captain
	if c == null or not targets_for(c).has(target):
		return "Cannot fly as a %s" % target.to_lower()
	if c.rank < MIN_RANK:
		return "Needs %s rank first" % Reputation.rank_name(MIN_RANK)
	var b := find_berth(ship.get_tree(), target)
	if b == null:
		return "No free berth at a %s outpost" % target.to_lower()
	if c.wallet < b.def.ship_cost:
		return "Can't afford a new ship (%s of %s cr)" % [UIUtil.amount(c.wallet), UIUtil.amount(b.def.ship_cost)]
	if appeal(c, target) + (OFFER_BONUS if offered else 0.0) < WANT:
		return "Not interested"
	return ""


## On a visit home: maybe think about a new career and take it. True when
## [param ship] left service (it was replaced).
static func consider(ship: Ship) -> bool:
	var c := ship.captain
	if c == null or c.rank < MIN_RANK or SimClock.time - c.career_since < COOLDOWN:
		return false
	if rng.randf() >= THINK_CHANCE:
		return false
	for target in targets_for(c):
		if block_reason(ship, target, false).is_empty():
			return switch(ship, target) != null
	return false


## The player suggests a move. Returns the captain's answer ("" = yes, they
## switched; else why not).
static func offer(ship: Ship, target: String) -> String:
	var why := block_reason(ship, target, true)
	if why.is_empty():
		if switch(ship, target) == null:
			return "Could not switch"
		return ""
	return why


## Moves the captain into a new ship of [param target]. Returns it.
static func switch(ship: Ship, target: String) -> Ship:
	var c := ship.captain
	var b := find_berth(ship.get_tree(), target)
	if c == null or b == null or c.wallet < b.def.ship_cost:
		return null
	var old_role := c.role
	var old_home := ship.home.display_name if is_instance_valid(ship.home) else "?"
	c.wallet -= b.def.ship_cost
	c.credits_spent += b.def.ship_cost
	Economy.add_income(roundi(b.def.ship_cost * Building.SHIP_SALE_SHARE), "Ship sales")
	ship.retire()
	c.role = target
	c.specialty = Captain.specialty_for(target)
	c.skill = rng.randi_range(NEW_SKILL.x, NEW_SKILL.y)
	c.career_since = SimClock.time
	c.add_history("Left %s, %s to %s at %s" % [old_home, old_role.to_lower(), target.to_lower(), b.display_name])
	var ns := b.adopt(c)
	EventLog.post("%s quit mining to fly as a %s" % [c.captain_name, target.to_lower()] if old_role == "Miner" else
			"%s quit %s work to fly as a %s" % [c.captain_name, old_role.to_lower(), target.to_lower()],
			EventLog.Kind.INFO, ns)
	return ns

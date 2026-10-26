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
static func find_berth(ctx: Node, role: String) -> Building:
	var mgr := BuildingManager.of(ctx)
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
	var b := find_berth(ship, target)
	if b == null:
		return "No free berth at a %s outpost" % target.to_lower()
	if c.wallet < b.def.ship_cost:
		return "Can't afford a new ship (%s of %s cr)" % [Fmt.amount(c.wallet), Fmt.amount(b.def.ship_cost)]
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
		var why := block_reason(ship, target, false)
		if why.is_empty():
			return switch(ship, target, "Thought it over: appeal %.2f, wants %.2f" % [appeal(c, target), WANT]) != null
		c.flight_log.note(CaptainLog.Kind.CAREER, CaptainLog.Outcome.REFUSED, "Thought about %s work: %s" % [target.to_lower(), why.to_lower()],
				appeal_line(c, target, false), "", "career:%s:%s" % [target, why])
	return false


## "Appeal 0.32 (Bold +0.35, Nerve +0.12 ...), wants 0.50"
static func appeal_line(c: Captain, target: String, offered: bool) -> String:
	var parts: PackedStringArray = []
	var rank_part := 0.08 * float(maxi(c.rank - MIN_RANK, 0))
	if rank_part > 0.0:
		parts.append("rank %+.2f" % rank_part)
	match target:
		"Mercenary":
			parts.append("%s %+.2f" % [c.get_personality_name(), 0.35 if c.personality == Captain.Personality.BOLD else (-0.3 if c.personality == Captain.Personality.CAUTIOUS else 0.0)])
			parts.append("Nerve %+.2f" % (0.25 * Captain.factor(c.effective_nerve())))
			parts.append("Piloting %+.2f" % (0.15 * Captain.factor(c.piloting)))
		"Salvager":
			var p := 0.0
			match c.personality:
				Captain.Personality.CAUTIOUS:
					p = 0.25
				Captain.Personality.GREEDY:
					p = 0.2
				Captain.Personality.LAZY:
					p = 0.1
				Captain.Personality.BOLD:
					p = -0.15
			parts.append("%s %+.2f" % [c.get_personality_name(), p])
	if offered:
		parts.append("your offer %+.2f" % OFFER_BONUS)
	return "Appeal %.2f (%s), wants %.2f" % [appeal(c, target) + (OFFER_BONUS if offered else 0.0), ", ".join(parts), WANT]


## The player suggests a move. Returns the captain's answer ("" = yes, they
## switched; else why not).
static func offer(ship: Ship, target: String) -> String:
	var why := block_reason(ship, target, true)
	var c := ship.captain
	if why.is_empty():
		if switch(ship, target, "You offered the move. " + appeal_line(c, target, true)) == null:
			return "Could not switch"
		return ""
	if c:
		c.flight_log.note(CaptainLog.Kind.CAREER, CaptainLog.Outcome.REFUSED, "Turned down your offer of %s work: %s" % [target.to_lower(), why.to_lower()],
				appeal_line(c, target, true) if why == "Not interested" else why)
	return why


## Moves the captain into a new ship of [param target]. Returns it.
## [param why] goes to the decision log.
static func switch(ship: Ship, target: String, why: String = "") -> Ship:
	var c := ship.captain
	var b := find_berth(ship, target)
	if c == null or b == null or c.wallet < b.def.ship_cost:
		return null
	var old_role := c.role
	var old_home := ship.home.display_name if is_instance_valid(ship.home) else "?"
	c.wallet -= b.def.ship_cost
	c.credits_spent += b.def.ship_cost
	Economy.add_income(roundi(b.def.ship_cost * Building.SHIP_SALE_SHARE), Ledger.SHIP_SALES, "Ship sold at %s" % b.display_name)
	ship.retire()
	c.role = target
	c.specialty = Captain.specialty_for(target)
	c.skill = rng.randi_range(NEW_SKILL.x, NEW_SKILL.y)
	c.career_since = SimClock.time
	c.add_history("Left %s, %s to %s at %s" % [old_home, old_role.to_lower(), target.to_lower(), b.display_name])
	c.flight_log.note(CaptainLog.Kind.CAREER, CaptainLog.Outcome.DID, "Switched from %s to %s work at %s" % [old_role.to_lower(), target.to_lower(), b.display_name],
			why, "Paid %s cr for the new ship; rank, traits and reputation carry over, the %s skill starts at %d" % [Fmt.amount(b.def.ship_cost), c.get_specialty_name(), c.skill])
	var ns := b.adopt(c)
	EventLog.post("%s quit mining to fly as a %s" % [c.captain_name, target.to_lower()] if old_role == "Miner" else
			"%s quit %s work to fly as a %s" % [c.captain_name, old_role.to_lower(), target.to_lower()],
			EventLog.Kind.INFO, ns)
	return ns

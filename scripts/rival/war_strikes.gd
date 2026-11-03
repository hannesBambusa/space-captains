class_name WarStrikes
extends RefCounted
## Corp war strikes and captain poaching (rival corporation plan, R6), the
## same for both corps.
##
## A strike: a corp pays a war bonus to the mercenaries that volunteer
## ([method volunteers]: idle at their own station, hull above
## [constant MIN_HULL], by personality and Loyalty) and sends them
## ([method launch], MercenaryBrain.strike_to) through the gates to the other
## corp's station system. There they shoot its shield, turrets, station and
## structures, and fly home when hurt, when nothing is left to hit or when
## the war ends.
##
## Poaching: a recruiting offer to one of the other corp's captains
## ([method poach]); the captain weighs it against Loyalty, wallet and how
## the job has gone. Taking it, the captain leaves its ship at the old
## station and flies a new one from a berth of its role at the new corp.

const MIN_HULL := 0.75
## Volunteer chance by personality (BOLD, CAUTIOUS, GREEDY, LAZY).
const VOLUNTEER: PackedFloat32Array = [0.9, 0.35, 0.6, 0.4]


## Mercs of [param corp_id] free to go now, best first, at most [param n].
static func volunteers(tree: SceneTree, corp_id: StringName, n: int) -> Array[Ship]:
	var out: Array[Ship] = []
	for s in RivalCorp.mercs_of(tree, corp_id):
		var mb := s.brain as MercenaryBrain
		if mb == null or s.transit or mb.mode == MercenaryBrain.Mode.STRIKE or mb.fleet or mb.mode == MercenaryBrain.Mode.ESCORT:
			continue
		if s.hull_fraction() < MIN_HULL:
			continue
		out.append(s)
	out.sort_custom(func(a: Ship, b: Ship) -> bool: return MercFleet.power_of(a) > MercFleet.power_of(b))
	return out.slice(0, n)


## Sends up to [param n] volunteers of [param corp_id] to [param target],
## [param bonus] credits each from the corp. Returns {sent: [Ship],
## refused: [String]}.
static func launch(tree: SceneTree, corp_id: StringName, target: StringName, bonus: int, n: int) -> Dictionary:
	var sent: Array[Ship] = []
	var refused: PackedStringArray = []
	var eco := Corps.economy_of_corp(corp_id)
	for s in volunteers(tree, corp_id, n * 2):
		if sent.size() >= n:
			break
		var c := s.captain
		var chance := VOLUNTEER[c.personality] + 0.03 * (c.loyalty - 5) + float(bonus) / 1000.0
		if s.brain.rng.randf() > chance:
			refused.append("%s said no (%d%%)" % [c.captain_name, roundi(clampf(chance, 0.0, 1.0) * 100.0)])
			continue
		if not (s.brain as MercenaryBrain).strike_to(target):
			continue
		if bonus > 0 and eco.credits >= bonus:
			ContractBoard.pay_captain(s, bonus)
		sent.append(s)
	if corp_id == Corps.PLAYER and not sent.is_empty():
		var names: PackedStringArray = []
		for s in sent:
			names.append(s.captain.captain_name)
		EventLog.post("War strike on %s: %s on the way" % [Sector.system_def(target).system_name if Sector.system_def(target) else "?", ", ".join(names)],
				EventLog.Kind.COMBAT, sent[0])
	return {"sent": sent, "refused": refused}


# --- Poaching --------------------------------------------------------------------

## The captain of [param from_corp] most open to an offer now (lowest
## Loyalty, docked at its station), or null.
static func poach_candidate(tree: SceneTree, from_corp: StringName) -> Captain:
	var best: Captain = null
	var best_l := 99
	for w in SystemWorld.all(tree):
		if not w.has_station or w.corp_id != from_corp or w.buildings == null:
			continue
		for b in w.buildings.buildings:
			if not is_instance_valid(b):
				continue
			for c in b.captains:
				if c.ship and is_instance_valid(c.ship) and c.ship.is_docked() and c.loyalty < best_l:
					best_l = c.loyalty
					best = c
	return best


## Chance that [param c] takes [param pay] to switch corps.
static func poach_chance(c: Captain, pay: int) -> float:
	var ch := 0.15 + 0.06 * (6 - c.loyalty) + float(pay) / 2000.0
	if c.wallet < 100:
		ch += 0.1
	if c.personality == Captain.Personality.GREEDY:
		ch += 0.15
	return clampf(ch, 0.02, 0.8)


## Offers [param c] [param pay] to fly for [param to_corp]. Returns {ok, text}.
static func poach(tree: SceneTree, c: Captain, to_corp: StringName, pay: int) -> Dictionary:
	if c == null or not is_instance_valid(c.ship):
		return {"ok": false, "text": "Nobody to approach"}
	var berth := _berth_for(tree, to_corp, c.role)
	if berth == null:
		return {"ok": false, "text": "No free %s berth to offer %s" % [c.role.to_lower(), c.captain_name]}
	var chance := poach_chance(c, pay)
	if c.ship.brain.rng.randf() > chance:
		return {"ok": false, "text": "%s turned the offer down (%d%%, Loyalty %d)" % [c.captain_name, roundi(chance * 100.0), c.loyalty]}
	var old := c.ship
	var old_home := old.home
	old.retire()
	if is_instance_valid(old_home):
		old_home.captains.erase(c)
		old_home.waiting.erase(c)
	c.wallet += pay
	c.add_history("Left %s for a %d cr offer from %s" % [old_home.display_name if is_instance_valid(old_home) else "?", pay, Corps.get_corp(to_corp).display_name])
	var ns := berth.adopt(c)
	return {"ok": ns != null, "text": "%s accepted the offer (%d%%) and now flies from %s" % [c.captain_name, roundi(chance * 100.0), berth.display_name]}


static func _berth_for(tree: SceneTree, corp_id: StringName, role: String) -> Building:
	for w in SystemWorld.all(tree):
		if not w.has_station or w.corp_id != corp_id or w.buildings == null:
			continue
		for b in w.buildings.buildings:
			if is_instance_valid(b) and b.is_active() and b.def.hire_role == role and b.captains.size() < b.def.max_hires:
				return b
	return null

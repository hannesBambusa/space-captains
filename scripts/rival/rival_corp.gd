class_name RivalCorp
extends Node
## The rival corporations' head offices (rival corporation plan, M1: 1 to
## 3 rivals): child of the [ViewManager], idle while the rivals are Off
## (Corps.has_rival). Each rival's memory is its [RivalMind] (saved with
## the corps); what it thinks of another corp is a RivalMind.Tie.
##
## Founding: on a new game each rival's headquarters goes into its home
## system (Corps.home_of): a station site with "corp" and "hq"
## (RemoteSystemState.station), pinned live for good. Its colony is run by
## the [RivalManager] in that world.
##
## Discovery: a rival charts the network outward from its home, one system
## per [method scout_time] while its Explorer Outpost has an explorer (an
## abstract survey program). Charting another corp's home means it has
## found that corp. The player finds a rival by surveying its home. Either
## direction is first contact between the two (both ties), and from then on
## their boardrooms may pick every stance toward each other. Rivals deal
## with each other the same way they deal with the player.
##
## Boardroom: every [method meeting_time] each rival scores the stances
## toward every corp it has a tie to ([method stance_scores]: strength,
## grudge, losses, weariness, opportunity, relations, by personality and
## difficulty) and keeps the best (the current one gets
## [constant STAY_BONUS]). A war ends only by a treaty: offers to the player
## come as a card it answers in 60 s real time; offers to another rival are
## answered by that rival's board at once ([method _ai_answer]).
##
## Hostile acts toward a corp it harasses or fights: hired raiders through
## the player's gates (GateRaidSource.form_hired; only against the player),
## shuttle sabotage, poaching a captain; at war also war strikes
## ([WarStrikes]) on that corp's home, warned 75 s ahead when it is yours.

const GROUP := "rival_corp"
## Sim seconds before the first boardroom (each rival a little later).
const FIRST_MEETING := 240.0
## A site planet keeps this far (orbit radius) from every hostile base.
const MIN_BASE_GAP := ForwardStations.MIN_BASE_DISTANCE
## Meetings, ops, strikes, scouting, by difficulty (Off, Easy, Normal, Hard), sim seconds.
const MEETING_TIMES: PackedFloat32Array = [300.0, 360.0, 300.0, 240.0]
const OP_TIMES: PackedFloat32Array = [480.0, 600.0, 480.0, 360.0]
const STRIKE_TIMES: PackedFloat32Array = [420.0, 600.0, 420.0, 300.0]
const SCOUT_TIMES: PackedFloat32Array = [180.0, 260.0, 180.0, 130.0]
const STAY_BONUS := 0.25
const STRIKE_WARNING := 75.0
const OFFER_MS := 60000
const CEASEFIRE := 1200.0
const PACT_TIME := 1200.0
## Trade income per sim minute for each side while a pact holds.
const PACT_TRADE := 30.0
## Personality weights per stance (PEACE, PACT, HARASS, WAR, SUE).
const WEIGHTS := {
	RivalMind.Personality.MERCHANT: [1.4, 1.6, 0.6, 0.5, 1.2],
	RivalMind.Personality.WARLORD: [0.8, 0.7, 1.0, 1.6, 0.7],
	RivalMind.Personality.SABOTEUR: [0.9, 0.8, 1.8, 0.8, 1.0],
	RivalMind.Personality.OPPORTUNIST: [1.0, 1.0, 1.2, 1.2, 1.0],
}
const P := Corps.PLAYER

## An offer card to the player changed (shown, answered, expired).
signal offer_changed
## A stance, contact or relations changed (the Rival panel).
signal changed

var _tick := 0.0
## Rival id -> sim seconds of scouting toward the next chart.
var _scout := {}
## "a|b" -> pact trade credits not paid yet.
var _trade := {}
var _rng := RandomNumberGenerator.new()


static func of(tree: SceneTree) -> RivalCorp:
	return tree.get_first_node_in_group(GROUP) as RivalCorp if tree else null


## [param rid]'s mind, null when there is no such rival.
static func mind(rid: StringName) -> RivalMind:
	var r := Corps.rival(rid)
	return r.mind if r else null


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(SimStepper.GROUP)
	_rng.seed = hash("rival_corp:%d" % Sector.get_seed())
	if not Sector.surveyed.is_connected(_on_surveyed):
		Sector.surveyed.connect(_on_surveyed)
	# After ForwardStations pinned the saved sites (and a load's apply_scene).
	_found_hqs.call_deferred()


func _process(delta: float) -> void:
	if not SimClock.paused:
		sim_step(delta * SimClock.speed)
	_check_offer_expiry()


func _diff(table: PackedFloat32Array) -> float:
	return table[clampi(Corps.difficulty, 0, table.size() - 1)]


func meeting_time() -> float:
	return _diff(MEETING_TIMES)


func op_time() -> float:
	return _diff(OP_TIMES)


func scout_time() -> float:
	return _diff(SCOUT_TIMES)


# --- Founding -----------------------------------------------------------------

func _found_hqs() -> void:
	if not Corps.has_rival() or Sector.network == null:
		return
	var vm := get_parent() as ViewManager
	if vm == null:
		return
	var fresh := false
	for r in Corps.rivals:
		if r.mind.eliminated:
			continue
		var id := Corps.home_of(r.id)
		var st := Sector.state(id)
		if st == null:
			continue
		if st.station.is_empty():
			var site := hq_site(id)
			if site.is_empty():
				push_warning("RivalCorp: no planet for %s's headquarters in %s" % [r.display_name, id])
				continue
			site["corp"] = String(r.id)
			site["hq"] = true
			site["name"] = "%s HQ" % r.display_name
			site["node"] = "RivalStation"
			site["model"] = HomeStation.STATION_PATH
			site["founded_at"] = 0.0
			st.station = site
			fresh = true
		if not vm.is_pinned(id):
			vm.pin(id)
	if fresh and SimClock.time < 5.0:
		var names: PackedStringArray = []
		for r in Corps.rivals:
			names.append(r.display_name)
		var who := names[0] if names.size() == 1 else "%s and %s" % [", ".join(names.slice(0, names.size() - 1)), names[names.size() - 1]]
		EventLog.post_public("Corporate briefing: %s also hold%s a charter in this sector. Where they operate is unknown: survey the deep systems to find them."
				% [who, "s" if names.size() == 1 else ""], EventLog.Kind.INFO)


## The headquarters site in [param id]: the planet nearest an iron cluster
## where they are now (they drift apart on their orbits, as home's Cinder
## Cluster does), whose orbit keeps [constant MIN_BASE_GAP] from every
## base's anchor (else the one farthest from them).
static func hq_site(id: StringName) -> Dictionary:
	var def := Sector.system_def(id)
	if def == null or def.planets.is_empty():
		return {}
	var t := SimClock.time
	var best: PlanetDef = null
	var best_score := INF
	for p in def.planets:
		var gap := INF
		for d in def.dens:
			gap = minf(gap, absf(p.orbit_radius - d.anchor_radius))
		var pp := Survey.planet_position(p, t)
		var near := INF
		for b in def.belts:
			var w := 1.0 if b.ore_type == AsteroidBelt.OreType.IRON else 2.0
			near = minf(near, pp.distance_to(Survey.cluster_position(b, t)) * w)
		var score := near + (0.0 if gap >= MIN_BASE_GAP else 100000.0 - gap)
		if score < best_score:
			best_score = score
			best = p
	return ForwardStations.site_on(id, best.name) if best else {}


# --- Step ---------------------------------------------------------------------

func sim_step(dt: float) -> void:
	if not Corps.has_rival() or dt <= 0.0:
		return
	for r in Corps.living_rivals():
		_scout_step(r, dt)
		_pact_trade(r, dt)
	_tick -= dt
	if _tick > 0.0:
		return
	_tick = 2.0
	for r in Corps.living_rivals():
		_step_rival(r)


func _step_rival(r: Corp) -> void:
	var m := r.mind
	_check_contacts(r)
	for k: StringName in m.ties:
		var t: RivalMind.Tie = m.ties[k]
		t.grudge = maxf(t.grudge - 0.02, 0.0)
	var pt := m.tie(P)
	if pt.contact and not pt.personality_known and SimClock.time - pt.since > 600.0:
		pt.personality_known = true
		var pn := m.personality_name().to_lower()
		_public(r, "Intel: %s's board is run like %s %s house" % [r.display_name, "an" if pn.begins_with("o") else "a", pn])
	if SimClock.time >= m.next_meeting:
		m.next_meeting = SimClock.time + meeting_time()
		for k: StringName in _targets(r):
			_meeting(r, k)
	for k: StringName in _targets(r):
		_ops(r, k)
		_strike_step(r, k)


## Corps [param r] has a view of now: the player, and every rival it met.
func _targets(r: Corp) -> Array[StringName]:
	var out: Array[StringName] = [P]
	for o in Corps.living_rivals():
		if o != r and r.mind.has_tie(o.id) and r.mind.tie(o.id).contact:
			out.append(o.id)
	return out


# --- Discovery -----------------------------------------------------------------

## Systems rival [param rid] has charted (its home first).
func charted(rid: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	var m := mind(rid)
	if m:
		for id: String in m.stats.get("charted", []):
			out.append(StringName(id))
	var home := Corps.home_of(rid)
	if out.is_empty() and not home.is_empty():
		out.append(home)
	return out


func _scout_step(r: Corp, dt: float) -> void:
	if not _has_explorer(r.id):
		return
	var t := float(_scout.get(r.id, 0.0)) + dt
	_scout[r.id] = t
	if t < scout_time():
		return
	_scout[r.id] = 0.0
	var known := charted(r.id)
	var frontier: Array[StringName] = []
	for id in known:
		for nb in Sector.network.neighbours(id):
			if not known.has(nb) and not frontier.has(nb):
				frontier.append(nb)
	if frontier.is_empty():
		return
	# Toward the shallow systems first (the way in from the deep); once it
	# knows the player's home, out into the deep, where the other rivals are.
	var deep := r.mind.tie(P).i_know_them
	frontier.sort_custom(func(a: StringName, b: StringName) -> bool:
		return Sector.network.depth(a) > Sector.network.depth(b) if deep else Sector.network.depth(a) < Sector.network.depth(b))
	var pick: StringName = frontier[0] if _rng.randf() < 0.7 else frontier[_rng.randi_range(0, frontier.size() - 1)]
	known.append(pick)
	var list: Array = []
	for id in known:
		list.append(String(id))
	r.mind.stats["charted"] = list
	var def := Sector.system_def(pick)
	r.mind.note("Our scouts charted %s" % (def.system_name if def else "the other charter's home" if pick == ClusterNetwork.HOME_ID else String(pick)))
	var owner := Corps.corp_at_home(pick)
	if not owner.is_empty() and owner != r.id:
		r.mind.tie(owner).i_know_them = true
		var o := Corps.rival(owner)
		if o:
			o.mind.tie(r.id).they_know_me = true
		r.mind.note("Our scouts found the home station of %s" % _name_for(r, owner))


func _has_explorer(rid: StringName) -> bool:
	var w := Corps.hq_world(get_tree(), rid)
	if w == null or w.buildings == null:
		return false
	for b in w.buildings.buildings:
		if is_instance_valid(b) and b.def.id == &"explorer_outpost" and b.is_active() and not b.captains.is_empty():
			return true
	return false


func _on_surveyed(id: StringName) -> void:
	var owner := Corps.corp_at_home(id)
	var r := Corps.rival(owner)
	if r:
		r.mind.tie(P).they_know_me = true
		_check_contacts(r)


## First contact of [param r] with every corp one of them has found.
func _check_contacts(r: Corp) -> void:
	var pt := r.mind.tie(P)
	var st := Sector.state(Corps.home_of(r.id))
	if st and st.known:
		pt.they_know_me = true
	if not pt.contact and (pt.they_know_me or pt.i_know_them):
		pt.contact = true
		pt.since = SimClock.time
		var where := "at %s" % _home_name(r.id) if pt.they_know_me else "from beyond the gates"
		_public(r, "First contact: %s hails your station %s. Diplomacy is open (Rival panel, R)" % [r.display_name, where], EventLog.Kind.REWARD)
		_toast("First contact: %s" % r.display_name)
		changed.emit()
	for o in Corps.living_rivals():
		if o == r or not r.mind.has_tie(o.id):
			continue
		var t := r.mind.tie(o.id)
		if t.contact or not (t.i_know_them or t.they_know_me):
			continue
		t.contact = true
		t.since = SimClock.time
		var back := o.mind.tie(r.id)
		back.contact = true
		back.since = SimClock.time
		r.mind.note("We made contact with %s" % o.display_name)
		o.mind.note("We made contact with %s" % r.display_name)
		if _player_knows(r) or _player_knows(o):
			_public(r, "Intel: %s and %s have made contact" % [r.display_name, o.display_name])
		changed.emit()


func _player_knows(r: Corp) -> bool:
	return r.mind.tie(P).contact


func _home_name(rid: StringName) -> String:
	var def := Sector.system_def(Corps.home_of(rid))
	return def.system_name if def else "?"


# --- Strength -------------------------------------------------------------------

## Fighting strength of [param corp_id]: its mercenaries' power, turrets,
## shields and stations (for the boardroom and the Rival panel).
static func strength(tree: SceneTree, corp_id: StringName) -> float:
	var p := 0.0
	for w in SystemWorld.all(tree):
		if not w.has_station or w.corp_id != corp_id:
			continue
		p += 1.5
		for n in SystemWorld.nodes_in(w, Ship.GROUP):
			var s := n as Ship
			if s and not s.dead and s.role == Ship.Role.MERCENARY and Corps.owner_of(s) == corp_id:
				p += MercFleet.power_of(s)
		for n in SystemWorld.nodes_in(w, Combat.GROUP):
			if n is DefenseTurret and Combat.is_live(n):
				p += 0.6
			elif n is StationShield and Combat.is_live(n):
				p += 1.0
	return p


## Its mercenaries in its own station systems, alive (strike volunteers).
static func mercs_of(tree: SceneTree, corp_id: StringName) -> Array[Ship]:
	var out: Array[Ship] = []
	for w in SystemWorld.all(tree):
		if not w.has_station or w.corp_id != corp_id:
			continue
		for n in SystemWorld.nodes_in(w, Ship.GROUP):
			var s := n as Ship
			if s and not s.dead and s.role == Ship.Role.MERCENARY and s.captain and Corps.owner_of(s) == corp_id:
				out.append(s)
	return out


# --- Boardroom ------------------------------------------------------------------

## [param r]'s scores per stance toward [param other], with the terms:
## {scores: [5 floats], ratio, mine, theirs, opp, cease}.
func stance_scores(r: Corp, other: StringName) -> Dictionary:
	var m := r.mind
	var t := m.tie(other)
	var mine := strength(get_tree(), r.id)
	var theirs := maxf(strength(get_tree(), other), 0.5)
	var ratio := mine / theirs
	var eco_r := float(r.economy.credits) / maxf(float(Corps.economy_of_corp(other).credits), 500.0)
	# Opportunity: the other's home is weak right now.
	var opp := clampf(ratio - 1.0, 0.0, 2.0)
	var hw := Corps.hq_world(get_tree(), other)
	if hw and hw.buildings and hw.buildings.station_hull and hw.buildings.station_hull.disabled:
		opp += 1.0
	var w: Array = WEIGHTS[m.personality]
	var war_mult: float = [1.0, 0.7, 1.0, 1.2][clampi(Corps.difficulty, 0, 3)]
	var rel := t.relations / 50.0
	var s := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, -99.0])
	s[RivalMind.Stance.PEACE] = (1.0 + rel * 0.6 + t.weariness * 0.4 - t.grudge / 60.0) * w[0]
	s[RivalMind.Stance.PACT] = (0.55 + rel * 0.8 + clampf(1.0 - absf(ratio - 1.0), 0.0, 1.0) * 0.3 - t.grudge / 40.0) * w[1] if t.contact else -99.0
	s[RivalMind.Stance.HARASS] = (0.25 + t.grudge / 40.0 + opp * 0.3 + clampf(eco_r - 1.0, 0.0, 1.0) * 0.2 - rel * 0.4) * w[2] * war_mult if t.i_know_them else -99.0
	s[RivalMind.Stance.WAR] = (-0.5 + 1.1 * (ratio - 1.0) + t.grudge / 30.0 + opp * 0.4 - t.weariness - rel * 0.6) * w[3] * war_mult if t.i_know_them and t.contact else -99.0
	if Corps.corps_at_war(r.id, other):
		s[RivalMind.Stance.SUE_FOR_PEACE] = (t.weariness + t.losses / 6.0 + clampf(1.0 - ratio, 0.0, 1.0) * 1.5 - 0.4) * w[4]
	var cease := SimClock.time < t.ceasefire_until or SimClock.time < t.pact_until
	if cease:
		s[RivalMind.Stance.WAR] = -99.0
		s[RivalMind.Stance.HARASS] = -99.0
	return {"scores": s, "ratio": ratio, "mine": mine, "theirs": theirs, "opp": opp, "cease": cease}


func _meeting(r: Corp, other: StringName) -> void:
	var m := r.mind
	var t := m.tie(other)
	var at_war := Corps.corps_at_war(r.id, other)
	if at_war:
		t.weariness += 0.15 + 0.05 * t.losses
	else:
		t.weariness = maxf(t.weariness - 0.2, 0.0)
	var res := stance_scores(r, other)
	var s: PackedFloat32Array = res["scores"]
	var cur := int(t.stance)
	var shown := s.duplicate()
	if cur != RivalMind.Stance.SUE_FOR_PEACE:
		shown[cur] += STAY_BONUS
	var order: Array[int] = [0, 1, 2, 3, 4]
	order.sort_custom(func(a: int, b: int) -> bool: return shown[a] > shown[b])
	var best := order[0]
	var parts: PackedStringArray = []
	for i in 5:
		if s[i] > -50.0:
			parts.append("%s %.2f" % [RivalMind.STANCE_NAMES[i].to_lower(), s[i]])
	m.note("Boardroom on %s: %s; strength %.1f vs %.1f -> %s (runner-up %s)" % [_name_for(r, other), ", ".join(parts), float(res["mine"]), float(res["theirs"]),
			RivalMind.STANCE_NAMES[best], RivalMind.STANCE_NAMES[order[1]]])
	# A war ends only by a treaty: wanting anything else at war is suing for peace.
	if best == RivalMind.Stance.SUE_FOR_PEACE or (at_war and best != RivalMind.Stance.WAR):
		_offer(r, other, "peace")
		return
	if best == RivalMind.Stance.PACT and t.stance != RivalMind.Stance.PACT:
		_offer(r, other, "pact")
		return
	if best != cur and not (at_war and best == RivalMind.Stance.WAR):
		set_stance(r, other, best as RivalMind.Stance)
	# Strong and greedy: a tribute demand now and then.
	if t.contact and not at_war and float(res["ratio"]) > 1.6 and m.personality in [RivalMind.Personality.WARLORD, RivalMind.Personality.OPPORTUNIST] \
			and _rng.randf() < 0.35:
		_offer(r, other, "tribute")


## How [param r]'s notes name [param other].
func _name_for(_r: Corp, other: StringName) -> String:
	return "the other charter" if other == P else Corps.display_name(other)


## [param r]'s stance toward [param other]. A war is mutual: the other
## side's tie goes to war too (a rival's; the player's is only the rival's).
func set_stance(r: Corp, other: StringName, st: RivalMind.Stance) -> void:
	var t := r.mind.tie(other)
	if t.stance == st:
		return
	var was_war := Corps.corps_at_war(r.id, other)
	t.stance = st
	t.since = SimClock.time
	var o := Corps.rival(other)
	var player_side := other == P
	match st:
		RivalMind.Stance.WAR:
			t.losses = 0.0
			t.relations = minf(t.relations, -60.0)
			t.last_strike = SimClock.time - _diff(STRIKE_TIMES) + 120.0
			r.mind.stats["wars"] = int(r.mind.stats.get("wars", 0)) + 1
			if o:
				var back := o.mind.tie(r.id)
				back.stance = RivalMind.Stance.WAR
				back.since = SimClock.time
				back.relations = minf(back.relations, -60.0)
				back.losses = 0.0
				o.mind.note("%s declared war on us" % r.display_name)
			if player_side:
				_public(r, "%s has declared war on your station" % r.display_name, EventLog.Kind.THREAT)
				_toast("WAR: %s declared war" % r.display_name)
			elif _player_knows(r) or (o and _player_knows(o)):
				_public(r, "Intel: %s has declared war on %s" % [r.display_name, Corps.display_name(other)], EventLog.Kind.THREAT)
		RivalMind.Stance.PEACE:
			if was_war:
				if o:
					var back2 := o.mind.tie(r.id)
					back2.stance = RivalMind.Stance.PEACE
					back2.since = SimClock.time
				if player_side:
					_public(r, "The war with %s is over" % r.display_name, EventLog.Kind.REWARD)
					_toast("Peace with %s" % r.display_name)
				elif _player_knows(r) or (o and _player_knows(o)):
					_public(r, "Intel: %s and %s made peace" % [r.display_name, Corps.display_name(other)])
			t.weariness *= 0.5
		RivalMind.Stance.HARASS:
			r.mind.note("We start a quiet campaign against %s" % _name_for(r, other))
		RivalMind.Stance.PACT:
			t.pact_until = SimClock.time + PACT_TIME
			t.relations = maxf(t.relations, 20.0)
			if o:
				var back3 := o.mind.tie(r.id)
				back3.stance = RivalMind.Stance.PACT
				back3.pact_until = t.pact_until
				back3.relations = maxf(back3.relations, 20.0)
	changed.emit()


# --- Offers -----------------------------------------------------------------------

## [param r] offers [param kind] ("peace", "pact", "tribute") to [param other].
func _offer(r: Corp, other: StringName, kind: String) -> void:
	var t := r.mind.tie(other)
	if kind == "peace":
		t.stance = RivalMind.Stance.SUE_FOR_PEACE
	var terms := {}
	var text := ""
	match kind:
		"peace":
			var pay := clampi(roundi(r.economy.credits * 0.3 / 50.0) * 50, 200, 2000)
			terms = {"reparations": pay}
			text = "We are ready to end this war. Ceasefire for %d min and %s cr in reparations to you." % [roundi(CEASEFIRE / 60.0), Fmt.amount(pay)]
		"pact":
			text = "A trade pact: no hostilities for %d min and %d cr per minute in trade for each of us." % [roundi(PACT_TIME / 60.0), roundi(PACT_TRADE)]
		"tribute":
			var amount := clampi(roundi(Corps.economy_of_corp(other).credits * 0.15 / 50.0) * 50, 300, 3000)
			terms = {"amount": amount}
			text = "Pay %s cr in tribute, or we will treat your refusal as a provocation." % Fmt.amount(amount)
	if other != P:
		_ai_answer(r, Corps.rival(other), kind, terms)
		return
	if not t.offer.is_empty():
		return
	t.offer = {"kind": kind, "text": text, "terms": terms, "until": Time.get_ticks_msec() + OFFER_MS}
	_public(r, "%s: %s" % [r.display_name, text], EventLog.Kind.INFO)
	_toast("%s sends an offer" % r.display_name)
	offer_changed.emit()


## Another rival's board answers [param r]'s offer at once, by its own scores.
func _ai_answer(r: Corp, o: Corp, kind: String, terms: Dictionary) -> void:
	if o == null:
		return
	var res := stance_scores(o, r.id)
	var s: PackedFloat32Array = res["scores"]
	var ok := false
	match kind:
		"peace":
			ok = s[RivalMind.Stance.SUE_FOR_PEACE] >= s[RivalMind.Stance.WAR] - 0.2 or o.mind.tie(r.id).weariness > 1.0
			if ok:
				_settle_peace(r, o.id, int(terms.get("reparations", 0)))
			else:
				r.mind.tie(o.id).stance = RivalMind.Stance.WAR
		"pact":
			ok = s[RivalMind.Stance.PACT] >= maxf(s[RivalMind.Stance.HARASS], s[RivalMind.Stance.WAR]) - 0.2
			if ok:
				set_stance(r, o.id, RivalMind.Stance.PACT)
		"tribute":
			var amount := int(terms.get("amount", 0))
			ok = float(res["ratio"]) < 0.7 and o.economy.credits >= amount
			if ok:
				o.economy.spend(amount, PackedInt32Array(), Ledger.OTHER, "Tribute to %s" % r.display_name)
				r.economy.add_income(amount, Ledger.OTHER, "Tribute from %s" % o.display_name)
			else:
				r.mind.tie(o.id).grudge += 10.0
	var line := "%s offered %s %s: %s" % [r.display_name, o.display_name, kind, "accepted" if ok else "refused"]
	r.mind.note(line)
	o.mind.note(line)
	if ok and (_player_knows(r) or _player_knows(o)) and kind != "tribute":
		_public(r, "Intel: %s" % line)


## The open offer of rival [param rid] to the player, {} when none.
func offer(rid: StringName) -> Dictionary:
	var m := mind(rid)
	return m.tie(P).offer if m else {}


## The first rival with an open offer to the player: {rid, offer}, {} when none.
func first_offer() -> Dictionary:
	for r in Corps.living_rivals():
		var o := r.mind.tie(P).offer
		if not o.is_empty():
			return {"rid": r.id, "offer": o}
	return {}


## The player's answer to [param rid]: "accept", "reject" or "counter".
func answer_offer(rid: StringName, choice: String) -> String:
	var r := Corps.rival(rid)
	if r == null:
		return ""
	var t := r.mind.tie(P)
	if t.offer.is_empty():
		return ""
	var o := t.offer
	t.offer = {}
	var kind := String(o["kind"])
	var terms: Dictionary = o.get("terms", {})
	var reply := ""
	match kind:
		"peace":
			if choice == "accept":
				_settle_peace(r, P, int(terms.get("reparations", 0)))
				reply = "Treaty signed with %s: ceasefire, %s cr in reparations received" % [r.display_name, Fmt.amount(int(terms.get("reparations", 0)))]
			elif choice == "counter":
				var want := int(terms.get("reparations", 0)) * 2
				var desperate := float(stance_scores(r, P)["scores"][RivalMind.Stance.SUE_FOR_PEACE]) > 1.3
				if desperate and r.economy.credits >= want:
					_settle_peace(r, P, want)
					reply = "%s accepted your counter: %s cr in reparations" % [r.display_name, Fmt.amount(want)]
				else:
					t.stance = RivalMind.Stance.WAR
					reply = "%s refused your counter (%s cr): the war goes on" % [r.display_name, Fmt.amount(want)]
			else:
				t.stance = RivalMind.Stance.WAR
				t.grudge += 5.0
				reply = "You refused %s's treaty: the war goes on" % r.display_name
		"pact":
			if choice == "accept":
				set_stance(r, P, RivalMind.Stance.PACT)
				t.relations += 15.0
				reply = "Trade pact with %s signed for %d min" % [r.display_name, roundi(PACT_TIME / 60.0)]
			else:
				t.relations -= 8.0
				reply = "You turned %s's pact down" % r.display_name
		"tribute":
			var amount := int(terms.get("amount", 0))
			if choice == "accept" and Economy.spend(amount, PackedInt32Array(), Ledger.OTHER, "Tribute to %s" % r.display_name):
				r.economy.add_income(amount, Ledger.OTHER, "Tribute")
				t.relations += 10.0
				reply = "You paid %s cr in tribute to %s" % [Fmt.amount(amount), r.display_name]
			elif choice == "counter" and Economy.spend(amount / 2, PackedInt32Array(), Ledger.OTHER, "Tribute to %s" % r.display_name):
				r.economy.add_income(amount / 2, Ledger.OTHER, "Tribute")
				var pleased := _rng.randf() < 0.5
				if not pleased:
					t.grudge += 8.0
				reply = "%s took %s cr, %s" % [r.display_name, Fmt.amount(amount / 2), "and seems satisfied" if pleased else "but is not satisfied"]
			else:
				t.grudge += 15.0
				t.relations -= 25.0
				reply = "You refused %s's tribute: they will remember it" % r.display_name
	r.mind.note("Offer %s: the other charter answered %s" % [kind, choice])
	_public(r, reply, EventLog.Kind.INFO)
	offer_changed.emit()
	changed.emit()
	return reply


func _check_offer_expiry() -> void:
	for r in Corps.rivals:
		var o := r.mind.tie(P).offer
		if not o.is_empty() and Time.get_ticks_msec() > int(o.get("until", 0)):
			answer_offer(r.id, "reject")


## A ceasefire between [param r] and [param other], [param reparations] from
## [param r] to [param other].
func _settle_peace(r: Corp, other: StringName, reparations: int) -> void:
	if reparations > 0:
		reparations = mini(reparations, maxi(r.economy.credits, 0))
		r.economy.spend(reparations, PackedInt32Array(), Ledger.OTHER, "Reparations")
		Corps.economy_of_corp(other).add_income(reparations, Ledger.OTHER, "Reparations from %s" % r.display_name)
	var t := r.mind.tie(other)
	t.ceasefire_until = SimClock.time + CEASEFIRE
	r.mind.stats["treaties"] = int(r.mind.stats.get("treaties", 0)) + 1
	var o := Corps.rival(other)
	if o:
		o.mind.tie(r.id).ceasefire_until = t.ceasefire_until
	t.stance = RivalMind.Stance.WAR
	set_stance(r, other, RivalMind.Stance.PEACE)
	t.relations = maxf(t.relations, -20.0)


# --- The player's diplomacy -------------------------------------------------------

## Why the player cannot use [param kind] toward rival [param rid] now, or "".
func propose_problem(rid: StringName, kind: String) -> String:
	var r := Corps.rival(rid)
	if r == null:
		return "No such rival"
	if r.mind.eliminated:
		return "%s is out of the game" % r.display_name
	var t := r.mind.tie(P)
	if not t.contact:
		return "No contact yet: find their home or wait for them to find you"
	if not t.offer.is_empty():
		return "Answer their offer first"
	var war := Corps.corps_at_war(rid, P)
	match kind:
		"pact":
			if war:
				return "At war: offer peace first"
			if t.stance == RivalMind.Stance.PACT:
				return "A pact holds already"
		"tribute":
			if not war:
				return "Only from a corp at war with you"
		"peace":
			if not war:
				return "You are not at war"
		"war":
			if war:
				return "Already at war"
			if not t.they_know_me:
				return "You do not know where they are: survey their home first"
	return ""


## The player proposes [param kind] ("pact", "tribute", "peace", "war") to
## rival [param rid]; its board scores it and answers. Returns {ok, text}.
func player_proposes(rid: StringName, kind: String) -> Dictionary:
	var why := propose_problem(rid, kind)
	if not why.is_empty():
		return {"ok": false, "text": why}
	var r := Corps.rival(rid)
	var t := r.mind.tie(P)
	var res := stance_scores(r, P)
	var s: PackedFloat32Array = res["scores"]
	var ok := false
	var text := ""
	match kind:
		"pact":
			var best := maxf(s[RivalMind.Stance.HARASS], s[RivalMind.Stance.WAR])
			ok = t.relations > -25.0 and s[RivalMind.Stance.PACT] >= best - 0.2
			text = "accepted a trade pact" if ok else "turned the pact down (pact %.2f against %.2f for hostility, relations %d)" % [s[RivalMind.Stance.PACT], best, roundi(t.relations)]
			if ok:
				set_stance(r, P, RivalMind.Stance.PACT)
		"tribute":
			ok = float(res["ratio"]) < 0.7 and t.weariness > 0.6
			if ok:
				var amount := mini(clampi(roundi(r.economy.credits * 0.25 / 50.0) * 50, 100, 2500), maxi(r.economy.credits, 0))
				r.economy.spend(amount, PackedInt32Array(), Ledger.OTHER, "Tribute paid")
				Economy.add_income(amount, Ledger.OTHER, "Tribute from %s" % r.display_name)
				text = "paid %s cr in tribute" % Fmt.amount(amount)
			else:
				t.grudge += 4.0
				text = "refused to pay (strength %.1f vs %.1f, weariness %.1f)" % [float(res["mine"]), float(res["theirs"]), t.weariness]
		"peace":
			ok = s[RivalMind.Stance.SUE_FOR_PEACE] >= s[RivalMind.Stance.WAR] - 0.2
			text = "agreed to a ceasefire" if ok else "refused peace (peace %.2f against war %.2f)" % [s[RivalMind.Stance.SUE_FOR_PEACE], s[RivalMind.Stance.WAR]]
			if ok:
				_settle_peace(r, P, 0)
		"war":
			ok = true
			t.grudge += 10.0
			t.relations = -60.0
			set_stance(r, P, RivalMind.Stance.WAR)
			text = "received your declaration of war"
	r.mind.note("The other charter proposed %s: we %s" % [kind, text])
	var line := "%s %s" % [r.display_name, text]
	if kind != "war":
		_public(r, line, EventLog.Kind.INFO)
	changed.emit()
	return {"ok": ok, "text": line}


# --- Hostile acts -----------------------------------------------------------------

func _ops(r: Corp, other: StringName) -> void:
	var t := r.mind.tie(other)
	if not t.hostile() or not t.i_know_them or SimClock.time - t.last_op < op_time():
		return
	t.last_op = SimClock.time
	var roll := _rng.randf()
	var saboteur := r.mind.personality == RivalMind.Personality.SABOTEUR
	var done := false
	if roll < 0.5 and other == P:
		done = _hired_raid(r)
	elif roll < (0.75 if saboteur else 0.7):
		done = _sabotage(r, other)
	if not done:
		done = _poach(r, other)
	if not done and other == P:
		_hired_raid(r)


func _hired_raid(r: Corp) -> bool:
	var home := SystemWorld.home(get_tree())
	var gr := home.combat.gate_raids if home and home.combat else null
	var cost := 500
	if gr == null or r.economy.credits < cost + RivalManager.RESERVE:
		return false
	var size := 2 + mini(floori(SimClock.time / 1200.0), 3)
	if not gr.form_hired(size, r.id):
		return false
	r.economy.spend(cost, PackedInt32Array(), Ledger.OTHER, "Hired raiders")
	r.mind.stats["ops"] = int(r.mind.stats.get("ops", 0)) + 1
	r.mind.note("We paid %d cr for %d raiders against the other charter" % [cost, size])
	if r.mind.tie(P).they_know_me and _rng.randf() < 0.5:
		_public(r, "Intercepted comms: the raiders forming beyond your gates were paid by %s" % r.display_name, EventLog.Kind.THREAT)
	return true


## A loaded cargo shuttle of [param other]'s home blows up in flight.
func _sabotage(r: Corp, other: StringName) -> bool:
	var home := Corps.hq_world(get_tree(), other)
	if home == null:
		return false
	for n in SystemWorld.nodes_in(home, Ship.GROUP):
		var sh := n as CargoShuttle
		if sh and not sh.dead and sh.is_carrying_cargo() and not sh.is_loading() and not sh.is_docked():
			sh.take_hit(99999.0, null, sh.global_position)
			r.mind.stats["ops"] = int(r.mind.stats.get("ops", 0)) + 1
			r.mind.note("Our agent planted a charge on a cargo shuttle of %s" % _name_for(r, other))
			if other == P:
				EventLog.post("A cargo shuttle exploded in flight: sabotage suspected", EventLog.Kind.LOSS, null, sh.global_position)
			else:
				Corps.rival(other).mind.note("A cargo shuttle exploded in flight: sabotage suspected")
			return true
	return false


## One of [param other]'s captains is offered a job by [param r].
func _poach(r: Corp, other: StringName) -> bool:
	var c := WarStrikes.poach_candidate(get_tree(), other)
	if c == null or Corps.hq_world(get_tree(), r.id) == null:
		return false
	var pay := 400
	var res := WarStrikes.poach(get_tree(), c, r.id, pay)
	if bool(res["ok"]):
		r.economy.spend(mini(pay, r.economy.credits), PackedInt32Array(), Ledger.HIRES, "Signing bonus")
		r.mind.stats["poached"] = int(r.mind.stats.get("poached", 0)) + 1
		if other == P:
			EventLog.post_public("%s left your station for a %d cr signing bonus from %s" % [c.captain_name, pay, r.display_name], EventLog.Kind.LOSS)
		else:
			Corps.rival(other).mind.tie(r.id).grudge += 3.0
	r.mind.note(String(res["text"]))
	return bool(res["ok"])


# --- War strikes ---------------------------------------------------------------------

func _strike_step(r: Corp, other: StringName) -> void:
	var t := r.mind.tie(other)
	if not Corps.corps_at_war(r.id, other) or not t.i_know_them:
		t.strike_at = -1.0
		return
	var n := 2 + mini(floori(SimClock.time / 1200.0), 4)
	if t.strike_at < 0.0:
		if SimClock.time - t.last_strike < _diff(STRIKE_TIMES):
			return
		if WarStrikes.volunteers(get_tree(), r.id, n).size() < 2:
			return
		t.strike_at = SimClock.time + STRIKE_WARNING
		if other == P:
			var where := "at %s" % _home_name(r.id) if t.they_know_me else "beyond your gates"
			EventLog.post_public("Long-range scans: a %s war fleet is forming %s" % [r.display_name, where], EventLog.Kind.THREAT)
			_toast("%s war fleet forming" % r.display_name)
		return
	if SimClock.time < t.strike_at:
		return
	t.strike_at = -1.0
	t.last_strike = SimClock.time
	var res := WarStrikes.launch(get_tree(), r.id, Corps.home_of(other), 120, n)
	r.mind.stats["strikes"] = int(r.mind.stats.get("strikes", 0)) + 1
	r.mind.note("War strike on %s: %d ships sent" % [_name_for(r, other), (res["sent"] as Array).size()])


# --- Kills and losses -------------------------------------------------------------------

## A ship died (Ship.destroy): kills between corps feed grudge, losses and relations.
static func note_destroyed(victim: Node, killer: Node) -> void:
	if not Corps.has_rival() or not is_instance_valid(victim):
		return
	var v := Corps.owner_of(victim)
	var k := Corps.owner_of(killer) if is_instance_valid(killer) else &""
	if v.is_empty() or k.is_empty() or v == k:
		return
	var rv := Corps.rival(v)
	if rv:
		var t := rv.mind.tie(k)
		t.grudge += 6.0
		t.losses += 1.0
		if not Corps.corps_at_war(v, k):
			t.relations -= 25.0
			rv.mind.note("%s shot down one of ours in peacetime" % Corps.display_name(k))
	var rk := Corps.rival(k)
	if rk:
		rk.mind.tie(v).relations -= 2.0


## A structure of a corp was disabled by [param attacker].
static func note_disabled(structure: Node, attacker: Node) -> void:
	if not Corps.has_rival() or not is_instance_valid(structure) or not is_instance_valid(attacker):
		return
	var v := Corps.owner_of(structure)
	var k := Corps.owner_of(attacker)
	var rv := Corps.rival(v)
	if rv and not k.is_empty() and k != v:
		var t := rv.mind.tie(k)
		t.grudge += 8.0
		t.losses += 2.0


# --- Pact trade ---------------------------------------------------------------------------

func _pact_trade(r: Corp, dt: float) -> void:
	for k: StringName in r.mind.ties.keys():
		var t: RivalMind.Tie = r.mind.ties[k]
		if t.stance != RivalMind.Stance.PACT:
			continue
		if SimClock.time > t.pact_until:
			r.mind.note("The trade pact with %s ran out" % _name_for(r, k))
			if k == P:
				_public(r, "The trade pact with %s ran out" % r.display_name, EventLog.Kind.INFO)
			set_stance(r, k, RivalMind.Stance.PEACE)
			continue
		var key := "%s|%s" % [r.id, k]
		var acc := float(_trade.get(key, 0.0)) + PACT_TRADE * dt / 60.0
		if acc >= 15.0:
			var n := floori(acc)
			acc -= n
			r.economy.add_income(n, Ledger.OTHER, "Pact trade")
			# Each side's pact pays it once: the player through its tie here,
			# another rival through its own tie to this one.
			if k == P:
				Economy.add_income(n, Ledger.OTHER, "Pact trade")
		_trade[key] = acc


# --- Helpers ----------------------------------------------------------------------------

func _public(r: Corp, text: String, kind: EventLog.Kind = EventLog.Kind.INFO) -> void:
	r.mind.note(text, true)
	EventLog.post_public(text, kind)


func _toast(text: String) -> void:
	var pm := get_tree().root.get_node_or_null(^"PauseMenu")
	if pm and pm.has_method(&"toast"):
		pm.call(&"toast", text)

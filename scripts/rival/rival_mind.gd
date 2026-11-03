class_name RivalMind
extends RefCounted
## What one rival corporation thinks and remembers, as plain data (saved
## by [Corps] under "corps"."rivals"[i]."mind"). [RivalCorp] (the
## boardrooms) reads and writes it; [RivalManager] reads the mood.
##
## Personality ([enum Personality], rolled per game and rival) weights the
## boardroom's stance scores. What it thinks of another corp is a [Tie] in
## [member ties], keyed by corp id: the player's from the start (unmet
## until contact), another rival's once they have met (rivals plan M1).
## A war between two corps holds while either side's tie says war
## (Corps.corps_at_war).

enum Personality { MERCHANT, WARLORD, SABOTEUR, OPPORTUNIST }
enum Stance { PEACE, PACT, HARASS, WAR, SUE_FOR_PEACE }

const PERSONALITY_NAMES: PackedStringArray = ["Merchant", "Warlord", "Saboteur", "Opportunist"]
const STANCE_NAMES: PackedStringArray = ["Peace", "Trade pact", "Harassment", "War", "Suing for peace"]
const MAX_INTEL := 80


## Its view of one other corp.
class Tie extends RefCounted:
	var stance: Stance = Stance.PEACE
	## Sim time the stance was set.
	var since := 0.0
	## -100..100.
	var relations := 0.0
	## What the other corp did to it (kills, poaching, refusals); fades.
	var grudge := 0.0
	## Ships and stations lost in the current war, weighted.
	var losses := 0.0
	var weariness := 0.0
	var contact := false
	## It knows where the other corp's home is.
	var i_know_them := false
	## The other corp knows where its home is.
	var they_know_me := false
	var pact_until := 0.0
	var ceasefire_until := 0.0
	var last_op := -1e9
	var last_strike := -1e9
	## Sim time a warned strike leaves, -1 = none forming.
	var strike_at := -1.0
	## The open offer to the player (player tie only), {} = none:
	## {kind, text, terms, until (real ms)}.
	var offer: Dictionary = {}
	## Its board's personality is known to the other corp (player tie only).
	var personality_known := false

	func at_war() -> bool:
		return stance == Stance.WAR or stance == Stance.SUE_FOR_PEACE

	## Hostile acts are on (war, or a harassment campaign).
	func hostile() -> bool:
		return at_war() or stance == Stance.HARASS

	func stance_name() -> String:
		return STANCE_NAMES[stance]

	func to_dict() -> Dictionary:
		return {"stance": int(stance), "since": since, "relations": relations, "grudge": grudge, "losses": losses, "weariness": weariness,
				"contact": contact, "i_know": i_know_them, "they_know": they_know_me, "pact_until": pact_until, "ceasefire_until": ceasefire_until,
				"last_op": last_op, "last_strike": last_strike, "strike_at": strike_at, "offer": offer.duplicate(true),
				"personality_known": personality_known}

	static func from_dict(d: Dictionary) -> Tie:
		var t := Tie.new()
		t.stance = int(d.get("stance", 0)) as Stance
		t.since = float(d.get("since", 0.0))
		t.relations = float(d.get("relations", 0.0))
		t.grudge = float(d.get("grudge", 0.0))
		t.losses = float(d.get("losses", 0.0))
		t.weariness = float(d.get("weariness", 0.0))
		t.contact = bool(d.get("contact", false))
		t.i_know_them = bool(d.get("i_know", false))
		t.they_know_me = bool(d.get("they_know", false))
		t.pact_until = float(d.get("pact_until", 0.0))
		t.ceasefire_until = float(d.get("ceasefire_until", 0.0))
		t.last_op = float(d.get("last_op", -1e9))
		t.last_strike = float(d.get("last_strike", -1e9))
		t.strike_at = float(d.get("strike_at", -1.0))
		t.offer = (d.get("offer", {}) as Dictionary).duplicate(true)
		t.personality_known = bool(d.get("personality_known", false))
		return t


var personality: Personality = Personality.MERCHANT
## Corp id -> [Tie].
var ties: Dictionary = {}
## Sim time of the next boardroom meeting.
var next_meeting := 0.0
## Newest last: {time, text, public (the player saw it)}.
var intel: Array[Dictionary] = []
## Counters for the end screens, and "charted" (system ids it charted).
var stats: Dictionary = {"strikes": 0, "ops": 0, "treaties": 0, "poached": 0, "lost_stations": 0}
## Eliminated (its home destroyed).
var eliminated := false


func personality_name() -> String:
	return PERSONALITY_NAMES[personality]


## Its tie to [param corp] (made on first use).
func tie(corp: StringName) -> Tie:
	var t: Tie = ties.get(corp)
	if t == null:
		t = Tie.new()
		ties[corp] = t
	return t


func has_tie(corp: StringName) -> bool:
	return ties.has(corp)


## Its side of a war with [param corp] is on.
func at_war_with(corp: StringName) -> bool:
	var t: Tie = ties.get(corp)
	return t != null and t.at_war()


## Corps it has met.
func met() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in ties:
		if (ties[k] as Tie).contact:
			out.append(k)
	return out


func note(text: String, public: bool = false) -> void:
	intel.append({"time": SimClock.time, "text": text, "public": public})
	if intel.size() > MAX_INTEL:
		intel.remove_at(0)


func to_dict() -> Dictionary:
	var td := {}
	for k: StringName in ties:
		td[String(k)] = (ties[k] as Tie).to_dict()
	return {"personality": int(personality), "ties": td, "next_meeting": next_meeting, "intel": intel.duplicate(true),
			"stats": stats.duplicate(true), "eliminated": eliminated}


## Reads both its own shape and the pre-M1 one (one player relationship).
static func from_dict(d: Dictionary) -> RivalMind:
	var m := RivalMind.new()
	m.personality = int(d.get("personality", 0)) as Personality
	m.next_meeting = float(d.get("next_meeting", 0.0))
	m.intel.assign(d.get("intel", []))
	var st: Dictionary = d.get("stats", {})
	for k: String in st:
		m.stats[k] = st[k]
	m.eliminated = bool(d.get("eliminated", false))
	var td: Dictionary = d.get("ties", {})
	for k: String in td:
		m.ties[StringName(k)] = Tie.from_dict(td[k])
	if td.is_empty() and d.has("stance"):
		var t := Tie.new()
		t.stance = int(d.get("stance", 0)) as Stance
		t.since = float(d.get("since", 0.0))
		t.relations = float(d.get("relations", 0.0))
		t.grudge = float(d.get("grudge", 0.0))
		t.losses = float(d.get("losses", 0.0))
		t.weariness = float(d.get("weariness", 0.0))
		t.contact = bool(d.get("contact", false))
		t.i_know_them = bool(d.get("located_player", false))
		t.they_know_me = bool(d.get("located_by_player", false))
		t.pact_until = float(d.get("pact_until", 0.0))
		t.ceasefire_until = float(d.get("ceasefire_until", 0.0))
		t.last_op = float(d.get("last_op", -1e9))
		t.last_strike = float(d.get("last_strike", -1e9))
		t.strike_at = float(m.stats.get("strike_at", -1.0))
		t.offer = (d.get("offer", {}) as Dictionary).duplicate(true)
		t.personality_known = bool(d.get("personality_known", false))
		m.ties[Corps.PLAYER] = t
	return m

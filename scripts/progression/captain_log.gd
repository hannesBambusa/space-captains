class_name CaptainLog
extends RefCounted
## A captain's decision log: what they decided and why, newest last, capped
## at [constant MAX_ENTRIES] (the oldest drop off). Shown in the captain
## panel's Log tab (CaptainLogView).
##
## Each entry: sim time, [enum Kind], [enum Outcome], a short headline
## ("Refused Talon Reach mining: too dangerous for that pay"), a plain "why"
## line and an optional multi-line detail with the numbers.
##
## Repeats coalesce: an entry with the same [param key] as one written in
## the last [constant COALESCE_WINDOW] sim seconds is not added again; that
## entry counts one more, takes the new text and moves to the newest place.
## Callers that know nothing changed call [method bump] instead, which
## formats no strings at all.

## A new entry, or a coalesced one that moved to the newest place.
signal written(entry: Entry)

enum Kind { CONTRACT, FLEET, COMBAT, RETREAT, REPAIR, PURCHASE, CAREER, REST, TRAIT, RANK, LOSS }
enum Outcome { ACCEPTED, REFUSED, DID, FAILED }
## UI filters (CaptainLogView).
enum Filter { ALL, CONTRACTS, COMBAT, MONEY, CAREER }

const MAX_ENTRIES := 150
const COALESCE_WINDOW := 600.0
const FILTER_NAMES: PackedStringArray = ["All", "Contracts", "Combat", "Money", "Career"]


class Entry:
	var serial: int = 0
	## First and latest sim time.
	var time: float = 0.0
	var last_time: float = 0.0
	var kind: Kind = Kind.CONTRACT
	var outcome: Outcome = Outcome.DID
	var headline: String = ""
	var why: String = ""
	var detail: String = ""
	var key: String = ""
	var count: int = 1


## Newest last.
var entries: Array[Entry] = []
var _by_key: Dictionary = {}
var _serial: int = 0


## Writes an entry (or coalesces it into a recent one with the same key).
func note(kind: Kind, outcome: Outcome, headline: String, why: String = "", detail: String = "", key: String = "") -> Entry:
	var now := SimClock.time
	var e := _recent(key, now)
	if e:
		e.count += 1
		e.last_time = now
		e.outcome = outcome
		e.headline = headline
		e.why = why
		e.detail = detail
		_to_newest(e)
		written.emit(e)
		return e
	e = Entry.new()
	_serial += 1
	e.serial = _serial
	e.time = now
	e.last_time = now
	e.kind = kind
	e.outcome = outcome
	e.headline = headline
	e.why = why
	e.detail = detail
	e.key = key
	entries.append(e)
	if not key.is_empty():
		_by_key[key] = e
	while entries.size() > MAX_ENTRIES:
		var old: Entry = entries.pop_front()
		if not old.key.is_empty() and _by_key.get(old.key) == old:
			_by_key.erase(old.key)
	written.emit(e)
	return e


## Counts one more repeat of the recent entry with [param key] (no text
## change). False when there is none (the caller should [method note]).
func bump(key: String) -> bool:
	var now := SimClock.time
	var e := _recent(key, now)
	if e == null:
		return false
	e.count += 1
	e.last_time = now
	_to_newest(e)
	written.emit(e)
	return true


func latest() -> Entry:
	return entries.back() if not entries.is_empty() else null


## Entries whose headline contains [param part] (tests).
func find(part: String) -> Array[Entry]:
	var out: Array[Entry] = []
	for e in entries:
		if e.headline.contains(part):
			out.append(e)
	return out


static func matches(e: Entry, filter: Filter) -> bool:
	match filter:
		Filter.CONTRACTS:
			return e.kind == Kind.CONTRACT or e.kind == Kind.FLEET or e.kind == Kind.REST
		Filter.COMBAT:
			return e.kind == Kind.COMBAT or e.kind == Kind.RETREAT or e.kind == Kind.FLEET or e.kind == Kind.LOSS
		Filter.MONEY:
			return e.kind == Kind.REPAIR or e.kind == Kind.PURCHASE
		Filter.CAREER:
			return e.kind == Kind.CAREER or e.kind == Kind.TRAIT or e.kind == Kind.RANK or e.kind == Kind.LOSS
	return true


func _recent(key: String, now: float) -> Entry:
	if key.is_empty():
		return null
	var e := _by_key.get(key) as Entry
	if e == null or now - e.last_time > COALESCE_WINDOW:
		return null
	return e


func _to_newest(e: Entry) -> void:
	if entries.back() == e:
		return
	entries.erase(e)
	entries.append(e)


# --- Save ---------------------------------------------------------------------

func save_state() -> Dictionary:
	var list := []
	for e in entries:
		list.append({"serial": e.serial, "time": e.time, "last_time": e.last_time, "kind": e.kind, "outcome": e.outcome,
				"headline": e.headline, "why": e.why, "detail": e.detail, "key": e.key, "count": e.count})
	return {"serial": _serial, "entries": list}


func load_state(d: Dictionary) -> void:
	entries.clear()
	_by_key.clear()
	_serial = int(d.get("serial", 0))
	for s: Dictionary in d.get("entries", []):
		var e := Entry.new()
		e.serial = int(s["serial"])
		e.time = float(s["time"])
		e.last_time = float(s["last_time"])
		e.kind = int(s["kind"]) as Kind
		e.outcome = int(s["outcome"]) as Outcome
		e.headline = String(s["headline"])
		e.why = String(s["why"])
		e.detail = String(s["detail"])
		e.key = String(s["key"])
		e.count = int(s["count"])
		entries.append(e)
		if not e.key.is_empty():
			_by_key[e.key] = e

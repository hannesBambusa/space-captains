class_name Ledger
extends RefCounted
## The credit log, owned by Economy ([member Economy.ledger]). Every credit
## change is one entry: {t (SimClock.time of the last change), t0 (of the
## first), amt (+in / -out), cat (category, [constant CATEGORIES]), label,
## bal (credits after), n (changes merged in), sys (system id, optional),
## held (credits paid out of an escrow: a note line with amt 0)}.
##
## Merging keeps the list short: a change joins a recent entry with the same
## category, label and sign while it is within [method merge_window] of that
## entry's first change (3 s, a minute for the steady trickles: Factory
## sales, fees, the grant, wages, repairs, raider looting). The merged entry moves
## to the end with the new balance. At most [constant MAX_ENTRIES] are kept;
## [member dropped_sum] holds what the dropped ones added up to, so
## [method total] always equals the credit change since the game started.
##
## Escrow: reserving credits (bounties, explore contracts, zone budgets) is
## one "Escrow" line out, giving them back one line in; paying a captain out
## of that escrow later is a note ([method note_held]), not a second spend.

## A new entry or a merge.
signal recorded

const MAX_ENTRIES := 400
## How far back a change looks for an entry to join.
const MERGE_LOOKBACK := 12
const MERGE_SHORT := 3.0
const MERGE_LONG := 60.0

const FACTORY := "Factory sales"
const GRANT := "Grant"
const FEES := "Fees"
const DISCOVERY := "Discovery"
const SALVAGE := "Salvage"
const REPAIRS := "Repairs"
const SHIP_SALES := "Ship sales"
const OUTFITTER := "Outfitter"
const RESEARCH_REFUND := "Research refund"
const CONTRACT_PAY := "Contract pay"
const BOUNTIES := "Bounties"
const ESCROW := "Escrow"
const HIRES := "Hires"
const SHIPS := "Ships"
const BUILDINGS := "Buildings"
const RESEARCH := "Research"
const ZONES := "Zones"
const UPKEEP := "Upkeep"
const OTHER := "Other"
## Every category, in the order the breakdown lists them.
const CATEGORIES: PackedStringArray = [FACTORY, GRANT, FEES, DISCOVERY, SALVAGE, REPAIRS, SHIP_SALES, OUTFITTER,
		RESEARCH_REFUND, CONTRACT_PAY, BOUNTIES, ESCROW, HIRES, SHIPS, BUILDINGS, RESEARCH, ZONES, UPKEEP, OTHER]
## Categories merged over a minute (steady trickles).
const LONG_MERGE: PackedStringArray = [FACTORY, FEES, GRANT, UPKEEP, REPAIRS, OTHER]

## Oldest first.
var entries: Array[Dictionary] = []
## Sum of the amounts of the entries dropped off the front.
var dropped_sum: int = 0


func clear() -> void:
	entries.clear()
	dropped_sum = 0
	recorded.emit()


## Seconds within which [param category] entries with the same label merge.
static func merge_window(category: String) -> float:
	return MERGE_LONG if LONG_MERGE.has(category) else MERGE_SHORT


## One credit change of [param amount] (non-zero) leaving [param balance].
func record(amount: int, category: String, label: String, balance: int, sys: StringName = &"") -> void:
	if amount == 0:
		return
	_add(amount, 0, category, label, balance, sys)


## Credits paid out of an escrow reserved earlier: a note line, the credits
## left when it was reserved ([param held] is shown, amt stays 0).
func note_held(held: int, category: String, label: String, balance: int, sys: StringName = &"") -> void:
	if held <= 0:
		return
	_add(0, held, category, label, balance, sys)


func _add(amount: int, held: int, category: String, label: String, balance: int, sys: StringName) -> void:
	var now := SimClock.time
	var cat := category if not category.is_empty() else OTHER
	var text := label if not label.is_empty() else cat
	var window := merge_window(cat)
	for i in range(entries.size() - 1, maxi(entries.size() - MERGE_LOOKBACK, 0) - 1, -1):
		var e := entries[i]
		if now - float(e["t0"]) > window:
			break
		if e["cat"] != cat or e["label"] != text or signi(int(e["amt"])) != signi(amount) or (held > 0) != (int(e.get("held", 0)) > 0):
			continue
		e["amt"] = int(e["amt"]) + amount
		if held > 0:
			e["held"] = int(e.get("held", 0)) + held
		e["bal"] = balance
		e["t"] = now
		e["n"] = int(e.get("n", 1)) + 1
		if i != entries.size() - 1:
			entries.remove_at(i)
			entries.append(e)
		recorded.emit()
		return
	var d := {"t": now, "t0": now, "amt": amount, "cat": cat, "label": text, "bal": balance, "n": 1}
	if held > 0:
		d["held"] = held
	if not sys.is_empty():
		d["sys"] = String(sys)
	entries.append(d)
	while entries.size() > MAX_ENTRIES:
		dropped_sum += int(entries[0]["amt"])
		entries.remove_at(0)
	recorded.emit()


## Sum of every change recorded (dropped ones included).
func total() -> int:
	var s := dropped_sum
	for e in entries:
		s += int(e["amt"])
	return s


## Credits in and out since sim time [param since]: {in, out (positive),
## cats: {category: [in, out]}}. Partly merged entries count by their last
## change time.
func summary(since: float) -> Dictionary:
	var total_in := 0
	var total_out := 0
	var cats := {}
	for i in range(entries.size() - 1, -1, -1):
		var e := entries[i]
		if float(e["t"]) < since:
			continue
		var a := int(e["amt"])
		if a == 0:
			continue
		var pair: Array = cats.get(e["cat"], [0, 0])
		if a > 0:
			total_in += a
			pair[0] += a
		else:
			total_out -= a
			pair[1] -= a
		cats[e["cat"]] = pair
	return {"in": total_in, "out": total_out, "cats": cats}


func save_state() -> Dictionary:
	return {"entries": entries.duplicate(true), "dropped_sum": dropped_sum}


## Old saves (no ledger): empty.
func load_state(d: Dictionary) -> void:
	entries.clear()
	for e: Variant in d.get("entries", []):
		if e is Dictionary:
			entries.append((e as Dictionary).duplicate())
	dropped_sum = int(d.get("dropped_sum", 0))
	recorded.emit()

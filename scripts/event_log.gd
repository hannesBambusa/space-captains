extends Node
## Autoload "EventLog". Game events for the HUD event feed ("Kenji Falk
## attacked at Talon Reach", "Scavenger destroyed by Ivo Rask (+150 cr)").
## Each entry keeps a node to focus (when it still exists) or a world
## position. Repeats of the same text within [member repeat_window] sim
## seconds are dropped so a running fight does not flood the feed.

signal posted(entry: Dictionary)

enum Kind { INFO, COMBAT, LOSS, THREAT, REWARD }

const MAX_ENTRIES := 60

@export var repeat_window: float = 20.0

## Newest last. {text, kind, time, target: WeakRef or null, position,
## faction: FactionDef id or &"" (the feed colours the line in its colour)}
var entries: Array[Dictionary] = []
var _last_by_text: Dictionary = {}


## [param key] groups repeats (defaults to the text): "attacked:Kenji Falk"
## keeps one "attacked" line per captain per window wherever the fight moves.
## [param faction] tags a line about a hostile faction (FactionDef id).
func post(text: String, kind: Kind = Kind.INFO, target: Node3D = null, position: Vector3 = Vector3.INF, key: String = "", faction: StringName = &"") -> void:
	var now := SimClock.time
	var k := text if key.is_empty() else key
	if _last_by_text.has(k) and now - float(_last_by_text[k]) < repeat_window:
		return
	_last_by_text[k] = now
	var pos := position
	if pos == Vector3.INF and is_instance_valid(target):
		pos = target.global_position
	var e := {"text": text, "kind": kind, "time": now, "target": weakref(target) if target else null, "position": pos, "faction": faction}
	entries.append(e)
	if entries.size() > MAX_ENTRIES:
		entries.remove_at(0)
	posted.emit(e)


## Entries whose text contains [param part] (tests).
func find(part: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in entries:
		if String(e["text"]).contains(part):
			out.append(e)
	return out



# --- Save ---------------------------------------------------------------------

func reset() -> void:
	entries.clear()
	_last_by_text.clear()


## Text, kind, time and place of each entry (the focus node is not kept: a
## loaded entry focuses its position).
func save_state() -> Array:
	var out := []
	for e in entries:
		out.append({"text": e["text"], "kind": e["kind"], "time": e["time"], "position": e["position"], "faction": String(e.get("faction", &""))})
	return out


func load_state(list: Array) -> void:
	reset()
	for s: Dictionary in list:
		entries.append({"text": String(s["text"]), "kind": int(s["kind"]), "time": float(s["time"]), "target": null, "position": s["position"] as Vector3,
				"faction": StringName(s.get("faction", ""))})

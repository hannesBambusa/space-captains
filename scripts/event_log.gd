extends Node
## Autoload "EventLog". Game events for the HUD event feed ("Kenji Falk
## attacked at Talon Reach", "Scavenger destroyed by Ivo Rask (+150 cr)").
## Each entry keeps a node to focus (when it still exists) or a world
## position. Repeats of the same text within [member repeat_window] sim
## seconds are dropped so a running fight does not flood the feed.
## A line whose node is in another system than home is tagged with that
## system ("[Ostra] Raid incoming"), and its entry keeps the system id
## ("system") so the feed can show that system for a position-only entry.

signal posted(entry: Dictionary)

enum Kind { INFO, COMBAT, LOSS, THREAT, REWARD }

const MAX_ENTRIES := 60

@export var repeat_window: float = 20.0

## Newest last. {text, kind, time, target: WeakRef or null, position,
## faction: FactionDef id or &"" (the feed colours the line in its colour),
## system: the system id it is about (home when there is no node)}
var entries: Array[Dictionary] = []
var _last_by_text: Dictionary = {}


## [param key] groups repeats (defaults to the text): "attacked:Kenji Falk"
## keeps one "attacked" line per captain per window wherever the fight moves.
## [param faction] tags a line about a hostile faction (FactionDef id).
func post(text: String, kind: Kind = Kind.INFO, target: Node3D = null, position: Vector3 = Vector3.INF, key: String = "", faction: StringName = &"") -> void:
	# The rival corp's own news goes to its private intel, not the feed.
	var rid := _rival_of(target) if not public_next else &""
	if not rid.is_empty():
		var r := Corps.rival(rid)
		if r and r.mind:
			r.mind.note(text)
		return
	public_next = false
	var now := SimClock.time
	var k := text if key.is_empty() else key
	if _last_by_text.has(k) and now - float(_last_by_text[k]) < repeat_window:
		return
	_last_by_text[k] = now
	var pos := position
	if pos == Vector3.INF and is_instance_valid(target):
		pos = target.global_position
	var sys := system_of(target)
	if sys != ClusterNetwork.HOME_ID:
		text = "%s %s" % [tag(sys), text]
	var e := {"text": text, "kind": kind, "time": now, "target": weakref(target) if target else null, "position": pos, "faction": faction, "system": sys}
	entries.append(e)
	if entries.size() > MAX_ENTRIES:
		entries.remove_at(0)
	posted.emit(e)


## The next [method post] reaches the feed even when it is about the rival
## (RivalCorp's own announcements: first contact, war, treaties).
var public_next := false


## Posts [param text] to the feed even when [param target] is the rival's.
func post_public(text: String, kind: Kind = Kind.INFO, target: Node3D = null, key: String = "") -> void:
	public_next = true
	post(text, kind, target, Vector3.INF, key)
	public_next = false


## The rival a line is about, &"" for the player's feed: its own ships and
## structures, raiders in its system with no owner, or anything a rival's
## AI starts with no target (Corps.acting).
static func _rival_of(target: Node3D) -> StringName:
	if not Corps.has_rival():
		return &""
	if not is_instance_valid(target):
		return Corps.acting if Corps.is_rival(Corps.acting) else &""
	var o := Corps.owner_of(target)
	if Corps.is_rival(o):
		return o
	var c := Corps.corp_of_node(target)
	return c if o.is_empty() and Corps.is_rival(c) else &""


## The system [param n] is in (its viewport's SystemWorld), home without one.
static func system_of(n: Node) -> StringName:
	if not is_instance_valid(n) or not n.is_inside_tree():
		return ClusterNetwork.HOME_ID
	var vp := n.get_viewport()
	var w := vp.get_meta(SystemWorld.META) as SystemWorld if vp.has_meta(SystemWorld.META) else null
	return w.system_id if w and not w.system_id.is_empty() else ClusterNetwork.HOME_ID


## "[Ostra]" for a system other than home, "" for home.
static func tag(system_id: StringName) -> String:
	if system_id.is_empty() or system_id == ClusterNetwork.HOME_ID:
		return ""
	var def := Sector.system_def(system_id)
	return "[%s]" % (def.system_name if def else String(system_id))


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
		out.append({"text": e["text"], "kind": e["kind"], "time": e["time"], "position": e["position"], "faction": String(e.get("faction", &"")),
				"system": String(e.get("system", ClusterNetwork.HOME_ID))})
	return out


func load_state(list: Array) -> void:
	reset()
	for s: Dictionary in list:
		entries.append({"text": String(s["text"]), "kind": int(s["kind"]), "time": float(s["time"]), "target": null, "position": s["position"] as Vector3,
				"faction": StringName(s.get("faction", "")), "system": StringName(s.get("system", ClusterNetwork.HOME_ID))})

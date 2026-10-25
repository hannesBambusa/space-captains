class_name ColonyAlarm
extends Node
## The colony calls its mercenaries when something of the player's is shot:
## a structure (outposts, turrets, the shield generator, the station), the
## station shield bubble or a cargo shuttle. The mirror of
## ScavengerDen.call_defenders for the player's side.
##
## [method raise] starts (or extends) an alarm on the site for
## [constant ALARM_TIME] sim seconds after the last hostile hit. While it
## lasts, every [constant RECALL_INTERVAL] s, the mercenaries within
## [constant RESPONSE_RANGE] of the site that are free (docked, resting or
## on patrol, hull good enough: MercenaryBrain.answer_alarm) fly to it and
## fight its attackers; bounty hunters and escorts keep their job. One feed
## line per alarm says who answered. Not saved: an alarm is short and the
## next hit raises it again.

const GROUP := "colony_alarm"
const ALARM_TIME := 25.0
const RESPONSE_RANGE := 5000.0
const RECALL_INTERVAL := 5.0

## Site instance id -> {"site": WeakRef, "name": String, "until": float,
## "attacker": WeakRef, "recall_at": float, "answered": int, "noted": bool}
var alarms: Dictionary = {}


static func of(tree: SceneTree) -> ColonyAlarm:
	return tree.get_first_node_in_group(GROUP) as ColonyAlarm if tree else null


## [param site] was hit by [param attacker]: raise or extend its alarm.
static func raise(tree: SceneTree, site: Node3D, site_name: String, attacker: Node3D) -> void:
	var a := of(tree)
	if a == null or not is_instance_valid(site) or not is_instance_valid(attacker):
		return
	if not attacker.has_method(&"get_faction") or int(attacker.call(&"get_faction")) == Combat.Faction.PLAYER:
		return
	a._raise(site, site_name, attacker)


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(SimStepper.GROUP)


func _process(_delta: float) -> void:
	if not SimClock.paused:
		sim_step(0.0)


func _raise(site: Node3D, site_name: String, attacker: Node3D) -> void:
	var key := site.get_instance_id()
	var e: Dictionary = alarms.get(key, {})
	var fresh := e.is_empty()
	if fresh:
		e = {"site": weakref(site), "name": site_name, "recall_at": 0.0, "answered": 0, "noted": false}
	e["until"] = SimClock.time + ALARM_TIME
	e["attacker"] = weakref(attacker)
	alarms[key] = e
	if fresh:
		_call(e)


func sim_step(_dt: float) -> void:
	for key in alarms.keys():
		var e: Dictionary = alarms[key]
		var site := (e["site"] as WeakRef).get_ref() as Node3D
		if site == null or not site.is_inside_tree() or SimClock.time > float(e["until"]):
			alarms.erase(key)
			continue
		if SimClock.time >= float(e["recall_at"]):
			_call(e)


## Is there an alarm on [param site] now?
func is_alerted(site: Node3D) -> bool:
	return is_instance_valid(site) and alarms.has(site.get_instance_id())


## The latest attacker of [param site]'s alarm, or null.
func attacker_of(site: Node3D) -> Node3D:
	var e: Dictionary = alarms.get(site.get_instance_id(), {}) if is_instance_valid(site) else {}
	if e.is_empty():
		return null
	var a := (e["attacker"] as WeakRef).get_ref() as Node3D
	return a if Combat.is_live_target(a) else null


## Asks the free mercenaries in range to come; the first round posts the feed line.
func _call(e: Dictionary) -> void:
	e["recall_at"] = SimClock.time + RECALL_INTERVAL
	var site := (e["site"] as WeakRef).get_ref() as Node3D
	if site == null:
		return
	var attacker := (e["attacker"] as WeakRef).get_ref() as Node3D
	var names: PackedStringArray = []
	for n in get_tree().get_nodes_in_group(Ship.GROUP):
		var s := n as Ship
		var mb := s.brain as MercenaryBrain if s else null
		if mb == null or s.dead:
			continue
		var d := SpaceNav.flat_distance(s.global_position, site.global_position)
		if d > RESPONSE_RANGE:
			continue
		if mb.answer_alarm(site, String(e["name"]), attacker, float(e["until"]), d):
			names.append(s.captain.captain_name if s.captain else s.get_display_name())
	e["answered"] = int(e["answered"]) + names.size()
	if bool(e["noted"]):
		if not names.is_empty():
			EventLog.post("%s joined the defence of %s" % [", ".join(names), e["name"]], EventLog.Kind.COMBAT, site, Vector3.INF, "alarm_join:%d" % site.get_instance_id())
		return
	e["noted"] = true
	var who := "no mercenary free within %d km" % roundi(RESPONSE_RANGE / 1000.0)
	if not names.is_empty():
		who = "%s answering" % ", ".join(names)
	var title := String(e["name"])
	title = title.left(1).to_upper() + title.substr(1)
	EventLog.post("%s is under attack: %s" % [title, who],
			EventLog.Kind.THREAT, site, Vector3.INF, "alarm:%d" % site.get_instance_id())

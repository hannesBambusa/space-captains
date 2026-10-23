class_name Durability
extends RefCounted
## Hull and shields for anything that can be shot (ships, dens). Shields soak
## damage first and regenerate after [member shield_delay] sim seconds
## without a hit. Keeps a per-attacker damage tally (bounty splits) and the
## time of the last hit (threat assessment).

var max_hull: float = 100.0
var hull: float = 100.0
var max_shields: float = 0.0
var shields: float = 0.0
var shield_regen: float = 0.0
var shield_delay: float = 4.0
## SimClock.time of the last hit (-INF = never).
var last_hit_time: float = -INF
## Who hit it last (may be freed).
var last_attacker: WeakRef
## attacker instance id -> {"ref": WeakRef, "damage": float, "time": float}
var tally: Dictionary = {}


func _init(hull_points: float = 100.0, shield_points: float = 0.0, regen: float = 0.0) -> void:
	max_hull = maxf(hull_points, 1.0)
	hull = max_hull
	max_shields = maxf(shield_points, 0.0)
	shields = max_shields
	shield_regen = regen


func is_dead() -> bool:
	return hull <= 0.0


func fraction() -> float:
	return clampf(hull / max_hull, 0.0, 1.0)


func shield_fraction() -> float:
	return clampf(shields / max_shields, 0.0, 1.0) if max_shields > 0.0 else 0.0


## Applies [param amount]; returns the hull damage taken.
func apply(amount: float, attacker: Object) -> float:
	if is_dead() or amount <= 0.0:
		return 0.0
	last_hit_time = SimClock.time
	if attacker:
		last_attacker = weakref(attacker)
		var key := attacker.get_instance_id()
		var e: Dictionary = tally.get(key, {"ref": weakref(attacker), "damage": 0.0, "time": 0.0})
		e["damage"] = float(e["damage"]) + amount
		e["time"] = SimClock.time
		tally[key] = e
	var soak := minf(shields, amount)
	shields -= soak
	var rest := amount - soak
	hull = maxf(hull - rest, 0.0)
	return rest


func step(dt: float) -> void:
	if is_dead():
		return
	if shields < max_shields and SimClock.time - last_hit_time >= shield_delay:
		shields = minf(shields + shield_regen * dt, max_shields)


func repair(points: float) -> void:
	if not is_dead():
		hull = minf(hull + points, max_hull)


func restore_all() -> void:
	hull = max_hull
	shields = max_shields


func seconds_since_hit() -> float:
	return SimClock.time - last_hit_time


func get_last_attacker() -> Object:
	return last_attacker.get_ref() if last_attacker else null


## Attackers still alive that did damage in the last [param window] seconds.
func attackers(window: float = 60.0) -> Array[Object]:
	var out: Array[Object] = []
	for key in tally:
		var e: Dictionary = tally[key]
		var o: Object = (e["ref"] as WeakRef).get_ref()
		if o and SimClock.time - float(e["time"]) <= window:
			out.append(o)
	return out

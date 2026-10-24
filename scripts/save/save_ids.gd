class_name SaveIds
extends RefCounted
## Persistent ids for everything a save file links to (buildings, ships,
## captains, contracts, dens, scrap fields, fleets). Handed out on first use
## and kept in the object's meta, so the same object keeps its id across
## saves; a loaded object gets its saved id back ([method assign]). The
## counter itself is saved with the game ([member next]).

const META := &"save_id"

## Next id to hand out. Reset for a new game, restored on load.
static var next: int = 1


static func reset(start: int = 1) -> void:
	next = maxi(start, 1)


## The id of [param o] (assigned now when it has none). 0 for null.
static func of(o: Object) -> int:
	if o == null or not is_instance_valid(o):
		return 0
	if o.has_meta(META):
		return int(o.get_meta(META))
	var id := next
	next += 1
	o.set_meta(META, id)
	return id


## Gives a loaded object its saved id.
static func assign(o: Object, id: int) -> void:
	if o == null or id <= 0:
		return
	o.set_meta(META, id)
	next = maxi(next, id + 1)

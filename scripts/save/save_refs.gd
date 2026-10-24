class_name SaveRefs
extends RefCounted
## Id -> object lookup while a save is applied. Every restored object is
## registered under its saved id ([method add]); later parts of the load
## resolve links through [method find] (null when the object was not
## restored, e.g. a ship that was freed).

var _objects: Dictionary = {}


func add(id: int, o: Object) -> void:
	if id <= 0 or o == null:
		return
	_objects[id] = o
	SaveIds.assign(o, id)


func find(id: int) -> Object:
	var o: Variant = _objects.get(id)
	if o == null or not is_instance_valid(o):
		return null
	return o


func captain(id: int) -> Captain:
	return find(id) as Captain


func ship(id: int) -> Ship:
	return find(id) as Ship


func building(id: int) -> Building:
	return find(id) as Building


func node3d(id: int) -> Node3D:
	return find(id) as Node3D


## A WeakRef to the object with [param id], or to nothing when it is gone
## (callers expect a WeakRef, never null).
func weak(id: int) -> WeakRef:
	var o := find(id)
	return weakref(o) if o else SaveUtil.dead_ref()

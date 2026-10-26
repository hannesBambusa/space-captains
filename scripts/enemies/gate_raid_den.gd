class_name GateRaidDen
extends ScavengerDen
## The stand-in base of one gate raid (P4, [GateRaidSource]): raiders from
## a base in another system come out of a home jump gate. A child of the
## gate, it is the raiders' "den" for everything ScavengerShip and
## ScavengerBrain do with one (the mouth is the portal, so fleeing and
## returning raiders fly back into the gate), but it is no base of its own:
## no model, not in the base group (no bounties, markers, threat clock or
## den raids), not targetable, never spawns on its own. A raider that
## comes home ([method recall]) jumps out through the portal and counts
## back into its base in the source system ([method GateRaidSource.note_return]).

var gate: JumpGate
## The system and the base the raid came from.
var source_id: StringName = &""
## Raiders sent out, and how many jumped back.
var launched := 0
var returned := 0


## Call before adding it to [param g]. [param d]: the source base's def.
func setup_gate(d: DenDef, g: JumpGate, from_id: StringName) -> void:
	setup(d)
	gate = g
	source_id = from_id
	name = StringName(("GateRaid_%s" % d.name).validate_node_name().replace(" ", ""))


func _ready() -> void:
	# Only the raid's base: no model, groups, guns or launches of its own.
	_rng.seed = hash(def.name)
	durability = Durability.new(1.0, 0.0, 0.0)


func _process(_delta: float) -> void:
	pass


func sim_step(_dt: float) -> void:
	_prune()


func is_alive() -> bool:
	return not dead and is_instance_valid(gate)


func is_targetable() -> bool:
	return false


func is_raid_base() -> bool:
	return false


func take_hit(_amount: float, _attacker: Node3D, _at: Vector3) -> void:
	pass


func raise_alert() -> void:
	pass


func call_defenders() -> int:
	return 0


func get_display_name() -> String:
	return "%s, through %s" % [def.name, gate.def.name] if is_instance_valid(gate) and def else super.get_display_name()


func get_status_text() -> String:
	return "%d raiders out" % live_raiders().size()


func _near_cluster() -> AsteroidCluster:
	return null


func get_mouth_position() -> Vector3:
	return _spawn_point()


func _spawn_point() -> Vector3:
	return gate.portal_center() if is_instance_valid(gate) else global_position


## Out of the portal, on the plane.
func get_outward() -> Vector3:
	var a := gate.portal_axis() if is_instance_valid(gate) else Vector3.FORWARD
	a.y = 0.0
	return a.normalized() if a.length() > 0.01 else Vector3.FORWARD


## Raiders of this raid still flying.
func live_raiders() -> Array[ScavengerShip]:
	var out: Array[ScavengerShip] = []
	for s in raiders:
		if is_instance_valid(s) and not s.dead:
			out.append(s)
	return out


## A raider made it back to the gate: it jumps out.
func recall(s: ScavengerShip) -> void:
	if is_instance_valid(gate):
		WarpFx.flash(s, gate.portal_center(), gate.portal_radius * 0.6, gate.def.portal_color.lerp(Color.WHITE, 0.35), 1.1)
	returned += 1
	var src := CombatWorld.of(self).gate_raids if CombatWorld.of(self) else null
	if src:
		src.note_return(self, s)
	super.recall(s)

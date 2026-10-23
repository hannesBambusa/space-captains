class_name ScavengerShip
extends Ship
## A scavenger raider launched by a ScavengerDen. Hostile faction, junk
## cannons (scavenger default loadout), driven by a ScavengerBrain instead of
## a CaptainBrain: roam the den's belt, hunt miners, steal cargo, flee home
## when hurt, raid the colony when sent by the RaidDirector.

const MODEL_PATH := "res://assets/models/ships/scavenger.glb"

var den: ScavengerDen
var callsign: String = ""
var is_raider: bool = false
## Share of a miner's load aboard (stolen).
var loot: float = 0.0
var ai: ScavengerBrain
var attack_side: float = 1.0


func _init() -> void:
	role = Role.SCAVENGER
	faction = Combat.Faction.SCAVENGER
	hit_radius = 9.0


## Call before adding to the tree.
func setup_scavenger(from_den: ScavengerDen, call_sign: String, raider: bool) -> void:
	den = from_den
	callsign = call_sign
	is_raider = raider
	_model_path = MODEL_PATH
	name = StringName(("Scavenger_%s" % call_sign).validate_node_name().replace(" ", ""))


func _on_ready_ship() -> void:
	attack_side = 1.0 if randf() < 0.5 else -1.0
	ai = ScavengerBrain.new(self)
	set_meta(&"focus_distance", 170.0)


func sim_step(dt: float) -> void:
	if dead:
		return
	if ai:
		ai.update(dt)
	super.sim_step(dt)


func get_display_name() -> String:
	return "Scavenger %s" % callsign


func get_status_text() -> String:
	return ai.get_status_text() if ai else "Idle"


func _on_damaged(_amount: float, attacker: Node3D) -> void:
	if ai:
		ai.on_attacked(attacker)


func _on_destroyed(killer: Node3D) -> void:
	if is_instance_valid(den):
		den.forget(self)
	var k := killer as Ship
	if k and k.captain:
		k.captain.kills += 1
		k.captain.add_reputation(Reputation.KILL)
		var helpers := 0
		for o in durability.attackers(60.0):
			if o is Ship and o != k and (o as Ship).faction == Combat.Faction.PLAYER:
				helpers += 1
		k.captain.note_job(helpers > 0)
	var has_bounty := false
	for c in ContractBoard.get_for_target(self):
		if c is BountyContract:
			has_bounty = true
	if not has_bounty and k:
		EventLog.post("%s destroyed by %s" % [get_display_name(), k.get_display_name()], EventLog.Kind.REWARD, null, global_position)
	elif not has_bounty and killer is DefenseTurret:
		EventLog.post("%s shot down by %s" % [get_display_name(), (killer as DefenseTurret).get_display_name()], EventLog.Kind.REWARD, null, global_position)


## Docked at its den: leaves without an explosion.
func leave_map() -> void:
	if dead:
		return
	dead = true
	remove_from_group(GROUP)
	remove_from_group(Combat.GROUP)
	remove_from_group(RTSCamera.FOCUS_GROUP)
	queue_free()

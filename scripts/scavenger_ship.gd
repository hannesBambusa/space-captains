class_name ScavengerShip
extends Ship
## A hostile raider launched by a ScavengerDen: a scavenger, corsair or
## syndicate gunship, by its [FactionDef] (model, loadout, hit radius,
## behaviour). Driven by a ScavengerBrain instead of a CaptainBrain: roam the
## den's belt, hunt prey, steal cargo, flee home when hurt, raid the colony
## when sent by the RaidDirector.

const MODEL_PATH := FactionDef.SCAVENGER_SHIP_MODEL

var den: ScavengerDen
var faction_def: FactionDef
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


## Call before adding to the tree. [param fdef] null = the den's faction
## (the scavengers when the den is gone).
func setup_scavenger(from_den: ScavengerDen, call_sign: String, raider: bool, fdef: FactionDef = null) -> void:
	den = from_den
	callsign = call_sign
	is_raider = raider
	faction_def = fdef if fdef else (from_den.faction_def if is_instance_valid(from_den) else Factions.scavengers())
	_model_path = FactionDef.pick_model(faction_def.ship_model_path, MODEL_PATH)
	hit_radius = faction_def.hit_radius
	if faction_def.loadout:
		loadout = faction_def.loadout.duplicate(true) as ShipLoadout
	name = StringName(("%s_%s" % [faction_def.unit_name, call_sign]).validate_node_name().replace(" ", ""))


## Stand-in scavenger model: faction tint and scale.
func _prepare_model(model: Node3D) -> void:
	if _model_path == faction_def.ship_model_path:
		return
	ModelLoader.tint(model, faction_def.color, faction_def.fallback_tint)
	model.scale *= faction_def.ship_fallback_scale


func _on_ready_ship() -> void:
	attack_side = 1.0 if randf() < 0.5 else -1.0
	# No captain: the faction sets gunnery and evasion.
	if stats and faction_def:
		stats.accuracy = faction_def.ship_accuracy
		stats.dodge = faction_def.ship_dodge
	ai = ScavengerBrain.new(self)
	set_meta(&"focus_distance", 170.0)


func sim_step(dt: float) -> void:
	if dead:
		return
	if ai:
		ai.update(dt)
	super.sim_step(dt)


func get_display_name() -> String:
	return "%s %s" % [faction_def.unit_name if faction_def else "Scavenger", callsign]


func get_status_text() -> String:
	var warp := warp_status_text()
	if not warp.is_empty():
		return warp
	return ai.get_status_text() if ai else "Idle"


func can_warp() -> bool:
	return ai != null and ai.can_warp()


func cruise_free() -> bool:
	return ai != null and ai.cruise_free()


## Fleeing to the den (evasive dives under fire).
func is_fleeing() -> bool:
	return ai != null and ai.state == ScavengerBrain.State.FLEEING


## Raiders swoop on miners, salvagers and pods: short orbits, steep passes
## from above and below. Against guns they fly the default runs.
func attack_style(target: Node3D) -> AttackRun.Style:
	var st := AttackRun.Style.new()
	if target is MinerShip or target is EscapePod or target is SalvagerShip:
		st.tilt_deg = Vector2(30.0, 45.0)
		st.pass_height = 230.0
		st.pass_close = 0.3
		st.orbit_time = Vector2(3.0, 6.0)
		st.pass_chance = 0.85
	return st


func warp_drop_distance() -> float:
	return ai.warp_drop() if ai else SpaceNav.WARP_DROP


func warp_destination() -> String:
	return ai.destination_name() if ai else ""


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
		EventLog.post("%s destroyed by %s" % [get_display_name(), k.get_display_name()], EventLog.Kind.REWARD, null, global_position, "", faction_def.id)
	elif not has_bounty and killer is DefenseTurret:
		EventLog.post("%s shot down by %s" % [get_display_name(), (killer as DefenseTurret).get_display_name()], EventLog.Kind.REWARD, null, global_position, "", faction_def.id)


## Docked at its den: leaves without an explosion.
func leave_map() -> void:
	if dead:
		return
	dead = true
	remove_from_group(GROUP)
	remove_from_group(Combat.GROUP)
	remove_from_group(RTSCamera.FOCUS_GROUP)
	queue_free()

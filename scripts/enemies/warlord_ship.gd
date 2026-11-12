class_name WarlordShip
extends ScavengerShip
## A pirate warlord's flagship (see [WarlordDirector]): the faction's raider
## hull scaled up ([constant SCALE]) and tinted, with [constant HULL_MULT]
## times the hull, more shields and heavier guns. It flies as a raider at
## the colony (its ScavengerBrain); escorts guard it. Below
## [constant RETREAT_HULL] it breaks off: flies away from the station and
## warps out after [constant RETREAT_WARP] s ([method leaving]), so a
## driven-off warlord comes back later ([method WarlordDirector.on_escaped]).
## Destroyed, it pays out through [method WarlordDirector.on_killed].

const WARLORD_GROUP := "warlords"
const SCALE := 2.6
const TINT := Color(0.62, 0.1, 0.08)
const HULL_MULT := 14.0
const SHIELD_MIN := 900.0
const SHIELD_MULT := 6.0
const DAMAGE_MULT := 2.2
const FIRE_MULT := 1.4
const RANGE_MULT := 1.25
const SPEED_MULT := 0.85
## Hull share below which it breaks off.
const RETREAT_HULL := 0.3
## Sim seconds of the run before it may warp out.
const RETREAT_WARP := 8.0
## Gone when this far from the station or after this long, metres / sim s.
const RETREAT_GONE := 14000.0
const RETREAT_MAX := 45.0

var warlord_name: String = ""
var title: String = ""
## Visit number (1 = the first time this warlord came).
var visit: int = 1
## Breaking off: sim seconds since it started.
var retreat_time: float = -1.0


func setup_warlord(fdef: FactionDef, who: String, what: String, nth: int) -> void:
	setup_scavenger(null, who, true, fdef)
	warlord_name = who
	title = what
	visit = nth
	hit_radius = faction_def.hit_radius * SCALE
	name = StringName(("Warlord_%s" % who).validate_node_name().replace(" ", ""))


func _prepare_model(model: Node3D) -> void:
	ModelLoader.tint(model, TINT, 0.3)
	model.scale *= SCALE * (faction_def.ship_fallback_scale if _model_path != faction_def.ship_model_path else 1.0)
	# A red glow so the flagship reads as the boss from the RTS camera.
	var glow := OmniLight3D.new()
	glow.name = "WarlordGlow"
	glow.light_color = Color(1.0, 0.25, 0.15)
	glow.light_energy = 3.0
	glow.omni_range = hit_radius * 6.0
	glow.position = Vector3(0.0, hit_radius * 1.2, 0.0)
	model.add_child(glow)


func _on_ready_ship() -> void:
	super._on_ready_ship()
	add_to_group(WARLORD_GROUP)
	if stats:
		stats.weapon_damage *= DAMAGE_MULT
		stats.fire_rate *= FIRE_MULT
		stats.weapon_range *= RANGE_MULT
	durability.max_hull *= HULL_MULT
	durability.max_shields = maxf(durability.max_shields * SHIELD_MULT, SHIELD_MIN)
	durability.shield_regen = maxf(durability.shield_regen * 2.0, 25.0)
	durability.restore_all()
	max_speed *= SPEED_MULT
	mover.max_speed = max_speed
	set_meta(&"focus_distance", 420.0)


func get_display_name() -> String:
	return "Warlord %s" % warlord_name


func get_status_text() -> String:
	if leaving():
		return "Breaking off, warping out"
	return super.get_status_text()


func leaving() -> bool:
	return retreat_time >= 0.0


func can_warp() -> bool:
	if leaving():
		return retreat_time >= RETREAT_WARP
	return super.can_warp()


func cruise_free() -> bool:
	return false if leaving() else super.cruise_free()


func sim_step(dt: float) -> void:
	if dead:
		return
	if not leaving() and durability.fraction() < RETREAT_HULL:
		retreat_time = 0.0
		ai_driven = false
		EventLog.post("%s is breaking off: the flagship is badly hurt and turning for the edge of the system" % get_display_name(),
				EventLog.Kind.REWARD, self, Vector3.INF, "", faction_def.id)
	if leaving():
		_retreat_step(dt)
	super.sim_step(dt)


func _retreat_step(dt: float) -> void:
	retreat_time += dt
	var sys := SolarSystem.of(self)
	var home := sys.home_station.global_position if sys and is_instance_valid(sys.home_station) else Vector3.ZERO
	var away := global_position - home
	away.y = 0.0
	if away.length() < 1.0:
		away = Vector3.FORWARD
	var goal := home + away.normalized() * (RETREAT_GONE + 4000.0)
	set_world_goal(goal, Vector3.ZERO, Vector3.ZERO, 200.0, max_speed)
	if retreat_time >= RETREAT_MAX or global_position.distance_to(home) > RETREAT_GONE:
		var dir := WarlordDirector.of(self)
		if dir:
			dir.on_escaped(self)
		WarpFx.flash(self, global_position, 80.0)
		leave_map()


func _on_destroyed(killer: Node3D) -> void:
	super._on_destroyed(killer)
	var dir := WarlordDirector.of(self)
	if dir:
		dir.on_killed(self, killer)

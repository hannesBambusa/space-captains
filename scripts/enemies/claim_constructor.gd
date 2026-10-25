class_name ClaimConstructor
extends ScavengerShip
## The core of a faction's claim group (PlanetClaims re-claims): a slow,
## tough, unarmed ship (the garrison model folded small, in the faction
## colour) that flies to the claim site beside its planet and deploys a new
## garrison there over [constant DEPLOY_TIME] sim seconds, holding position
## with the planet. Shooting it down before that ends the re-claim. It flies
## itself ([member ScavengerShip.ai_driven] off); its escorts guard it
## (ScavengerBrain guard mode).

signal deploy_started(ship: ClaimConstructor)
signal deployed(ship: ClaimConstructor)

const SCALE := 0.24
const DEPLOY_TIME := 60.0
const ARRIVE_RADIUS := 70.0

var planet: PlanetBody
var site_angle: float = 0.0
var gang: String = ""
var deploying: bool = false
## 0..1 of the deployment.
var deploy_progress: float = 0.0


## Call before adding to the tree.
func setup_constructor(body: PlanetBody, angle: float, fdef: FactionDef, gang_name: String) -> void:
	setup_scavenger(null, "%s constructor" % gang_name, false, fdef)
	planet = body
	site_angle = angle
	gang = gang_name
	_model_path = ClaimGarrison.MODEL
	hit_radius = 16.0
	var lo := ShipLoadout.new()
	lo.role_name = "Constructor"
	lo.base_hull = fdef.constructor_hull
	lo.base_shields = fdef.constructor_shields
	lo.base_shield_regen = 6.0
	lo.base_speed = 85.0
	lo.base_acceleration = 16.0
	lo.base_turn_rate_deg = 45.0
	lo.base_sensor_range = 1500.0
	loadout = lo
	ai_driven = false
	name = StringName(("%s_Constructor_%s" % [gang_name, body.def.name]).validate_node_name().replace(" ", ""))


func _prepare_model(model: Node3D) -> void:
	model.scale *= SCALE
	ClaimGarrison.paint(model, faction_def.color)
	ModelLoader.dim_emission(model)


func _on_ready_ship() -> void:
	super._on_ready_ship()
	set_meta(&"focus_radius", 24.0)
	set_meta(&"focus_distance", 260.0)


func get_display_name() -> String:
	return "%s constructor" % gang


func get_status_text() -> String:
	if deploying:
		return "Deploying a garrison over %s, %d%%" % [_planet_name(), roundi(deploy_progress * 100.0)]
	return "Flying to %s to deploy a garrison" % _planet_name()


func can_warp() -> bool:
	return false


func cruise_free() -> bool:
	return false


## Where it deploys (world).
func site_position() -> Vector3:
	if not is_instance_valid(planet):
		return global_position
	return planet.to_global(ClaimGarrison.site_local(planet, site_angle))


func sim_step(dt: float) -> void:
	if dead:
		return
	if is_instance_valid(planet):
		_fly(dt)
	super.sim_step(dt)


func _fly(dt: float) -> void:
	var site := site_position()
	var vel := SpaceNav.world_velocity(planet)
	if not deploying:
		set_world_goal(site, vel, Vector3.ZERO, 30.0, max_speed)
		if global_position.distance_to(site) < ARRIVE_RADIUS:
			deploying = true
			deploy_started.emit(self)
		return
	set_world_goal(site, vel, Vector3.ZERO, 8.0, max_speed * 0.6)
	deploy_progress = minf(deploy_progress + dt / DEPLOY_TIME, 1.0)
	if deploy_progress >= 1.0:
		deployed.emit(self)


func _planet_name() -> String:
	return planet.def.name if is_instance_valid(planet) else "?"

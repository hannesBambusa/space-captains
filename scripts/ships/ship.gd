class_name Ship
extends Node3D
## Base for every ship: model, engine glow driven by thrust, banking, a
## [ShipMover] for flight, an optional [CaptainBrain], docking with its home
## building and small floating toasts.
##
## Frames: parked/docking ships are children of their home Building (so they
## ride its orbit); undocked ships fly under the world-space "Ships" node.
## All motion runs on sim time through [method sim_step]; _process feeds it
## the scaled frame delta (nothing moves while paused). Fast-forward tools call
## [method sim_step] directly for every node in [constant GROUP].
## Model convention: nose along -Z, child mesh "engine_glow" with flames on +Z,
## empties "muzzle_l" / "muzzle_r" for cannons.
##
## Stage 2: the hardware comes from a [ShipLoadout] (default per role) turned
## into [ShipStats] with the captain's attributes. Ships are combatants (see
## [Combat]): hull and shields ([Durability]), optional cannons
## ([ShipWeapon]), repair while docked, separation from nearby ships while in
## open space, and [method destroy] (explosion, scrap field, captain lost).
##
## Stage 3: the loadout's unlocked slots follow the captain's rank;
## [method refit] re-derives the stats after a module is installed. Back home
## after a trip ([method on_docked_home]) the captain counts a survived fight
## (Survivor, Shaken), then, while docked, may switch careers ([Career]) or
## shop at the Outfitter ([Outfitter]). A destroyed player ship may eject its
## captain in an [EscapePod] ([method eject_chance]); otherwise the captain is
## gone. Losses to scavengers give nearby wingmates a Grudge.
##
## Belt lanes: in open space ships leave the plane to clear asteroid belts
## ([method _update_altitude]). Before the route enters a belt band the ship
## climbs over it or dives under it (its lane, [method lane_sign], splits the
## traffic), and comes back down after the band. Near a goal that has its own
## height (a miner beside its rock) it takes that height; caught low inside
## a band it climbs straight out, riding with the rocks.

signal status_changed(ship: Ship)
signal damaged(ship: Ship, amount: float, attacker: Node3D)
signal destroyed(ship: Ship, killer: Node3D)

const GROUP := "ships"
const RENDER_LAYER := 2
const GLOW_NODE := "engine_glow"
## Largest sim step per update. Bigger frame deltas are split.
const MAX_STEP := 0.1
const MAX_SUBSTEPS := 40

enum Role { MINER, MERCENARY, SCAVENGER, SALVAGER, POD }

const ROLE_NAMES: PackedStringArray = ["Miner", "Mercenary", "Scavenger", "Salvager", "Pod"]
## Docked captains look in at the Outfitter this often, sim seconds.
const IDLE_VISIT_INTERVAL := 45.0
const TRAIT_INTERVAL := 2.0
## Other ships closer than this push apart while in open space, metres.
const SEPARATION_RADIUS := 48.0
const SEPARATION_SPEED := 45.0
const SEPARATION_INTERVAL := 0.25
## Flat distance to a goal with its own height at which the ship goes to
## that height, and at which it climbs back to its lane, metres.
const GOAL_HEIGHT_ENTER := 18.0
const GOAL_HEIGHT_EXIT := 45.0

@export var role: Role = Role.MINER
@export var max_speed: float = 150.0
@export var acceleration: float = 32.0
@export var turn_rate_deg: float = 110.0
@export var bank_max_deg: float = 28.0
@export var bob_height: float = 0.5
@export var bob_period: float = 5.0
@export var glow_pulse_speed: float = 2.2
## Engine flame length at idle / full thrust (multiplies the model's Z scale).
@export var glow_idle: float = 0.35
## Toasts are hidden when the camera is farther than this, metres.
@export var toast_max_distance: float = 2500.0
@export var glow_full: float = 1.5
## Hull repaired per sim second while docked, as a share of max hull.
@export var dock_repair_rate: float = 0.04
## Radius used for hits and picking, metres.
@export var hit_radius: float = 8.0

var captain: Captain
var brain: CaptainBrain
var mover: ShipMover
## Building this ship belongs to and docks at.
var home: Building
## Berth index at [member home].
var slot_index: int = 0
var faction: Combat.Faction = Combat.Faction.PLAYER
var loadout: ShipLoadout
var stats: ShipStats
var durability: Durability
## Null for unarmed ships.
var weapon: ShipWeapon
var dead: bool = false
## Lowest hull share since the last dock, and whether it was hit at all.
var trip_lowest_hull: float = 1.0
var trip_was_hit: bool = false

var _model: Node3D
var _model_path := ""
var _glow_mats: Array[StandardMaterial3D] = []
var _glow_base: Array[float] = []
var _glow_node: Node3D
var _glow_scale := Vector3.ONE
var _phase := 0.0
var _glow_level := 0.3
var _toast: Label3D
var _toast_until := 0.0
var _sep_timer := 0.0
var _visit_pending := false
var _visit_timer := 0.0
var _trait_timer := 0.0
var _lane := 1.0
var _at_goal_height := false


## Call before adding to the tree.
func setup_ship(ship_captain: Captain, model_path: String, home_building: Building, berth: int) -> void:
	captain = ship_captain
	home = home_building
	slot_index = berth
	_model_path = model_path
	captain.ship = self
	captain.stranded = false
	name = StringName(("%s_%s" % [captain.role, captain.captain_name]).validate_node_name().replace(" ", ""))


func _ready() -> void:
	add_to_group(GROUP)
	_phase = randf() * TAU
	add_to_group(Combat.GROUP)
	_sep_timer = randf() * SEPARATION_INTERVAL
	_lane = 1.0 if hash(String(name)) % 2 == 0 else -1.0
	if loadout == null:
		loadout = ShipLoadout.default_for(ROLE_NAMES[role])
	if captain and faction == Combat.Faction.PLAYER:
		loadout.unlocked_slots = Reputation.slots_for(captain.rank)
	stats = loadout.derive(captain)
	max_speed = stats.max_speed
	acceleration = stats.acceleration
	turn_rate_deg = stats.turn_rate_deg
	durability = Durability.new(stats.max_hull, stats.max_shields, stats.shield_regen)
	durability.shield_delay = stats.shield_delay
	mover = ShipMover.new(self)
	mover.max_speed = max_speed
	mover.acceleration = acceleration
	mover.turn_rate_deg = turn_rate_deg
	mover.bank_max_deg = bank_max_deg
	mover.yaw = rotation.y
	_model = ModelLoader.instantiate(_model_path, _fallback_model)
	_model.name = "Model"
	add_child(_model)
	MeshUtil.set_layers_recursive(_model, RENDER_LAYER)
	_collect_glow()
	if stats.has_weapon():
		weapon = ShipWeapon.new(self, stats, _model, Combat.HOSTILE_TRACER if faction == Combat.Faction.SCAVENGER else Combat.PLAYER_TRACER)
	set_meta(&"focus_radius", 14.0)
	set_meta(&"focus_distance", 150.0)
	add_to_group(RTSCamera.FOCUS_GROUP)
	brain = _make_brain()
	if brain:
		brain.decided.connect(_on_decided)
	_on_ready_ship()
	_apply_visuals(0.0)


func _process(delta: float) -> void:
	var dt := 0.0 if SimClock.paused else delta * SimClock.speed
	if dt > 0.0:
		var n := mini(ceili(dt / MAX_STEP), MAX_SUBSTEPS)
		var h := dt / float(n)
		for i in n:
			sim_step(h)
	_apply_visuals(dt)


## One simulation step of [param dt] sim seconds.
func sim_step(dt: float) -> void:
	if dead:
		return
	durability.step(dt)
	if weapon:
		weapon.step(dt)
	if is_docked():
		if durability.hull < durability.max_hull:
			durability.repair(durability.max_hull * dock_repair_rate * dt)
		durability.shields = durability.max_shields
	if brain:
		brain.update(dt)
	if dead:
		return
	if captain:
		_trait_timer -= dt
		if _trait_timer <= 0.0:
			_trait_timer = TRAIT_INTERVAL
			captain.update_traits()
		if is_docked() and _can_visit():
			_visit_timer -= dt
			if _visit_pending or _visit_timer <= 0.0:
				_visit_pending = false
				_visit_timer = IDLE_VISIT_INTERVAL
				if _visit_services():
					return
	_sep_timer -= dt
	if _sep_timer <= 0.0:
		_sep_timer = SEPARATION_INTERVAL
		_update_separation()
	_update_altitude()
	mover.step(dt)
	# Keep the heading current for aiming and formations during fast-forward
	# (the visual roll and bob are applied per frame in _apply_visuals).
	rotation.y = mover.yaw


func get_display_name() -> String:
	return captain.captain_name if captain else String(name)


func get_status_text() -> String:
	return brain.get_status_text() if brain else "Idle"


func is_docked() -> bool:
	return home != null and get_parent() == home


func get_role_name() -> String:
	return ROLE_NAMES[role]


func hull_fraction() -> float:
	return durability.fraction() if durability else 1.0


func shield_fraction() -> float:
	return durability.shield_fraction() if durability else 0.0


func is_hostile() -> bool:
	return faction != Combat.Faction.PLAYER


# --- Combatant API (see Combat) ---------------------------------------------

func get_faction() -> int:
	return faction


func is_alive() -> bool:
	return not dead


## Docked ships are safe inside their hangar.
func is_targetable() -> bool:
	return not dead and not is_docked() and is_inside_tree()


func get_hit_radius() -> float:
	return hit_radius


func get_aim_velocity() -> Vector3:
	return get_world_velocity()


func get_dodge() -> float:
	return stats.dodge if stats else 0.0


func take_hit(amount: float, attacker: Node3D, _at: Vector3) -> void:
	if dead:
		return
	durability.apply(amount, attacker)
	trip_was_hit = true
	trip_lowest_hull = minf(trip_lowest_hull, durability.fraction())
	damaged.emit(self, amount, attacker)
	_on_damaged(amount, attacker)
	if durability.is_dead():
		destroy(attacker)


## Blows the ship up: explosion, scrap field, events; then frees it.
func destroy(killer: Node3D = null) -> void:
	if dead:
		return
	dead = true
	var pos := global_position
	var world := CombatWorld.of(get_tree())
	if world:
		world.fx.explode(pos, 9.0)
		if _leaves_scrap():
			world.spawn_scrap(pos, world.ship_scrap, world.ship_scrap_life, 26.0, "%s wreck" % get_display_name())
	_on_destroyed(killer)
	destroyed.emit(self, killer)
	if world:
		world.notify_destroyed(self, killer)
	remove_from_group(GROUP)
	remove_from_group(Combat.GROUP)
	remove_from_group(RTSCamera.FOCUS_GROUP)
	queue_free()


## Re-derives the stats after a loadout change (module installed), keeping
## the hull and shield shares.
func refit() -> void:
	if loadout == null:
		return
	if captain and faction == Combat.Faction.PLAYER:
		loadout.unlocked_slots = Reputation.slots_for(captain.rank)
	var hf := durability.fraction() if durability else 1.0
	var sf := durability.shield_fraction() if durability else 1.0
	stats = loadout.derive(captain)
	max_speed = stats.max_speed
	acceleration = stats.acceleration
	turn_rate_deg = stats.turn_rate_deg
	if mover:
		mover.max_speed = max_speed
		mover.acceleration = acceleration
		mover.turn_rate_deg = turn_rate_deg
	if durability:
		durability.max_hull = maxf(stats.max_hull, 1.0)
		durability.hull = durability.max_hull * hf
		durability.max_shields = stats.max_shields
		durability.shields = stats.max_shields * sf
		durability.shield_regen = stats.shield_regen
	if weapon:
		weapon.stats = stats


## Chance this ship's captain ejects when it is destroyed.
func eject_chance() -> float:
	return captain.eject_chance(stats) if captain else 0.0


## Called by the brain when the ship is back in its berth after a trip.
func on_docked_home() -> void:
	if captain:
		captain.note_survived(trip_lowest_hull, trip_was_hit)
	trip_lowest_hull = 1.0
	trip_was_hit = false
	_visit_pending = true


## Leaves service without a fight (career switch): frees the berth and the
## contract, no explosion, no scrap.
func retire() -> void:
	if dead:
		return
	if brain:
		brain.on_ship_destroyed()
	dead = true
	if is_instance_valid(home):
		home.remove_ship(self)
	if captain and captain.ship == self:
		captain.ship = null
	remove_from_group(GROUP)
	remove_from_group(Combat.GROUP)
	remove_from_group(RTSCamera.FOCUS_GROUP)
	queue_free()


## Docked captains go shopping or change careers only when not mid-job.
func _can_visit() -> bool:
	if brain == null or faction != Combat.Faction.PLAYER:
		return false
	return brain.trip == null and (brain.state == CaptainBrain.State.RESTING or brain.state == CaptainBrain.State.DOCKED or brain.state == CaptainBrain.State.REPAIRING)


## Career switch first (it replaces this ship), then the Outfitter. True when
## this ship left service.
func _visit_services() -> bool:
	if Career.consider(self):
		return true
	var o := Outfitter.find(get_tree())
	if o:
		o.visit(self)
	return false


## Attack run on [param target]: close to cannon range, then circle it at
## about half range with the guns on it, firing when lined up. [param side]
## (+1 / -1) picks the circling direction. Only in open space.
func fight_step(target: Node3D, side: float = 1.0) -> void:
	var tp := target.global_position
	var my := global_position
	var to := Vector3(tp.x - my.x, 0.0, tp.z - my.z)
	var dist := to.length()
	var dir := to / maxf(dist, 0.1)
	var r := stats.weapon_range if weapon else 300.0
	var hr := float(target.call(&"get_hit_radius"))
	var keep := r * 0.5 + hr
	var tv := target.call(&"get_aim_velocity") as Vector3
	var goal: Vector3
	var face := Vector3.ZERO
	if dist > r * 0.9 + hr:
		goal = tp - dir * keep
		if dist < r * 1.6 + hr:
			face = to
	else:
		var tangent := dir.cross(Vector3.UP) * side
		goal = tp - dir * keep + tangent * keep * 0.7
		face = to
	set_world_goal(goal, tv, face, 18.0)
	if weapon:
		weapon.try_fire(target)


## Goal in world space (converted to the current parent frame).
func set_world_goal(pos: Vector3, vel: Vector3 = Vector3.ZERO, face: Vector3 = Vector3.ZERO, radius: float = 12.0, speed: float = -1.0) -> void:
	var p := get_parent() as Node3D
	var local := pos
	var lvel := vel
	if p:
		local = p.to_local(pos)
		lvel = p.global_basis.inverse() * (vel - SpaceNav.world_velocity(p))
		face = p.global_basis.inverse() * face
	local.y = 0.0
	mover.set_goal(local, lvel, speed, true, face, radius)
	mover.goal_has_altitude = false


## +1 = flies over belts, -1 = under. Stable per ship (name hash), so the
## traffic splits into two lanes.
func lane_sign() -> float:
	return _lane


## Sets the mover's height for this step (world frame only, see the class
## notes). Cheap: one ring test per belt.
func _update_altitude() -> void:
	mover.cruise_active = mover.avoid_enabled
	mover.hold_climb = false
	if not mover.avoid_enabled:
		_at_goal_height = false
		return
	var parent := get_parent() as Node3D
	var pos := global_position
	var goal := parent.to_global(mover.goal_pos) if parent else mover.goal_pos
	var goal_flat := Combat.flat_distance(pos, goal)
	if not mover.goal_has_altitude:
		_at_goal_height = false
	elif _at_goal_height:
		_at_goal_height = goal_flat < GOAL_HEIGHT_EXIT
	else:
		_at_goal_height = goal_flat < GOAL_HEIGHT_ENTER and mover.relative_speed() < 8.0
	if _at_goal_height:
		mover.cruise_y = mover.goal_y
		return
	var tree := get_tree()
	var need := SpaceNav.belt_lane_altitude(tree, pos, get_world_velocity(), goal, tan(deg_to_rad(mover.climb_angle_deg)))
	var band := SpaceNav.rock_band_at(tree, pos)
	var side := _lane
	if band:
		# Inside a band, stay on the side already reached (never cross the rocks).
		var layer := band.rock_layer_height()
		if absf(pos.y) >= layer:
			side = signf(pos.y)
		if absf(pos.y) < layer + 6.0:
			# Low among the rocks: climb (or dive) straight out with them.
			mover.hold_climb = true
			var v := SpaceNav.belt_point_velocity(band, pos)
			mover.hold_velocity = parent.global_basis.inverse() * (v - SpaceNav.world_velocity(parent)) if parent else v
	mover.cruise_y = side * need


func _update_separation() -> void:
	var sep := Vector3.ZERO
	if mover.avoid_enabled:
		var p := global_position
		var parent := get_parent()
		var key := separation_key()
		for n in get_tree().get_nodes_in_group(GROUP):
			if n == self or n.get_parent() != parent:
				continue
			if key != 0 and (n as Ship).separation_key() == key:
				continue
			var o := n as Node3D
			# 3D distance (ships in other belt lanes pass freely), pushed on the plane.
			var d := p - o.global_position
			var dist := d.length()
			if dist >= SEPARATION_RADIUS:
				continue
			d.y = 0.0
			var flat := d.length()
			if flat < 0.5:
				d = Vector3(randf() - 0.5, 0.0, randf() - 0.5)
				flat = d.length()
			sep += d / maxf(flat, 0.01) * (1.0 - dist / SEPARATION_RADIUS)
	mover.separation = sep.limit_length(1.0) * SEPARATION_SPEED


## World velocity, m/s.
func get_world_velocity() -> Vector3:
	var p := get_parent() as Node3D
	var v := mover.velocity + Vector3(0.0, mover.climb_rate, 0.0)
	if p == null:
		return v
	return p.global_basis * v + SpaceNav.world_velocity(p)


# --- Frames, docking ----------------------------------------------------------

func enter_space() -> void:
	mover.change_frame(SpaceNav.space_root(get_tree()), true)


func enter_home_frame() -> void:
	if home:
		mover.change_frame(home, false)


## Path from the berth out past the spawn point (home frame).
func start_undock() -> void:
	if home:
		mover.set_path(home.undock_path(slot_index))


## Path from the approach point into the berth (home frame).
func start_dock() -> void:
	if home:
		mover.set_path(home.dock_path(slot_index))


## Places the ship in its berth at once.
func snap_to_slot() -> void:
	if home == null:
		return
	if get_parent() != home:
		mover.change_frame(home, false)
	var berth := home.berth_transform(slot_index)
	position = berth.origin
	mover.velocity = Vector3.ZERO
	mover.yaw = ShipMover.yaw_for(-berth.basis.z)
	mover.hold()
	if brain:
		brain.on_snapped_to_berth()
	_apply_visuals(0.0)


# --- Toasts -------------------------------------------------------------------

## Small floating text above the ship, fades after a few sim seconds.
func show_toast(text: String, color: Color = Color(0.85, 0.9, 1.0)) -> void:
	if _toast == null:
		_toast = Label3D.new()
		_toast.name = "Toast"
		_toast.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_toast.fixed_size = true
		_toast.pixel_size = 0.0006
		_toast.font_size = 22
		_toast.outline_size = 6
		_toast.no_depth_test = true
		_toast.shaded = false
		_toast.render_priority = 12
		_toast.outline_render_priority = 11
		_toast.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_toast.offset = Vector2(0.0, 60.0 + 150.0 * float(slot_index % 4))
		_toast.position = Vector3(0.0, 6.0, 0.0)
		add_child(_toast)
	_toast.text = text
	_toast.modulate = Color(color, 0.95)
	_toast.outline_modulate = Color(0.0, 0.0, 0.0, 0.6)
	_toast.visible = true
	_toast_until = SimClock.time + 4.0


func _on_decided(_brain: CaptainBrain, accepted: bool, text: String) -> void:
	show_toast(text, Color(0.55, 0.9, 1.0) if accepted else Color(1.0, 0.6, 0.45))


# --- Hooks for subclasses -----------------------------------------------------

func _make_brain() -> CaptainBrain:
	return null


## Model used when [member _model_path] has no file.
func _fallback_model() -> Node3D:
	return ModelLoader.ship_placeholder()


## False for ships that leave no wreck (escape pods).
func _leaves_scrap() -> bool:
	return true


func _on_ready_ship() -> void:
	pass


## Took a hit (still alive or about to die).
func _on_damaged(_amount: float, _attacker: Node3D) -> void:
	pass


## Called once when destroyed, before the ship is freed. Player captains
## eject with [method eject_chance] (an escape pod flies them home) or are
## lost for good.
func _on_destroyed(killer: Node3D) -> void:
	if brain:
		brain.on_ship_destroyed()
	var ejected := faction == Combat.Faction.PLAYER and captain != null and randf() < eject_chance()
	if captain:
		if captain.ship == self:
			captain.ship = null
		if not ejected:
			captain.alive = false
	if is_instance_valid(home):
		home.remove_ship(self, ejected)
	if faction == Combat.Faction.PLAYER and captain:
		var by := ""
		if is_instance_valid(killer) and killer.has_method(&"get_display_name"):
			by = " (%s)" % String(killer.call(&"get_display_name"))
		if ejected:
			EventLog.post("%s ejected from a destroyed ship%s" % [captain.captain_name, by], EventLog.Kind.LOSS, null, global_position)
			_launch_pod()
		else:
			EventLog.post("%s was lost%s" % [captain.captain_name, by], EventLog.Kind.LOSS, null, global_position)
		if killer is ScavengerShip or killer is ScavengerDen:
			_spread_grudge()


func _launch_pod() -> void:
	captain.ejections += 1
	captain.add_reputation(Reputation.EJECTED)
	captain.add_trait(CaptainTraits.SURVIVOR)
	captain.add_history("Ejected from a destroyed %s" % ROLE_NAMES[role].to_lower())
	var pod := EscapePod.new()
	pod.setup_pod(captain, home if is_instance_valid(home) else null)
	var root := SpaceNav.space_root(get_tree())
	root.add_child(pod)
	# Same height: a pod launched in a belt lane starts clear of the rocks.
	pod.global_position = global_position
	pod.mover.yaw = mover.yaw
	pod.rotation.y = mover.yaw


## Wingmates (same home, or close by) take a loss to scavengers personally.
func _spread_grudge() -> void:
	var pos := global_position
	for n in get_tree().get_nodes_in_group(GROUP):
		var s := n as Ship
		if s == null or s == self or s.dead or s.faction != Combat.Faction.PLAYER or s.captain == null or s is EscapePod:
			continue
		if (is_instance_valid(home) and s.home == home) or Combat.flat_distance(pos, s.global_position) < CaptainTraits.GRUDGE_RADIUS:
			s.captain.add_trait(CaptainTraits.GRUDGE)


## Ships with the same non-zero key skip separation from each other
## (co-workers on spread-out spots, see SalvagerShip). 0 = always separate.
func separation_key() -> int:
	return 0


## Job hooks, called by CaptainBrain. A role implements what its work is.
## Prepares the work for [param trip] once in space. False = cannot (abort).
func job_begin(_trip: CaptainBrain.Trip) -> bool:
	return false


## Where to be for the job: {pos, vel, face} in world space; empty = gone.
## [param working] = holding position while doing the work.
func job_target(_trip: CaptainBrain.Trip, _working: bool) -> Dictionary:
	return {}


## Advances the work by [param dt]. True when done.
func job_work(_trip: CaptainBrain.Trip, _dt: float) -> bool:
	return true


## Work finished or aborted: release what job_begin claimed.
func job_end(_trip: CaptainBrain.Trip) -> void:
	pass


## Cargo handed over at home.
func on_cargo_delivered() -> void:
	pass


# --- Visuals ------------------------------------------------------------------

func _apply_visuals(_dt: float) -> void:
	var t := SimClock.time
	var w := TAU * t / bob_period + _phase
	var parked := is_docked() and mover.path_done() and mover.velocity.length() < 0.5
	rotation = Vector3(0.0, mover.yaw, 0.0)
	if _model:
		var sway := 1.0 if parked else 0.3
		_model.position.y = sin(w) * bob_height * sway
		_model.rotation = Vector3(mover.pitch + sin(w * 0.5) * 0.02 * sway, sin(w * 0.37) * 0.03 * sway, mover.bank + sin(w) * 0.03 * sway)
	var speed_part := clampf(mover.relative_speed() / maxf(max_speed, 1.0), 0.0, 1.0)
	var want := 0.12 if parked else maxf(mover.thrust, speed_part * 0.45) + 0.15
	_glow_level = lerpf(_glow_level, clampf(want, 0.0, 1.0), 0.15)
	_pulse_glow()
	if _toast and _toast.visible:
		var left := _toast_until - t
		var cam := get_viewport().get_camera_3d()
		var far := cam != null and cam.global_position.distance_to(global_position) > toast_max_distance
		if left <= 0.0:
			_toast.visible = false
		else:
			var a := 0.0 if far else clampf(left / 1.2, 0.0, 1.0)
			_toast.modulate.a = 0.95 * a
			_toast.outline_modulate.a = 0.6 * a


func _collect_glow() -> void:
	_glow_node = _model.find_child(GLOW_NODE, true, false) as Node3D
	if _glow_node == null:
		return
	_glow_scale = _glow_node.scale
	for mi in ModelLoader.meshes_of(_glow_node):
		for s in mi.get_surface_override_material_count():
			var src := mi.get_active_material(s) as StandardMaterial3D
			if src == null:
				continue
			var m := src.duplicate() as StandardMaterial3D
			m.emission_enabled = true
			if m.emission == Color.BLACK:
				m.emission = m.albedo_color
			mi.set_surface_override_material(s, m)
			_glow_mats.append(m)
			_glow_base.append(maxf(src.emission_energy_multiplier, 1.0))


func _pulse_glow() -> void:
	var k := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.001 * glow_pulse_speed * TAU * 0.5 + _phase)
	var lvl := _glow_level
	for i in _glow_mats.size():
		_glow_mats[i].emission_energy_multiplier = _glow_base[i] * k * lerpf(0.35, 0.9, lvl)
	if _glow_node:
		# The flame runs along local +Z; stretch it with thrust.
		var z := lerpf(glow_idle, glow_full, lvl) * (0.92 + 0.12 * k)
		_glow_node.scale = Vector3(_glow_scale.x, _glow_scale.y, _glow_scale.z * z)

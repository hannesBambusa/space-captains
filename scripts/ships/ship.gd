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
## ([ShipWeapon]), paid hull repair while docked ([RepairBay]: hull never
## regenerates in space, shields do), separation from nearby ships while in
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
## Cruise arcs: on travel legs (the brain says when, [method cruise_free])
## a ship does not fly the straight line from its start height to its
## goal's height (the plane for goals in a cluster) but an arc off it
## ([CruiseLeg]): its personality band ([method cruise_band]: Bold low and
## direct, Cautious far off the line) scaled by the leg length, above the
## line outbound and below it inbound (the highway rule, so opposing traffic
## passes at different heights). Fights, formations and docking fly
## straight at the goal's height.
## Cluster lanes: ships leave that height only when the way ahead crosses
## an asteroid cluster's footprint ([method _update_altitude]); the lane
## altitude wins over the arc unless the arc already clears the clump on the
## same side. Before the route enters a cluster the ship climbs over it or
## dives under it (its lane, [method lane_sign], splits the traffic), and
## comes back down after it; routes that miss every cluster fly level. Near a goal that has its own
## height (a miner beside its rock) it takes that height; caught low inside
## a band it climbs straight out, riding with the rocks.
##
## Warp hops (ShipMover): the ship tells its mover every step whether it may
## warp ([method can_warp], from the brain: never in combat), how far short
## to drop out ([method warp_drop_distance]) and whose hop to follow
## ([method warp_lead]: fleets, escorts). While spooling the hull shakes and
## the engines run hot; the jump, the light trail of the hop and the drop-in
## are [WarpVisuals]. The lane height of any cluster on the hop
## is held throughout; a hop with no band flies the straight 3D line from
## the (levelled) spool height to the arc's height at the drop-out point.
##
## 3D combat ([method fight_step], [AttackRun]): attack runs circle the
## target on a tilted plane, dive or climb through it and break off
## vertically, flavoured by personality ([method attack_style]) and spread
## out in fleets ([method attack_slot]). The fight sets the cruise height
## itself (belt lanes only while still closing in) and the mover flies
## [member ShipMover.agile]. The nose pitches toward the target while
## fighting (up to [constant AIM_PITCH_MAX_DEG], [method gun_forward]) and
## the guns fire along it. Fleeing under fire ([method is_fleeing]) the ship
## dives or climbs away from the nearest hostile's height to break the line.
##
## Gate trips ([method jump_to], [method start_transit]): a [GateTransit]
## takes over from the brain (flies to the gate, into the portal, leaves
## the world as a ShipCodec dict, comes out of the far gate) until it
## hands the ship back at home. A captain shot down outside home does not
## eject (no way home for a pod yet).

signal status_changed(ship: Ship)
signal damaged(ship: Ship, amount: float, attacker: Node3D)
signal destroyed(ship: Ship, killer: Node3D)

const GROUP := "ships"
const RENDER_LAYER := 2
const GLOW_NODE := "engine_glow"
## Toast colours: goods delivered (and escort pay), credits earned.
const TOAST_DELIVERY := Color(0.55, 1.0, 0.65)
const TOAST_REWARD := Color(1.0, 0.85, 0.4)
## Largest sim step per update. Bigger frame deltas are split.
const MAX_STEP := 0.1
const MAX_SUBSTEPS := 40

enum Role { MINER, MERCENARY, SCAVENGER, SALVAGER, POD, SHUTTLE, LANDER, EXPLORER, STATION }

const ROLE_NAMES: PackedStringArray = ["Miner", "Mercenary", "Scavenger", "Salvager", "Pod", "Cargo shuttle", "Lander", "Explorer", "Forward station"]
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
## A goal this far above or below the plane picks the belt lane on its side, metres.
const LANE_BASE_SIDE := 100.0
## Visual and gun pitch toward a target while fighting: limit, rate (degrees, degrees/s).
const AIM_PITCH_MAX_DEG := 35.0
const AIM_PITCH_RATE_DEG := 120.0
## Fleeing under fire: height off the line, how near a hostile must be, vertical ease (m, m, m/s).
const EVADE_HEIGHT := 170.0
const EVADE_RANGE := 900.0
const EVADE_EASE := 45.0

## Debug: fly the old flat attack runs and aim on the plane only (A/B tests).
static var flat_combat: bool = false

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
## Hull repaired per sim second while docked, as a share of max hull (paid,
## see RepairBay).
@export var dock_repair_rate: float = 0.04
## Radius used for hits and picking, metres.
@export var hit_radius: float = 8.0

var captain: Captain
var brain: CaptainBrain
var mover: ShipMover
## Gate trip in progress (null = the brain flies the ship).
var transit: GateTransit
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
## Docked and being repaired right now.
var repairing: bool = false
## Repair credits paid but not used yet, and paid this docking (RepairBay).
var repair_credit: float = 0.0
var repair_session_paid: int = 0
## Hull share when this repair session started paying (decision log).
var repair_from: float = 1.0

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
var _leg := CruiseLeg.new()
## Vertical speed of the last world goal (a climbing ward or fleet leader), m/s.
var _goal_vy := 0.0
var _goal_vy_at := -1.0
## 0..1, picks this ship's cruise height inside its band (stable per name).
var _cruise_roll := 0.5
var _warp_vis: WarpVisuals
var _run := AttackRun.new()
## Sim time of the last fight_step, the fight's height and target.
var _fight_at := -1.0
var _fight_y := 0.0
var _fight_close := false
var _fight_target: Node3D
## Nose pitch toward the target (radians) and how far it replaces the climb pitch (0..1).
var _aim_pitch := 0.0
var _aim_blend := 0.0
## Evasive height offset while fleeing: current and wanted (metres).
var _evade_y := 0.0
var _evade_want := 0.0


## Call before adding to the tree.
func setup_ship(ship_captain: Captain, model_path: String, home_building: Building, berth: int) -> void:
	captain = ship_captain
	home = home_building
	slot_index = berth
	_model_path = model_path
	captain.ship = self
	captain.stranded = false
	captain.away_slot = -1
	captain.away_in = ""
	name = StringName(("%s_%s" % [captain.role, captain.captain_name]).validate_node_name().replace(" ", ""))


func _ready() -> void:
	add_to_group(GROUP)
	_phase = randf() * TAU
	add_to_group(Combat.GROUP)
	_sep_timer = randf() * SEPARATION_INTERVAL
	_lane = 1.0 if hash(String(name)) % 2 == 0 else -1.0
	_cruise_roll = float(hash(String(name) + "/cruise") % 1000) / 999.0
	if loadout == null:
		loadout = ShipLoadout.default_for(ROLE_NAMES[role])
	if captain and faction == Combat.Faction.PLAYER:
		# The hull is what this ship is, whatever loadout it was handed.
		loadout.role_name = ROLE_NAMES[role]
		loadout.unlocked_slots = Reputation.slots_for(captain.rank)
	stats = loadout.derive(captain)
	if faction == Combat.Faction.PLAYER and not Research.tech_completed.is_connected(_on_research_done):
		Research.tech_completed.connect(_on_research_done)
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
	mover.warp_changed.connect(_on_warp_changed)
	_model = ModelLoader.instantiate(_model_path, _fallback_model)
	_model.name = "Model"
	add_child(_model)
	_prepare_model(_model)
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
			RepairBay.step(self, dt * work_speed())
		elif repairing:
			repairing = false
			RepairBay.end_session(self)
		durability.shields = durability.max_shields
	if transit:
		# The transit flies the ship; true = it placed the ship itself (or
		# the ship left the world through a portal).
		if transit.step(dt) or dead or not is_inside_tree():
			_update_aim(dt)
			return
	elif brain:
		brain.update(dt)
	if dead:
		return
	if captain and transit == null:
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
	_update_warp_policy()
	_update_altitude(dt)
	_update_aim(dt)
	mover.step(dt)
	# Keep the heading current for aiming and formations during fast-forward
	# (the visual roll and bob are applied per frame in _apply_visuals).
	rotation.y = mover.yaw


func get_display_name() -> String:
	return captain.captain_name if captain else String(name)


func get_status_text() -> String:
	if transit and mover.warp_state == ShipMover.Warp.IDLE:
		return transit.status_text()
	var warp := warp_status_text()
	if not warp.is_empty():
		return warp
	var text := brain.get_status_text() if brain else "Idle"
	if is_docked() and not repairing and RepairBay.needs_repair(self) and not RepairBay.can_afford(self):
		text += ", needs repairs"
	return text


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


# --- Warp ---------------------------------------------------------------------

## May the mover start (or follow) a warp hop now? Brains decide.
func can_warp() -> bool:
	if transit:
		return transit.can_warp()
	return brain != null and brain.can_warp()


## Drop-out distance before the destination, metres.
func warp_drop_distance() -> float:
	return brain.warp_drop() if brain else SpaceNav.WARP_DROP


## The mover whose hops this ship follows (formation), or null.
func warp_lead() -> ShipMover:
	if transit:
		return null
	return brain.warp_lead() if brain else null


## Where the ship is warping to, for the status line ("" = unknown).
func warp_destination() -> String:
	if transit:
		return transit.destination_name()
	return brain.destination_name() if brain else ""


## "Spooling warp to Cinder Cluster", "Warping to home"; "" when not warping.
func warp_status_text() -> String:
	if mover == null or mover.warp_state == ShipMover.Warp.IDLE:
		return ""
	var dest := warp_destination()
	var to := " to " + dest if not dest.is_empty() else ""
	return ("Warping" if mover.warp_state == ShipMover.Warp.WARP else "Spooling warp") + to


func _update_warp_policy() -> void:
	if not mover.avoid_enabled:
		mover.warp_allowed = false
		mover.warp_lead = null
		return
	mover.warp_allowed = can_warp()
	mover.warp_drop = warp_drop_distance()
	var lead := warp_lead()
	mover.warp_lead = lead if lead != mover else null


func _on_warp_changed(_m: ShipMover, state: ShipMover.Warp) -> void:
	if _warp_vis == null and state != ShipMover.Warp.IDLE and DisplayServer.get_name() != "headless":
		_warp_vis = WarpVisuals.new()
		var fac := Factions.of(self)
		_warp_vis.setup(self, _model, _glow_node, fac.light_color if fac else HudStyle.HOLO)
		add_child(_warp_vis)
	if _warp_vis:
		_warp_vis.on_warp_changed(state)
	status_changed.emit(self)


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


## The nearest live hostile to this ship within [param radius] (on the
## plane), or null (Combat.nearest_hostile).
func nearest_hostile(radius: float) -> Node3D:
	return Combat.nearest_hostile(self, global_position, radius, faction)


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


## Out of every list (ships, combatants, camera focus), then freed.
func _leave_world() -> void:
	remove_from_group(GROUP)
	remove_from_group(Combat.GROUP)
	remove_from_group(RTSCamera.FOCUS_GROUP)
	queue_free()


## Blows the ship up: explosion, scrap field, events; then frees it.
func destroy(killer: Node3D = null) -> void:
	if dead:
		return
	dead = true
	var pos := global_position
	var world := CombatWorld.of(self)
	if world:
		world.fx.explode(pos, 9.0)
		if _leaves_scrap():
			world.spawn_scrap(pos, world.ship_scrap, world.ship_scrap_life, 26.0, "%s wreck" % get_display_name(), self)
	_on_destroyed(killer)
	destroyed.emit(self, killer)
	if world:
		world.notify_destroyed(self, killer)
	_leave_world()


## Re-derives the stats after a loadout change (module installed), keeping
## the hull and shield shares.
func refit() -> void:
	if loadout == null:
		return
	if captain and faction == Combat.Faction.PLAYER:
		# The hull is what this ship is, whatever loadout it was handed.
		loadout.role_name = ROLE_NAMES[role]
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


## Techs that add a mercenary accuracy or miner hold apply at once.
func _on_research_done(t: TechDef) -> void:
	if t and (t.merc_accuracy != 0.0 or t.miner_hold != 0.0) and not dead:
		refit()


## Work timer speed (mining, salvage, dock repairs): slower while the
## home's forward station has no water (StationSupply.work_mult).
func work_speed() -> float:
	return StationSupply.work_mult(home if is_instance_valid(home) else self)


## Chance this ship's captain ejects when it is destroyed.
func eject_chance() -> float:
	var w := SystemWorld.of(self)
	if w and not w.has_station:
		return 0.0
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
	_leave_world()


## Walk to the station services on the next sim step while docked (or on
## the next docking): a Factory order is ready for pickup.
func request_visit() -> void:
	_visit_pending = true


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
	var o := Outfitter.find(self)
	if o:
		o.visit(self)
	return false


## Attack run on [param target] in 3D ([AttackRun]): close to cannon
## range, then circle it on a tilted plane, with dive and climb passes and
## vertical break-offs, firing whenever the guns bear. [param side]
## (+1 / -1) picks the circling direction. Only in open space.
func fight_step(target: Node3D, side: float = 1.0) -> void:
	if flat_combat:
		_fight_step_flat(target, side)
		return
	var tp := target.global_position
	var r := stats.weapon_range if weapon else 300.0
	var hr := float(target.call(&"get_hit_radius"))
	var tv := target.call(&"get_aim_velocity") as Vector3
	var now := SimClock.time
	if _run.target_id != target.get_instance_id():
		var slot := attack_slot()
		_run.begin(target, attack_style(target), hash(String(name)), slot.x, slot.y, now)
	_run.step(global_position, get_world_velocity(), tp, tv, r, hr, side, now)
	var face := Vector3.ZERO
	if _run.face:
		face = tp - global_position
		face.y = 0.0
	_fight_at = now
	_fight_y = _run.goal.y
	_fight_close = _run.close
	_fight_target = target
	set_world_goal(_run.goal, Vector3(tv.x, _run.goal_vy, tv.z), face, _run.radius)
	if weapon:
		weapon.try_fire(target)


## The old flat attack run (debug, [member flat_combat]): circle at about
## half range at the goal's height.
func _fight_step_flat(target: Node3D, side: float) -> void:
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


## How this pilot flies attack runs. Bold: steep planes, frequent close
## passes; Cautious: a wider orbit above the target, rare passes from
## above; Lazy: flat and seldom. Subclasses (raiders) override.
func attack_style(_target: Node3D) -> AttackRun.Style:
	var st := AttackRun.Style.new()
	if captain == null:
		return st
	match captain.personality:
		Captain.Personality.BOLD:
			st.tilt_deg = Vector2(35.0, 50.0)
			st.radius = 0.85
			st.pass_height = 240.0
			st.pass_close = 0.25
			st.orbit_time = Vector2(6.0, 10.0)
			st.pass_chance = 0.7
		Captain.Personality.CAUTIOUS:
			st.tilt_deg = Vector2(20.0, 30.0)
			st.radius = 1.2
			st.lift = 0.35
			st.pass_height = 170.0
			st.pass_close = 0.7
			st.orbit_time = Vector2(12.0, 20.0)
			st.pass_chance = 0.3
			st.pass_from = 1.0
		Captain.Personality.LAZY:
			st.tilt_deg = Vector2(20.0, 32.0)
			st.orbit_time = Vector2(12.0, 18.0)
			st.pass_chance = 0.35
	return st


## (slot, size) of this ship in its attack group (fleet wingmen spread out).
func attack_slot() -> Vector2i:
	return brain.attack_slot() if brain else Vector2i(0, 1)


## Running for safety (the brain says so; raiders override).
func is_fleeing() -> bool:
	return brain != null and brain.is_fleeing()


## Gun line in world space: the heading pitched by the nose pitch.
func gun_forward() -> Vector3:
	var p := nose_pitch()
	return global_basis * Vector3(0.0, sin(p), -cos(p))


## Nose pitch (radians, + = up): the climb pitch, or toward the target while fighting.
func nose_pitch() -> float:
	if mover == null:
		return 0.0
	return lerpf(mover.pitch, _aim_pitch, _aim_blend)


func _update_aim(dt: float) -> void:
	var fighting := _fight_at == SimClock.time and is_instance_valid(_fight_target)
	var want := 0.0
	if fighting:
		var d := _fight_target.global_position - global_position
		want = clampf(atan2(d.y, maxf(SpaceNav.flat_length(d), 1.0)), -deg_to_rad(AIM_PITCH_MAX_DEG), deg_to_rad(AIM_PITCH_MAX_DEG))
	_aim_pitch = move_toward(_aim_pitch, want if fighting else mover.pitch, deg_to_rad(AIM_PITCH_RATE_DEG) * dt)
	_aim_blend = move_toward(_aim_blend, 1.0 if fighting else 0.0, dt * 2.0)
	if not fighting:
		_fight_target = null


## Goal in world space (converted to the current parent frame). In open
## space its height is where the ship cruises to (see [method _update_altitude]);
## arrival is judged on the plane.
func set_world_goal(pos: Vector3, vel: Vector3 = Vector3.ZERO, face: Vector3 = Vector3.ZERO, radius: float = 12.0, speed: float = -1.0) -> void:
	var p := get_parent() as Node3D
	var local := pos
	var lvel := vel
	if p:
		local = p.to_local(pos)
		lvel = p.global_basis.inverse() * (vel - SpaceNav.world_velocity(p))
		face = p.global_basis.inverse() * face
	if not mover.avoid_enabled:
		local.y = 0.0
	mover.set_goal(local, lvel, speed, true, face, radius)
	mover.goal_has_altitude = false
	_goal_vy = vel.y
	_goal_vy_at = SimClock.time


## +1 = flies over clusters, -1 = under. Stable per ship (name hash), so the
## traffic splits into two lanes.
func lane_sign() -> float:
	return _lane


## Side (+1 over, -1 under) this ship approaches [param belt] from: the
## side its inclined orbit has lifted or sunk it to (the short way in), or
## this ship's lane for a cluster near the plane.
func cluster_side(belt: AsteroidCluster) -> float:
	var cy := belt.global_position.y
	return signf(cy) if absf(cy) > LANE_BASE_SIDE else lane_sign()


## Sets the mover's height for this step (world frame only, see the class
## notes). Cheap: one disc test per cluster.
func _update_altitude(dt: float) -> void:
	mover.cruise_active = mover.avoid_enabled
	mover.hold_climb = false
	mover.cruise_vy = 0.0
	var fighting := _fight_at == SimClock.time
	_evade_y = move_toward(_evade_y, _evade_want, EVADE_EASE * dt)
	mover.agile = mover.avoid_enabled and (fighting or _evade_want != 0.0)
	if not mover.avoid_enabled:
		_at_goal_height = false
		_leg.clear()
		return
	var parent := get_parent() as Node3D
	var pos := global_position
	var goal := parent.to_global(mover.goal_pos) if parent else mover.goal_pos
	# The goal's own height (the station complex on its planet's inclined
	# orbit, a den above the plane). Goals in a cluster (miners take their
	# rock's height only beside it): from outside, its lane height on the
	# side its orbit has lifted it to (the arc and a warp hop end there);
	# inside, the plane (the lane rule below holds the height).
	var goal_band := SpaceNav.rock_band_at(self, goal)
	var base := goal.y
	if goal_band:
		base = 0.0
		if SpaceNav.flat_distance(pos, goal_band.global_position) > SpaceNav.band_radius(goal_band):
			var cy := goal_band.global_position.y
			base = cluster_side(goal_band) * goal_band.lane_altitude()
	if fighting:
		# The attack run sets its own height (relative to the target).
		base = _fight_y
	_track_leg(pos, goal, dt)
	if mover.warp_state != ShipMover.Warp.IDLE:
		# Hold the hop's lane height; never cross back through the rocks.
		var y := position.y
		_at_goal_height = false
		mover.warp_exit_y = NAN
		if mover.warp_altitude > 0.0:
			mover.cruise_y = (signf(y) if absf(y) > 1.0 else lane_sign()) * mover.warp_altitude
		elif mover.warp_state == ShipMover.Warp.SPOOL:
			# No band on the hop: spool level.
			mover.cruise_y = y
		else:
			# In the hop: the mover flies the 3D line to the cruise height
			# at the drop-out point, then eases on from there.
			var end := mover.warp_end
			var rem := SpaceNav.flat_distance(end, goal)
			var exit_y := _leg.height(rem, base, goal) if _leg.active else base
			mover.warp_exit_y = exit_y
			mover.cruise_y = exit_y
		return
	var goal_flat := SpaceNav.flat_distance(pos, goal)
	if not mover.goal_has_altitude:
		_at_goal_height = false
	elif _at_goal_height:
		_at_goal_height = goal_flat < GOAL_HEIGHT_EXIT
	else:
		_at_goal_height = goal_flat < GOAL_HEIGHT_ENTER and mover.relative_speed() < 8.0
	if _at_goal_height:
		mover.cruise_y = mover.goal_y
		mover.y_peak = NAN
		return
	var cruise := base
	if _leg.active:
		cruise = _leg.height(goal_flat, base, goal)
		mover.y_peak = _leg.peak(base)
	else:
		mover.y_peak = NAN
		# Straight at the goal's height: follow its climb (formation slots,
		# the attack plane).
		if (fighting or base == goal.y) and _goal_vy_at == SimClock.time:
			mover.cruise_vy = _goal_vy
	if absf(_evade_y) > 0.5:
		cruise += _evade_y
	if fighting and _fight_close:
		# In the fight: its heights win over the belt lanes.
		mover.cruise_y = cruise
		return
	var need := SpaceNav.belt_lane_altitude(self, pos, get_world_velocity(), goal, tan(deg_to_rad(mover.climb_angle_deg)))
	if need <= 0.0:
		mover.cruise_y = cruise
		return
	var band := SpaceNav.rock_band_at(self, pos)
	if band == null and absf(cruise) >= need:
		# The cruise arc already clears the band ahead.
		mover.cruise_y = cruise
		return
	# Over or under a band: the side the goal (or the arc) lies on, else
	# this ship's lane.
	var side := lane_sign()
	if absf(base) > LANE_BASE_SIDE:
		side = signf(base)
	elif absf(cruise) > LANE_BASE_SIDE:
		side = signf(cruise)
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
	# The lane altitude wins, unless the arc is already higher on that side.
	mover.cruise_y = cruise if signf(cruise) == side and absf(cruise) > need else side * need


## Starts a new cruise leg when the goal changed (or the ship may now fly
## its own arc), or drops it when the brain wants direct flight (fights,
## formations).
func _track_leg(pos: Vector3, goal: Vector3, dt: float) -> void:
	var free := cruise_free()
	if not free:
		_leg.clear()
		return
	var gv := mover.goal_vel
	var p := get_parent() as Node3D
	if p:
		gv = p.global_basis * gv + SpaceNav.world_velocity(p)
	if not _leg.active or _leg.goal_jumped(goal, gv, dt):
		var leg_len := SpaceNav.flat_distance(pos, goal)
		var sys := SolarSystem.of(self)
		var st := sys.home_station.global_position if sys and sys.home_station else Vector3.INF
		_leg.begin(pos, goal, CruiseLeg.plan_offset(leg_len, cruise_band(), _cruise_roll, CruiseLeg.highway_sign(pos, goal, st)))


## May this ship fly its own cruise arc right now (travel legs), or must it
## fly straight at its goal (fights, formations, docking approaches)?
func cruise_free() -> bool:
	if transit:
		return transit.cruise_free()
	return brain != null and brain.cruise_free()


## Cruise arc size: x..y = height off the straight line in metres (this
## ship's roll picks a value), z = leg length at which it is reached in
## full (shorter legs scale it down). By personality: Bold flies low and
## direct, Cautious high above (or below) the traffic.
func cruise_band() -> Vector3:
	if captain == null:
		return Vector3(200.0, 700.0, 8000.0)
	match captain.personality:
		Captain.Personality.BOLD:
			return Vector3(150.0, 420.0, 8000.0)
		Captain.Personality.GREEDY:
			return Vector3(250.0, 650.0, 8000.0)
		Captain.Personality.LAZY:
			return Vector3(350.0, 850.0, 8000.0)
		Captain.Personality.CAUTIOUS:
			return Vector3(650.0, 1200.0, 8000.0)
	return Vector3(200.0, 700.0, 8000.0)


## The current leg's straight line height and the arc's offset from it
## (NAN when not on a cruise leg), for tools.
func cruise_line_y() -> float:
	return _leg.last_line_y if _leg.active else NAN


func _update_separation() -> void:
	_update_evade()
	var sep := Vector3.ZERO
	if mover.avoid_enabled:
		var p := global_position
		var parent := get_parent()
		var key := separation_key()
		for n in SystemWorld.nodes_in(self, GROUP):
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


## Fleeing under fire with a hostile near: dive or climb away from its
## height (kept until calm), else back onto the line.
func _update_evade() -> void:
	if flat_combat or not mover.avoid_enabled or not is_fleeing() or durability.seconds_since_hit() > 6.0:
		_evade_want = 0.0
		return
	var h := nearest_hostile(EVADE_RANGE)
	if h == null:
		_evade_want = 0.0
		return
	if _evade_want == 0.0:
		var dy := global_position.y - h.global_position.y
		_evade_want = (signf(dy) if absf(dy) > 20.0 else lane_sign()) * EVADE_HEIGHT


## World velocity, m/s.
func get_world_velocity() -> Vector3:
	var p := get_parent() as Node3D
	var v := mover.velocity + Vector3(0.0, mover.climb_rate, 0.0)
	if p == null:
		return v
	return p.global_basis * v + SpaceNav.world_velocity(p)


# --- Frames, docking ----------------------------------------------------------

## Starts a trip through [param gate] (a JumpGate in this ship's system):
## hired ships only. Null when the ship cannot go.
func jump_to(gate: JumpGate) -> GateTransit:
	if gate == null or gate.def == null:
		return null
	return start_transit(PackedStringArray([gate.def.name]))


## Starts a trip through the gates named in [param hops], one per system
## along the way, holding [param dwell] sim seconds in every system it
## passes through (see [GateTransit]).
func start_transit(hops: PackedStringArray, dwell: float = 0.0) -> GateTransit:
	return GateTransit.start(self, hops, dwell)


## Faces [param yaw] (the mover's heading and the node's).
func set_heading(yaw: float) -> void:
	mover.yaw = yaw
	rotation.y = yaw


## Puts the ship at [param pos] in the world frame, heading [param yaw] and
## moving at [param vel] (its climb rate from vel.y), holding its course.
func place_in_space(pos: Vector3, yaw: float, vel: Vector3) -> void:
	global_position = pos
	set_heading(yaw)
	mover.velocity = Vector3(vel.x, 0.0, vel.z)
	mover.climb_rate = vel.y
	mover.hold()


func enter_space() -> void:
	mover.change_frame(SpaceNav.space_root(self), true)


func enter_home_frame() -> void:
	if home:
		mover.change_frame(home, false)


## Path from the berth out past the spawn point (home frame).
func start_undock() -> void:
	repairing = false
	RepairBay.end_session(self)
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


## Hook right after the model is loaded, before its glow is collected.
func _prepare_model(_m: Node3D) -> void:
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
		var odds := "eject chance %d%% (Piloting %d%s%s)" % [roundi(eject_chance() * 100.0), captain.piloting,
				", escape gear +%d%%" % roundi(stats.eject_bonus * 100.0) if stats and stats.eject_bonus > 0.0 else "", ", Survivor +10%" if captain.has_trait(CaptainTraits.SURVIVOR) else ""]
		captain.flight_log.note(CaptainLog.Kind.LOSS, CaptainLog.Outcome.DID if ejected else CaptainLog.Outcome.FAILED,
				("Ejected from the destroyed ship%s" if ejected else "Lost with the ship%s") % by,
				("The pod made it out: " if ejected else "No way out: ") + odds, "Destroyed at %s" % SpaceNav.place_name(self, global_position))
		if ejected:
			EventLog.post("%s ejected from a destroyed ship%s" % [captain.captain_name, by], EventLog.Kind.LOSS, null, global_position)
			_launch_pod()
		else:
			EventLog.post("%s was lost%s" % [captain.captain_name, by], EventLog.Kind.LOSS, null, global_position)
		if killer is ScavengerShip or killer is ScavengerDen:
			_spread_grudge(Factions.of(killer))


func _launch_pod() -> void:
	captain.ejections += 1
	captain.add_reputation(Reputation.EJECTED)
	captain.add_trait(CaptainTraits.SURVIVOR, "Ejected from a destroyed ship and lived")
	captain.add_history("Ejected from a destroyed %s" % ROLE_NAMES[role].to_lower())
	var pod := EscapePod.new()
	pod.setup_pod(captain, home if is_instance_valid(home) else null)
	var root := SpaceNav.space_root(self)
	root.add_child(pod)
	# Same height: a pod launched in a belt lane starts clear of the rocks.
	pod.global_position = global_position
	pod.set_heading(mover.yaw)


## Wingmates (same home, or close by) take a loss to raiders personally.
func _spread_grudge(by: FactionDef) -> void:
	var pos := global_position
	for n in SystemWorld.nodes_in(self, GROUP):
		var s := n as Ship
		if s == null or s == self or s.dead or s.faction != Combat.Faction.PLAYER or s.captain == null or s is EscapePod:
			continue
		if (is_instance_valid(home) and s.home == home) or SpaceNav.flat_distance(pos, s.global_position) < CaptainTraits.GRUDGE_RADIUS:
			s.captain.add_trait(CaptainTraits.GRUDGE, "%s destroyed %s nearby" % [by.display_name if by else "Raiders", get_display_name()])


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

func _apply_visuals(dt: float) -> void:
	var t := SimClock.time
	var w := TAU * t / bob_period + _phase
	var parked := is_docked() and mover.path_done() and mover.velocity.length() < 0.5
	rotation = Vector3(0.0, mover.yaw, 0.0)
	if _model:
		var sway := 1.0 if parked else 0.3
		_model.position = Vector3(0.0, sin(w) * bob_height * sway, 0.0)
		_model.rotation = Vector3(nose_pitch() + sin(w * 0.5) * 0.02 * sway, sin(w * 0.37) * 0.03 * sway, mover.bank + sin(w) * 0.03 * sway)
	var speed_part := clampf(mover.relative_speed() / maxf(max_speed, 1.0), 0.0, 1.0)
	var want := 0.12 if parked else maxf(mover.thrust, speed_part * 0.45) + 0.15
	if mover.warp_state != ShipMover.Warp.IDLE:
		want = 1.0
		if mover.warp_state == ShipMover.Warp.SPOOL and _model:
			# Spool shake, growing as the drive charges.
			var k := 1.0 - clampf(mover.warp_timer / SpaceNav.WARP_SPOOL, 0.0, 1.0)
			var amp := 0.35 * (0.3 + k)
			_model.position.x = sin(t * 97.0 + _phase) * amp
			_model.position.z = cos(t * 91.0) * amp
	_glow_level = lerpf(_glow_level, clampf(want, 0.0, 1.0), 0.15)
	_pulse_glow()
	if _warp_vis:
		_warp_vis.update(dt)
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
	var boost := _warp_vis.glow_boost() if _warp_vis else 1.0
	for i in _glow_mats.size():
		_glow_mats[i].emission_energy_multiplier = _glow_base[i] * k * lerpf(0.35, 0.9, lvl) * boost
	if _glow_node:
		# The flame runs along local +Z; stretch it with thrust (and the warp drive's flare).
		var z := lerpf(glow_idle, glow_full, lvl) * (0.92 + 0.12 * k) * lerpf(1.0, boost, 0.35)
		_glow_node.scale = Vector3(_glow_scale.x, _glow_scale.y, _glow_scale.z * z)

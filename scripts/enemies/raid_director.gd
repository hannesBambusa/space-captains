class_name RaidDirector
extends Node
## Sends raids at the player's structures. The first comes after
## [member first_raid_time]; then one every [method interval] (+- jitter),
## from [member interval_range].x early down to .y as the pressure grows
## ([method pressure]: game time and colony size, captains plus structures).
## Waves grow with time and the colony ([method wave_size]); the first
## [member gentle_raids] raids are small (1, then 2 raiders).
## Raiders come from a living den, beyond its spawn cap.
##
## Each raid has an objective ([method pick_objective]): an outpost, the
## cargo shuttles of an outpost (raiders catch one in flight) or the
## station itself, by weight and faction (the Syndicate besieges the
## structures). [member warning_time] ahead a feed line and a toast say
## "Raid incoming from X toward Y"; then it launches. A den that dies
## meanwhile calls it off.
##
## Factions: a raid first picks a faction among those with a living base
## whose FactionDef.raid_after has passed, by FactionDef.raid_weight
## (no roll while only one qualifies, so the early game is the scavengers'
## alone), then one of its bases. A faction with a raid_size sends that
## many (Syndicate 3-5, rarer by weight; Corsairs a pair) instead of the
## growing wave, launched in its packs.
## Only bases that have arrived exist (ThreatDirector), so a faction raids
## once its first base is in; a base that just arrived waits
## SystemDef.arrival_raid_grace before it sends raiders.
##
## A forward station (F4, set up by CombatWorld): every clock reading is
## time since [member start_offset] (the founding: first raid, pressure,
## wave growth, FactionDef.raid_after), the first raid comes after the
## grace (first_raid_time set to CombatWorld.forward_raid_grace), and with a
## [member danger] above 0 the growing wave starts at [method danger_wave]
## instead of [member base_wave]. Only the system's own bases raid (no
## arrivals there, ThreatDirector.arrivals).

signal raid_warned(den: ScavengerDen, size: int, objective_name: String)
signal raid_started(den: ScavengerDen, size: int)

## Objective kinds.
enum Aim { NEAREST, STRUCTURE, SHUTTLES, STATION }

@export var enabled: bool = true
@export var first_raid_time: float = 480.0
## Seconds between raids at pressure 0 (x) and 1 (y).
@export var interval_range: Vector2 = Vector2(600.0, 360.0)
@export var raid_jitter: float = 40.0
## Warning lead before a raid launches, sim seconds.
@export var warning_time: float = 30.0
@export var base_wave: int = 1
## One raider more per this much sim time.
@export var growth_time: float = 1080.0
## One raider more per this many captains plus structures past [member colony_base].
@export var colony_step: int = 6
@export var colony_base: int = 4
@export var max_wave: int = 6
## The first raids are capped at 1, 2, ... raiders.
@export var gentle_raids: int = 2
## Pressure reaches 1 at this game time (half) and colony size (half).
@export var pressure_time: float = 2700.0
@export var pressure_colony: float = 20.0
## The station itself is only a raid objective after this many raids.
@export var station_after_raids: int = 2

## Sim time the clock counts from (0 at home, founded_at at a forward station).
@export var start_offset: float = 0.0
## The system's danger for the wave size (0 = home: [member base_wave]).
@export var danger: int = 0

var raids_sent: int = 0
var _next_raid: float = 0.0
var _rng := RandomNumberGenerator.new()
## The announced raid: den, size, objective, launch time (null den = none).
var pending_den: ScavengerDen
var pending_size: int = 0
var pending_aim: Aim = Aim.NEAREST
var pending_target: Node3D
var pending_at: float = 0.0


func _ready() -> void:
	add_to_group(SimStepper.GROUP)
	_rng.randomize()
	_next_raid = maxf(SimClock.time, start_offset) + first_raid_time


func _process(_delta: float) -> void:
	if not SimClock.paused:
		sim_step(0.0)


func sim_step(_dt: float) -> void:
	if not enabled:
		return
	if is_instance_valid(pending_den) or pending_size > 0:
		if SimClock.time >= pending_at:
			_launch_pending()
		return
	if SimClock.time < _next_raid:
		return
	_next_raid = SimClock.time + interval() + _rng.randf_range(-raid_jitter, raid_jitter)
	var mgr := BuildingManager.of(self)
	if mgr == null or mgr.buildings.is_empty():
		return
	var den := pick_den()
	if den:
		warn_raid(den, size_for(den))


# --- Pacing -------------------------------------------------------------------

## Living hired captains plus active structures.
func colony_size() -> int:
	var world := get_parent() as CombatWorld
	if world == null or world.threats == null:
		return 0
	return world.threats.hired_captains() + world.threats.active_structures()


## Sim seconds since [member start_offset] (the game, or the founding).
func elapsed() -> float:
	return maxf(SimClock.time - start_offset, 0.0)


## First wave of a forward system by its danger: 1 (danger 1-2), 2 (3-4), 3 (5).
func danger_wave() -> int:
	return base_wave if danger <= 0 else clampi(ceili(danger / 2.0), 1, 3)


## 0..1: half from game time, half from colony size.
func pressure() -> float:
	return clampf(0.5 * elapsed() / pressure_time, 0.0, 0.5) + clampf(0.5 * float(colony_size()) / pressure_colony, 0.0, 0.5)


## Seconds to the next raid now (before jitter).
func interval() -> float:
	return lerpf(interval_range.x, interval_range.y, pressure())


func wave_size() -> int:
	var first := danger_wave()
	var n := first + int(elapsed() / growth_time) + int(float(maxi(colony_size() - colony_base, 0)) / float(maxi(colony_step, 1)))
	if raids_sent < gentle_raids:
		n = mini(n, raids_sent + first)
	return clampi(n, 1, max_wave)


## Raid size from [param den]: its faction's range, else the growing wave.
func size_for(den: ScavengerDen) -> int:
	var r := den.faction_def.raid_size
	if r.x <= 0:
		return wave_size()
	return _rng.randi_range(r.x, maxi(r.y, r.x))


## Sim seconds until the next raid is announced (or launches, when announced).
func seconds_to_next() -> float:
	if pending_size > 0:
		return maxf(pending_at - SimClock.time, 0.0)
	return maxf(_next_raid - SimClock.time, 0.0)


## A living base to raid from (see the class notes), or null.
func pick_den() -> ScavengerDen:
	var by_faction: Dictionary = {}
	var order: Array[FactionDef] = []
	var sys := SolarSystem.of(self)
	var grace := sys.system_def.arrival_raid_grace if sys and sys.system_def else 0.0
	for n in SystemWorld.nodes_in(self, ScavengerDen.GROUP):
		var d := n as ScavengerDen
		if d == null or not d.is_alive() or not d.is_raid_base() or SimClock.time - d.arrived_at < grace:
			continue
		var f := d.faction_def
		if f.raid_weight <= 0.0 or elapsed() < f.raid_after:
			continue
		if not by_faction.has(f):
			by_faction[f] = [] as Array[ScavengerDen]
			order.append(f)
		(by_faction[f] as Array[ScavengerDen]).append(d)
	if order.is_empty():
		return null
	var pick := order[0]
	if order.size() > 1:
		var total := 0.0
		for f in order:
			total += f.raid_weight
		var roll := _rng.randf() * total
		for f in order:
			roll -= f.raid_weight
			pick = f
			if roll <= 0.0:
				break
	var live: Array[ScavengerDen] = by_faction[pick]
	return live[_rng.randi() % live.size()]


# --- Objectives ---------------------------------------------------------------

## {"aim": Aim, "target": Node3D (a Building, or the station hull)} for a
## raid from [param den]: outposts weigh 3 (Syndicate 4.5), the shuttles of
## an outpost that runs them 1.5 (Corsairs and Scavengers like cargo: x2
## while one is loaded in flight; never the Syndicate), the station 1 after
## [member station_after_raids] raids (Syndicate 2), turrets 1 for the
## Syndicate only. Disabled structures are skipped. [param rng]: the roll
## (default the director's own; gate raids bring theirs, GateRaidSource).
func pick_objective(den: ScavengerDen, rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = _rng
	var mgr := BuildingManager.of(self)
	var none := {"aim": Aim.NEAREST, "target": null}
	if mgr == null:
		return none
	var siege := den != null and den.faction_def.raid_style == FactionDef.RaidStyle.STRUCTURES
	var options: Array[Dictionary] = []
	for b in mgr.buildings:
		if not is_instance_valid(b) or not b.is_active() or b.def.station_addon or b.is_disabled():
			continue
		if b.get_hull():
			options.append({"aim": Aim.STRUCTURE, "target": b, "w": 4.5 if siege else 3.0})
		elif siege and b.get_service() is DefenseTurret:
			options.append({"aim": Aim.STRUCTURE, "target": b, "w": 1.0})
		var depot := b.get_cargo_depot()
		if depot and not siege and not depot.is_supply_only():
			var w := 1.5
			for s in depot.shuttles:
				if is_instance_valid(s) and s.is_carrying_cargo() and s.is_targetable():
					w = 3.0
			options.append({"aim": Aim.SHUTTLES, "target": b, "w": w})
	if mgr.station_hull and not mgr.station_hull.disabled and raids_sent >= station_after_raids:
		options.append({"aim": Aim.STATION, "target": mgr.station_hull, "w": 2.0 if siege else 1.0})
	if options.is_empty():
		return none
	var total := 0.0
	for o in options:
		total += float(o["w"])
	var roll := rng.randf() * total
	for o in options:
		roll -= float(o["w"])
		if roll <= 0.0:
			return o
	return options[options.size() - 1]


## "Mining Outpost 1", "the cargo shuttles of Mining Outpost 1", "the station".
static func objective_text(aim: Aim, target: Node3D) -> String:
	match aim:
		Aim.STRUCTURE:
			return (target as Building).display_name if target is Building else "the colony"
		Aim.SHUTTLES:
			return "the cargo shuttles of %s" % (target as Building).display_name if target is Building else "the cargo shuttles"
		Aim.STATION:
			return "the station"
	return "the colony"


# --- Raids --------------------------------------------------------------------

## Announces a raid of [param size] from [param den]; it launches
## [member warning_time] later ([method trigger_raid] sends one at once).
func warn_raid(den: ScavengerDen, size: int) -> void:
	var o := pick_objective(den)
	pending_den = den
	pending_size = size
	pending_aim = o["aim"]
	pending_target = o["target"]
	pending_at = SimClock.time + warning_time
	var f := den.faction_def
	var what := "%d %s" % [size, Fmt.plural(f.unit_name.to_lower()) if size != 1 else f.unit_name.to_lower()]
	var text := "Raid incoming from %s toward %s: %s, launching in %d s" % [den.get_display_name(), objective_text(pending_aim, pending_target), what, roundi(warning_time)]
	EventLog.post(text, EventLog.Kind.THREAT, den, Vector3.INF, "", f.id)
	_toast("Raid incoming toward %s" % objective_text(pending_aim, pending_target))
	Sfx.ui(&"alert")
	raid_warned.emit(den, size, objective_text(pending_aim, pending_target))


func _launch_pending() -> void:
	var den := pending_den
	var size := pending_size
	var aim := pending_aim
	var target := pending_target
	_clear_pending()
	if not is_instance_valid(den) or not den.is_alive():
		EventLog.post("The raid was called off: its base is gone", EventLog.Kind.INFO)
		return
	if aim != Aim.NEAREST and not is_instance_valid(target):
		var o := pick_objective(den)
		aim = o["aim"]
		target = o["target"]
	_send(den, size, aim, target)


func _clear_pending() -> void:
	pending_den = null
	pending_size = 0
	pending_aim = Aim.NEAREST
	pending_target = null


## Sends a raid of [param size] ships now (no warning). Returns the raiders.
func trigger_raid(size: int, from_den: ScavengerDen = null) -> Array[ScavengerShip]:
	var den := from_den
	if den == null:
		den = pick_den()
		if den == null:
			var none: Array[ScavengerShip] = []
			return none
	var o := pick_objective(den)
	return _send(den, size, o["aim"], o["target"])


func _send(den: ScavengerDen, size: int, aim: Aim, target: Node3D) -> Array[ScavengerShip]:
	var out: Array[ScavengerShip] = []
	var pack := den.faction_def.pack_size
	while out.size() < size:
		var group := den.spawn_pack(mini(pack, size - out.size()), true)
		if group.is_empty():
			break
		out.append_array(group)
	if out.is_empty():
		return out
	var objective := objective_node(aim, target)
	for s in out:
		if s.ai:
			s.ai.set_raid_objective(objective)
	raids_sent += 1
	raid_started.emit(den, out.size())
	EventLog.post("%s raid launched (%d from %s) toward %s" % [den.faction_def.unit_name, out.size(), den.get_display_name(), objective_text(aim, target)],
			EventLog.Kind.THREAT, out[0], Vector3.INF, "", den.faction_def.id)
	return out


## The node the raiders go for: the building, a loaded (else any) shuttle of
## it in flight (else the building), the station hull.
func objective_node(aim: Aim, target: Node3D) -> Node3D:
	if aim == Aim.SHUTTLES and target is Building:
		var depot := (target as Building).get_cargo_depot()
		var best: CargoShuttle = null
		if depot:
			for s in depot.shuttles:
				if is_instance_valid(s) and not s.dead and s.is_targetable():
					if best == null or (s.is_carrying_cargo() and not best.is_carrying_cargo()):
						best = s
		return best if best else target
	return target


func _toast(text: String) -> void:
	var pm := get_tree().root.get_node_or_null(^"PauseMenu")
	if pm and pm.has_method(&"toast"):
		pm.call(&"toast", text)


# --- Save ---------------------------------------------------------------------

func save_state() -> Dictionary:
	var d := {"enabled": enabled, "raids_sent": raids_sent, "next_raid": _next_raid, "rng": SaveUtil.rng_state(_rng),
			"start_offset": start_offset, "danger": danger}
	if pending_size > 0 and is_instance_valid(pending_den):
		d["pending"] = {"den": pending_den.def.name if pending_den.def else "", "size": pending_size, "aim": pending_aim, "at": pending_at,
				"target": -1 if pending_target is StructureHull else (SaveIds.of(pending_target) if is_instance_valid(pending_target) else 0)}
	return d


## After the dens and buildings are loaded ([param refs] finds the target).
func load_state(d: Dictionary, refs: SaveRefs = null) -> void:
	enabled = bool(d.get("enabled", enabled))
	raids_sent = int(d.get("raids_sent", 0))
	start_offset = float(d.get("start_offset", start_offset))
	danger = int(d.get("danger", danger))
	_next_raid = float(d.get("next_raid", _next_raid))
	SaveUtil.set_rng(_rng, d.get("rng", {}))
	_clear_pending()
	var p: Dictionary = d.get("pending", {})
	if p.is_empty():
		return
	var sys := SolarSystem.of(self)
	if sys:
		for den in sys.dens:
			if is_instance_valid(den) and den.def and den.def.name == String(p.get("den", "")):
				pending_den = den
	if pending_den == null:
		return
	pending_size = int(p.get("size", 1))
	pending_aim = int(p.get("aim", Aim.NEAREST)) as Aim
	pending_at = float(p.get("at", SimClock.time))
	var tid := int(p.get("target", 0))
	if tid == -1:
		var mgr := BuildingManager.of(self)
		pending_target = mgr.station_hull if mgr else null
	elif tid != 0 and refs:
		pending_target = refs.node3d(tid)

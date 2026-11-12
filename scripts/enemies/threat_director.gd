class_name ThreatDirector
extends Node
## Threat escalation: the game starts with the bases whose
## DenDef.arrival_order is 0 (the Rustjaw Hideout); the others arrive one
## at a time in arrival order. The next one comes when its
## DenDef.min_arrival_time of threat time has passed and the colony has
## grown (DenDef.growth_captains living hired captains and
## DenDef.growth_structures active structures), or anyway once threat time
## reaches min time times SystemDef.arrival_max_wait_mult, and never sooner
## than SystemDef.arrival_min_gap after the previous arrival.
## Threat time runs with the sim clock, faster (SystemDef.cleared_speedup)
## while every arrived base is destroyed, so clearing the map brings the
## next base a little sooner, never later. With SystemDef.crowd_bases or
## more bases standing it runs at SystemDef.crowd_slowdown and the min gap
## grows by SystemDef.crowd_gap_mult, so a crowded map fills up slower.
## An arrival is announced SystemDef.arrival_warning_time ahead: a "Long-range
## scans" event line and toast, and a DenArrivalSite (hologram, "Arriving"
## countdown on the map and overview). Then SolarSystem.arrive_den builds
## the base with its warp-in; a faction's first base posts its
## FactionDef.intro once.
## Planet claims (phase C3): a den with a DenDef.claim_planet first claims
## that world (PlanetClaims.claim: a garrison warps in over it)
## DenDef.claim_lead seconds before its own arrival would be due, so a new
## faction shows itself early; its intro posts then. The base itself comes
## at its usual time, at least half the claim lead after the claim.
## A forward station system has [member arrivals] off (F4): only the bases
## already there; the threat clock still runs.

signal changed

const MAX_WAIT_MULT_FALLBACK := 1.5

## Threat clock, sim seconds (see the class notes).
var threat_time: float = 0.0
## Arrived queue dens: DenDef.name -> SimClock.time of arrival.
var arrived: Dictionary = {}
## The den being announced (null = none) and when it arrives (SimClock.time).
var pending: DenDef
var pending_at: float = 0.0
## SimClock.time of the last arrival (min gap).
var last_arrival: float = -1.0e9
## Factions whose intro line was posted (FactionDef ids).
var introduced: Array[StringName] = []
## Dens whose planet claim was made: DenDef.name -> SimClock.time of the claim.
var claimed_for: Dictionary = {}
var site: DenArrivalSite
## New bases arrive (false in a forward station system).
var arrivals := true
## Hives the Swarm budded ([method bud_hive]): runtime DenDefs, saved as
## "extra_dens" and rebuilt from their template on load.
var extra_dens: Array[DenDef] = []
## The most Swarm hives standing at once.
const MAX_HIVES := 3
const HIVE_NUMERALS: PackedStringArray = ["II", "III", "IV", "V", "VI", "VII", "VIII"]

var _last_time: float = 0.0


func _ready() -> void:
	add_to_group(SimStepper.GROUP)
	_last_time = SimClock.time


func _process(_delta: float) -> void:
	if not SimClock.paused:
		sim_step(0.0)


## Steps on the clock's advance since the last call (from _process or SimStepper).
func sim_step(_dt: float) -> void:
	var dt := SimClock.time - _last_time
	_last_time = SimClock.time
	var sys := _system()
	if sys == null or dt <= 0.0:
		return
	var sd := sys.system_def
	var alive := _alive_bases(sys)
	var crowded := alive >= sd.crowd_bases
	var rate := 1.0 + sd.cleared_speedup if alive == 0 else (sd.crowd_slowdown if crowded else 1.0)
	threat_time += dt * rate * SectorModifier.num("threat")
	if not arrivals:
		return
	if pending:
		if SimClock.time >= pending_at:
			_arrive(sys)
		return
	var next := next_den()
	if next == null:
		return
	var lead := sd.arrival_warning_time
	if wants_claim(next):
		if _due(next, lead + next.claim_lead):
			_claim_first(sys, next)
		return
	if SimClock.time + lead - last_arrival < sd.arrival_min_gap * (sd.crowd_gap_mult if crowded else 1.0):
		return
	if claimed_for.has(next.name) and SimClock.time < float(claimed_for[next.name]) + next.claim_lead * 0.5:
		return
	if _due(next, lead):
		_warn(sys, next)


## Would [param d] be due [param ahead] sim seconds from now?
func _due(d: DenDef, ahead: float) -> bool:
	return threat_time + ahead >= max_time(d) or (threat_time + ahead >= d.min_arrival_time and growth_met(d))


## [param d] still has to make its planet claim.
func wants_claim(d: DenDef) -> bool:
	return not d.claim_planet.is_empty() and not claimed_for.has(d.name)


## The faction of [param d] claims its planet (see the class notes). A
## planet held already, or one that is missing, is skipped.
func _claim_first(sys: SolarSystem, d: DenDef) -> void:
	claimed_for[d.name] = SimClock.time
	var world := CombatWorld.of(self)
	var body := PlanetInfo.find_planet(self, d.claim_planet)
	if world == null or world.claims == null or body == null:
		return
	var f := d.get_faction()
	var outs := Outposts.of(get_tree())
	if outs and outs.claim_blocked(body, 3, d.gang):
		return
	var g := world.claims.claim(body, f, d.gang, true)
	if g == null:
		return
	EventLog.post("%s %s claimed %s: a garrison is in orbit, no outpost can be founded there" % [d.gang, f.display_name, body.def.name], EventLog.Kind.THREAT, g, Vector3.INF, "", f.id)
	if not introduced.has(f.id):
		introduced.append(f.id)
		if not f.intro.is_empty():
			EventLog.post(f.intro, EventLog.Kind.INFO, g, Vector3.INF, "", f.id)
		_toast("New faction: %s claimed %s" % [f.display_name, body.def.name])
	else:
		_toast("Faction claim: %s claimed %s" % [d.gang, body.def.name])
	changed.emit()


# --- Queries ------------------------------------------------------------------

## The next den to arrive (lowest arrival order not arrived yet), or null.
func next_den() -> DenDef:
	var sys := _system()
	if sys == null:
		return null
	var best: DenDef = null
	for d in sys.system_def.dens:
		if d.starts_present() or arrived.has(d.name) or d == pending:
			continue
		if best == null or d.arrival_order < best.arrival_order:
			best = d
	return best


## Threat time at which [param d] arrives regardless of growth.
func max_time(d: DenDef) -> float:
	var sys := _system()
	var mult := sys.system_def.arrival_max_wait_mult if sys else MAX_WAIT_MULT_FALLBACK
	return d.min_arrival_time * mult


func growth_met(d: DenDef) -> bool:
	return hired_captains() >= d.growth_captains and active_structures() >= d.growth_structures


## Living captains hired at the player's buildings.
func hired_captains() -> int:
	var mgr := BuildingManager.of(self)
	var n := 0
	if mgr:
		for b in mgr.buildings:
			if is_instance_valid(b):
				for c in b.captains:
					if c and c.alive:
						n += 1
	return n


func active_structures() -> int:
	var mgr := BuildingManager.of(self)
	var n := 0
	if mgr:
		for b in mgr.buildings:
			if is_instance_valid(b) and b.is_active():
				n += 1
	return n


## Vague hint for the overview: "Next: unknown signals, ~6 min" ("" while
## an arrival is announced or nothing is left to come).
func outlook_text() -> String:
	if pending or not arrivals:
		return ""
	var next := next_den()
	if next == null:
		return ""
	var target := next.min_arrival_time if growth_met(next) else max_time(next)
	var eta := maxf(target - threat_time, 0.0)
	var sys := _system()
	if sys:
		eta = maxf(eta, last_arrival + sys.system_def.arrival_min_gap - SimClock.time)
	if eta < 90.0:
		return "Next: unknown signals, soon"
	return "Next: unknown signals, ~%d min" % roundi(eta / 60.0)


# --- Arrival ------------------------------------------------------------------

func _warn(sys: SolarSystem, d: DenDef) -> void:
	pending = d
	pending_at = SimClock.time + sys.system_def.arrival_warning_time
	_make_site(sys)
	var f := d.get_faction()
	var text := "Long-range scans: %s ships gathering near %s" % [f.unit_name, d.belt_name]
	EventLog.post(text, EventLog.Kind.THREAT, site, Vector3.INF, "", f.id)
	_toast(text)
	changed.emit()


func _arrive(sys: SolarSystem) -> void:
	var d := pending
	pending = null
	if is_instance_valid(site):
		site.queue_free()
	site = null
	arrived[d.name] = SimClock.time
	last_arrival = SimClock.time
	var den := sys.arrive_den(d, true)
	var f := d.get_faction()
	EventLog.post("%s has arrived near %s" % [d.name, d.belt_name], EventLog.Kind.THREAT, den, Vector3.INF, "", f.id)
	if not introduced.has(f.id):
		introduced.append(f.id)
		if not f.intro.is_empty():
			EventLog.post(f.intro, EventLog.Kind.INFO, den, Vector3.INF, "", f.id)
			_toast("New faction: %s" % f.display_name)
	changed.emit()


func _make_site(sys: SolarSystem) -> void:
	site = DenArrivalSite.new()
	site.setup(pending, pending_at)
	site.position = sys.den_position(pending)
	site.rotation.y = sys.den_yaw(pending)
	sys.add_child(site)


func _all_cleared(sys: SolarSystem) -> bool:
	return _alive_bases(sys) == 0


## Raid bases standing in [param sys].
func _alive_bases(sys: SolarSystem) -> int:
	var n := 0
	for den in sys.dens:
		if is_instance_valid(den) and den.is_alive() and den.is_raid_base():
			n += 1
	return n


func _system() -> SolarSystem:
	return SolarSystem.of(self)


func _toast(text: String) -> void:
	var pm := get_tree().root.get_node_or_null(^"PauseMenu")
	if pm and pm.has_method(&"toast"):
		pm.call(&"toast", text)



# --- Swarm budding --------------------------------------------------------------

## A grown Swarm hive buds (ScavengerDen._swarm_step): a new hive warps in
## elsewhere in the system, while fewer than [constant MAX_HIVES] stand.
func bud_hive(parent: ScavengerDen) -> void:
	var sys := _system()
	if sys == null or parent == null or parent.def == null:
		return
	var alive := 0
	for den in sys.dens:
		if is_instance_valid(den) and den.is_alive() and den.faction_def and den.faction_def.id == ScavengerDen.SWARM_ID:
			alive += 1
	if alive >= MAX_HIVES:
		return
	var n := extra_dens.size() + 1
	var base := _template(sys, parent.def.name)
	if base == null:
		base = parent.def
	var anchor := clampf(base.anchor_radius + (5000.0 if n % 2 == 1 else -6000.0), 14000.0, 46000.0)
	var nd := _bud_def(base, "%s %s" % [base.name, HIVE_NUMERALS[mini(n - 1, HIVE_NUMERALS.size() - 1)]],
			fposmod(parent.def.angle_deg + 95.0 * float(n), 360.0), anchor)
	extra_dens.append(nd)
	arrived[nd.name] = SimClock.time
	var den := sys.arrive_den(nd, true)
	den.arrived_at = SimClock.time
	EventLog.post("The Swarm is spreading: %s budded a new hive, %s" % [parent.def.name, nd.name], EventLog.Kind.THREAT, den, Vector3.INF, "", ScavengerDen.SWARM_ID)
	_toast("Swarm hive budded: raid danger rising")
	changed.emit()


## A copy of [param base] as a budded hive at [param angle] / [param anchor].
func _bud_def(base: DenDef, hive_name: String, angle: float, anchor: float) -> DenDef:
	var d := base.duplicate() as DenDef
	d.name = hive_name
	d.belt_name = ""
	d.angle_deg = angle
	d.anchor_radius = anchor
	d.radial_offset = 0.0
	d.arrival_order = 99
	d.min_arrival_time = 0.0
	d.claim_planet = ""
	d.initial_spawns = 2
	return d


## The system's own den def a budded hive copies (by name; any Swarm one as a fallback).
func _template(sys: SolarSystem, base_name: String) -> DenDef:
	var any: DenDef = null
	for def in sys.system_def.dens:
		if def.get_faction() and def.get_faction().id == ScavengerDen.SWARM_ID:
			if def.name == base_name or base_name.begins_with(def.name):
				return def
			any = def
	return any


func _extra_out() -> Array:
	var out := []
	var sys := _system()
	for d in extra_dens:
		var base := _template(sys, d.name) if sys else null
		out.append({"name": d.name, "angle": d.angle_deg, "anchor": d.anchor_radius, "base": base.name if base else ""})
	return out

# --- Save ---------------------------------------------------------------------

func save_state() -> Dictionary:
	var intro := []
	for id in introduced:
		intro.append(String(id))
	return {"threat_time": threat_time, "arrived": arrived.duplicate(), "pending": pending.name if pending else "", "pending_at": pending_at,
			"last_arrival": last_arrival, "introduced": intro, "claimed_for": claimed_for.duplicate(), "arrivals": arrivals,
			"extra_dens": _extra_out()}


## Before the dens are loaded: builds the arrived dens (no warp-in; their
## state and ships come from the save) and the arrival site of a pending one.
func load_state(d: Dictionary) -> void:
	_last_time = SimClock.time
	arrivals = bool(d.get("arrivals", arrivals))
	threat_time = float(d.get("threat_time", SimClock.time))
	arrived = (d.get("arrived", {}) as Dictionary).duplicate()
	pending_at = float(d.get("pending_at", 0.0))
	last_arrival = float(d.get("last_arrival", -1.0e9))
	claimed_for = (d.get("claimed_for", {}) as Dictionary).duplicate()
	introduced.clear()
	for id in d.get("introduced", []):
		introduced.append(StringName(id))
	var sys := _system()
	if sys == null:
		return
	pending = null
	var pending_name := String(d.get("pending", ""))
	extra_dens.clear()
	for e: Dictionary in d.get("extra_dens", []):
		var base := _template(sys, String(e.get("base", "")))
		if base:
			extra_dens.append(_bud_def(base, String(e.get("name", "")), float(e.get("angle", 0.0)), float(e.get("anchor", 20000.0))))
	var all: Array[DenDef] = sys.system_def.dens.duplicate()
	all.append_array(extra_dens)
	for def in all:
		if arrived.has(def.name):
			var den := sys.arrive_den(def, false)
			den.arrived_at = float(arrived[def.name])
		elif def.name == pending_name:
			pending = def
	if pending:
		_make_site(sys)
	changed.emit()

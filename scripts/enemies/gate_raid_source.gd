class_name GateRaidSource
extends Node
## Gate raids (P4): hostile bases in dangerous systems near home send
## raids through the jump gates. Home only (CombatWorld.gate_raids, beside
## the RaidDirector; den raids go on as before).
##
## From [constant START_TIME] on, every [constant INTERVAL] (random in the
## range) it looks at the systems at most [constant MAX_JUMPS] jumps out
## with danger [constant MIN_DANGER] or more and a living base, and rolls
## each ([method chance]: by danger, less two jumps out). A hit forms a raid
## there: [method size_for] ships of one of its bases, out of the home gate
## on the way to that system, [constant LEAD] seconds later. The raiders
## come out of the portal (a [GateRaidDen] at the gate is their base),
## pick an objective like any raid (RaidDirector.pick_objective) and fight
## like normal raiders; hurt or done they fly back into the gate and jump
## out, counted back into their base over there.
##
## Warning: only when the source is scouted ([method is_scouted]: surveyed
## in the last [constant SCOUTED_TIME], or one of the player's ships is in
## it) a feed line, a toast and a THREATS row say "Raid forming in Ostra,
## through Ostra Gate in ~1 min" (also once scouting starts while it
## forms). Unscouted they just arrive.
##
## Rolls are seeded by the network seed and the check count (no RNG
## member: the smoke test's per-node seeding stays as it was). Saved with
## the system ("gate_raids", GameSnapshot): the clock, the forming raid,
## the raids in progress (their GateRaidDen, restored before the ships so
## the raiders find their base) and the tally.

signal changed

const START_TIME := 1800.0
const FIRST_JITTER := 180.0
## Sim seconds between checks.
const INTERVAL := Vector2(720.0, 1200.0)
## Forming time before the raiders come out, sim seconds.
const LEAD := Vector2(60.0, 90.0)
const SCOUTED_TIME := 900.0
const MIN_DANGER := 3
const MAX_JUMPS := 2
const FAR_FACTOR := 0.75

@export var enabled: bool = true

var next_check := START_TIME
var checks := 0
## The forming raid: {source, den, gate, size, at, warned}, empty = none.
var pending: Dictionary = {}
var dens: Array[GateRaidDen] = []
## Tally: raids, ships, warned, returned, killed; "log": one line per raid.
var stats := {"raids": 0, "ships": 0, "warned": 0, "returned": 0, "killed": 0, "log": []}


func _ready() -> void:
	add_to_group(SimStepper.GROUP)
	next_check = maxf(SimClock.time, START_TIME) + _rng_for(-1).randf_range(0.0, FIRST_JITTER)


func _process(_delta: float) -> void:
	if not SimClock.paused:
		sim_step(0.0)


func _rng_for(n: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:gate_raid:%d" % [Sector.get_seed(), n])
	return rng


func sim_step(_dt: float) -> void:
	_prune()
	if not enabled:
		return
	if not pending.is_empty():
		if not bool(pending.get("warned", false)) and is_scouted(StringName(pending["source"])):
			_warn()
		if SimClock.time >= float(pending["at"]):
			_launch()
		return
	if SimClock.time < next_check:
		return
	checks += 1
	var rng := _rng_for(checks)
	next_check = SimClock.time + rng.randf_range(INTERVAL.x, INTERVAL.y)
	var mgr := BuildingManager.of(self)
	if mgr == null or mgr.buildings.is_empty():
		return
	for c in candidates():
		if rng.randf() < chance(int(c["danger"]), int(c["jumps"])):
			form(StringName(c["id"]), rng)
			return


# --- Sources ----------------------------------------------------------------------

## Systems that can raid home now: [{id, danger, jumps, gate (the home
## gate they come out of), dens (living base names)}], by id.
func candidates() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if Sector.network == null:
		return out
	for id in Sector.network.remote_ids():
		var e := Sector.network.entry(id)
		if e == null or e.danger < MIN_DANGER:
			continue
		var path := Sector.network.path(ClusterNetwork.HOME_ID, id)
		var jumps := path.size() - 1
		if jumps < 1 or jumps > MAX_JUMPS:
			continue
		var alive := living_dens(id)
		if alive.is_empty():
			continue
		out.append({"id": id, "danger": e.danger, "jumps": jumps, "gate": Sector.gate_between(ClusterNetwork.HOME_ID, path[1]), "dens": alive})
	return out


## Chance per check that a system of [param danger] [param jumps] out raids.
static func chance(danger: int, jumps: int) -> float:
	return (0.4 + 0.15 * float(danger - MIN_DANGER)) * (1.0 if jumps <= 1 else FAR_FACTOR)


## Raiders per raid: more with danger (2 to 5), a faction's own raid size
## when it has one (the Syndicate).
static func size_for(danger: int, f: FactionDef, rng: RandomNumberGenerator) -> int:
	var n := clampi(danger - 1 + rng.randi_range(0, 1), 2, 5)
	if f and f.raid_size.x > 0:
		n = clampi(n, f.raid_size.x, maxi(f.raid_size.y, f.raid_size.x))
	return n


## Base names in [param id] still standing (as data: not marked dead; a
## base never visited stands).
func living_dens(id: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	var def := Sector.system_def(id)
	var st := Sector.state(id)
	if def == null or st == null:
		return out
	var vm := ViewManager.of(get_tree())
	var live := vm.world(id) if vm else null
	for dd in def.dens:
		if dd.get_faction() == null:
			continue
		if live and live.sys:
			var node := live.sys.den_of(dd)
			if node and not node.is_alive():
				continue
		var ds: Dictionary = st.dens.get(dd.name, {})
		if bool(ds.get("dead", false)):
			continue
		out.append(dd.name)
	return out


## Surveyed in the last [constant SCOUTED_TIME], or one of the player's
## ships is in it (or jumping there).
func is_scouted(id: StringName) -> bool:
	var st := Sector.state(id)
	if st == null:
		return false
	if st.known and st.last_seen >= 0.0 and SimClock.time - st.last_seen <= SCOUTED_TIME:
		return true
	if RemoteSim.has_player_ship(st):
		return true
	var vm := ViewManager.of(get_tree())
	var w := vm.world(id) if vm else null
	if w:
		for n in SystemWorld.nodes_in(w, Ship.GROUP):
			var s := n as Ship
			if s and not s.dead and s.faction == Combat.Faction.PLAYER:
				return true
	var sim := RemoteSim.of(get_tree())
	return sim != null and sim.player_ship_bound_for(id)


# --- Raids ------------------------------------------------------------------------

## A raid forms in [param id] (see the class notes). [param rng] null: a
## fixed roll (debug). [param lead] < 0: the usual forming time.
func form(id: StringName, rng: RandomNumberGenerator = null, lead: float = -1.0) -> bool:
	if rng == null:
		rng = _rng_for(10000 + checks)
	var c := {}
	for x in candidates():
		if x["id"] == id:
			c = x
	if c.is_empty():
		return false
	var names: PackedStringArray = c["dens"]
	var den_name := names[rng.randi() % names.size()]
	var dd := _den_def(id, den_name)
	pending = {"source": String(id), "den": den_name, "gate": String(c["gate"]), "size": size_for(int(c["danger"]), dd.get_faction(), rng),
			"at": SimClock.time + (lead if lead >= 0.0 else rng.randf_range(LEAD.x, LEAD.y)), "warned": false, "seed": rng.randi()}
	if is_scouted(id):
		_warn()
	changed.emit()
	return true


## "Raid forming in Ostra, through Ostra Gate in ~1 min" (the forming raid).
func warning_text() -> String:
	if pending.is_empty():
		return ""
	return "Raid forming in %s, through %s %s" % [_system_name(StringName(pending["source"])), String(pending["gate"]), eta_text()]


func eta_text() -> String:
	var left := maxf(float(pending.get("at", 0.0)) - SimClock.time, 0.0)
	return "in ~%d min" % maxi(roundi(left / 60.0), 1) if left >= 30.0 else "any moment"


## The forming raid is known to the player.
func is_warned() -> bool:
	return not pending.is_empty() and bool(pending.get("warned", false))


func _warn() -> void:
	pending["warned"] = true
	var dd := _den_def(StringName(pending["source"]), String(pending["den"]))
	var f := dd.get_faction() if dd else null
	var n := int(pending["size"])
	var what := "%d %s" % [n, (Fmt.plural(f.unit_name.to_lower()) if n != 1 else f.unit_name.to_lower()) if f else "raiders"]
	EventLog.post("%s: %s from %s" % [warning_text(), what, String(pending["den"])], EventLog.Kind.THREAT, home_gate(String(pending["gate"])), Vector3.INF, "",
			f.id if f else &"")
	_toast("Raid forming in %s, through %s" % [_system_name(StringName(pending["source"])), String(pending["gate"])])
	changed.emit()


func _launch() -> void:
	var p := pending
	pending = {}
	var id := StringName(p["source"])
	var gate := home_gate(String(p["gate"]))
	var dd := _den_def(id, String(p["den"]))
	if gate == null or dd == null or not living_dens(id).has(String(p["den"])):
		if bool(p.get("warned", false)):
			EventLog.post("The raid forming in %s broke up" % _system_name(id), EventLog.Kind.INFO)
		changed.emit()
		return
	var den := GateRaidDen.new()
	den.setup_gate(dd, gate, id)
	gate.add_child(den)
	dens.append(den)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p.get("seed", 0))
	var size := int(p["size"])
	var out: Array[ScavengerShip] = []
	while out.size() < size:
		var group := den.spawn_pack(mini(den.faction_def.pack_size, size - out.size()), true)
		if group.is_empty():
			break
		out.append_array(group)
	den.launched = out.size()
	var world := CombatWorld.of(self)
	var raids := world.raids if world else null
	var o := raids.pick_objective(den, rng) if raids else {"aim": RaidDirector.Aim.NEAREST, "target": null}
	var objective := raids.objective_node(o["aim"], o["target"]) if raids else null
	for s in out:
		if s.ai:
			s.ai.set_raid_objective(objective)
	WarpFx.flash(gate, gate.portal_center(), gate.portal_radius * 0.9, gate.def.portal_color.lerp(Color.WHITE, 0.35), 1.3)
	var f := den.faction_def
	var what := "%d %s" % [out.size(), Fmt.plural(f.unit_name.to_lower()) if out.size() != 1 else f.unit_name.to_lower()]
	var aim := RaidDirector.objective_text(o["aim"], o["target"])
	var warned := bool(p.get("warned", false))
	if warned:
		EventLog.post("Raid through %s: %s from %s in %s, toward %s" % [gate.def.name, what, dd.name, _system_name(id), aim],
				EventLog.Kind.THREAT, out[0] if not out.is_empty() else gate, Vector3.INF, "", f.id)
	else:
		EventLog.post("Unknown raiders came through %s: %s, toward %s" % [gate.def.name, what, aim], EventLog.Kind.THREAT,
				out[0] if not out.is_empty() else gate, Vector3.INF, "", f.id)
	_toast("Raiders through %s toward %s" % [gate.def.name, aim])
	stats["raids"] = int(stats["raids"]) + 1
	stats["ships"] = int(stats["ships"]) + out.size()
	if warned:
		stats["warned"] = int(stats["warned"]) + 1
	(stats["log"] as Array).append("%s %s x%d from %s%s" % [Fmt.clock(SimClock.time), gate.def.name, out.size(), _system_name(id), " (warned)" if warned else ""])
	changed.emit()


## A raider jumped back out: it counts into its base over there again
## (while the system is data; a live base keeps its own count), up to the
## base's spawn cap (a raid never left its count: a full base just takes
## it back into the hangar).
func note_return(den: GateRaidDen, _s: ScavengerShip) -> void:
	stats["returned"] = int(stats["returned"]) + 1
	var st := Sector.state(den.source_id)
	var ds: Dictionary = st.dens.get(den.def.name, {}) if st else {}
	if not ds.is_empty() and not bool(ds.get("dead", false)) and RemoteSim.den_out(st, ds) < den.def.spawn_cap:
		ds["pending"] = int(ds.get("pending", 0)) + 1
	EventLog.post("%s jumped back out through %s" % [_s.get_display_name() if is_instance_valid(_s) else "A raider", den.gate.def.name if is_instance_valid(den.gate) else "the gate"],
			EventLog.Kind.COMBAT, null, den.get_mouth_position())
	changed.emit()


## Raids with nobody left out: gone.
func _prune() -> void:
	for i in range(dens.size() - 1, -1, -1):
		var d := dens[i]
		if not is_instance_valid(d):
			dens.remove_at(i)
			continue
		if d.live_raiders().is_empty():
			stats["killed"] = int(stats["killed"]) + maxi(d.launched - d.returned, 0)
			dens.remove_at(i)
			d.dead = true
			d.queue_free()
			changed.emit()


func home_gate(gate_name: String) -> JumpGate:
	var sys := SolarSystem.of(self)
	if sys:
		for g in sys.gates:
			if is_instance_valid(g) and g.def and g.def.name == gate_name:
				return g
	return null


func _den_def(id: StringName, den_name: String) -> DenDef:
	var def := Sector.system_def(id)
	if def:
		for dd in def.dens:
			if dd.name == den_name:
				return dd
	return null


static func _system_name(id: StringName) -> String:
	var def := Sector.system_def(id)
	return def.system_name if def else String(id)


func _toast(text: String) -> void:
	var pm := get_tree().root.get_node_or_null(^"PauseMenu")
	if pm and pm.has_method(&"toast"):
		pm.call(&"toast", text)


## One line for tests and the smoke run.
func summary() -> String:
	var lg: Array = stats["log"]
	return "%d raids, %d ships (%d warned), %d jumped back, %d destroyed; next check %s%s%s" % [int(stats["raids"]), int(stats["ships"]),
			int(stats["warned"]), int(stats["returned"]), int(stats["killed"]), Fmt.clock(next_check),
			(", forming: " + warning_text()) if not pending.is_empty() else "", (": " + "; ".join(lg)) if not lg.is_empty() else ""]


# --- Save -----------------------------------------------------------------------

func save_state() -> Dictionary:
	var ds := []
	for d in dens:
		if is_instance_valid(d) and is_instance_valid(d.gate):
			ds.append({"id": SaveIds.of(d), "den": d.def.name, "gate": d.gate.def.name, "source": String(d.source_id), "launched": d.launched, "returned": d.returned})
	return {"enabled": enabled, "next": next_check, "checks": checks, "pending": pending.duplicate(), "dens": ds, "stats": stats.duplicate(true)}


## Before the ships: the raids' bases, so their raiders link to them
## ([param refs]); [method relink] after the ships.
func load_state(d: Dictionary, refs: SaveRefs) -> void:
	if d.is_empty():
		return
	enabled = bool(d.get("enabled", true))
	next_check = float(d.get("next", next_check))
	checks = int(d.get("checks", 0))
	pending = (d.get("pending", {}) as Dictionary).duplicate()
	var st: Dictionary = d.get("stats", {})
	for k in stats:
		if st.has(k):
			stats[k] = st[k]
	for x: Dictionary in d.get("dens", []):
		var id := StringName(x.get("source", ""))
		var gate := home_gate(String(x.get("gate", "")))
		var dd := _den_def(id, String(x.get("den", "")))
		if gate == null or dd == null:
			continue
		var den := GateRaidDen.new()
		den.setup_gate(dd, gate, id)
		den.launched = int(x.get("launched", 0))
		den.returned = int(x.get("returned", 0))
		gate.add_child(den)
		SaveIds.assign(den, int(x.get("id", 0)))
		if refs:
			refs.add(int(x.get("id", 0)), den)
		dens.append(den)


## The loaded raiders join their raid again.
func relink() -> void:
	for n in SystemWorld.nodes_in(self, Ship.GROUP):
		var s := n as ScavengerShip
		if s and s.den is GateRaidDen and not s.dead and not (s.den as GateRaidDen).raiders.has(s):
			(s.den as GateRaidDen).raiders.append(s)
	changed.emit()

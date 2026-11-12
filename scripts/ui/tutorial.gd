class_name Tutorial
extends Node
## The training card's steps, shown by the [TutorialCard]. Two modes:
## - [constant QUICK]: the short card a new game starts with (six steps:
##   Mining Outpost, miner, mining contract, first ore sale, mercenary,
##   defence zone), unless the player finished or skipped it once (that flag
##   lives in user://settings.cfg: [method runs_on_new_game]; the main menu
##   Settings has the "Tutorial" checkbox).
## - [constant ACADEMY]: the tutorial game, started from the main menu's
##   Tutorial button ([member academy_next], set by SaveManager.new_game).
##   Every part of the game in chapters ([method chapters]): command,
##   mining, defence, contracts, research, gear, exploration, planets,
##   expansion, rivals. No rivals; raids, base arrivals and gate raids stay
##   off until the defence chapter forces one small raid ([method _apply_safety]).
##   Each chapter tops the money and ore up to what it needs, once
##   ([member _topped]); the card's chapter list jumps anywhere (a jump
##   grants the research the chapter builds on), and any step can be skipped.
##   Finished or quit, the game goes on as a normal sandbox.
##
## A step ends on its own when the game shows it done: [method _is_met],
## checked every [constant CHECK_EVERY] real seconds and on the events the
## old card listened to; info steps (welcome, rivals) end on the card's
## Next button. A met step is latched ([member met]) and waits for SOLA to
## finish its line ([method _held], the card's voice) before it moves on,
## so the voice is never cut off; the card's Next skips the wait. Events a
## step counts that land while the step before it is still being read are
## kept ([member _ore_in], [member _tech_seen]). Saved in the game ([method save_state], GameSnapshot
## "tutorial"); a save without it loads with the tutorial off, one with
## only "step" is a quick card.

signal changed

const GROUP := "tutorial"
## Shared with the WindowMode autoload (fullscreen).
const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "tutorial"
const SETTINGS_KEY := "finished"

enum Mode { QUICK, ACADEMY }
const QUICK := Mode.QUICK
const ACADEMY := Mode.ACADEMY

const OFF := -1
const CHECK_EVERY := 0.5
## Camera travel (m) or zoom change (share) that counts as "looked around".
const CAMERA_MOVE := 250.0
const CAMERA_ZOOM := 0.3
## Camera turn (degrees) that counts too.
const CAMERA_TURN := 30.0

const MINING_ID := &"mining_outpost"
const MERC_ID := &"mercenary_outpost"

## Set by SaveManager.new_game(true) just before the game scene is built;
## the next Tutorial takes it (academy mode) and clears it.
static var academy_next := false
## False in tests: [method set_runs_on_new_game] leaves user://settings.cfg alone.
static var write_settings := true

var mode: Mode = QUICK
## Index into [method steps], [constant OFF] when not running. Equal to
## steps().size() is the done card.
var step: int = OFF
var hud: HUD
## The current step is done and waits for the voice line to end.
var met := false

## Chapter indices already topped up (academy).
var _topped: Array[int] = []
## Per-step flags set by events since the step began.
var _flag := false
var _ore_in := false
## A research project finished since the fund step began.
var _tech_seen := false
var _cam_start := Vector3.INF
var _cam_dist := 0.0
var _cam_yaw := 0.0
var _market: FactoryMarket
var _zones: DefenseZones
var _clock := 0.0


func _ready() -> void:
	add_to_group(GROUP)
	if academy_next:
		academy_next = false
		mode = ACADEMY
		step = 0
	else:
		mode = QUICK
		step = 0 if runs_on_new_game() else OFF


static func of(tree: SceneTree) -> Tutorial:
	return tree.get_first_node_in_group(GROUP) as Tutorial


# --- Steps ----------------------------------------------------------------------

## Chapters of the academy: name, blurb, top-up (credits and ore floors) and
## the research a jump to it grants.
static func chapters() -> Array[Dictionary]:
	return [
		{"name": "Command", "blurb": "Camera, time and your station", "top": {}, "grants": []},
		{"name": "Mining", "blurb": "Outposts, miners, contracts, ore sales", "top": {"cr": 2000, "fe": 120}, "grants": []},
		{"name": "Defence", "blurb": "Mercenaries, zones, turrets, a raid", "top": {"cr": 2500, "fe": 150, "ti": 60}, "grants": []},
		{"name": "Contracts", "blurb": "Bounties, escorts, salvage", "top": {"cr": 2500, "fe": 100, "ti": 40}, "grants": []},
		{"name": "Research", "blurb": "Science Lab, researchers, projects", "top": {"cr": 3000, "fe": 200, "ti": 100}, "grants": []},
		{"name": "Gear", "blurb": "Factory and Outfitter", "top": {"cr": 2000, "fe": 200, "ti": 100}, "grants": []},
		{"name": "Exploration", "blurb": "Jump gates, explorers, the cluster map", "top": {"cr": 2500, "fe": 200, "ti": 80}, "grants": [&"eng_jump_navigation"]},
		{"name": "Planets", "blurb": "Planet outposts on the surface", "top": {"cr": 4000, "fe": 300, "ti": 150}, "grants": [&"pln_assault_doctrine"]},
		{"name": "Expansion", "blurb": "Forward stations in other systems", "top": {"cr": 5000, "fe": 400, "ti": 300, "wa": 250}, "grants": [&"eng_forward_operations"]},
		{"name": "Rivals", "blurb": "Other corporations", "top": {}, "grants": []},
	]


## The step list of the running mode. Each: id, chapter (index into
## [method chapters]), and for the card: build (the build bar tile to pulse,
## opens the bar), zone (the defence zone tile), info (ends on Next).
func steps() -> Array[Dictionary]:
	return steps_of(mode)


static func steps_of(m: Mode) -> Array[Dictionary]:
	if m == QUICK:
		return [
			{"id": &"build_mining", "chapter": 1, "build": MINING_ID},
			{"id": &"hire_miner", "chapter": 1},
			{"id": &"post_mining", "chapter": 1},
			{"id": &"sell_ore", "chapter": 1},
			{"id": &"merc", "chapter": 2, "build": MERC_ID},
			{"id": &"zone", "chapter": 2, "zone": true},
		]
	return [
		{"id": &"welcome", "chapter": 0, "info": true},
		{"id": &"camera", "chapter": 0},
		{"id": &"time", "chapter": 0},
		{"id": &"station", "chapter": 0},
		{"id": &"build_mining", "chapter": 1, "build": MINING_ID},
		{"id": &"hire_miner", "chapter": 1},
		{"id": &"post_mining", "chapter": 1},
		{"id": &"sell_ore", "chapter": 1},
		{"id": &"merc", "chapter": 2, "build": MERC_ID},
		{"id": &"zone", "chapter": 2, "zone": true},
		{"id": &"turret", "chapter": 2, "build": &"defense_turret"},
		{"id": &"raid", "chapter": 2},
		{"id": &"bounty", "chapter": 3},
		{"id": &"escort", "chapter": 3},
		{"id": &"salvage_yard", "chapter": 3, "build": &"salvage_yard"},
		{"id": &"hire_salvager", "chapter": 3},
		{"id": &"lab", "chapter": 4, "build": &"science_lab"},
		{"id": &"researcher", "chapter": 4},
		{"id": &"fund", "chapter": 4},
		{"id": &"tech_done", "chapter": 4},
		{"id": &"factory", "chapter": 5},
		{"id": &"outfitter", "chapter": 5, "build": &"outfitter"},
		{"id": &"gear_sale", "chapter": 5},
		{"id": &"jump_nav", "chapter": 6},
		{"id": &"explorer_outpost", "chapter": 6, "build": &"explorer_outpost"},
		{"id": &"hire_explorer", "chapter": 6},
		{"id": &"explore", "chapter": 6},
		{"id": &"map", "chapter": 6},
		{"id": &"surface_ops", "chapter": 7},
		{"id": &"found_outpost", "chapter": 7},
		{"id": &"visit_surface", "chapter": 7},
		{"id": &"forward_ops", "chapter": 8},
		{"id": &"forward_build", "chapter": 8, "build": &"forward_station"},
		{"id": &"forward_found", "chapter": 8},
		{"id": &"rivals", "chapter": 9, "info": true},
	]


func step_count() -> int:
	return steps().size()


## The current step's dictionary ({} when off or done).
func current() -> Dictionary:
	var list := steps()
	return list[step] if step >= 0 and step < list.size() else {}


func is_running() -> bool:
	return step != OFF


func is_done_card() -> bool:
	return step >= 0 and step >= step_count()


## Chapter index of [param s] (the current step by default), -1 when none.
func chapter_of(s: int = -2) -> int:
	if s == -2:
		s = step
	var list := steps()
	return int(list[s]["chapter"]) if s >= 0 and s < list.size() else -1


## First step index of chapter [param c] in this mode, -1 when it has none.
func first_step_of(c: int) -> int:
	var list := steps()
	for i in list.size():
		if int(list[i]["chapter"]) == c:
			return i
	return -1


## [index within the chapter (1-based), steps in the chapter] of the current step.
func chapter_progress() -> Vector2i:
	var c := chapter_of()
	var n := 0
	var at := 0
	var list := steps()
	for i in list.size():
		if int(list[i]["chapter"]) == c:
			n += 1
			if i <= step:
				at = n
	return Vector2i(at, n)


# --- Running --------------------------------------------------------------------

func setup(owner_hud: HUD) -> void:
	hud = owner_hud
	if hud.manager:
		hud.manager.building_added.connect(_on_building)
		hud.manager.building_changed.connect(_on_building)
	ContractBoard.contract_posted.connect(func(_c: Contract) -> void: _check())
	Economy.cargo_received.connect(func(ore: PackedInt32Array, _source: String) -> void:
		if _id() in [&"post_mining", &"sell_ore"]:
			for n in ore:
				if n > 0:
					_ore_in = true
					break)
	Research.tech_completed.connect(func(_t: TechDef) -> void:
		if _id() in [&"fund", &"tech_done"]:
			_tech_seen = true
		_check())
	SimClock.speed_changed.connect(func(_s: float) -> void: _on_time())
	SimClock.paused_changed.connect(func(_p: bool) -> void: _on_time())
	if hud.camera:
		hud.camera.view_changed.connect(_on_camera)
	if hud.selection:
		hud.selection.selection_changed.connect(_on_selected)
	var home := SystemWorld.home(get_tree())
	var combat := CombatWorld.of(home) if home else null
	if combat:
		combat.combatant_destroyed.connect(func(n: Node3D, _k: Node3D) -> void:
			if _id() == &"raid" and n is ScavengerShip:
				_flag = true
				_check())
	_zones = DefenseZones.of(self)
	if _zones:
		_zones.zones_changed.connect(_check)
	_hook_factory.call_deferred()
	_resume.call_deferred()


func _process(delta: float) -> void:
	if step == OFF or is_done_card():
		return
	_clock += delta
	if _clock >= CHECK_EVERY:
		_clock = 0.0
		_check()


## Moves to the next step (and past any that are already done).
func advance() -> void:
	if step == OFF or is_done_card():
		return
	_go_to(step + 1)


## Jumps to chapter [param c] (academy): grants the research it builds on,
## tops up, starts its first step.
func jump_to_chapter(c: int) -> void:
	var s := first_step_of(c)
	if s < 0:
		return
	if mode == ACADEMY:
		for id: StringName in chapters()[c]["grants"]:
			Research.grant(Research.catalog().find(id))
	_go_to(s)


## Ends the tutorial for good (Skip, the done card closed, Quit tutorial).
func finish() -> void:
	if step == OFF:
		return
	step = OFF
	set_runs_on_new_game(false)
	_apply_safety()
	changed.emit()


func save_state() -> Dictionary:
	return {"step": step, "mode": int(mode), "topped": _topped.duplicate()}


## A save without the key ({}) loads with the tutorial off; one without
## "mode" is a quick card.
func load_state(d: Dictionary) -> void:
	mode = clampi(int(d.get("mode", QUICK)), 0, ACADEMY) as Mode
	step = clampi(int(d.get("step", OFF)), OFF, step_count())
	_topped.clear()
	for c in d.get("topped", []):
		_topped.append(int(c))
	_reset_flags()
	_apply_safety.call_deferred()
	changed.emit()
	_check.call_deferred()


func _id() -> StringName:
	var cur := current()
	return cur.get("id", &"")


func _go_to(s: int) -> void:
	step = clampi(s, 0, step_count())
	if is_done_card():
		set_runs_on_new_game(false)
		_apply_safety()
		changed.emit()
		return
	_begin_step()
	changed.emit()
	_check()


## After the scene (and a load) is in: the safety rules and the current
## chapter's top-up, without a step's own setup (a loaded raid step keeps
## the raid the save holds).
func _resume() -> void:
	_apply_safety()
	if mode == ACADEMY and step != OFF and not is_done_card():
		_top_up(chapter_of())
	_check()


## A step starts: flags reset, the chapter's top-up, the safety rules, the
## step's own setup (the forced raid).
func _begin_step() -> void:
	if step == OFF or is_done_card():
		return
	_reset_flags()
	_apply_safety()
	if mode != ACADEMY:
		return
	_top_up(chapter_of())
	if _id() == &"raid":
		_force_raid()
	elif _id() == &"station":
		show_station()


## Clears the per-step flags. Entering sell_ore keeps the ore that came in
## while post_mining was still being read, entering tech_done keeps a project
## that finished during the fund step.
func _reset_flags() -> void:
	met = false
	_flag = false
	if _id() != &"sell_ore":
		_ore_in = false
	if _id() != &"tech_done":
		_tech_seen = false
	_cam_start = Vector3.INF
	_cam_dist = 0.0


# --- Academy rules --------------------------------------------------------------

## Academy: raids only from the raid step on, no base arrivals and no gate
## raids while the tutorial runs. Back to normal once it ends.
func _apply_safety() -> void:
	if mode != ACADEMY or not is_inside_tree():
		return
	var home := SystemWorld.home(get_tree())
	var combat := CombatWorld.of(home) if home else null
	if combat == null:
		return
	var running := step != OFF and not is_done_card()
	var raid_at := _index_of(&"raid")
	if combat.raids:
		combat.raids.enabled = not running or step >= raid_at
	if combat.threats:
		combat.threats.arrivals = not running
	if combat.gate_raids:
		combat.gate_raids.enabled = not running
	if combat.warlords:
		combat.warlords.enabled = not running


func _index_of(id: StringName) -> int:
	var list := steps()
	for i in list.size():
		if list[i]["id"] == id:
			return i
	return -1


## Raises credits and ore to the chapter's floors, once per chapter.
func _top_up(c: int) -> void:
	if c < 0 or _topped.has(c):
		return
	_topped.append(c)
	var top: Dictionary = chapters()[c]["top"]
	if top.is_empty():
		return
	var add_ore := Economy.zero_ore()
	var keys := {"fe": Economy.Ore.IRON, "ti": Economy.Ore.TITANIUM, "cy": Economy.Ore.CRYSTAL, "wa": Economy.Ore.WATER}
	for k: String in keys:
		var i: int = keys[k]
		add_ore[i] = maxi(0, int(top.get(k, 0)) - Economy.ore[i])
	var cr := maxi(0, int(top.get("cr", 0)) - Economy.credits)
	var any := cr > 0
	for n in add_ore:
		any = any or n > 0
	if any:
		Economy.add(cr, add_ore, Ledger.GRANT, "Training grant")


## The station step: the camera flies to the home station and follows it,
## zooming in to the station's own framing when it is further out (a closer
## view stays as it is). It does not select the station: that is the step.
func show_station() -> void:
	if hud == null or hud.camera == null or hud.solar_system == null or not hud.is_home_view():
		return
	var st := hud.solar_system.home_station
	if not is_instance_valid(st):
		return
	var cam := hud.camera
	var framing := float(st.get_meta(&"focus_distance", maxf(float(st.get_meta(&"focus_radius", 100.0)) * 5.0, cam.min_distance)))
	cam.focus_on(st, minf(cam.get_distance(), framing))


## One small raid from a living base, announced as usual.
func _force_raid() -> void:
	var home := SystemWorld.home(get_tree())
	var combat := CombatWorld.of(home) if home else null
	var raids := combat.raids if combat else null
	if raids == null or raids.pending_size > 0:
		return
	raids.enabled = true
	var den := raids.pick_den()
	if den:
		raids.warn_raid(den, 1)
	else:
		_flag = true


# --- Detection -----------------------------------------------------------------

func _on_building(_b: Building) -> void:
	_hook_factory()
	_check()


func _on_time() -> void:
	if _id() == &"time":
		_flag = true
		_check()


func _on_camera(pivot: Vector3, distance: float, yaw: float) -> void:
	if _id() != &"camera":
		return
	if _cam_start == Vector3.INF:
		_cam_start = pivot
		_cam_dist = distance
		_cam_yaw = yaw
		return
	if pivot.distance_to(_cam_start) > CAMERA_MOVE or absf(distance - _cam_dist) > _cam_dist * CAMERA_ZOOM \
			or absf(angle_difference(deg_to_rad(yaw), deg_to_rad(_cam_yaw))) > deg_to_rad(CAMERA_TURN):
		_flag = true


func _on_selected(target: Node3D) -> void:
	if _id() == &"factory" and target is Building and (target as Building).def and (target as Building).def.id == &"factory":
		_flag = true
		_check()


## Latches the current step once it is met, then advances when SOLA is
## done reading its line.
func _check() -> void:
	if step < 0 or is_done_card():
		return
	if not met and _is_met(_id()):
		met = true
		changed.emit()
	if met and not _held():
		advance()


## The card is still reading the current line.
func _held() -> bool:
	return hud != null and hud.tutorial_card != null and hud.tutorial_card.is_speaking()


func _is_met(id: StringName) -> bool:
	match id:
		&"welcome", &"rivals":
			return false
		&"camera", &"time", &"factory", &"raid", &"sell_ore":
			return _flag
		&"tech_done":
			return _tech_seen
		&"station":
			return hud != null and hud.build_menu.visible
		&"build_mining":
			return _active(MINING_ID)
		&"hire_miner":
			return _has_crew(MINING_ID)
		&"post_mining":
			return _listed(func(c: Contract) -> bool: return c is MiningContract)
		&"merc":
			return _has_crew(MERC_ID)
		&"zone":
			return _zones != null and _zones.count() > 0
		&"turret":
			return _active(&"defense_turret")
		&"bounty":
			return _listed(func(c: Contract) -> bool: return c is BountyContract)
		&"escort":
			return _listed(func(c: Contract) -> bool: return c is EscortContract)
		&"salvage_yard":
			return _active(&"salvage_yard")
		&"hire_salvager":
			return _has_crew(&"salvage_yard")
		&"lab":
			return _active(&"science_lab")
		&"researcher":
			return not Research.researchers.is_empty()
		&"fund":
			return not Research.projects.is_empty()
		&"outfitter":
			return _active(&"outfitter")
		&"gear_sale":
			var o := Outfitter.find(SystemWorld.home(get_tree()))
			return o != null and o.total_income > 0
		&"jump_nav":
			return Research.is_done(&"eng_jump_navigation")
		&"explorer_outpost":
			return _active(&"explorer_outpost")
		&"hire_explorer":
			return _has_crew(&"explorer_outpost")
		&"explore":
			return _listed(func(c: Contract) -> bool: return c is ExploreContract)
		&"map":
			return hud != null and hud.cluster_map != null and hud.cluster_map.visible
		&"surface_ops":
			return Research.is_done(OutpostState.TECH)
		&"found_outpost":
			return not Sector.outposts.is_empty()
		&"visit_surface":
			var op := Outposts.of(get_tree())
			return op != null and op.live != null
		&"forward_ops":
			return Research.is_done(&"eng_forward_operations")
		&"forward_build":
			return MobileStation.count_all(get_tree(), Corps.PLAYER) > 0 or _forward_count() > 0
		&"forward_found":
			return _forward_count() > 0
	return false


func _forward_count() -> int:
	var fs := ForwardStations.of(get_tree())
	return fs.ids().size() if fs else 0


func _listed(test: Callable) -> bool:
	for c in ContractBoard.get_listed():
		if c.system_id == ClusterNetwork.HOME_ID and test.call(c):
			return true
	return false


func _active(id: StringName) -> bool:
	return hud != null and hud.manager != null and hud.manager.find_active(id) != null


func _has_crew(id: StringName) -> bool:
	if hud == null or hud.manager == null:
		return false
	for b in hud.manager.buildings:
		if is_instance_valid(b) and b.def.id == id and b.is_active() and not b.captains.is_empty():
			return true
	return false


func _hook_factory() -> void:
	if _market and is_instance_valid(_market):
		return
	var f := Factory.find(self)
	if f == null or f.market == null:
		return
	_market = f.market
	_market.sold.connect(func(_ore: int, units: int, _credits: int) -> void:
		if _id() == &"sell_ore" and _ore_in and units > 0:
			_flag = true
			_check())


# --- Settings ------------------------------------------------------------------

## True unless the player finished or skipped the tutorial once.
static func runs_on_new_game() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return true
	return not bool(cfg.get_value(SETTINGS_SECTION, SETTINGS_KEY, false))


## SOLA's voice lines play (TutorialCard); on unless the player turned them off.
static func voice_on() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return true
	return bool(cfg.get_value(SETTINGS_SECTION, "voice", true))


static func set_voice_on(on: bool) -> void:
	if not write_settings:
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SETTINGS_SECTION, "voice", on)
	cfg.save(SETTINGS_PATH)


static func set_runs_on_new_game(on: bool) -> void:
	if not write_settings:
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SETTINGS_SECTION, SETTINGS_KEY, not on)
	cfg.save(SETTINGS_PATH)

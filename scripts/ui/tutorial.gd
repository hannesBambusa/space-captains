class_name Tutorial
extends Node
## First-time tutorial: six training steps that teach the core loop, shown by
## the [TutorialCard]. A step ends on its own when the game shows it is done
## (signals only, no polling):
##   0 Build a Mining Outpost: an active one exists (BuildingManager
##     building_added / building_changed, construction finished).
##   1 Hire a miner: a Mining Outpost has a captain (building_changed, fired
##     by Building.hires_changed).
##   2 Post a mining contract: ContractBoard.contract_posted with a
##     MiningContract (or one is already listed).
##   3 Sell your first ore: a cargo shuttle brought ore to the station
##     (Economy.cargo_received) and after that the Factory bought ore
##     (FactoryMarket.sold).
##   4 Mercenary Outpost and a mercenary: one has a captain.
##   5 Defence zone: DefenseZones has a zone (zones_changed).
## Then [constant DONE] (the closing tip card) and [constant OFF].
##
## Saved in the game ([method save_state], GameSnapshot "tutorial"); a save
## without it loads with the tutorial off. A new game starts it unless the
## player finished or skipped it once: that flag lives in user://settings.cfg
## ([method runs_on_new_game], [method set_runs_on_new_game]; the main menu
## Settings has the "Tutorial" checkbox).

signal changed

const GROUP := "tutorial"
## Shared with the WindowMode autoload (fullscreen).
const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "tutorial"
const SETTINGS_KEY := "finished"

const OFF := -1
const BUILD_MINING := 0
const HIRE_MINER := 1
const POST_CONTRACT := 2
const SELL_ORE := 3
const MERCENARY := 4
const DEFENCE_ZONE := 5
const DONE := 6
const STEP_COUNT := 6

const MINING_ID := &"mining_outpost"
const MERC_ID := &"mercenary_outpost"

## Current step, [constant OFF] when not running.
var step: int = OFF
var hud: HUD

## Ore reached the station since the sell step began.
var _ore_in := false
var _market: FactoryMarket
var _zones: DefenseZones


func _ready() -> void:
	add_to_group(GROUP)
	step = BUILD_MINING if runs_on_new_game() else OFF


static func of(tree: SceneTree) -> Tutorial:
	return tree.get_first_node_in_group(GROUP) as Tutorial


func setup(owner_hud: HUD) -> void:
	hud = owner_hud
	if hud.manager:
		hud.manager.building_added.connect(_on_building)
		hud.manager.building_changed.connect(_on_building)
	ContractBoard.contract_posted.connect(func(c: Contract) -> void:
		if step == POST_CONTRACT and c is MiningContract and c.system_id == ClusterNetwork.HOME_ID:
			advance())
	Economy.cargo_received.connect(func(ore: PackedInt32Array, _source: String) -> void:
		if step == SELL_ORE:
			for n in ore:
				if n > 0:
					_ore_in = true
					break)
	_zones = DefenseZones.of(self)
	if _zones:
		_zones.zones_changed.connect(_check)
	_hook_factory.call_deferred()
	_check.call_deferred()


func is_running() -> bool:
	return step != OFF


## Moves to the next step (and past any that are already done).
func advance() -> void:
	if step == OFF or step >= DONE:
		return
	step += 1
	_ore_in = false
	if step == DONE:
		set_runs_on_new_game(false)
	changed.emit()
	_check()


## Ends the tutorial for good (Skip, or the done card closed).
func finish() -> void:
	if step == OFF:
		return
	step = OFF
	set_runs_on_new_game(false)
	changed.emit()


func save_state() -> Dictionary:
	return {"step": step}


## A save without the key ({}) loads with the tutorial off.
func load_state(d: Dictionary) -> void:
	step = clampi(int(d.get("step", OFF)), OFF, DONE)
	_ore_in = false
	changed.emit()
	_check.call_deferred()


# --- Detection -----------------------------------------------------------------

func _on_building(_b: Building) -> void:
	_hook_factory()
	_check()


## Advances while the current step is already met.
func _check() -> void:
	if step >= 0 and step < DONE and _is_met(step):
		advance()


func _is_met(s: int) -> bool:
	match s:
		BUILD_MINING:
			return _active(MINING_ID) != null
		HIRE_MINER:
			return _has_crew(MINING_ID)
		POST_CONTRACT:
			for c in ContractBoard.get_listed():
				if c is MiningContract and c.system_id == ClusterNetwork.HOME_ID:
					return true
			return false
		SELL_ORE:
			return false
		MERCENARY:
			return _has_crew(MERC_ID)
		DEFENCE_ZONE:
			return _zones != null and _zones.count() > 0
	return false


func _active(id: StringName) -> Building:
	return hud.manager.find_active(id) if hud and hud.manager else null


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
		if step == SELL_ORE and _ore_in and units > 0:
			advance())


# --- Settings ------------------------------------------------------------------

## True unless the player finished or skipped the tutorial once.
static func runs_on_new_game() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return true
	return not bool(cfg.get_value(SETTINGS_SECTION, SETTINGS_KEY, false))


static func set_runs_on_new_game(on: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SETTINGS_SECTION, SETTINGS_KEY, not on)
	cfg.save(SETTINGS_PATH)

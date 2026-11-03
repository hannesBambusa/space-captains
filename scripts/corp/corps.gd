class_name CorpRegistry
extends Node
## Autoload "Corps". The corporations of this game ([Corp]): the player's
## (the Economy and Research autoloads) and, when the New game setting is
## not Off, 1 to 3 rival AI corps (rivals plan M1), each with its own
## [CorpEconomy] and [CorpResearch] (children of this node) and its own
## [RivalMind]. Ids: [constant PLAYER], then [constant RIVAL_IDS] in order.
##
## Ownership: every station belongs to a corp. Home and forward stations
## are the player's; a station site with "corp" (RemoteSystemState.station)
## belongs to that corp ([method corp_of_system]). Node-side code asks
## [method of] / [method economy] / [method research]: the corp of the
## system the node is in. A ship belongs to the corp of its home building
## ([method owner_of]).
##
## Acting: things a corp starts (posting a contract, funding research, a
## hire from code that has no node of its own) count for [member acting],
## the player unless a rival's AI runs inside [method act_as].
##
## New game settings ([member next_difficulty], [member next_rival_count],
## user://settings.cfg [rival]) become [member difficulty] and the rivals;
## saved with the game. Off = no rival at all (the game as before, smoke).
## One difficulty for every rival.

enum Difficulty { OFF, EASY, NORMAL, HARD }

const PLAYER := &"player"
const RIVAL_IDS: Array[StringName] = [&"rival_1", &"rival_2", &"rival_3"]
## Saves from before M1 had one rival with this id.
const OLD_RIVAL := &"rival"
const MAX_RIVALS := 3
const DIFFICULTY_NAMES: PackedStringArray = ["Off", "Easy", "Normal", "Hard"]
## Corporate grant multiplier of a rival by difficulty.
const GRANT_MULT: PackedFloat32Array = [0.0, 0.8, 1.0, 1.3]
const SETTINGS_PATH := "user://settings.cfg"
const RIVAL_NAMES: PackedStringArray = ["Helix Dynamics", "Vantor Combine", "Kessler-Arat Mining", "Obelisk Industries",
		"Corvane Holdings", "Tessaract Freight", "Morrow Deepworks", "Halcyon Extraction"]
## One colour per rival, in id order (markers, the Rival panel).
const RIVAL_COLORS: Array[Color] = [Color(0.62, 1.0, 0.45), Color(0.85, 0.55, 1.0), Color(1.0, 0.82, 0.35)]

## A corp was created or removed (new game, load).
signal corps_changed

## The setting the next new game starts with.
var next_difficulty: Difficulty = Difficulty.OFF
## Rivals in the next new game (1 to 3, used unless Off).
var next_rival_count := 1
## This game's setting.
var difficulty: Difficulty = Difficulty.OFF
var player: Corp
## The rival corps, [constant RIVAL_IDS] order; empty while Off.
var rivals: Array[Corp] = []
## The corp that starts things now (see [method act_as]).
var acting: StringName = PLAYER


func _ready() -> void:
	player = Corp.new()
	player.id = PLAYER
	player.display_name = "Your station"
	player.economy = Economy
	player.research = Research
	Research.corp_id = PLAYER
	_load_settings()


func has_rival() -> bool:
	return not rivals.is_empty()


## True for a rival corp id (also the pre-M1 "rival").
static func is_rival(id: StringName) -> bool:
	return RIVAL_IDS.has(id) or id == OLD_RIVAL


## [param id] with the pre-M1 "rival" read as rival 1.
static func norm(id: StringName) -> StringName:
	return RIVAL_IDS[0] if id == OLD_RIVAL else id


## The corp [param id], the player for unknown ids.
func get_corp(id: StringName) -> Corp:
	var r := rival(id)
	return r if r else player


## The rival [param id], null when there is none.
func rival(id: StringName) -> Corp:
	id = norm(id)
	for r in rivals:
		if r.id == id:
			return r
	return null


## Ids of the rivals in play (eliminated ones too).
func rival_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for r in rivals:
		out.append(r.id)
	return out


## Rivals still in the game.
func living_rivals() -> Array[Corp]:
	var out: Array[Corp] = []
	for r in rivals:
		if r.mind and not r.mind.eliminated:
			out.append(r)
	return out


func display_name(id: StringName) -> String:
	return get_corp(id).display_name


func economy_of_corp(id: StringName) -> CorpEconomy:
	return get_corp(id).economy


func research_of_corp(id: StringName) -> CorpResearch:
	return get_corp(id).research


func acting_corp() -> Corp:
	return get_corp(acting)


func acting_economy() -> CorpEconomy:
	return acting_corp().economy


## Runs [param fn] with [member acting] set to [param corp_id] and returns
## its result.
func act_as(corp_id: StringName, fn: Callable) -> Variant:
	var before := acting
	acting = norm(corp_id)
	var out: Variant = fn.call()
	acting = before
	return out


# --- Ownership ----------------------------------------------------------------

## Corp of the station in system [param id]: home and forward stations are
## the player's, a site with "corp" is that corp's. No station: the player
## (nobody else owns anything there).
func corp_of_system(id: StringName) -> StringName:
	if id.is_empty() or id == ClusterNetwork.HOME_ID:
		return PLAYER
	var st := Sector.state(id)
	if st == null or st.station.is_empty():
		return PLAYER
	return norm(StringName(st.station.get("corp", PLAYER)))


func corp_of_node(n: Node) -> StringName:
	var w := SystemWorld.of(n)
	return corp_of_system(w.system_id) if w else PLAYER


## Who [param n] belongs to: a ship its home building's corp (&"" for ships
## without one: raiders, captainless strays), anything else the corp of its
## system's station.
func owner_of(n: Node) -> StringName:
	if n == null or not is_instance_valid(n):
		return &""
	var s := n as Ship
	if s:
		if is_instance_valid(s.home):
			return corp_of_node(s.home)
		var ms := s as MobileStation
		return norm(ms.corp) if ms else &""
	return corp_of_node(n)


func of(n: Node) -> Corp:
	return get_corp(corp_of_node(n))


func economy(n: Node) -> CorpEconomy:
	return of(n).economy


func research(n: Node) -> CorpResearch:
	return of(n).research


## The home system of [param corp_id] (home for the player, its region's home
## for a rival), &"" when unknown.
func home_of(corp_id: StringName) -> StringName:
	corp_id = norm(corp_id)
	if corp_id == PLAYER:
		return ClusterNetwork.HOME_ID
	var i := RIVAL_IDS.find(corp_id)
	if i < 0 or Sector.network == null or i >= Sector.network.rival_ids.size():
		return &""
	return Sector.network.rival_ids[i]


## The corp whose home is system [param id], &"" for none.
func corp_at_home(id: StringName) -> StringName:
	if id == ClusterNetwork.HOME_ID:
		return PLAYER
	for r in rivals:
		if home_of(r.id) == id:
			return r.id
	return &""


## The live world of [param corp_id]'s headquarters (home for the player).
func hq_world(tree: SceneTree, corp_id: StringName) -> SystemWorld:
	corp_id = norm(corp_id)
	if corp_id == PLAYER:
		return SystemWorld.home(tree)
	var id := home_of(corp_id)
	for w in SystemWorld.all(tree):
		if w.system_id == id:
			return w
	return null


## Corps [param a] and [param b] fight each other (Combat.hostile): a war
## between them, declared by either side, both still in the game.
func corps_at_war(a: StringName, b: StringName) -> bool:
	a = norm(a)
	b = norm(b)
	if a == b or a.is_empty() or b.is_empty():
		return false
	var ra := rival(a)
	var rb := rival(b)
	if (ra and ra.mind.eliminated) or (rb and rb.mind.eliminated):
		return false
	return (ra != null and ra.mind.at_war_with(b)) or (rb != null and rb.mind.at_war_with(a))


## Any war involving the player.
func player_at_war() -> bool:
	for r in rivals:
		if corps_at_war(r.id, PLAYER):
			return true
	return false


## True when [param a] and [param b] are different corps (both set).
static func rivals_of(a: StringName, b: StringName) -> bool:
	return not a.is_empty() and not b.is_empty() and norm(a) != norm(b)


# --- New game, saves ----------------------------------------------------------

## Rival regions the next network gets (Sector.reset): the rival count, 1 while Off.
func regions_for_new_game() -> int:
	return clampi(next_rival_count, 1, MAX_RIVALS) if next_difficulty != Difficulty.OFF else 1


## A new game (SaveManager._reset_globals, after Sector.reset).
func reset() -> void:
	acting = PLAYER
	difficulty = next_difficulty
	_drop_rivals()
	if difficulty != Difficulty.OFF:
		var n := clampi(next_rival_count, 1, MAX_RIVALS)
		if Sector.network:
			n = mini(n, maxi(Sector.network.rival_ids.size(), 1))
		for i in n:
			_make_rival(i)
	corps_changed.emit()


## Remembers [param d] for the next new game (main menu).
func set_next_difficulty(d: Difficulty) -> void:
	next_difficulty = d
	_save_settings()


func set_next_rival_count(n: int) -> void:
	next_rival_count = clampi(n, 1, MAX_RIVALS)
	_save_settings()


func save_state() -> Dictionary:
	var list := []
	for r in rivals:
		list.append({"id": String(r.id), "name": r.display_name, "economy": r.economy.save_state(), "ledger": r.economy.ledger.save_state(),
				"research": r.research.save_state(), "mind": r.mind.to_dict()})
	return {"difficulty": int(difficulty), "rivals": list}


## [param d]: the "corps" key ({} for older saves: no rival). The pre-M1
## shape (one "rival") loads as rival 1.
func load_state(d: Dictionary) -> void:
	acting = PLAYER
	difficulty = int(d.get("difficulty", Difficulty.OFF)) as Difficulty
	_drop_rivals()
	var list: Array = d.get("rivals", [])
	if list.is_empty() and d.has("rival"):
		list = [d["rival"]]
	if difficulty != Difficulty.OFF:
		var n := maxi(list.size(), 1)
		if Sector.network:
			n = clampi(n, 1, maxi(Sector.network.rival_ids.size(), 1))
		for i in n:
			var r := _make_rival(i)
			if i >= list.size():
				continue
			var rd: Dictionary = list[i]
			r.display_name = String(rd.get("name", r.display_name))
			r.economy.load_state(rd.get("economy", {}))
			r.economy.ledger.load_state(rd.get("ledger", {}))
			r.research.load_state(rd.get("research", {}))
			r.research.legacy_pending = false
			if rd.has("mind"):
				r.mind = RivalMind.from_dict(rd["mind"])
	corps_changed.emit()


func _make_rival(i: int) -> Corp:
	var r := Corp.new()
	r.id = RIVAL_IDS[i]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("rival_name:%d" % Sector.get_seed())
	# Distinct names in id order: the first draw is rival 1's as before M1.
	# A real copy: Array(PackedStringArray const) shares the constant here.
	var pool: Array[String] = []
	for n in RIVAL_NAMES:
		pool.append(n)
	for k in i + 1:
		var pick: String = pool[rng.randi_range(0, pool.size() - 1)]
		if k == i:
			r.display_name = pick
		pool.erase(pick)
	r.color = RIVAL_COLORS[i]
	r.mind = RivalMind.new()
	var prng := RandomNumberGenerator.new()
	prng.seed = hash("rival_personality:%d:%d" % [Sector.get_seed(), i])
	r.mind.personality = prng.randi_range(0, RivalMind.Personality.size() - 1) as RivalMind.Personality
	r.mind.next_meeting = RivalCorp.FIRST_MEETING + 40.0 * i
	var eco := (load("res://scripts/economy.gd") as GDScript).new() as CorpEconomy
	eco.name = "Economy_%s" % r.id
	eco.grant_per_minute *= GRANT_MULT[difficulty]
	add_child(eco)
	r.economy = eco
	var res := (load("res://scripts/research/research.gd") as GDScript).new() as CorpResearch
	res.name = "Research_%s" % r.id
	res.corp_id = r.id
	add_child(res)
	r.research = res
	rivals.append(r)
	return r


func _drop_rivals() -> void:
	for r in rivals:
		for n: Node in [r.economy, r.research]:
			if is_instance_valid(n):
				remove_child(n)
				n.queue_free()
	rivals.clear()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	next_difficulty = clampi(int(cfg.get_value("rival", "difficulty", Difficulty.OFF)), 0, Difficulty.HARD) as Difficulty
	next_rival_count = clampi(int(cfg.get_value("rival", "count", 1)), 1, MAX_RIVALS)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("rival", "difficulty", int(next_difficulty))
	cfg.set_value("rival", "count", next_rival_count)
	cfg.save(SETTINGS_PATH)

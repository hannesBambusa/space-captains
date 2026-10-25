extends Node
## Autoload "SaveManager". Save slots, starting and loading games, autosave.
##
## One slot per game ("Game 1", "Game 2", ...), a file each:
## user://saves/<slot>.save holds two values written with store_var (no
## objects): a small header (name, version, real date, sim time, credits,
## captains: the load list reads only this) and the [GameSnapshot] data.
## Writes are atomic: the new save goes to <slot>.tmp first, the old save
## becomes <slot>.bak, then the tmp file takes its place, so a crash while
## saving always leaves one good file. A corrupt or old-version save
## reports an error and the menus offer the .bak.
##
## Autosave: every [member autosave_interval] real seconds of unpaused play,
## and when going back to the main menu, quitting, or closing the window.
## A new game runs the scenes/system.tscn start as before; loading builds
## the same scene and applies the save before its first sim step.

signal saved(slot: String)

const SAVE_DIR := "user://saves"
const EXT := ".save"
const VERSION := GameSnapshot.VERSION
const SYSTEM_SCENE := "res://scenes/system.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
## First bytes of every save file.
const MAGIC := "SCSAVE\n"

## Real seconds of unpaused play between autosaves.
@export var autosave_interval: float = 180.0

## Slot of the game being played ("" in the menu).
var current_slot: String = ""
## Real seconds of unpaused play since the last save.
var since_save: float = 0.0
var _busy := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().set_auto_accept_quit(false)
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


## A system scene is running (also when it was started on its own, e.g.
## from the editor: it then gets a new slot on its first save).
func in_game() -> bool:
	return SolarSystem.of(get_tree()) != null


func _process(delta: float) -> void:
	if not in_game() or _busy or SimClock.paused:
		return
	since_save += delta
	if since_save >= autosave_interval:
		if save_game().is_empty():
			_toast("Autosaved")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()


# --- Slots ----------------------------------------------------------------------

static func path_of(slot: String) -> String:
	return "%s/%s%s" % [SAVE_DIR, slot, EXT]


static func backup_of(slot: String) -> String:
	return path_of(slot) + ".bak"


## Every save, newest first: {slot, name, saved_at (unix), sim_time,
## credits, captains, ok, error, has_backup}.
func list_saves() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if not f.ends_with(EXT):
			continue
		var slot := f.trim_suffix(EXT)
		var h := read_header(path_of(slot))
		h["slot"] = slot
		h["has_backup"] = FileAccess.file_exists(backup_of(slot))
		if not h.has("name"):
			h["name"] = slot.capitalize()
		if not h.has("saved_at"):
			h["saved_at"] = FileAccess.get_modified_time(path_of(slot))
		out.append(h)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["saved_at"]) > int(b["saved_at"]))
	return out


## The newest save, or {} when there is none.
func newest_save() -> Dictionary:
	var list := list_saves()
	return list[0] if not list.is_empty() else {}


## "game_3" for the third game: one more than the highest slot number used.
func next_slot() -> String:
	var n := 0
	var dir := DirAccess.open(SAVE_DIR)
	if dir:
		for f in dir.get_files():
			if f.begins_with("game_"):
				n = maxi(n, f.trim_prefix("game_").get_slice(".", 0).to_int())
	return "game_%d" % (n + 1)


static func slot_name(slot: String) -> String:
	if slot.begins_with("game_"):
		return "Game %s" % slot.trim_prefix("game_")
	return slot.capitalize()


func delete_save(slot: String) -> void:
	for p in [path_of(slot), backup_of(slot), path_of(slot) + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


# --- Files ----------------------------------------------------------------------

## The header of a save file, with "ok" and "error" ("" when fine).
static func read_header(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "Could not open the file"}
	var magic := MAGIC.to_utf8_buffer()
	if f.get_length() <= magic.size() or f.get_buffer(magic.size()) != magic:
		return {"ok": false, "error": "The save file is damaged"}
	var h: Variant = f.get_var(false)
	if not (h is Dictionary) or not (h as Dictionary).has("version"):
		return {"ok": false, "error": "The save file is damaged"}
	var d := (h as Dictionary).duplicate()
	if int(d["version"]) != VERSION:
		d["ok"] = false
		d["error"] = "Saved by an %s version of the game (save v%d, game v%d)" % ["newer" if int(d["version"]) > VERSION else "older", int(d["version"]), VERSION]
	else:
		d["ok"] = true
		d["error"] = ""
	return d


## {ok, error, header, data}.
static func read_file(path: String) -> Dictionary:
	var h := read_header(path)
	if not bool(h.get("ok", false)):
		return {"ok": false, "error": h.get("error", "Unknown error")}
	var f := FileAccess.open(path, FileAccess.READ)
	f.get_buffer(MAGIC.to_utf8_buffer().size())
	f.get_var(false)
	var data: Variant = f.get_var(false) if f.get_position() < f.get_length() else null
	if not (data is Dictionary) or (data as Dictionary).is_empty():
		return {"ok": false, "error": "The save file is damaged"}
	return {"ok": true, "error": "", "header": h, "data": data}


## Writes [param data] for [param slot]: tmp file, old save to .bak, rename.
static func write_file(slot: String, header: Dictionary, data: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := path_of(slot)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(MAGIC.to_utf8_buffer())
	f.store_var(header, false)
	f.store_var(data, false)
	var err := f.get_error()
	f.close()
	if err != OK:
		return err
	if FileAccess.file_exists(path):
		var bak := backup_of(slot)
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		err = DirAccess.rename_absolute(path, bak)
		if err != OK:
			return err
	return DirAccess.rename_absolute(tmp, path)


# --- Saving ---------------------------------------------------------------------

## Saves the running game to its slot. Returns "" or the error.
func save_game(slot: String = "") -> String:
	if not in_game():
		return "No game running"
	if slot.is_empty():
		if current_slot.is_empty():
			current_slot = next_slot()
		slot = current_slot
	var tree := get_tree()
	var data := GameSnapshot.capture(tree)
	var header := GameSnapshot.summary(tree)
	header["version"] = VERSION
	header["name"] = slot_name(slot)
	header["saved_at"] = int(Time.get_unix_time_from_system())
	var err := write_file(slot, header, data)
	if err != OK:
		push_error("SaveManager: could not save %s (%s)" % [slot, error_string(err)])
		return "Could not save (%s)" % error_string(err)
	since_save = 0.0
	saved.emit(slot)
	return ""


# --- Scenes -----------------------------------------------------------------------

## Starts a fresh game in a new slot.
func new_game() -> void:
	if _busy:
		return
	_busy = true
	var slot := next_slot()
	var cover := await LoadingScreen.cover(get_tree(), "Starting %s" % slot_name(slot))
	await _leave_scene()
	_reset_globals()
	current_slot = slot
	_enter_game({})
	_busy = false
	cover.reveal()


## Loads [param slot] (its .bak with [param backup]). Returns "" or the
## error; on an error nothing changes.
func load_game(slot: String, backup: bool = false) -> String:
	if _busy:
		return "Busy"
	var file := read_file(backup_of(slot) if backup else path_of(slot))
	if not bool(file["ok"]):
		return String(file["error"])
	_busy = true
	var cover := await LoadingScreen.cover(get_tree(), "Loading %s" % slot_name(slot))
	await _leave_scene()
	_reset_globals()
	current_slot = slot
	var data: Dictionary = file["data"]
	GameSnapshot.apply_globals(data)
	_enter_game(data)
	_busy = false
	cover.reveal()
	if backup:
		# The backup is now the game: save it back as the main file.
		save_game()
	return ""


## Saves, then shows the main menu.
func to_main_menu() -> void:
	if _busy:
		return
	if in_game():
		save_game()
	_busy = true
	var cover := await LoadingScreen.cover(get_tree(), "Returning to the menu")
	await _leave_scene()
	current_slot = ""
	_reset_globals()
	get_tree().change_scene_to_file(MENU_SCENE)
	_busy = false
	cover.reveal()


## Saves the running game, then quits.
func quit_game() -> void:
	if in_game() and not _busy:
		save_game()
	get_tree().quit()


func _leave_scene() -> void:
	var tree := get_tree()
	var pm := tree.root.get_node_or_null(^"PauseMenu")
	if pm and pm.has_method(&"dismiss"):
		pm.call(&"dismiss")
	var old := tree.current_scene
	if old:
		# Unhook the board first: the scene's targets going away must not
		# cancel or finish contracts (and update freed markers).
		ContractBoard.reset()
		old.queue_free()
		await tree.process_frame
		# Deferred callbacks of the freed scene (bounty checks) run now.
		await tree.process_frame


func _enter_game(data: Dictionary) -> void:
	var tree := get_tree()
	var scene := (load(SYSTEM_SCENE) as PackedScene).instantiate()
	tree.root.add_child(scene)
	tree.current_scene = scene
	if not data.is_empty():
		GameSnapshot.apply_scene(tree, data)
	since_save = 0.0


## Autoload state and static registries for a fresh scene.
func _reset_globals() -> void:
	SaveIds.reset()
	ContractBoard.reset()
	SimClock.reset()
	Economy.reset()
	Research.reset()
	EventLog.reset()
	MinerShip._claims.clear()
	SalvagerShip._slots.clear()
	CargoShuttle._pads.clear()
	SalvageContract._free.clear()
	SalvageContract._next_free_id = -1
	PlanetRaidContract.records.clear()


func _toast(text: String) -> void:
	var pm := get_tree().root.get_node_or_null(^"PauseMenu")
	if pm and pm.has_method(&"toast"):
		pm.call(&"toast", text)

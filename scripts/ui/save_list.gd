class_name SaveList
extends VBoxContainer
## The "Load game" list shared by the main menu and the pause menu: one row
## per save, newest first (name, in-game time, real date, credits,
## captains), with Load and Delete. Delete asks in the row first. A save
## that cannot be read shows why and offers its backup when there is one.
## [signal back] when the player closes the list.

signal back

## Slot to mark as the game being played (no delete there).
var playing_slot: String = ""

var _rows: VBoxContainer
var _empty: Label


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var title := UIUtil.label("LOAD GAME", &"TitleLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows)
	_empty = UIUtil.label("No saved games yet", &"DimLabel")
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_empty)
	var close := UIUtil.button("Back")
	close.custom_minimum_size = Vector2(0, 40)
	close.pressed.connect(func() -> void: back.emit())
	add_child(close)


## Rebuilds the rows from the files.
func refresh() -> void:
	for c in _rows.get_children():
		c.queue_free()
	var list := SaveManager.list_saves()
	_empty.visible = list.is_empty()
	for s in list:
		_rows.add_child(_make_row(s))


func _make_row(s: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(margin)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	margin.add_child(h)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	h.add_child(info)
	var slot := String(s["slot"])
	var playing := slot == playing_slot
	info.add_child(UIUtil.label(String(s["name"]) + ("  (playing)" if playing else ""), &"HeaderLabel"))
	var ok := bool(s.get("ok", false))
	if ok:
		info.add_child(UIUtil.label(detail_text(s), &"DimLabel"))
	else:
		var err := UIUtil.label(String(s.get("error", "Cannot be read")), &"WarnLabel")
		info.add_child(err)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	h.add_child(buttons)
	_fill_buttons(buttons, info, s, ok, playing)
	return panel


func _fill_buttons(buttons: HBoxContainer, info: VBoxContainer, s: Dictionary, ok: bool, playing: bool) -> void:
	for c in buttons.get_children():
		c.queue_free()
	var slot := String(s["slot"])
	if ok:
		var load_b := UIUtil.button("Load", &"AccentButton")
		load_b.custom_minimum_size = Vector2(80, 34)
		load_b.pressed.connect(func() -> void: _load(slot, false, info, buttons, s, playing))
		buttons.add_child(load_b)
	elif bool(s.get("has_backup", false)):
		var bak := UIUtil.button("Load backup", &"AccentButton")
		bak.custom_minimum_size = Vector2(110, 34)
		bak.pressed.connect(func() -> void: _load(slot, true, info, buttons, s, playing))
		buttons.add_child(bak)
	if not playing:
		var del := UIUtil.button("Delete")
		del.custom_minimum_size = Vector2(70, 34)
		del.pressed.connect(func() -> void: _confirm_delete(buttons, info, s, ok, playing))
		buttons.add_child(del)


func _confirm_delete(buttons: HBoxContainer, info: VBoxContainer, s: Dictionary, ok: bool, playing: bool) -> void:
	for c in buttons.get_children():
		c.queue_free()
	buttons.add_child(UIUtil.label("Delete %s?" % s["name"], &"WarnLabel"))
	var yes := UIUtil.button("Delete")
	yes.custom_minimum_size = Vector2(70, 34)
	yes.pressed.connect(func() -> void:
		SaveManager.delete_save(String(s["slot"]))
		refresh())
	buttons.add_child(yes)
	var no := UIUtil.button("Keep")
	no.custom_minimum_size = Vector2(60, 34)
	no.pressed.connect(func() -> void: _fill_buttons(buttons, info, s, ok, playing))
	buttons.add_child(no)


## Loads; on an error the row says why and offers the backup.
func _load(slot: String, backup: bool, info: VBoxContainer, buttons: HBoxContainer, s: Dictionary, playing: bool) -> void:
	var err: String = await SaveManager.load_game(slot, backup)
	if err.is_empty() or not is_instance_valid(info):
		return
	info.add_child(UIUtil.label(("Backup: " if backup else "") + err, &"WarnLabel"))
	var row := s.duplicate()
	row["has_backup"] = not backup and bool(s.get("has_backup", false))
	_fill_buttons(buttons, info, row, false, playing)


## "Sim time 1:02:15 · 23 Oct 2026 14:05 · 2,340 cr · 5 captains".
static func detail_text(s: Dictionary) -> String:
	var t := int(float(s.get("sim_time", 0.0)))
	var sim := "%d:%02d:%02d" % [t / 3600, (t / 60) % 60, t % 60]
	var when := date_text(int(s.get("saved_at", 0)))
	var n := int(s.get("captains", 0))
	return "Sim time %s  ·  %s  ·  %s cr  ·  %d captain%s" % [sim, when, UIUtil.amount(int(s.get("credits", 0))), n, "" if n == 1 else "s"]


## Local date and time of a unix timestamp: "23 Oct 2026 14:05".
static func date_text(unix: int) -> String:
	const MONTHS: PackedStringArray = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var d := Time.get_datetime_dict_from_unix_time(unix + bias * 60)
	return "%d %s %d %02d:%02d" % [d["day"], MONTHS[clampi(int(d["month"]) - 1, 0, 11)], d["year"], d["hour"], d["minute"]]

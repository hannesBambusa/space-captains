class_name EndScreen
extends CanvasLayer
## The end of a rival war (rival corporation plan, R7): defeat when the
## player's home station is destroyed, victory when the rival's
## headquarters is. Defeat pauses the game, marks the save slot lost
## (SaveManager.mark_lost: it cannot be continued) and offers only the main
## menu. Victory offers Continue playing (the sector without the rival) or
## the main menu. The stats come from the rival's mind and the ledger.

const THEME_PATH := "res://ui/theme.tres"
const H := preload("res://scripts/ui/theme/hud_style.gd")

var won := false


## Shows the screen once (a second call is ignored).
static func show_end(tree: SceneTree, victory: bool) -> void:
	if tree == null or tree.root.get_node_or_null(^"EndScreen"):
		return
	var e := EndScreen.new()
	e.name = "EndScreen"
	e.won = victory
	tree.root.add_child(e)
	if not victory:
		SaveManager.mark_lost()
		SimClock.paused = true


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = load(THEME_PATH)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"MenuPanel"
	panel.custom_minimum_size = Vector2(560.0, 0.0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var rival := "The rival charters"
	for r in Corps.rivals:
		if not won and Corps.corps_at_war(r.id, Corps.PLAYER):
			rival = r.display_name
	var title := UIUtil.label("VICTORY" if won else "DEFEAT", &"HeaderLabel")
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", H.GOOD if won else H.BAD)
	v.add_child(title)
	var what := ("Every rival headquarters is destroyed. The sector is yours.") if won else \
			("%s destroyed your home station. This game is over and its save cannot be continued." % rival)
	var l := UIUtil.label(what, &"")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 520.0
	v.add_child(l)
	v.add_child(HSeparator.new())
	for line in _stats():
		v.add_child(UIUtil.label(line, &"DimLabel"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	if won:
		var go_on := UIUtil.button("Continue playing", &"MainMenuButton")
		go_on.pressed.connect(func() -> void: queue_free())
		row.add_child(go_on)
	var menu := UIUtil.button("Main menu", &"MainMenuButton")
	menu.pressed.connect(func() -> void:
		SimClock.paused = false
		queue_free()
		SaveManager.to_main_menu())
	row.add_child(menu)


func _stats() -> PackedStringArray:
	var out: PackedStringArray = []
	out.append("Time in the sector: %s" % Fmt.clock(SimClock.time))
	out.append("Credits: %s" % Fmt.amount(Economy.credits))
	for r in Corps.rivals:
		var m := r.mind
		out.append("%s (%s board%s): wars %d, treaties %d, war strikes %d, operations %d, captains poached %d, stations lost %d" % [r.display_name,
				m.personality_name().to_lower(), ", out of the game" if m.eliminated else "", int(m.stats.get("wars", 0)), int(m.stats.get("treaties", 0)),
				int(m.stats.get("strikes", 0)), int(m.stats.get("ops", 0)), int(m.stats.get("poached", 0)), int(m.stats.get("lost_stations", 0))])
	return out

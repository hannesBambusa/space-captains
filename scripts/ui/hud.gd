class_name HUD
extends CanvasLayer
## Game HUD root. Finds the world-side controllers by group and hands itself
## to each widget. Tab toggles the system overview; H (or the top bar's
## HOME button) flies the camera to the home station, or takes the view
## home while another system is viewed;
## M (or the top bar's MAP button) opens the cluster map ([ClusterMap]);
## N cycles the ship markers (see [ShipMarkers]).
## L (or a click on the top bar's credits) opens the ledger ([LedgerPanel]).
## Right column: the minimap, under it the pilot list ([PilotColumn]), and
## the selection panels at the bottom. [method _layout_right] keeps them
## apart: an open selection panel is capped to the room under the minimap
## (its content scrolls) and the pilot list ends above it.
##
## Views (ViewManager): [member solar_system] and [member camera] are the
## viewed system's, rebound on every switch ([signal view_rebound] for the
## widgets that keep signal links); [member manager] stays home's (the
## economy, the pilots and the build menu are global). Outside home the
## build menu is hidden and placement cancelled (no station there). The
## top bar's system name opens the system menu. [method focus] switches
## the view to the system of what it focuses on.

## After a view switch, once [member solar_system] and [member camera] point
## at the new system.
signal view_rebound(world: SystemWorld)

const GROUP := "hud"

@onready var marker: TargetMarker = $Root/TargetMarker
@onready var top_bar: TopBar = $Root/TopBar
@onready var overview: OverviewPanel = $Root/Overview
@onready var build_menu: BuildMenu = $Root/BuildMenu
@onready var building_panel: BuildingPanel = $Root/BuildingPanel
@onready var belt_panel: BeltPanel = $Root/BeltPanel
@onready var captain_panel: CaptainPanel = $Root/CaptainPanel
@onready var target_panel: TargetPanel = $Root/TargetPanel
@onready var event_feed: EventFeed = $Root/EventFeed
@onready var ship_markers: ShipMarkers = $Root/ShipMarkers
@onready var minimap: Minimap = $Root/Minimap

var solar_system: SolarSystem
var camera: RTSCamera
var manager: BuildingManager
var placement: PlacementController
var zone_placement: ZonePlacement
var selection: SelectionController
var view_manager: ViewManager
## Built in code (bottom right, like the other panels).
var zone_panel: ZonePanel
## Built in code: the selected planet or moon (planet raids).
var planet_panel: PlanetPanel
## Built in code: the selected jump gate (explore contracts).
var gate_panel: GatePanel
## Built in code: the pilot list under the minimap.
var pilots: PilotColumn
## Built in code: posted contracts, bottom left above the event feed.
var contracts: ContractStrip
## Built in code: the first-time tutorial and its card (top left, right of
## the left panel).
var tutorial: Tutorial
var tutorial_card: TutorialCard
## Built in code: the full-screen cluster map (M), on top of everything.
var cluster_map: ClusterMap
## Built in code: the credit log (L), a centred overlay above the build bar.
var ledger: LedgerPanel

## Width of the right column (minimap, pilot list, selection panels).
const RIGHT_WIDTH := 380.0
const EDGE := 12.0
const GAP := 8.0
const SCROLLBAR_ROOM := 12.0
var _layout_left := 0.0


func _ready() -> void:
	add_to_group(GROUP)
	var tree := get_tree()
	solar_system = SolarSystem.of(self)
	camera = RTSCamera.of(self)
	manager = BuildingManager.of(SystemWorld.home(tree))
	view_manager = ViewManager.of(tree)
	placement = tree.get_first_node_in_group(PlacementController.GROUP) as PlacementController
	zone_placement = tree.get_first_node_in_group(ZonePlacement.GROUP) as ZonePlacement
	selection = tree.get_first_node_in_group(SelectionController.GROUP) as SelectionController
	zone_panel = ZonePanel.new()
	zone_panel.name = "ZonePanel"
	$Root.add_child(zone_panel)
	$Root.move_child(zone_panel, belt_panel.get_index() + 1)
	zone_panel.anchor_left = 1.0
	zone_panel.anchor_top = 1.0
	zone_panel.anchor_right = 1.0
	zone_panel.anchor_bottom = 1.0
	zone_panel.offset_left = -392.0
	zone_panel.offset_top = -12.0
	zone_panel.offset_right = -12.0
	zone_panel.offset_bottom = -12.0
	zone_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	zone_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	planet_panel = PlanetPanel.new()
	planet_panel.name = "PlanetPanel"
	$Root.add_child(planet_panel)
	$Root.move_child(planet_panel, zone_panel.get_index() + 1)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		planet_panel.set_anchor(side, 1.0)
	planet_panel.offset_left = -392.0
	planet_panel.offset_top = -12.0
	planet_panel.offset_right = -12.0
	planet_panel.offset_bottom = -12.0
	planet_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	planet_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	gate_panel = GatePanel.new()
	gate_panel.name = "GatePanel"
	$Root.add_child(gate_panel)
	$Root.move_child(gate_panel, planet_panel.get_index() + 1)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		gate_panel.set_anchor(side, 1.0)
	gate_panel.offset_left = -392.0
	gate_panel.offset_top = -12.0
	gate_panel.offset_right = -12.0
	gate_panel.offset_bottom = -12.0
	gate_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	gate_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pilots = PilotColumn.new()
	pilots.name = "Pilots"
	$Root.add_child(pilots)
	$Root.move_child(pilots, minimap.get_index() + 1)
	minimap.custom_minimum_size.x = RIGHT_WIDTH
	contracts = ContractStrip.new()
	contracts.name = "Contracts"
	$Root.add_child(contracts)
	$Root.move_child(contracts, event_feed.get_index())
	tutorial = Tutorial.new()
	tutorial.name = "Tutorial"
	add_child(tutorial)
	tutorial_card = TutorialCard.new()
	tutorial_card.name = "TutorialCard"
	$Root.add_child(tutorial_card)
	$Root.move_child(tutorial_card, overview.get_index() + 1)
	tutorial_card.position = Vector2(overview.position.x + overview.panel_width + EDGE, overview.position.y)
	UIUtil.no_focus($Root)
	overview.setup(self)
	build_menu.setup(self)
	building_panel.setup(self)
	belt_panel.setup(self)
	zone_panel.setup(self)
	planet_panel.setup(self)
	gate_panel.setup(self)
	captain_panel.setup(self)
	target_panel.setup(self)
	event_feed.setup(self)
	ship_markers.setup(self)
	minimap.setup(self, ship_markers)
	pilots.setup(self)
	top_bar.home_pressed.connect(fly_home)
	top_bar.system_menu_opening.connect(_fill_system_menu)
	top_bar.system_picked.connect(func(id: StringName) -> void:
		if view_manager:
			view_manager.view(id))
	if view_manager:
		view_manager.view_changed.connect(_on_view_changed)
	top_bar.research_pressed.connect(select_lab)
	contracts.setup(self)
	ledger = LedgerPanel.new()
	ledger.name = "Ledger"
	$Root.add_child(ledger)
	ledger.setup(self)
	top_bar.ledger_pressed.connect(ledger.toggle)
	cluster_map = ClusterMap.new()
	cluster_map.name = "ClusterMap"
	$Root.add_child(cluster_map)
	cluster_map.setup(self)
	top_bar.map_pressed.connect(cluster_map.toggle)
	tutorial.setup(self)
	tutorial_card.setup(self, tutorial)
	get_viewport().size_changed.connect(_layout_right)
	_layout_right.call_deferred()
	if selection:
		selection.selection_changed.connect(func(t: Node3D) -> void:
			marker.select_target = t if (t is Building or t is Ship or t is ScavengerDen or t is ScrapField) else null)


func _process(delta: float) -> void:
	_layout_left -= delta
	if _layout_left <= 0.0:
		_layout_left = 0.1
		_layout_right()
		_layout_bottom_left()


## The bottom-right selection panels (the Factory and Science Lab panels once they exist).
func selection_panels() -> Array[PanelContainer]:
	var out: Array[PanelContainer] = [building_panel, belt_panel, captain_panel, target_panel, zone_panel, planet_panel, gate_panel]
	if building_panel and is_instance_valid(building_panel.factory_panel) and building_panel.factory_panel.is_inside_tree():
		out.append(building_panel.factory_panel)
	if building_panel and is_instance_valid(building_panel.lab_panel) and building_panel.lab_panel.is_inside_tree():
		out.append(building_panel.lab_panel)
	return out


## Minimap on top, the pilot list under it down to the open selection
## panel (or the screen bottom); the panel is capped to the room left under
## the pilot list's title row and scrolls inside.
func _layout_right() -> void:
	var root := $Root as Control
	var vp := root.size
	var top := minimap.position.y + minimap.size.y + GAP
	var bottom := vp.y - EDGE
	var open_panel: PanelContainer = null
	for p in selection_panels():
		if p == null:
			continue
		var sc := _panel_scroll(p)
		var content := sc.get_child(0) as Control if sc.get_child_count() > 0 else null
		if content == null:
			continue
		var sb := p.get_theme_stylebox(&"panel")
		var chrome := sb.get_minimum_size().y if sb else 0.0
		var room := bottom - top - pilots.header_height() - GAP - chrome
		var want := content.get_combined_minimum_size().y
		var h := clampf(want, 40.0, maxf(room, 40.0))
		if absf(sc.custom_minimum_size.y - h) > 0.5:
			sc.custom_minimum_size.y = h
		var scrolls := want > h + 0.5
		sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if scrolls else ScrollContainer.SCROLL_MODE_DISABLED
		# Room for the scroll bar so the content keeps its width.
		var w := content.get_combined_minimum_size().x + (SCROLLBAR_ROOM if scrolls else 0.0)
		if absf(sc.custom_minimum_size.x - w) > 0.5:
			sc.custom_minimum_size.x = w
		if p.visible:
			open_panel = p
	var col_bottom := bottom
	if open_panel:
		col_bottom = open_panel.get_global_rect().position.y - root.get_global_rect().position.y - GAP
	pilots.place(Rect2(Vector2(vp.x - EDGE - RIGHT_WIDTH, top), Vector2(RIGHT_WIDTH, maxf(col_bottom - top, 0.0))))


## Bottom left: the event feed at the bottom (room for its full height kept,
## so nothing jumps), the contract list above it, the left panel above both.
func _layout_bottom_left() -> void:
	var root := $Root as Control
	var vp := root.size
	var feed_h := float(event_feed.max_visible) * 28.0
	var bottom := vp.y - EDGE - feed_h - GAP
	var used := 0.0
	if contracts.visible:
		var h := contracts.get_combined_minimum_size().y
		contracts.position = Vector2(EDGE, bottom - h)
		contracts.size = Vector2(contracts.width, h)
		used = h + GAP
	var margin := vp.y - bottom + used + 4.0
	if absf(overview.bottom_margin - margin) > 0.5:
		overview.bottom_margin = margin
		overview._fit_height()


## The ScrollContainer around a selection panel's content (made on first use).
func _panel_scroll(p: PanelContainer) -> ScrollContainer:
	if p.has_meta(&"hud_scroll"):
		return p.get_meta(&"hud_scroll") as ScrollContainer
	var sc := ScrollContainer.new()
	sc.name = "FitScroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.focus_mode = Control.FOCUS_NONE
	var kids := p.get_children()
	for k in kids:
		p.remove_child(k)
		sc.add_child(k)
	p.add_child(sc)
	p.set_meta(&"hud_scroll", sc)
	return sc


## Mouse events over a panel must never reach the map, even when the control
## under the cursor did not accept them (a list that cannot scroll lets the
## wheel through). The HUD sits after the world controllers in the tree, so it
## sees unhandled input first.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton or event is InputEventGesture):
		return
	var mb := event as InputEventMouseButton
	if mb and not mb.pressed:
		return
	if get_viewport().gui_get_hovered_control() != null:
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.physical_keycode == KEY_TAB:
		overview.toggle()
		get_viewport().set_input_as_handled()
	elif k and k.pressed and not k.echo and k.physical_keycode == KEY_H and not (k.ctrl_pressed or k.meta_pressed or k.alt_pressed):
		fly_home()
		get_viewport().set_input_as_handled()
	elif k and k.pressed and not k.echo and k.physical_keycode == KEY_M and not (k.ctrl_pressed or k.meta_pressed or k.alt_pressed):
		cluster_map.toggle()
		get_viewport().set_input_as_handled()
	elif k and k.pressed and not k.echo and k.physical_keycode == KEY_L and not (k.ctrl_pressed or k.meta_pressed or k.alt_pressed):
		ledger.toggle()
		get_viewport().set_input_as_handled()


## Flies the camera to the home station and follows it (its focus distance),
## like a double click on it.
## Selects the Science Lab (the top bar's research box).
func select_lab() -> void:
	var lab := ScienceLab.find(self)
	if lab and selection:
		selection.select(lab.building)


func fly_home() -> void:
	if not is_home_view():
		view_manager.view_home()
		return
	if camera and solar_system and is_instance_valid(solar_system.home_station):
		camera.focus_on(solar_system.home_station)


# --- Views ----------------------------------------------------------------------

## Home is on screen (or there is no view switch).
func is_home_view() -> bool:
	return view_manager == null or view_manager.viewed == null or view_manager.viewed == view_manager.home


## The viewed system's buildings (null outside home).
func local_manager() -> BuildingManager:
	return manager if is_home_view() else null


## Camera to [param n] (its focus distance, or [param distance]); first
## switches the view to the system [param n] is in. False when it cannot.
func focus(n: Node3D, distance: float = -1.0) -> bool:
	if not is_instance_valid(n) or not n.is_inside_tree():
		return false
	if not show_system_of(n):
		return false
	if camera == null:
		return false
	if distance > 0.0:
		camera.focus_on(n, distance)
	else:
		camera.focus_on(n)
	return true


## Switches the view at once to the live system [param n] is in.
func show_system_of(n: Node) -> bool:
	var w := n.get_viewport().get_meta(SystemWorld.META) as SystemWorld if n.get_viewport().has_meta(SystemWorld.META) else null
	if w == null or view_manager == null or w == view_manager.viewed:
		return true
	return view_manager.view_now(w.system_id) == w


func _fill_system_menu() -> void:
	if view_manager == null:
		return
	var items := []
	for id in view_manager.viewable_ids():
		var note := ""
		if id != ClusterNetwork.HOME_ID:
			# "danger ? (2 jumps out)" or "danger 3 · seen 12 min ago".
			note = Sector.danger_text(id)
		items.append({"id": id, "name": view_manager.system_name(id), "note": note, "current": id == view_manager.viewed_id()})
	top_bar.set_system_list(items)


func _on_view_changed(w: SystemWorld) -> void:
	if not is_instance_valid(w):
		return
	solar_system = w.sys
	camera = w.camera
	var home := is_home_view()
	if placement and not home:
		placement.cancel()
	if zone_placement and not home:
		zone_placement.cancel()
	build_menu.visible = home
	if solar_system and solar_system.system_def:
		top_bar.set_system_name(solar_system.system_def.system_name)
	view_rebound.emit(w)

class_name HUD
extends CanvasLayer
## Game HUD root. Finds the world-side controllers by group and hands itself
## to each widget. Tab toggles the system overview; H (or the top bar's
## HOME button) flies the camera to the home station;
## M cycles the ship markers (see [ShipMarkers]).
## Right column: the minimap, under it the pilot list ([PilotColumn]), and
## the selection panels at the bottom. [method _layout_right] keeps them
## apart: an open selection panel is capped to the room under the minimap
## (its content scrolls) and the pilot list ends above it.

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
## Built in code (bottom right, like the other panels).
var zone_panel: ZonePanel
## Built in code: the pilot list under the minimap.
var pilots: PilotColumn
## Built in code: posted contracts, bottom left above the event feed.
var contracts: ContractStrip

## Width of the right column (minimap, pilot list, selection panels).
const RIGHT_WIDTH := 380.0
const EDGE := 12.0
const GAP := 8.0
const SCROLLBAR_ROOM := 12.0
var _layout_left := 0.0


func _ready() -> void:
	add_to_group(GROUP)
	var tree := get_tree()
	solar_system = tree.get_first_node_in_group(SolarSystem.GROUP) as SolarSystem
	camera = tree.get_first_node_in_group("rts_camera") as RTSCamera
	manager = tree.get_first_node_in_group(BuildingManager.GROUP) as BuildingManager
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
	pilots = PilotColumn.new()
	pilots.name = "Pilots"
	$Root.add_child(pilots)
	$Root.move_child(pilots, minimap.get_index() + 1)
	minimap.custom_minimum_size.x = RIGHT_WIDTH
	contracts = ContractStrip.new()
	contracts.name = "Contracts"
	$Root.add_child(contracts)
	$Root.move_child(contracts, event_feed.get_index())
	UIUtil.no_focus($Root)
	overview.setup(self)
	build_menu.setup(self)
	building_panel.setup(self)
	belt_panel.setup(self)
	zone_panel.setup(self)
	captain_panel.setup(self)
	target_panel.setup(self)
	event_feed.setup(self)
	ship_markers.setup(self)
	minimap.setup(self, ship_markers)
	pilots.setup(self)
	top_bar.home_pressed.connect(fly_home)
	contracts.setup(self)
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


## The bottom-right selection panels (the Factory panel once it exists).
func selection_panels() -> Array[PanelContainer]:
	var out: Array[PanelContainer] = [building_panel, belt_panel, captain_panel, target_panel, zone_panel]
	if building_panel and is_instance_valid(building_panel.factory_panel) and building_panel.factory_panel.is_inside_tree():
		out.append(building_panel.factory_panel)
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


## Flies the camera to the home station and follows it (its focus distance),
## like a double click on it.
func fly_home() -> void:
	if camera and solar_system and is_instance_valid(solar_system.home_station):
		camera.focus_on(solar_system.home_station)

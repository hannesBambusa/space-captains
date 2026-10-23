class_name HUD
extends CanvasLayer
## Game HUD root. Finds the world-side controllers by group and hands itself
## to each widget. Tab toggles the system overview;
## M cycles the ship markers (see [ShipMarkers]).

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
var selection: SelectionController


func _ready() -> void:
	add_to_group(GROUP)
	var tree := get_tree()
	solar_system = tree.get_first_node_in_group(SolarSystem.GROUP) as SolarSystem
	camera = tree.get_first_node_in_group("rts_camera") as RTSCamera
	manager = tree.get_first_node_in_group(BuildingManager.GROUP) as BuildingManager
	placement = tree.get_first_node_in_group(PlacementController.GROUP) as PlacementController
	selection = tree.get_first_node_in_group(SelectionController.GROUP) as SelectionController
	UIUtil.no_focus($Root)
	overview.setup(self)
	build_menu.setup(self)
	building_panel.setup(self)
	belt_panel.setup(self)
	captain_panel.setup(self)
	target_panel.setup(self)
	event_feed.setup(self)
	ship_markers.setup(self)
	minimap.setup(self, ship_markers)
	if selection:
		selection.selection_changed.connect(func(t: Node3D) -> void:
			marker.select_target = t if (t is Building or t is Ship or t is ScavengerDen or t is ScrapField) else null)


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

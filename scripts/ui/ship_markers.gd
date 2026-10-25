class_name ShipMarkers
extends Control
## Always-on screen overlay for ships and Scavenger Dens: one constant-size
## icon per ship (shape by role, colour by faction), turned to the screen
## heading of its velocity, with a status glyph (mining, cargo, fighting,
## fleeing, escorting, spooling or in a warp hop), a hull pip when damaged
## and a short name label.
## Labels fade with zoom and are decluttered; the selected, followed and
## hovered ship always keep theirs. Icons fade out once the real model is
## big on screen. Parked ships are hidden and counted in a "n docked" badge
## on their outpost. Hostiles near the home station and the selected ship get
## an arrow at the screen edge with their distance while off screen.
## A base being announced (DenArrivalSite) shows as a pulsing faded den
## icon labelled "Arriving m:ss".
##
## Clicking a marker selects it and the camera follows; hovering shows a
## compact tooltip. M (or the minimap button) cycles the density:
## all, hostiles plus selected, off. The choice lasts for the session.
## Mercenary fleets: a thin gold link from each wingman to its leader and a
## small badge with the fleet size on the leader's marker.
## Height hint: a faint drop line from the ship down (or up) to its
## reference plane (the station's plane near home, else the main plane)
## with a small ground dot, for the selected, followed and hovered ship,
## and for every ship once zoomed out past [member drop_line_zoom].
## One _draw for everything; per frame it only unprojects positions.

signal mode_changed(mode: Mode)

enum Mode { ALL, HOSTILES, OFF }
enum Shape { MINER, MERCENARY, SALVAGER, POD, SCAVENGER, DEN, SHUTTLE, LANDER }
enum Glyph { NONE, MINING, CARGO, FIGHT, FLEE, ESCORT, WARP }

const MODE_NAMES: PackedStringArray = ["All", "Hostiles", "Off"]
## Captain ships wear the role colour of the pilot list (HudStyle.ROLE_COLORS).
const MINER_COLOR: Color = HudStyle.ROLE_COLORS["Miner"]
const MERC_COLOR: Color = HudStyle.ROLE_COLORS["Mercenary"]
const SALVAGER_COLOR: Color = HudStyle.ROLE_COLORS["Salvager"]
const LANDER_COLOR: Color = HudStyle.ROLE_COLORS["Lander"]
const POD_COLOR := Color(0.95, 0.97, 1.0)
## Cargo shuttles: small and neutral, so they do not crowd the captains.
const SHUTTLE_COLOR := Color(0.7, 0.73, 0.78)
const SCAVENGER_COLOR := Color(1.0, 0.32, 0.24)
const RAIDER_COLOR := Color(1.0, 0.55, 0.2)
const DEN_COLOR := Color(1.0, 0.3, 0.24)
const SELECT_COLOR := Color(1.0, 0.62, 0.26)
const SHADOW := Color(0.0, 0.0, 0.0, 0.6)
const FLEET_COLOR := Color(1.0, 0.85, 0.42)
const GLYPH_COLORS: Array[Color] = [
	Color.WHITE, Color(0.85, 0.92, 1.0), Color(1.0, 0.84, 0.42), Color(1.0, 0.5, 0.36), Color(1.0, 0.86, 0.25), Color(0.5, 0.95, 1.0),
	Color(0.7, 0.88, 1.0),
]

## Session memory of the density mode (survives scene reloads).
static var session_mode: Mode = Mode.ALL

@export var icon_px: float = 8.0
@export var den_icon_px: float = 11.0
@export var label_font_size: int = 13
## Labels are fully shown below this camera distance and gone above the
## second value, metres (the selected, followed and hovered ship always).
@export var label_fade: Vector2 = Vector2(6000.0, 12000.0)
## The icon fades out while the model's diameter on screen grows through
## this range, pixels.
@export var model_fade_px: Vector2 = Vector2(30.0, 52.0)
## Hostiles within this distance of the home station get edge arrows, metres.
@export var home_threat_radius: float = 5000.0
@export var edge_margin_px: float = 30.0
@export var hover_px: float = 13.0
@export var click_slop_px: float = 4.0
## Drop lines for every ship beyond this camera distance, metres (closer:
## only the selected, followed and hovered ship).
@export var drop_line_zoom: float = 5000.0
## Ships closer than this to their reference plane get no drop line, metres.
@export var drop_line_min_height: float = 12.0
## Near the station (flat distance) the reference plane is the station's, metres.
@export var station_plane_radius: float = 3500.0

var hud: HUD
var mode: Mode = Mode.ALL

## Live marker data, pooled: rebuilt in place every frame.
var _entries: Array[Entry] = []
var _count := 0
var _badges: Array[Dictionary] = []
var _arrows: Array[Dictionary] = []
## Fleet links this frame: {from, to, alpha}; badges: {pos, count, alpha}.
var _fleet_links: Array[Dictionary] = []
var _fleet_badges: Array[Dictionary] = []
var _hover: Entry
var _hover_target: Node3D
var _press_pos := Vector2.INF
var _press_target: Node3D
var _tooltip: PanelContainer
var _tooltip_label: Label
var _tooltip_timer := 0.0
var _font: Font
var _px_per_rad := 1.0
var _zoomed_out := false


class Entry:
	var target: Node3D
	var ship: Ship
	var pos := Vector2.ZERO
	var heading := 0.0
	var shape: Shape = Shape.MINER
	var color := Color.WHITE
	var alpha := 1.0
	var glyph: Glyph = Glyph.NONE
	var hull := 1.0
	var label := ""
	var label_alpha := 0.0
	var label_rect := Rect2()
	var show_label := false
	var model_px := 0.0
	var hostile := false
	var emphasis := false
	var priority := 0
	## Screen point of the drop line's foot (INF = no line).
	var drop := Vector2.INF


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mode = session_mode
	_tooltip = PanelContainer.new()
	_tooltip.name = "Tooltip"
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.visible = false
	_tooltip_label = UIUtil.label("")
	_tooltip_label.add_theme_font_size_override("font_size", 13)
	_tooltip.add_child(_tooltip_label)
	add_child(_tooltip)


func setup(owner_hud: HUD) -> void:
	hud = owner_hud


func set_mode(m: Mode) -> void:
	mode = m
	session_mode = m
	mode_changed.emit(m)
	queue_redraw()


func cycle_mode() -> void:
	set_mode(((int(mode) + 1) % MODE_NAMES.size()) as Mode)


func get_mode_name() -> String:
	return MODE_NAMES[mode]


## Live entries this frame (for tools and tests).
func marker_targets() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for i in _count:
		out.append(_entries[i].target)
	return out


## Screen position of [param target]'s marker, or Vector2.INF.
func marker_position(target: Node3D) -> Vector2:
	for i in _count:
		if _entries[i].target == target:
			return _entries[i].pos
	return Vector2.INF


## Targets that have an edge arrow this frame.
func arrow_targets() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for a in _arrows:
		out.append(a["target"] as Node3D)
	return out


## Role colour of the pilot list for captain ships, hostiles in their
## faction's colour (scavengers red, their raiders orange).
static func color_for(n: Node3D) -> Color:
	if n is ScavengerDen:
		return (n as ScavengerDen).faction_def.color
	if n is DenArrivalSite:
		return (n as DenArrivalSite).faction_def.color
	if n is ScavengerShip:
		var f := (n as ScavengerShip).faction_def
		return f.raider_color if (n as ScavengerShip).is_raider else f.color
	var s := n as Ship
	if s == null:
		return Color.WHITE
	if s.is_hostile():
		return SCAVENGER_COLOR
	match s.role:
		Ship.Role.MINER:
			return MINER_COLOR
		Ship.Role.MERCENARY:
			return MERC_COLOR
		Ship.Role.SALVAGER:
			return SALVAGER_COLOR
		Ship.Role.LANDER:
			return LANDER_COLOR
		Ship.Role.SHUTTLE:
			return SHUTTLE_COLOR
	return POD_COLOR


## Short map name: captain name for ours, callsign for scavengers.
static func short_name(n: Node3D) -> String:
	if n is ScavengerShip:
		return (n as ScavengerShip).callsign
	if n is EscapePod:
		return "%s (pod)" % (n as Ship).get_display_name()
	if n is CargoShuttle:
		return "Shuttle"
	if n.has_method(&"get_display_name"):
		return String(n.call(&"get_display_name"))
	return String(n.name)


## A ship parked in its berth (no marker; counted on the outpost badge).
static func is_parked(s: Ship) -> bool:
	return s.is_docked() and s.mover != null and s.mover.path_done()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.physical_keycode == KEY_M:
		cycle_mode()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT or mode == Mode.OFF:
		return
	if mb.pressed:
		_press_pos = mb.position if not mb.double_click and not mb.alt_pressed else Vector2.INF
		_press_target = _pick(mb.position)
		return
	var target := _press_target
	var was_click := _press_pos != Vector2.INF and mb.position.distance_to(_press_pos) <= click_slop_px
	_press_pos = Vector2.INF
	_press_target = null
	if not was_click or not is_instance_valid(target) or (hud and hud.camera and hud.camera.is_orbiting()):
		return
	if _pick(mb.position) != target:
		return
	select_and_follow(target)
	get_viewport().set_input_as_handled()


func select_and_follow(target: Node3D) -> void:
	if hud == null or not is_instance_valid(target):
		return
	if hud.selection and not target is DenArrivalSite:
		hud.selection.select(target)
	if hud.camera:
		hud.camera.focus_on(target, hud.camera.get_distance())


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	_count = 0
	_badges.clear()
	_arrows.clear()
	_fleet_links.clear()
	_fleet_badges.clear()
	if cam == null or hud == null or mode == Mode.OFF:
		_set_hover(null)
		queue_redraw()
		return
	if _font == null:
		_font = get_theme_font(&"font", &"Label")
	var vp := get_viewport_rect()
	_px_per_rad = vp.size.y / (2.0 * tan(deg_to_rad(cam.fov) * 0.5))
	var dist := hud.camera.get_distance() if hud.camera else 3000.0
	var zoom_alpha := 1.0 - smoothstep(label_fade.x, label_fade.y, dist)
	var selected := hud.selection.selected if hud.selection else null
	var followed := hud.camera.get_follow_target() if hud.camera else null
	var home := _home_position()
	_zoomed_out = dist > drop_line_zoom
	var screen := vp.grow(20.0)
	for n in get_tree().get_nodes_in_group(Ship.GROUP):
		var s := n as Ship
		if s == null or s.dead or not s.is_inside_tree():
			continue
		var emphasis := s == selected or s == followed
		if mode == Mode.HOSTILES and not s.is_hostile() and not emphasis:
			continue
		if is_parked(s) and not emphasis:
			continue
		var p := s.global_position
		if s.is_hostile() and home != Vector3.INF and SpaceNav.flat_distance(p, home) < home_threat_radius:
			_maybe_arrow(cam, s, p, vp, screen, s == selected)
		elif s == selected:
			_maybe_arrow(cam, s, p, vp, screen, true)
		if cam.is_position_behind(p):
			continue
		var sp := cam.unproject_position(p)
		if not screen.has_point(sp):
			continue
		var e := _next_entry()
		_fill_ship(e, s, cam, sp, emphasis)
		_fill_drop(e, s, cam, p, home)
	if hud.solar_system:
		for d in hud.solar_system.dens:
			if not is_instance_valid(d) or d.dead or not d.is_inside_tree():
				continue
			var p := d.global_position
			if cam.is_position_behind(p):
				continue
			var sp := cam.unproject_position(p)
			if not screen.has_point(sp):
				continue
			var e := _next_entry()
			_fill_den(e, d, cam, sp, d == selected or d == followed)
		for n in get_tree().get_nodes_in_group(DenArrivalSite.GROUP):
			var site := n as DenArrivalSite
			if site == null or not site.is_inside_tree() or cam.is_position_behind(site.global_position):
				continue
			var sp := cam.unproject_position(site.global_position)
			if not screen.has_point(sp):
				continue
			_fill_site(_next_entry(), site, sp, site == followed)
	if mode == Mode.ALL and hud.manager:
		_collect_badges(cam, screen, zoom_alpha)
	if mode == Mode.ALL:
		_collect_fleets()
	_update_hover()
	_layout_labels(zoom_alpha)
	_update_tooltip(delta)
	queue_redraw()


## Links wingmen to their fleet leader; a size badge on the leader.
func _collect_fleets() -> void:
	var by_ship: Dictionary = {}
	for i in _count:
		if _entries[i].ship:
			by_ship[_entries[i].ship] = _entries[i]
	for i in _count:
		var e := _entries[i]
		var mb := e.ship.brain as MercenaryBrain if e.ship else null
		if mb == null or mb.fleet == null or mb.fleet.state == MercFleet.State.DONE:
			continue
		var f := mb.fleet
		if e.ship == f.leader:
			_fleet_badges.append({"pos": e.pos, "count": f.members.size(), "alpha": maxf(e.alpha, 0.6)})
		elif by_ship.has(f.leader):
			var le := by_ship[f.leader] as Entry
			_fleet_links.append({"from": e.pos, "to": le.pos, "alpha": maxf(minf(e.alpha, le.alpha), 0.35)})


func _next_entry() -> Entry:
	if _count >= _entries.size():
		_entries.append(Entry.new())
	var e := _entries[_count]
	_count += 1
	return e


func _fill_ship(e: Entry, s: Ship, cam: Camera3D, sp: Vector2, emphasis: bool) -> void:
	e.target = s
	e.ship = s
	e.pos = sp
	e.hostile = s.is_hostile()
	e.emphasis = emphasis
	e.color = color_for(s)
	e.shape = _shape_for(s)
	e.hull = s.hull_fraction()
	e.glyph = _glyph_for(s)
	e.label = short_name(s)
	var d := maxf(cam.global_position.distance_to(s.global_position), 1.0)
	e.model_px = 2.0 * float(s.get_meta(&"focus_radius", 14.0)) / d * _px_per_rad
	e.alpha = 1.0 - smoothstep(model_fade_px.x, model_fade_px.y, e.model_px)
	if s.is_docked():
		e.alpha *= 0.5
	e.heading = _screen_heading(s, cam, sp, d)
	e.priority = 0 if emphasis else (1 if e.hostile else 2)
	if s is CargoShuttle and not emphasis:
		e.priority = 3


## Foot of the height hint, when this ship gets one this frame.
func _fill_drop(e: Entry, s: Ship, cam: Camera3D, p: Vector3, home: Vector3) -> void:
	e.drop = Vector2.INF
	if not (e.emphasis or s == _hover_target or (_zoomed_out and not (s is CargoShuttle))) or s.is_docked():
		return
	var ref_y := 0.0
	if home != Vector3.INF and SpaceNav.flat_distance(p, home) < station_plane_radius:
		ref_y = home.y
	if absf(p.y - ref_y) < drop_line_min_height:
		return
	var foot := Vector3(p.x, ref_y, p.z)
	if cam.is_position_behind(foot):
		return
	e.drop = cam.unproject_position(foot)


func _fill_den(e: Entry, d: ScavengerDen, cam: Camera3D, sp: Vector2, emphasis: bool) -> void:
	e.target = d
	e.ship = null
	e.pos = sp
	e.hostile = true
	e.emphasis = emphasis
	e.color = d.faction_def.color
	e.shape = Shape.DEN
	e.hull = d.hull_fraction()
	e.glyph = Glyph.NONE
	e.label = d.get_display_name()
	var dist := maxf(cam.global_position.distance_to(d.global_position), 1.0)
	e.model_px = 2.0 * float(d.get_meta(&"focus_radius", 60.0)) / dist * _px_per_rad
	e.alpha = 1.0 - smoothstep(model_fade_px.x * 2.0, model_fade_px.y * 2.0, e.model_px)
	e.heading = 0.0
	e.priority = 0 if emphasis else 1


func _fill_site(e: Entry, site: DenArrivalSite, sp: Vector2, emphasis: bool) -> void:
	e.target = site
	e.ship = null
	e.pos = sp
	e.hostile = true
	e.emphasis = emphasis
	e.color = site.faction_def.color
	e.shape = Shape.DEN
	e.hull = 1.0
	e.glyph = Glyph.NONE
	e.label = "Arriving %s" % site.countdown_text()
	e.model_px = 0.0
	e.alpha = 0.45 + 0.3 * sin(Time.get_ticks_msec() * 0.004)
	e.heading = 0.0
	e.priority = 0


func _shape_for(s: Ship) -> Shape:
	if s is ScavengerShip:
		return Shape.SCAVENGER
	match s.role:
		Ship.Role.MERCENARY:
			return Shape.MERCENARY
		Ship.Role.SALVAGER:
			return Shape.SALVAGER
		Ship.Role.LANDER:
			return Shape.LANDER
		Ship.Role.POD:
			return Shape.POD
		Ship.Role.SHUTTLE:
			return Shape.SHUTTLE
	return Shape.MINER


func _glyph_for(s: Ship) -> Glyph:
	if s.mover and s.mover.warp_state != ShipMover.Warp.IDLE:
		return Glyph.WARP
	if s is ScavengerShip:
		var sc := s as ScavengerShip
		if sc.ai == null:
			return Glyph.NONE
		match sc.ai.state:
			ScavengerBrain.State.ATTACKING, ScavengerBrain.State.HUNTING, ScavengerBrain.State.RAIDING:
				return Glyph.FIGHT
			ScavengerBrain.State.FLEEING:
				return Glyph.FLEE
			ScavengerBrain.State.RETURNING:
				return Glyph.CARGO if sc.loot > 0.0 else Glyph.NONE
		return Glyph.NONE
	if s is CargoShuttle:
		return Glyph.CARGO if (s as CargoShuttle).cargo_total() > 0 else Glyph.NONE
	var br := s.brain
	if br == null:
		return Glyph.FLEE if s is EscapePod else Glyph.NONE
	match br.state:
		CaptainBrain.State.MINING:
			return Glyph.MINING
		CaptainBrain.State.FLEEING:
			return Glyph.FLEE
		CaptainBrain.State.ENGAGING, CaptainBrain.State.HUNTING:
			return Glyph.FIGHT
		CaptainBrain.State.ESCORTING:
			return Glyph.ESCORT
		CaptainBrain.State.RETURNING, CaptainBrain.State.DOCKING, CaptainBrain.State.UNLOADING:
			if br.trip and br.trip.loaded and br.trip.cargo > 0.05:
				return Glyph.CARGO
	return Glyph.NONE


## Screen angle of the ship's motion (nose up = 0), its nose when slow.
func _screen_heading(s: Ship, cam: Camera3D, sp: Vector2, d: float) -> float:
	var v := s.get_world_velocity()
	v.y = 0.0
	var dir := v / v.length() if v.length() > 3.0 else -s.global_basis.z
	var ahead := s.global_position + dir * d * 0.03
	if cam.is_position_behind(ahead):
		return 0.0
	var step := cam.unproject_position(ahead) - sp
	if step.length() < 0.01:
		return 0.0
	return step.angle() + PI * 0.5


func _home_position() -> Vector3:
	if hud.solar_system and is_instance_valid(hud.solar_system.home_station):
		return hud.solar_system.home_station.global_position
	return Vector3.INF


func _maybe_arrow(cam: Camera3D, target: Node3D, p: Vector3, vp: Rect2, screen: Rect2, is_selected: bool) -> void:
	var behind := cam.is_position_behind(p)
	var sp := cam.unproject_position(p)
	if not behind and screen.has_point(sp):
		return
	var area := _arrow_area(vp)
	var c := area.get_center()
	var dir: Vector2
	if behind:
		var local := cam.global_transform.affine_inverse() * p
		dir = Vector2(local.x, -local.y)
		if dir.length() < 0.001:
			dir = Vector2.DOWN
	else:
		dir = sp - c
	dir = dir.normalized()
	var half := area.size * 0.5
	var t := INF
	if absf(dir.x) > 1e-4:
		t = minf(t, half.x / absf(dir.x))
	if absf(dir.y) > 1e-4:
		t = minf(t, half.y / absf(dir.y))
	var from := hud.camera.global_position if hud.camera else cam.global_position
	_arrows.append({"target": target, "pos": c + dir * t, "dir": dir, "color": color_for(target),
			"km": SpaceNav.flat_distance(from, p) / 1000.0, "selected": is_selected})


## Screen area edge arrows sit on: the viewport, inset, right of the overview.
func _arrow_area(vp: Rect2) -> Rect2:
	var r := vp.grow(-edge_margin_px)
	if hud.overview and hud.overview.is_visible_in_tree():
		var o := hud.overview.get_global_rect()
		var left := o.end.x + edge_margin_px * 0.5
		if left < r.end.x - 200.0:
			r.size.x -= left - r.position.x
			r.position.x = left
	r.position.y += 40.0
	r.size.y -= 40.0
	return r


func _collect_badges(cam: Camera3D, screen: Rect2, zoom_alpha: float) -> void:
	if zoom_alpha < 0.02:
		return
	for b in hud.manager.buildings:
		if not is_instance_valid(b) or not b.is_inside_tree():
			continue
		var parked := 0
		for s in b.ships:
			if is_instance_valid(s) and not s.dead and is_parked(s):
				parked += 1
		if parked == 0:
			continue
		var p := b.global_position
		if cam.is_position_behind(p):
			continue
		var sp := cam.unproject_position(p)
		if not screen.has_point(sp):
			continue
		var d := maxf(cam.global_position.distance_to(p), 1.0)
		var r := minf(b.def.footprint_radius / d * _px_per_rad, 70.0)
		_badges.append({"target": b, "pos": sp + Vector2(0.0, r + 12.0), "text": "%d docked" % parked, "alpha": zoom_alpha})


# --- Hover, labels, tooltip ------------------------------------------------------

func _pick(at: Vector2) -> Node3D:
	if hud and get_viewport().gui_get_hovered_control() != null:
		return null
	var best: Node3D = null
	var best_d := INF
	for i in _count:
		var e := _entries[i]
		if e.alpha < 0.15 and not e.emphasis:
			continue
		var r := hover_px * (1.4 if e.shape == Shape.DEN else 1.0)
		var d := e.pos.distance_to(at)
		if (d <= r or (e.show_label and e.label_rect.has_point(at))) and d < best_d:
			best_d = d
			best = e.target
	if best == null:
		for b in _badges:
			var bp := b["pos"] as Vector2
			if absf(bp.x - at.x) < 34.0 and absf(bp.y - at.y) < 10.0:
				return b["target"] as Node3D
	return best


func _update_hover() -> void:
	var m := get_viewport().get_mouse_position()
	var t := _pick(m)
	var found: Entry = null
	if t:
		for i in _count:
			if _entries[i].target == t:
				found = _entries[i]
				break
	_hover = found
	_set_hover(t if found else null)


func _set_hover(t: Node3D) -> void:
	if t == _hover_target:
		return
	_hover_target = t
	_tooltip_timer = 0.0
	if t == null:
		_hover = null
		_tooltip.visible = false


func _layout_labels(zoom_alpha: float) -> void:
	var order: Array[Entry] = []
	for i in _count:
		var e := _entries[i]
		e.show_label = false
		var forced := e.emphasis or e == _hover or e.target is DenArrivalSite
		e.label_alpha = 1.0 if forced else zoom_alpha
		if e.label_alpha < 0.03 or e.label.is_empty():
			continue
		order.append(e)
	order.sort_custom(func(a: Entry, b: Entry) -> bool:
		var pa := -1 if a == _hover else a.priority
		var pb := -1 if b == _hover else b.priority
		return pa < pb if pa != pb else a.pos.y < b.pos.y)
	var placed: Array[Rect2] = []
	# Labels also keep off the other icons.
	var icons: Array[Rect2] = []
	for i in _count:
		var ie := _entries[i]
		var r := icon_px + 3.0
		icons.append(Rect2(ie.pos - Vector2(r, r), Vector2(r, r) * 2.0) if ie.alpha > 0.15 else Rect2())
	for e in order:
		var w := _font.get_string_size(e.label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size).x if _font else 60.0
		var off := maxf(icon_px + 5.0, e.model_px * 0.4 + 4.0) if e.alpha < 0.5 else icon_px + 5.0
		if e.glyph != Glyph.NONE and e.alpha >= 0.5:
			off += 12.0
		var rect := Rect2(e.pos + Vector2(off, -9.0), Vector2(w + 4.0, 17.0))
		var clash := false
		if not (e.emphasis or e == _hover):
			for r in placed:
				if r.intersects(rect):
					clash = true
					break
			if not clash:
				for i in _count:
					if _entries[i] != e and icons[i].has_area() and icons[i].intersects(rect):
						clash = true
						break
		if clash:
			continue
		placed.append(rect)
		e.label_rect = rect
		e.show_label = true


func _update_tooltip(delta: float) -> void:
	if _hover == null or not is_instance_valid(_hover_target):
		_tooltip.visible = false
		return
	_tooltip_timer -= delta
	if _tooltip_timer <= 0.0 or not _tooltip.visible:
		_tooltip_timer = 0.25
		_tooltip_label.text = _tooltip_text(_hover_target)
		_tooltip.reset_size()
	_tooltip.visible = true
	var m := get_viewport().get_mouse_position()
	var sz := _tooltip.get_combined_minimum_size()
	var vp := get_viewport_rect().size
	var at := m + Vector2(18.0, 18.0)
	if at.x + sz.x > vp.x - 8.0:
		at.x = m.x - sz.x - 12.0
	if at.y + sz.y > vp.y - 8.0:
		at.y = m.y - sz.y - 12.0
	_tooltip.position = at


func _tooltip_text(t: Node3D) -> String:
	if t is DenArrivalSite:
		var a := t as DenArrivalSite
		return "%s\n%s ships gathering near %s\n%s" % [a.get_display_name(), a.faction_def.unit_name, a.def.belt_name, a.get_status_text()]
	if t is ScavengerDen:
		var d := t as ScavengerDen
		return "%s\n%s %s, %s\n%s\nHull %d%%" % [d.get_display_name(), d.faction_def.display_name, d.kind_name(), d.claim_text(), d.get_status_text(), roundi(d.hull_fraction() * 100.0)]
	if t is Building:
		var b := t as Building
		return "%s\n%s" % [b.display_name, b.get_status_text()]
	var s := t as Ship
	if s == null:
		return String(t.name)
	var lines: PackedStringArray = []
	if s is ScavengerShip:
		var sc := s as ScavengerShip
		lines.append(sc.get_display_name() + (" (raider)" if sc.is_raider else ""))
		lines.append("%s, %s" % [sc.faction_def.display_name, sc.den.get_display_name() if is_instance_valid(sc.den) else "no base"])
	else:
		lines.append(s.get_display_name())
		var role_line := s.get_role_name()
		if s.captain:
			role_line = "%s %s, %s" % [s.captain.get_rank_name(), s.get_role_name().to_lower(), s.captain.get_personality_name()]
		lines.append(role_line)
	lines.append(s.get_status_text())
	if s.durability:
		var hp := "Hull %d / %d" % [roundi(s.durability.hull), roundi(s.durability.max_hull)]
		if s.durability.max_shields > 0.0:
			hp += "   Shields %d / %d" % [roundi(s.durability.shields), roundi(s.durability.max_shields)]
		lines.append(hp)
	if s.brain and s.brain.trip and s.brain.trip.contract:
		lines.append("Contract: %s" % s.brain.trip.contract.get_title())
	var mb := s.brain as MercenaryBrain
	if mb and mb.fleet:
		lines.append("%s's fleet (%d), %s" % [mb.fleet.leader_name, mb.fleet.members.size(), mb.fleet.role_of(s)])
	return "\n".join(lines)


# --- Drawing --------------------------------------------------------------------

func _draw() -> void:
	if mode == Mode.OFF:
		return
	for l in _fleet_links:
		var a := float(l["alpha"])
		draw_line(l["from"] as Vector2, l["to"] as Vector2, Color(SHADOW, 0.5 * a), 3.0, true)
		draw_dashed_line(l["from"] as Vector2, l["to"] as Vector2, Color(FLEET_COLOR, 0.7 * a), 1.3, 5.0, true, true)
	for i in _count:
		_draw_drop(_entries[i])
	# Friendly first, hostiles over them, the emphasised ones on top.
	for pass_i in 3:
		for i in _count:
			var e := _entries[i]
			var layer := 2 if (e.emphasis or e == _hover) else (1 if e.hostile else 0)
			if layer == pass_i:
				_draw_entry(e)
	for b in _badges:
		_draw_badge(b)
	for fb in _fleet_badges:
		_draw_fleet_badge(fb)
	for a in _arrows:
		_draw_arrow(a)


## Faint height line and ground dot (under the icons).
func _draw_drop(e: Entry) -> void:
	if e.drop == Vector2.INF:
		return
	var strong := e.emphasis or e == _hover
	if not strong and not _zoomed_out:
		return
	var a := 0.55 if strong else 0.2
	var col := Color(e.color, a)
	draw_line(e.pos, e.drop, col, 1.0, true)
	draw_circle(e.drop, 2.6 if strong else 1.8, Color(SHADOW, 0.5 * a))
	draw_circle(e.drop, 1.6 if strong else 1.1, col)
	if strong:
		# A short tick across the foot reads as "on the plane".
		draw_line(e.drop + Vector2(-4.0, 0.0), e.drop + Vector2(4.0, 0.0), Color(e.color, a * 0.7), 1.0, true)


func _draw_entry(e: Entry) -> void:
	var hovered := e == _hover
	var a := e.alpha
	if hovered or e.emphasis:
		a = maxf(a, 0.35)
	if a > 0.02:
		var size := (den_icon_px if e.shape == Shape.DEN else icon_px) * (1.2 if (e.emphasis or hovered) else 1.0)
		_draw_icon(e.shape, e.pos, e.heading, size, e.color, a)
		if e.emphasis:
			draw_arc(e.pos, size * 1.75, 0.0, TAU, 32, Color(SELECT_COLOR, 0.9 * a), 1.5, true)
		if e.hull < 0.5:
			var pip := Color(1.0, 0.6, 0.15) if e.hull >= 0.25 else Color(1.0, 0.2, 0.15)
			var pp := e.pos + Vector2(-size - 2.0, size * 0.6)
			draw_circle(pp, 3.2, Color(SHADOW, 0.8 * a))
			draw_circle(pp, 2.3, Color(pip, a))
		if e.glyph != Glyph.NONE:
			_draw_glyph(e.glyph, e.pos + Vector2(size + 7.0, 0.0), a)
	if e.show_label and _font:
		var la := e.label_alpha * (1.0 if (hovered or e.emphasis) else 0.85)
		var col := e.color.lerp(Color.WHITE, 0.45)
		if e.emphasis:
			col = SELECT_COLOR.lerp(Color.WHITE, 0.25)
		var base := e.label_rect.position + Vector2(2.0, 13.0)
		draw_string_outline(_font, base, e.label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size, 4, Color(0.0, 0.0, 0.0, 0.75 * la))
		draw_string(_font, base, e.label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size, Color(col, la))


func _draw_icon(shape: Shape, c: Vector2, heading: float, s: float, color: Color, a: float) -> void:
	if shape == Shape.POD:
		draw_circle(c, s * 0.75, Color(SHADOW, SHADOW.a * a))
		draw_circle(c, s * 0.5, Color(color, 0.95 * a))
		var tip := c + Vector2.UP.rotated(heading) * s * 1.05
		draw_line(c + Vector2.UP.rotated(heading) * s * 0.5, tip, Color(color, a), 1.5, true)
		return
	if shape == Shape.DEN:
		var oct := _ngon(c, s, 8, PI / 8.0)
		draw_colored_polygon(_ngon(c, s * 1.3, 8, PI / 8.0), Color(SHADOW, SHADOW.a * a))
		draw_colored_polygon(oct, Color(color, 0.35 * a))
		oct.append(oct[0])
		draw_polyline(oct, Color(color, a), 1.6, true)
		draw_arc(c, s * 0.42, 0.0, TAU, 20, Color(color, a), 1.6, true)
		return
	var pts := _shape_points(shape)
	var outer := PackedVector2Array()
	var poly := PackedVector2Array()
	var rot := Transform2D(heading, c)
	for p in pts:
		poly.append(rot * (p * s))
		outer.append(rot * (p * s * 1.4))
	draw_colored_polygon(outer, Color(SHADOW, SHADOW.a * a))
	draw_colored_polygon(poly, Color(color, 0.92 * a))
	poly.append(poly[0])
	draw_polyline(poly, Color(color.lerp(Color.WHITE, 0.5), a), 1.0, true)
	if shape == Shape.SALVAGER:
		draw_circle(c, s * 0.22, Color(0.0, 0.0, 0.0, 0.7 * a))


static func _shape_points(shape: Shape) -> PackedVector2Array:
	match shape:
		Shape.MERCENARY:
			return PackedVector2Array([Vector2(0.0, -1.15), Vector2(0.8, 0.85), Vector2(0.0, 0.4), Vector2(-0.8, 0.85)])
		Shape.SALVAGER:
			return PackedVector2Array([Vector2(0.0, -1.1), Vector2(0.8, 0.0), Vector2(0.0, 1.0), Vector2(-0.8, 0.0)])
		Shape.LANDER:
			# Wide dropship: short nose, broad wings.
			return PackedVector2Array([Vector2(0.0, -1.0), Vector2(0.45, -0.55), Vector2(0.95, 0.75), Vector2(0.3, 0.55), Vector2(-0.3, 0.55), Vector2(-0.95, 0.75), Vector2(-0.45, -0.55)])
		Shape.SHUTTLE:
			# Small box with a blunt nose.
			return PackedVector2Array([Vector2(0.0, -0.75), Vector2(0.5, -0.45), Vector2(0.5, 0.6), Vector2(-0.5, 0.6), Vector2(-0.5, -0.45)])
		Shape.SCAVENGER:
			return PackedVector2Array([Vector2(0.0, -1.15), Vector2(0.95, 0.9), Vector2(0.4, 0.55), Vector2(0.0, 0.95), Vector2(-0.4, 0.55), Vector2(-0.95, 0.9)])
	# Miner: blunt hauler.
	return PackedVector2Array([Vector2(0.0, -1.0), Vector2(0.72, -0.35), Vector2(0.72, 0.85), Vector2(-0.72, 0.85), Vector2(-0.72, -0.35)])


static func _ngon(c: Vector2, r: float, n: int, phase: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		out.append(c + Vector2.from_angle(phase + TAU * float(i) / float(n)) * r)
	return out


func _draw_glyph(g: Glyph, c: Vector2, a: float) -> void:
	var col := Color(GLYPH_COLORS[g], a)
	var sh := Color(0.0, 0.0, 0.0, 0.65 * a)
	draw_circle(c, 6.5, sh)
	match g:
		Glyph.MINING:
			draw_polyline(PackedVector2Array([c + Vector2(-4.5, -1.5), c + Vector2(-1.0, -4.2), c + Vector2(2.5, -4.5), c + Vector2(4.5, -2.5)]), col, 1.6, true)
			draw_line(c + Vector2(0.5, -4.2), c + Vector2(-3.0, 4.5), col, 1.6, true)
		Glyph.CARGO:
			draw_rect(Rect2(c - Vector2(4.0, 3.0), Vector2(8.0, 6.0)), col, true)
			draw_line(c + Vector2(-4.0, -0.5), c + Vector2(4.0, -0.5), sh, 1.0, true)
		Glyph.FIGHT:
			draw_arc(c, 3.6, 0.0, TAU, 16, col, 1.3, true)
			for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				draw_line(c + d * 2.0, c + d * 5.5, col, 1.3, true)
		Glyph.FLEE:
			draw_line(c + Vector2(0.0, -4.8), c + Vector2(0.0, 1.2), col, 2.2, true)
			draw_circle(c + Vector2(0.0, 3.9), 1.3, col)
		Glyph.ESCORT:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-4.0, -4.5), c + Vector2(4.0, -4.5), c + Vector2(4.0, 0.0), c + Vector2(0.0, 5.0), c + Vector2(-4.0, 0.0)]), col)
		Glyph.WARP:
			for k in 2:
				var x := -3.5 + 4.0 * float(k)
				draw_polyline(PackedVector2Array([c + Vector2(x, -4.0), c + Vector2(x + 3.0, 0.0), c + Vector2(x, 4.0)]), col, 1.6, true)


func _draw_badge(b: Dictionary) -> void:
	if _font == null:
		return
	var text := String(b["text"])
	var a := float(b["alpha"])
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var p := b["pos"] as Vector2
	var r := Rect2(p - Vector2(w * 0.5 + 6.0, 8.0), Vector2(w + 12.0, 16.0))
	draw_rect(r, Color(0.04, 0.07, 0.1, 0.75 * a), true)
	draw_rect(r, Color(MINER_COLOR, 0.5 * a), false, 1.0)
	draw_string(_font, Vector2(r.position.x + 6.0, p.y + 4.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.82, 0.92, 1.0, a))


## Small gold tag above-left of a fleet leader: chevron and member count.
func _draw_fleet_badge(b: Dictionary) -> void:
	var a := float(b["alpha"])
	var c := (b["pos"] as Vector2) + Vector2(-icon_px - 9.0, -icon_px - 7.0)
	var r := Rect2(c - Vector2(9.0, 7.0), Vector2(18.0, 14.0))
	draw_rect(r.grow(1.0), Color(SHADOW, 0.8 * a), true)
	draw_rect(r, Color(0.12, 0.09, 0.02, 0.85 * a), true)
	draw_rect(r, Color(FLEET_COLOR, a), false, 1.0)
	draw_polyline(PackedVector2Array([c + Vector2(-6.0, 2.0), c + Vector2(-3.5, -2.5), c + Vector2(-1.0, 2.0)]), Color(FLEET_COLOR, a), 1.4, true)
	if _font:
		draw_string(_font, c + Vector2(0.5, 4.5), str(int(b["count"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(FLEET_COLOR, a))


func _draw_arrow(a: Dictionary) -> void:
	var p := a["pos"] as Vector2
	var dir := a["dir"] as Vector2
	var col := a["color"] as Color
	var sel := bool(a["selected"])
	if sel:
		col = SELECT_COLOR
	var side := dir.orthogonal()
	var tip := p + dir * 9.0
	var tri := PackedVector2Array([tip, p - dir * 5.0 + side * 7.0, p - dir * 2.0, p - dir * 5.0 - side * 7.0])
	var shadow := PackedVector2Array()
	for q in tri:
		shadow.append(p + (q - p) * 1.35)
	draw_colored_polygon(shadow, SHADOW)
	draw_colored_polygon(tri, Color(col, 0.95))
	if _font:
		var text := "%.1f km" % float(a["km"])
		var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var tp := p - dir * 22.0 - Vector2(w * 0.5, -4.0)
		draw_string_outline(_font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 4, Color(0.0, 0.0, 0.0, 0.75))
		draw_string(_font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col.lerp(Color.WHITE, 0.35))

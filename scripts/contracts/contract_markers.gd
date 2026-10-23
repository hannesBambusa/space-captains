class_name ContractMarkers
extends Node3D
## Holographic beacons for posted contracts: one per contract target (belt),
## at the contract site (for belts: the stretch nearest the home station,
## so it slides along the ring as the station orbits). Each beacon has a
## constant-size label (visible at every zoom), a pulsing ring and a light
## pillar for closer views. Beacons are focusable; clicking one selects its
## belt (meta "belt").

const GROUP := "contract_markers"
const HOLO := Color(0.4, 0.88, 1.0)
const BOUNTY_COLOR := Color(1.0, 0.3, 0.24)
const ESCORT_COLOR := Color(0.45, 0.95, 1.0)
const SALVAGE_COLOR := Color(1.0, 0.72, 0.35)
## Icon size on screen ~ texture px * this * px per radian.
const ICON_PIXEL_SIZE := 0.0006

@export var ring_radius_factor: float = 0.32
@export var pillar_height: float = 160.0

## target (Node3D) -> marker Node3D
var _markers: Dictionary = {}
var _system: SolarSystem
## Shields over miners flying escorted mining trips: miner -> Sprite3D.
var _escort_icons: Dictionary = {}
var _icon_timer := 0.0


func _ready() -> void:
	add_to_group(GROUP)
	ContractBoard.contract_posted.connect(func(_c: Contract) -> void: _refresh())
	ContractBoard.contract_changed.connect(func(_c: Contract) -> void: _refresh())
	ContractBoard.contract_removed.connect(func(_c: Contract) -> void: _refresh())
	_refresh()


func _process(delta: float) -> void:
	_icon_timer -= delta
	if _icon_timer <= 0.0:
		_icon_timer = 0.25
		_update_escort_icons()
	for miner in _escort_icons.keys():
		if not is_instance_valid(miner):
			continue
		(_escort_icons[miner] as Node3D).global_position = (miner as Node3D).global_position + Vector3(0.0, 4.0, 0.0)
	if _markers.is_empty():
		return
	var from := _reference_point()
	var t := Time.get_ticks_msec() * 0.001
	if not is_inside_tree():
		return
	for target in _markers.keys():
		if not is_instance_valid(target) or not (target as Node3D).is_inside_tree():
			continue
		var m := _markers[target] as Node3D
		var cs := ContractBoard.get_for_target(target as Node)
		if cs.is_empty():
			continue
		if not (target is SystemBelt):
			m.global_position = (target as Node3D).global_position + Vector3(0.0, 3.0, 0.0)
			var icon := m.get_node_or_null(^"Icon") as Sprite3D
			if icon:
				icon.pixel_size = ICON_PIXEL_SIZE * (1.0 + 0.08 * sin(t * 4.0))
			continue
		var site := cs[0].get_site_position(from)
		m.global_position = Vector3(site.x, 0.0, site.z)
		var ring := m.get_node_or_null(^"Ring") as Node3D
		if ring:
			var k := fposmod(t * 0.35, 1.0)
			ring.scale = Vector3.ONE * lerpf(0.55, 1.0, k)
			RingUtil.set_color(ring as MeshInstance3D, Color(HOLO, 0.9 * (1.0 - k)))


## The beacon for [param contract]'s target, or null.
func get_marker(contract: Contract) -> Node3D:
	if contract == null or not is_instance_valid(contract.target):
		return null
	return _markers.get(contract.target) as Node3D


## Shield icon over [param miner] (escorted mining trip), or null.
func get_escort_icon(miner: Node) -> Node3D:
	return _escort_icons.get(miner) as Node3D


func _update_escort_icons() -> void:
	var want: Dictionary = {}
	for c in ContractBoard.get_listed():
		var e := c as EscortContract
		if e and e.is_linked():
			for m in e.covered_miners():
				want[m] = true
	for miner in _escort_icons.keys():
		if not is_instance_valid(miner) or not want.has(miner):
			(_escort_icons[miner] as Node3D).queue_free()
			_escort_icons.erase(miner)
	for miner: Ship in want:
		if not _escort_icons.has(miner):
			var icon := _make_icon(IconTextures.shield(), ESCORT_COLOR)
			icon.pixel_size = ICON_PIXEL_SIZE * 0.7
			add_child(icon)
			_escort_icons[miner] = icon


func _reference_point() -> Vector3:
	if _system == null:
		_system = get_tree().get_first_node_in_group(SolarSystem.GROUP) as SolarSystem
	if _system and _system.home_station:
		return _system.home_station.global_position
	return Vector3.ZERO


func _refresh() -> void:
	var by_target: Dictionary = {}
	for c in ContractBoard.get_listed():
		if is_instance_valid(c.target):
			if not by_target.has(c.target):
				by_target[c.target] = []
			(by_target[c.target] as Array).append(c)
	for target in _markers.keys():
		if not is_instance_valid(target) or not by_target.has(target):
			(_markers[target] as Node3D).queue_free()
			_markers.erase(target)
	for target: Node3D in by_target:
		var m := _markers.get(target) as Node3D
		if m == null:
			m = _make_marker(target) if target is SystemBelt else _make_icon_marker(target, by_target[target][0] as Contract)
			_markers[target] = m
		var lines: PackedStringArray = []
		for c: Contract in by_target[target]:
			var line := "%s  %s" % [c.get_type_name().to_upper(), c.get_reward_text()]
			if not c.takers.is_empty():
				line += "  ·  %d on it" % c.takers.size()
			lines.append(line)
		(m.get_node(^"Label") as Label3D).text = "\n".join(lines)
	_process(0.0)


## Screen-size icon (billboard, always on top).
func _make_icon(tex: Texture2D, color: Color) -> Sprite3D:
	var icon := Sprite3D.new()
	icon.name = "Icon"
	icon.texture = tex
	icon.modulate = Color(color * 1.4, 0.95)
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.fixed_size = true
	icon.pixel_size = ICON_PIXEL_SIZE
	icon.no_depth_test = true
	icon.shaded = false
	icon.double_sided = true
	icon.render_priority = 12
	icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	icon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return icon


## Beacon for a ship, den or scrap field target: reticle (bounty), shield
## (escort) or claw (salvage) and a label, following the target.
func _make_icon_marker(target: Node3D, first: Contract) -> Node3D:
	var bounty := first is BountyContract
	var salvage := first is SalvageContract
	var color := BOUNTY_COLOR if bounty else (SALVAGE_COLOR if salvage else ESCORT_COLOR)
	var m := Node3D.new()
	m.name = "Contract_%s" % String(target.name)
	m.set_meta(&"focus_radius", 40.0)
	m.set_meta(&"focus_distance", 520.0 if target is ScavengerDen else 220.0)
	add_child(m)
	var icon := _make_icon(IconTextures.reticle() if bounty else (IconTextures.salvage() if salvage else IconTextures.shield()), color)
	if target is ScavengerDen:
		icon.pixel_size = ICON_PIXEL_SIZE * 1.3
	m.add_child(icon)
	var l := Label3D.new()
	l.name = "Label"
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0004
	l.font_size = 24
	l.outline_size = 8
	l.modulate = Color(color.lerp(Color.WHITE, 0.25), 0.95)
	l.outline_modulate = Color(0.08, 0.0, 0.0, 0.7)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l.no_depth_test = true
	l.shaded = false
	l.double_sided = true
	l.render_priority = 11
	l.outline_render_priority = 10
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.offset = Vector2(0.0, 70.0)
	m.add_child(l)
	return m


func _make_marker(target: Node3D) -> Node3D:
	var m := Node3D.new()
	m.name = "Contract_%s" % String(target.name)
	var width := 900.0
	if target is SystemBelt:
		m.set_meta(&"belt", target)
		width = (target as SystemBelt).def.width
	m.set_meta(&"focus_radius", width * 0.3)
	m.set_meta(&"focus_distance", width * 2.0)
	m.add_to_group(RTSCamera.FOCUS_GROUP)
	add_child(m)

	var ring := RingUtil.make_ring(width * ring_radius_factor, HOLO, 2.0, 128)
	ring.name = "Ring"
	ring.position.y = 1.0
	m.add_child(ring)
	var inner := RingUtil.make_ring(width * ring_radius_factor * 0.25, Color(HOLO, 0.8), 1.6, 64)
	inner.name = "Inner"
	inner.position.y = 1.0
	m.add_child(inner)

	var pillar := MeshInstance3D.new()
	pillar.name = "Pillar"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.5
	cyl.bottom_radius = 4.0
	cyl.height = pillar_height
	cyl.radial_segments = 12
	cyl.cap_top = false
	cyl.cap_bottom = false
	pillar.mesh = cyl
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	pm.albedo_color = Color(HOLO * 1.6, 0.35)
	pillar.material_override = pm
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pillar.position.y = pillar_height * 0.5
	m.add_child(pillar)

	var l := Label3D.new()
	l.name = "Label"
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0004
	l.font_size = 26
	l.outline_size = 8
	l.modulate = Color(HOLO, 0.95)
	l.outline_modulate = Color(0.0, 0.05, 0.1, 0.7)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l.no_depth_test = true
	l.shaded = false
	l.double_sided = true
	l.render_priority = 11
	l.outline_render_priority = 10
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.position.y = 2.0
	l.offset = Vector2(0.0, 70.0)
	m.add_child(l)
	return m

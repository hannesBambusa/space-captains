class_name DefenseZone
extends Node3D
## One defence zone the player placed (see [DefenseZones]): a centre, a
## radius and an optional kill bounty paid from a reserved budget for every
## raider killed inside. Mercenaries on patrol roam inside it and engage
## raiders that enter it.
## Anchored zones ([member anchored]) sit in the station's Structures frame
## and move with it; the others stay fixed in space (over a belt, a lane).
## Look: a faint translucent disc with a thin rim (shaders/defense_zone),
## cyan without a kill bounty, gold with one; it pulses red while raiders
## are inside ([member raiders_inside]) and brightens when selected.
## Membership is on the plane (flat distance), like every other range check.

signal changed(zone: DefenseZone)

const SHADER: Shader = preload("res://shaders/defense_zone.gdshader")
const PLAIN_COLOR := Color(0.4, 0.85, 1.0)
const BOUNTY_COLOR := Color(1.0, 0.8, 0.35)
## Pick radius of the centre marker on screen, pixels.
const CENTER_PICK_PX := 18.0

## Stable id within the game (saves, mercenary patrol targets).
var uid: int = 0
var zone_name: String = "Picket"
var radius: float = 1500.0
## Credits per raider killed inside (0 = none).
var kill_bounty: int = 0
## Credits reserved for the kill bounty (escrow), what is left of it.
var budget: int = 0
## Raiders killed inside while it paid, and what it paid out.
var kills: int = 0
var paid_total: int = 0
## Moves with the station (child of its Structures frame).
var anchored: bool = true
var placed_at: float = 0.0
## Hostile ships inside right now (DefenseZones updates it).
var raiders_inside: int = 0
## The "budget is spent" line was posted for the current budget.
var spent_noted: bool = false

var _mesh: MeshInstance3D
var _mat: ShaderMaterial
var _label: Label3D
var _selected := false


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mesh = MeshInstance3D.new()
	_mesh.name = "Disc"
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_label = Label3D.new()
	_label.name = "Label"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = true
	_label.pixel_size = 0.0006
	_label.font_size = 24
	_label.outline_size = 8
	_label.no_depth_test = true
	_label.shaded = false
	_label.position = Vector3(0.0, 30.0, 0.0)
	add_child(_label)
	set_meta(&"focus_radius", 60.0)
	refresh_look()


func _process(_delta: float) -> void:
	if _mat:
		_mat.set_shader_parameter("time_s", SimClock.time)


## Flat distance check: is [param p] (world) inside the zone?
func contains(p: Vector3) -> bool:
	return Combat.flat_distance(p, global_position) <= radius


## Hostile ships inside the zone (and [param margin] metres past its edge), nearest the centre first.
func hostiles_inside(margin: float = 0.0) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if not is_inside_tree():
		return out
	for h in Combat.hostiles_near(get_tree(), global_position, radius + margin, Combat.Faction.PLAYER):
		if h is Ship:
			out.append(h)
	return out


## A random point inside the zone at [param min_share]..[param max_share]
## of the radius, world space, on the zone's plane.
func random_point(rng: RandomNumberGenerator, min_share: float = 0.15, max_share: float = 0.85) -> Vector3:
	var a := rng.randf() * TAU
	var r := radius * sqrt(rng.randf_range(min_share * min_share, max_share * max_share))
	return global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)


## Velocity of the zone's frame (anchored zones ride the station).
func frame_velocity() -> Vector3:
	return SpaceNav.world_velocity(self) if anchored else Vector3.ZERO


func has_paying_bounty() -> bool:
	return kill_bounty > 0 and budget > 0


## Kills the budget still pays for in full.
func kills_left() -> int:
	return floori(float(budget) / float(kill_bounty)) if kill_bounty > 0 else 0


func set_selected(on: bool) -> void:
	_selected = on
	refresh_look()


func is_selected() -> bool:
	return _selected


## Applies the radius, colour, alert and label.
func refresh_look() -> void:
	if _mesh == null:
		return
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE * radius * 2.0
	_mesh.mesh = quad
	_mesh.custom_aabb = AABB(Vector3(-radius, -5.0, -radius), Vector3(radius * 2.0, 10.0, radius * 2.0))
	var c := BOUNTY_COLOR if kill_bounty > 0 else PLAIN_COLOR
	_mat.set_shader_parameter("zone_color", c)
	_mat.set_shader_parameter("radius", radius)
	_mat.set_shader_parameter("highlight", 1.0 if _selected else 0.0)
	_mat.set_shader_parameter("alert", 1.0 if raiders_inside > 0 else 0.0)
	_label.text = zone_name + ("  %d cr/kill" % kill_bounty if kill_bounty > 0 else "")
	_label.modulate = Color(c, 0.95 if _selected else 0.7)
	_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.7)


func get_display_name() -> String:
	return zone_name


# --- Save ---------------------------------------------------------------------

func save_state() -> Dictionary:
	var d := SaveUtil.props(self, ["uid", "zone_name", "radius", "kill_bounty", "budget", "kills", "paid_total", "anchored", "placed_at", "spent_noted"])
	# Anchored: offset in the Structures frame; fixed: world position.
	d["pos"] = position if anchored else global_position
	return d


func load_state(d: Dictionary) -> void:
	var fields := d.duplicate()
	fields.erase("pos")
	SaveUtil.apply_props(self, fields)

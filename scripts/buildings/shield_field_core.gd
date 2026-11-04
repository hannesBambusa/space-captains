class_name ShieldFieldCore
extends Node3D
## The Shield Generator's animated force-field core: a shimmering hex-lattice
## orb ([constant FIELD_RADIUS]) in the emitter cradle plus a flat quad of
## pulse rings on its equator (shaders/shield_field_core and
## shield_field_ring). Child of the [Building], not of its model: the
## construction look and the drones walk every mesh under the model.
## Placed at the model's "shield_emitter_point" empty (building space).
##
## Driven per frame by [ShieldGenerator] through [method update_look] from
## the bubble's state: hidden until the generator is active; RAISING grows
## it in, UP holds steady with a gentle pulse (pulses run faster while the
## bubble recharges), COLLAPSING swells, breaks up and flickers out, DOWN is
## off with a faint sputter that quickens near the re-raise. A bubble hit
## flashes it for a moment. Look only: no sim state, nothing saved.

const ORB_SHADER: Shader = preload("res://shaders/shield_field_core.gdshader")
const RING_SHADER: Shader = preload("res://shaders/shield_field_ring.gdshader")
const FIELD_RADIUS := 4.0
## Half the side of the ring quad, m (pulses fade out before it).
const RING_OUTER := 9.5
## Sputter in the last seconds of the cooldown.
const SPUTTER_LEAD := 8.0
const HIT_FLASH_DECAY := 6.0

var _orb: MeshInstance3D
var _ring: MeshInstance3D
var _orb_mat: ShaderMaterial
var _ring_mat: ShaderMaterial
var _state := -1
var _state_since := 0.0
## Shown presence 0..1 (eases toward the state's target in sim time).
var _presence := 0.0


## Call before adding to [param building]: places the core at
## [param emitter] (a node of its model), building space.
func setup(building: Building, emitter: Node3D) -> void:
	name = "ShieldFieldCore"
	position = ModelLoader.relative_transform(building, emitter).origin


func _ready() -> void:
	_orb_mat = ShaderMaterial.new()
	_orb_mat.shader = ORB_SHADER
	_orb_mat.set_shader_parameter("radius", FIELD_RADIUS)
	var sphere := SphereMesh.new()
	sphere.radius = FIELD_RADIUS
	sphere.height = FIELD_RADIUS * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	_orb = _make_mesh("Orb", sphere, _orb_mat)
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = RING_SHADER
	_ring_mat.set_shader_parameter("outer", RING_OUTER)
	_ring_mat.set_shader_parameter("inner", FIELD_RADIUS)
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE * RING_OUTER * 2.0
	_ring = _make_mesh("Rings", quad, _ring_mat)
	visible = false


## [param shield] may be null (no bubble); [param active]: the generator is
## built and alive. [param delta] is real time.
func update_look(shield: StationShield, active: bool, shown_charge: float, delta: float) -> void:
	if not active or not is_instance_valid(shield):
		visible = false
		_presence = 0.0
		_state = -1
		return
	var st: int = shield.state
	if st != _state:
		_state = st
		_state_since = SimClock.time
	var dt := 0.0 if SimClock.paused else delta * SimClock.speed
	var age := SimClock.time - _state_since
	var fade := 0.0
	var dissolve := 0.0
	var collapsing := 0.0
	var swell := 1.0
	var flicker := 0.0
	var k := clampf(shown_charge, 0.0, 1.0)
	match st:
		StationShield.State.RAISING:
			_presence = move_toward(_presence, 1.0, dt / maxf(shield.raise_time, 0.1))
			fade = minf(_presence * 1.6, 1.0)
			dissolve = 1.0 - _presence
			swell = lerpf(0.25, 1.0, ease(_presence, 0.4))
		StationShield.State.UP:
			_presence = move_toward(_presence, 1.0, dt / maxf(shield.raise_time, 0.1))
			fade = _presence * (0.92 + 0.08 * sin(SimClock.time * 1.6))
			dissolve = 1.0 - _presence
			if k < shield.low_fraction:
				flicker = 1.0 - k / shield.low_fraction
		StationShield.State.COLLAPSING:
			var t := clampf(age / maxf(shield.collapse_time, 0.1), 0.0, 1.0)
			_presence = 1.0 - t
			# A bright burst first, then it breaks up and swells out.
			fade = (1.0 - t) * (1.0 + 1.4 * exp(-t * 10.0))
			dissolve = t
			collapsing = 1.0
			swell = 1.0 + 0.3 * ease(t, 0.5)
			flicker = 1.0
		StationShield.State.DOWN:
			_presence = 0.0
			fade = _sputter(shield.cooldown_left)
			dissolve = 0.55
			swell = 0.6
			flicker = 1.0
		_:
			_presence = 0.0
	visible = fade > 0.002
	if not visible:
		return
	var hit := exp(-maxf(SimClock.time - shield.last_hit_time, 0.0) * HIT_FLASH_DECAY) if shield.is_up() else 0.0
	_orb.scale = Vector3.ONE * swell
	_ring.scale = Vector3.ONE * lerpf(0.6, 1.0, minf(swell, 1.0))
	var rate := 0.7 if shield.is_regenerating() else 0.4
	for m: ShaderMaterial in [_orb_mat, _ring_mat]:
		m.set_shader_parameter("sim_time", SimClock.time)
		m.set_shader_parameter("charge", k if shield.is_up() else 0.0)
		m.set_shader_parameter("fade", fade)
		m.set_shader_parameter("flicker", flicker)
		m.set_shader_parameter("hit_flash", hit)
	_orb_mat.set_shader_parameter("dissolve", dissolve)
	_orb_mat.set_shader_parameter("collapsing", collapsing)
	_ring_mat.set_shader_parameter("pulse_rate", rate)


## DOWN: short, faint sparks, more often as the re-raise nears.
func _sputter(cooldown_left: float) -> float:
	var near := 1.0 - clampf(cooldown_left / SPUTTER_LEAD, 0.0, 1.0)
	var slot := floorf(SimClock.time * 4.0)
	var roll := fposmod(sin(slot * 12.9898 + 4.1) * 43758.5453, 1.0)
	if roll < lerpf(0.94, 0.55, near):
		return 0.0
	var within := fposmod(SimClock.time * 4.0, 1.0)
	return lerpf(0.12, 0.35, near) * (1.0 - within)


func _make_mesh(node_name: String, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = Building.RENDER_LAYER
	add_child(mi)
	return mi

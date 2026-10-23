class_name OutpostUnloadFx
extends Node3D
## Mining Outpost unloading look (child of the [Building], building space).
## Building adds it when the model has an "unload_arm" node. It plays when a
## miner of this outpost delivers a load (ContractBoard.delivery_made, in
## the docking berth) for CaptainBrain.UNLOAD_TIME sim seconds:
## - unload_arm (pivot at its base) swings between the docked ship's hold
##   (rest) and the hopper (+[member arm_swing_deg] about local Y), a dust
##   puff at the hold on each grab, ore chunks falling from ore_flow_point
##   into the hopper on each drop, coloured by the ore type;
## - ore_conveyor_belt: its material (a copy per outpost) scrolls V down,
##   one repeat per [member belt_repeat_m], so ore runs toward the silos;
##   it keeps running [member belt_tail] seconds after the unload;
## - ore_silo_fill (origin at the silo floor, scale Y 1 = full) shows the
##   ore this outpost delivered recently: each load adds its units, the
##   level drains slowly toward the Factory ([member silo_drain_per_min]);
## - unload_lights: hidden while idle, blinking while unloading.
## Sim time only (SimClock speed; paused = frozen; SimStepper steps it). The chunks and puffs
## are a small pool of meshes, nothing is made per frame.

## Arm swing from the hold to the hopper, degrees about local Y.
@export var arm_swing_deg: float = 78.6
## Sim seconds per hold-to-hopper-and-back swing (fitted to the unload time).
@export var swing_period: float = 2.0
@export var belt_speed: float = 2.4
@export var belt_repeat_m: float = 4.8
@export var belt_tail: float = 4.0
## Silo: units for full, drain per sim minute (base plus a share of the level).
@export var silo_capacity: float = 80.0
@export var silo_drain_per_min: float = 4.0
@export var silo_drain_share: float = 0.08
@export var silo_start: float = 12.0
## Chunks per drop and dust bits per grab.
@export var chunks_per_drop: int = 5
@export var dust_per_grab: int = 3
@export var light_blink_hz: float = 1.6

## Belt ore colours (iron, titanium, crystal), crystal glows.
const ORE_TINTS: Array[Color] = [Color(0.46, 0.39, 0.33), Color(0.72, 0.78, 0.86), Color(0.3, 0.95, 0.88)]
const DUST_COLOR := Color(0.62, 0.56, 0.5, 0.55)
const GRAVITY := 14.0
const CHUNK_POOL := 24
const DUST_POOL := 9

var building: Building
## Telemetry for tests and tools.
var chunks_spawned: int = 0
var dust_spawned: int = 0
var unloads: int = 0
## Ore (Economy.Ore) of the load being unloaded.
var ore: int = 0
## 0..1 swing of the arm right now (0 = over the hold).
var swing: float = 0.0
var silo_amount: float = 0.0

var _arm: Node3D
var _arm_basis := Basis.IDENTITY
var _flow := Vector3.ZERO
var _hold := Vector3.ZERO
var _belt_mat: StandardMaterial3D
var _silo: Node3D
var _belt: MeshInstance3D
var _lights: MeshInstance3D
var _light_mat: StandardMaterial3D
var _light_base: float = 1.0
var _unload_left: float = 0.0
var _unload_time: float = 0.0
var _belt_left: float = 0.0
var _phase: float = 0.0
var _dropped := false
var _grabbed := false
var _rng := RandomNumberGenerator.new()
## Pool entries: {node: MeshInstance3D, mat, vel: Vector3, life, max_life, dust: bool}.
var _bits: Array[Dictionary] = []
var _chunk_mats: Array[StandardMaterial3D] = []


## Call after adding to the building; [param model] is the outpost model.
func setup(owner_building: Building, model: Node3D) -> void:
	building = owner_building
	_rng.seed = hash(building.name)
	_arm = model.find_child("unload_arm", true, false) as Node3D
	var flow := model.find_child("ore_flow_point", true, false) as Node3D
	var belt := model.find_child("ore_conveyor_belt", true, false) as MeshInstance3D
	_silo = model.find_child("ore_silo_fill", true, false) as Node3D
	_lights = model.find_child("unload_lights", true, false) as MeshInstance3D
	if _arm:
		_arm_basis = _arm.basis
	var pivot := ModelLoader.relative_transform(building, _arm).origin if _arm else Vector3.ZERO
	_flow = ModelLoader.relative_transform(building, flow).origin if flow else pivot
	# The grab at rest: the flow point swung back about the pivot.
	var off := _flow - pivot
	_hold = pivot + off.rotated(Vector3.UP, -deg_to_rad(arm_swing_deg)) + Vector3(0.0, -2.5, 0.0)
	_belt = belt
	if belt and belt.mesh and belt.mesh.get_surface_count() > 0:
		var src := _source_material(belt)
		if src:
			_belt_mat = src.duplicate() as StandardMaterial3D
	if _lights and _lights.mesh and _lights.mesh.get_surface_count() > 0:
		var src := _source_material(_lights)
		if src:
			_light_mat = src.duplicate() as StandardMaterial3D
			_light_base = maxf(src.emission_energy_multiplier, 0.5)
		_lights.visible = false
	_apply_materials()
	building.state_changed.connect(func(_b: Building) -> void: _apply_materials())
	silo_amount = silo_start
	add_to_group(SimStepper.GROUP)
	_make_pool()
	_apply_silo()
	ContractBoard.delivery_made.connect(_on_delivery)


## The single-surface material the model shows (dimmed copy included).
static func _source_material(mi: MeshInstance3D) -> StandardMaterial3D:
	var m := mi.get_surface_override_material(0) as StandardMaterial3D
	return m if m else mi.mesh.surface_get_material(0) as StandardMaterial3D


## Own copies go on as material_override (one surface each); the building's
## construction look replaces them and clears them when done, so this runs
## again on every state change.
func _apply_materials() -> void:
	if building.state != Building.State.ACTIVE:
		return
	if _belt and _belt_mat:
		_belt.material_override = _belt_mat
	if _lights and _light_mat:
		_lights.material_override = _light_mat


func _exit_tree() -> void:
	if ContractBoard.delivery_made.is_connected(_on_delivery):
		ContractBoard.delivery_made.disconnect(_on_delivery)


## True while a load is being unloaded.
func is_unloading() -> bool:
	return _unload_left > 0.0


func lights_visible() -> bool:
	return _lights != null and _lights.visible


func belt_offset() -> float:
	return _belt_mat.uv1_offset.y if _belt_mat else 0.0


func arm_angle_deg() -> float:
	return rad_to_deg(swing * deg_to_rad(arm_swing_deg))


## Starts (or extends) an unload of [param ore_type] (Economy.Ore) adding
## [param units] to the silo over [param duration] sim seconds.
func play_unload(ore_type: int, units: int, duration: float) -> void:
	ore = clampi(ore_type, 0, ORE_TINTS.size() - 1)
	if not is_unloading():
		_phase = 0.0
		_unload_time = 0.0
	_unload_left = maxf(_unload_left, duration)
	_unload_time = maxf(_unload_time, duration)
	# Whole swings that fit the unload.
	swing_period = _unload_time / maxf(roundf(_unload_time / 2.0), 1.0)
	_belt_left = _unload_left + belt_tail
	silo_amount = minf(silo_amount + float(units), silo_capacity * 1.15)
	unloads += 1
	if _lights:
		_lights.visible = true
	var cm := _chunk_mats[ore]
	for b in _bits:
		if not bool(b["dust"]):
			(b["node"] as MeshInstance3D).material_override = cm


func _on_delivery(contract: Contract, ship: Node, _credits: int, materials: int, belt_ore: int) -> void:
	var s := ship as Ship
	if not (contract is MiningContract) or s == null or s.home != building:
		return
	play_unload(Economy.ore_of_belt(belt_ore), materials, CaptainBrain.UNLOAD_TIME)


func _process(delta: float) -> void:
	if not SimClock.paused:
		sim_step(delta * SimClock.speed)


## One sim step (also driven by SimStepper fast-forwards).
func sim_step(dt: float) -> void:
	if building == null or dt <= 0.0:
		return
	_step_arm(dt)
	_step_belt(dt)
	_step_bits(dt)
	_step_silo(dt)
	_step_lights()


func _step_arm(dt: float) -> void:
	if not is_unloading():
		if swing > 0.0:
			swing = maxf(swing - dt * 1.2, 0.0)
			_apply_arm()
		return
	_unload_left -= dt
	_phase += dt / maxf(swing_period, 0.2)
	var k := fposmod(_phase, 1.0)
	swing = 0.5 - 0.5 * cos(TAU * k)
	# Drop at the top of the swing (over the hopper), grab at the bottom.
	if k >= 0.45 and k < 0.6 and not _dropped:
		_dropped = true
		_spawn_chunks()
	elif k < 0.45 or k >= 0.6:
		_dropped = false
	if (k < 0.08 or k > 0.95) and not _grabbed:
		_grabbed = true
		_spawn_dust()
	elif k >= 0.08 and k <= 0.95:
		_grabbed = false
	if _unload_left <= 0.0:
		_unload_left = 0.0
		swing = 0.0
		if _lights:
			_lights.visible = false
	_apply_arm()


func _apply_arm() -> void:
	if _arm:
		_arm.basis = _arm_basis * Basis(Vector3.UP, deg_to_rad(arm_swing_deg) * swing)


func _step_belt(dt: float) -> void:
	if _belt_left <= 0.0 or _belt_mat == null:
		return
	_belt_left -= dt
	# Ease out over the last second.
	var k := clampf(_belt_left, 0.0, 1.0) if _belt_left < 1.0 else 1.0
	var v := _belt_mat.uv1_offset
	v.y = fposmod(v.y - belt_speed / belt_repeat_m * dt * k, 1.0)
	_belt_mat.uv1_offset = v


func _step_silo(dt: float) -> void:
	if silo_amount <= 0.0:
		return
	silo_amount = maxf(silo_amount - (silo_drain_per_min + silo_drain_share * silo_amount) * dt / 60.0, 0.0)
	_apply_silo()


func _apply_silo() -> void:
	if _silo:
		_silo.scale = Vector3(1.0, clampf(silo_amount / silo_capacity, 0.03, 1.0), 1.0)


func _step_lights() -> void:
	if _lights == null or not _lights.visible:
		return
	# Double flash, like a rotating beacon passing twice.
	var t := fposmod(_unload_time - _unload_left, 1000.0) * light_blink_hz
	var k := fposmod(t, 1.0)
	var f := 1.0 if k < 0.18 else (0.25 if k < 0.3 else (0.9 if k < 0.42 else 0.2))
	if _light_mat:
		_light_mat.emission_energy_multiplier = _light_base * (0.6 + 2.2 * f)


# --- Chunks and dust ---------------------------------------------------------------

func _make_pool() -> void:
	for c in ORE_TINTS.size():
		var m := StandardMaterial3D.new()
		m.albedo_color = ORE_TINTS[c]
		m.roughness = 0.8
		m.metallic = 0.3 if c == 1 else 0.1
		if c == 2:
			m.emission_enabled = true
			m.emission = ORE_TINTS[c]
			m.emission_energy_multiplier = 2.5
		_chunk_mats.append(m)
	var chunk_mesh := BoxMesh.new()
	chunk_mesh.size = Vector3.ONE * 0.7
	var dust_mesh := SphereMesh.new()
	dust_mesh.radius = 1.0
	dust_mesh.height = 2.0
	dust_mesh.radial_segments = 8
	dust_mesh.rings = 4
	for i in CHUNK_POOL + DUST_POOL:
		var dust := i >= CHUNK_POOL
		var mi := MeshInstance3D.new()
		mi.name = ("Dust%d" if dust else "Chunk%d") % i
		mi.mesh = dust_mesh if dust else chunk_mesh
		mi.layers = Building.RENDER_LAYER
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		var mat: StandardMaterial3D = null
		if dust:
			mat = StandardMaterial3D.new()
			mat.albedo_color = DUST_COLOR
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mi.material_override = mat
		else:
			mi.material_override = _chunk_mats[0]
		add_child(mi)
		_bits.append({"node": mi, "mat": mat, "vel": Vector3.ZERO, "life": 0.0, "max_life": 1.0, "dust": dust})


func _free_bit(dust: bool) -> Dictionary:
	for b in _bits:
		if bool(b["dust"]) == dust and float(b["life"]) <= 0.0:
			return b
	return {}


func _spawn_chunks() -> void:
	for i in chunks_per_drop:
		var b := _free_bit(false)
		if b.is_empty():
			return
		var mi := b["node"] as MeshInstance3D
		mi.position = _flow + Vector3(_rng.randf_range(-0.8, 0.8), _rng.randf_range(-0.3, 0.4), _rng.randf_range(-0.8, 0.8))
		mi.rotation = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, 0.0)
		mi.scale = Vector3.ONE * _rng.randf_range(0.6, 1.3)
		mi.visible = true
		b["vel"] = Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-1.0, 0.5), _rng.randf_range(-0.6, 0.6))
		b["max_life"] = _rng.randf_range(0.7, 1.0)
		b["life"] = b["max_life"]
		chunks_spawned += 1


func _spawn_dust() -> void:
	for i in dust_per_grab:
		var b := _free_bit(true)
		if b.is_empty():
			return
		var mi := b["node"] as MeshInstance3D
		mi.position = _hold + Vector3(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-0.5, 0.5), _rng.randf_range(-1.5, 1.5))
		mi.scale = Vector3.ONE * 0.6
		mi.visible = true
		b["vel"] = Vector3(_rng.randf_range(-1.2, 1.2), _rng.randf_range(0.4, 1.4), _rng.randf_range(-1.2, 1.2))
		b["max_life"] = _rng.randf_range(1.0, 1.6)
		b["life"] = b["max_life"]
		dust_spawned += 1


func _step_bits(dt: float) -> void:
	for b in _bits:
		var life := float(b["life"])
		if life <= 0.0:
			continue
		life -= dt
		b["life"] = life
		var mi := b["node"] as MeshInstance3D
		if life <= 0.0:
			mi.visible = false
			continue
		var v := b["vel"] as Vector3
		var age := 1.0 - life / float(b["max_life"])
		if bool(b["dust"]):
			v *= maxf(1.0 - 1.5 * dt, 0.0)
			mi.scale = Vector3.ONE * lerpf(0.6, 2.6, age)
			(b["mat"] as StandardMaterial3D).albedo_color.a = DUST_COLOR.a * (1.0 - age)
		else:
			v.y -= GRAVITY * dt
			mi.rotate_x(dt * 3.0)
		b["vel"] = v
		mi.position += v * dt

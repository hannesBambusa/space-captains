class_name ScrapField
extends Node3D
## Debris left by a destroyed ship or den: a cloud of tumbling, glinting
## chunks (one MultiMesh, shaders/scrap.gdshader) holding [member amount]
## scrap. Fades out and frees itself after [member lifetime] sim seconds.
## Selectable and focusable; listed in the overview.
## Stage 3: salvagers on Salvage contracts call [method take]. While a
## salvage contract is open on it the field does not age; a stripped field
## fades out quickly. Den ruins also hold the den's stash ([method add_scrap]).

signal depleted(field: ScrapField)

const GROUP := "scrap_fields"
const SHADER: Shader = preload("res://shaders/scrap.gdshader")
## The last part of the life during which the chunks shrink away, seconds.
const FADE_TIME := 25.0
## Fresh wrecks glow for this long, seconds.
const HOT_TIME := 25.0
## Sim seconds between checks for an open salvage contract.
const CLAIM_CHECK := 1.0

var amount: int = 0
var initial_amount: int = 0
var lifetime: float = 180.0
var radius: float = 30.0
var display_name: String = "Scrap field"
var created_at: float = 0.0

var _age: float = 0.0
var _claimed := false
var _claim_timer := 0.0
var _mat: ShaderMaterial
var _mmi: MultiMeshInstance3D


func setup(scrap: int, life: float, field_radius: float, label: String) -> void:
	amount = scrap
	initial_amount = scrap
	lifetime = life
	radius = field_radius
	display_name = label
	name = StringName(("Scrap_%s" % label).validate_node_name().replace(" ", ""))


static func all(tree: SceneTree) -> Array[ScrapField]:
	var out: Array[ScrapField] = []
	for n in tree.get_nodes_in_group(GROUP):
		if n is ScrapField and not n.is_queued_for_deletion():
			out.append(n as ScrapField)
	return out


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(SimStepper.GROUP)
	created_at = SimClock.time
	set_meta(&"focus_radius", radius)
	set_meta(&"focus_distance", maxf(radius * 6.0, 220.0))
	add_to_group(RTSCamera.FOCUS_GROUP)
	_build()


func _process(delta: float) -> void:
	if not SimClock.paused:
		sim_step(delta * SimClock.speed)


func sim_step(dt: float) -> void:
	if dt <= 0.0 or is_queued_for_deletion():
		return
	_claim_timer -= dt
	if _claim_timer <= 0.0:
		_claim_timer = CLAIM_CHECK
		_claimed = amount > 0 and not ContractBoard.get_for_target(self).is_empty()
	if not _claimed:
		_age += dt
	var spread := 0.35 + 0.65 * (1.0 - exp(-_age * 1.6))
	if _mmi:
		_mmi.scale = Vector3(spread, 1.0, spread)
	if _mat:
		_mat.set_shader_parameter("fade", clampf((lifetime - _age) / FADE_TIME, 0.0, 1.0))
		_mat.set_shader_parameter("hot", clampf(1.0 - _age / HOT_TIME, 0.0, 1.0))
	if _age >= lifetime:
		queue_free()


func remaining_time() -> float:
	return maxf(lifetime - _age, 0.0)


func get_display_name() -> String:
	return display_name


func get_status_text() -> String:
	if _claimed:
		return "%d scrap, salvage contract" % amount
	return "%d scrap, fades in %s" % [amount, _clock(remaining_time())]


func is_claimed() -> bool:
	return _claimed


## Adds scrap (a den's stash spilling into its ruins).
func add_scrap(extra: int) -> void:
	amount += maxi(extra, 0)
	initial_amount += maxi(extra, 0)


## Removes up to [param want] scrap (stage 3 salvage). Returns what was taken.
func take(want: int) -> int:
	var got := mini(want, amount)
	amount -= got
	if amount <= 0 and got > 0:
		_claimed = false
		lifetime = minf(lifetime, _age + FADE_TIME)
		depleted.emit(self)
	return got


func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name) ^ int(SimClock.time * 1000.0)
	var n := clampi(int(radius * 0.9), 18, 120)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mm.mesh = box
	mm.instance_count = n
	for i in n:
		var a := rng.randf() * TAU
		var r := radius * sqrt(rng.randf())
		var p := Vector3(cos(a) * r, rng.randf_range(-4.0, 4.0), sin(a) * r)
		var s := rng.randf_range(0.6, 2.6) * (1.0 if radius < 60.0 else 1.8)
		if rng.randf() < 0.12:
			s *= 2.2
		var b := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU))
		b = b.scaled(Vector3(s * rng.randf_range(0.6, 1.6), s * rng.randf_range(0.2, 0.6), s * rng.randf_range(0.6, 1.4)))
		mm.set_instance_transform(i, Transform3D(b, p))
		var tint := [Color(1, 1, 1), Color(0.8, 0.62, 0.5), Color(0.6, 0.62, 0.56), Color(0.9, 0.9, 0.95)][rng.randi() % 4] as Color
		mm.set_instance_color(i, tint)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Chunks"
	_mmi.multimesh = mm
	_mmi.material_override = _mat
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.layers = 2
	_mmi.custom_aabb = AABB(Vector3(-radius - 10.0, -15.0, -radius - 10.0), Vector3(radius * 2.0 + 20.0, 30.0, radius * 2.0 + 20.0))
	add_child(_mmi)


static func _clock(t: float) -> String:
	var s := int(t)
	return "%d:%02d" % [floori(s / 60.0), s % 60]

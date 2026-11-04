extends Node3D
## Shield preview: the home station, a Shield Generator and the station bubble
## (shaders/station_shield.gdshader) plus the generator's field core
## (ShieldFieldCore), cycling through the bubble's states on a loop:
## offline -> raising -> up (hits come in, HP drains) -> low flicker ->
## collapse -> down (sputter) -> re-raise at 40% -> recharge -> again.
##
## Look only. No game systems run: the StationShield here is a plain object
## that is never added to the tree; this script sets its state, HP and hit
## time and drives the bubble material the way StationShield._update_look
## does. Timings come from StationShield's exports; only the down time is
## shortened (12 s instead of 45 s) so the loop stays watchable.
##
## Run: Godot --path . res://tools/shield_preview.tscn [-- --model=/abs/gen.glb] [--shot=/abs/out.png]
##      [--shot-after=<s>] (default 4.5 s) [--close] (frame the generator, not the bubble)
## Mouse: left drag orbit, right drag pan, wheel zoom. Keys: H hit, R restart,
## Space pause (SimClock), 1..4 sim speed (SimClock), F reset view, Q quit.

const FIELD_CORE := preload("res://scripts/buildings/shield_field_core.gd")
const STATION_GLB := "res://assets/models/station/station_home.glb"
const GEN_GLB := "res://assets/models/buildings/shield_generator.glb"
## Generator spot in the station frame, m (a typical slot in the complex).
const GEN_POS := Vector3(110.0, 0.0, 60.0)
const GEN_FOOTPRINT := 22.0
const DOWN_TIME := 12.0
const BG := Color(0.012, 0.016, 0.03)

enum Phase { OFFLINE, RAISING, UP_FULL, UNDER_FIRE, LOW, COLLAPSING, DOWN, RERAISE, RECHARGE }
const PHASE_LEN := {
	Phase.OFFLINE: 2.0, Phase.UP_FULL: 4.0, Phase.UNDER_FIRE: 7.0, Phase.LOW: 4.0,
	Phase.DOWN: DOWN_TIME, Phase.RECHARGE: 8.0,
}

var _shield: StationShield
var _core: Node3D
var _bubble: MeshInstance3D
var _mat: ShaderMaterial
var _impacts := PackedVector4Array()
var _next_impact := 0
var _anim := 0.0
var _phase := Phase.OFFLINE
var _phase_t := 0.0
var _next_hit := 0.0
var _rng := RandomNumberGenerator.new()
var _label: Label
var _shot := ""
var _shot_wait := 4.5

var _cam: Camera3D
var _yaw := -35.0
var _pitch := 32.0
var _dist := 620.0
var _focus := Vector3(30.0, 0.0, 20.0)
var _drag := 0


func _ready() -> void:
	_rng.seed = 7
	var gen_path := GEN_GLB
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--model="):
			gen_path = a.substr(8)
		elif a.begins_with("--shot="):
			_shot = a.substr(7)
		elif a.begins_with("--shot-after="):
			_shot_wait = float(a.substr(13))
		elif a == "--close":
			_focus = GEN_POS + Vector3(0.0, 16.0, 0.0)
			_dist = 85.0
			_pitch = 28.0
	_build_stage()
	var station := _load(STATION_GLB)
	if station:
		add_child(station)
	var gen_root := Node3D.new()
	gen_root.name = "Generator"
	gen_root.position = GEN_POS
	add_child(gen_root)
	var gen := _load(gen_path)
	if gen:
		gen_root.add_child(gen)
		_dim(gen, 0.35)
	print("SHIELD_PREVIEW station %s generator %s" % [station != null, gen != null])
	_shield = StationShield.new()
	_core = FIELD_CORE.new()
	var point := gen.find_child("shield_emitter_point", true, false) as Node3D if gen else null
	if point:
		_core.position = ModelLoader.relative_transform(gen_root, point).origin
	gen_root.add_child(_core)
	_build_bubble()
	_restart()


func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.7)
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	add_child(sun)
	_cam = Camera3D.new()
	_cam.far = 20000.0
	_cam.fov = 50.0
	add_child(_cam)
	_update_cam()
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_font_size_override("font_size", 18)
	layer.add_child(_label)
	var help := Label.new()
	help.text = "Left drag orbit · right drag pan · wheel zoom · H hit · R restart · Space pause · 1-4 speed · F reset · Q quit"
	help.position = Vector2(16, 40)
	help.modulate = Color(1, 1, 1, 0.6)
	layer.add_child(help)


func _build_bubble() -> void:
	_impacts.resize(StationShield.MAX_IMPACTS)
	for i in StationShield.MAX_IMPACTS:
		_impacts[i] = Vector4(0.0, 1.0, 0.0, -100.0)
	# Same fit rule as StationShield.refit: centre on the complex, cover the
	# outermost footprint plus the margin, never below min_radius.
	_shield.position = Vector3.ZERO
	_shield.radius = maxf(GEN_POS.length() + GEN_FOOTPRINT + _shield.margin, _shield.min_radius)
	_bubble = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	_bubble.mesh = sphere
	_mat = ShaderMaterial.new()
	_mat.shader = StationShield.SHADER
	_mat.set_shader_parameter("impacts", _impacts)
	_bubble.material_override = _mat
	_bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var r := _shield.radius
	_bubble.scale = Vector3(r, r * _shield.height_ratio, r)
	add_child(_bubble)


func _restart() -> void:
	_set_phase(Phase.OFFLINE)


func _set_phase(p: Phase) -> void:
	_phase = p
	_phase_t = 0.0
	var s := _shield
	match p:
		Phase.OFFLINE:
			s.state = StationShield.State.OFFLINE
			s.hp = 0.0
			_anim = 0.0
			s.last_hit_time = -INF
		Phase.RAISING:
			s.state = StationShield.State.RAISING
			s.hp = s.max_hp
			_anim = 0.0
		Phase.UP_FULL, Phase.UNDER_FIRE, Phase.LOW, Phase.RECHARGE:
			s.state = StationShield.State.UP
			_anim = 1.0
		Phase.COLLAPSING:
			s.state = StationShield.State.COLLAPSING
			s.hp = 0.0
			_anim = 1.0
		Phase.DOWN:
			s.state = StationShield.State.DOWN
			s.cooldown_left = DOWN_TIME
		Phase.RERAISE:
			s.state = StationShield.State.RAISING
			s.hp = s.max_hp * s.restore_fraction
			_anim = 0.0


func _process(delta: float) -> void:
	var dt := SimClock.frame_dt
	_phase_t += dt
	var s := _shield
	match _phase:
		Phase.RAISING, Phase.RERAISE:
			_anim = minf(_anim + dt / s.raise_time, 1.0)
			if _anim >= 1.0:
				_set_phase(Phase.UP_FULL if _phase == Phase.RAISING else Phase.RECHARGE)
		Phase.UNDER_FIRE:
			# Drain from full to just under the low-flicker line.
			s.hp = lerpf(s.max_hp, s.max_hp * s.low_fraction * 0.9, _phase_t / PHASE_LEN[_phase])
			_auto_hits(dt, 0.55)
		Phase.LOW:
			s.hp = maxf(s.hp - dt * 60.0, s.max_hp * 0.04)
			_auto_hits(dt, 0.35)
		Phase.COLLAPSING:
			_anim = maxf(_anim - dt / s.collapse_time, 0.0)
			if _anim <= 0.0:
				_set_phase(Phase.DOWN)
		Phase.DOWN:
			s.cooldown_left = maxf(s.cooldown_left - dt, 0.0)
		Phase.RECHARGE:
			if SimClock.time - s.last_hit_time >= s.regen_delay:
				s.hp = minf(s.hp + s.regen * 4.0 * dt, s.max_hp)
	if PHASE_LEN.has(_phase) and _phase_t >= PHASE_LEN[_phase]:
		_set_phase(_next_phase(_phase))
	_update_bubble()
	_core.update_look(s, true, s.hp / s.max_hp if s.is_up() else 0.0, delta)
	_label.text = "%s   HP %d / %d   bubble r %d m   sim %.1fx%s" % [
		Phase.keys()[_phase], int(s.hp), int(s.max_hp), int(s.radius), SimClock.speed,
		"  (paused)" if SimClock.paused else ""]
	if _shot != "":
		_shot_wait -= delta
		if _shot_wait <= 0.0:
			get_viewport().get_texture().get_image().save_png(_shot)
			print("SHIELD_PREVIEW shot ", _shot)
			get_tree().quit()


func _next_phase(p: Phase) -> Phase:
	match p:
		Phase.OFFLINE: return Phase.RAISING
		Phase.UP_FULL: return Phase.UNDER_FIRE
		Phase.UNDER_FIRE: return Phase.LOW
		Phase.LOW: return Phase.COLLAPSING
		Phase.DOWN: return Phase.RERAISE
		Phase.RECHARGE: return Phase.OFFLINE
	return p


func _auto_hits(dt: float, every: float) -> void:
	_next_hit -= dt
	if _next_hit <= 0.0:
		_next_hit = every * _rng.randf_range(0.5, 1.5)
		_hit()


## A tracer hit on the bubble from a random direction near the plane.
func _hit() -> void:
	if not _shield.is_up():
		return
	var a := _rng.randf() * TAU
	var y := _rng.randf_range(-0.25, 0.6)
	var u := Vector3(cos(a), y, sin(a)).normalized()
	_impacts[_next_impact] = Vector4(u.x, u.y, u.z, SimClock.time)
	_next_impact = (_next_impact + 1) % StationShield.MAX_IMPACTS
	_mat.set_shader_parameter("impacts", _impacts)
	_shield.last_hit_time = SimClock.time


## Mirrors StationShield._update_look.
func _update_bubble() -> void:
	var s := _shield
	var shown := s.state != StationShield.State.OFFLINE and s.state != StationShield.State.DOWN
	_bubble.visible = shown
	if not shown:
		return
	var k := clampf(s.hp / s.max_hp, 0.0, 1.0)
	_mat.set_shader_parameter("sim_time", SimClock.time)
	_mat.set_shader_parameter("charge", k)
	_mat.set_shader_parameter("radius", s.radius)
	_mat.set_shader_parameter("dissolve", 1.0 - _anim)
	_mat.set_shader_parameter("collapsing", 1.0 if s.state == StationShield.State.COLLAPSING else 0.0)
	var flick := 0.0
	if s.is_up() and k < s.low_fraction:
		flick = 1.0 - k / s.low_fraction
	_mat.set_shader_parameter("flicker", flick)
	var d := _cam.global_position.distance_to(_bubble.global_position)
	var near := smoothstep(s.radius * 0.8, s.radius * 2.2, d)
	var far := 1.0 - smoothstep(s.radius * 14.0, s.radius * 30.0, d)
	_mat.set_shader_parameter("view_fade", lerpf(0.25, 1.0, near) * far)


func _dim(n: Node, f: float) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			var m := mi.get_active_material(i) as StandardMaterial3D
			if m and m.emission_enabled:
				m = m.duplicate()
				m.emission_energy_multiplier *= f
				mi.set_surface_override_material(i, m)
	for c in n.get_children():
		_dim(c, f)


func _load(path: String) -> Node3D:
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	if not FileAccess.file_exists(abs_path):
		push_warning("shield_preview: missing " + abs_path)
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(abs_path, state) != OK:
		return null
	return doc.generate_scene(state) as Node3D


func _update_cam() -> void:
	var b := Basis.from_euler(Vector3(deg_to_rad(-_pitch), deg_to_rad(_yaw), 0.0))
	_cam.global_transform = Transform3D(b, _focus + b.z * _dist)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_dist = maxf(_dist * 0.9, 30.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_dist = minf(_dist * 1.1, 6000.0)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = 1 if mb.pressed else 0
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_drag = 2 if mb.pressed else 0
		_update_cam()
	elif event is InputEventMouseMotion and _drag != 0:
		var mm := event as InputEventMouseMotion
		if _drag == 1:
			_yaw -= mm.relative.x * 0.3
			_pitch = clampf(_pitch + mm.relative.y * 0.3, -85.0, 85.0)
		else:
			var b := _cam.global_transform.basis
			_focus += (-b.x * mm.relative.x + b.y * mm.relative.y) * _dist * 0.0015
		_update_cam()
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_H: _hit()
			KEY_R: _restart()
			KEY_F:
				_yaw = -35.0
				_pitch = 32.0
				_dist = 620.0
				_focus = Vector3(30.0, 0.0, 20.0)
				_update_cam()
			KEY_Q: get_tree().quit()


func _exit_tree() -> void:
	if is_instance_valid(_shield):
		_shield.free()

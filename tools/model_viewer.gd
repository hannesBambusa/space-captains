extends Node3D
## Model viewer: shows one or more 3D models in their own window to look at.
## Installed by the /3D skill (~/.claude/skills/3d) into <project>/tools/.
##
## Run: Godot --path <project> res://tools/model_viewer.tscn -- --model=<path> [--model=<path> ...]
##   <path>: an absolute path or res:// path to a .glb / .gltf (loaded at runtime with
##   GLTFDocument, so a freshly exported file needs no editor import), or a .tscn / .scn.
##   Several --model args are laid out side by side, left to right.
##   Optional: --dim=0.35 (scale every emission, like a game that dims lights), --spin,
##   --shot=<png> (save one frame after 1.5 s and quit: a check that it loads).
## Staging a scene (e.g. a ship docked at a building, a part moving like in the game):
##   --model=<path>@x,y,z[,yaw_deg]   place that model there (Godot coords, metres) instead of
##                                    the side-by-side layout; models without @ are laid out
##   --swing=<node>:<deg>[:<period s>] swing a named node back and forth about its local up,
##                                    0 -> deg -> 0 with an eased cosine (default period 4 s)
##   --scroll=<node>:<v per s>        scroll the node's material along V (conveyor belts)
##   --blink=<node>                   double-flash the node's emission (warning beacons)
##   --show=<node> / --hide=<node>    force a node visible / hidden
## Named nodes are looked up in every loaded model (first match). Space pauses all motion.
##
## Mouse: left drag orbit, right or middle drag pan, wheel zoom (trackpad: pinch / two-finger).
## Keys: F frame all, 1..9 frame model n, R auto-rotate, E emission dim on/off, W wireframe,
##   G grid, B background, L light side, T top view, Space play/pause animations, H hide help,
##   Esc / Q quit.

const BG_DARK := Color(0.012, 0.016, 0.03)
const BG_GREY := Color(0.32, 0.33, 0.35)
const GAP := 6.0

var _pivot := Vector3.ZERO
var _yaw := deg_to_rad(-35.0)
var _pitch := deg_to_rad(32.0)
var _dist := 30.0
var _target_dist := 30.0
var _drag := 0
var _spin := false
var _dim := 1.0
var _dim_on := false
var _grey := false
var _models: Array[Node3D] = []
var _names: PackedStringArray = []
var _boxes: Array[AABB] = []
var _emission := {}
var _cam: Camera3D
var _sun: DirectionalLight3D
var _env: Environment
var _grid: MeshInstance3D
var _help: Label
var _info: Label
var _shot := ""
var _t := 0.0
var _paused := false
var _swings: Array = []   # [node, rest basis, rad, period]
var _scrolls: Array = []  # [material, v per s]
var _blinks: Array = []   # [material, base energy]


func _ready() -> void:
	var paths: PackedStringArray = []
	var motions: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--model="):
			paths.append(a.trim_prefix("--model="))
		elif a.begins_with("--swing=") or a.begins_with("--scroll=") or a.begins_with("--blink=") \
				or a.begins_with("--show=") or a.begins_with("--hide="):
			motions.append(a)
		elif a.begins_with("--dim="):
			_dim = clampf(a.trim_prefix("--dim=").to_float(), 0.0, 1.0)
			_dim_on = _dim < 1.0
		elif a == "--spin":
			_spin = true
		elif a.begins_with("--shot="):
			_shot = a.trim_prefix("--shot=")
	_build_stage()
	var x := 0.0
	for spec in paths:
		var place := _placement(spec)
		var p: String = place[0]
		var m := _load(p)
		if m == null:
			push_error("model_viewer: could not load %s" % p)
			continue
		add_child(m)
		if place[1] != null:
			var xf: Array = place[1]
			m.position = Vector3(xf[0], xf[1], xf[2])
			m.rotation.y = deg_to_rad(xf[3])
		else:
			var box := _aabb_of(m)
			m.position.x = x - box.position.x
			x += box.size.x + maxf(GAP, box.size.x * 0.15)
		_models.append(m)
		_names.append(p.get_file())
		_boxes.append(_aabb_of(m))
		_collect_emission(m)
		for n in m.find_children("*", "AnimationPlayer", true, false):
			var player := n as AnimationPlayer
			if player.get_animation_list().size() > 0:
				player.play(player.get_animation_list()[0])
	for a in motions:
		_add_motion(a)
	if _models.is_empty():
		_info.text = "No model loaded. Pass --model=<path to .glb>"
	_apply_dim()
	get_window().title = "3D: %s" % ", ".join(_names)
	_frame_all(true)
	_update_info()
	print("MODEL_VIEWER loaded %d of %d: %s" % [_models.size(), paths.size(), ", ".join(_names)])
	if not _shot.is_empty():
		await get_tree().create_timer(1.5).timeout
		get_viewport().get_texture().get_image().save_png(_shot)
		print("MODEL_VIEWER shot %s" % _shot)
		get_tree().quit()


## "path@x,y,z[,yaw]" -> [path, [x, y, z, yaw] or null].
func _placement(spec: String) -> Array:
	var at := spec.rfind("@")
	if at > 0:
		var nums := spec.substr(at + 1).split(",")
		if nums.size() >= 3 and nums[0].is_valid_float():
			var yaw := nums[3].to_float() if nums.size() > 3 else 0.0
			return [spec.substr(0, at), [nums[0].to_float(), nums[1].to_float(), nums[2].to_float(), yaw]]
	return [spec, null]


func _find(node_name: String) -> Node:
	for m in _models:
		var n := m.find_child(node_name, true, false)
		if n:
			return n
	return null


func _own_material(n: Node) -> StandardMaterial3D:
	var mi := n as MeshInstance3D
	if mi == null or mi.mesh == null:
		return null
	var src := mi.get_active_material(0) as StandardMaterial3D
	if src == null:
		return null
	var mat := src.duplicate() as StandardMaterial3D
	mi.material_override = mat
	return mat


func _add_motion(a: String) -> void:
	var kind := a.substr(2, a.find("=") - 2)
	var parts := a.substr(a.find("=") + 1).split(":")
	var n := _find(parts[0])
	if n == null:
		push_error("model_viewer: no node named %s for --%s" % [parts[0], kind])
		print("MODEL_VIEWER missing node %s" % parts[0])
		return
	match kind:
		"swing":
			var n3 := n as Node3D
			_swings.append([n3, n3.basis, deg_to_rad(parts[1].to_float() if parts.size() > 1 else 45.0),
					parts[2].to_float() if parts.size() > 2 else 4.0])
		"scroll":
			var mat := _own_material(n)
			if mat:
				_scrolls.append([mat, parts[1].to_float() if parts.size() > 1 else 0.5])
		"blink":
			(n as Node3D).visible = true
			var mat := _own_material(n)
			if mat:
				_blinks.append([mat, maxf(mat.emission_energy_multiplier, 0.5)])
		"show":
			(n as Node3D).visible = true
		"hide":
			(n as Node3D).visible = false
	print("MODEL_VIEWER %s %s" % [kind, parts[0]])


func _step_motion(delta: float) -> void:
	if _paused:
		return
	_t += delta
	for sw in _swings:
		var f := 0.5 - 0.5 * cos(TAU * _t / maxf(float(sw[3]), 0.1))
		(sw[0] as Node3D).basis = (sw[1] as Basis) * Basis(Vector3.UP, float(sw[2]) * f)
	for sc in _scrolls:
		(sc[0] as StandardMaterial3D).uv1_offset.y -= float(sc[1]) * delta
	for bl in _blinks:
		var k := fposmod(_t * 1.6, 1.0)
		var f := 1.0 if k < 0.18 else (0.25 if k < 0.3 else (0.9 if k < 0.42 else 0.2))
		var dim := _dim if _dim_on else 1.0
		(bl[0] as StandardMaterial3D).emission_energy_multiplier = float(bl[1]) * dim * (0.6 + 2.2 * f)


func _load(path: String) -> Node3D:
	var ext := path.get_extension().to_lower()
	if ext in ["tscn", "scn"]:
		var ps := load(path) as PackedScene
		return ps.instantiate() as Node3D if ps else null
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	if not FileAccess.file_exists(abs_path):
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(abs_path, state) != OK:
		return null
	return doc.generate_scene(state) as Node3D


func _build_stage() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = BG_DARK
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.55, 0.6, 0.7)
	_env.ambient_light_energy = 0.35
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	_env.glow_enabled = true
	_env.glow_intensity = 0.7
	_env.glow_bloom = 0.05
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	_sun.light_energy = 1.6
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 600.0
	add_child(_sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15.0, 150.0, 0.0)
	fill.light_energy = 0.25
	fill.light_color = Color(0.7, 0.8, 1.0)
	add_child(fill)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.near = 0.05
	_cam.far = 20000.0
	add_child(_cam)
	_cam.current = true
	_grid = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	_grid.mesh = plane
	var gm := ShaderMaterial.new()
	gm.shader = Shader.new()
	gm.shader.code = """shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, shadows_disabled;
uniform float cell = 1.0;
void fragment() {
	vec2 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec2 g = abs(fract(p / cell - 0.5) - 0.5) / fwidth(p / cell);
	vec2 g10 = abs(fract(p / (cell * 10.0) - 0.5) - 0.5) / fwidth(p / (cell * 10.0));
	float line = 1.0 - min(min(g.x, g.y), 1.0);
	float line10 = 1.0 - min(min(g10.x, g10.y), 1.0);
	ALBEDO = vec3(0.5, 0.6, 0.7);
	ALPHA = max(line * 0.12, line10 * 0.3);
}"""
	_grid.material_override = gm
	_grid.visible = false
	add_child(_grid)
	var ui := CanvasLayer.new()
	add_child(ui)
	_info = Label.new()
	_info.position = Vector2(12, 10)
	_info.add_theme_font_size_override("font_size", 15)
	_info.add_theme_color_override("font_outline_color", Color.BLACK)
	_info.add_theme_constant_override("outline_size", 4)
	ui.add_child(_info)
	_help = Label.new()
	_help.add_theme_font_size_override("font_size", 13)
	_help.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
	_help.add_theme_color_override("font_outline_color", Color.BLACK)
	_help.add_theme_constant_override("outline_size", 4)
	_help.text = "Left drag orbit  ·  right/middle drag pan  ·  wheel zoom\nF frame all  ·  1-9 frame model  ·  T top  ·  R spin  ·  E emission dim  ·  W wireframe\nG grid  ·  B background  ·  L light side  ·  Space animations  ·  H help  ·  Q quit"
	_help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_help.position = Vector2(12, 0)
	ui.add_child(_help)


func _aabb_of(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var inv := n.global_transform.affine_inverse() if n.is_inside_tree() else Transform3D.IDENTITY
	for c in n.find_children("*", "VisualInstance3D", true, false):
		var vi := c as VisualInstance3D
		var t := (inv * vi.global_transform) if n.is_inside_tree() else _rel(n, vi)
		var b := t * vi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	if n.is_inside_tree():
		box = n.global_transform * box
	return box


func _rel(root: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


func _collect_emission(n: Node) -> void:
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s) as StandardMaterial3D
			if m and m.emission_enabled and not _emission.has(m):
				_emission[m] = m.emission_energy_multiplier


func _apply_dim() -> void:
	var k := _dim if _dim_on else 1.0
	for m: StandardMaterial3D in _emission:
		m.emission_energy_multiplier = float(_emission[m]) * k


func _frame(box: AABB, snap: bool) -> void:
	_pivot = box.get_center()
	var r := maxf(box.size.length() * 0.5, 0.5)
	_target_dist = r / tan(deg_to_rad(_cam.fov) * 0.5) * 0.8
	if snap:
		_dist = _target_dist
	var g := maxf(box.size.x, box.size.z) * 1.6
	_grid.scale = Vector3(g, 1.0, g)
	_grid.position = Vector3(_pivot.x, box.position.y - 0.01, _pivot.z)
	var cell := pow(10.0, floorf(log(maxf(g, 1.0)) / log(10.0)) - 1.0)
	(_grid.material_override as ShaderMaterial).set_shader_parameter("cell", maxf(cell, 0.1))


func _frame_all(snap: bool = false) -> void:
	if _boxes.is_empty():
		return
	var box := _boxes[0]
	for b in _boxes:
		box = box.merge(b)
	_frame(box, snap)


func _update_info() -> void:
	var lines: PackedStringArray = []
	for i in _models.size():
		var tris := 0
		for c in _models[i].find_children("*", "MeshInstance3D", true, false):
			var mesh := (c as MeshInstance3D).mesh
			if mesh == null:
				continue
			for s in mesh.get_surface_count():
				var a := mesh.surface_get_arrays(s)
				var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				tris += idx.size() / 3 if idx.size() > 0 else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		var s := _boxes[i].size
		lines.append("%d  %s   %.1f x %.1f x %.1f m   %s tris" % [i + 1, _names[i], s.x, s.y, s.z, _fmt(tris)])
	lines.append("emission x%.2f%s%s" % [_dim if _dim_on else 1.0, "   spinning" if _spin else "", "   wireframe" if get_viewport().debug_draw == Viewport.DEBUG_DRAW_WIREFRAME else ""])
	_info.text = "\n".join(lines)


static func _fmt(n: int) -> String:
	return "%.1fk" % (n / 1000.0) if n >= 10000 else str(n)


func _process(delta: float) -> void:
	_step_motion(delta)
	if _spin:
		_yaw += delta * 0.35
	var vs := get_viewport().get_visible_rect().size
	_help.position = Vector2(12, vs.y - 62)
	_dist = lerpf(_dist, _target_dist, clampf(delta * 10.0, 0.0, 1.0))
	var off := Vector3(cos(_pitch) * sin(_yaw), sin(_pitch), cos(_pitch) * cos(_yaw)) * _dist
	_cam.global_position = _pivot + off
	_cam.look_at(_pivot, Vector3.UP if absf(_pitch) < deg_to_rad(89.0) else Vector3.FORWARD)
	_cam.near = clampf(_dist * 0.002, 0.01, 5.0)


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_target_dist *= 0.88
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_target_dist *= 1.14
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = 1 if mb.pressed else 0
		elif mb.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_drag = 2 if mb.pressed else 0
		return
	var mm := event as InputEventMouseMotion
	if mm and _drag == 1:
		_yaw -= mm.relative.x * 0.006
		_pitch = clampf(_pitch + mm.relative.y * 0.006, deg_to_rad(-89.5), deg_to_rad(89.5))
		return
	if mm and _drag == 2:
		var right := _cam.global_transform.basis.x
		var up := _cam.global_transform.basis.y
		_pivot += (-right * mm.relative.x + up * mm.relative.y) * _dist * 0.0015
		return
	var mg := event as InputEventMagnifyGesture
	if mg:
		_target_dist /= maxf(mg.factor, 0.01)
		return
	var pg := event as InputEventPanGesture
	if pg:
		if pg.shift_pressed:
			var right := _cam.global_transform.basis.x
			var up := _cam.global_transform.basis.y
			_pivot += (right * pg.delta.x - up * pg.delta.y) * _dist * 0.01
		else:
			_target_dist *= exp(pg.delta.y * 0.05)
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_ESCAPE, KEY_Q:
			get_tree().quit()
		KEY_F:
			_frame_all()
		KEY_R:
			_spin = not _spin
		KEY_E:
			_dim_on = not _dim_on
			if _dim_on and _dim >= 1.0:
				_dim = 0.35
			_apply_dim()
		KEY_W:
			var vp := get_viewport()
			vp.debug_draw = Viewport.DEBUG_DRAW_DISABLED if vp.debug_draw == Viewport.DEBUG_DRAW_WIREFRAME else Viewport.DEBUG_DRAW_WIREFRAME
		KEY_G:
			_grid.visible = not _grid.visible
		KEY_B:
			_grey = not _grey
			_env.background_color = BG_GREY if _grey else BG_DARK
		KEY_L:
			_sun.rotation_degrees.y += 90.0
		KEY_T:
			_pitch = deg_to_rad(89.5)
		KEY_H:
			_help.visible = not _help.visible
		KEY_SPACE:
			_paused = not _paused
			for m in _models:
				for n in m.find_children("*", "AnimationPlayer", true, false):
					var player := n as AnimationPlayer
					if player.is_playing():
						player.pause()
					elif player.get_animation_list().size() > 0:
						player.play()
		_:
			if k.keycode >= KEY_1 and k.keycode <= KEY_9:
				var i := k.keycode - KEY_1
				if i < _boxes.size():
					_frame(_boxes[i], false)
			return
	_update_info()

class_name JumpGate
extends Orbiter
## Jump gate from a GateDef. Instances assets/models/gate/jump_gate.glb (ring
## axis along local +Z, "gate_emitter" mesh, "portal_anchor" empty at the ring
## centre) or a torus fallback. Draws a swirling portal disc at the anchor and
## pulses the emitter. The ring axis points at the star, then leans back by
## GateDef.tilt_deg so the portal reads from the tilted top-down camera.

const GATE_PATH := "res://assets/models/gate/jump_gate.glb"
const PORTAL_SHADER: Shader = preload("res://shaders/gate_portal.gdshader")
const FALLBACK_PORTAL_RADIUS := 80.0
## The glb's inner_radius is the ring's inner face; pylon prongs reach further in.
const PORTAL_INSET := 0.93

@export var pulse_speed: float = 1.4

var def: GateDef
var portal_radius: float = FALLBACK_PORTAL_RADIUS

var _pivot: Node3D
var _portal_mat: ShaderMaterial
var _emitter_mats: Array[StandardMaterial3D] = []
var _emitter_base: Array[float] = []
var _glow_light: OmniLight3D


func build(gate_def: GateDef) -> void:
	def = gate_def
	name = StringName(def.name.validate_node_name())
	setup_orbit(def.orbit_radius, def.orbit_period, def.orbit_angle_deg)
	make_focusable(150.0, 900.0)

	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	var model := _load_model()
	_pivot.add_child(model)
	MeshUtil.set_layers_recursive(model, 2)

	var anchor := model.find_child("portal_anchor", true, false) as Node3D
	portal_radius = _portal_radius(model, anchor)
	var portal := MeshInstance3D.new()
	portal.name = "Portal"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * portal_radius * 2.0
	portal.mesh = quad
	portal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_portal_mat = ShaderMaterial.new()
	_portal_mat.shader = PORTAL_SHADER
	_portal_mat.render_priority = 1
	_portal_mat.set_shader_parameter("portal_color", Color(def.portal_color, 1.0))
	_portal_mat.set_shader_parameter("intensity", 1.1)
	portal.material_override = _portal_mat
	if anchor:
		# Anchor may carry a scale; keep the disc at its true size.
		anchor.add_child(portal)
		var sx := absf(anchor.scale.x)
		portal.scale = Vector3.ONE / sx if sx > 0.001 else Vector3.ONE
	else:
		_pivot.add_child(portal)

	_glow_light = OmniLight3D.new()
	_glow_light.name = "PortalGlow"
	_glow_light.light_color = def.portal_color
	_glow_light.light_energy = 1.0
	_glow_light.omni_range = portal_radius * 3.0
	_glow_light.omni_attenuation = 1.2
	_glow_light.light_cull_mask = 2
	portal.add_child(_glow_light)

	_collect_emitters(model)
	_orient()


func update_sim(sim_time: float) -> void:
	super.update_sim(sim_time)
	if orbit_period != 0.0:
		_orient()


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var pulse := 0.75 + 0.25 * sin(t * pulse_speed) + 0.1 * sin(t * pulse_speed * 3.1)
	if _portal_mat:
		_portal_mat.set_shader_parameter("pulse", 0.9 + 0.2 * pulse)
	for i in _emitter_mats.size():
		_emitter_mats[i].emission_energy_multiplier = _emitter_base[i] * (0.55 + 0.6 * pulse)
	if _glow_light:
		_glow_light.light_energy = 0.8 + 0.5 * pulse


## Ring axis toward the star, leaned back so the face tilts up.
func _orient() -> void:
	var to_star := -Vector3(position.x, 0.0, position.z)
	if to_star.length_squared() < 1.0:
		to_star = Vector3.FORWARD
	to_star = to_star.normalized()
	var tilt := deg_to_rad(def.tilt_deg)
	var axis := (to_star * cos(tilt) + Vector3.UP * sin(tilt)).normalized()
	_pivot.basis = Basis.looking_at(-axis, Vector3.UP if absf(axis.y) < 0.999 else to_star)


func _portal_radius(model: Node3D, anchor: Node3D) -> float:
	if anchor:
		var r := float(anchor.get_meta(&"inner_radius", 0.0))
		if r <= 0.0 and anchor.has_meta(&"extras"):
			var extras: Variant = anchor.get_meta(&"extras")
			if extras is Dictionary:
				r = float((extras as Dictionary).get("inner_radius", 0.0))
		if r > 0.0:
			return r * PORTAL_INSET
		var s := anchor.scale.x
		if absf(s - 1.0) > 0.01 and s > 1.0:
			return s
	var ring := model.find_child("gate_ring", true, false) as MeshInstance3D
	if ring and ring.mesh:
		var e := ring.mesh.get_aabb().size
		return minf(e.x, e.y) * 0.5 * 0.72
	return FALLBACK_PORTAL_RADIUS


func _collect_emitters(model: Node) -> void:
	var emitter := model.find_child("gate_emitter", true, false)
	if emitter == null:
		return
	var stack: Array[Node] = [emitter]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s) as StandardMaterial3D
			if src == null:
				continue
			# Runtime copy so the imported material stays untouched.
			var m := src.duplicate() as StandardMaterial3D
			m.emission_enabled = true
			mi.set_surface_override_material(s, m)
			_emitter_mats.append(m)
			_emitter_base.append(maxf(src.emission_energy_multiplier, 1.0))


func _load_model() -> Node3D:
	if ResourceLoader.exists(GATE_PATH):
		var packed := load(GATE_PATH) as PackedScene
		if packed:
			var inst := packed.instantiate() as Node3D
			if inst:
				return inst
	print("JumpGate: %s not found, using torus fallback" % GATE_PATH)
	return _build_fallback()


func _build_fallback() -> Node3D:
	var root := Node3D.new()
	root.name = "gate_fallback"
	var hull := StandardMaterial3D.new()
	hull.albedo_color = Color(0.5, 0.52, 0.56)
	hull.metallic = 0.6
	hull.roughness = 0.4
	var ring := MeshInstance3D.new()
	ring.name = "gate_ring"
	var torus := TorusMesh.new()
	torus.inner_radius = 88.0
	torus.outer_radius = 108.0
	torus.rings = 96
	torus.ring_segments = 16
	torus.material = hull
	ring.mesh = torus
	ring.rotation.x = PI * 0.5
	root.add_child(ring)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.3, 0.8, 1.0)
	glow.emission_enabled = true
	glow.emission = Color(0.3, 0.85, 1.0)
	glow.emission_energy_multiplier = 5.0
	var band := MeshInstance3D.new()
	band.name = "gate_emitter"
	var band_mesh := TorusMesh.new()
	band_mesh.inner_radius = 86.0
	band_mesh.outer_radius = 89.0
	band_mesh.rings = 96
	band_mesh.material = glow
	band.mesh = band_mesh
	band.rotation.x = PI * 0.5
	root.add_child(band)
	var anchor := Node3D.new()
	anchor.name = "portal_anchor"
	root.add_child(anchor)
	return root

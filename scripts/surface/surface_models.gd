class_name SurfaceModels
extends RefCounted
## Models of the surface (planet outposts plan): assets/models/surface/<id>.glb
## from blender/gen_surface.py when it exists, else a simple stand-in built
## here from primitives (the same shapes, so the game reads either way).

const DIR := "res://assets/models/surface/"


static func make(id: String, tint: Color = Color(0.6, 0.62, 0.66)) -> Node3D:
	return ModelLoader.instantiate(DIR + id + ".glb", func() -> Node3D: return _stand_in(id, tint))


static func _mat(c: Color, metal: float = 0.3, rough: float = 0.6, glow: Color = Color.BLACK) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	if glow != Color.BLACK:
		m.emission_enabled = true
		m.emission = glow
		m.emission_energy_multiplier = 2.0
	return m


static func _part(root: Node3D, mesh: Mesh, at: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.rotation = rot
	root.add_child(mi)
	return mi


static func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b


static func _cyl(r: float, h: float, top: float = -1.0, sides: int = 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r if top < 0.0 else top
	c.bottom_radius = r
	c.height = h
	c.radial_segments = sides
	return c


static func _stand_in(id: String, tint: Color) -> Node3D:
	var root := Node3D.new()
	root.name = id
	var hull := _mat(tint)
	var dark := _mat(Color(0.18, 0.19, 0.21), 0.4, 0.5)
	var light := _mat(Color(0.9, 0.7, 0.3), 0.0, 0.4, Color(1.0, 0.65, 0.25))
	var cyan := _mat(Color(0.3, 0.8, 1.0), 0.0, 0.3, Color(0.3, 0.8, 1.0))
	match id:
		"landing_pad":
			_part(root, _cyl(55.0, 3.0, -1.0, 32), Vector3(0, 1.5, 0), dark)
			_part(root, _cyl(48.0, 0.4, -1.0, 32), Vector3(0, 3.2, 0), _mat(Color(0.55, 0.5, 0.3), 0.2, 0.7))
			_part(root, _box(18, 14, 18), Vector3(40, 7, 40), hull)
			_part(root, _cyl(1.2, 26.0), Vector3(40, 27, 40), dark)
			for a in 8:
				var ang := a * TAU / 8.0
				_part(root, _box(2, 1, 2), Vector3(cos(ang) * 52.0, 3.6, sin(ang) * 52.0), light)
		"harvester_bay":
			_part(root, _box(60, 16, 40), Vector3(0, 8, 0), hull)
			_part(root, _box(24, 12, 2), Vector3(0, 6, 20.5), dark)
			_part(root, _cyl(6.0, 22.0), Vector3(-22, 11, -10), hull)
			_part(root, _cyl(6.0, 22.0), Vector3(-8, 11, -10), hull)
			_part(root, _box(3, 1, 3), Vector3(28, 16.5, 18), light)
		"garrison":
			_part(root, _box(50, 14, 50), Vector3(0, 7, 0), _mat(tint.darkened(0.2)))
			_part(root, _box(30, 10, 30), Vector3(0, 19, 0), hull)
			_part(root, _box(3, 1, 3), Vector3(16, 24.5, 16), _mat(Color(1, 0.3, 0.2), 0.0, 0.4, Color(1, 0.25, 0.15)))
		"ground_turret":
			_part(root, _cyl(10.0, 6.0, 8.0), Vector3(0, 3, 0), dark)
			_part(root, _box(10, 6, 12), Vector3(0, 9, 0), hull)
			_part(root, _cyl(1.0, 16.0), Vector3(0, 10, -10), dark, Vector3(PI / 2.0, 0, 0))
		"shield_dome":
			_part(root, _cyl(14.0, 10.0, 10.0), Vector3(0, 5, 0), hull)
			_part(root, _cyl(3.0, 18.0, 1.5), Vector3(0, 19, 0), cyan)
		"harvester":
			_part(root, _box(8, 3.5, 12), Vector3(0, 2.0, 0), _mat(Color(0.9, 0.6, 0.2), 0.3, 0.5))
			_part(root, _box(6, 3, 5), Vector3(0, 4.5, 2.5), hull)
			_part(root, _cyl(1.4, 5.0), Vector3(0, 2.0, -7), dark, Vector3(PI / 2.0, 0, 0))
			_part(root, _box(9, 1, 2), Vector3(0, 0.5, -4), light)
		"hover_tank":
			_part(root, _box(9, 3.5, 13), Vector3(0, 2.0, 0), _mat(Color(0.75, 0.25, 0.2), 0.4, 0.45))
			_part(root, _box(6, 2.5, 6), Vector3(0, 4.8, 0.5), hull)
			_part(root, _cyl(0.7, 9.0), Vector3(0, 4.8, -6.0), dark, Vector3(PI / 2.0, 0, 0))
			_part(root, _box(10, 0.8, 2), Vector3(0, 0.4, 4), cyan)
		"raider_tank":
			_part(root, _box(8, 3, 12), Vector3(0, 2.0, 0), _mat(Color(0.35, 0.32, 0.3), 0.5, 0.6))
			_part(root, _box(5, 2.5, 5), Vector3(0, 4.5, 1.0), _mat(Color(0.55, 0.15, 0.1), 0.4, 0.5))
			_part(root, _cyl(0.6, 8.0), Vector3(0, 4.5, -5.0), dark, Vector3(PI / 2.0, 0, 0))
			_part(root, _box(9, 0.8, 2), Vector3(0, 0.4, 4), _mat(Color(1, 0.4, 0.1), 0.0, 0.4, Color(1, 0.35, 0.1)))
		"critter":
			var body := SphereMesh.new()
			body.radius = 2.4
			body.height = 3.2
			_part(root, body, Vector3(0, 1.8, 0), _mat(Color(0.32, 0.42, 0.18), 0.0, 0.8))
			var head := SphereMesh.new()
			head.radius = 1.5
			head.height = 2.4
			_part(root, head, Vector3(0, 2.2, -2.8), _mat(Color(0.25, 0.32, 0.14), 0.0, 0.8))
			for s in [-1.0, 1.0]:
				_part(root, _box(0.4, 0.4, 3.5), Vector3(s * 2.2, 0.8, 0), dark, Vector3(0, 0, s * 0.6))
				_part(root, _box(0.6, 0.6, 0.6), Vector3(s * 0.7, 2.6, -4.0), _mat(Color(1, 0.8, 0.2), 0.0, 0.4, Color(1, 0.7, 0.1)))
		"nest":
			var mound := SphereMesh.new()
			mound.radius = 40.0
			mound.height = 36.0
			_part(root, mound, Vector3(0, 2, 0), _mat(Color(0.3, 0.33, 0.18), 0.0, 0.9))
			for k in 6:
				var a := k * TAU / 6.0
				var pod := SphereMesh.new()
				pod.radius = 8.0
				pod.height = 12.0
				_part(root, pod, Vector3(cos(a) * 30.0, 6, sin(a) * 30.0), _mat(Color(0.5, 0.55, 0.2), 0.0, 0.6, Color(0.4, 0.5, 0.05)))
		"platform":
			# A floating deck (gas giants), radius 60 at scale 1, lift engines under it.
			_part(root, _cyl(60.0, 4.0, -1.0, 24), Vector3(0, -2.0, 0), dark)
			_part(root, _cyl(54.0, 0.5, -1.0, 24), Vector3(0, 0.1, 0), _mat(Color(0.42, 0.44, 0.48), 0.5, 0.5))
			for k in 4:
				var a := k * TAU / 4.0 + PI / 4.0
				_part(root, _cyl(6.0, 10.0, 4.0), Vector3(cos(a) * 42.0, -9.0, sin(a) * 42.0), dark)
				_part(root, _cyl(4.0, 1.0), Vector3(cos(a) * 42.0, -14.5, sin(a) * 42.0), cyan)
		"floater":
			var bell := SphereMesh.new()
			bell.radius = 3.2
			bell.height = 3.6
			var jelly := _mat(Color(0.75, 0.4, 0.9, 0.75), 0.0, 0.3, Color(0.6, 0.25, 0.9))
			jelly.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_part(root, bell, Vector3(0, 2.0, 0), jelly)
			for k in 5:
				var a := k * TAU / 5.0
				_part(root, _box(0.3, 4.0, 0.3), Vector3(cos(a) * 1.6, -0.6, sin(a) * 1.6), jelly)
		"storm_cell":
			var core := SphereMesh.new()
			core.radius = 45.0
			core.height = 50.0
			var cloud := _mat(Color(0.35, 0.3, 0.45, 0.85), 0.0, 1.0, Color(0.5, 0.35, 0.9))
			cloud.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_part(root, core, Vector3(0, 20, 0), cloud)
			for k in 5:
				var a := k * TAU / 5.0
				var puff := SphereMesh.new()
				puff.radius = 18.0
				puff.height = 22.0
				_part(root, puff, Vector3(cos(a) * 40.0, 12, sin(a) * 40.0), cloud)
		"deposit_fuel":
			# A gas pocket: a glowing column of rising gas over the clouds.
			var gas := _mat(Color(1.0, 0.7, 0.3, 0.45), 0.0, 0.2, Color(1.0, 0.6, 0.2))
			gas.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(id)
			for k in 7:
				var puff := SphereMesh.new()
				var r := rng.randf_range(10.0, 22.0)
				puff.radius = r
				puff.height = r * 1.6
				_part(root, puff, Vector3(rng.randf_range(-25.0, 25.0), 8.0 + k * 9.0, rng.randf_range(-25.0, 25.0)), gas)
		_:
			# Deposits: "deposit_<good>".
			var col := Color(0.7, 0.85, 1.0)
			var glow := Color.BLACK
			if id.ends_with("silicates"):
				col = Color(0.9, 0.8, 0.55)
			elif id.ends_with("heavy_ore"):
				col = Color(0.45, 0.38, 0.33)
			elif id.ends_with("rare_metals"):
				col = Color(0.5, 0.25, 0.3)
				glow = Color(1.0, 0.35, 0.1)
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(id)
			for k in 9:
				var a := rng.randf() * TAU
				var r := rng.randf_range(0.0, 45.0)
				var s := rng.randf_range(6.0, 16.0)
				var shard := _cyl(s * 0.35, s * rng.randf_range(1.2, 2.4), s * 0.05, 6)
				_part(root, shard, Vector3(cos(a) * r, s * 0.6, sin(a) * r), _mat(col, 0.2, 0.35, glow),
						Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4)))
	return root

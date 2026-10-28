class_name GraphicsSettings
extends RefCounted
## Player graphics options, kept under [graphics] in user://settings.cfg
## (the shared settings file, see WindowMode). Applied once at start by the
## WindowMode autoload; [GraphicsOptions] (main menu and pause menu) sets
## them live and saves.
##
## Where they go: the root viewport (main menu backdrop) gets the AA and
## scaling values, and every [SystemView] copies them onto its system
## SubViewports ([method SystemView.match_quality]; SubViewports do not
## inherit the root's). New system worlds pick them up as they are built:
## the SubViewport copies the root, [method apply_world] (from
## SystemWorld._enter_tree) sets glow and SSAO on the world's environment.
## Shadows: the directional atlas size and soft filter are global
## (RenderingServer); [LocalSunLight] asks [method shadows_on].
##
## Presets set the quality keys ([constant PRESET_KEYS]); changing one of
## those makes the preset "custom". VSync, FPS cap, the FPS counter and the
## rendering driver stay as they are.
##
## Rendering driver (Windows only, needs a restart): written to
## user://engine_override.cfg as rendering_device/driver.windows. project.godot
## points application/config/project_settings_override at that file, so
## Godot loads it at start in exported builds too. "default" deletes the key.

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "graphics"
const OVERRIDE_PATH := "user://engine_override.cfg"
const DRIVER_KEY := "rendering_device/driver.windows"

const PRESETS: Array[String] = ["low", "medium", "high", "ultra", "custom"]
const DEFAULT_PRESET := "high"

## Quality keys a preset sets.
const PRESET_KEYS: Array[String] = ["msaa", "screen_aa", "taa", "sharpness",
		"render_scale", "scaling", "shadows", "glow", "ssao", "aniso"]

## msaa: Viewport.MSAA (0 off, 1 2x, 2 4x, 3 8x). screen_aa: 0 off, 1 FXAA,
## 2 SMAA. sharpness 0..1 (FSR only). render_scale 0.5..2.0. scaling: 0
## bilinear, 1 FSR 1, 2 FSR 2 (FSR only below 100%). shadows: 0 off, 1 low,
## 2 medium, 3 high. aniso: Viewport.AnisotropicFiltering (0 off .. 4 16x).
const PRESET_VALUES := {
	"low": {"msaa": 0, "screen_aa": 1, "taa": false, "sharpness": 0.5,
			"render_scale": 0.75, "scaling": 1, "shadows": 1, "glow": false, "ssao": false, "aniso": 1},
	"medium": {"msaa": 1, "screen_aa": 1, "taa": false, "sharpness": 0.5,
			"render_scale": 1.0, "scaling": 0, "shadows": 2, "glow": true, "ssao": false, "aniso": 2},
	"high": {"msaa": 2, "screen_aa": 0, "taa": false, "sharpness": 0.5,
			"render_scale": 1.0, "scaling": 0, "shadows": 3, "glow": true, "ssao": false, "aniso": 4},
	"ultra": {"msaa": 2, "screen_aa": 0, "taa": false, "sharpness": 0.5,
			"render_scale": 1.5, "scaling": 0, "shadows": 3, "glow": true, "ssao": true, "aniso": 4},
}

## Display keys, not part of a preset. vsync: 0 off, 1 on, 2 adaptive.
## fps_cap: 0 unlimited. driver: "default", "vulkan", "d3d12".
const DISPLAY_DEFAULTS := {"vsync": 1, "fps_cap": 0, "show_fps": false, "driver": "default"}

const FPS_CAPS: Array[int] = [30, 60, 120, 144, 0]
const DRIVERS: Array[String] = ["default", "vulkan", "d3d12"]

## Per shadow level: directional atlas size and soft filter quality.
## Medium is what the project used before these settings.
const SHADOW_SIZE: Array[int] = [1024, 2048, 4096, 8192]
const SHADOW_SOFT: Array[int] = [
	RenderingServer.SHADOW_QUALITY_HARD,
	RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
	RenderingServer.SHADOW_QUALITY_SOFT_LOW,
	RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
]

const FPS_COUNTER_NAME := "FpsCounter"

## The live values (preset, quality and display keys).
static var _values: Dictionary = {}


## Loads user://settings.cfg and applies everything to [param tree].
static func apply_saved(tree: SceneTree) -> void:
	_load()
	apply(tree)


## Current value of [param key].
static func get_value(key: String) -> Variant:
	_ensure()
	return _values.get(key)


## Shadows switched on at all (level above off).
static func shadows_on() -> bool:
	_ensure()
	return int(_values.get("shadows", 2)) > 0


## Whether this platform can pick the rendering driver.
static func driver_choice_available() -> bool:
	return OS.get_name() == "Windows"


## Sets one key, applies it now and saves. A quality key makes the preset
## "custom".
static func set_value(tree: SceneTree, key: String, value: Variant, save: bool = true) -> void:
	_ensure()
	_values[key] = value
	if key in PRESET_KEYS:
		_values["preset"] = "custom"
	if key == "driver":
		_write_driver(String(value))
	apply(tree)
	if save:
		_save()


## Picks [param preset] (low/medium/high/ultra; custom keeps the values).
static func set_preset(tree: SceneTree, preset: String, save: bool = true) -> void:
	_ensure()
	_values["preset"] = preset
	if PRESET_VALUES.has(preset):
		var p: Dictionary = PRESET_VALUES[preset]
		for k: String in p:
			_values[k] = p[k]
	apply(tree)
	if save:
		_save()


## Scaling mode actually used: FSR only below 100%.
static func effective_scaling() -> int:
	_ensure()
	if float(_values["render_scale"]) >= 0.999:
		return 0
	return int(_values["scaling"])


## Sharpening only works with FSR (Godot has no TAA-only sharpen pass).
static func sharpness_used() -> bool:
	return effective_scaling() != 0


## Pushes every value to the root, every system SubViewport, every
## WorldEnvironment, the shadow lights and the display.
static func apply(tree: SceneTree) -> void:
	_ensure()
	if tree == null:
		return
	var root := tree.root
	_apply_viewport(root)
	for c in root.find_children("*", "SubViewportContainer", true, false):
		var view := c as SystemView
		if view == null:
			continue
		for vp in view.get_children():
			if vp is SubViewport:
				view.match_quality(vp)
	for env_node in root.find_children("*", "WorldEnvironment", true, false):
		apply_environment(env_node as WorldEnvironment)
	var lvl := int(_values["shadows"])
	RenderingServer.directional_shadow_atlas_set_size(SHADOW_SIZE[clampi(lvl, 0, 3)], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(SHADOW_SOFT[clampi(lvl, 0, 3)])
	for l in root.find_children("*", "DirectionalLight3D", true, false):
		if l is LocalSunLight:
			(l as LocalSunLight).refresh_shadow()
		elif l.get_parent() is MenuBackdrop:
			(l as DirectionalLight3D).shadow_enabled = shadows_on()
	Engine.max_fps = int(_values["fps_cap"])
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.VSYNC_ENABLED
		match int(_values["vsync"]):
			0: mode = DisplayServer.VSYNC_DISABLED
			2: mode = DisplayServer.VSYNC_ADAPTIVE
		DisplayServer.window_set_vsync_mode(mode)
	_apply_fps_counter(root)


## Glow and SSAO on the environments of one system world (called as the
## world enters the tree, before its first frame).
static func apply_world(world: Node) -> void:
	_ensure()
	var env_node := world.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	apply_environment(env_node)


static func apply_environment(env_node: WorldEnvironment) -> void:
	if env_node == null or env_node.environment == null:
		return
	var env := env_node.environment
	env.glow_enabled = bool(_values["glow"])
	env.ssao_enabled = bool(_values["ssao"])
	if env.ssao_enabled:
		# Station-scale contact shading; the system spans km, so keep it short.
		env.ssao_radius = 4.0
		env.ssao_intensity = 1.6
		env.ssao_power = 1.4
		env.ssao_detail = 0.5
		env.ssao_light_affect = 0.0


static func _apply_viewport(vp: Viewport) -> void:
	vp.msaa_3d = int(_values["msaa"]) as Viewport.MSAA
	vp.screen_space_aa = int(_values["screen_aa"]) as Viewport.ScreenSpaceAA
	var scaling := effective_scaling()
	var modes := [Viewport.SCALING_3D_MODE_BILINEAR, Viewport.SCALING_3D_MODE_FSR, Viewport.SCALING_3D_MODE_FSR2]
	vp.scaling_3d_mode = modes[clampi(scaling, 0, 2)]
	vp.scaling_3d_scale = clampf(float(_values["render_scale"]), 0.5, 2.0)
	# FSR 2 is temporal already.
	vp.use_taa = bool(_values["taa"]) and scaling != 2
	# fsr_sharpness: 0 sharpest, 2 none.
	vp.fsr_sharpness = 2.0 * (1.0 - clampf(float(_values["sharpness"]), 0.0, 1.0))
	vp.anisotropic_filtering_level = int(_values["aniso"]) as Viewport.AnisotropicFiltering


static func _apply_fps_counter(root: Window) -> void:
	var on := bool(_values["show_fps"])
	var counter := root.get_node_or_null(FPS_COUNTER_NAME)
	if on and counter == null:
		counter = FpsCounter.new()
		counter.name = FPS_COUNTER_NAME
		root.add_child.call_deferred(counter)
	elif not on and counter:
		counter.queue_free()


static func _ensure() -> void:
	if _values.is_empty():
		_load()


static func _defaults() -> Dictionary:
	var d := {"preset": DEFAULT_PRESET}
	var p: Dictionary = PRESET_VALUES[DEFAULT_PRESET]
	for k: String in p:
		d[k] = p[k]
	for k: String in DISPLAY_DEFAULTS:
		d[k] = DISPLAY_DEFAULTS[k]
	return d


static func _load() -> void:
	_values = _defaults()
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK or not cfg.has_section(SECTION):
		return
	for k: String in _values.keys():
		var v: Variant = cfg.get_value(SECTION, k, _values[k])
		# Keep the default's type (a hand-edited file may hold "2" or 2.0).
		match typeof(_values[k]):
			TYPE_INT: v = int(v)
			TYPE_FLOAT: v = float(v)
			TYPE_BOOL: v = bool(v)
			TYPE_STRING: v = str(v)
		_values[k] = v
	if not PRESETS.has(_values["preset"]):
		_values["preset"] = "custom"
	if not DRIVERS.has(_values["driver"]):
		_values["driver"] = "default"


static func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	for k: String in _values:
		cfg.set_value(SECTION, k, _values[k])
	cfg.save(SETTINGS_PATH)


## Windows driver override for the next start (see the class note).
static func _write_driver(driver: String) -> void:
	if not driver_choice_available():
		return
	var cfg := ConfigFile.new()
	cfg.load(OVERRIDE_PATH)
	if driver == "default" or not DRIVERS.has(driver):
		if cfg.has_section_key("rendering", DRIVER_KEY):
			cfg.erase_section_key("rendering", DRIVER_KEY)
	else:
		cfg.set_value("rendering", DRIVER_KEY, driver)
	if cfg.get_sections().is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OVERRIDE_PATH))
	else:
		cfg.save(OVERRIDE_PATH)


## The driver this run started with ("vulkan", "d3d12", ...).
static func running_driver() -> String:
	return RenderingServer.get_current_rendering_driver_name()

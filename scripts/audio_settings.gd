class_name AudioSettings
extends RefCounted
## Player volume per audio bus (default_bus_layout.tres: Master, Music,
## Ambient (sends to Music), SFX, UI), kept as linear 0..1 under [audio] in
## user://settings.cfg (the shared settings file, see WindowMode). Applied
## once at start by the Sfx autoload; the volume sliders ([VolumeSliders])
## set and save.

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "audio"
## Buses with a player slider, in slider order.
const BUSES: Array[StringName] = [&"Music", &"SFX", &"UI"]
const DEFAULT := 0.8


## Applies every saved volume to its bus.
static func apply_saved() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	for bus in BUSES:
		_apply(bus, float(cfg.get_value(SECTION, String(bus).to_lower(), DEFAULT)))


## Linear volume of [param bus] (0..1) as the player set it.
static func volume(bus: StringName) -> float:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return DEFAULT
	return 0.0 if AudioServer.is_bus_mute(i) else db_to_linear(AudioServer.get_bus_volume_db(i))


## Sets [param bus] to [param linear] (0..1) now; [param save] writes it.
static func set_volume(bus: StringName, linear: float, save: bool = false) -> void:
	_apply(bus, linear)
	if not save:
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SECTION, String(bus).to_lower(), snappedf(clampf(linear, 0.0, 1.0), 0.01))
	cfg.save(SETTINGS_PATH)


static func _apply(bus: StringName, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	linear = clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(i, linear <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.001)))

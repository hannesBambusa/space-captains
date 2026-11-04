extends Node
## Autoload "AudioDirector". Music and ambience that outlive scene changes:
## the ambient background loops all the time (menu and game); the intro
## music loops on top while the main menu is up and fades out over
## [constant FADE_TIME] when a game starts; the tutorial music loops while
## the tutorial game runs ([Tutorial] academy mode, until it is finished or
## quit). Buses: music on "Music", the ambience on "Ambient" (sends to
## Music, so the Music slider covers both); sound effects are the Sfx
## autoload's. The Music bus has a compressor keyed on the Voice bus
## (default_bus_layout.tres), so music and ambience dip while SOLA speaks.

const MENU_SCENE := "res://scenes/main_menu.tscn"
const MENU_MUSIC :="res://assets/audio/intro_music.mp3"
const AMBIENT := "res://assets/audio/ambient_background.mp3"
const TUTORIAL_MUSIC := "res://assets/audio/tutorial_music.mp3"
const TUTORIAL_VOLUME_DB := -8.0
const MENU_VOLUME_DB := -6.0
const AMBIENT_VOLUME_DB := -10.0
const FADE_TIME := 1.5
## Volume treated as silent at the ends of a fade.
const SILENT_DB := -60.0
## Seconds between checks of which scene is running.
const CHECK_INTERVAL := 0.25

var _menu: AudioStreamPlayer
var _ambient: AudioStreamPlayer
var _tutorial: AudioStreamPlayer
var _check := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_menu = _make_player(MENU_MUSIC, &"Music")
	_ambient = _make_player(AMBIENT, &"Ambient")
	_tutorial = _make_player(TUTORIAL_MUSIC, &"Music")


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = CHECK_INTERVAL
	var scene := get_tree().current_scene
	var in_menu := scene != null and scene.scene_file_path == MENU_SCENE
	_fade(_menu, in_menu, MENU_VOLUME_DB)
	_fade(_ambient, get_tree().current_scene != null, AMBIENT_VOLUME_DB)
	_fade(_tutorial, not in_menu and in_tutorial(), TUTORIAL_VOLUME_DB)


## The tutorial game is running (not the quick card of a normal game).
func in_tutorial() -> bool:
	var t := Tutorial.of(get_tree())
	return t != null and t.mode == Tutorial.ACADEMY and t.is_running()


## Drops the streams on exit, so the engine does not report them as leaked.
func _exit_tree() -> void:
	for p in [_menu, _ambient, _tutorial]:
		if p:
			p.stop()
			p.stream = null


func _make_player(path: String, bus: StringName) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	var stream := load(path) as AudioStreamMP3
	if stream:
		stream.loop = true
	p.stream = stream
	p.volume_db = SILENT_DB
	add_child(p)
	return p


## Fades [param p] in to [param volume_db] when [param on], else out and stops.
func _fade(p: AudioStreamPlayer, on: bool, volume_db: float) -> void:
	if p.stream == null or p.has_meta(&"fading_to") and bool(p.get_meta(&"fading_to")) == on:
		return
	if not on and not p.playing:
		return
	if on and p.playing and not p.has_meta(&"fading_to"):
		return
	p.set_meta(&"fading_to", on)
	if on and not p.playing:
		p.volume_db = SILENT_DB
		p.play()
	var tw := create_tween()
	tw.tween_property(p, "volume_db", volume_db if on else SILENT_DB, FADE_TIME)
	if not on:
		tw.tween_callback(p.stop)
	tw.tween_callback(p.remove_meta.bind(&"fading_to"))

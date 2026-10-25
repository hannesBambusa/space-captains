class_name LoadingScreen
extends CanvasLayer
## Full-screen cover while [SaveManager] swaps scenes (new game, load,
## back to the menu), so the player never sees the grey gap while the
## system scene builds and its shaders compile. Above every other layer.
## The scene build blocks the main thread, so nothing animates during it;
## the sweep bar only moves in the frames before and after.

const LAYER := 128
const FADE_TIME := 0.35
## Real seconds the cover stays up after the new scene is in, while the
## first frames render (shader compiles, cluster chunks).
const SETTLE_TIME := 0.5
const TIPS := [
	"Captains choose their own work. Post contracts and they decide if the pay is worth it.",
	"Rich clusters pay more, and raiders know it.",
	"Defence zones give mercenaries a place to patrol, and a kill bounty makes them keen.",
	"A disabled structure is never lost. It repairs itself over time.",
	"Researchers pick the funded project that suits them best.",
	"Double click anything to fly the camera to it. H takes you home.",
	"Cancelling a bounty nobody took gives the full reward back.",
]

var _root: Control
var _bar: ColorRect
var _sweep := 0.0


## Shows a new cover with [param title] (e.g. "Loading Game 3") and
## returns it once it has been drawn.
static func cover(tree: SceneTree, title: String) -> LoadingScreen:
	var ls := LoadingScreen.new()
	tree.root.add_child(ls)
	ls._build(title)
	# Two frames: one to lay out, one to present.
	await tree.process_frame
	await tree.process_frame
	return ls


## Keeps the cover for [constant SETTLE_TIME], fades it out, then frees it.
func reveal() -> void:
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(SETTLE_TIME, true, false, true).timeout
	if not is_inside_tree():
		return
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, FADE_TIME)
	tw.tween_callback(queue_free)


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if _bar == null:
		return
	_sweep = fmod(_sweep + delta * 0.6, 1.0)
	var track := _bar.get_parent() as Control
	var w := track.size.x * 0.28
	_bar.size = Vector2(w, track.size.y)
	_bar.position.x = lerpf(-w, track.size.x, _sweep)


func _build(title: String) -> void:
	var H := HudStyle
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.024, 0.032)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	# Faint warm glow low on the screen, like a star below the horizon.
	var glow := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.55, 0.15, 0.10))
	grad.set_color(1, Color(1.0, 0.55, 0.15, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 1.0)
	tex.fill_to = Vector2(0.5, 0.25)
	glow.texture = tex
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(glow)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	col.custom_minimum_size = Vector2(560, 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	_root.add_child(col)

	var logo := Label.new()
	logo.text = "SPACE CAPTAINS"
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.add_theme_font_override("font", H.font("SemiBold", true, false, 4))
	logo.add_theme_font_size_override("font_size", 52)
	logo.add_theme_color_override("font_color", H.ACCENT)
	col.add_child(logo)

	var sub := Label.new()
	sub.text = title.to_upper()
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_override("font", H.font("Medium", true, false, 3))
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", H.TEXT_DIM)
	col.add_child(sub)

	var track := Control.new()
	track.custom_minimum_size = Vector2(360, 2)
	track.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	track.clip_contents = true
	col.add_child(track)
	var rail := ColorRect.new()
	rail.color = H.HAIRLINE
	rail.set_anchors_preset(Control.PRESET_FULL_RECT)
	track.add_child(rail)
	_bar = ColorRect.new()
	_bar.color = H.ACCENT
	track.add_child(_bar)

	var tip := Label.new()
	tip.text = TIPS[randi() % TIPS.size()]
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(560, 0)
	tip.add_theme_font_override("font", H.font("Regular"))
	tip.add_theme_font_size_override("font_size", 14)
	tip.add_theme_color_override("font_color", H.TEXT_FAINT)
	col.add_child(UIUtil.spacer(8.0))
	col.add_child(tip)

extends SceneTree
## Writes ui/theme.tres from [HudThemeBuilder]. Run:
##   Godot --headless --path . --script res://scripts/ui/theme/generate_theme.gd

const OUT := "res://ui/theme.tres"


func _init() -> void:
	var builder: Script = load("res://scripts/ui/theme/hud_theme_builder.gd")
	var theme: Theme = builder.call(&"build")
	var err := ResourceSaver.save(theme, OUT)
	print("theme -> %s: %s" % [OUT, error_string(err)])
	quit(0 if err == OK else 1)

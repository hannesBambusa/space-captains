class_name Corp
extends RefCounted
## One corporation of the game: the player's, or the rival AI's (rival
## corporation plan). Each holds its own wallet and ore ([member economy],
## a [CorpEconomy]) and its own research ([member research], a
## [CorpResearch]). The player's are the Economy and Research autoloads; the
## rival's are children of the [Corps] autoload. Every station belongs to one
## corp (Corps.corp_of_system); node-side code asks [method Corps.of].

var id: StringName
var display_name: String = ""
## Marker and station tint.
var color := Color(1.0, 0.75, 0.3)
var economy: CorpEconomy
var research: CorpResearch
## The rival's strategy state (RivalMind), null for the player.
var mind: RivalMind


func is_player() -> bool:
	return id == Corps.PLAYER

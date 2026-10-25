class_name Fmt
extends RefCounted
## Text formatting shared by the game code and the HUD (UIUtil passes these
## on): credit amounts, sim clock times, plurals.


## "2,000" style thousands separators.
static func amount(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if value < 0 else "") + s + out


## "3:05" from sim seconds.
static func clock(t: float) -> String:
	var s := int(t)
	return "%d:%02d" % [floori(s / 60.0), s % 60]


## "Miner" -> "Miners", "Mercenary" -> "Mercenaries".
static func plural(word: String) -> String:
	if word.ends_with("y") and word.length() > 1 and not "aeiou".contains(word[word.length() - 2]):
		return word.left(word.length() - 1) + "ies"
	return word + "s"

class_name ModuleTips
extends RefCounted
## Tooltip text for ship modules, shared by the Factory panel, the Outfitter
## section, the captain panel and the Science Lab panel: what a module does
## in numbers (ShipModule.effect_text) and whether research still locks it.


## "Shield Projector Mk II (defense, for miners and salvagers), 340 cr" + effects
## + blurb + the research lock.
static func tip(m: ShipModule, f: Factory = null) -> String:
	if m == null:
		return ""
	var who := "any role" if m.roles.is_empty() else "for " + " and ".join(_plural_roles(m.roles))
	var lines: PackedStringArray = ["%s (%s, %s), %s cr" % [m.display_name, ShipModule.SLOT_NAMES[m.slot].to_lower(), who, UIUtil.amount(m.cost)]]
	var fx := m.effect_text()
	if not fx.is_empty():
		lines.append(fx[0].to_upper() + fx.substr(1))
	if not m.blurb.is_empty():
		lines.append(m.blurb)
	var locked := Research.module_lock_reason(m.id)
	if not locked.is_empty():
		lines.append(locked)
	elif f:
		var why := f.make_block_reason(m)
		lines.append("%d in stock%s" % [f.stock_of(m), ", " + why.to_lower() if not why.is_empty() else ""])
	return "\n".join(lines)


## One line: "Deflector Mk I: +80 hull, +260 shields" or "... needs research: X".
static func line(m: ShipModule, f: Factory = null) -> String:
	var locked := Research.module_lock_reason(m.id)
	if not locked.is_empty():
		return "%s: %s" % [m.display_name, locked.to_lower()]
	var stock := ""
	if f:
		stock = ", %d in stock" % f.stock_of(m)
	return "%s: %s%s" % [m.display_name, m.effect_text(), stock]


## Modules of [param slot] and [param tier], one line each.
static func cell_tip(slot: int, tier: int, f: Factory) -> String:
	var lines: PackedStringArray = ["%s %s" % [ShipModule.SLOT_NAMES[slot], ShipModule.TIER_NAMES[tier]]]
	for m in ModuleCatalog.shared().modules:
		if m and m.slot == slot and m.tier == tier:
			lines.append(line(m, f))
	return "\n".join(lines)


## What the Outfitter can offer: researched modules with their numbers, then
## the locked ones grouped by the tech they need.
static func catalogue_tip(f: Factory) -> String:
	var offered: PackedStringArray = []
	var by_tech := {}
	for m in ModuleCatalog.shared().modules:
		if m == null or m.tier < 1:
			continue
		var t := Research.catalog().for_module(m.id)
		if Research.is_module_unlocked(m.id):
			offered.append(line(m, f))
		elif t:
			if not by_tech.has(t.display_name):
				by_tech[t.display_name] = PackedStringArray()
			(by_tech[t.display_name] as PackedStringArray).append(m.display_name)
	var lines: PackedStringArray = ["Researched (%d):" % offered.size()]
	lines.append_array(offered)
	if not by_tech.is_empty():
		lines.append("")
		lines.append("Needs research at the Science Lab:")
		for tech: String in by_tech:
			lines.append("%s: %s" % [tech, ", ".join(by_tech[tech])])
	return "\n".join(lines)


## Researched modules of tier 1+ against all of them.
static func offered_count() -> Vector2i:
	var n := 0
	var all := 0
	for m in ModuleCatalog.shared().modules:
		if m and m.tier >= 1:
			all += 1
			if Research.is_module_unlocked(m.id):
				n += 1
	return Vector2i(n, all)


static func _plural_roles(roles: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = []
	for r in roles:
		out.append(UIUtil.plural(r).to_lower())
	return out

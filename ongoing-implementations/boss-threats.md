# Boss threats (warlord and the Swarm)

| | |
|---|---|
| **Status** | built (warlord and Swarm); needs your play test |
| **Branch** | main (uncommitted) |
| **Updated** | 2026-11-10 |
| **Scope** | Idea 7 of the 2026-11-10 list, both bosses (user's pick): a named pirate warlord with a flagship, then the Swarm (rogue drones that spread). |

## Files

**Owned:**

- `scripts/enemies/warlord_ship.gd`: WarlordShip (flagship, retreat)
- `scripts/enemies/warlord_director.gd`: WarlordDirector (schedule, arrival, outcomes, save)
- `tools/warlord_test.gd`, `tools/warlord_test.tscn`
- `data/factions/swarm.tres`, `data/loadouts/swarm_drone.tres`
- `tools/swarm_test.gd`, `tools/swarm_test.tscn`

**Shared:**

- `scripts/combat/combat_world.gd`: `warlords` member and its creation (home only)
- `scripts/save/game_snapshot.gd`: "warlord" key, load and `relink` after the ship links
- `scripts/save/ship_codec.gd`: "warlord" dict in `_save_scavenger`, WarlordShip branch in `_create_scavenger`
- `scripts/ui/tutorial.gd`: `_apply_safety` turns `warlords.enabled` off
- `scripts/ui/overview_panel.gd`: the warlord rows in the threats section
- `data/systems/home_system.tres`: the "Swarm Hive" DenDef (arrival 5, 80 min) and the swarm faction ext_resource
- `scripts/enemies/scavenger_den.gd`: SWARM_* constants, `growth`, `spawn_limit`, `_swarm_step`, growth in save/load
- `scripts/enemies/threat_director.gd`: `extra_dens`, `bud_hive`, `_bud_def`, `_template`, "extra_dens" in save/load
- `scripts/enemies/faction_def.gd` (`always_tint`), `scripts/scavenger_ship.gd` (tints its own model when set)
- `scripts/ui/overview_panel.gd` and `scripts/ai/merc_fleet.gd`: `spawn_limit()` instead of `def.spawn_cap`
- `docs/DESIGN.md` (Enemies: the warlord and Swarm bullets), `CLAUDE.md` (Run line)

## Built

**Warlord schedule.** WAITING (first at threat clock 45 min with a base standing, later ones at `next_at`), WARNED (90 s, THREAT feed and a red toast "Warlord raid: ..."), PRESENT, AWAY (12 min +-2). `scripts/enemies/warlord_director.gd`

**Flagship.** ScavengerShip subclass, no den (so the brain never flees), raider at the RaidDirector's objective; hull x14, shields max(x6, 900), regen max(x2, 25), damage x2.2, fire x1.4, range x1.25, speed x0.85; model x2.6, tint 0.3 red plus an OmniLight glow. Retreat below 30%: steers away from the station, warps after 8 s, gone at 14 km or 45 s. `scripts/enemies/warlord_ship.gd`

**Escorts.** `escort_count` = 2 + generation - 1 + visit - 1, max 5; plain ScavengerShips with `ai.set_guard(flagship, 650, 120)`; they withdraw on their own when the flagship is gone (ScavengerBrain guard rule).

**Outcomes.** Kill: 3,000 + 1,000 per return (Ledger.BOUNTIES), scrap x10 for 3x the life, a tier 2 or 3 part via `Factory.add_rare_part`, `Reputation.KILL * 4` and a history line per attacker in the last 240 s, next warlord 40 min later. Kills of player captains counted (`combatant_destroyed`).

**Overview.** HOSTILES OUT lists the flagship (a ship row, counted as raiding) and a line from `outlook_text` (inbound countdown, here with N escorts, away and back in ~). `scripts/ui/overview_panel.gd`

**Save.** Director state under "warlord"; the flagship as a scavenger dict plus "warlord" {name, title, visit, retreat}; escorts keep their guard by save id. `relink` finds the flagship by group after the load.

**Tests.** `tools/warlord_test.tscn` on 2026-11-10: 16 WARLORD ok (warning, arrival, 2 escorts, raiding, save round trip with escorts, retreat, away, return with 3 escorts, kill, +4,000 reward, next scheduled). Window shot: dark red flagship with a glow, far bigger than escorts. Smoke default 0 errors; tutorial test all ok.

**The Swarm.** Faction "swarm" (drones on the construction drone hull, tinted; 70 hull, packs of 4, never flee or steal, hunt armed ships too, raids of 5 to 8 that shoot every structure). The home system's Swarm Hive arrives through the ThreatDirector (order 5, 80 min, 10 captains / 7 structures). A hive grows one drone every 240 sim s (max +8) and buds at growth 3 and 6 (`ThreatDirector.bud_hive`, max 3 standing); budded hives are runtime DenDefs saved as "extra_dens". `scripts/enemies/scavenger_den.gd`, `scripts/enemies/threat_director.gd`, `data/factions/swarm.tres`

**Swarm tests.** `tools/swarm_test.tscn` 2026-11-11: hive in place (5,200 hull), growth 3 (limit 9), a second hive budded, 15 drones out, save round trip keeps both hives and the growth. Window shot: green hive and drones, "THE SWARM" in the overview.

## Gotchas

- **A subclass constant may not reuse a parent's name.** `const GROUP` in WarlordShip clashed with Ship.GROUP and broke every script that depends on Ship (hundreds of "Failed to compile depended scripts"; the test then hangs). It is `WARLORD_GROUP`.
- **A headless tool scene with a parse error never quits.** Run new tool scenes with a timeout.
- **The toast colour comes from the words** (`PauseMenu.toast`: "raid" or "under attack" is red). Warlord threat toasts say "Warlord raid: ...".

## Remaining

- **Balance probe:** how many stock / Mk I mercs kill a flagship (hull 4,200 + 900 shields for a scavenger warlord); only forced damage was tested.
- **Flagship model:** a stand-in (the faction raider scaled and tinted). A Blender flagship in `blender/` would read better (needs the user's taste).
- **Swarm "8/6 out":** a launching pack of 4 overshoots the cap shown in the overview; cosmetic. `scripts/enemies/scavenger_den.gd` spawn_pack
- **Swarm models:** the hive is the scavenger hideout tinted green and the drones are the construction drone; Blender models would read better.
- **Swarm balance:** not probed against real defences; only growth and budding were tested.

## Open questions

- None.

## Decisions

- **Warlord v1 is home only.** Forward stations and rival worlds get none.
- **Driven off, it comes back stronger** (one escort more per return); killed, a new warlord follows 40 min later. Keeps a late-game peak.
- **No new ShipCodec kind:** the flagship saves as a scavenger with an extra "warlord" dict (the ClaimConstructor pattern).

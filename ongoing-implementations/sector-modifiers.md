# Sector modifiers

| | |
|---|---|
| **Status** | built; needs your play test of the balance |
| **Branch** | main (uncommitted) |
| **Updated** | 2026-11-10 |
| **Scope** | Idea 9 of the 2026-11-10 list: one sector modifier per game, picked on the New game page or Random. |

## Files

**Owned:**

- `scripts/cluster/sector_modifier.gd`: SectorModifier (the table, `find`, `num`, `random_pool`, `name_of`)
- `tools/sector_modifier_test.gd`, `tools/sector_modifier_test.tscn`

**Shared:**

- `scripts/cluster/sector.gd`: `modifier`, `next_modifier`, `set_next_modifier`, `_load_settings`, `take_announcement`, the pick in `reset`, "modifier" in `save_state` / `load_state`
- `scripts/save/save_manager.gd`: `new_game` keeps the tutorial Standard
- `scripts/ui/main_menu.gd`: SECTOR row and hint on the New game page
- `scripts/ui/hud.gd`: `_announce_sector`
- `scripts/cluster_def.gd` (`get_reserve`), `scripts/enemies/threat_director.gd` (threat clock), `scripts/enemies/raid_director.gd` (`interval`, `wave_size`, first raid), `scripts/buildings/factory_market.gd` (`willing_price`), `scripts/cluster_spawner.gd` (`_pick_ore`): one modifier line each
- `tools/smoke_test.gd`, `tools/smoke.sh`: `--modifier=ID`, Standard by default
- `docs/DESIGN.md` ("Sector modifiers"), `CLAUDE.md` (Run lines)

## Built

**Table.** Standard, Motherlode, Backwater, Pirate haven, Boom market, Crystal rush; keys reserve, threat, raid_interval, raid_extra, ore_price, iron / titanium / crystal, credits_add. `scripts/cluster/sector_modifier.gd`

**Pick and save.** `Sector.reset` takes `next_modifier` (Random rolls from the five others with Sector's rng), adds credits_add to `Economy.credits`. Saved as "cluster"."modifier"; `load_state` sets it first, so a save without the key is Standard. Next choice in user://settings.cfg [sector] modifier. `scripts/cluster/sector.gd`

**UI.** New game page SECTOR chips (HFlowContainer) with the blurb under them; first feed line "Sector survey: <name>. <blurb>" and a toast in a non-standard game. `scripts/ui/main_menu.gd`, `scripts/ui/hud.gd`

**Tests.** `tools/sector_modifier_test.tscn` on 2026-11-10: every modifier matches Standard times its numbers (start credits, reserve, raid interval, iron price, threat clock), Random, tutorial Standard, save round trip and an old save: all ok. Smoke default and `--modifier=pirate_haven --minutes 12` 0 errors (first raid 6:06 against 8:30).

## Gotchas

- **Smoke and tests must set `Sector.next_modifier` themselves.** It comes from the player's settings otherwise, and every number drifts. `tools/smoke_test.gd`
- **Start credits read after any sim time include Factory sales**, which ore_price changes. Compare credits before stepping. `tools/sector_modifier_test.gd`

## Remaining

- **Play test (user):** is each modifier fun and fair; Pirate haven and Motherlode early game in particular.

## Open questions

- None.

## Decisions

- **Five modifiers plus Standard, numbers chosen by Claude** (user picked "Pick or Random"). Modifiers only scale existing tuning; none changes the seeded network, so seeds and SystemGenerator.VERSION stay.
- **Random never rolls Standard.** A player who picks Random wants something different.

# Rival corporation

| | |
|---|---|
| **Status** | ready for review |
| **Branch** | — |
| **Updated** | 2026-11-03 |
| **Scope** | A full-mirror AI rival corp, home 4 to 5 jumps out, that picks peace, pact, harassment or war on its own. R0 to R8 and M1 (1 to 3 rivals that also deal with each other) built and smoke-tested; not playtested or visually checked. |

Planned on 2026-11-02 from an interview with the user; work started the same day.

## Files

**Owned**:

- `scripts/corp/**`: `corp.gd` (Corp), `corps.gd` (autoload "Corps", class CorpRegistry)
- `scripts/rival/**`: `rival_mind.gd`, `rival_corp.gd`, `rival_manager.gd`, `war_strikes.gd`, `station_loss.gd`
- `scripts/ui/rival_panel.gd`, `scripts/ui/treaty_card.gd`, `scripts/ui/end_screen.gd`

**Shared** (stage hunks; `scripts/miner_ship.gd` and `scripts/sfx.gd` also carry the user's own uncommitted changes and are not touched by this feature):

- `project.godot` (Corps autoload after Sector)
- `scripts/cluster/`: `cluster_network.gd`, `system_generator.gd`, `forward_stations.gd`, `system_host.gd`, `station_supply.gd`, `derelict_loot.gd`, `discovery_bounty.gd`
- `scripts/economy.gd`, `scripts/research/research.gd`, `scripts/system_world.gd`, `scripts/view_manager.gd`, `scripts/event_log.gd`, `scripts/selection_controller.gd`
- `scripts/combat/`: `combat.gd`, `combat_world.gd`, `static_combatant.gd`, `projectile_pool.gd`
- `scripts/building.gd`, `scripts/building_manager.gd`, `scripts/buildings/`: `factory.gd`, `factory_market.gd`, `outfitter.gd`, `salvage_yard.gd`, `science_lab.gd`, `structure_repair.gd`, `structure_hull.gd`, `defense_structure.gd`, `defense_turret.gd`, `forward_station_yard.gd`
- `scripts/contracts/contract.gd`, `scripts/contracts/contract_board.gd`, `scripts/save/`: `contract_codec.gd`, `game_snapshot.gd`, `save_manager.gd`, `ship_codec.gd`
- `scripts/ai/`: `captain_brain.gd`, `mercenary_brain.gd`, `merc_fleet.gd`, `decision_notes.gd`; `scripts/enemies/scavenger_brain.gd`, `scripts/enemies/gate_raid_source.gd`; `scripts/defense/`: `defense_zones.gd`, `defense_zone.gd`, `colony_alarm.gd`
- `scripts/ships/`: `ship.gd`, `ship_loadout.gd`, `cargo_shuttle.gd`, `repair_bay.gd`, `mobile_station.gd`; `scripts/lander_ship.gd`, `scripts/progression/career.gd`
- `scripts/ui/hud.gd`, `scripts/ui/top_bar.gd`, `scripts/ui/main_menu.gd`
- `tools/smoke.sh`, `tools/smoke_test.gd`
- `docs/DESIGN.md` ("Rival corporation" section, stage R), `CLAUDE.md` (conventions and smoke flags)

## Built

**R0 deeper network.** A rival region past the tree: a chain from a depth-3 system to `ClusterNetwork.rival_id` at depth 4 or 5, plus 2 to 3 side systems at depth 4 to 5 (own rng, appended last, so v2 systems keep their content). Rival home danger 2 (`RIVAL_HOME_DANGER`), its first two clusters iron, the first danger 1. 7 to 14 remote systems over 60 seeds, rival always at depth 4 to 5. `SystemGenerator.VERSION` 3, `SEED_VERSION` 2. Files: `scripts/cluster/cluster_network.gd`, `scripts/cluster/system_generator.gd`.

**R1 corps.** `Corps` autoload: player corp (Economy, Research autoloads) and, unless Off, a rival corp with its own `CorpEconomy` and `CorpResearch` children (grant x0.8 / 1 / 1.3 by difficulty). Ownership by system (`Corps.corp_of_system`: site "corp"), by node (`Corps.economy(node)`, `Corps.research(node)`, `Corps.owner_of(ship)` via its home building). Contracts carry `corp` (set from `Corps.acting` in `ContractBoard.post`, saved by ContractCodec), pay from `Contract.eco()`; `ContractBoard.get_available(type, system, corp)` and `CaptainBrain.corp_id()` keep captains on their corp's work. `Corps.act_as(corp, fn)` for things a corp starts. Difficulty: `Corps.next_difficulty` (user://settings.cfg [rival]) → `Corps.difficulty` on new game; saved under "corps". Files: `scripts/corp/corps.gd`, `scripts/corp/corp.gd`.

**R2 rival colony.** `RivalCorp` (ViewManager child) founds the HQ on a new game: site with corp "rival", hq true, home station model, pinned live (`RivalCorp.hq_site`). `SystemWorld.is_hq`: full bays, its own Factory, no StationSupply, raids like home (no arrivals). `RivalManager` (child of the HQ world, stateless) ticks every 20 / 12 / 8 s (Easy / Normal / Hard) and takes up to 2 steps: mining outpost, miners, mining contracts (safest, iron first while short), escorts, merc outpost and mercs, defence zone, turrets, Science Lab and research (`TECH_ORDER`), Outfitter, Salvage Yard, shield, den bounty, Explorer Outpost; keeps 300 iron / 80 titanium / 20 crystal on its Factory. `RivalMind` holds stance, relations, grudge, intel (saved under "corps"."rival"."mind"). Measured (smoke --rival, 30 min): 2 mining outposts, 5 miners, 2 mercs, ~250 iron; 10 sim min cost 11.8 s real vs 6.3 s without. Save round trip identical. Files: `scripts/rival/*.gd`.

**R3 combat sides.** `Combat.Faction.RIVAL` for the rival's ships (`Ship.get_faction`, cached per home) and structures (`StaticCombatant.get_faction`, by system corp); `Ship.faction` stays PLAYER, so pirates hunt both corps. `Combat.hostile(PLAYER, RIVAL)` is `Corps.corps_at_war()`. Turrets, zones, colony alarm and merc targeting use their own side; shield bubbles stop only hostile shots (`ProjectilePool._side`). Pirate raids on the rival HQ run through its own RaidDirector like home's. Files: `scripts/combat/combat.gd`, `scripts/combat/static_combatant.gd`, `scripts/combat/projectile_pool.gd`.

**R4 discovery and first contact.** Briefing at game start. The rival charts one system per `RivalCorp.scout_time()` while its Explorer Outpost has an explorer (`RivalMind.stats["charted"]`); charting home sets `located_player`. The player surveying its home (`Sector.surveyed`) sets `located_by_player`. Either one opens contact (feed, toast). Personality revealed 10 min after. Rival news goes to its intel (`EventLog._is_rivals`, `EventLog.post_public`; `MobileStation._feed` for data-path convoy lines). Rival assets cannot be selected (`SelectionController.select`). Files: `scripts/rival/rival_corp.gd`, `scripts/event_log.gd`.

**R5 boardroom and diplomacy.** `RivalCorp.stance_scores` / `_meeting` (personality `WEIGHTS`, `STAY_BONUS`, intel line with scores and runner-up), war ends only by a treaty, tribute demands. Offers in `RivalMind.offer`, answered by `answer_offer` (accept, reject, counter; 60 s real time). Player proposals: `propose_problem` / `player_proposes` (pact, tribute, peace, war). UI: `RivalPanel` (R, top bar RIVAL button with the stance), `TreatyCard`; main menu "Rival corporation" button cycles the difficulty. Files: `scripts/rival/rival_corp.gd`, `scripts/ui/rival_panel.gd`, `scripts/ui/treaty_card.gd`, `scripts/ui/top_bar.gd`, `scripts/ui/hud.gd`, `scripts/ui/main_menu.gd`.

**R6 harassment, war, poaching.** Ops every `op_time()`: `GateRaidSource.form_hired` (deniable hired gate raid), shuttle sabotage, `poach_from_player`. War strikes: `WarStrikes.volunteers` / `launch` (war bonus, personality and Loyalty chance), `MercenaryBrain.strike_to` and `Mode.STRIKE` (gate trip, `strike_targets` shield > turrets > structures > ships, home after `STRIKE_TIME` or when hurt; `strike_system` saved in `ShipCodec.MERC_FIELDS`). 75 s warning before a rival strike. Kills between corps feed grudge and losses (`RivalCorp.note_destroyed` from `Ship.destroy`, `note_disabled`). Files: `scripts/rival/war_strikes.gd`, `scripts/ai/mercenary_brain.gd`, `scripts/enemies/gate_raid_source.gd`.

**R7 destruction and the end.** `StructureHull` station hulls: `scuttle_left` (90 s HQ, 60 s forward) at 0 hull from the other corp at war, still a target, saved at 15%; `StationLoss.lose` / `destroy_station` / `eliminate`. `EndScreen` (defeat: pause, `SaveManager.mark_lost`, main menu only; victory: Continue playing). Lost slots never load or save, Continue skips them (`SaveManager.is_lost`, settings [lost]). Files: `scripts/buildings/structure_hull.gd`, `scripts/rival/station_loss.gd`, `scripts/ui/end_screen.gd`, `scripts/save/save_manager.gd`.

**R8 rival forward stations.** `MobileStation.corp` (saved), `set_destination_site` for the AI, corp carried into the founded site (live and data paths). `ForwardStations.ids/count/free_slots` per corp. `RivalManager._forward_station` (from `forward_after` min, water shipped by the corp), `_dispatch`, `_pick_target` (charted, between the charters, danger at most 4); a smaller plan at rival forward stations; no water use for rival stations. Files: `scripts/ships/mobile_station.gd`, `scripts/cluster/forward_stations.gd`, `scripts/rival/rival_manager.gd`.

**M1 1 to 3 rivals.** `Corps.rivals` (`rival_1..3`, `RIVAL_IDS`, `norm` maps the pre-M1 "rival"), `next_rival_count` (main menu "Rivals" button, settings [rival] count), one difficulty for all. `ClusterNetwork.generate(seed, regions)`: one region per rival from a different depth-3 root (farthest from the homes before it, else a connector), `rival_ids`; `Sector` saves "regions". `Combat.Faction.RIVAL_1..3` with `faction_of_corp` / `corp_of_faction`; `Corps.corps_at_war(a, b)` per pair. `RivalMind.Tie` per known corp (stance, relations, grudge, losses, weariness, contact, i_know_them / they_know_me, pact, ceasefire, strike timer, the player's offer); old minds load into the player tie. `RivalCorp` runs every rival: per-tie boardroom, mutual wars, AI-to-AI offers (`_ai_answer`), `first_offer` / `answer_offer(rid, ...)`, `player_proposes(rid, ...)`; scouting toward shallow systems, then the deep ones once it found you. `StationLoss.eliminate(tree, rid, by)`: captains to the destroying corp; victory when no rival is left. UI: Rival panel tabs, top bar RIVALS chip, offer queue, end screen per rival. `RivalManager` per station corp: Explorer Outpost first once Jump navigation (now its first tech) is done; extras and tech funding wait while it saves for the Science Lab or the Explorer Outpost. Measured: 3 rivals 5 to 9 jumps apart over both branches (21 systems); forced lab: found the player at 23 min, war at 24; round trips identical with 2 and 3 rivals; natural 75 min with 3 rivals: rival 1 found the player, went to war at 64 min and found rival 3 at 69 min (contact, peace so far); `--rivals=3 --eliminate` ends in victory with 8 captains signed on.

**Smoke coverage.** `--rival` (report), `--rival --save-roundtrip` (identical at 8:01, also at war), `--rival --war`, `--rival --eliminate` (HQ scuttled, rival eliminated, its captains joined the player), `--rival --expand` (2 rival forward stations, player slots untouched). Regression runs (default, `--forward --save-roundtrip`, `--colony`, `--explore`, `--multi`, `--long`) pass with 0 errors; `--long` keeps its documented sources (Corvus, Fennick).

## Gotchas

- **A new `class_name` is unknown until the class cache is rebuilt.** Headless runs fail with "Could not find type" until `Godot --headless --path . --import` runs once. `.godot/global_script_class_cache.cfg`
- **Smoke ledger entry counts vary run to run** (merging is timing-sensitive); credits match. Do not read a changed entry count as a regression.
- **`Array(SOME_PACKED_CONST)` shares the constant**: erasing from it mutated `Corps.RIVAL_NAMES` and the name pool ran dry after a reload. Copy element by element. `scripts/corp/corps.gd` `_make_rival`
- **A smoke reload check must pause the sim while the scene settles**: a payout in those frames reads as a save diff. `tools/smoke_test.gd` `_rival_roundtrip`
- **A parse error makes `tools/smoke.sh` hang instead of fail** (Godot waits). Parse-check changed files first (`Godot --headless --path . --check-only -s res://<file>`, read only "Parse Error" lines: autoload names show as compile errors there).
- **Rival economy outcomes vary a lot by network seed** (where its iron clusters drift): one 60 min run reached 3 mining outposts and the Science Lab, another 1 to 2 outposts. `scripts/rival/rival_manager.gd`
- **`EventLog.post` drops lines about the rival's things** (target owned by the rival, or no target while `Corps.acting` is the rival). RivalCorp's own announcements must use `EventLog.post_public`. `scripts/event_log.gd`
- **The smoke test reseeds every new node's RNG members in order** (`_seed_rngs`): new nodes with RNGs shift the seeds of everything after them, so `--rival` runs differ from Off runs on the player side too.

## Remaining

- **Sim slows down badly late in a 3-rival war** — a natural `--rivals=3 --minutes 75` run took 1,872 s real (a 60 min run without a war: 214 s). Profile the war phase (strike targeting, transits, turrets). `scripts/ai/mercenary_brain.gd` `strike_targets`, `scripts/rival/rival_corp.gd`
- **A rival with an explorer charted nothing in one run** (rival_2, 75 min: Explorer Outpost and explorer present, charted 0). Check `RivalCorp._has_explorer` (outpost disabled by raids?). `scripts/rival/rival_corp.gd`
- **Speed with 3 rivals** — about 3.5 to 4x the sim cost of a game without; check the frame time at 24x in the real game. `scripts/cluster/system_host.gd`
- **Playtest and look at the UI in the game** — RivalPanel, TreatyCard, EndScreen and the top bar RIVAL button only ran headless (smoke opens the panel and reads its texts). Check layout at 1920x1080 and on small windows. `scripts/ui/rival_panel.gd`, `scripts/ui/treaty_card.gd`, `scripts/ui/end_screen.gd`
- **Rival growth tuning** — on some seeds it stays at 1 to 2 mining outposts for an hour (far, drifting clusters, miners dying). Measure over several `--net-seed` values with `--rival --minutes 60`. `scripts/rival/rival_manager.gd`
- **Rival markers and tint** — its ships and stations use the player's colours on the map, minimap and markers; `Corp.color` exists but nothing reads it. `scripts/ui/ship_markers.gd`, `scripts/ui/minimap.gd`
- **War strikes against a forward station** — strikes only target a corp's home (`WarStrikes.launch` target system); striking a rival forward station system works but nothing picks one. `scripts/rival/rival_corp.gd`, `scripts/ui/rival_panel.gd`

## Open questions

- Should the player get deniable sabotage too (hiring pirates against the rival)? (v1: no)
- If ms per step gets bad with 3 rival stations live, should unviewed rival worlds fall back to a data sim like RemoteSim? (v1: always pinned live; 10 sim min cost 11.8 s real against 6.3 s without a rival)
- What utility weights per stance, personality and difficulty feel right? (current: `RivalCorp.WEIGHTS`, `stance_scores`)
- Treaty terms: reparations size (30% of its credits, 200 to 2,000 cr), non-aggression length (20 min), exclusion zones (not built)?
- Victory screen contents and what changes in Continue playing (today: stats lines; the sector simply runs on without the rival)?
- Is the AI-only iron swap acceptable, or should the rival get the player's tools (planet raids, refinery) instead?

## Decisions

- **Full mirror, not an abstract corp.** The user wants a real rival playing the same rules.
- **Ownership by node (`Corp` plus `X.of(node)`), not a parallel rival copy.** One code path, and it fits the existing node-scoped lookups.
- **The AI chooses its own stance among peace, pact, harassment, war and suing for peace, and it sues for peace when losing.** The user wants it to decide freely, including "terror for fun".
- **Rival home at depth 4 or 5 past a branch tip (7 to 14 systems), not a third home gate.** Keeps home's fixed `.tres` and puts the rival far away.
- **The rival expands with up to 2 forward stations.** A contested middle; reuses F6.
- **Three sides; pirates hostile to both.** Keeps the AI honest and gives it losses.
- **Home stations can be destroyed, only by the other corp at war; losing yours is game over with the save marked lost.** The user wants real stakes. Pirates only disable, so an early raid never ends a run.
- **Rival eliminated means victory plus Continue playing.**
- **Difficulty Off / Easy / Normal / Hard on New game; smoke defaults to Off plus a `--rival` flag.** A way out of the rival, and stable tests.
- **Both sides must find each other.** An early-game window before contact (the rival's side is abstract, see below).
- **Treaty cards do not pause, 60 s, ignoring counts as reject.**
- **Boardroom plus Manager, acting only through the HUD's public calls; ordinary captain brains.** Same rules for both corps, indirect control for the AI too.
- **All rival stations pinned live in v1.**
- **Tree depth stays 3; the rival region is appended past it (own rng, last ids), not MAX_DEPTH 5 for the whole tree.** Keeps every v2 system's content and the smoke seeds; `SEED_VERSION` stays 2 while `VERSION` is 3.
- **Pirates raid the rival as much as the player; rival home danger 2 (one base at the start, like home).** User decision; danger 3 (two bases) killed its miners faster than it could hire.
- **Rival scouting is a timed program at its Explorer Outpost, not explorers flying the player's survey code.** The survey code writes player-global charts (Sector.reveal, discoveries); a second chart set would touch the whole fog and map UI.
- **War strikes are volunteer runs for a war bonus (`WarStrikes`), not bounty contracts on stations.** Merc bounty evaluation, fleets and system filters assume same-system targets; a strike mode is a smaller change.
- **AI crutches, rival only:** corp office iron swap, water shipped for its Forward Station, no water upkeep, no Salvage Yard. It has no planet raids or refinery and the yard's auto-buy drained its credits.
- **Rival assets cannot be selected.** Their panels would spend the rival's money with the player's clicks.
- **1 to 3 rivals, picked on New game; one difficulty for all.** User decision.
- **Rivals deal with each other when they meet** (war, pacts, raids between them), not only with the player. User decision.

# Planet outposts

| | |
|---|---|
| **Status** | built (follow-ups done but the play test and raid sizes), needs a play test |
| **Branch** | main (S0 to S5 in db35437, follow-ups in c4c3778, raider range fix in 2090349; all committed) |
| **Updated** | 2026-11-05 |
| **Scope** | Surface outposts on planets and moons (4 km landing zone, own world while viewed), replacing planet raids. S0 to S5 built; follow-ups in Remaining. |

## Files

**Owned:**

- `scripts/surface/outpost_state.gd`: OutpostState, the data of one outpost and every tuning constant
- `scripts/surface/outposts.gd`: Outposts (ViewManager child): founding, shared rules, data sim, raids, claim_blocked
- `scripts/surface/surface_terrain.gd`, `shaders/terrain_surface.gdshader`: heightfield and ground shader
- `scripts/surface/surface_world.gd`: live world (units, combat, picking)
- `scripts/surface/surface_mode.gd`: planet mode overlay, camera, input
- `scripts/surface/surface_models.gd`: loads `assets/models/surface/<id>.glb`, primitive stand-ins for the rest (floater, storm_cell, deposits)
- `blender/gen_surface.py` (`-- --only=<id>[,<id>]`, `--no-textures`, `--no-preview`, `--no-sheet`; full run about 3 min), `blender/surface/<id>.blend`
- `assets/models/surface/<id>.glb` (+ extracted textures and `.import`) for landing_pad, harvester_bay, garrison, ground_turret, shield_dome, harvester, hover_tank, raider_tank, critter, nest, platform
- `blender/textures/surface_<id>_{albedo,mr,normal}.jpg`, `_decals.png`; `blender/previews/surface_<id>.png`, `blender/previews/surface_sheet.png`
- `scripts/surface/uplink_shuttle.gd`: the station-system flights, visual only: lifts up onto a docking pad, the founding lander (dropship) down to the planet
- `scripts/surface/raid_dropship.gd`: RaidDropship, a ground raid's dropship on the live surface (visual only)
- `scripts/ui/surface_hud.gd`: planet mode HUD
- `scripts/planet_info.gd`: find_planet, danger_for (moved off the raid contract)

**Shared:**

- `scripts/cluster/sector.gd` (outposts dict, save), `scripts/view_manager.gd` (Outposts child)
- `scripts/ui/planet_panel.gd` (OUTPOST section, raid form gone), `scripts/ui/overview_panel.gd`, `scripts/selection_controller.gd` (double-click)
- `scripts/enemies/planet_claims.gd`, `scripts/enemies/threat_director.gd` (claim_blocked)
- `scripts/building_manager.gd` (_retire_dock), `scripts/solar_system.gd` (add_station falls back to another planet for old saves, `_fallback_host`), `scripts/save/{contract_codec,ship_codec,game_snapshot,save_manager}.gd`
- Raid removal edits: `scripts/ai/{captain_brain,decision_notes}.gd`, `scripts/contracts/{contract,contract_board,contract_markers}.gd`, `scripts/enemies/{scavenger_brain,claim_garrison}.gd`, `scripts/ships/ship_loadout.gd`, `scripts/combat/scrap_field.gd`, `scripts/defense/defense_zones.gd`, `scripts/economy.gd`, `scripts/ui/{top_bar,contract_strip,contract_row,pilot_card,factory_panel,captain_panel,post_contract_form,research_tip,pilot_roster,tutorial_card,hud}.gd`
- Deleted (follow-ups): the Raider Dock model: `assets/models/buildings/raider_dock*` (glb, 3 textures, imports), `blender/gen_raider_dock.py`, `blender/raider_dock.blend`, `blender/textures/raider_dock_*`, `blender/previews/raider_dock_*`, `assets/ui/icons/build/raider_dock.png` (+ import); its line in `blender/render_icons.py`. `BuildingManager.RETIRED_DOCK` stays for old saves.
- Deleted: `scripts/contracts/planet_raid_{contract,rules}.gd`, `scripts/lander_ship.gd`, `scripts/ai/lander_{brain,evaluator}.gd`, `data/buildings/raider_dock.tres`, `data/contracts/planet_raid_rules.tres`, `data/loadouts/lander_default.tres`
- `data/research/{pln_assault_doctrine,pln_heavy_dropships,eng_armoured_dropships}.tres` (renamed in text, ids kept), `data/modules/*.tres` ("Lander" role dropped), `scenes/system.tscn` (dock def dropped)
- `tools/smoke.sh`, `tools/smoke_test.gd` (`--surface`), `docs/DESIGN.md`, `CLAUDE.md`

## Built

- S0 surface world: OutpostState in Sector.outposts, saved; Outposts founding (lander 60 s); SurfaceTerrain per planet type and its shader; SurfaceMode overlay with camera and UP / Backspace / H; SurfaceHud; planet panel OUTPOST section; double-click a planet; "[outpost]" planet label and overview row.
- S1 harvesting: build placement within 700 m, Harvester Bay, hires, harvest contracts per deposit, harvesters drive, harvest, deliver and get paid; shuttle lifts (1 to 3) deliver into the corp's stock; UplinkShuttle visual.
- S2 data sim: Outposts._data_step runs trips on timers; the live world edits the same OutpostState, so there is no write-back.
- S3 critters and defence: nests, agitation, swarms live and as data rolls, Garrison and soldiers, nest bounties, Ground Turret, Shield Dome, building disable and paid repairs.
- S4 ground raids: pirates or a rival at war, 30 s warning, live tanks or data rolls; losing the pad loses the outpost; a faction claim or re-claim on an outpost world sends a ground raid instead (Outposts.claim_blocked).
- Gas giant platforms: fuel from gas pockets, cloud deck terrain and shader, decks 60 m up, drones, floaters and storm cells (surface_terrain.gd is_gas, SurfaceWorld.deck_at, SurfaceModels platform/floater/storm_cell/deposit_fuel).
- S5: planet raid code deleted; techs renamed with effects wired (OutpostState.shuttle_load, max_hull); old-save migration (dock refunded, landers bought out, raid contracts dropped); loads tuned to about 200 cr/min net for 2 harvesters; `--surface` smoke; DESIGN.md and CLAUDE.md.
- Review round (workflow, 5 areas, 3 skeptics per finding): 29 of 30 findings confirmed and fixed except fuel. Fixed: building nodes piling up, hidden-HUD keys, view switch under the surface, disabled dome still shielding, saves erasing a live raid (hostiles saved as "ground", resolved after load), offers expiring unseen (they wait, the surface HUD shows a button), trackpad zoom, fleeing harvesters dropping loads, a dead pad repaired before the loss check, repair cost piling up unpaid, data soldiers never healing, claims during the lander flight, lifts lost with the outpost, deposits under buildings, outposts outliving their station, berths counting unfinished bays, dock depot loot and orphaned lander captains in old saves, the outposts RNG not saved, ledger entries without their system.
- Second review round (fix check per finding plus a regression hunt): 21 of 27 fixes clean; fixed the rest and 14 new findings: offers now frozen (not floored), Escape handled on the surface, Shift+'+' passes, panels closed on entering, hire reasons shown as text, saved hostiles kept through a second save and spawned live when entering, harvester trips synced on leaving, dome shield back after a data repair, soldier repair needs a working garrison, claim raids give 150 s after landing, data hits capped at 60% of hull, dock refund pads the ore array.
- Follow-ups (2026-11-04):
  - Founding lander: a dropship flies from a station docking pad down to the planet over the 60 s founding (`UplinkShuttle.setup_lander`, `Outposts._show_lander`; shown again part way after a load or a view switch). Lifts settle on a docking pad, alternating pads (`UplinkShuttle.setup`, `Outposts._lift_count`).
  - Ground raids: every raid gets a drop bearing (`o.raid["a"]`, set in `_raid_clock` and `claim_blocked`; old raids get one on the surface). The live surface shows one dropship per three tanks 14 s before landing; they set down at the drop point exactly when the tanks spawn there (`SurfaceWorld._drop_step`, `drop_point`, `spawn_raid(size, source, a)`), wait 5 s and leave.
  - Fade from black on entering and leaving the surface (`SurfaceMode.fade_in`, 0.45 s, input passes through, runs paused).
  - The surface camera levels out from 52 to 20 degrees as it zooms in (`SurfaceMode.PITCH_LOW`, `LEVEL_FROM`) and stays 15 m over the ground. Close in, the sky shows the star as a glowing disc on the sun's bearing (tinted by the system's star) and, on a moon, its parent planet low over the horizon with the planet's own shader (`SurfaceWorld._build_sky`).
  - Surface models: `blender/gen_surface.py` exports 11 models in the station's worn-industrial style (worn_kit bake, 1024 or 2048 per model; critter and nest vertex colour, organic). Tris: pad 3.1k, bay 2.8k, garrison 3.1k, turret 0.9k, dome 2.5k, platform 2.1k, harvester 1.0k, hover tank 1.0k, raider tank 1.1k, critter 1.6k, nest 4.4k. All inside the stand-in footprints. Checked in game next to the 44 m dropships. The gas giant deck under a building is counter-scaled while it is built (`SurfaceWorld._update_building_look`, "PlatformDeck"); seen live on Tavros with a bay at 8%, and a raid's dropship and tanks set down over the clouds at deck height.
  - Old saves: all 16 real pre-outpost saves (generator v2 to v4) load and run 2 sim min. Saves 10 to 12 failed: their forward / rival stations sat on planets the v5 generator no longer makes ("Planet 101"), so BuildingManager spawned onto a null frame. `SolarSystem.add_station` now moves such a station to the innermost non-gas-giant planet and writes the new name into the site (`_fallback_host`); all 16 load with 0 script errors. The Raider Dock refund, injected into a real save: 900 + 550 per lander cr, ore plus depot, crew retired, feed line posted. (Temporary tool, deleted.) Default smoke and `--forward --save-roundtrip` 0 errors after the change.
  - Checked live in a window (temporary tool, deleted): lander at the pad and on its way, the lift 13 m over pad 0 at 95%, fade frames black then clear, Noctis over Iru, 2 dropships landing 4 tanks at the drop point; `--surface` smoke 0 errors.
- Checked: smoke default, --surface (12 and 20 min), --forward --save-roundtrip, --rival --war, --rival --save-roundtrip, --multi, --multi --long, --explore: all 0 errors. Screenshots of lava, rocky and ice surfaces looked right.

- Raider range fix: raiders weigh buildings at 0.6 of their distance to prefer them, but that scaled number also fed the range check, so they hit buildings from about 550 m plus the radius, outside the turret's 520 m (seen: a raider 770 m out shooting the Harvester Bay). The range check now uses the real gap. `scripts/surface/surface_world.gd` `_hostile_step`
- Live raid check (temp harness, removed), 2 soldiers and a turret: 2 tanks die in 60 to 80 s with no building damage and no crew lost; 4 tanks disable the turret and the bay and scratch the pad, but no crew are lost and the raiders die by 150 s. The raid size table stays.
- Vehicle readability at the default zoom (520 m) checked in screenshots: yellow harvesters, red soldiers and dark raiders with orange beams read apart; soldiers repairing next to the garrison are hard to spot.

## Gotchas

- JSON turns ints into floats. OutpostState.from_dict re-ints crew, deposit and lift fields (_ints); real saves use var_to_bytes, but keep the dict round trip clean.
- A node that steps itself must also join SimStepper.GROUP, or headless smoke runs never step it (SurfaceWorld first harvested nothing).
- Leaving the surface frees its hostiles; SurfaceMode.leave resolves them as a data attack so leaving is not an escape.
- look_at errors when the direction is parallel to up: tracers and the uplink shuttle guard it.
- Godot hashes a Dictionary used as a key by its contents: building dicts change every step, so SurfaceWorld keeps [dict, node] pairs and looks up with is_same.
- Surface models are not dimmed like station buildings (`ModelLoader.BUILDING_LIGHT_DIM`): gen_surface.py scales the worn_kit emissives by `EMIT_K = 0.4` and keeps its own glows at 2 to 4.
- Building nodes scale on Y by build progress: anything parented under a building (the gas giant deck) gets squashed unless it undoes the scale.
- Old saves regenerate their systems with the current SystemGenerator.VERSION (v5 since db35437, which also changed ore weights and star colours): planet names can differ, so anything saved by planet name (station sites, outposts "system|planet") can point at a planet that no longer exists. Stations fall back (`SolarSystem._fallback_host`); outposts did not exist before v5.
- A headless check that never quits (a parse error in a tool scene) hangs until the timeout: run new tool scenes once briefly first.
- `SolarSystem.home_station` is an Orbiter; the HomeStation (docking pads) is its "Station" child. A typed `as HomeStation` cast on it fails to parse.
- The surface camera only sees sky when it levels out close in (pitch 20 at 90 m). The star disc and the parent planet sit 11 degrees up for that reason; the sun light stays at 38 degrees for readable shadows, so the disc is lower than the light.
- Godot runs _unhandled_key_input on every node before any _unhandled_input, and a hidden CanvasLayer still gets input: SurfaceMode takes keys in _input, or the hidden HUD's shortcuts fire first.
- Outposts must join its group in _enter_tree: the HUD's _ready asks for it before Outposts._ready runs.
- Ship.Role.LANDER, Captain.Specialty.LANDING and Contract.Type.PLANET_RAID stay in their enums: saves store the indices.

## Remaining

- **Play test in the editor (user):** placing, hiring, contracts, and the feel of the camera (it now levels out close in). Vehicle readability and raid sizes were checked by Claude (see Built); worth a second look while playing.
- Smoke `--surface` net income varies 77 to 287 cr/min between runs (unseeded surface rolls) and mostly sits under the 150 to 250 target. 9 minutes with the founding and a raid is a short window; judge it in the play test before tuning.

## Open questions

- None.

## Decisions

- **Planet raids are replaced completely by surface outposts.** User decision.
- **A surface patch of a few km, one landing zone, one outpost per planet or moon.** User decision; a whole planet is out of scope.
- **Vehicles only: no people to animate.** User decision.
- **Unlimited outposts, only in systems where the player has a station.** User decision.
- **Live only while viewed, data otherwise.** Many outposts must not slow the game the way pinned station worlds do.
- **Gas giants get floating platforms that harvest fuel.** User decision after the review found fuel had no source left (it overrides "no gas giants in v1"). Claimed worlds still need the garrison broken first.
- **Goods by type: water (ice, ocean), silicates (desert), heavy ore (rocky), rare metals (lava); buildings: landing pad, harvester bay, garrison, ground turret, shield dome; harvest contracts like mining.** Proposed by Claude at the user's request, agreed.
- **Threats: agitated critter nests, pirate ground drops, rival strikes at war; data rolls while not viewed; losing the pad loses the outpost.** Agreed.
- **Costs: founding 1,500 cr + 200 iron (halved to 100 later with every building's iron) + 50 titanium, upkeep 20 cr/min, buildings and hires as listed in Remaining; shuttle 60 per trip, up to 3.** Agreed.
- **Economy target 150 to 250 cr/min net for 2 harvesters, payback 10 to 15 min.** Agreed after the user asked how outposts make money.
- **Planet mode UI: Go to surface, UP, surface build bar, tagged feed, outpost icon in orbit.** Agreed.
- **Raider Dock, landers and raid contracts removed; research renamed; old saves refunded; C4 dropped; no rival outposts in v1.** Agreed.
- **Terrain generated in Godot per planet seed; buildings, vehicles and critters modelled in Blender.** Agreed; an exception to "Blender owns meshes", like asteroid clusters.
- **Build order S0 to S5 as in Remaining.** Agreed.

- **Surface mode is a CanvasLayer overlay, not a third ViewManager level.** The system keeps running underneath and no SystemHost code changed. (Built.)
- **Outposts are plain data in Sector; the live world edits that data directly.** Nothing to write back on leaving.
- **Harvest contracts live in OutpostState, not the ContractBoard.** Keeps the board and its UI free of surface rules.
- **Danger and planet lookup moved to PlanetInfo** so nothing depends on the deleted raid classes.
- **Rivals found no outposts in v1; deposit respawn timing stays; hovering over the heightfield is enough (no obstacles or ground pathfinding).** Claude's call, the user delegated these (2026-11-04).
- **Ground raid sizes by danger: tanks 2 (danger 1 to 2), 2 to 3 (3), 3 to 4 (4), 4 to 5 (5); 2 at most in the first 25 min after landing (`Outposts.FIRST_RAIDS_GRACE`); critter swarms capped at 2 + danger.** Claude's call, delegated; claim raids keep their own size (2 to 6). `scripts/surface/outposts.gd` `_raid_clock`, `_data_step`; `scripts/surface/surface_world.gd` `_nests_step`
- **The dropship model is reused for the founding lander and raid drops; the Raider Dock model is deleted.** Recommended by Claude, user said to build it.
- **Raid dropships are visual only and land exactly at the raid time.** Raid timing and data rolls are unchanged.
- **Fade in from black, not a fade out first.** SurfaceMode.enter and leave stay synchronous (smoke and callers rely on it).

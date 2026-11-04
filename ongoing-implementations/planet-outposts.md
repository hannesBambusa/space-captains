# Planet outposts

| | |
|---|---|
| **Status** | built, needs a play test |
| **Branch** | main (uncommitted) |
| **Updated** | 2026-11-03 |
| **Scope** | Surface outposts on planets and moons (4 km landing zone, own world while viewed), replacing planet raids. S0 to S5 built; follow-ups in Remaining. |

## Files

**Owned:**

- `scripts/surface/outpost_state.gd`: OutpostState, the data of one outpost and every tuning constant
- `scripts/surface/outposts.gd`: Outposts (ViewManager child): founding, shared rules, data sim, raids, claim_blocked
- `scripts/surface/surface_terrain.gd`, `shaders/terrain_surface.gdshader`: heightfield and ground shader
- `scripts/surface/surface_world.gd`: live world (units, combat, picking)
- `scripts/surface/surface_mode.gd`: planet mode overlay, camera, input
- `scripts/surface/surface_models.gd`: .glb or primitive stand-ins
- `scripts/surface/uplink_shuttle.gd`: the visual lift in the station's system
- `scripts/ui/surface_hud.gd`: planet mode HUD
- `scripts/planet_info.gd`: find_planet, danger_for (moved off the raid contract)

**Shared:**

- `scripts/cluster/sector.gd` (outposts dict, save), `scripts/view_manager.gd` (Outposts child)
- `scripts/ui/planet_panel.gd` (OUTPOST section, raid form gone), `scripts/ui/overview_panel.gd`, `scripts/selection_controller.gd` (double-click)
- `scripts/enemies/planet_claims.gd`, `scripts/enemies/threat_director.gd` (claim_blocked)
- `scripts/building_manager.gd` (_retire_dock), `scripts/save/{contract_codec,ship_codec,game_snapshot,save_manager}.gd`
- Raid removal edits: `scripts/ai/{captain_brain,decision_notes}.gd`, `scripts/contracts/{contract,contract_board,contract_markers}.gd`, `scripts/enemies/{scavenger_brain,claim_garrison}.gd`, `scripts/ships/ship_loadout.gd`, `scripts/combat/scrap_field.gd`, `scripts/defense/defense_zones.gd`, `scripts/economy.gd`, `scripts/ui/{top_bar,contract_strip,contract_row,pilot_card,factory_panel,captain_panel,post_contract_form,research_tip,pilot_roster,tutorial_card,hud}.gd`
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
- Checked: smoke default, --surface (12 and 20 min), --forward --save-roundtrip, --rival --war, --rival --save-roundtrip, --multi, --multi --long, --explore: all 0 errors. Screenshots of lava, rocky and ice surfaces looked right.

## Gotchas

- JSON turns ints into floats. OutpostState.from_dict re-ints crew, deposit and lift fields (_ints); real saves use var_to_bytes, but keep the dict round trip clean.
- A node that steps itself must also join SimStepper.GROUP, or headless smoke runs never step it (SurfaceWorld first harvested nothing).
- Leaving the surface frees its hostiles; SurfaceMode.leave resolves them as a data attack so leaving is not an escape.
- look_at errors when the direction is parallel to up: tracers and the uplink shuttle guard it.
- Godot hashes a Dictionary used as a key by its contents: building dicts change every step, so SurfaceWorld keeps [dict, node] pairs and looks up with is_same.
- Godot runs _unhandled_key_input on every node before any _unhandled_input, and a hidden CanvasLayer still gets input: SurfaceMode takes keys in _input, or the hidden HUD's shortcuts fire first.
- Outposts must join its group in _enter_tree: the HUD's _ready asks for it before Outposts._ready runs.
- Ship.Role.LANDER, Captain.Specialty.LANDING and Contract.Type.PLANET_RAID stay in their enums: saves store the indices.

## Remaining


- Play test in the editor: placing, hiring, contracts, a raid on screen, the feel of the camera.
- Blender models for the surface (assets/models/surface/<id>.glb, blender/gen_surface.py); stand-ins now.
- Raids appear at the zone edge with no dropship; the founding lander is a timer with no visual.
- Uplink shuttles fly to the station centre, not a docking pad.
- No fade on entering or leaving; the sky has no star disc or parent planet.
- Old-save migration not tried on a real pre-outpost save.
- Raid sizes are harsh early: a forced 5-tank raid at danger 3 killed a harvester against 2 soldiers and a turret.
- assets/models/buildings/raider_dock.glb and assets/models/ships/dropship.glb are unused now: delete, or reuse the dropship for the founding lander and raid drops.

## Open questions

- Should rivals found outposts too, and when? (v1: no)
- Exact critter and pirate drop sizes per danger level?
- How fast new deposits turn up after one runs out?
- Is hovering over the heightfield enough, or do outposts need obstacles and ground pathfinding?

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

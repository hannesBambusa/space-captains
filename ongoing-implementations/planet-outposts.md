# Planet outposts

| | |
|---|---|
| **Status** | planned |
| **Branch** | — |
| **Updated** | 2026-11-03 |
| **Scope** | Surface outposts on planets and moons (a few km landing zone, own world while viewed), replacing planet raids. Not started. |

Planned on 2026-11-03 from an interview with the user. No code exists yet; the paths under `## Files` are intended paths.

## Files

None of these exist yet. Coarse intent only.

**Owned** (intended):

- `scripts/surface/**`: the surface world (terrain generation, camera limits, deposits, nests), the outpost data sim, surface buildings' services, harvester and soldier vehicles and their brains, critters, ground raids
- `scenes/surface.tscn`: one surface world (like `scenes/system.tscn`)
- `shaders/terrain_*.gdshader`: terrain per planet type
- `assets/models/surface/**`, `blender/gen_surface_*.py`: pad, harvester bay, garrison, turret, dome, harvester rover, hover tank, critters, raider tanks, deposit props
- `data/buildings/{landing_pad,harvester_bay,garrison,ground_turret,shield_dome}.tres`

**Shared** (other features write here too):

- `scripts/view_manager.gd`, `scripts/cluster/system_host.gd`, `scripts/system_world.gd`: a third view level (system and surface)
- `scripts/ui/planet_panel.gd`, `scripts/ui/hud.gd`, `scripts/ui/top_bar.gd`, `scripts/ui/build_menu.gd`, `scripts/placement_controller.gd`: Found outpost, Go to surface, UP, surface build bar
- `scripts/contracts/contract_board.gd`, `scripts/save/*`: harvest contracts, outpost saves, old-save migration
- `scripts/ships/cargo_shuttle.gd`, `scripts/lander_ship.gd`: the uplink shuttle and the founding lander (dropship model)
- `data/research/*.tres`: renames (Surface operations, Heavy shuttles, Armoured rovers)
- Planet raid code to remove: Raider Dock, `LanderBrain`, `LanderEvaluator`, `PlanetRaidContract`, `PlanetRaidRules`, `data/buildings/raider_dock.tres`
- `scripts/rival/*` (rival ground strikes at war), `scripts/enemies/*` (pirate ground drops)
- `tools/smoke.sh`, `tools/smoke_test.gd` (`--surface`), `docs/DESIGN.md`, `CLAUDE.md`

## Built

Nothing built yet. This doc is a plan.

## Gotchas

None yet. Nothing has been built to trip over.

## Remaining

Milestones in order; each leaves the game playable.

- **S0: surface world.** A surface world per planet or moon (not gas giants), its own scene and viewport like a system (`scenes/surface.tscn`), built on going down and freed after leaving. Terrain generated in Godot from the planet's seed: a heightfield a few km square, ridges, craters or dunes by type, a terrain shader per type (ice, desert, dark rock, lava with glowing cracks), sky with the star and the parent planet. The RTS camera limited to the zone. Planet panel: "Found outpost" (1,500 cr + 200 iron + 50 titanium; only in a system with your station; not on a faction-claimed world while its garrison stands) sends a lander (dropship model) down from the station, about 1 min, which sets the landing pad. "Go to surface" (or double-click a planet with an outpost) switches the view with a fade; top bar "Verda surface", UP (Backspace) back to orbit, H home. Outpost icon on the planet and its overview row. Save and load. Done when: a smoke test founds an outpost, views the surface and back, and a save round trip keeps it.
- **S1: harvesting.** Surface buildings through the build bar (placement on the terrain): harvester bay (500 cr + 80 iron), and the pad's shuttle. Deposits by type: ice and ocean water, desert silicates, rocky heavy ore, lava rare metals; 3 to 5 per zone, finite, new ones turning up. Harvester rovers (hire 200 cr) hover over the terrain reusing ship movement (a fixed height over the heightfield), take harvest contracts (posted on a deposit, paid per load like mining), load, return to the pad. The shuttle lifts 60 units per trip: ascent, cruise to the station in that system, lands on a docking pad; up to 3 as stock waits. Done when: goods from a surface reach the station's stock.
- **S2: not viewed.** Leaving the surface writes it to data; a data sim runs harvest trips and shuttle lifts on timers and delivers the same goods; returning rebuilds the world from it. Done when: an outpost left unviewed for 10 sim min delivers about what it does while viewed.
- **S3: critters and defence.** 1 to 3 critter nests per zone (more on dangerous worlds), critters as fast low-poly crawlers that hunt harvesters and attack buildings; nest agitation rises with harvesting nearby. Garrison (600 cr + 100 iron + 30 titanium) hires soldiers (hover tanks, 300 cr) that guard, answer the alarm and take bounties on nests (a cleared nest comes back after a while). Ground turret (250 cr + 60 iron), shield dome (600 cr + 120 iron + 60 titanium). Not viewed: attacks rolled from soldiers, turrets and dome against the attackers (harvesters lost, a building disabled, cargo stolen; a feed line each). Buildings get disabled like the station's.
- **S4: ground raids.** Pirate factions drop a dropship with 2 to 5 tanks every 10 to 20 min by the system's danger; a rival corp at war sends a ground strike; 30 s warning. Live and as data. Losing the landing pad loses the outpost (wrecks remain). A faction re-claim over a planet with your outpost sends ground raids instead of a new garrison.
- **S5: replace planet raids, tune, document.** Remove the Raider Dock, landers and planet raid contracts. Research: Planetary assault doctrine becomes Surface operations (unlocks founding), Heavy dropships becomes Heavy shuttles (+40% lift), Armoured dropship hulls becomes Armoured rovers (harvesters and soldiers hull x1.4, +60 shields). Old saves: a Raider Dock is removed with its build cost refunded, landers paid off, raid contracts refunded, techs kept under the new names. Upkeep 20 cr/min per outpost (owed blocks hiring there). Tune to the target: 2 harvesters at fair pay net 150 to 250 cr/min after upkeep at normal prices, payback 10 to 15 min. `--surface` smoke test, `docs/DESIGN.md` (drop C4), `CLAUDE.md`.

## Open questions

- Should rivals found outposts too, and when? (v1: no)
- Gas giant floating platforms for fuel: later, or never?
- Exact critter and pirate drop sizes per danger level?
- How fast new deposits turn up after one runs out?
- Is hovering over the heightfield enough, or do outposts need obstacles and ground pathfinding?

## Decisions

- **Planet raids are replaced completely by surface outposts.** User decision.
- **A surface patch of a few km, one landing zone, one outpost per planet or moon.** User decision; a whole planet is out of scope.
- **Vehicles only: no people to animate.** User decision.
- **Unlimited outposts, only in systems where the player has a station.** User decision.
- **Live only while viewed, data otherwise.** Many outposts must not slow the game the way pinned station worlds do.
- **No outposts on gas giants in v1; claimed worlds need the garrison broken first.** Agreed in the interview.
- **Goods by type: water (ice, ocean), silicates (desert), heavy ore (rocky), rare metals (lava); buildings: landing pad, harvester bay, garrison, ground turret, shield dome; harvest contracts like mining.** Proposed by Claude at the user's request, agreed.
- **Threats: agitated critter nests, pirate ground drops, rival strikes at war; data rolls while not viewed; losing the pad loses the outpost.** Agreed.
- **Costs: founding 1,500 cr + 200 iron + 50 titanium, upkeep 20 cr/min, buildings and hires as listed in Remaining; shuttle 60 per trip, up to 3.** Agreed.
- **Economy target 150 to 250 cr/min net for 2 harvesters, payback 10 to 15 min.** Agreed after the user asked how outposts make money.
- **Planet mode UI: Go to surface, UP, surface build bar, tagged feed, outpost icon in orbit.** Agreed.
- **Raider Dock, landers and raid contracts removed; research renamed; old saves refunded; C4 dropped; no rival outposts in v1.** Agreed.
- **Terrain generated in Godot per planet seed; buildings, vehicles and critters modelled in Blender.** Agreed; an exception to "Blender owns meshes", like asteroid clusters.
- **Build order S0 to S5 as in Remaining.** Agreed.

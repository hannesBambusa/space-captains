# Space Captains

Indirect-control space sim in the spirit of Majesty 2. You are a station administrator in a star sector. Ship captains (miners, escorts, scouts, bounty hunters) act on their own; you steer them with paid contracts (mining, explore, protect, bounty). Rich asteroid belts are more dangerous. Resources: credits (pay contractors) and typed ore (iron, titanium, crystal: for building, tooling, and to sell to the Factory, which makes the modules captains buy).

Design: docs/DESIGN.md (agreed design and stages, read it first). Reference: ../majesty/docs/MAJESTY2_MECHANICS_RESEARCH.md (fantasy original, mechanics only).

## Engine and tools
- Godot 4.7, Forward+ renderer, GDScript. Binary: /Applications/Godot.app/Contents/MacOS/Godot
- Blender 5.2. Binary: /Applications/Blender.app/Contents/MacOS/Blender
- Blender owns meshes/materials, exported as .glb to assets/models/. Godot owns scenes, lighting, gameplay. Never edit imported mesh data in Godot.
- Blender source scripts live in blender/ (headless bpy scripts, re-runnable).

## World conventions
- 1 unit = 1 m. Y is up. "Thick disc": the system has a main orbital plane (y = 0), but planets and moons orbit on inclined planes (PlanetDef inclination), asteroids come in clusters (AsteroidCluster: a 1 to 3 km clump on a slow inclined orbit, finite ore, fades when mined out; ClusterSpawner keeps 4 to 6 alive), dens sit at fixed spots at a height, and the home station rides its planet's height. Ships fly in 3D within this disc: they fly a lane over or under a cluster only when their route crosses it (AsteroidCluster.lane_altitude), miners drop to their rock's real height, and planet avoidance uses spheres. Travel legs fly cruise arcs (CruiseLeg, highway rule) and combat is 3D (AttackRun: tilted orbits, dive/climb passes, pitch aiming, fleeing dives). Structures stay level in the station's frame.
- Scale: cluster (8-12 star systems linked by jump lanes) -> solar system (one scene each, ~50 km radius, compressed scale, star at origin) -> local area (zoomed in on a colony/belt/station). Godot float precision is fine inside one system; never put two systems in one scene.
- Planets move slowly on orbits (pausable sim time). Home station orbits a planet.
- Structures stand free near the station (no corridors); cargo shuttles fly goods from the outposts to the station's docking pads.
- Station hub radius ~40 m. Asteroids 2 to 25 m. Ships (later) 5 to 20 m.
- Camera is a tilted top-down RTS camera, zooms from ~80 m (station) to the whole system.
- Main scene is scenes/main_menu.tscn (New game / Continue / Load); the game scene is scenes/game.tscn. Saves: SaveManager autoload, scripts/save/, user://saves/.
- One system per World3D: scenes/game.tscn (root ViewManager) holds each live system as scenes/system.tscn (root SystemWorld: SolarSystem, RTSCamera, Buildings, Combat, ContractMarkers) inside its own SubViewport (own_world_3d) under the SystemView container, and the HUD, ScreenshotMode, Selection, Placement and ZonePlacement at the top, outside every system. Only home is live for now.
- System-side lookups are node-scoped: X.of(node) (SolarSystem, BuildingManager, CombatWorld, RTSCamera, DefenseZones, PlanetClaims, ColonyAlarm) go through SystemWorld.of(node) (the node's viewport meta; nodes outside every system get the viewed one). Group scans: SystemWorld.nodes_in(node, group). Static helpers take a node in the system (ctx: Node), never the SceneTree. Global code (autoloads, saves) asks SystemWorld.home(tree). Screen-space UI uses SystemWorld.camera_3d(self), not get_viewport().get_camera_3d().
- SystemView renders the SubViewport at window pixel size with a 1920x1080 2D size and forwards the input nobody at the top took (camera drag/zoom); keep new 3D-world input on RTSCamera-style _unhandled_input inside the system, or at the top level next to Selection.

## Layout
- scenes/      .tscn (game: scenes/game.tscn, one system: scenes/system.tscn)
- data/systems/ SystemDef .tres, one per star system
- scripts/     GDScript
- shaders/     .gdshader
- assets/models/{asteroids,station,gate,buildings,ships}   .glb from Blender (station addons: assets/models/station/addons, attached to the station's addon_bay_1..6 empties)
- blender/     bpy scripts that generate the .glb files

## Run
- Editor: Godot --path . -e
- Play:   Godot --path .
- Screenshot check: Godot --path . -- --screenshot=/abs/path/out.png  (renders ~90 frames, saves, quits)
- Smoke test: tools/smoke.sh [--minutes N]  (headless new game with outposts, crews and a mining contract, seeded, ~10 sim min in a few seconds; prints credits, ships by role, raids, ore delivered, contracts, error count; exit 1 on script errors; writes no saves)

## Rules
- Never git commit or push.

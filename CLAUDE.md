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
- Main scene is scenes/main_menu.tscn (New game / Continue / Load); the game scene is scenes/system.tscn. Saves: SaveManager autoload, scripts/save/, user://saves/.

## Layout
- scenes/      .tscn (main: scenes/system.tscn)
- data/systems/ SystemDef .tres, one per star system
- scripts/     GDScript
- shaders/     .gdshader
- assets/models/{asteroids,station,gate,buildings,ships}   .glb from Blender (station addons: assets/models/station/addons, attached to the station's addon_bay_1..6 empties)
- blender/     bpy scripts that generate the .glb files

## Run
- Editor: Godot --path . -e
- Play:   Godot --path .
- Screenshot check: Godot --path . -- --screenshot=/abs/path/out.png  (renders ~90 frames, saves, quits)

## Rules
- Never git commit or push.

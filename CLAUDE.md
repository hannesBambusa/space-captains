# Space Majesty (working title)

Indirect-control space sim in the spirit of Majesty 2. You are a station administrator in a star sector. Ship captains (miners, escorts, scouts, bounty hunters) act on their own; you steer them with paid contracts (mining, explore, protect, bounty). Rich asteroid belts are more dangerous. Resources: credits (pay contractors) and typed ore (iron, titanium, crystal: for building, tooling, and to sell to the Factory, which makes the modules captains buy).

Design: docs/DESIGN.md (agreed design and stages, read it first). Reference: ../majesty/docs/MAJESTY2_MECHANICS_RESEARCH.md (fantasy original, mechanics only).

## Engine and tools
- Godot 4.7, Forward+ renderer, GDScript. Binary: /Applications/Godot.app/Contents/MacOS/Godot
- Blender 5.2. Binary: /Applications/Blender.app/Contents/MacOS/Blender
- Blender owns meshes/materials, exported as .glb to assets/models/. Godot owns scenes, lighting, gameplay. Never edit imported mesh data in Godot.
- Blender source scripts live in blender/ (headless bpy scripts, re-runnable).

## World conventions
- 1 unit = 1 m. Y is up. The play area is the flat plane y = 0; ships move on it (no free 3D flight), except that they leave the plane to clear asteroid belts: they climb over or dive under a belt band in a lane (SystemBelt.lane_altitude) and miners drop to their rock's real height beside it.
- Scale: cluster (8-12 star systems linked by jump lanes) -> solar system (one scene each, ~50 km across, compressed scale, star at origin) -> local area (zoomed in on a colony/belt/station). Godot float precision is fine inside one system; never put two systems in one scene.
- Planets move slowly on orbits (pausable sim time). Home station orbits a planet.
- Station hub radius ~40 m. Asteroids 2 to 25 m. Ships (later) 5 to 20 m.
- Camera is a tilted top-down RTS camera, zooms from ~80 m (station) to the whole system.
- scenes/sector.tscn is the first prototype (one local area), kept as reference. Main scene is scenes/system.tscn.

## Layout
- scenes/      .tscn (main: scenes/system.tscn)
- data/systems/ SystemDef .tres, one per star system
- scripts/     GDScript
- shaders/     .gdshader
- assets/models/{asteroids,station,gate,buildings,ships}   .glb from Blender
- blender/     bpy scripts that generate the .glb files

## Run
- Editor: Godot --path . -e
- Play:   Godot --path .
- Screenshot check: Godot --path . -- --screenshot=/abs/path/out.png  (renders ~90 frames, saves, quits)

## Rules
- Never git commit or push.

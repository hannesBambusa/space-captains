# Merc outpost redesign

| | |
|---|---|
| **Status** | in progress (new model built and exported; 3 look fixes left) |
| **Branch** | main (uncommitted) |
| **Updated** | 2026-11-04 |
| **Scope** | Rebuild the Mercenary Outpost model so it reads as an Expanse-style space structure, not an Earth airport hangar. Blender generator only, no game code. |

User ask: "looks to much like an airport on earth.. this is an oupost in space..make it look cooler and more inline woth the expanse series". Then: "fix what is not done".

**Work rule from the user: one thing at a time.** One agent, one Blender or Godot process at a time. No parallel agents and no fan-out workflows. They overload the machine.

## Files

**Owned:**

- `blender/gen_mercenary_outpost.py`: rewritten from scratch (775 lines)
- `blender/mercenary_outpost.blend`
- `assets/models/buildings/mercenary_outpost.glb`
- `assets/models/buildings/mercenary_outpost_mercenary_outpost_{albedo,mr,normal}.jpg` (+ `.import`)
- `blender/textures/mercenary_outpost_{albedo,mr,normal}.jpg`, `blender/textures/mercenary_outpost_decals.png`
- `blender/previews/mercenary_outpost_{preview,preview_ships,top,top_ships}.png`

**Not this feature** (dirty from other work): `data/buildings/mercenary_outpost.tres` (cost_iron 120 -> 60, the user's change), `assets/models/ships/merc_interceptor.glb` and `blender/gen_merc_interceptor.py`, `tools/smoke*`, `tools/model_viewer.*` (the /3D skill's viewer). Unclear: `assets/models/buildings/defense_turret_defense_turret_*.jpg.import`. Their md5 metadata changed, possibly from a reviewer's Godot reimport during this work. Check before staging.

## Built

**New design: "Drumhead rack", MX-12 merc carrier hub.** Free-floating. No floor, deck, walls, control tower, apron or runway lights. Layout and coordinates are in the module docstring of `blender/gen_mercenary_outpost.py`.
- **Rack:** four interceptors hang nose-out between lattice finger piers. Dorsal clamp yokes hold them from above and ventral saddles from below. The inner fingers carry walkway tubes and umbilicals.
- **Lights:** guide arms with red/green lamp heads frame each lane in free space.
- **Girder:** cross-girder with bolted BAY 1..4 armour, an ops gondola, propellant tanks and sodium floods.
- **Magazines:** two torpedo magazines with tube bores, VLS lids (one open) and a "12" on top. Six PDC turrets.
- **Back:** a non-rotating axle through a 22 m standing spin drum, two radiator fans, a comms mast and the link port at the tail.
- **Size:** 63.2 x 53.6 x 24.8 m, 22.8k tris (hull 21.2k, one atlas material; lights 1.6k).

**Built-in check.** `-- --check` re-measures `merc_interceptor.glb`, tests the four docking corridors, the sideways path, the outer berth spots and r <= 40, and prints `BERTH CHECK ... ALL OK`. Last full textured run: ALL OK, max XY radius 39.39. `blender/gen_mercenary_outpost.py` (`check_build`, `measure_fighter`)

**Verified in game tooling.** Two independent geometry checks passed (glb import, triangle tests). The model loads in `tools/model_viewer.tscn` with `--dim=0.35`. `tools/smoke.sh` ran with 0 errors (0 script) and 0 warnings.

**Previews.** Use `--no-ships` for previews without the docked ships. With ships, each berth gets a `merc_interceptor.glb` (was `merc_fighter_old.glb`).

## Gotchas

- **The berth geometry is fixed by game code, not by the model.** `Building.berth_transform` / `dock_path` (`scripts/building.gd:420`) put ships at Blender (x, -3.5, 0) for x = -15, -5, 5, 15 and fly them straight along Y at z = 0 from spawn (0, -34, 0). Anything in the corridor x = bx +-4.3, z +-3.2, y -40..+3.5 gets flown through. Clamps are the one allowed exception (bottom z >= 2.40, top z <= -1.58). Run `--check` after every geometry change.
- **Footprint margin is 0.6 m.** The radiator blade corners sit at r 39.39 and the limit is 40 (`footprint_radius`). Wider radiators must be pulled in or reshaped.
- **`link_point` moved to (0, 33.6, 0) at the axle tail.** It was (0, 18.6, 0.5). Game code reads it only on models without a `dock_point` (`scripts/building_manager.gd:451`), so nothing changes in game.
- **Running `Godot --import` rewrites `.import` metadata of unrelated assets.** Skip the smoke test rather than reimport, or check `git status` for stray `.import` changes afterwards.
- **Emission is dimmed in game.** Judge lights with the viewer's `--dim=0.35`, not with the Blender previews.

## Remaining

Do these one at a time, in this order. After each: fast build with `-- --no-textures --check`, look at the previews, then the full textured build with `--check`.

- **Radiators read as thin antennae/whiskers.** Six narrow blades (`RAD_W` 1.9 m chord, twisted 40 deg) on two hubs show edge-on from the top and the 3/4 camera. Done = broad, thin, dark panels several metres wide on a visible truss, with faint coolant lines in the lights mesh, broad face visible from both cameras, r <= 40. `blender/gen_mercenary_outpost.py:523` (`RAD_*`, `build_radiators`)
- **Drum reads as a banded rectangle from straight above.** Done = the top view reads as a cylinder on an axle: end caps or a hub with spokes/bearing ring on the axle ends, end faces darker than the rim, a lit rim or porthole band that shows from above. `blender/gen_mercenary_outpost.py` (`build_drum`, `drum_mat`, `build_axle`)
- **Magazine sides are plain slabs that look like shipping containers.** Done = armoured ordnance blocks: bolted plate courses, chamfered upper edges, rails/conduits, vent or loading hatches. Keep the flat top "12" decal plane and the front tube bores. `blender/gen_mercenary_outpost.py` (`magazine`)
- **After all three:** load in the viewer at `--dim=0.35` with the four interceptors docked (Godot coords (bx, 0, 3.5), yaw 180) and check the log. `/3D merc outpost` opens it.

## Open questions

- None.

## Decisions

- **Drum concept over "docking spine" and "Belter asteroid hole".** The spine had too little mass from the RTS camera. The asteroid would read as an enemy base (scavenger den, corsair nest and syndicate fortress are already rock bases).
- **Berth fields and `dock_point` / `spawn_point` unchanged.** This keeps `data/buildings/mercenary_outpost.tres` and ship docking untouched.
- **No text that reads as an airport.** NO STEP, HOT, FLT CTRL, LAUNCH and AMMO are gone. Labels are BAY n, MX-12, MERC, SPIN, ORD, OPS and "12".
- **Old version backup (session scratch, may be gone):** `/private/tmp/claude-501/-Users-hannesalm-code-games-space-majesty/3db159a0-2d9c-431d-a05f-99d0e05d0054/scratchpad/merc_old/`. Git HEAD also has the old script and glb.

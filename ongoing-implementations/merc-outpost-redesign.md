# Merc outpost redesign

| | |
|---|---|
| **Status** | done (look fixes built, viewer checked, smoke re-run clean) |
| **Branch** | main (first model in db35437, look fixes in c4c3778; all committed) |
| **Updated** | 2026-11-05 |
| **Scope** | Rebuild the Mercenary Outpost model so it reads as an Expanse-style space structure, not an Earth airport hangar. Blender generator only, no game code. |

User ask: "looks to much like an airport on earth.. this is an oupost in space..make it look cooler and more inline woth the expanse series". Then: "fix what is not done".

**Work rule from the user: one thing at a time.** One agent, one Blender or Godot process at a time. No parallel agents and no fan-out workflows. They overload the machine.

## Files

**Owned:**

- `blender/gen_mercenary_outpost.py`: rewritten from scratch, then the look fixes (880 lines)
- `blender/mercenary_outpost.blend`
- `assets/models/buildings/mercenary_outpost.glb`
- `assets/models/buildings/mercenary_outpost_mercenary_outpost_{albedo,mr,normal}.jpg` (+ `.import`)
- `blender/textures/mercenary_outpost_{albedo,mr,normal}.jpg`, `blender/textures/mercenary_outpost_decals.png`
- `blender/previews/mercenary_outpost_{preview,preview_ships,top,top_ships}.png`

**Not this feature** (dirty from other work): `data/buildings/mercenary_outpost.tres` (cost_iron 120 -> 60, the user's change), `assets/models/ships/merc_interceptor.glb` and `blender/gen_merc_interceptor.py`, `tools/smoke*`, `tools/model_viewer.*` (the /3D skill's viewer), `assets/models/buildings/defense_turret_defense_turret_*.jpg.import` (dirty before the look-fix session; its reimport did not touch them).

## Built

**New design: "Drumhead rack", MX-12 merc carrier hub.** Free-floating. No floor, deck, walls, control tower, apron or runway lights. Layout and coordinates are in the module docstring of `blender/gen_mercenary_outpost.py`.
- **Rack:** four interceptors hang nose-out between lattice finger piers. Dorsal clamp yokes hold them from above and ventral saddles from below. The inner fingers carry walkway tubes and umbilicals.
- **Lights:** guide arms with red/green lamp heads frame each lane in free space.
- **Girder:** cross-girder with bolted BAY 1..4 armour, an ops gondola, propellant tanks and sodium floods.
- **Magazines:** armoured ordnance blocks. Front: tube bores and chamfered cheeks. Top: VLS lids (one open) and the flat "12" decal. Outboard side: staggered courses of thick bevelled plates with bolt rows, a conduit run with clamps, a louvred vent and a loading hatch. Bolted chamfer armour on both upper edges. Inboard face: a loading hatch with hazard trim and a feed conduit pair. Six PDC turrets. `magazine`
- **Drum:** 22 m spin drum on a non-rotating axle. Rim facets darken toward the sides (dark, hull2, hull3, hull), so it shades like a cylinder from straight above. 16 lengthwise stringers, spaced closer toward the edges. A lit porthole band (window_cool) on the red spin band. Dark end faces with spokes on both. Bearing hubs r 6.6 at both ends, wider than the axle (the rear one shows from the top, the front one sits mostly under the drum lip). `drum_mat`, `build_drum`
- **Radiators:** per side a box-truss boom off a gimbal on the axle, swept 15 deg forward, carrying three broad, flat, dark panel sections on both sides of the open truss (8 m chord, 17 m span). Grey edge frames, bare-metal coolant headers along the truss, faint amber coolant lines across the chord in `_lights`. Panels lie in the docking plane, so the broad face shows from the top and the 3/4 camera. `RAD_*`, `truss_along`, `build_radiators`
- **Back:** comms mast, two rear PDCs, link port at the axle tail.
- **Size:** 63.9 x 50.6 x 24.8 m, 27.9k tris (hull 25.7k, one atlas material; lights 2.2k).

**Built-in check.** `-- --check` re-measures `merc_interceptor.glb`, tests the four docking corridors, the sideways path, the outer berth spots and r <= 40, and prints `BERTH CHECK ... ALL OK`. Last full textured run: ALL OK, max XY radius 39.06 (radiator panel outer corner). `blender/gen_mercenary_outpost.py` (`check_build`, `measure_fighter`)

**Verified in game tooling.** The look-fix model loads in `tools/model_viewer.tscn` at `--dim=0.35` with four `merc_interceptor.glb` docked (`--model=<glb>@bx,0,3.5,180`): 5 of 5 loaded, no errors in the log. `Godot --headless --import` ran clean. Earlier (pre-look-fix geometry): two independent geometry checks. On the look-fix geometry: `tools/smoke.sh` and `tools/smoke.sh --multi` with 0 errors (2026-11-05).

**Previews.** Use `--no-ships` for previews without the docked ships. With ships, each berth gets a `merc_interceptor.glb`.

## Gotchas

- **The berth geometry is fixed by game code, not by the model.** `Building.berth_transform` / `dock_path` (`scripts/building.gd:420`) put ships at Blender (x, -3.5, 0) for x = -15, -5, 5, 15 and fly them straight along Y at z = 0 from spawn (0, -34, 0). Anything in the corridor x = bx +-4.3, z +-3.2, y -40..+3.5 gets flown through. Clamps are the one allowed exception (bottom z >= 2.40, top z <= -1.58). Run `--check` after every geometry change.
- **Footprint margin is 0.94 m.** The radiator panel outer corners sit at r 39.06 and the limit is 40 (`footprint_radius`). Longer or wider panels must be swept further forward or shortened (`RAD_SWEEP`, `RAD_T1`, `RAD_OUT`).
- **The texture bake flattens grey-on-white shading.** Rim facets in hull2 next to hull read almost the same after the textured build, so the drum's side darkening needs the `dark` material on the outermost facets. Judge shading on the textured previews, not the `--no-textures` ones. `blender/gen_mercenary_outpost.py` (`drum_mat`)
- **`link_point` moved to (0, 33.6, 0) at the axle tail.** It was (0, 18.6, 0.5). Game code reads it only on models without a `dock_point` (`scripts/building_manager.gd:451`), so nothing changes in game.
- **Running `Godot --import` can rewrite `.import` metadata of unrelated assets.** It did once during the first build. The look-fix run changed only this model's own three `.import` files. Check `git status` for stray `.import` changes after every reimport.
- **Emission is dimmed in game.** Judge lights with the viewer's `--dim=0.35`, not with the Blender previews (the coolant lines look bright in Blender and faint in the viewer).

## Remaining

- None. Delete this doc once you are happy with it.

## Open questions

- None.

## Decisions

- **Drum concept over "docking spine" and "Belter asteroid hole".** The spine had too little mass from the RTS camera. The asteroid would read as an enemy base (scavenger den, corsair nest and syndicate fortress are already rock bases).
- **Berth fields and `dock_point` / `spawn_point` unchanged.** This keeps `data/buildings/mercenary_outpost.tres` and ship docking untouched.
- **No text that reads as an airport.** NO STEP, HOT, FLT CTRL, LAUNCH and AMMO are gone. Labels are BAY n, MX-12, MERC, SPIN, ORD, OPS and "12".
- **Radiators as flat wings in the docking plane, not twisted blades.** Twisted narrow blades showed edge-on from both cameras. Flat panels show their broad face from above and from the 3/4 view, and fill the empty corners beside the drum.
- **Old version backup (session scratch, may be gone):** `/private/tmp/claude-501/-Users-hannesalm-code-games-space-majesty/3db159a0-2d9c-431d-a05f-99d0e05d0054/scratchpad/merc_old/`. Git HEAD also has the old script and glb.

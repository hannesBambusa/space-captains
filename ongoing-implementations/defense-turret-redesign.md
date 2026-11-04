# Defense turret redesign

| | |
|---|---|
| **Status** | in progress (model built and exported; silhouette rework not started) |
| **Branch** | main (uncommitted) |
| **Updated** | 2026-11-04 |
| **Scope** | Rebuild the Defense Turret model (`blender/gen_defense_turret.py` -> `defense_turret.glb`) in the home station's worn-industrial style, Expanse PDC look, station-level detail. |

User ask: "The turret has an orange circle on it.. it is designed to be connected to a space station like it was before.. need to do a redesign of the turret and have a much nicer texture.. should match the station design, more Expanse-like and just as detailed as the station." After the first pass: "continue with all that is not done".

**Work rule from the user: one thing at a time.** Run one agent and one Blender or Godot process at a time. Parallel agents and workflows overloaded the machine. No fan-out workflows.

## Files

**Owned:**

- `blender/gen_defense_turret.py` (rewritten), `blender/defense_turret.blend`
- `assets/models/buildings/defense_turret.glb`, `assets/models/buildings/defense_turret_defense_turret_{albedo,mr,normal}.jpg` (+ `.import`)
- `blender/textures/defense_turret_albedo.jpg`, `defense_turret_mr.jpg`, `defense_turret_normal.jpg`, `defense_turret_decals.png` (new, untracked); `defense_turret_mr.png` and `defense_turret_normal.png` deleted (replaced by the .jpg)
- `blender/previews/defense_turret_{preview,top,posed}.png` (modified), `defense_turret_{posed_low,posed_high,closeup,compare}.png` (new, untracked)
- `assets/ui/icons/build/defense_turret.png`

**Shared** (stage hunks):

- `blender/station_textures.py`: turret added defaulted `chip_scale` / `edge_cut` (in `build_worn_surface`) and `ao_far` / `edge_r` (in `bake_masks`, `bake_worn_atlas`). `ao_far` / `edge_r` are also used by `blender/gen_syndicate_fortress.py:772`.
- `blender/worn_kit.py`: `texture(..., ao_far, edge_r)` pass-through, same users as above.

**Not this feature** (dirty from other work): `data/buildings/defense_turret.tres` (cost_iron 60 -> 30), `tools/model_viewer.*` (the /3D skill viewer).

## Built

**PDM-2 "Warden" model.** It is a free-standing PDC platform. From the bottom up:
- a keel with a magazine can and 2 reaction-mass tanks
- a recessed core under a deck slab (r 7.6), with armour cassettes and an open ring truss under the rim
- radiator wings on +-X
- a deck with 2 horizontal tanks, ammo hatches with hoists, cable trays, floods and a lidar post
- a barbette (r 4.4, 3 m tall)
- a turret house with a ready magazine, swept link chutes, coolant fin stacks, a phased-array slab and a status lamp
- a pitch pod with 2 six-barrel rotary guns and muzzle brakes

The +Y side is a plain service block, with no corridor port and no orange ring. The full layout table is in the script docstring. File: `blender/gen_defense_turret.py`.

**Texture.** One worn atlas (4096 by default, `--res=2048` optional) built with `worn_kit.texture` and the station `WORN_KINDS`. The turret adds its own kinds: a hull override with a turret-scale panel grid, `gunmetal`, `tank`, `radfine`, `deckplate`, and the `FINE` edge wear. It carries stencils (DT-04, AMMO, PWR IN, SVC, EVA, MAG, NO STEP, FIRE CTRL, R-02, H2O, PDC 1/2). Accent is dark maroon, used only on small ammo tags.

**Game contract kept.** These are unchanged:
- root `defense_turret`
- `turret_yaw` (yaw deck z 15.6)
- `turret_pitch` (pitch axis Blender (0, 2.0, 18.0))
- `muzzle_l` / `muzzle_r` at y 10.95
- `turret_status_light` with its own material of that name, at `STATUS_O` (1.35, -2.2, 19.285)
- `link_point` (0, 9.4, 10.0)

All empties are unrotated. The footprint is 11.25 m (limit 11.5), 21.4k tris. Read by `scripts/buildings/defense_turret.gd` and `scripts/building_manager.gd:451`.

**Checks.** `--check` sweeps yaw 15 deg x pitch 5 deg (-25..70) for BVH overlap: 0 problems. An independent critic sweep at 5 / 2.5 deg also found 0. Godot imports cleanly, and the /3D viewer loads it.

**Build icon.** Re-rendered with `blender/render_icons.py -- defense_turret` (turret only).

## Gotchas

- **The glb and previews may be one edit behind the script.** The last edit is 02:24, the export 02:23. Re-run the full export before judging any image.
- **Blender previews and the Godot viewer disagree on dark materials.** The keel and deck tanks and the `radfine` wings look dark in Blender but mid or light grey in Godot. Judge value steps in the Godot shot, not the Blender previews. Godot shot: `Godot --path . res://tools/model_viewer.tscn -- --model=$PWD/assets/models/buildings/defense_turret.glb --dim=0.35 --shot=<png>`
- **Clearance has almost no headroom.** At pitch -25 the pitch pod is about 0.04 m from the yaw house. The receivers were trimmed from r 0.69 to 0.67 to pass. Any growth of the receivers, shrouds or fin stacks needs `--check` again.
- **Status lamp emission is 3; the old model's was 6.** `defense_turret.gd` uses `max(emission, 1.5)` as its base, so all three states glow at half the old brightness. Fix it in the model, not the .gd.
- **The export reuses the old texture file names** (`defense_turret_defense_turret_*.jpg`), so there is nothing stale to delete in `assets/models/buildings/`.
- **`radfine` channel lines alias into ~0.1 m stripes in Godot.** The seam groove depth is hard-coded in shared `station_textures.py`. Use wider plates, or a plain panel.
- **The session scratchpad is wiped between sessions.** Keep work files in the repo or under `ongoing-implementations/`.

## Remaining

Last review verdict: the texture and detail are approved. The **silhouette** still reads as a three-tier layered cake (deck slab, plain barbette drum, gun house on top), with about 60% of the mass in the base. Do this as one agent, one process at a time:

1. **Re-export first** (see Gotchas) and look at the fresh previews and a Godot shot.
2. **Compact PDC silhouette** (`build_drum`, `build_barbette`, `build_pitch`).
   - Lower and tighten the base. Break up the solid saucer slab with open truss sectors or notches.
   - Cut the barbette to about 1.5 m, or break it with dark strakes and a recessed band. Keep the gun >= 15 m up.
   - Fatten the shrouds and receivers about 25%, and add a full-length dark jacket from y 5.3 to 9.8.
   - Add a dark bellows mantlet (box x +-1.9, y 0.1..1.0, z 16.6..18.9) to close the black slot between the house front and the pod.
3. **Under-slab armour cassettes** at 243/297 deg (`build_drum`) read as pale AC units. Make them slate or dark, thinner, with a chamfered outer face and no top bolt row.
4. **Keel tanks and MAG can** (`build_keel`) read as pale bottles in Godot. Use a dark kind, or roughness ~0.65 and metal ~0.1, or shorten them so they hide behind the ring truss.
5. **Radiator wings** (`build_wings`) are vertical and edge-on from the game camera, and read as corrugated shutters.
   - Lay them near horizontal: one larger panel per side, a thin light frame, within r 11.5.
   - Make `radfine` rougher and less metal.
   - Drop the hanging / standing panel pair.
6. **Ammo hoists** (`build_shoulder`) read as gallows. Either hang a visible gunmetal canister (about 0.6 x 0.6 x 0.9) over the hatch and knee-brace the jib, or make it a cantilever monorail from the barbette feed box.
7. **Deck tanks** read as propane bottles. Give them flat or shallow dished heads with a dark end ring, 2-3 dark straps and roughness ~0.65, or recess them half into a dark trough.
8. **Rear chamfer floods** (`build_yaw`) compete with the status lamp. Use a smaller recessed lens with a hood lip, or emission ~1.5.
9. **Link chutes** read as segmented vacuum hose. Flatten them to about 0.5 x 0.18, clamps every ~1.2 m at 0.03 oversize, roughness ~0.55.
10. **Labels.**
    - Remove the barbette "PDC 1" (it collides with a window).
    - Move the pod's PDC 1/2 onto the receiver tops, facing up. They are hidden inside the cheeks today.
    - Drop the unused "LIVE AMMO" from `LABELS`.
11. **Status lamp emission** back to about 6 (`build_materials` / `build_status`).
12. **`--check`** resolution up to yaw 5 deg / pitch 2.5 deg.
13. **After each change:**
    1. Run Blender export and `--check`.
    2. Run `Godot --headless --path . --import`.
    3. Re-render the icon.
    4. Look at `blender/previews/defense_turret_compare.png` next to the station, and at a Godot shot.
14. **Not tested in a live match.** Check tracer origins (the pitch axis moved +0.4 m) and lamp colours in game, e.g. with `tools/smoke.sh` or `--screenshot`.

## Open questions

- **Relax `pitch_min_port_deg`?** It is -8 in `scripts/buildings/defense_turret.gd:41`. Nothing tall remains on the +Y side, so -25 all round would clear (sweep min 0.68 m to the base). This is a gameplay-code change, so the user decides.

## Decisions

- **Design: PDM-2 "Warden".** Chosen from three concepts (Warden, Picket, Node Gun). It had the best PDC read and clearance analysis. It took grafts from the other two: the panel grid, the base height assert, the bolt circle, the elevation drive and the posed_low / posed_high shots.
- **Style template: `blender/gen_mining_outpost.py`.** It uses `worn_kit` and the station `WORN_KINDS` bake, which is the same language as the station.
- **`link_point` stays on +Y (Godot -Z) as a plain service side.** `BuildingManager` still turns it toward the station; there is no corridor port, because structures stand free.
- **No gameplay `.gd` / `.tres` edits.** This is a model-only feature.
- **Shared texture modules get only defaulted parameters,** so other models bake identically.

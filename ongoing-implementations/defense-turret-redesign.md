# Defense turret redesign

| | |
|---|---|
| **Status** | done (all review items built and checked; one open question; uncommitted) |
| **Branch** | main (first model in db35437; silhouette rework uncommitted) |
| **Updated** | 2026-11-04 |
| **Scope** | Rebuild the Defense Turret model (`blender/gen_defense_turret.py` -> `defense_turret.glb`) in the home station's worn-industrial style, Expanse PDC look, station-level detail. |

User ask: "The turret has an orange circle on it.. it is designed to be connected to a space station like it was before.. need to do a redesign of the turret and have a much nicer texture.. should match the station design, more Expanse-like and just as detailed as the station." After the first pass: "continue with all that is not done". Then: "Do this work until defense tower is 100% finished".

**Work rule from the user: one thing at a time.** Run one agent and one Blender or Godot process at a time. Parallel agents and workflows overloaded the machine. No fan-out workflows.

## Files

**Owned:**

- `blender/gen_defense_turret.py`, `blender/defense_turret.blend`
- `assets/models/buildings/defense_turret.glb`, `assets/models/buildings/defense_turret_defense_turret_{albedo,mr,normal}.jpg` (+ `.import`)
- `blender/textures/defense_turret_{albedo,mr,normal}.jpg`, `blender/textures/defense_turret_decals.png`
- `blender/previews/defense_turret_{preview,top,posed,posed_low,posed_high,closeup,compare}.png`
- `assets/ui/icons/build/defense_turret.png`

**Shared** (already committed in db35437, not touched since):

- `blender/station_textures.py`: defaulted `chip_scale` / `edge_cut` (in `build_worn_surface`) and `ao_far` / `edge_r` (in `bake_masks`, `bake_worn_atlas`). `ao_far` / `edge_r` are also used by `blender/gen_syndicate_fortress.py`.
- `blender/worn_kit.py`: `texture(..., ao_far, edge_r)` pass-through.

## Built

**PDM-2 "Warden" model, compact PDC silhouette.** The mass sits high: a thin deck, a dark machine neck, a compact gun house. From the bottom up:
- a keel (magazine can, two short reaction-mass tanks), all matte dark, raised 0.8 m
- a recessed core with thin chamfered armour cassettes and an open ring truss under the slab
- a thin deck slab: 0.55 m armoured edge (r 7.6) over an underside sloping back to the core, three rim notches cut to r 6.6 (wing roots at +-X, power conduit at +Y)
- radiator wings: one broad near-horizontal panel per side (10 deg tilt to the camera), thin light frame, manifold out of the notch
- a deck with 2 flat-headed strapped tanks, ammo hatches with cantilever monorail hoists (knee brace, trolley, hanging ammo canister), cable trays, floods and a lidar post
- a barbette: armoured foot, tall dark recessed band with strakes and an EVA door module, short collar under the turntable
- a turret house with a ready magazine, flat link chutes with sparse clamps, coolant fin stacks, a phased-array slab, small dim rear floods under hood lips and the status lamp
- a dark pleated bellows mantlet (an arc round the pitch axis) closing the slot between the house front and the pod
- a pitch pod with fat receivers (r 0.84, PDC 1 / 2 on their top plates), two six-barrel rotary guns in full-length dark cooling jackets with shroud rings and muzzle brakes

The full layout table is in the script docstring. File: `blender/gen_defense_turret.py`.

**Texture.** One worn atlas (4096) built with `worn_kit.texture` and the station `WORN_KINDS`. Turret kinds: hull override, `gunmetal`, `tank`, `tankdark` (keel / deck tanks, magazine can), `chute`, `radfine` (rough 0.72, metal 0.04, 0.4 m channels), `deckplate`, and the `FINE` edge wear. `LIVE AMMO` dropped from `LABELS`; the barbette "PDC 1" removed.

**Game contract kept.** Unchanged: root `defense_turret`, `turret_yaw` (z 15.6), `turret_pitch` (axis Blender (0, 2.0, 18.0)), `muzzle_l` / `muzzle_r` at y 10.95, `turret_status_light` (own material, at `STATUS_O`, emission back to 6), `link_point` (0, 9.4, 10.0). All empties unrotated. Footprint 11.29 m (limit 11.5), 23.3k tris.

**Checks.**
- `--check` sweeps yaw 5 deg x pitch 2.5 deg (-25..70): 0 problems; it prints the hit locations when something clashes. Cone min margin 0.38 m (the lidar cap), with `zmax` now allowing for the r 0.69 shroud rings.
- Godot import clean; viewer shot checked; icon re-rendered with `blender/render_icons.py -- defense_turret`.
- Live match (temporary tool, deleted after): turret built next to the station, 3 raiders sent at it. Lamp went green (idle) -> amber (tracking) -> red (firing), base emission 2.1 in Godot (the old model's level). The muzzle empties sit at the barrel tips (10.98 m out, 18.29 m up at 1.8 deg pitch), which is where `_muzzle_position` spawns the tracers. 21 shots fired in 8.5 s, no script errors. No frame caught a tracer in flight.

## Gotchas

- **Dark dielectrics read mid grey in Godot.** A baked albedo of ~0.26 sRGB (the deck's) looks mid grey in Godot; the `dark` kind only reads black because it is metal 0.55. To make a part read dark, lower its tones (~0.04 linear) and give it some metal (0.35 on `tankdark`). Judge values in a Godot shot, not the Blender previews: `Godot --path . res://tools/model_viewer.tscn -- --model=$PWD/assets/models/buildings/defense_turret.glb --dim=0.35 --shot=<png>`
- **Clearance has little headroom.** With the receivers at r 0.84 on the pitch axis, their belly hit the turntable top (z 16.0) at pitch -25 and -22.5; the receiver axis sits 0.17 m above the pitch axis so the belly stays where the old r 0.67 one was (margin not measured). The mantlet's inner radius (1.42) clears the pod's rear corners (r 1.35). Any change to the pod, receivers or mantlet needs `--check` again.
- **A fast build overwrites the textured glb.** `-- --no-textures` still exports, with flat colours. Always finish with a full build before importing or judging in Godot.
- **Blender aborted once (exit 134) during the bake, right after the decal sheet,** with no Python error. A rerun worked.
- **The export reuses the old texture file names** (`defense_turret_defense_turret_*.jpg`), so there is nothing stale to delete in `assets/models/buildings/`.
- **The session scratchpad is wiped between sessions.** Keep work files in the repo or under `ongoing-implementations/`.

## Remaining

- **Commit** (user), then delete this doc and its README row once the open question is settled.

## Open questions

- None.

## Decisions

- **Design: PDM-2 "Warden".** Chosen from three concepts (Warden, Picket, Node Gun). It had the best PDC read and clearance analysis.
- **Style template: `blender/gen_mining_outpost.py`.** It uses `worn_kit` and the station `WORN_KINDS` bake, the same language as the station.
- **`link_point` stays on +Y (Godot -Z) as a plain service side.** No corridor port, because structures stand free.
- **No gameplay `.gd` / `.tres` edits, except one:** `pitch_min_port_deg` is -25 (was -8) in `scripts/buildings/defense_turret.gd`, the same as everywhere else, since the PDM-2 clears it all round. Claude's call, the user delegated it (2026-11-04).
- **Shared texture modules get only defaulted parameters,** so other models bake identically.
- **Barbette broken up, not cut to 1.5 m.** Cutting it means lowering the yaw deck (or raising the slab), which pushes the deck tanks, hoists and lidar through the -25 deg barrel cone. A tall dark recessed band with strakes and a short collar gets the same read without moving the game contract.
- **Hoists are cantilever monorails, not gantries.** The gantry post read as a gallows; the rail now comes out of the barbette feed box with a knee brace.
- **Tanks are metal 0.35, not ~0.1 as the review suggested,** because of the Godot value gotcha above.

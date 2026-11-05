# Shield generator redesign

| | |
|---|---|
| **Status** | done |
| **Branch** | main (field effect committed in db35437; model change uncommitted) |
| **Updated** | 2026-11-04 |
| **Scope** | Rebuild the Shield Generator model in the worn-industrial style of the redesigned turret / merc outpost / mining outpost, and make it feel like a force field (in-game animated field orb). |

User ask: "redesign the Shield Generator so it matches the new designs of the redesigned buildings. Needs to look professional and feel like a force field."

**Work rule from the user: one thing at a time.** Run one agent / one Blender or Godot process at a time. No fan-out workflows for this feature.

## Files

**Owned, uncommitted (stage these):**

- `blender/gen_shield_generator.py` (rewritten: the containment gimbal), `blender/shield_generator.blend`
- `assets/models/buildings/shield_generator.glb`
- `assets/models/buildings/shield_generator_shield_generator_{albedo,mr,normal}.jpg` + `.import` (new, Godot-extracted)
- deleted: `assets/models/buildings/shield_generator_shield_{albedo,mr,normal}.jpg` + `.import`
- `blender/textures/shield_generator_{albedo.jpg,mr.jpg,normal.jpg,decals.png}` (new); deleted: `blender/textures/shield_albedo.jpg`, `shield_mr.png`, `shield_normal.png`
- `blender/previews/shield_generator_{preview,top,game,closeup,compare}.png`
- `assets/ui/icons/build/shield_generator.png`
- `tools/shield_preview.gd` (default model now the repo glb; `--close`, `--shot-after=<s>`), `tools/shield_preview.gd.uid` (new)
- `ongoing-implementations/shield-generator-redesign.md` (this doc)

**Committed in db35437:** `scripts/buildings/shield_field_core.gd`, `shaders/shield_field_core.gdshader`, `shaders/shield_field_ring.gdshader`, `scripts/buildings/shield_generator.gd`, `tools/shield_preview.tscn`, the work folder `ongoing-implementations/shield-generator-redesign/` (variant scripts; deleted from the tree since).

**Not this feature** (dirty in the tree from other work): `scripts/ai/mercenary_*`, `scripts/research/*`, `scripts/ui/research_*`, `scripts/ui/science_lab_panel.gd`, `scripts/ui/tutorial_card.gd`, `scripts/rival/rival_manager.gd`, `scenes/system.tscn`, `scripts/space_dust.gd*`, `shaders/space_dust.gdshader*`.

## Built

**Force-field core effect (Godot).** Hex-lattice orb (r 4.0) plus an equator quad with a dashed ring and 3 pulse rings out to 9.5 m, at the model's `shield_emitter_point`. Follows StationShield state (raising, up, low flicker, collapse, down with sputters, hit flash). Files: `scripts/buildings/shield_field_core.gd`, `shaders/shield_field_core.gdshader`, `shaders/shield_field_ring.gdshader`, `scripts/buildings/shield_generator.gd`.

**Containment gimbal model (shipped).** Picked by the user over the lens and coil spire variants. Base plant (drum r 9.4, 4 capacitor banks, +-X fin radiators, cabin -Y, service +Y, link_point (0, 13.2, 3.5)), turntable and U-fork, three nested tilted rings (R 9.2 / 7.4 / 5.9) around the cradle at (0, 0, 22.5). 33,450 tris, 34 x 38.2 x 25.9 m, 4096 atlas, `CONTRACT OK`. Layout table in the script docstring. File: `blender/gen_shield_generator.py`, output `assets/models/buildings/shield_generator.glb`.

**Verified 2026-11-04.** Model viewer shot clean. `tools/shield_preview.tscn -- --close --shot-after=8`: orb sits inside the rings, pulse rings read through them. New game with a finished generator placed by a temporary script: ShieldFieldCore at building-local y 22.5, "Station shield online", no errors. `tools/smoke.sh` and `tools/smoke.sh --rival` exit 0, 0 errors. Icon re-rendered. A thin dark "spike" under the drum in some in-game shots is the +-X radiator fin pair seen edge-on (camera on the X axis); a 40 deg turn shows it as the fin panel. Not a defect.

## Gotchas

- **Construction look replaces every material under the model.** So the field core is a child of the Building, not of `shield_emitter_point`; it is placed with `ModelLoader.relative_transform(building, point)`. `scripts/buildings/shield_field_core.gd`
- **`shield_generator.gd` preloads the core script instead of using `class_name ShieldFieldCore`.** The global class cache only learns new classes on `--import`.
- **Model contract the Godot code depends on** (keep exact): root empty `shield_generator`; mesh `shield_base`; mesh `shield_emitter_glow` with ONE material; mesh `shield_capacitors` with ONE material, strips sharing one bottom z, origin at that bottom; empty `shield_emitter_point` at the cradle centre (clear sphere r 4.5, core r <= 1.2); empty `link_point` unrotated on +Y. Max radius 20 m, height <= 44 m. The script's `check()` enforces all of it.
- **Slate takes no stencils.** `blender/station_textures.py` `bake_worn_atlas` labels only hull, hull2, hull3, pad, dark, metal and mli; a label on slate is silently dropped.
- **A `-s` SceneTree script cannot reference autoloads or project classes** (compiled before they exist). For one-off in-game checks, load a separate Node script at runtime.

## Remaining

1. Commit (user), then delete this doc and its README row. The work folder `ongoing-implementations/shield-generator-redesign/` is deleted (2026-11-04); its concept scripts show as deleted in git and stay in db35437.

## Open questions

## Decisions

- **Containment gimbal ships** (user, 2026-11-04), over the lens and the coil spire.
- **Effect is Godot-side, not in the glb**: Blender owns meshes only (project rule); the animated orb needs shader state from StationShield.

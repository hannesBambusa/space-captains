# Shield generator redesign

| | |
|---|---|
| **Status** | in progress (Godot field effect built; new model not exported yet) |
| **Branch** | main (uncommitted) |
| **Updated** | 2026-11-04 |
| **Scope** | Rebuild the Shield Generator model in the worn-industrial style of the redesigned turret / merc outpost / mining outpost, and make it feel like a force field (in-game animated field orb). |

User ask: "redesign the Shield Generator so it matches the new designs of the redesigned buildings. Needs to look professional and feel like a force field."

**Work rule from the user: one thing at a time.** Run one agent / one Blender or Godot process at a time. Parallel agents (5 at once) overloaded the machine. No fan-out workflows for this feature.

## Files

**Owned:**

- `ongoing-implementations/shield-generator-redesign/gen_shield_lens.py`: recovered "lens" variant Blender script (work copy, writes to `out/` next to it, git-ignored)
- `ongoing-implementations/shield-generator-redesign/gen_shield_coil.py`: coil spire variant, outputs `out/shield_generator_coil.glb` + `out/coil_*.png`
- `ongoing-implementations/shield-generator-redesign/gen_shield_gimbal.py`: containment gimbal variant, outputs `out/shield_generator_gimbal.glb` + `out/gimbal_*.png`
- `tools/shield_preview.gd`, `tools/shield_preview.tscn` (new, untracked): look-only preview of station + generator + bubble + field core cycling every bubble state
- `ongoing-implementations/shield-generator-redesign/.gitignore`
- `scripts/buildings/shield_field_core.gd` (new, untracked): ShieldFieldCore, the orb + pulse ring effect
- `shaders/shield_field_core.gdshader`, `shaders/shield_field_ring.gdshader` (new, untracked)
- `scripts/buildings/shield_generator.gd`: header doc, `EMITTER_POINT`, `FIELD_CORE` preload, core creation in `_on_setup`, `_core.update_look` in `_animate`
- To be replaced (still old): `blender/gen_shield_generator.py`, `blender/shield_generator.blend`, `assets/models/buildings/shield_generator.glb`, `blender/previews/shield_generator_*.png`, `assets/ui/icons/build/shield_generator.png`
- To be deleted once the new glb exports: `blender/textures/shield_albedo.jpg`, `shield_mr.png`, `shield_normal.png`, `assets/models/buildings/shield_generator_shield_{albedo,mr,normal}.jpg` (+ `.import`), if the new glb no longer references them

**Not this feature** (dirty in the tree from other work): `data/buildings/shield_generator.tres` (cost_iron 150 -> 75), `data/modules/shield_projector_*.tres`, `tools/smoke*`, `shaders/sun*.gdshader`.

## Built

**Force-field core effect (Godot).** A hex-lattice orb (SphereMesh r 4.0) and a flat equator quad with a dashed ring plus 3 pulse rings running out to 9.5 m, placed at the model's `shield_emitter_point`. Additive, unshaded, colour (0.32, 0.72, 1.0) shifting to the bubble's low colour when weak. Follows StationShield state: hidden under construction / destroyed / no shield; RAISING grows in from 0.25x; UP steady, 8% pulse, flicker under `low_fraction`; COLLAPSING burst and swell to 1.3x; DOWN off with sputters near re-raise; hit flash from `shield.last_hit_time` (read only). Uses SimClock.time. Files: `scripts/buildings/shield_field_core.gd`, `shaders/shield_field_core.gdshader`, `shaders/shield_field_ring.gdshader`, `scripts/buildings/shield_generator.gd`. Verified: `tools/smoke.sh` and `tools/smoke.sh --rival --minutes 14` exit 0, 0 errors (neither builds a shield generator); a deleted temp tool placed one in a new game, no errors. Only seen with the OLD model (orb at building-local y 41.5).

**"Lens" model variant (Blender, not in the repo assets).** SG-01 projector ring lens: squat armoured drum (r 9.6), 4 capacitor banks on outriggers (r 13.5, diagonals), radiator wings on +-X, control cabin on -Y, service block on +Y (link_point (0, 13.4, 3.6)), column with a parabolic reflector bowl whose focus is the cradle, 3 gimballed pylons (90/210/330) holding a segmented lens ring (r 12) level with the cradle, 12 inward emitter prongs with cyan tips. Contract checked in the agent's run: names/hierarchy, cradle clearance 4.88 m (limit 4.5), extent r 18.5, height 29.65, 29,490 tris (1.38x turret). Full layout table in the script docstring. File: `ongoing-implementations/shield-generator-redesign/gen_shield_lens.py`. The script was rebuilt from the agent's transcript (one Write + 4 patch scripts replayed). Re-run 2026-11-04 at --res=2048: `CONTRACT OK`, ~61 s, outputs in `out/` (`shield_generator.glb`, `lens_{preview,top,game,closeup,compare}.png`); all replayed patches applied, no hand fixes. Weakness pass (2026-11-04): preview lighting gets a shadowless fill sun from +X+Y and a steeper key (no more black radiator / NE bank); capacitor cabinets are chamfered octagonal prisms (`cab_ring` / `cab_prism` / `cab_body`) with gunmetal corner posts, a sloped shoulder, a band, a raised slate label plate per side, an outer-face visor and pilasters, a roof breaker box and vent grille; stencils enlarged (drum SG-01 1.15 m at 202 / 22 deg, cabin SG-01 0.95 m, ring outer-face labels 0.6-0.72 m with ink matched to the slate / hull2 plate, CAP BANK 0.62 m, roof HV 0.8 m, LENS A-C 0.55 m); underside detail (`build_underside`: ribs, hatches, conduit ring, sensor pods, dish). 30,846 tris, contract OK.

**"Coil spire" model variant (Blender, work folder).** Tall: drum r 9.4 with the same plant (4 cap banks r 13.3 on the diagonals, +-X vertical fin radiators, cabin -Y, service +Y, link_point (0, 13.2, 3.5)), plinth and column carrying 5 stacked field coils (z 9.8..22.8, outer r 7.2 -> 4.29, cyan slots, COIL 1-5 stencils), 4 diagonal ribs (HV busbars land on their foot blocks) up into a crown: cup r 5.3 with a cyan ring, 4 arms out to r 7.45 and back in as talons with emitters, brace ring r 6.35. Cradle (0, 0, 30), height 40.59, r 17.0, 33,434 tris, contract OK (its check() also enforces hierarchy, empties, link_point, single materials, tris <= 40k). Layout table in the script docstring. File: `ongoing-implementations/shield-generator-redesign/gen_shield_coil.py`.

**"Containment gimbal" model variant (Blender, work folder).** Same base plant as the coil (drum r 9.4, deck z 6.4, caps r 13.3, +-X fin radiators, cabin -Y, service +Y, link_point (0, 13.2, 3.5)). Turntable r 5.0 (z 8.24..10.1, slew drives at 90 / 270, HV junction blocks r 7.75 on the diagonals where the busbars land), yoke hub z 11 with a projector dish (cyan tip z 14), U-fork arms at x +-11.2 up to z 22.5 with knee rams, bearing housings with trunnions and outboard drive motors (to x +-13.76, red nav on top). Three nested static rings: outer R 9.2 tilted 70 deg about X; middle R 7.4 tilted +45 deg about the outer's Y (drive pod + white nav at the top pivot, z 32.9); inner R 5.9 tilted -50 deg about the middle's X; frames every 30 deg, gunmetal collars and pins at every pivot, cyan slots and emitter nodes on the inner faces. Cradle (0, 0, 22.5), height 38.21, r 17.0, 33,450 tris, contract OK (check() also requires every ring's inner edge >= 5.0 m: 8.65 / 6.95 / 5.50). File: `ongoing-implementations/shield-generator-redesign/gen_shield_gimbal.py`.

**Shield preview tool.** `tools/shield_preview.tscn` loads the station glb and a generator glb (default the lens in `out/`, `--model=` for another), fits the bubble like StationShield.refit, and loops OFFLINE -> RAISING -> UP -> under fire (auto hits, HP drains) -> LOW flicker -> COLLAPSING -> DOWN (12 s, sputter) -> re-raise at 40% -> recharge. It drives `station_shield.gdshader` the way `_update_look` does and the real ShieldFieldCore through `update_look` with a StationShield object never added to the tree. Keys H hit, R restart, Space pause, 1-4 speed, F reset view, Q quit; `--shot=<png>` saves a frame and quits. Verified with `--shot`: bubble r 217 m and the generator inside it render.

## Gotchas

- **The session scratchpad is wiped between sessions.** All variant outputs (glbs, previews, the lens script) were lost that way. Keep work files under `ongoing-implementations/shield-generator-redesign/`, never in `/private/tmp/...scratchpad`.
- **Construction look replaces every material under the model.** So the field core is a child of the Building, not of `shield_emitter_point`; it is placed with `ModelLoader.relative_transform(building, point)`. Parenting it under the model breaks the orb during and after construction. `scripts/buildings/shield_field_core.gd`
- **`shield_generator.gd` preloads the core script instead of using `class_name ShieldFieldCore`.** The global class cache only learns new classes on `--import`; without it the class name fails to resolve. Keep the preload or run `--import` first.
- **Model contract the Godot code depends on** (keep exact): root empty `shield_generator`; mesh `shield_base` (atlas + joined flat lamps); mesh `shield_emitter_glow` with ONE material (Godot duplicates surface 0 and pulses `emission_energy_multiplier`); mesh `shield_capacitors` with ONE material, vertical strips sharing one bottom z, origin at that bottom (Godot scales local Y 0.04..1 for charge); empty `shield_emitter_point` at the cradle centre; empty `link_point` unrotated on the +Y side (Godot -Z), turned toward the station by `scripts/building_manager.gd:451`. Max radius 20 m (footprint_radius 22), height <= 44 m.
- **Field cradle: clear sphere r 4.5 m around `shield_emitter_point`**, only a core of r <= 1.2 inside. The orb is r 4.0.
- **Coil spire: the 225 deg crown arm crosses the orb in the Blender preview camera** (azimuth ~239). Kept on the diagonals because the game camera (from -Y) frames the orb between two arms.
- **Slate takes no stencils.** `blender/station_textures.py` `bake_worn_atlas` (~line 1141) applies labels only to the hull, hull2, hull3, pad, dark, metal and mli materials; a label on slate is silently dropped. Put labels on hull2 (or another listed kind).
- **Gimbal rings cross the orb and the pulse quad.** The inner ring's tilted ellipse passes through the r 4 orb's silhouette and the 9.5 m equator pulse quad in previews; in Godot the pulses will likely run through the rings (same open issue as the lens prongs). Middle ring dips to ~z 15 near the hub dish, ~1.5 m clear.
- **Lens ring sits at cradle height, so the 12 prongs (r 6.3..12) cross the equator pulse quad (out to 9.5 m).** The quad is depth-tested; pulses may look like they run along the prongs. Not checked in engine.
- **Variant scripts must redirect outputs before baking**: `st.TEX_DIR` and `common.PREVIEW_DIR` default into `blender/textures` and `blender/previews`. `worn_kit.SCRATCH` points at a dead old scratchpad; `wk.previews` only copies there if it exists.

## Remaining

Do these one at a time, in order.

1. **Pick the variant** (user, from the three `*_compare.png` / `*_preview.png`).
2. **Promote to the repo script**: replace `blender/gen_shield_generator.py` with the chosen variant's script, using repo conventions (docstring like `blender/gen_defense_turret.py`, PRE `shield_generator`, OUT `assets/models/buildings/shield_generator.glb`, BLEND `blender/shield_generator.blend`, default `st.TEX_DIR` / `common.PREVIEW_DIR`, `--res` default 4096, preview-only orb never exported). Run at 4096. Delete the old textures listed in Files.
3. **Re-render the icon**: `Blender -b --python blender/render_icons.py -- shield_generator`.
4. **Reimport**: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import`.
5. **Check in engine**: model viewer shot `Godot --path . res://tools/model_viewer.tscn -- --model=<abs glb> --shot=<abs png>`; place a shield generator in a game and screenshot the orb in the new cradle (orb now at y ~22, not 41.5); check the prong / pulse-ring overlap; `tools/smoke.sh` and `tools/smoke.sh --rival`.
6. Delete `ongoing-implementations/shield-generator-redesign/` (work folder) once the repo script is the source of truth, and this doc when shipped.

## Open questions

- Which variant ships (lens, coil spire or containment gimbal)? Decide after comparing the three previews.

## Decisions

- **Fix all lens weaknesses and build the coil spire and containment gimbal variants for comparison** (user, 2026-11-04). Variants are built one at a time, each as its own script in the work folder.

- **Lens concept carried forward** because it is the only variant that completed and passed its contract check; redoing three variants cost too much machine time.
- **Effect is Godot-side, not in the glb**: Blender owns meshes only (project rule); the animated orb needs shader state from StationShield.

# Sound effects

Drop files here with exactly these names. The game plays any that exist and
skips missing ones silently. Mix (gain, voices, pitch jitter) is set per
sound in the SOUNDS table in `scripts/sfx.gd`.

Format: `.wav`, 44.1 or 48 kHz, 16-bit. Mono for world sounds (they are 3D
positioned), mono or stereo for UI cues. Trim leading silence.

## World sounds (3D, heard only in the viewed system)

| File | When it plays | Length | Notes |
|---|---|---|---|
| `autocannon_1.wav`, `_2`, `_3` | Every gun shot (ships, turrets, dens) | 0.1-0.4 s | Very frequent; 3 variants, picked at random |
| `hull_hit_1.wav`, `_2`, `_3` | A shot hits hull | 0.1-0.4 s | Very frequent; 3 variants |
| `shield_hit.wav` | A shot hits a ship whose shield holds | 0.2-0.5 s | |
| `explosion_small_1.wav`, `_2`, `_3` | A ship dies | 1-2 s | 3 variants |
| `explosion_big.wav` | A station, den or building dies | 2-4 s | Heavy, low |
| `warp_spool.wav` | Ship charges its warp drive | about 2.5 s | Rising |
| `warp_jump.wav` | Ship jumps to warp | 0.5-1.5 s | |
| `gate_transit.wav` | Ship goes through a jump gate (in and out) | 1-2 s | |
| `dock.wav` | Ship docks at a station | 0.5-1.5 s | Mechanical clunk |
| `undock.wav` | Ship leaves a station | 0.5-1.5 s | |
| `mining_laser.wav` | While a drill beam is on | 2-5 s | Must loop seamlessly |
| `missile_launch.wav` | Not used yet (no missiles in the game) | 0.5-1 s | Optional |

## Cues (flat, not positioned)

| File | When it plays | Length | Notes |
|---|---|---|---|
| `ui_click.wav` | Any button press | under 0.1 s | Very frequent, keep it soft |
| `ui_hover.wav` | Mouse moves onto a menu button | under 0.1 s | Very frequent, quieter than click |
| `build_placed.wav` | A structure is placed | 0.3-1 s | |
| `research_done.wav` | A research project finishes | 0.5-1.5 s | |
| `alert.wav` | Raid warning (hostiles inbound) | 1-2 s | Rate-limited to once per 3 s |
| `contract_posted.wav` | Player posts a contract | 0.2-0.6 s | |

Income makes no sound, by design.

After adding files, open the project in Godot once (or run a build) so they
get imported. Then tune loudness in the `db` column of `SOUNDS`.

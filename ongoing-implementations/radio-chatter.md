# Radio chatter

| | |
|---|---|
| **Status** | built; needs your listen test |
| **Branch** | main (uncommitted) |
| **Updated** | 2026-11-11 |
| **Scope** | Idea 4 of the 2026-11-10 list: voiced captain radio lines, 8 voices (user's pick), with subtitles. |

## Files

**Owned:**

- `scripts/ui/radio_chatter.gd`: RadioChatter (hooks, limits, playback, subtitle)
- `data/radio/radio_lines.json`: voices, settings, every line
- `assets/audio/voice/radio/**`: 240 mp3 (+ `.import`)
- `tools/gen_radio_lines.py`: generator (ElevenLabs, skips existing files)
- `tools/radio_test.gd`, `tools/radio_test.tscn`

**Shared:**

- `scripts/ui/hud.gd`: `radio` member and its creation
- `scripts/captain.gd`: `voice` field (saved), `voice_slot()`
- `scripts/ships/gate_transit.gd`: one `RadioChatter.say(..., &"jump")` in `start`
- `default_bus_layout.tres`: bus 6 "Radio" and its three effects; `scripts/audio_settings.gd`: "Radio" in BUSES (slider)
- `docs/DESIGN.md` ("Radio chatter"), `CLAUDE.md` (Run lines)

## Built

**Events.** Brain `state_changed` (UNDOCKING with a mining or bounty trip, MINING, RETURNING loaded from MINING, merc RETURNING retreating, UNLOADING, FLEEING, HUNTING on a bounty), `decided` refusals (15%), `damaged` (under fire after 15 sim s quiet, shields_down once per fight), CombatWorld `combatant_destroyed` (kills of raiders), GateTransit.start (jump), raid warnings and the warlord PRESENT phase (`_watch_threats`). Ships are hooked once (meta "radio_hooked") by a 1 s scan of the viewed system. `scripts/ui/radio_chatter.gd`

**Limits.** Viewed system only; GLOBAL_GAP 12, CAPTAIN_GAP 45, EVENT_GAP 60 real s; PRIORITY 3 lines skip the first two and interrupt lower ones.

**Audio.** 8 premade ElevenLabs voices, model eleven_multilingual_v2, stability 0.45, similarity 0.8, style 0.3, speed 1.05, seed 7. Radio bus (comms sound, 2026-11-11 after the user found it too loud): high pass 450, low pass 2,700 (resonance 0.7), overdrive 0.4 (post -4 dB), compressor -22 dB 6:1, Amplify -18 dB (the slider resets the bus volume on start, so the level cut lives in the chain). Each line opens with a click and static and closes with a static tail (`_make_static`, generated). A missing file shows the subtitle only.

**Tests.** `tools/radio_test.tscn` on 2026-11-11: 240 of 240 files, 6 lines heard and voiced in one run (launch, raid alert, fleeing, under fire, delivered, kill). Voiceprint per voice folder (Resemblyzer, scratchpad): medians 0.84 to 0.92; the lowest are very short or shouted lines, and two retakes on seed 41 scored lower, so the originals stay.

## Gotchas

- **AudioSettings.apply_saved overwrites every slider bus's volume_db at start.** A fixed level change for the Radio bus must be an effect (AudioEffectAmplify), not `bus/6/volume_db`. `default_bus_layout.tres`

- **The API key cannot list voices and Lily (pFZP5JQG7iQjIQuC4Bkp) is gone (404).** Probe a premade voice id with a one-line request before using it.
- **Short shouted lines score low on a voiceprint without being drift.** Compare a retake before replacing one.

## Remaining

- **Listen test (user):** the new comms chain (level -18 dB, 450 Hz to 2.7 kHz, static bursts); then the 8 voices against the personalities.

## Open questions

- None.

## Decisions

- **Premade voices, not designed ones.** The key has no voice-design or listing rights; premade ids work for text to speech.
- **Voice slot from the name when unset.** Rolling it at hire would shift every seeded smoke run's RNG.
- **Radio bus is not a sidechain for the music duck.** Only SOLA (Voice) ducks the music.

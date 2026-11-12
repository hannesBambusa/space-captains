# Tutorial academy and SOLA voice

| | |
|---|---|
| **Status** | done (2026-11-10, by the user's call); listen and play test deferred, see Remaining |
| **Branch** | main (all code committed, last in d69d22c) |
| **Updated** | 2026-11-10 |
| **Scope** | Main menu Tutorial: a guided game (ACADEMY, 10 chapters, 35 steps) told as a story by SOLA, the station AI, with ElevenLabs voice lines, replay button and its own music. |

## Files

**Owned:**

- `scripts/ui/tutorial.gd`: Tutorial (modes QUICK / ACADEMY, steps, chapters, checks, top-ups, safety, save state, station zoom, voice setting)
- `scripts/ui/tutorial_card.gd`: TutorialCard (card UI, story + objective texts in `_text_for` / `_done_text`, voice player, replay / speaker / minimise buttons, chapter list)
- `tools/tutorial_test.gd`, `tools/tutorial_test.tscn`: headless academy test
- `assets/audio/tutorial_music.mp3` (+ `.import`): Quiet_Orbit
- `assets/audio/voice/tutorial/**`: SOLA lines, `<step id>.mp3` + `.import`
- `assets/ui/icons/voice_on.svg`, `voice_off.svg`, `voice_replay.svg` (+ `.import`)

**Shared:**

- `scripts/ui/top_bar.gd`: only `speed_control` (= `speed_box`) is this feature's; the rest of its diff is planet outposts
- `scripts/save/save_manager.gd`: `new_game(tutorial)` (difficulty OFF, `Tutorial.academy_next`, cover text)
- `scripts/ui/main_menu.gd`: Tutorial button, `--tutorial` screenshot arg
- `scripts/audio_director.gd`: tutorial music player and fade
- `default_bus_layout.tres`: Voice bus, Music compressor sidechained to Voice
- `scripts/audio_settings.gd` (Voice in BUSES), `scripts/ui/volume_sliders.gd` (doc comment)
- `CLAUDE.md`: "## Voice (SOLA)" section and two Run lines; rest of its diff is other work
- `docs/DESIGN.md`: tutorial bullet and Audio section; most of its diff is planet outposts

## Built

**Two modes.** QUICK is the short training card of a normal game; ACADEMY is the full tutorial game started from the main menu. `chapters()`, `steps_of(m)`; step dicts hold id, chapter, build, zone, info. Old saves without "mode" load as QUICK. `scripts/ui/tutorial.gd`

**Chapters.** Command, Mining, Defence, Contracts, Research, Gear, Exploration, Planets, Expansion, Rivals, then done card. Chapter list on the card jumps; a jump grants the research earlier chapters would have given. `jump_to_chapter`, `scripts/ui/tutorial_card.gd`

**Progress checks.** `_check` polls every 0.5 s plus signals; `_is_met(id)` per step. Camera step: pivot moved > 250 m, zoom > 30%, or yaw > `CAMERA_TURN` 30°. Info steps finish with Next. sell_ore and tech_done are flag steps; ore that lands during post_mining and research done during fund carry over (`_ore_in`, `_tech_seen`, kept by `_reset_flags`).

**Voice wait.** A met step latches (`Tutorial.met`) and advances only when `TutorialCard.is_speaking()` is false (voice off or Voice bus muted counts as silent); the player's `finished` signal re-runs `_check`. While waiting the card says "Done. Next step when SOLA finishes, or press Next." (ACCENT) and shows Next. The done card's countdown pauses while its line plays. `scripts/ui/tutorial.gd`, `scripts/ui/tutorial_card.gd`

**Safety.** `_apply_safety`: raids off until the "raid" step, arrivals and gate raids off while running, all restored on finish or quit. `_force_raid` sends one raider via `warn_raid(pick_den(), 1)`. `_top_up` gives a "Training grant" once per chapter (`_topped`, saved).

**Start.** `SaveManager.new_game(true)` (rivals OFF for that game, cover "Starting the tutorial"). `scripts/save/save_manager.gd`, `scripts/ui/main_menu.gd`

**Card.** Title, story (`_body`, what SOLA says), objective (`_goal`, HOLO colour, holds the hotkeys). Buttons: Chapters, Skip step, Skip / Quit tutorial, Next, Got it / Keep playing; top row replay, speaker, minimise. Only build or zone steps open the build bar. Time step pulses `top_bar.speed_control`. `scripts/ui/tutorial_card.gd`

**Station zoom.** Station step calls `show_station()`: focuses the home station, zooming in only if the camera is farther out than the station's framing. `scripts/ui/tutorial.gd`

**Voice.** `_voice` AudioStreamPlayer on bus Voice plays `voice/tutorial/<voice_key()>.mp3` when a step opens; missing file is silent. Speaker toggle saved as [tutorial] voice in `user://settings.cfg` (`voice_on` / `set_voice_on`). Replay button shows only when voice is on and the step has a line, and replays it. All 37 lines done: every step id in `_text_for` plus done and done_quick, in `assets/audio/voice/tutorial/<id>.mp3` (+ `.import`). Seed 33 for all after the first six, except rivals, hire_explorer, hire_salvager (seed 41) and gear_sale (seed 7): their seed 33 takes drifted. Recipe: CLAUDE.md "## Voice (SOLA)".

**Music.** `AudioDirector` fades `tutorial_music.mp3` in (-8 dB, Music bus) while ACADEMY runs, out on quit; Music ducks under Voice (compressor threshold -28, ratio 2.5, sidechain Voice). `scripts/audio_director.gd`, `default_bus_layout.tres`

**Tests.** `Godot --headless --path . res://tools/tutorial_test.tscn`: 40 TUT ok, 0 FAIL on 2026-11-04; on 2026-11-05 all ok again after the camera wait fix (Gotchas), and again later that day after the asteroid cluster change (chapters, jumps, grants, raid gate, save round trip, quit restores raids, music and ducking, voice and replay, station zoom, time step pulse). 2026-11-10: all ok again with the new "a met step waits for its line to end" check; the exit "1 resources still in use" error was there before the change. `tools/smoke.sh` (QUICK card in a normal game) ran clean on 2026-11-05: 0 script errors.

## Gotchas

- **The tutorial test waits for the camera on real time, not frames** (`tools/tutorial_test.gd`, "station step zooms in", at most 3 real s). The camera eases on frame delta; once the sim got cheaper (rival worlds as data, 2026-11-05), 120 headless frames were too short and the check failed at 3,000+ m.

- **ElevenLabs sometimes drifts to another timbre on one take, even with the same seed.** First time.mp3 came out deeper; user heard it at once. In the 2026-11-05 batch, seed 33 gave rivals and hire_explorer a darker, lower take (much less energy above 1 kHz); seed 41 fixed both. Check new takes by ear and with a voiceprint: decode with `afconvert -f WAVE -d LEI16@16000 -c 1` (no ffmpeg on this machine), then median pitch, band energies (80-300, 300-1k, 1k-3k, 3k-8k Hz), spectral centroid, level and chars per second, as an RMS z-score against the accepted lines. Accepted lines scored 0.68 to 1.79 leave-one-out; the two drifted takes 3.00 and 2.19, their remakes 1.03 and 0.47. Scripts live in the session scratchpad (numpy in a venv there), not the repo; the scores are not comparable with the older script's numbers. Better check (2026-11-10): Resemblyzer speaker embeddings (`pip install torch resemblyzer "setuptools<81"` in a scratch venv), cosine to the centroid of the other lines: accepted lines 0.912 to 0.974 (median 0.954); seed 33 hire_salvager and gear_sale scored 0.851 / 0.849, remakes 0.955 / 0.944. A drifted seed 33 take comes back identical when the same seed is asked again, so change the seed.
- **API key lacks `voices_read` and `speech_history_read`.** Cannot list voices or fetch history; use the voice id directly. Key at `~/.config/elevenlabs/api_key`, never print it.
- **A pulse target on a non-build step opens the build bar.** That auto-completed the station step. `bar` is gated on `cur.has("build") or zone`. `scripts/ui/tutorial_card.gd`
- **Tests must not touch user settings.** Backing up `settings.cfg` from the test is blocked; the test sets `Tutorial.write_settings = false`. `tools/tutorial_test.gd`
- **Story text is the audio.** Changing a story line stales its mp3; regenerate it. Hotkeys and numbers live only in the objective line for that reason.
- **User wording rule.** Manager framing: say what the administrator will do, never what they will not ("do not say i dont fly ships"). The scratchpad copy of texts still has the old welcome line; the card file is the truth.
- **New mp3s need an import.** `Godot --headless --path . --import`, or the file does not load.

## Remaining

Deferred by the user on 2026-11-10 ("we can revisit this later"); not blocking.

- **Listen to the lines** (checked only by voiceprint). Most important: the two remade 2026-11-10, `hire_salvager.mp3` and `gear_sale.mp3`, next to `welcome.mp3`. All 37 now match by speaker embedding.
- **Play test the academy by hand** end to end; only the headless test and screenshots have run. Check the voice wait feels right (no line cut off, no long dead wait).

## Open questions

- Should the QUICK card in a normal game speak? (current: build_mining and hire_miner lines also play there)

## Decisions

- **One voice for every SOLA line:** "SOLA - Station AI", voice_id 4ErE58PM2fI5IzqYiWgM, designed from a description (no cloned character voice).
- **Story, not instructions:** the card tells a story; the objective line carries the how-to.
- **Time step text names the action plainly** ("Change the game speed", any speed change or pause completes it) after the user found the first one unclear.

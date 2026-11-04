# Tutorial academy and SOLA voice

| | |
|---|---|
| **Status** | in progress (built and tested; voice lines 11 of 37) |
| **Branch** | main (uncommitted) |
| **Updated** | 2026-11-04 |
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

**Progress checks.** `_check` polls every 0.5 s plus signals; `_is_met(id)` per step. Camera step: pivot moved > 250 m, zoom > 30%, or yaw > `CAMERA_TURN` 30°. Info steps finish with Next.

**Safety.** `_apply_safety`: raids off until the "raid" step, arrivals and gate raids off while running, all restored on finish or quit. `_force_raid` sends one raider via `warn_raid(pick_den(), 1)`. `_top_up` gives a "Training grant" once per chapter (`_topped`, saved).

**Start.** `SaveManager.new_game(true)` (rivals OFF for that game, cover "Starting the tutorial"). `scripts/save/save_manager.gd`, `scripts/ui/main_menu.gd`

**Card.** Title, story (`_body`, what SOLA says), objective (`_goal`, HOLO colour, holds the hotkeys). Buttons: Chapters, Skip step, Skip / Quit tutorial, Next, Got it / Keep playing; top row replay, speaker, minimise. Only build or zone steps open the build bar. Time step pulses `top_bar.speed_control`. `scripts/ui/tutorial_card.gd`

**Station zoom.** Station step calls `show_station()`: focuses the home station, zooming in only if the camera is farther out than the station's framing. `scripts/ui/tutorial.gd`

**Voice.** `_voice` AudioStreamPlayer on bus Voice plays `voice/tutorial/<voice_key()>.mp3` when a step opens; missing file is silent. Speaker toggle saved as [tutorial] voice in `user://settings.cfg` (`voice_on` / `set_voice_on`). Replay button shows only when voice is on and the step has a line, and replays it. Lines done: welcome, camera, time, station, build_mining, hire_miner, post_mining, sell_ore, merc, zone, turret. Recipe: CLAUDE.md "## Voice (SOLA)".

**Music.** `AudioDirector` fades `tutorial_music.mp3` in (-8 dB, Music bus) while ACADEMY runs, out on quit; Music ducks under Voice (compressor threshold -28, ratio 2.5, sidechain Voice). `scripts/audio_director.gd`, `default_bus_layout.tres`

**Tests.** `Godot --headless --path . res://tools/tutorial_test.tscn`: 40 TUT ok, 0 FAIL (chapters, jumps, grants, raid gate, save round trip, quit restores raids, music and ducking, voice and replay, station zoom, time step pulse).

## Gotchas

- **ElevenLabs sometimes drifts to another timbre on one take.** First time.mp3 came out deeper; user heard it at once. Every line after the first six uses `"seed": 33`; check new takes with the voiceprint script (pitch + band energies vs accepted lines; accepted 0.74 to 3.58, the bad take 3.76) and by ear. Script was in the session scratchpad, not the repo.
- **API key lacks `voices_read` and `speech_history_read`.** Cannot list voices or fetch history; use the voice id directly. Key at `~/.config/elevenlabs/api_key`, never print it.
- **A pulse target on a non-build step opens the build bar.** That auto-completed the station step. `bar` is gated on `cur.has("build") or zone`. `scripts/ui/tutorial_card.gd`
- **Tests must not touch user settings.** Backing up `settings.cfg` from the test is blocked; the test sets `Tutorial.write_settings = false`. `tools/tutorial_test.gd`
- **Story text is the audio.** Changing a story line stales its mp3; regenerate it. Hotkeys and numbers live only in the objective line for that reason.
- **User wording rule.** Manager framing: say what the administrator will do, never what they will not ("do not say i dont fly ships"). The scratchpad copy of texts still has the old welcome line; the card file is the truth.
- **New mp3s need an import.** `Godot --headless --path . --import`, or the file does not load.

## Remaining

- **Voice the other 26 lines**, one batch at a time when the user asks: raid, bounty, escort, salvage_yard, hire_salvager, lab, researcher, fund, tech_done, factory, outfitter, gear_sale, jump_nav, explorer_outpost, hire_explorer, explore, map, surface_ops, found_outpost, visit_surface, forward_ops, forward_build, forward_found, rivals, done, done_quick. Text from `_text_for` / `_done_text` story entry; update CLAUDE.md "Done so far".
- **Play test the academy by hand** end to end; only the headless test and screenshots have run.
- **Not run since tutorial edits:** `tools/smoke.sh` (QUICK card path in a normal game).

## Open questions

- Should the QUICK card in a normal game speak? (current: build_mining and hire_miner lines also play there)

## Decisions

- **One voice for every SOLA line:** "SOLA - Station AI", voice_id 4ErE58PM2fI5IzqYiWgM, designed from a description (no cloned character voice).
- **Story, not instructions:** the card tells a story; the objective line carries the how-to.
- **Time step text names the action plainly** ("Change the game speed", any speed change or pause completes it) after the user found the first one unclear.

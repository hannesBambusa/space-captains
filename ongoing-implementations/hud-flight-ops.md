# HUD flight ops redesign

| | |
|---|---|
| **Status** | in progress (look, top, left column, right column built; next the mission timeline) |
| **Branch** | main |
| **Updated** | 2026-11-11 |
| **Scope** | New HUD look and layout "flight ops" (mock C): thin type on the scene, edge shading, mission timeline, action ring. |

Mock: https://claude.ai/artifact/32qYk87knYfsRFDWNcDpJJ (option C). Mock HTML and backdrops in the
session scratchpad only; the published page is the reference.

## Files

**Owned**:

- `scripts/ui/theme/hud_style.gd`, `scripts/ui/theme/hud_theme_builder.gd`, `ui/theme.tres`
- `scripts/ui/edge_shade.gd` (+ `.uid`), `scripts/ui/top_bar.gd`, `scripts/ui/overview_section.gd`
- Deleted: `scripts/ui/contract_strip.gd` (+ `.uid`), last in db35437
- `ongoing-implementations/hud-flight-ops.md`

**Shared**:

- `scripts/screenshot_mode.gd`: `--nohud` (clean frames for mocks); also carries older screenshot work
- `scripts/ui/hud.gd`: EdgeShade added first under `$Root`; also carries the radio chatter and ride-along work (uncommitted, other sessions)
- `scripts/ui/overview_panel.gd`: `SECTIONS` order and titles, doc line; other uncommitted overview work may sit there too
- `scenes/ui/hud.tscn`: Overview `offset_top` 150, Minimap `offset_top` 160 (HUD._layout_right moves it under the research list)
- `scripts/ui/event_feed.gd`, `scripts/ui/minimap.gd`, `scripts/ui/pilot_column.gd`, `scripts/ui/pilot_card.gd`, `scripts/ui/research_list.gd`: flight ops restyle hunks
- `CLAUDE.md`, `docs/DESIGN.md`: "contract strip" mentions replaced by the overview's contracts

## Built

- **Look (phase 1).** Ice-white palette, amber accent, ice-blue secondary, nearly clear panels with
  a top hairline, no brackets or scanlines, Thin/Light Saira weights. `scripts/ui/theme/hud_style.gd`,
  `scripts/ui/theme/hud_theme_builder.gd`, `ui/theme.tres` (regenerated).
- **Edge shading** under every widget (left 560, right 440, bottom 260, top 150 px). `scripts/ui/edge_shade.gd`
- **Top (phase 2).** No bar: crumb row (SYSTEM, HOME, MAP, RIVAL chips), system name 46 px Thin
  (the system menu), summary line (kind, star class, planets, gates); right a dark strip with
  caption, thin value, demand pips and delta row per resource; under it research, `T+ hh:mm:ss`
  and clickable speed steps (pause mark toggles pause). Only controls take the mouse. `scripts/ui/top_bar.gd`
- **Left column (phase 3).** Sections Threats, Contracts, Clusters, then Star, Planets, Stations,
  Gates, Scrap fields, folded by default (`OverviewSection.FOLDED_BY_DEFAULT`, settings keys
  `collapsed` and `opened`); large Light titles over a hairline, no icons. `scripts/ui/overview_section.gd`,
  `scripts/ui/overview_panel.gd`
- **Contract strip gone.** The overview's Contracts section (ContractRow, cancel included) is the
  only contract list. `scripts/ui/hud.gd`
- **Right column.** Research list (title "Research n") at the top under the clock, then the
  minimap (moved down by `HUD._layout_right`), then the pilots. The top bar's research box only
  shows while a lab stands idle. `scripts/ui/hud.gd`, `scripts/ui/top_bar.gd`, `scripts/ui/research_list.gd`
- **Lists on the scene, no boxes:** overview frame and minimap panel clear their fill
  (`overview_panel.gd` `_ready`, `minimap.gd` `_ready`); minimap field 38% dark, no grid,
  brackets or frame, white orbits; event feed rows: dot, mono time, text, no fill
  (`FeedRow` theme style). Reading panels (selection panels, tutorial card) keep `PANEL_BG` 86%.
- **Pilots:** "Pilots" thin title, role icon without badge, thin outlines (2 px, 55%) in
  `HudStyle.outline_labels` and `PilotCard._text`.
- **Checks:** tutorial test exit 0, smoke default and `--forward` 0 errors, screenshots of a
  new game and the tutorial game at 1920x1080 (2026-11-11). Pilot rows and research rows not
  seen with content yet (no pilots or research in a fresh game).

## Gotchas

- **Every panel takes its colours from `HudStyle` constants, not only from the theme.** 41 scripts
  read `H.HOLO`, `H.PANEL_BG` and so on directly, so a palette change lands everywhere at once,
  and a new constant name does not. `scripts/ui/theme/hud_style.gd`
- **The tutorial test must not write user settings.** Default folds live in code
  (`FOLDED_BY_DEFAULT`), never written at load; only a click saves. `scripts/ui/overview_section.gd`
- **The speed readout is `TopBar.speed_control`;** the tutorial's time step pulses it and the
  tutorial test checks that node. Keep the name when moving it. `scripts/ui/top_bar.gd`
- **`ui/theme.tres` is generated.** Edit the builder, then run
  `Godot --headless --path . --script res://scripts/ui/theme/generate_theme.gd`. `scripts/ui/theme/hud_theme_builder.gd`

## Remaining

Order agreed with the user: the look first (restyles every panel), then the layout piece by piece.

1. **Check with content:** pilot rows and research rows in a running game (play test or a save).
   The overview tab row (ALL / SYSTEM / CONTRACTS / THREATS) still has the old two-line look.
2. **Mission timeline** (new, replaces `scripts/ui/event_feed.gd` at the bottom): past events as
   dots on a minute axis, a NOW marker, forecasts after it (next raid from `RaidDirector`, gate
   signals from `ThreatDirector`, Factory and research finish times). Hover for the line, click
   to focus. The full event list stays reachable from a button.
3. **Action ring** (new): 3 to 5 hotkey actions around the selected object (build, post contract,
   hire, zone; per selection type), drawn at the `TargetMarker`. The detail panels stay on the
   right, restyled.
4. **Check the rest:** main menu, pause menu, cluster map, rival panel, `SurfaceHud`, tooltips.
5. **Tests.** Tutorial test (the tutorial card points at HUD controls by node), smoke test,
   screenshots at 1920x1080 and a smaller window.

## Open questions

- None now. The user picked: look first; the timeline replaces the feed and shows forecasts; the
  ring is for quick actions and the panels stay; the left column keeps every section with the
  rest collapsed.

## Decisions

- **Option C (flight ops) over A (tactical glass) and B (command deck).** The user's pick, 2026-11-11.
- **Keep the shipped fonts** (Saira, Saira Condensed, IBM Plex Mono); the new look comes from
  weight, size and spacing, not new faces.

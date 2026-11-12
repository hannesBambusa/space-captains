# Follow cam (ride along)

| | |
|---|---|
| **Status** | built; needs your feel test in a window |
| **Branch** | main (uncommitted) |
| **Updated** | 2026-11-10 |
| **Scope** | Idea 11 of the 2026-11-10 list: a chase camera that rides with one captain, through fights and gate jumps. |

## Files

**Owned:**

- `scripts/ui/ride_along.gd`: RideAlong (banner, chase logic, V and Esc)
- `tools/ride_along_test.gd`, `tools/ride_along_test.tscn`: headless check, optional `-- --shot=/abs/dir` screenshots with a window

**Shared:**

- `scripts/rts_camera.gd`: only `set_pitch` is this feature's
- `scripts/ui/hud.gd`: `ride_along` member and its creation in `_ready`
- `scripts/ui/captain_panel.gd`: the Ride button in the top row and one doc line
- `docs/DESIGN.md`: the "Ride along" bullet in UI

## Built

**Chase camera.** Follows `captain.ship` with `RTSCamera.focus_on`, pitch eased to `CHASE_PITCH` 14 via `RTSCamera.set_pitch`, distance `hit_radius * CHASE_RADII` clamped to the camera's min and `CHASE_MAX` 420. Yaw eases to the ship's nose (`YAW_RATE` 1.8/s); a player orbit drag is kept as an offset. `scripts/ui/ride_along.gd` `_chase`

**Fights.** While `Ship._fight_target` is valid in the same world, yaw faces the target and distance pulls back to `FIGHT_GAP` 1.15 x the gap (max 2,600); back to the calm distance after.

**Captain, not node.** The ship node is freed at each portal. While the ship is data, the view goes to the transit's "to" system (`Sector.transits`, matched by `SaveIds.of(captain)`) or the remote system holding its dict (`RemoteSystemState.ships`), once per place; when the new node appears the camera cuts to it (snap on a new system's camera). Lost captain: holds `LOST_HOLD` 3 s, then stops.

**Start and stop.** V with a player ship selected or the captain panel's Ride button start it; V, Esc (`ui_cancel`, consumed), panning (the camera's `follow_changed` moves off the ship), focusing something else, or the HUD hiding (planet mode) stop it. Banner top centre: captain, personality, `PilotCard.status_text` ("Jumping to Ostra" while in a portal).

**Tests.** `Godot --headless --path . res://tools/ride_along_test.tscn`: 12 RIDE ok on 2026-11-10 (ride at home, pitch and distance, Ostra Gate round trip out and back, pan stops it). Window screenshots checked: chase view behind a docking merc at home, ship centred in Ostra after the switch. `tools/smoke.sh` 0 errors.

## Gotchas

- **A new class needs `Godot --headless --path . --import` before a tool scene can use it.** Without it the test fails with "Could not find type RideAlong".
- **Each system has its own RTSCamera.** `hud.camera` changes on a view switch; RideAlong rebinds `follow_changed` to the new one, or the old camera's signal ends the ride on the next stop_follow.
- **focus_on flies in from wherever the camera was.** Across a system switch that is 20 km+ and takes seconds; `_attach` snaps when the camera changed.

## Remaining

- **Feel test in a window (user):** turn speed, distance, the fight framing, Esc order next to the pause menu.

## Open questions

- None.

## Decisions

- **The ride follows the Captain object, not the Ship node.** The node does not survive a gate jump; the captain does (GateTransit keeps it by save id).
- **Plain follow (double-click) stays as it was.** Ride along is a separate mode, so the RTS follow keeps its top-down view.

# Remote work (mining and bounties in other systems)

| | |
|---|---|
| **Status** | built; needs your play test |
| **Branch** | main (uncommitted) |
| **Updated** | 2026-11-11 |
| **Scope** | Idea 10 of the 2026-11-10 list: captains based at a station take mining and bounty contracts in any charted system without a station, fly there through the gates, work live, come home. |

## Files

**Owned:**

- `scripts/cluster/remote_work.gd`: RemoteWork (held systems, contracts_for, trip_km, post_block)
- `tools/remote_work_test.gd`, `tools/remote_work_test.tscn`

**Shared:**

- `scripts/view_manager.gd`: `remote_work` child
- `scripts/ai/captain_brain.gd`: remote contracts in `_decide`, gate trip in `_take`, `begin_transit` / `takes_ship_back` / `end_transit` keep a remote trip, `remote_trip`, `home_system_id`, `away_from_home`, `_gate_to`, `_gate_home` (miners only) in RETURNING and `_update_flee`
- `scripts/ai/mercenary_brain.gd`: `remote_system`, remote contracts in the decide, `_launch_remote`, transit hooks
- `scripts/ai/miner_evaluator.gd`, `scripts/ai/mercenary_evaluator.gd`: `RemoteWork.trip_km` for remote contracts
- `scripts/save/ship_codec.gd`: `remote_system` in MERC_FIELDS
- `scripts/save/game_snapshot.gd`: held systems saved with the forward parts ("remote_work" flag), loaded and pinned
- `scripts/ui/belt_panel.gd` (remote note, no Escorted, post_block), `scripts/ui/target_panel.gd` (post_block)

## Built

**Held live.** A system with a listed player mining or bounty contract, or a player captain's ship there or jumping there, is pinned (ViewManager.pin) and released 20 real s after both are gone; max 3 systems (a 4th post is refunded; panels show `post_block` first). Pinned station-less systems are adopted after a load. `scripts/cluster/remote_work.gd`

**Miners.** A docked miner at its station sees remote mining contracts (`RemoteWork.contracts_for`), scores the trip as km to the first gate + 22 km per jump + km from the last gate to the cluster, takes it through the gates (`_gate_to`), keeps the trip across the jump, mines live, goes RETURNING and gates home with the load (`_gate_home`), docks and delivers as usual. Fleeing in a remote system means gating home.

**Mercenaries.** Remote bounties (no fleets): `_launch_remote` starts the gate trip with the job kept; at the target `end_transit` enters HUNTING; afterwards RETURNING uses the existing `_gate_home`.

**Save.** Held systems are captured whole (`capture_system`) under "forward" with "remote_work": true; contracts there go into that part; on load the system is pinned and applied with the station parts.

**Tests.** `tools/remote_work_test.tscn` 2026-11-11, all ok run alone: posted in Ostra, held, seen by the docked miner, flown out, mining, saved mid-job and reloaded with the contract and miner, 25 ore delivered home; a bounty on a lone raider in Ostra: the merc flew out, warped across the system, shot it down and came home through the gates.

## Gotchas

- **The test waits on real time at 24x.** Run it alone: with other Godot runs or heavy jobs at the same time even the mining leg times out.
- **A ship is rebuilt from its ShipCodec dict on the far side of a gate when that system is live.** Every brain field a transit needs must be in ShipCodec's field lists (`remote_system` is in MERC_FIELDS); a missing one left the merc parked at the gate ("Holding in Ostra").
- **CaptainBrain is the base of ExplorerBrain and MercenaryBrain.** The new gate-home step in RETURNING and FLEEING is miners only, or it would drop an explorer's survey trip.

## Remaining

- **Overview / pilot list:** remote contracts show in the strip with a system tag; nothing else marks remote work.

## Open questions

- None.

## Decisions

- **Remote systems stay live while there is work** (user picked "any charted system"). Contracts point at live nodes; keeping the system live avoids a data model for remote mining and bounties. Capped at 3 systems for the sim cost. Claude's call.
- **No escorts and no fleets for remote work.** Escort and fleet logic assume one system.

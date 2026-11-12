# Ideas for later

Ideas raised on 2026-11-10 and parked by the user for later. None are agreed design yet; `docs/DESIGN.md` is the agreed design. Picked from the same list and being built now: radio chatter, boss threats, sector modifiers, work in remote systems, follow cam (see `ongoing-implementations/`).

## Things the player does

- **Station powers.** Majesty 2's spells as station abilities with a credit cost and a cooldown: an orbital strike on one raider, overcharging the shield bubble, a tractor beam that drags a fleeing miner to safety, "hazard pay" that raises every contract's pay for 60 s. Fights are mostly waiting today. This gives the player a move without direct control of ships.
- **Bounty on one ship.** Click the raider that killed a captain and put a price on that exact ship. It turns a loss into a revenge story. Builds on BountyContract, which today targets bases and raiders in general.

## Captains as characters

- **Captain requests.** Captains ask for things and the player says yes or no: "Ivo wants a bounty on the corsair that killed his wingman", "Mara wants a raise or she leaves", "the Union Rep calls a strike over losses". Builds on traits, Loyalty and poaching.
- **Memorial and hall of fame.** A wall for dead captains; Legend-rank captains get a named ship and their own paint. Players remember people more than credit totals.

## Events

- **Sector events.** A crystal-rich comet crosses the system for about 10 minutes and the player races pirates and rivals for it; a solar flare drops every shield so ships must dock; an ore price spike or crash at the Factory; a refugee convoy calls for an escort. Reuses contracts, the Factory market and the event feed.

## Goals

- **Charters.** Stage 4 in `docs/DESIGN.md`. Corporate targets with a deadline ("500 titanium by minute 60", "hold a forward station in Kharon"), a reward for meeting one and a budget cut for missing one. Gives a session a shape and a win condition.

## Look

- **A station that grows.** Hull tiers on the home station model that show progress at a glance. Blender work in `blender/` plus a tier switch on HomeStation.

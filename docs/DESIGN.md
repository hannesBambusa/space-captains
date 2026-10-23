# Design

Agreed design. Workers read this before building. Winning and charters come later; the current focus is the player experience.

## Core idea
You are a station administrator. Independent ship captains act on their own. You build structures, hire captains, and post paid contracts. Captains decide for themselves whether a contract is worth it.

## Resources
- Credits: you pay contracts and hires with them. They come back when captains spend money at your buildings (later: Outfitter) and through fees.
- Materials: only from miners delivering ore (and later salvage). Spent on buildings and on unlocking better modules.

## Buildings (near the Home Station, inside the build zone)
- Mining Outpost: hires miners (200 cr). Max 4.
- Mercenary Outpost: hires mercenaries (300 cr). Max 4. 600 cr + 150 materials.
- Later: Outfitter (captains buy modules; upgraded with materials to unlock Mk II/III), Salvage Yard.

## Contracts
- Mining: on a belt, credits per delivered load.
- Bounty: on a scavenger ship or a Scavenger Den, paid on destruction.
- Escort: on a miner (or a mining contract), paid to escorts per completed trip. Like Majesty's protect flag.
- Later: Salvage (on a scrap field), Explore.

## Enemies
- Scavengers: junk raider ships from Scavenger Dens near the richer belts. They hunt miners, steal cargo, and raid near home now and then. Belt danger comes from nearby dens.
- Later: the Swarm, rogue drones.

## Captains
The captain is the person. The ship is the hardware.
- Personality (headline): Bold, Cautious, Greedy, Lazy. It sets the starting attributes.
- Attributes 1 to 10, rolled at hire: Nerve, Greed, Diligence, Piloting, specialty skill (Mining or Gunnery), Loyalty.
- Traits (stage 3), earned from events, 2 to 3 max, some fade: Survivor, Shaken, Crystal Hound, Grudge, Lone Wolf, Union Rep.
- Reputation ranks (stage 3) instead of levels: Rookie, Licensed, Veteran, Ace, Legend. A rank unlocks module slots (2 up to 6) and higher module tiers. It does not add raw stats.
- Ship modules (stage 3), bought by the captain with their own earnings at your Outfitter. Personality decides what they buy. Slots: tool (drill / cannons / missiles), cargo or ammo, defense (armor, shields), engines, sensors.
- Career switching (stage 3): a captain can change role, e.g. a veteran Bold miner becomes a mercenary. They need a new ship; experience and traits carry over, the specialty skill starts low.
- Death: a destroyed ship has an eject chance (Piloting, modules). Ejected captains return without the ship and keep their rank. Otherwise they are gone for good.
- Mercenaries defend the area around home on their own, take bounty and escort contracts by pay and personality, and go home to repair when damaged. Miners flee when attacked.

## Salvage
Destroyed ships (any side) leave scrap fields. Stage 2: scrap fields exist and fade after a while. Stage 3: the salvager role and Salvage contracts; scrap gives materials and sometimes rare parts.

## Stages
1. Contracts, miner AI, mining loop. (done)
2. Mercenary Outpost, mercenaries, scavengers and dens, combat, Bounty and Escort contracts, captain attributes plus the module-slot data model, scrap fields from destroyed ships. (done)
3. Reputation ranks, traits from events, Outfitter and captains buying modules, career switching, salvager role and Salvage contracts, death and ejection. (done)
4. Later: charters (win/lose), the cluster map and more systems.

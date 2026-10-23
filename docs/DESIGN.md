# Design

Agreed design. Workers read this before building. Winning and charters come later; the current focus is the player experience.

## Core idea
You are a station administrator. Independent ship captains act on their own. You build structures, hire captains, and post paid contracts. Captains decide for themselves whether a contract is worth it.

## Resources
- Credits: you pay contracts and hires with them. They come in from selling ore to the Factory, from the station fee share of every payment to a captain (20 to 30%), from the Outfitter's share of module sales (35%) and ship sales, and a small corporate grant (30 cr/min).
- Ore, by type: iron (Cinder Belt), titanium (Talon Reach), crystal (Crystal Veil). Miners deliver the type they mined; salvage is reprocessed at the Salvage Yard into mostly iron, some titanium and a little crystal, which you buy from the yard. Ore pays for buildings (mostly iron, advanced ones some titanium) and Factory tooling, and is what you sell. Rarer ore is worth much more per unit: crystal >> titanium >> iron.
- Credit flow: you pay a miner per load, the load is ore, you sell the ore to the Factory. A fair-pay iron load is slightly profitable, titanium with escorts more so, crystal the most but only with good gear and escorts. Overpaying or losing ships costs you.

## Buildings (near the Home Station, inside the build zone)
- Mining Outpost: hires miners (200 cr). Max 4. 500 cr + 100 iron.
- Mercenary Outpost: hires mercenaries (300 cr). Max 4. 600 cr + 120 iron + 30 titanium.
- Factory: there from the start, linked to the station by a corridor; cannot be built again. It buys your ore and makes the modules captains buy at the Outfitter.
  - Market: one ore stock per type with a target level. Demand (low, normal, high) and the price it is willing to pay rise when its stock is low and fall when it is high, between a floor and a ceiling; open backorders raise demand for the ore they need. The stock drains by production and a steady corporate export, so prices recover.
  - Selling: auto-sell is on from the start. Each ore's ask follows the market by default (95% of what the Factory pays, shown as "auto"); +/- sets it by hand, "=" follows again. You set an asking price per ore type; the closer to (or below) what the Factory pays, the faster it buys (full pace at 80% of its price, nothing past 135%). It never sells below your "keep at least" reserve per type. The panel shows the expected sales rate; the top bar shows each ore with a small demand meter.
  - Production: Mk I from iron, Mk II from titanium plus iron, Mk III from crystal plus titanium, one at a time (40 / 75 / 120 s). Backorders first, then a spread of parts for the roles and ranks you hired. Warehouse of 16 parts. Mk II and Mk III need tooling upgrades (250 iron + 50 titanium, then 200 iron + 400 titanium + 200 crystal) and that ore in the Factory's stock. Rare salvaged parts go into the warehouse and let it make that module early, or discount the next one.
  - The trade-off: sell rare ore for credits now, or let it feed production so captains get better gear and take on more dangerous belts.
- Outfitter (800 cr, 200 iron + 50 titanium, max 1): captains buy the Factory's modules here with their own earnings. Stock is finite. Out of stock: Bold takes another part or backorders, Cautious and Greedy backorder and wait, Lazy takes whatever is there or tries again later. No Outfitter, no module sales.
- Salvage Yard: hires salvagers (250 cr). Max 3. 500 cr + 80 iron + 20 titanium. Runs as a small business: salvagers strip scrap fields on their own (free salvage, no contract needed), the yard pays them 40 cr per load from its own funds (starts with 300 cr; when short it owes the rest and pays debts first from sales), reprocesses 1 scrap per second into ore (75% iron, 20% titanium, 5% crystal; den ruins 60/28/12) and sells it to you at 70% of the Factory's current bid. Auto-buy (on from the start) buys it all while you keep 200 cr. You sell it on to the Factory: the gap is your margin. A posted salvage contract is an optional bonus per load on top of the yard's pay, to draw salvagers to one wreck or make a dangerous one worth it.
- Station complex: every structure except the turrets links to the complex by a short corridor: 20 to 120 m edge to edge (min gap 25 m between footprints), so the station stays compact. Docking lanes stay clear. The Factory sits right next to the station.
- Defense Turret (250 cr + 60 iron + 15 titanium, 15 s, max 8): standalone, no corridor, anywhere in the build zone clear of footprints, corridors and docking lanes (good for perimeter cover; the placement ghost shows its 900 m range). Shoots hostiles within 900 m on its own, raiders and ships attacking the colony first; leads its aim, about half a mercenary's damage per second. Hold-fire toggle. Hull 520 + 120 shields; raiders can destroy it (it leaves scrap and can be rebuilt). The station repairs its hull slowly once it has not been hit for 8 s, and you pay RepairBay's rate less the station's 35% share (about 10 cr per 100 hull).
- Shield Generator (600 cr + 150 iron + 60 titanium, 30 s, max 1): projects a flattened shield bubble over the whole complex (radius fits every linked structure plus 70 m, grows when the complex grows; standalone turrets do not stretch it). Ships fly through it. Hostile shots from outside hit the bubble instead of anything inside; hostiles already inside hit normally; friendly shots pass out. 2400 HP, regenerates 30 HP/s after 5 s without hits; at 0 it collapses and re-raises 45 s later at 40%. The generator (hull 900 + 150 shields) can only be shot while the bubble is down; destroyed, the bubble is gone until it is rebuilt.

## Contracts
- Mining: on a belt, credits per delivered load.
- Bounty: on a scavenger ship or a Scavenger Hideout, paid on destruction.
- Escort: on a miner (or a mining contract), paid to escorts per completed trip. Like Majesty's protect flag.
- Later: Salvage (on a scrap field), Explore.

## Enemies
- Scavengers: junk raider ships from Scavenger Hideouts (bases dug into asteroids) near the richer belts. They hunt miners, steal cargo, and raid near home now and then. Belt danger comes from nearby hideouts.
- Raids: raiders attack the station in order: the shield bubble while it is up (they never chase targets inside it from outside), then the defense turrets, then the shield generator, then ships near home; with nothing left to shoot they loot credits from a structure. They flee home below 35% hull. Tuned so a mid raid (4 raiders) is driven off by 2 turrets and a shield with every mercenary away, and an undefended early colony survives it with 2 mercenaries at home.
- Later: the Swarm, rogue drones.

## Captains
The captain is the person. The ship is the hardware.
- Personality (headline): Bold, Cautious, Greedy, Lazy. It sets the starting attributes.
- Attributes 1 to 10, rolled at hire: Nerve, Greed, Diligence, Piloting, specialty skill (Mining or Gunnery), Loyalty.
- Traits (stage 3), earned from events, 2 to 3 max, some fade: Survivor, Shaken, Crystal Hound, Grudge, Lone Wolf, Union Rep.
- Reputation ranks (stage 3) instead of levels: Rookie, Licensed, Veteran, Ace, Legend. A rank unlocks module slots (2 up to 6) and higher module tiers. It does not add raw stats.
- Ship modules (stage 3), made by the Factory and bought by the captain with their own earnings at your Outfitter. Better defense and engine modules make miners take more dangerous belts (every 3 module tiers there count as one danger level less, at most 2). Personality decides what they buy. Slots: tool (drill / cannons / missiles), cargo or ammo, defense (armor, shields), engines, sensors.
- Career switching (stage 3): a captain can change role, e.g. a veteran Bold miner becomes a mercenary. They need a new ship; experience and traits carry over, the specialty skill starts low.
- Death: a destroyed ship has an eject chance (Piloting, modules). Ejected captains return without the ship and keep their rank. Otherwise they are gone for good.
- Mercenaries defend the area around home on their own, take bounty and escort contracts by pay and personality, and go home to repair when damaged. Miners flee when attacked.
- Repairs: hull never regenerates in space (shields do). Docked, a ship is repaired at a cost per hull point paid from the captain's wallet (a full merc repair is about 55 cr); the station keeps 35% as income. Broke captains repair what they can pay for. After a fight a merc goes home to repair below its personality's level (Cautious at almost any damage, Bold and Greedy later, Lazy early); escorts and fleets finish their job first.
- Attribute Teamwork (1 to 10, personality base +-2; Lone Wolf -3, Union Rep +2). A bounty too strong for one ship (hideouts, groups) makes a merc call a fleet: others join by Teamwork, personality, share, Grudge and distance; it forms up off the station, flies in formation, focuses fire and retreats together; the leader is picked by rank, then Nerve. The bounty is split by rank and damage done, less for those who left early. Lone wolves (high Nerve, low Teamwork) take such bounties alone, keep it all, and die more often.

## Salvage
Destroyed ships (any side) leave scrap fields. Stage 2: scrap fields exist and fade after a while. Stage 3: the salvager role, free salvage paid by the Salvage Yard, optional Salvage contracts as a bonus; scrap is reprocessed into ore the yard sells you, and sometimes gives rare parts.

## Stages
1. Contracts, miner AI, mining loop. (done)
2. Mercenary Outpost, mercenaries, scavengers and hideouts, combat, Bounty and Escort contracts, captain attributes plus the module-slot data model, scrap fields from destroyed ships. (done)
3. Reputation ranks, traits from events, Outfitter and captains buying modules, career switching, salvager role and Salvage contracts, death and ejection. (done)
3b. Factory and typed ore: iron, titanium and crystal; the Factory buys ore at a floating price (asking price, auto-sell, reserve) and makes the modules the Outfitter sells; tooling gates Mk II/III. (done)
4. Later: charters (win/lose), the cluster map and more systems.

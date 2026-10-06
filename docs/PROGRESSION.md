# Goliradile Isle — Progression

Status: **draft for owner review.** Every number is a starting proposal, to be tuned with the
simulation tools (`--balance`, `--defense`, `--bossfight`) and playtests. Decisions it relies
on are in `DECISIONS.md`; the rules are in `DESIGN.md`.

## The ladder

There are **10 tiers**, one per boss. Tier 1 is the start. **Beating boss N unlocks tier N+1.**
The Final boss ends the run, so it unlocks nothing.

Raids at tier N draw from the first N croc types, so players meet a type's minions before they
fight its boss. Boss N is the capstone of tier N.

| Tier | Starts when | Raid croc types | Capstone boss |
|---|---|---|---|
| 1 | New game | green | Green |
| 2 | Green beaten | green, yellow | Yellow |
| 3 | Yellow beaten | + red | Red |
| 4 | Red beaten | + blue | Blue |
| 5 | Blue beaten | + pink | Pink |
| 6 | Pink beaten | + brown | Brown |
| 7 | Brown beaten | + purple | Purple |
| 8 | Purple beaten | + white | White |
| 9 | White beaten | + black | Black |
| 10 | Black beaten | all nine | **Final: the Great Goliradile** |

(Today the game unlocks croc types by night number; the threat anchor in ROADMAP 1.8 replaces
that with tiers.)

## Pacing targets

Day = 7 minutes, ordinary night about 3 minutes (so one day-night cycle is about 7 minutes of
play, with the night inside it). Targets below are **in-game days spent per tier**:

| Difficulty | Days per tier | Time per tier | Whole run (10 tiers) |
|---|---|---|---|
| Easy | about 3 | about 20 minutes | about 3.5 hours (target: one evening) |
| Normal | about 10 | about 70 minutes | about 12 hours |
| Hard | about 25 | about 3 hours | about 30 hours (spread over days) |

The levers are resource scarcity, hunger and thirst pressure, raid growth between bosses and
the cost of the summon components. The numbers are meant to land inside the run-length targets
in `DESIGN.md` (Easy 3–5 h, Normal 10–15 h, Hard 25–40 h).

Player level targets at the moment of each boss (cap 65):

| Boss | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | Final |
|---|---|---|---|---|---|---|---|---|---|---|
| Level | 5 | 12 | 19 | 26 | 33 | 40 | 47 | 54 | 60 | 65 |

## Biomes

| Biome | First needed | Supplies |
|---|---|---|
| **Jungle** (start) | Tier 1 | wood, stone, grass, bamboo, bananas, berries, coconuts, bees, worms, fish, sand (beach and pool) |
| **Rocky highlands** | Tier 3 | metal ore, coal (charcoal), harder stone; deep caves for tier 6–7 ore |
| **Volcano** | Tier 3 (Red) | cinder and obsidian-type materials, heat-resistant plants |
| **Frozen cove** | Tier 4 (Blue) | frost crystal, ice-pool fish, cold-resistant plants |
| **Swamp** | Tier 7 (Purple) | bog resin, toxic plants and fungi, poison-resistant ingredients |

Boss materials are named after the boss ("Red Scale") and come only from that boss. Biome
materials are gathered from the world. Both are needed for a boss set.

## Tier by tier

Each row lists what the tier **adds**. Stations carry forward. Existing structures are placed
in the ladder so nothing already in the game is wasted.

### Tier 1 — Castaway (jungle)
- **Stations:** workbench, campfire.
- **Existing structures:** walls, door, floor, storage, planter, barrel, juicer, spike trap,
  glapple lamp.
- **Towers:** Boxer, Machine Gun.
- **Gear:** stone tool, slingshot, mallet, spear; hide armour.
- **Meals (tier 1):** simple foods from bananas, berries, coconuts and raw fish.
- **Automation:** none.
- **Summon (Green):** Green Lure = hand-made component only (no previous boss).

### Tier 2 — Smith (after Green)
- **Stations:** kiln (charcoal, metal, glass).
- **Existing structures:** kiln, bee enclosure, worm habitat, glass jar.
- **Towers:** Sniper, Adhesive.
- **Gear:** metal tool; **Green set** (from Green boss materials).
- **Meals:** honey and fish dishes.
- **Summon (Yellow):** Green boss drop + a **Wooden Gear** (hand-craft: about 20 minutes of
  gathering; automated later at about one fifth of the cost).

### Tier 3 — Highlander (after Yellow)
- **Stations:** forge (metal parts, better weapons).
- **Towers:** Slicer, Collector.
- **Gear:** metal weapons and armour; **Yellow set**.
- **New areas:** rocky highlands and the volcano become worth visiting.
- **Meals (tier 2 begins):** buffs for speed and gathering.
- **Summon (Red):** Yellow drop + **Metal Bolt**.

### Tier 4 — Furnace (after Red)
- **Stations:** still (berry oil) for fuel and lamps.
- **Existing structures:** still, electric fence, land mine.
- **Towers:** Rocket, Trickster.
- **Gear:** **Red set** (fire resistance).
- **Summon (Blue):** Red drop + **Fuse**.

### Tier 5 — Frostwork (after Blue)
- **Stations:** generator and power grid.
- **Existing structures:** generator, wire, electric bulb, pipe, sprinkler.
- **Towers:** Engineer, Repair tower.
- **Gear:** **Blue set** (cold resistance, control effects).
- **Summon (Pink):** Blue drop + **Circuit**.

### Tier 6 — Foundry (after Pink)
- **Stations:** **assembler** (first automation machine).
- **Automation:** miner, belt, smelter.
- **Existing structures:** aquarium, peel launcher.
- **Towers:** Drill.
- **Gear:** **Pink set** (structure and rebuild bonuses).
- **Meals (tier 3 begins).**
- **Summon (Brown):** Pink drop + **Reinforced Frame** (assembler).

### Tier 7 — Deep Works (after Brown)
- **Automation:** ammo assembler, feeder (supplies towers with fuel or ammo).
- **Towers:** Terrain tower.
- **Gear:** **Brown set** (ground and tunnelling resistance).
- **Biome:** swamp becomes the key area.
- **Summon (Purple):** Brown drop + **Sealed Cell**.

### Tier 8 — Bog Engineer (after Purple)
- **Automation:** larger production chains, power storage.
- **Gear:** **Purple set** (poison resistance).
- **Summon (White):** Purple drop + **Regulator**.

### Tier 9 — Clinic (after White)
- **Gear:** **White set** (support, healing and cleansing).
- **Meals (tier 4 begins):** the strongest meals.
- **Summon (Black):** White drop + **Heart Valve**.

### Tier 10 — Eclipse (after Black)
- **Gear:** **Black set** (revival, darkness).
- **Final preparation:** all four meal tiers, every tower path at its cap, the full factory.
- **Summon (Final):** Black drop + **the Great Lure** (one component of each earlier type,
  assembled at the altar).

## Towers and caps by tier

Towers (see `TOWERS.md`) and the cap on how many may stand at once:

| Tier | New towers | Tower cap | Structural block cap |
|---|---|---|---|
| 1 | Boxer, Machine Gun | 3 | 80 |
| 2 | Sniper, Adhesive | 4 | 120 |
| 3 | Slicer, Collector | 5 | 160 |
| 4 | Rocket, Trickster | 6 | 200 |
| 5 | Engineer, Repair | 7 | 260 |
| 6 | Drill | 8 | 320 |
| 7 | Terrain | 9 | 400 |
| 8 | — | 10 | 480 |
| 9 | — | 11 | 560 |
| 10 | — | 12 | 640 |

The caps are also a performance guard. Each further tower of the same type costs more.

## Crafting stations

Recipes need the right station nearby. The station list above is the order they arrive.
Basic recipes (string, cup, rope, rods, nails, ammo) can be made at the workbench from tier 1.

## Summon components

A boss summon item is made from the **previous boss's drop plus a tier component**. The
component is hand-craftable at about **5× the automated cost, about 20 minutes of
gathering**. Automation (tier 6 onward) makes it cheap. The components are placeholders for
design: Wooden Gear, Metal Bolt, Fuse, Circuit, Reinforced Frame, Sealed Cell, Regulator, Heart
Valve, then the Great Lure.

## What this document does not decide

- Exact recipe costs and material counts (tuned in playtests).
- Names of the biome materials (placeholders above).
- Exact meal lists per tier (in `PLAYER.md`).
- The shape of the three new towers' upgrades (in `TOWERS.md`).

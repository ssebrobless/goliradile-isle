# Goliradile Isle — Design

The reference for *what* we are building. `ROADMAP.md` says *how and in what order*.
When the two disagree, update both in the same PR.

*For William.* (The dedication stays in the game.)

## Vision

A commercial 2D game that is a hybrid of a **tower-defense game** (Bloons TD6: tower
upgrade paths, targeting, escalating rounds) and a **survival-crafting game** (Terraria,
Don't Starve Together, Factorio: gather, build a base, automate, fight bosses).

You are a gorilla on a crocodile-infested island. By day you gather, build and automate.
By night the crocodiles come, and your base, towers and factory have to hold. Recognisable
machines (generators, filters, refineries) are rebuilt out of jungle junk for comic effect.
The run ends when you beat the final boss.

### Pillars
1. **Gather → Automate → Defend → Boss.** Every system feeds the next. A factory exists
   because towers need supplies; towers exist because bosses need answers.
2. **Planning is the game.** Long runs, pausing and quitting anywhere, and nights you can
   prepare for. Pressure comes from what's coming, not from reflex alone.
3. **Readable chaos.** Hordes look like hordes; boss attacks are telegraphed; losses are
   explainable ("my fire defences were weak to the blue boss").
4. **Comedy in the tech.** Junk machines, dry item names, a gorilla who takes it seriously.

### Audience and sales
Public release, sold (target: Steam). **A full 1.0 launch, no Early Access.** Windows, macOS
and Linux; Steam Deck as a stretch goal. Single-player first; co-op after launch (see
Multiplayer). Before 1.0, only closed playtests with invited players.

- **Price: $5.** No demo. Playtest builds go to friends directly, then through Steam Playtest
  once the store page exists. Steam features at launch: **achievements only** (no cloud saves,
  Workshop or leaderboards at launch).
- **After launch:** free updates (fixes, balance, and **co-op as a free update**); no paid DLC
  planned.
- **Mods:** content is data-driven so mods are possible later; no Workshop at launch.
- **Languages:** English at launch, with all text in one place so translations can be added.
- **Telemetry:** local crash logs only, nothing sent automatically.
- Difficulty names stay **Easy, Normal, Hard**.
- **Tone and text:** almost no text beyond item and UI names; the humour comes from names, art
  and animation, not dialogue. There are no boss intro lines or cutscenes.

## Run structure

- A save is created with a **name, a difficulty and a world seed**. Saves are slots; the
  player picks which to resume. Quit-and-resume works at any moment, including mid-night
  and mid-boss.
- Days are **7 minutes** (today's 165 s is placeholder). Beds let the player **sleep to skip
  the rest of the day** (at a hunger cost) so long multi-day runs have no dead time.
- **Rolling autosaves** (the last 3) at every dawn and on quit, plus manual saves any time.
  A bad autosave is never the only copy.
- **5 save slots.**
- The run is won by defeating the **final boss**. There is **no endless mode**. The win plays
  the **credits** (automatically on the first win only; a **Credits** button in the main menu
  replays them any time) and records a Hall of Fame entry. The save is **marked complete and
  stays playable as a free-play sandbox** (no further boss scaling or goals).

### Hall of Fame
A main-menu screen listing every win. It lives in the **player profile, not in a save slot**,
so deleting a save never deletes the record. Each entry stores: date, **difficulty**, **number
of players**, **time taken** (playtime), **final level and perk build**, **gear and tower
roster**, and **boss kill times and deaths**. A base screenshot was considered and dropped.

### Progression order
Bosses are fought in a **fixed order matching the croc unlock order**: Green, Yellow, Red,
Blue, Pink, Brown, Purple, White, Black, then the Final. **One tech tier per boss** (10 tiers):
beating a boss unlocks the next tier of gear, towers, automation and meals.

### Death and game over
A save is **never wiped** by dying. Lives apply per night or boss fight, not per run:
Easy has cheap respawns, Normal costs you part of your inventory, Hard gives few lives and a
lost boss fight costs real progress. A wipe-on-death "Hardcore" mode may be added later.

### Threat scaling
Raid strength is anchored to **progress, not the calendar**: bosses defeated sets the
baseline, plus a small capped creep for days spent since the last boss. Stalling can't make
raids infinite and rushing can't skip the challenge. (Today raids scale with nights survived;
this changes in ROADMAP Phase 1.)

### Difficulties

Every difficulty has the same 10 boss fights and the same content. They differ in how much
preparation each fight demands and how hard the world pushes in between. Numbers below are
starting targets; `data/difficulty` owns the real values.

| | Easy | Normal | Hard |
|---|---|---|---|
| Target run length | one evening (3–5 h) | 10–15 h over several sittings | 25–40 h across days |
| Who it's for | has the controls and mechanics | genre fans | planners who enjoy losing a night |
| Raid size / HP / damage | low | baseline | high |
| Resource regrowth, hunger, thirst | forgiving | baseline | scarce, faster drain |
| Lives | generous | 3 | few; a lost boss fight costs real progress |
| Boss telegraphs | long | baseline | short |
| Active meal buffs (slots) | 5 | 4 | 3 |
| Boss retreat if you stall | yes | yes | yes, but it comes back stronger |

Difficulty is **fixed when the save is created, but can be lowered later** (never raised).

### Player-count scaling (co-op)
Difficulty scales separately by the number of players, so a 4-player Normal is not just
"Normal with more HP". Per additional player: raids grow in number first (capped), then in
toughness; boss health scales by a smaller factor than raid size (as in Terraria's Expert
mode) so fights stay about the same length; resource regrowth rises so the group isn't
starved. Expected run length for co-op: 1–5 days of calendar time. The formulas live in one
place (`data/difficulty`) and are covered by the balance tools.

## Player power

Goal: levels and gear **both** matter. Gear grants named effects; levels unlock and deepen
them, so neither replaces the other. Numbers below are starting proposals for tuning.

- **Role: hybrid.** The player is a strong fighter and the towers hold the base. Boss fights
  need both: towers handle waves and chip damage; the player dodges, bursts and uses
  abilities. Neither can carry a boss alone.
- **Levels 1–65.** Each level grants a **stat point** (the five stats: health, attack, speed,
  armor, regen), each stat capped at **30**, so 65 points fill two stats and part of a third
  and you must choose a shape. A **perk point every 2 levels** (about 32 in total).
  Late power comes from gear and perk depth.
- **Perk tree.** About **48 perks** in **4 branches of about 12** themed by playstyle (Brawler,
  Marksman, Engineer/Commander, Survivalist), so a player buys about two thirds of the tree.
  Any mix is allowed; there are no classes.
- **Gear slots:** weapon, tool, 3 armour pieces, 2 accessories.
- **Gear sources:** tech-tier base gear from your tier of the progression; **boss-themed
  sets** crafted from boss materials, each tied to its croc type (for example the Red set
  resists fire, the Brown set resists being undermined).
- **Attunement (how levels and gear interact).** Each piece of gear has perk slots with named
  effects (for example "Ember"). Player level **unlocks additional slots and raises the rank**
  of the effects, so the gear gives the effect and the level gives the depth: the **2nd slot
  at level 15, the 3rd at level 35, and ranks every 10 levels**. The UI shows which level
  unlocks the next slot or rank.
- **Active abilities.** Two or three abilities with cooldowns, unlocked by level and gear.
  The first two are **Dodge roll** (short dash with brief invulnerability) and **War cry**
  (briefly buffs nearby towers). Other abilities, such as Ground slam and Banana throw
  (a ranged arc that leaves a peel), are reserved for boss sets: each boss set adds one.
- **Tower buffs.** Player perks and gear can buff nearby towers (for example an aura that
  raises fire rate), tying the two halves of the game together. The aura reaches **about
  5 tiles**; buffs from several sources stack up to a cap.
- **XP.** The player earns XP from **all** kills; kills made by towers pay at a reduced rate.
  Bosses and milestones add bonuses. Turrets no longer level.
- **Respec** is free at the workbench or bed, so players can retune for a specific boss.
- **Food buffs.** Cooking grows into a wide set of **cooked meals, each with a unique timed
  buff**, like potions in Terraria (for example fire resistance, regeneration, faster
  gathering, tower-aura range). Meals are how a player prepares for a boss, and they give the
  existing cooking, fish, honey and farming systems a late-game role.
  - About **20 meals across 4 tiers**. Raw ingredients spoil; cooked meals keep.
  - Each buff lasts **5–10 minutes**. The number of meals active at once is **5 on Easy, 4 on
    Normal, 3 on Hard**; eating one more replaces the oldest.
- **Difficulty and player power.** Enemies scale with difficulty; player power (levels, gear,
  perks) is the same everywhere. The one deliberate exception is the number of active meal
  buffs above.

## Core loop systems (existing)

Day gathering and building; night raids; nine crocodile types (green melee, yellow fast,
red fire, blue ice, pink wrecker, brown digger, purple poison, white healer, black
reviver); turrets in three categories; wine and power (generators, wires); farming, bees,
worms, fish, kiln, still; pipes and sprinklers; levels and stat points. See `README.md`.

## Boss fights

**One boss per crocodile type (9) plus a final giant boss = 10.** Each is its own extra-long
night (target 6–10 minutes), inspired by Terraria: telegraphed attacks, distinct phases,
minions, and a boss that reshapes the map.

### Anatomy of a boss night
- **If the player dies mid-fight** they respawn at base and rejoin; the fight resets only when
  lives run out (the boss then retreats).
- **Minions:** up to **60 or more** on screen. That is a performance target (see ROADMAP).
- **Summoned**, not scheduled. The player builds a summoning altar and crafts a summon item
  from the **previous boss's drop plus a component from the automation chain**, so *they*
  choose which night to fight. The component can always be **hand-crafted at high cost**;
  automation makes it cheap, and it is effectively required for the larger bosses. The fight can only be
  **started at dusk**, so players prepare by day (and sleep to dusk when ready). Each boss is
  gated by the tech and the previous boss.
- **Phases** change at health thresholds (e.g. 100/66/33%): new attacks, new minion mix,
  new arena hazards. The boss does a visible, audible phase transition.
- **Escalation clock:** the longer the night runs, the faster minions spawn and the harder
  the boss hits, so stalling is punished and "it gets harder as the night goes on" is real.
- **Minions** are drawn from the boss's crocodile family, spawned in waves by a director.
- **Retreat rule:** if the player is clearly losing (or all lives are gone) the boss
  retreats at dawn and heals; the fight can be re-summoned. A bad night never dead-ends a
  save.
- **Size and movement:** bosses are large (3×3 tiles or more) and ignore tile pathfinding;
  walls slow them by being smashed, not by blocking. The camera may zoom out during fights.
- **Structure damage:** destroyed structures leave **ruins that can be rebuilt at roughly half
  cost**. Terrain effects (fire, ice, flood) revert when the fight ends.
- **Rewards:** drops that unlock the next tier of towers or automation, plus a first-kill
  bonus. Boss kills are recorded in the save.
- Everything is **saveable mid-fight**.

### Roster

| Boss | Signature | How it uses the map |
|---|---|---|
| Green | charging brute, ground slams | slams crack and break walls |
| Yellow | dash with afterimages | skids through bases, trampling traps |
| Red | fire rain, burn | ignites trees, wood walls, berries |
| Blue | freezing waves | freezes the pool into walkable ice; locks structures |
| Pink | demolition | wrecks buildings, hurls rubble |
| Brown | tunnelling | erupts under the base, undermines walls |
| Purple | poison | corrupts grass, kills planters |
| White | heals, shields | shields the boss and minions; cleanses debuffs |
| Black | revives | brings back dead minions; darkens the map |
| **Final: the Great Goliradile** | all of the above, in sequence | floods the island, quakes, burns, freezes; about 6 phases, each themed on one croc type's power, ending in a combined finale |

Map effects are built once as a **terrain-event system** (burn, freeze, flood, quake,
corrupt, darken): events apply a reversible change to tiles, are saved with the game, and
revert on defeat or at dawn. Bosses use the system; they don't edit tiles directly.

## Towers (the Bloons side)

- **Upgrade paths** replace flat stat points: three paths per tower, tiers per path, with a
  cross-path cap so a tower specialises. **Per-turret XP and levels are removed**; kills fund
  upgrades through drops instead.
- **Targeting modes:** first, last, strongest, closest (plus tower-specific modes).
- **Placement limits:** the cap **grows with tech tier** and the cost of each further tower
  rises, instead of the fixed cap of 5, so early game stays tight and spamming one tower is
  expensive.
- **Upgrade currency:** **bones and hides for early tiers, boss materials for top tiers**, so killing
  things funds defence.
- Sell with a partial refund. A tower info panel shows range, targeting and path state.
- **Fast-forward** (2×/3×) during **raids only**; boss fights run at normal speed because their
  telegraphs and phase changes are timed for it.
- **12 tower types at launch:** the 9 existing plus 3 new: a **Repair tower** (heals nearby
  structures and speeds rebuilding ruins), a **Terrain tower** (slow zones, walls or fire
  patches, using the terrain-event system) and a **Collector** (auto-gathers drops and
  trickles resources).
- **Upgrade structure:** 3 paths per tower, **4 tiers per path**, cross-path cap **4/2/0**
  (top out one path, take a second partway, never all three).
- **Supply:** one idea covers fuel and ammo (wine, oil or ammo). It is hand-fed early; the
  automation phase adds feeders that deliver it.

## Automation (the Factorio side — "lite")

Not a full Factorio. Enough that building a supply chain is a real, satisfying puzzle:
- Miners on ore deposits, conveyor belts, smelters and assemblers, and **feeders** that
  deliver ammo and fuel to towers.
- A power grid with capacity and load (generators and wires exist today).
- Quality of life: minimap, copy/paste of a blueprint, clear production/throughput readouts.
- Needs a **bigger map with biomes and ore** (today 50×50; target **160×160**) and chunked
  simulation so the cost doesn't grow with world size. Measured on today's code, the croc
  path rebuild (5.3 ms) and world tick (1.1 ms) would grow about 10× at that size, so they
  must be bounded and chunked first.
- **MVP chain:** miner, belt, smelter, ammo assembler, feeder, power. More machines can come
  after launch.
- **Night clearing** applies only near the base; wild areas keep their trees and rocks.
- **Raids** spawn at the map edge or water and march in along set fronts the player can scout
  and defend.

## Multiplayer (post-launch)

Host-authoritative co-op over Godot's high-level networking, **up to 4 players**. It is not
built until after single-player launch, but **no new system may assume a single player**:
state is per-player (`players` list), enemies target the nearest player, randomness goes
through a seeded service, and **all player actions go through a command queue** (so
single-player uses the same path co-op will). See ROADMAP Phase 0 and Phase 7.

## Art, audio, UX (launch requirements)

- **Art and audio come from open-licensed assets, credited in the game's end credits.** No
  placeholder procedural art in the shipped game. **Tiles stay 16 px**, with richer sprites;
  bosses are drawn as multi-tile 16 px sprites (these will likely need custom or edited
  work, since packs rarely have them).
- Licence policy (full detail in `docs/ASSETS.md` when written): allowed are CC0, CC-BY and
  permissive licences such as MIT/OFL; **not allowed** are non-commercial (NC) and no-
  derivatives (ND) licences, and share-alike (SA) only after a licence check. Every asset
  is recorded in a manifest (source, author, licence, link) from day one, and the end
  credits are generated from it.
- Risk to manage: assets from many artists look inconsistent, so prefer one or two coherent
  16 px packs and edit the rest to match.
- Audio: free open-licensed music and sound effects under the same policy and manifest;
  music is calm by day, tense by night, with unique boss tracks where available.
- Onboarding: a **guided first day** that teaches controls and the loop, then contextual
  hints. With almost no text in the game, the prompts are mostly icons, highlights and arrows.
- Accessibility **must-haves at launch:** rebindable keys, text and UI scaling,
  **colour-blind-safe cues** (every croc type also needs a distinct shape or icon, not just
  a colour), and screen-shake and flash toggles.
- Keyboard and mouse at launch; **controller support comes after launch** (a separate UI
  project, also needed for a verified Steam Deck release).
- Strings are kept in one place so localisation is possible later.

## Technical principles

- Stay on **Godot 4.x / GDScript**. Move hot loops to packed arrays and profile before
  considering anything else.
- **Data-driven definitions** for crocodiles, towers, bosses, difficulties, recipes.
- **Tests gate every PR** (see ROADMAP "Quality gates"). Simulations (`--soak`, `--defense`,
  and later `--bossfight`) back balance decisions with numbers, but only human playtests
  judge feel.
- **Save compatibility:** saves are versioned and migrated; a released save never breaks.
- Original names and gameplay; art and audio are open-licensed and credited (see above).
  "Inspired by" does not mean copied. The name **Goliradile Isle** is kept; a trademark and
  Steam name check is an early task for the owner.

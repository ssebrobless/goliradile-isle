# Decisions log

Choices made for Goliradile Isle, with the implication for the plan. `DESIGN.md` and
`ROADMAP.md` already reflect these; this file is the quick reference and the place for what
is still open. Newest round first.

## Planning docs written after round 10

At the owner's request, three more planning documents were drafted: `ARCHITECTURE.md` (target
code structure, core types, fixed timestep, save v2 layout, large-world design, testing and CI,
migration strategy, and an 18-task Phase 0 breakdown with acceptance tests), `BOSSES.md` (shared
boss rules and a sheet for each of the 10 bosses, plus the `--bossfight` test scenarios) and
`PHASES_1_2.md` (27 PR-sized tasks with tests and two playtest checklists). All are drafts for
review; Phase 0 has **not** been started (owner: more planning first).

## Round 10 (audit of the docs)

| ID | Question | Decision | Implication |
|---|---|---|---|
| V1 | Boss sets need biome materials, but the world came after the bosses | **Build the 160×160 world and biomes right after the boss slice, before player power and the remaining bosses** | New Phase 2a (5a and 5f moved out of Phase 5); Red boss runs on the small map with stand-ins until then |
| V2 | Achievements | About 25: each boss, a win per difficulty, build milestones | 6.6 |
| V3 | Reviewing PR #8 | Owner reads **all seven docs** before merging | I do not merge it; I fix whatever the owner finds |
| V4 | Starting Phase 0 | **Not yet; more planning first** | No code work until the owner says |

## Round 9 (interpretations in PLAYER.md, now confirmed)

| ID | Question | Decision | Implication |
|---|---|---|---|
| A1 | Attunement | Each effect-bearing piece has one effect; the player has attunement slots (1, 2nd at level 15, 3rd at level 35) choosing which are active | 2b.3 |
| A2 | Boss set size | **Five pieces** (three armour, two accessories); the weapon is separate | Per boss: 5 pieces + 1 weapon; set bonus needs no slot |
| A3 | Boss weapons | One per boss; the family rotates through the four branches | Boss 1 melee, 2 ranged, 3 gadget, 4 thrown, repeating |
| A4 | Perk tier unlocks | 0, 3, 6 and 9 points in the branch | 2b.2 |
| A5 | Tower-kill XP | 40% of the player's own-kill XP | 1.9 |
| A6 | War cry | Unlocks at level 8 | 2b.4 |
| A7 | Respawn | At the player's bed, otherwise the workbench | 1.8b |

## Round 8 (boss and co-op details)

| ID | Question | Decision | Implication |
|---|---|---|---|
| X1 | Where a boss fight happens | The boss marches in from a map-edge front toward your altar and base | Fight is base defence; ties to raid fronts (5a) |
| X2 | Boss night cap | **15 minutes** (owner's choice) | Retreat, heal, return stronger; longer than the 12 recommended |
| X3 | Rematches | Re-summon with reduced drops and a one-day cooldown | Also in a completed save |
| X4 | Boss targets | A mix by phase: structures, towers, then the player | Boss attack scripts per phase |
| X5 | Weapons and branches | Each branch favours a weapon family; any weapon works | 2b.1 |
| X6 | UI | Keep the side panels; full-screen menus for inventory, gear, perks, map | New 2b.00 |
| X7 | Friendly fire | None | Phase 7 |
| X8 | Co-op rewards | Own XP per player; shared drops; own boss reward per player | 7.2b |

## Round 7 (rules and world; gaps found by rereading the plan)

| ID | Question | Decision | Implication |
|---|---|---|---|
| W1 | Biomes | Five themed to the bosses: jungle (start), rocky highlands, swamp, frozen cove, volcano | 5f; each boss tier maps to a biome (`PROGRESSION.md`) |
| W2 | Weather | A few events, no seasons | 5f |
| W3 | Daytime threats | Day stays safe | |
| W4 | Night length | **About 40% (about 3 minutes)** (owner's choice, not the recommended 30%) | 1.4; more room for bigger raids, less building time per day |
| W5 | Inventory | Slot-based with stacks and chests | New 2b.0; Phase 0.9 adds an inventory interface first |
| W6 | Build limits | Caps grow with tech tier; a performance guard, not a design limit | 2b.0 |
| W7 | Death penalty | Normal drops about 25% of carried materials at the death spot, recoverable | 1.8b |
| W8 | Lives | Easy 5, Normal 3, Hard 2, per night or boss fight | 1.8b |
| W9 | Crafting | Stations per tier | Station markers of progress; `PROGRESSION.md` |
| W10 | Old saves | Discarded (no migration) | Simplifies 0.6 |
| W11 | Sleeping | Needs a bed; costs about a day's food and water; not during a raid; all players in co-op | 1.8b |
| W12 | Co-op looks | Palette-swapped gorillas with player names | Phase 7 |

## Round 6 (business, scope edges)

| ID | Question | Decision | Implication |
|---|---|---|---|
| S1 | Price | **$5** (owner's choice) | See the notes below |
| S2 | Demo | No demo | No Steam Next Fest; rely on wishlists and trailer |
| S3 | Playtest builds | Direct builds early; Steam Playtest once the store page exists | |
| S4 | Steam features | Achievements only | Cloud saves, Workshop, leaderboards not at launch |
| S5 | Hand-craft cost | About 5× the automated cost, about 20 minutes of gathering | Tune in playtests |
| S6 | Co-op scaling | Raid size first (+60% per extra player, capped), boss HP +35% | Starting numbers for `data/difficulty` |
| S7 | Content lists | Claude drafts `PLAYER.md`; owner reviews and edits | Before Phase 2b |
| S8 | Onboarding | Guided first day, then contextual hints | Icon-driven; the game has almost no text |
| S9 | Tone and text | Almost no text beyond item and UI names | **Replaces** boss intro lines; humour comes from names, art, animation |
| S10 | Languages | English only; strings in one place | |
| S11 | Mods | Data-driven so possible later; no Workshop at launch | |
| S12 | Rights holder | `ssebrobless` for now | `LICENSE` updated; replace with a legal or studio name later |
| S13 | Telemetry | Local crash logs only | No privacy policy complexity |
| S14 | Difficulty names | Easy, Normal, Hard | |
| S15 | Accessibility | All four are must-haves: rebinding, text/UI scaling, colour-blind-safe cues, shake/flash toggles | Croc types need shapes or icons, not only colours |
| S16 | After launch | Free updates, co-op as a free update, no paid DLC planned | Co-op (Phase 7) is post-1.0 |

Notes to keep in view:
- **Price versus scope.** At $5 (roughly $3.50 per sale after Steam's cut, before tax) a game
  with 10 bosses, automation and co-op relies on volume. Price can change at any time before
  launch; the checkpoints are where to reconsider price or scope.
- **No demo, no Early Access.** The store page, trailer and wishlists carry discoverability;
  plan marketing early.
- **Little text** and **a guided tutorial** pull in opposite directions: the tutorial has to
  teach with icons, highlights and arrows.

## Round 5 (progression and endgame)

| ID | Question | Decision | Implication |
|---|---|---|---|
| Q1 | Boss order | Fixed, matching croc unlock order: Green, Yellow, Red, Blue, Pink, Brown, Purple, White, Black, Final | Red is built first as the slice but is the third boss in play |
| Q2 | Tech tiers | One tier per boss (10 tiers) | `PROGRESSION.md` is organised by boss |
| Q3 | Summon items | Previous boss's drop + an automation-chain component | **Dependency:** automation arrives after the bosses |
| Q3b | Resolution | Hand-craftable at high cost; automation makes it cheap (and effectively required for large bosses) | Keeps the phase order; tune the hand-craft cost so it is possible but painful |
| Q4 | 3 new towers | Repair tower, Terrain tower, Collector | `TOWERS.md` (the Lancer was not chosen) |
| Q5 | Upgrade currency | Bones and hides for early tiers, boss materials for top tiers | 3.3 |
| Q6 | After the final boss | Credits, then done. **No endless mode.** Credits play automatically on the first win only, and a menu button replays them | 4.5 |
| Q6b | Hall of Fame | Main-menu screen of every win: difficulty, player count, time taken, final level and perk build, gear and tower roster, boss kill times and deaths (no base screenshot) | Stored in a profile file outside save slots (0.6b) |
| Q7 | Completed save | Marked complete; stays playable as a free-play sandbox | No further boss scaling or goals |
| Q8 | Perk branches | 4 branches of about 12 | 2b.2 |
| Q9 | Co-op size | Up to 4 players | Phase 7 |
| Q10 | Save slots | 5 | 1.1 |

## Round 4 (leftover open items)

| ID | Question | Decision | Implication |
|---|---|---|---|
| F1 | Tower paths | 3 paths × 4 tiers, cross-path cap 4/2/0 | Phase 3.6 |
| F2 | Roster | 12 types (9 existing + 3 new) | Roles go in `TOWERS.md` |
| F3 | Supply | One "supply" idea (wine, oil, ammo): hand-fed early, belts later | 3.9, 5c |
| F4 | Tower limit | Cap grows with tech tier; costs rise per tower | 3.4 |
| E4 | Death during a boss | Respawn at base and rejoin; fight resets only when lives run out | 2.7 |
| E5 | Minion cap | **60 or more** (owner's choice) | Performance work: spatial grid, profiling gate (2.7) |
| E6 | Final boss | About 6 phases, each themed on one croc type, ending combined | Reuses earlier terrain events |
| F5 | Fast-forward | Raids only; bosses at normal speed | 3.5 |
| G1 | Map size | **160×160** (owner's choice) | Works only with 5a: path rebuild, world tick and swaps must be bounded and chunked (measured) |
| G2 | Automation | MVP: miner, belt, smelter, ammo assembler, feeder, power | 5b, 5c |
| G3 | Night clearing | Near the base only; wild areas stay | 5a |
| G4 | Raid routes | Spawn at the map edge or water, march along set fronts | 5a, tower placement |
| I2 | Art | **Open-licensed assets, credited in the end credits** (owner's choice) | Licence policy, manifest from Phase 0.8, credits screen; boss sprites will need custom work |
| I3 | Audio | **Free open-licensed music and sound, credited in the end credits** (owner's choice) | Same manifest and policy |
| I4 | Controller | Keyboard and mouse at launch; controller after launch | Removed from Phase 6 |
| N1 | Name | Keep "Goliradile Isle"; run a trademark and Steam name check now | Owner task |

## Round 3 (open items)

| ID | Question | Decision | Implication |
|---|---|---|---|
| P13 | Perk tree size and rate | ~48 perks; a perk point every 2 levels (~32) | Real choices; free respec is meaningful |
| P14 | Stat cap | 30 per stat | 65 points fill two stats and part of a third |
| P15 | Attunement | 2nd slot at level 15, 3rd at 35, ranks every 10 levels | UI shows the next unlock |
| P16 | First abilities | Dodge roll and War cry; Ground slam and Banana throw reserved for boss sets | 2b.4 builds two abilities first |
| P17 | Buff rules | 5-10 minute buffs; active meals 5 (Easy), 4 (Normal), 3 (Hard); replace oldest | Meal slots are a difficulty setting (see below) |
| P18 | Meals | ~20 meals across 4 tiers; raw ingredients spoil, cooked meals keep | 2b.6 starts the set; grows in Phases 4 and 6 |
| P19 | Tower aura | About 5 tiles; sources stack up to a cap | Stack cap value to tune |
| P20 | Difficulty and player power | Same player power everywhere; enemies scale | **Exception:** meal slots differ by difficulty (P17), deliberately |
| R1 | PR #1 | Closed without a comment | Done |
| R2 | Repo visibility | Keep public until the first public build | See "Open" for the consequence |
| R3 | First release | Full 1.0 only, no Early Access | Plan keeps full scope; playtests are closed/private |
| R4 | Platforms | Windows, macOS, Linux | macOS needs signing and notarisation (Apple developer account) |

## Round 2 (player power)

| ID | Question | Decision | Implication |
|---|---|---|---|
| P1 | Player's combat role | Hybrid: strong fighter, towers hold the base | Boss fights tuned so neither can carry alone |
| P2 | What levels give | Stat points + perk points | Perk tree (2b.2); stats stay as the base |
| P3 | Levels and gear | Attunement: gear has perk slots that levels unlock and strengthen | Core of 2b.3; UI shows next unlock level |
| P4 | Gear slots | Weapon, tool, 3 armour, 2 accessories | 2b.1 |
| P5 | Gear sources | Boss-themed sets from boss materials + tech-tier base gear | Each boss ships a set (4.4); first is Red (2b.7) |
| P6 | Builds | Free-form; perks and gear steer the build | No classes |
| P7 | Active abilities | 2–3 with cooldowns, unlocked by level and gear | 2b.4; each boss set adds one |
| P8 | Player buffs towers | Yes, perks and gear can buff nearby towers | 3.8 |
| P9 | Respec | Free at the workbench or bed | Encourages tuning for each boss |
| P10 | Level cap | **65** (owner's choice) | Stat caps retuned (1.9); per-level pacing designed for 65 |
| P11 | XP source | Player earns XP from all kills, towers at a reduced rate; bosses and milestones add bonuses | Turret XP removed (1.9, 3.1) |
| P12 | Food | Yes: a wide set of cooked meals with unique timed buffs, like Terraria potions (owner's addition) | Buff framework (2b.5), meals (2b.6, grows through 4 and 6); "D2" resolved |

Also: PR #1 (`will-bogusz`) — the fork was only for sharing ideas. Decision: **we proceed with
our own ideas only and push to this repository**; PR #1 will not be merged. Closing it, with a
thank-you note, is the owner's call.

## Round 1 (design review)

| ID | Question | Decision | Implication |
|---|---|---|---|
| B1 | Game over | Never wipe a save; lives per night or boss fight | Death policy per difficulty (Phase 1.8); a Hardcore wipe mode is optional later |
| B2 | Saving | Rolling autosaves (last 3) + manual saves anywhere | Save v2 (Phase 0.6) |
| B3 | Day length | 7-minute days + sleep to skip to dusk | Day length (1.4) and beds (1.7); retune hunger, growth and regrowth |
| B4 | Threat scaling | Bosses defeated + capped day creep | Replaces nights-survived scaling (1.8); balance tools updated |
| C1 | Changing difficulty | Fixed at creation, may be lowered | Save header stores the difficulty |
| D3 | Turret XP | Remove; upgrade paths funded by drops | Phase 3.1 removes XP and migrates old saves |
| E1 | Boss start | Summon at an altar, **at dusk only** | Players prepare by day; sleep-to-dusk (1.7) matters; no mid-day summons |
| E2 | Boss size | Large (3×3+), ignore pathing, smash structures | Separate movement and collision for bosses; camera zoom option |
| E3 | Structure damage | Ruins, rebuild at reduced cost; terrain effects revert | Ruins tile/state in the world and save |
| H1 | Command queue | Yes, adopt in Phase 0 | New task 0.4b; player actions applied by the simulation |
| I1 | Pixel size | Keep 16 px tiles, richer sprites | Bosses are multi-tile 16 px sprites; no art redraw |
| J2 | Team | Just the owner and Claude (see "Open" about PR #1) | Solo process; no contribution rules yet |
| J2b | Licence | Proprietary "All rights reserved" | `LICENSE` added |
| J3 | Pace | Evenings and weekends, no fixed date | Calendar estimate stretches to about 2–3 years; full scope kept (R3) |

## Open

- **Content docs are drafted and awaiting owner review:** `PLAYER.md` (stats, 48 perks, gear
  and attunement, boss sets, abilities, 20 meals), `PROGRESSION.md` (10 tiers, biomes, pacing),
  `TOWERS.md` (12 towers and their upgrade paths), `ASSETS.md` (licence policy, manifest,
  credits). All numbers are starting proposals tuned in playtests. The interpretations that
  were flagged in `PLAYER.md` are now **confirmed** (round 9).
- **Co-op formulas** start from S6 and are finalised in Phase 7.
- **Repository visibility (decided: public until the first public build).** With no Early
  Access, the first public build is the 1.0 launch, possibly years away, so design docs, boss
  ideas and later art and audio will be visible in the meantime, and the proprietary licence
  does not stop people reading them. Revisit before committing art or audio assets or anything
  the owner wants unreleased; making the repo private is a GitHub setting only the owner can
  change.
- **Trademark and Steam name check** for "Goliradile Isle" (owner task, early).
- **Legal or studio name** for the `LICENSE` (placeholder is `ssebrobless`).
- **PR #1** is closed. If anyone other than the owner ever contributes code, a simple
  contributor agreement is needed before a commercial release.
- **Asset sourcing is a risk, not a decision:** open-licensed packs won't cover multi-tile
  bosses or a coherent style by themselves; expect custom work, and licences must be checked
  per asset (no non-commercial or no-derivatives licences).

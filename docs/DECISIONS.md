# Decisions log

Choices made for Goliradile Isle, with the implication for the plan. `DESIGN.md` and
`ROADMAP.md` already reflect these; this file is the quick reference and the place for what
is still open. Newest round first.

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
| J3 | Pace | Evenings and weekends, no fixed date | Calendar estimate stretches to about 2–3 years; favour a smaller first release |

## Open

- **Player power content** (the rules are decided in `DESIGN.md`; the lists are not): the 48
  perks and their branches; the named gear effects and per-rank values; the ~20 meals and
  their buffs; ability numbers (cooldowns, durations); the aura stack cap. These go in
  `PLAYER.md` before Phase 2b, and are tuned by playtest.
- **Repository visibility (decided: public until the first public build).** Consequence to keep
  in mind: with no Early Access, the first public build is the 1.0 launch, possibly years away,
  so design docs, boss ideas and later art and audio will be visible in the meantime, and the
  proprietary licence does not stop people reading them. Revisit before committing art or
  audio assets or anything the owner wants unreleased; making the repo private is a GitHub
  setting only the owner can change.
- **PR #1 (`will-bogusz`).** Resolved above: not merging, owner decides whether to close it. If
  anyone other than the owner ever contributes code, a simple contributor agreement is needed
  before a commercial release.
- **`PROGRESSION.md`** (tiers, boss order, materials) and **`TOWERS.md`** (roles for the 12
  towers, upgrade paths) still to be written; the design questions that blocked them are now
  answered. **`ASSETS.md`** (licence policy and manifest format) is new.
- **Legal name for the `LICENSE`** copyright line (owner to provide).
- **Trademark and Steam name check** for "Goliradile Isle" (owner task, early).
- **Co-op scaling formulas** (Phase 7); **price**; how playtesters get builds (default:
  private builds to invited players); the **hand-craft cost** of summon components. None
  block Phase 0–2.
- **Asset sourcing is a risk, not a decision:** open-licensed packs won't cover multi-tile
  bosses or a coherent style by themselves; expect custom work, and that licences must be
  checked per asset (no non-commercial or no-derivatives licences).
- Remaining items marked in `ROADMAP.md` "Decisions we still need": price and platforms, name
  and trademark, Early Access versus full launch, co-op baseline.

# Decisions log

Choices made for Goliradile Isle, with the implication for the plan. `DESIGN.md` and
`ROADMAP.md` already reflect these; this file is the quick reference and the place for what
is still open. Newest round first.

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

- **Player power details** (the direction is decided; these numbers and lists are not): perk
  tree layout and size; perk-point rate per level; per-stat caps with the cap of 65;
  attunement thresholds (which levels unlock slots and ranks); the ability list; the cooked
  meal list; buff stacking, duration and whether a meal spoils; the aura radius for tower
  buffs; how player power scales with difficulty. These go in `PLAYER.md` before Phase 2b.
- **J1 Repository visibility.** The repo is **public** and has been forked once. For a game that
  will be sold, recommend **private**. Making it private detaches existing public forks, which
  stay public with whatever code they already copied; the proprietary licence applies from now
  on but does not recall earlier copies. Owner to decide, then change the setting on GitHub.
- **PR #1 (`will-bogusz`).** Resolved above: not merging, owner decides whether to close it. If
  anyone other than the owner ever contributes code, a simple contributor agreement is needed
  before a commercial release.
- **`PROGRESSION.md`** (tiers, boss order, materials) and **`TOWERS.md`** (roles, upgrade
  paths) still to be written; D2 blocks part of the first.
- Remaining items marked in `ROADMAP.md` "Decisions we still need": price and platforms, name
  and trademark, Early Access versus full launch, co-op baseline.

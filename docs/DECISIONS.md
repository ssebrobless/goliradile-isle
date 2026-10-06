# Decisions log

Choices made for Goliradile Isle, with the implication for the plan. `DESIGN.md` and
`ROADMAP.md` already reflect these; this file is the quick reference and the place for what
is still open. Newest round first.

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

- **D2 Player power.** Not decided. Direction from the owner: keep levels meaningful by making
  levels and gear interact, with armour and gear granting special effects that levels unlock
  or scale, instead of cutting levels. Needs a follow-up design pass before gear tiers, boss
  rewards (Phase 2/4) and `PROGRESSION.md` are written.
- **J1 Repository visibility.** The repo is **public** and has been forked once. For a game that
  will be sold, recommend **private**. Making it private detaches existing public forks, which
  stay public with whatever code they already copied; the proprietary licence applies from now
  on but does not recall earlier copies. Owner to decide, then change the setting on GitHub.
- **PR #1 (`will-bogusz`, draft, June).** A fork owner's draft PR proposes about 7,000 lines of
  changes, including an AStarGrid2D rework of croc pathing, based on the original commit. It
  overlaps heavily with the croc steering, separation, soak and turret fixes already merged,
  so it cannot merge as is. Needs a decision: close, port selected ideas, or rebase. It also
  raises the team question (J2): if William contributes code, a simple contributor agreement
  is needed before a commercial release.
- **`PROGRESSION.md`** (tiers, boss order, materials) and **`TOWERS.md`** (roles, upgrade
  paths) still to be written; D2 blocks part of the first.
- Remaining items marked in `ROADMAP.md` "Decisions we still need": price and platforms, name
  and trademark, Early Access versus full launch, co-op baseline.

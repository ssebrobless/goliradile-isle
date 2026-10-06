# Goliradile Isle — Execution Roadmap

How we get from today's game to a shippable, sellable v1.0 (and then co-op). Read
`DESIGN.md` first for the *what*.

**Status legend:** `[ ]` not started · `[~]` in progress · `[x]` done.

## Where we are (baseline)

- One 8,900-line `Main.gd` (about 2,000 of those are the in-file selftests); 318 functions;
  50×50 map; a single player assumed everywhere (`_player_pos`, `_health`, croc pathing to
  one cell).
- A single save slot; no difficulty setting; no win condition.
- Procedurally synthesised placeholder audio; 16×16 baked tile art.
- Dev tools already in place: `--selftest`, `--soak`, `--defense`, `--balance`, `--shot`,
  `--drawtime`.
- **No CI.** Selftests are run by hand, and a failing run still exits 0.
- Known: turrets only started working in the last fix, so earlier balance work was tuned
  against ineffective turrets.

## How we work

- One topic per PR, small enough to review. Branch from `main`, PR, merge, repeat.
- Every PR keeps all selftests green and adds tests for what it changes. Bug fixes add a
  test that fails before the fix.
- Balance claims come with simulation numbers; "feels right" comes from a human playtest.
- Each phase ends with a **playtest checkpoint**: a build and a short checklist for the
  owner, whose feedback shapes the next phase. I (Claude) can measure and simulate; I can't
  judge fun.
- Scope changes update `DESIGN.md` and this file in the same PR.

## Quality gates (CI from Phase 0)

A PR may merge only if:
1. `--selftest` reports 0 failures (and exits non-zero otherwise).
2. `--soak` (small fixed seeds): no crocs inside solid terrain; stalled crocs ≤ the recorded
   baseline.
3. `--defense` and, later, `--bossfight`: results inside recorded bands (so a refactor can't
   silently change balance).
4. Performance budgets hold: world redraw and croc/boss update stay inside the per-frame
   budget recorded in the repo (re-baselined deliberately, never silently).
5. A save written by the previous release still loads (once saves are versioned).

## Phases

Effort is order-of-magnitude, in weeks of focused solo work with AI assistance, and only
meant for ordering and expectation-setting. Everything after Phase 2 will be re-estimated
at the checkpoint before it.

### Phase 0 — Foundation (2–3 weeks)
*Goal: make the codebase safe to grow, with no change in behaviour.*

- [ ] **0.1 CI.** GitHub Action that downloads Godot, runs the quality gates, fails the PR.
      Make `--selftest` exit non-zero on failure. Record soak/defense/perf baselines.
- [ ] **0.2 Data tables out of code.** Move croc, turret, structure, recipe and balance
      constants into `data/` (typed GDScript resources or JSON). First step toward
      difficulty and boss definitions.
- [ ] **0.3 Split `Main.gd` incrementally** (strangler pattern, tests green after every
      step), lowest coupling first: audio → sprite baking → save/load → selftests →
      world generation → UI → monsters → turrets → rendering. `Main.gd` ends as glue
      (target under 3,000 lines).
- [ ] **0.4 Players list.** `players: Array[PlayerState]` with a `local_player` accessor.
      Croc targeting picks the nearest player; the flow field becomes a multi-source search.
      Single-player behaviour is identical.
- [ ] **0.4b Command queue.** Player actions (move, place, craft, attack, interact) become
      commands applied by the simulation, so single-player is a local host and co-op later
      adds only networking. Behaviour is unchanged.
- [ ] **0.5 Seeded randomness service.** All gameplay randomness goes through one service
      with per-system streams (needed for tests, boss patterns, and later networking).
- [ ] **0.6b Player profile file** (separate from the 5 save slots): Hall of Fame entries,
      credits-seen flag and settings, so deleting a save never loses them.
- [ ] **0.6 Save v2.** Versioned format (**today's saves are discarded**: no migration, as
      there are no public players yet; later releases migrate); a header
      (name, difficulty, nights, boss progress, playtime, timestamp); multiple slots; **rolling
      autosaves (last 3)** at dawn and on quit; Save & Quit works mid-night.
- [ ] **0.7 Time constants.** Day/night lengths become data, ready for Phase 1 tuning.
- [ ] **0.9 Inventory interface.** All reads and writes of resources and items go through an
      `Inventory` API (has/take/add), so slots and stacks can replace the plain counts in 2b.0
      without touching every recipe and cost check.
- [ ] **0.8 Asset manifest.** `assets/MANIFEST` (source, author, licence, link per asset) and
      the licence policy in `docs/ASSETS.md`; a CI check that every asset file is listed.
      Credits are generated from it later.

*Exit:* CI green; `soak`/`defense` numbers unchanged within tolerance; save v2 round-trips.

### Phase 1 — Run structure and difficulty (1–2 weeks)
*Goal: the shape of a save.*

- [ ] **1.1 New Game flow:** slot (5 slots), name, difficulty, seed; Continue lists slots
      with their headers.
- [ ] **1.2 Pause menu** (Esc): resume, settings, save, save & quit to menu.
- [ ] **1.3 Difficulty data:** the three sets of multipliers (raid size/HP/damage/speed,
      regrowth, hunger/thirst, lives, boss telegraph length) read through one config.
- [ ] **1.4 Day length** raised to **7 minutes**, ordinary nights about **40% (about 3
      minutes)**; re-tune hunger, regrowth and growth timers per day so the economy feels
      right at the new length.
- [ ] **1.5 Balance tooling per difficulty:** `--balance` and `--defense` take a difficulty
      and report the curve; recorded as new baselines.
- [ ] **1.6 Playtime tracking** shown in the slot list.
- [ ] **1.7 Beds / sleep:** sleep to skip to dusk at a hunger cost.
- [ ] **1.9 XP sharing and level cap:** the player earns XP from all kills (tower kills at a
      reduced rate), turret XP removed, level cap 65, stat caps retuned. (Turret levels are
      removed fully in 3.1; this lands the player side early.)
- [ ] **1.8b Lives and death:** lives per night or boss fight (Easy 5, Normal 3, Hard 2),
      reset each; Normal drops about 25% of carried materials at the death spot (recoverable);
      Easy cheaper, Hard harsher; sleeping rules (bed, hunger cost, not during a raid).
- [ ] **1.8 Threat anchor:** raid strength driven by bosses defeated plus capped day creep
      (replaces nights survived); death policy per difficulty (never wipes a save; lives per
      night/boss, inventory loss on Normal); difficulty lowerable after creation.

*Exit / checkpoint A:* owner plays a few days on each difficulty and reports pacing.

### Phase 2 — Boss framework + the first boss (3–4 weeks)
*Goal: one complete, great boss fight; the framework the other nine reuse.*

- [ ] **2.1 Boss framework:** `BossDef` data (health, phases, attacks, minion families,
      escalation curve); phase machine on health thresholds; attack scripts with ground
      telegraphs; wave director for minions; escalation clock; boss health bar and phase
      banners; the boss marches in from a map-edge front toward the altar/base; mix of
      targets by phase; **15-minute cap** with retreat (heal, return stronger); rematches
      with reduced drops and a one-day cooldown; win/lose handling; mid-fight save and load.
- [ ] **2.2 Terrain-event system** (first primitive: burn). Reversible, saved, reverts on
      defeat or dawn. Tests for apply/revert/save round-trip.
- [ ] **2.3 Summoning:** altar structure, summon item (previous boss's drop + an automation-
      chain component, hand-craftable at high cost), tech/previous-boss gating, UI. The
      fight can only be started at dusk. Large (3×3+) boss bodies that ignore pathing and
      smash structures; ruins and rebuild-at-reduced-cost for destroyed structures.
- [ ] **2.4 First boss: Red** (fire). Built first as the slice; in play it is gated as the
      **third** boss (fixed order). Chosen because its map interaction exercises the
      terrain-event system.
- [ ] **2.5 `--bossfight <type> [difficulty] [tower loadout]`** headless simulation, with
      recorded pass bands (e.g. "fresh turrets lose; geared turrets win in N minutes").
- [ ] **2.6 Boss audio/visual cues** (placeholder quality is fine until Phase 6).
- [ ] **2.7 Scale to 60+ minions.** Spatial grid for separation and targeting (separation is
      O(n²) today), cheaper per-croc updates, profiling gate in CI (the `--soak` and
      `--bossfight` tools report per-frame cost at 60+). Dying mid-fight: respawn at base and
      rejoin; the fight resets only when lives run out.

*Exit / checkpoint B (first external playtest):* the Red boss is beatable on Normal at the
intended tech level, readable, and fun; owner signs off the fight structure before we build
nine more.

### Phase 2b — Player power (4–6 weeks)
*Goal: the player is worth playing, and boss gear has somewhere to land.* Runs after the boss
slice so the Red boss can be the first source of a boss set.

- [ ] **2b.00 UI:** keep the side panels; add full-screen menus for inventory, gear, perks and
      map (pausing in single-player).
- [ ] **2b.0 Inventory rework:** slot-based inventory with stacks and storage chests on top of
      the Phase 0.9 inventory interface; crafting stations per tier; build caps that grow
      with tech tier and act as a performance guard.
- [ ] **2b.1 Gear and equipment:** slots (weapon, tool, 3 armour, 2 accessories), equip UI,
      stats from gear; tech-tier base gear; weapon families that branches favour (not lock).
- [ ] **2b.2 Perk tree:** perk points, 4 branches of about 12 (Brawler, Marksman,
      Engineer/Commander, Survivalist), free respec at the workbench or bed.
- [ ] **2b.3 Attunement:** perk slots on gear with named effects; player level unlocks slots
      and raises ranks; UI shows the next unlock.
- [ ] **2b.4 Active abilities:** 2–3 with cooldowns, input, telegraph and sound; unlocked by
      level and gear.
- [ ] **2b.5 Timed buffs framework:** status effects with durations and icons, shared by food,
      perks and gear.
- [ ] **2b.6 Cooked meals:** a first set of meals with unique buffs on the existing cooking
      systems; the full list grows through Phases 4 and 6.
- [ ] **2b.7 First boss set:** the Red set (materials from the Red boss, set effects, one
      ability) as the template for the rest.
- [ ] **2b.8 Balance tooling:** `--bossfight` and `--defense` take a gear/level loadout;
      bands recorded.

*Exit / checkpoint B2:* owner plays the Red boss at two different builds and reports
whether choices feel meaningful.

### Phase 3 — Towers, the Bloons side (3–4 weeks)
*Goal: defence you can think about.*

- [ ] **3.1 Upgrade paths:** three paths per tower with tiers and a cross-path cap, replacing
      flat stat points; costing; **remove per-turret XP and levels**; migration of existing
      turret saves.
- [ ] **3.2 Targeting modes** and a tower info/upgrade panel with range display.
- [ ] **3.3 Upgrade currency:** bones and hides for early tiers, boss materials for top
      tiers.
- [ ] **3.4 Placement limits:** cap grows with tech tier and each further tower costs more,
      instead of the fixed 5; sell and partial refund.
- [ ] **3.5 Fast-forward** (2×/3×) during **raids only**, with the sim stepped safely; boss
      fights stay at normal speed.
- [ ] **3.6 New towers:** 3 new (12 types in total), each with a distinct role against the
      croc and boss roster. Upgrade paths are **3 paths × 4 tiers, cross-path cap 4/2/0**.
- [ ] **3.9 Supply:** one fuel/ammo concept (wine, oil, ammo), hand-fed now; feeders arrive
      in 5c.
- [ ] **3.7 Re-baseline `--defense`** for the new system.
- [ ] **3.8 Player-to-tower buffs:** perks and gear that buff nearby towers (aura range,
      fire rate), tuned with the tower paths.

*Exit / checkpoint C:* owner plays nights 1–15 on Normal and reports whether tower choices
feel meaningful.

### Phase 4 — The remaining bosses and the final boss (6–10 weeks)
*Goal: content-complete bosses.*

- [ ] **4.1 Remaining terrain events:** freeze, flood, quake, corrupt, darken, plus the
      ground-damage and structure-damage variants bosses need.
- [ ] **4.2 Bosses in order of difficulty,** each its own PR with definition, attacks,
      arena effects, tests and `--bossfight` bands:
      Green → Yellow → Pink → Brown → Blue → Purple → White → Black.
- [ ] **4.3 Final boss (the Great Goliradile):** 5–6 phases combining all abilities,
      world-scale hazards (flood, quake, fire, ice), minion director drawing on every
      family; the escalation clock and the retreat rule tuned for the longest fight.
- [ ] **4.4 Boss progression:** fixed order (Green, Yellow, Red, Blue, Pink, Brown, Purple,
      White, Black, Final), one tech tier per boss, rewards, summon items, first-kill bonuses; the
      boss-themed gear set, attunement effects and ability for each boss; its cooked meals.
- [ ] **4.5 Ending:** victory sequence; credits (automatic on the first win only, replayable
      from a main-menu button, with the dedication); **Hall of Fame** screen reading the
      profile file; the won save is marked complete and stays playable as a free-play
      sandbox. No endless mode.
- [ ] **4.6 Balance pass:** all 10 bosses × 3 difficulties, using sims for ranges and
      playtests for feel.

*Exit / checkpoint D:* a full run is possible start to finish on every difficulty.
This is the **Alpha**.

### Phase 5 — Automation and world scale, the Factorio side (8–14 weeks)
*Goal: a base worth building.* The largest and riskiest phase; it is split so each part
ships on its own.

- [ ] **5a World scale (do first).** Map of **160×160** with biomes and ore deposits; chunked
      simulation; spatial indexes; world-gen rework. Measured costs on the 50×50 map that
      would grow about 10×: croc path rebuild 5.3 ms (bound it to a radius and use coarse
      chunk-level routing for long marches), world growth tick 1.1 ms (spread over chunks),
      structure scan 0.12 ms per pink croc (cache it), night/day swap 7 ms (only near the
      base). Night clearing applies only near the base. Raids spawn at the edge or water and
      march in along fronts. Must hold the performance budgets before anything else is built
      on it. Save migration.
- [ ] **5b Production chains:** miners, conveyor belts, smelters/assemblers with recipes,
      item flow and throughput readouts.
- [ ] **5c Supply logistics:** feeders that deliver ammo and fuel to towers; power grid with
      capacity and load; brown-outs.
- [ ] **5d Quality of life:** minimap and map, blueprint copy/paste, search in menus.
- [ ] **5e Rebalance** raids, bosses and economy for the larger world and automation.
- [ ] **5f Biomes and weather:** the five biomes (jungle, rocky highlands, swamp, frozen cove,
      volcano) with their ores and materials, and a few weather events (rain, storm, fog);
      no seasons.

*Exit / checkpoint E:* the owner can run a long Hard save on the larger map with a working
factory; performance budgets hold. This is the **Beta**.

### Phase 6 — Launch content and polish (10–16 weeks, partly outsourced)
*Goal: something strangers will pay for.* Several items run in parallel from earlier phases.

- [ ] **6.1 Onboarding:** guided first day and contextual hints, icon- and highlight-driven
      (the game has almost no text).
- [ ] **6.2 Art:** curate open-licensed 16 px packs (CC0/CC-BY/permissive; no NC/ND), edit them
      into one coherent look, make the multi-tile boss sprites, replace the procedural
      placeholder art; every asset in the manifest.
- [ ] **6.3 Audio:** open-licensed sound effects and music (calm day, tense night, boss
      tracks), under the same policy and manifest.
- [ ] **6.3b Credits:** end-credits screen generated from the manifest (plus the dedication).
- [ ] **6.4 UX and accessibility (all four are launch must-haves):** rebindable keys, text and
      UI scaling, colour-blind-safe cues (a distinct icon or shape per croc type), screen-
      shake and flash toggles; clear settings. (Controller support is post-launch.)
- [ ] **6.5 Localisation-ready strings.**
- [ ] **6.6 Achievements** (the only Steam feature at launch; cloud saves, Workshop and
      leaderboards are not planned for launch).
- [ ] **6.7 Performance and min-spec pass;** local crash and error logs (nothing is sent
      automatically); a Bug Report button that opens the log folder.
- [ ] **6.8 Builds:** Windows, macOS (signed and notarised), Linux; automated release
      pipeline.
- [ ] **6.9 Store and legal:** Steam page (capsule art, trailer, description), EULA/privacy,
      third-party licence audit, trademark check on the name.
- [ ] **6.10 Test rounds:** closed playtests with invited players on private builds; balance
      passes per difficulty from real data. (No public Early Access.)

*Exit:* **1.0 launch** (single-player, no Early Access). Co-op follows in Phase 7. Playtests
before launch are closed: invited players on private builds.

### Phase 7 — Co-op multiplayer (8–12 weeks, after launch)
*Goal: up to 4 players on one island.* Cheap only because Phase 0 removed single-player
assumptions.

- [ ] **7.1 Networking:** host-authoritative simulation over Godot high-level networking;
      snapshot/interpolation for crocs, projectiles and bosses; player prediction.
- [ ] **7.2 Shared world rules:** base ownership and permissions, shared storage, per-player
      inventory, drop-in/drop-out, join-in-progress.
- [ ] **7.2b Co-op rules:** no friendly fire; each player earns their own XP; drops are shared;
      each player gets their own boss reward.
- [ ] **7.3 Scaling:** player-count formulas from `DESIGN.md`, applied to raids, bosses and
      regrowth; balance sims extended with player count.
- [ ] **7.4 Saves:** host saves; joiners see the world's slot header.
- [ ] **7.5 Lobby/invites** (Steam relay), reconnects, latency handling for aiming.
- [ ] **7.6 Test harness:** headless dedicated server plus bot clients for CI.

*Exit:* a 4-player Normal run completes without desync; 1–5 day co-op runs are viable.

## Milestones at a glance

| Milestone | After | What it means |
|---|---|---|
| Foundation | Phase 0 | CI, tests, modular code, players list, save v2 |
| Playable shape | Phase 1 | slots, difficulties, pause/save/quit |
| Boss vertical slice | Phase 2 | one finished boss and the framework |
| Player power | Phase 2b | gear, perks, attunement, abilities, buffs, first boss set |
| Alpha | Phase 4 | all 10 bosses; a run can be won |
| Beta | Phase 5 | automation and the larger world |
| 1.0 launch | Phase 6 | art, audio, tutorial, builds, Steam; no Early Access |
| Co-op | Phase 7 | multiplayer and player scaling |

Rough total to the 1.0 launch: **10–16 months of focused work**. At the stated pace
(**evenings and weekends, roughly 5–10 hours a week**, no fixed date) calendar time is
several times longer, plausibly **2–3 years**. Treat it as a range to plan around, not a
promise; the checkpoints exist to re-plan. The owner chose a full 1.0 with no Early Access,
so the plan keeps full scope; the checkpoints are where scope can still be cut.

## Dependencies

- 0.4 (players list) and 0.5 (seeded RNG) before any boss or tower code, so those aren't
  written twice.
- 2.2 (terrain events) before bosses 4.2/4.3.
- 2b (player power) after 2 and before 4, so every boss ships with its set, ability and
  meals; 2b depends on 0.2 (data tables), 0.4/0.4b (players, commands) and 1.9.
- 5a (world scale) before 5b–5d, and before final art, since the art pipeline depends on the
  map's biome set.
- 1.4 (day length) before economy and balance work, so tuning isn't thrown away.
- 6.x polish items can start earlier as parallel work (e.g. commissioning art during Phase 4).

## Risks

| Risk | Mitigation |
|---|---|
| Scope is very large for one project | Phase checkpoints; Early Access before 1.0; co-op after launch; cut automation depth before cutting bosses |
| GDScript performance on a bigger map | Chunked simulation, packed arrays, perf budgets in CI, profile before optimising |
| Refactor regressions | Strangler split, tests green at every step, soak/defense gates |
| Retrofitting multiplayer | Phase 0.4/0.5 and a "no new single-player assumptions" rule |
| Balance across 3 difficulties × 10 bosses | Data-driven difficulty, sim bands, playtests per checkpoint |
| Art and audio cost and quality | Decide budget and sourcing at Phase 4; keep asset pipeline simple |
| Save compatibility once players have saves | Versioned saves with migrations and a CI check |
| "Fun" can't be simulated | A playtest checkpoint at the end of every phase |
| Legal (name, assets, music) | Trademark check, licence audit, original assets only |
| Burnout | Small PRs, visible progress each phase, scope cuts decided at checkpoints |
| $5 price against a very large scope | Revenue per sale is small (roughly $3.50 after Steam's cut and before tax), so the plan relies on volume and word of mouth; reconsider price or scope at the Phase 4 and 5 checkpoints |
| No Early Access and no demo | Discoverability depends on the store page, trailer and wishlists alone (a demo is also the way into Steam Next Fest); plan marketing early and use Steam Playtest |

## Decisions we still need (with my default)

| Decision | Default |
|---|---|
| Day length | **decided: 7 min**, tuned in Phase 1 |
| Upgrade currency | boss and croc drops (bones, hides, boss materials); turret XP is removed |
| Final map size | **decided: 160×160**, subject to 5a profiling |
| Lives on Hard | **decided:** few, a lost boss fight costs progress; saves are never wiped |
| Co-op baseline | **decided: up to 4 players**; formulas in `data/difficulty` |
| Art direction | **decided:** 16 px tiles, richer sprites, multi-tile bosses |
| Early Access vs full launch | **decided:** full 1.0, no Early Access |
| Price and platforms | **decided:** $5; Windows, macOS, Linux |
| Final name | trademark check before the Steam page |

## Next step

Start **Phase 0.1 (CI)** and **0.2 (data tables)**: both are low-risk, they unblock everything
else, and they give every later PR a safety net.

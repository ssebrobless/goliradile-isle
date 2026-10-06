# Goliradile Isle — Phases 1 and 2: task breakdown

Status: **draft for owner review.** Breaks ROADMAP Phase 1 (run structure and difficulty) and
Phase 2 (boss framework and the first boss) into PR-sized tasks with tests. Architecture
terms (Sim, PlayerState, commands, events, Inventory) are defined in `ARCHITECTURE.md`;
Phase 0 task ids are `P0-xx` there. Phase 2a (world), 2b (player power), 3 (towers) and 4
(remaining bosses) get the same treatment later, once Phase 2 has taught us what we missed.

Size: S about a day or less, M a few days, L about a week or more, in focused work.
**Done when** is what must be true to merge. Every task also keeps the full selftest and the
CI gates green.

## Phase 1 — Run structure and difficulty

*Goal: the shape of a save.* Depends on Phase 0 through at least P0-03 (data tables), P0-07
(events), P0-10 (PlayerState), P0-11 (commands, fixed tick) and P0-12 (save v2).

### P1-01 Difficulty definitions (S, data only)
- **What:** `data/difficulty_defs.gd` with one dictionary per difficulty (Easy, Normal, Hard)
  holding every knob. Starting values:

| Knob | Easy | Normal | Hard |
|---|---|---|---|
| raid size multiplier | 0.7 | 1.0 | 1.4 |
| croc health multiplier | 0.8 | 1.0 | 1.3 |
| croc damage multiplier | 0.7 | 1.0 | 1.3 |
| croc speed multiplier | 0.95 | 1.0 | 1.05 |
| resource regrowth multiplier | 1.5 | 1.0 | 0.6 |
| hunger drain multiplier | 0.7 | 1.0 | 1.3 |
| thirst drain multiplier | 0.7 | 1.0 | 1.3 |
| lives per night or boss fight | 5 | 3 | 2 |
| death drop (share of carried materials) | 10% | 25% | 40% |
| boss telegraph multiplier | 1.5 | 1.0 | 0.6 |
| active meal slots | 5 | 4 | 3 |
| boss health multiplier | 0.8 | 1.0 | 1.25 |
| days per tier (pacing target) | 3 | 10 | 25 |

- **Done when:** a test asserts every difficulty defines every knob; a grep finds no code that
  branches on the difficulty *name*.

### P1-02 Apply difficulty to existing systems (M)
- **What:** raid count, croc stats, regrowth rates, hunger and thirst drain read the active
  difficulty through accessors.
- **Tests:** `--balance --difficulty=<name>` prints per-difficulty tables; unit tests check each
  multiplier changes the right number; Normal output equals today's baseline.
- **Done when:** Normal is unchanged within tolerance; Easy and Hard shift in the stated
  directions.

### P1-03 Save slots, New Game and Continue screens (L)
- **What:** 5 slots; New Game asks for name, difficulty and seed (random by default);
  Continue lists slots from their headers (name, difficulty, in-game day, bosses defeated,
  playtime, completed flag). Delete with confirmation.
- **Depends on:** P0-12.
- **Tests:** create, load and delete a slot; header-only listing doesn't open save bodies; a
  corrupt slot shows as "damaged" without crashing.
- **Done when:** a new save can be made on each difficulty and resumed after restart.

### P1-04 Pause menu and Save & Quit (M)
- **What:** Esc opens a pause menu (resume, settings, save, save and quit to menu); the sim
  halts in single-player. Save & Quit works mid-night and stores everything needed to resume
  exactly.
- **Tests:** save mid-raid, reload, compare the sim state hash; autosave rotation (3) at dawn
  and on quit.
- **Done when:** quitting and resuming mid-night is seamless.

### P1-05 Day length and night length (M)
- **What:** day cycle 7 minutes (data); ordinary night about 40% of the cycle; the dusk
  warning keeps firing about 10 s before night; retune hunger, thirst, growth, regrowth and
  spoilage timers per day so the economy still feels right.
- **Tests:** cycle length and night fraction as data; `--balance` shows hunger and growth
  per day; a headless day simulation checks the player doesn't starve at normal pace.
- **Done when:** a full day plays at the new length with no new shortage of food and water.

### P1-06 Beds and sleeping (M)
- **What:** a Bed structure; a sleep command skips the rest of the day to dusk. Rules: needs a
  bed, costs about a day's worth of food and water, not allowed during a raid, and (co-op
  later) all players in bed. The bed is also the respawn point (else the workbench).
- **Tests:** sleep during day advances to dusk and charges the cost; refused at night and
  during raids; respawn picks the bed, then the workbench.
- **Done when:** the loop "build, gather, sleep to dusk, defend" works.

### P1-07 Lives, death penalty and respawn (M)
- **What:** lives per night or boss fight (from difficulty), reset each; dying drops a share of
  carried materials in a **bag** at the death spot (recoverable); respawn at the bed (else the
  workbench); equipped gear and the base are never lost; running out of lives ends the night
  or retreats the boss, never the save.
- **Tests:** death drops the right share and the bag can be picked up; lives reset at dawn;
  zero lives on Hard ends the encounter, not the save.
- **Done when:** a long run can no longer be lost to dying.

### P1-08 Threat anchor (M)
- **What:** raid strength depends on **tier** (bosses defeated) plus a **capped day creep** since
  the last boss, not on nights survived. The raid pool uses the tier table in `PROGRESSION.md`
  (tier 1 green only, tier 2 adds yellow, and so on). Until bosses exist, a **debug setting**
  advances the tier.
- **Tests:** tier-to-raid table; creep cap; stalling doesn't scale without bound; saving
  stores the tier.
- **Done when:** `--balance` shows the curve by tier and creep, not by night.

### P1-09 XP sharing, level cap, stat caps (M)
- **What:** the player earns XP from **all** kills, tower kills at 40%; turret XP stops being
  awarded (full removal comes with tower paths); level cap 65; stat points cap at 30 per stat;
  per-point stat values from `PLAYER.md`; XP curve tuned to the level targets in
  `PROGRESSION.md`.
- **Tests:** XP split between player and tower kills; cap behaviour; a headless run reaches
  the level target for tier 1.
- **Done when:** levelling is driven by the player, not turrets.

### P1-10 Playtime tracking (S)
- Playtime counted in the sim (not paused time); saved in the header; shown in slots.

### P1-11 Tools per difficulty (S–M)
- `--balance`, `--defense` and `--soak` accept `--difficulty`; baselines recorded per
  difficulty in `ci/baselines.json`.

### P1-12 Playtest checkpoint A
- **Build:** a release build with the slot flow, difficulties, sleeping, lives and new day
  length.
- **Checklist for the owner:**
  1. Make a save on each difficulty. Does Easy feel like an evening game, Hard like planning?
  2. Is a 7-minute day long enough to build, short enough not to drag?
  3. Is a 3-minute night tense or tedious?
  4. Does sleeping to dusk feel useful or like a cheat?
  5. Is dying annoying but fair? Do lives per night make sense?
  6. Quit mid-night and resume. Anything lost?
- **Output:** notes that adjust the difficulty table and timers before Phase 2.

## Phase 2 — Boss framework and the first boss (Red)

*Goal: one finished boss and the framework the other nine reuse.* Depends on Phase 1,
P0-07 (events), P0-10 (PlayerState), P0-11 (fixed tick), P0-17 (performance gates). The Red
boss runs on today's small map with stand-in materials until Phase 2a.

### P2-01 Boss data and entity (M)
- **What:** `data/boss_defs.gd` schema (see `BOSSES.md`) with the Red definition; a `Boss`
  entity: health, size (3×3 or more), position, phase, state; movement that **ignores tile
  pathfinding** and **smashes structures** it touches.
- **Tests:** a 3×3 boss crosses a wall line by destroying it; structure damage values;
  serialisation round trip.
- **Done when:** a placeholder boss walks across the base, breaking things.

### P2-02 Phase machine (S–M)
- **What:** phases at health thresholds; a transition (brief boss invulnerability, event,
  minion burst); each phase lists attacks, minion mix and terrain events.
- **Tests:** every threshold fires once, in order; damage during transition is ignored;
  transitions survive save and load.

### P2-03 Attack system and telegraphs (L)
- **What:** an attack is a state machine: **windup (telegraph) → active → recovery**. Telegraph
  shapes: circle, lane, cone, ring, zone. Hit tests for each; damage to player, towers and
  structures; difficulty telegraph multiplier; icon plus colour coding.
- **Tests:** geometry tests for each shape; telegraph time scales with difficulty; an attack
  can't hit before its windup ends; structure damage applied.
- **Done when:** the Red attacks (fireball volley, fire rain) work with visible telegraphs.

### P2-04 Minion director (M)
- **What:** wave definitions per phase (types, counts, interval), spawned from the boss's
  front; respects the minion cap; escalation hooks.
- **Tests:** waves respect the cap; spawn interval shrinks with escalation; leftover minions
  cleared at the end.

### P2-05 Escalation clock and retreat (M)
- **What:** after the approach, per-minute pressure (minion interval, boss damage, hazards);
  frenzy at 12 minutes; hard cap 15 minutes; retreat state (boss heals, returns stronger on the
  next summon, stored in the save); also retreat when all lives are gone.
- **Tests:** a stalling scenario reaches frenzy and retreat at the right times; "returns
  stronger" persists across save and load.

### P2-06 Boss HUD (M)
- **What:** boss health bar with phase ticks, name, phase banner, escalation timer; shown over
  the world without hiding the action; text kept minimal.
- **Tests:** screenshot test (`--shot --boss`) per phase; HUD updates on events only.

### P2-07 Terrain-event system (L)
- **What:** an event = cells, from → to, time to live, owner; apply reversibly; saved with the
  game; reverts on its own or at dawn or when the fight ends; ruins for destroyed structures.
- **Tests:** apply and revert restore the exact tiles; save mid-event and load; overlapping
  events resolve in order; ruins rebuild at about half cost.

### P2-08 Burn event (M)
- **What:** fire spreads tile by tile (about every 2 s, chance to jump to flammable
  neighbours: wood walls, trees, berries), damages structures, burns out after about 12 s; water
  tiles, sprinklers, stone and Repair towers stop or heal it.
- **Tests:** deterministic spread with a fixed seed; stone and water block it; sprinkler and
  repair interactions.

### P2-09 Altar, summon item and dusk rule (M)
- **What:** altar structure; the summon item recipe (previous boss's drop plus the hand-craft
  component); summoning allowed **only at dusk**; the day clock then runs into a **boss night**;
  the boss's approach starts from its front.
- **Tests:** summon refused by day or without the item; accepted at dusk; the boss spawns at the
  correct front; the night ends at defeat or retreat and returns to dawn.

### P2-10 The Red boss (L)
- **What:** the Cinder Matriarch from `BOSSES.md`: four phases, fireball volley, fire rain,
  ignite and Burn event, minions (red and green), Wildfire and Meltdown phases, drops
  (stand-in materials).
- **Tests:** each phase's attacks and events fire; a scripted scenario with fresh towers
  loses, one with tier-appropriate towers wins.
- **Done when:** it can be fought start to finish.

### P2-11 Boss night flow and saving (M)
- **What:** game-mode states (day, raid night, boss night); mid-fight save and load restores
  boss, phase, minions, events and escalation; autosave rules during a boss.
- **Tests:** save at each phase and resume; quitting mid-fight and returning continues it.

### P2-12 `--bossfight` simulation (M)
- **What:** headless run of a boss against a loadout, difficulty and player count; prints win
  rate, kill time, deaths, losses, peak minions and frame cost; CI compares to recorded bands.
- **Tests:** the Red boss bands (win with the tier loadout, lose with fewer towers or one
  tower type, frenzy and retreat when stalling).

### P2-13 Placeholder cues (S)
- Phase sting, telegraph sound, boss music layer, simple placeholder boss art (boxes plus
  telegraphs). Real art and audio arrive in Phase 6.

### P2-14 Scale to 60+ minions (M–L)
- **What:** spatial hash for crowd separation, targeting and area damage; cheaper per-croc
  updates; performance gate with a 60-minion scenario.
- **Tests:** cost per frame at 60 minions inside the recorded budget; behaviour unchanged at 28.

### P2-15 Playtest checkpoint B
- **Build:** a release build where the owner can build an altar, craft the Red lure and fight
  the boss on the small map.
- **Checklist for the owner:**
  1. Are the telegraphs readable? Could you tell what was about to hit you?
  2. Did the fight feel like base defence, or like a duel?
  3. Did the fire spread feel fair, and did stone, water and Repair help?
  4. Was the fight length right (about 8–11 minutes on Normal)?
  5. Did phases feel different? Did escalation make you hurry?
  6. If you lost, did retreat and return feel fair?
  7. Would you want this structure for the other nine bosses?
- **Output:** go or no-go on the boss structure before nine more are built.

## Order and dependencies

```
P1-01 -> P1-02 -> P1-08 -> P1-09           (difficulty, then threat anchor and XP)
P1-03 -> P1-04 -> P1-10                    (slots, pause, playtime)       needs P0-12
P1-05 -> P1-06 -> P1-07                    (time, sleeping, lives and death)
P1-11, P1-12 last

P2-01 -> P2-02 -> P2-03 -> P2-04 -> P2-05  (entity, phases, attacks, minions, clock)
P2-07 -> P2-08                             (terrain events, burn)
P2-09 -> P2-10 -> P2-11                    (altar, Red boss, flow and saves)
P2-06, P2-13 anytime after P2-02
P2-12 after P2-10;  P2-14 anytime after P0-17;  P2-15 last
```

Total: Phase 1 is 12 tasks (about 1–2 weeks of focused work as estimated), Phase 2 is 15 tasks
(about 3–4 weeks). At the stated pace the calendar time is several times longer.

# Goliradile Isle — Architecture and Phase 0 breakdown

Status: **draft for owner review.** This document says how the code should be organised so
the roadmap (`ROADMAP.md`) can be built without rewriting it twice, and breaks Phase 0 into
reviewable, test-gated tasks. It describes intent; the code does not look like this yet.

## 1. Where the code is today

Measured on `main`:

| Fact | Value |
|---|---|
| Game code | one file, `Main.gd`, about **8,900 lines**, **318 functions**, about **450** constants and top-level variables |
| Of which self-tests | about **1,800 lines** (`_run_selftest`), living inside the same file |
| Dev tools | `--selftest`, `--soak`, `--defense`, `--balance`, `--shot`, `--drawtime` |
| Single-player assumptions | `_player_pos` ×128, `_health` ×64, `_cell` ×182; crocs path to one cell |
| State coupling | `_resources` ×197 and `_inv(` ×195 (inventory), `_terrain` ×218, `_set_terrain` ×159, `_monsters` ×211, `_turrets` ×158 |
| Simulation touching the UI | `_set_msg` ×54, `_refresh_context_panel` ×67, `_update_status` ×21, `queue_redraw` ×24, `_play_sfx` ×17 — all called from game logic |
| Randomness | about 51 call sites of `randf`/`randi`/`shuffle`/`pick_random`, none seeded per system |
| Timing | variable timestep: logic runs with whatever `delta` the frame gives |
| Tests | no CI; a failing `--selftest` still exits 0 |

The code works and is well covered, but four things block the roadmap: simulation and UI are
tangled (no headless boss or co-op testing), the player is a set of globals, the inventory is
a bare dictionary, and the world is a 50×50 constant.

## 2. Principles

1. **Simulation and view are separate.** The simulation (`Sim`) owns all game state and never
   touches a Control, label, sprite or audio player. The renderer, UI and audio read state and
   listen to events.
2. **Commands in, events out.** Anything a player does is a **command** applied by the
   simulation. Anything that happened is an **event** the view subscribes to. Single-player is a
   local host applying its own commands; co-op later adds only the network.
3. **Fixed timestep.** The simulation advances in fixed ticks (proposal: **60 per second**);
   the frame loop accumulates `delta` and runs zero or more ticks. Required for determinism,
   fast-forward (run several ticks per frame), headless simulation and networking.
4. **Seeded randomness per system.** One `Rng` service with named streams (world, spawn,
   loot, combat, boss), seeded from the world seed. Tests and sims can replay a run.
5. **Data-driven definitions.** Crocs, towers, structures, recipes, difficulties, bosses,
   perks, gear and meals are data, not code. GDScript constant dictionaries first; an optional
   JSON overlay later for mods.
6. **One owner per piece of state.** Inventory, terrain grid, players, monsters, towers,
   utilities each live in one class with a small API.
7. **Everything testable headlessly.** A test builds a `Sim` with no scene and steps it.
8. **Size discipline.** No file over about 800 lines; no function over about 80 lines without a
   reason.
9. **Performance is a requirement.** Budgets live in CI (section 9).

## 3. Target layout

```
res://
  Main.tscn, main.gd              thin glue: scene root, app state machine, input -> commands
  scripts/
    core/       sim.gd, rng.gd, commands.gd, events.gd, ids.gd
    data/       croc_defs.gd, tower_defs.gd, structure_defs.gd, recipe_defs.gd,
                item_defs.gd, difficulty_defs.gd, boss_defs.gd, perk_defs.gd,
                gear_defs.gd, meal_defs.gd
    world/      grid.gd (terrain arrays, bounds, index helpers), chunks.gd, world_gen.gd,
                biomes.gd, terrain_events.gd, weather.gd
    entities/   player_state.gd, monsters.gd, monster_ai.gd, pathing.gd, towers.gd,
                projectiles.gd, traps.gd, loot.gd, boss_director.gd, boss_attacks.gd
    systems/    time_of_day.gd, survival.gd, inventory.gd, crafting.gd, building.gd,
                progression.gd (levels, perks, attunement), abilities.gd, meals.gd,
                utilities/ (barrel, juicer, planter, kiln, bees, worms, campfire,
                           aquarium, still, power, water), automation/ (belts, machines)
    save/       save_game.gd, profile.gd, migrations.gd
    render/     world_renderer.gd, sprites.gd, fx.gd, camera_rig.gd
    audio/      audio.gd, music.gd
    ui/         hud.gd, menus.gd, settings.gd, panels/*.gd
    dev/        selftest/*.gd, runner.gd, soak.gd, defense.gd, balance.gd, bossfight.gd,
                shots.gd
  assets/       MANIFEST.csv and asset files (see ASSETS.md)
  ci/           baselines.json, compare.gd
```

### Where today's code goes

| Today (`Main.gd` lines, approx.) | Becomes |
|---|---|
| Constants 28–560 (survival, croc, turret, terrain, structures, recipes) | `data/*.gd` |
| `_ready`, `_process` 811–967 | `main.gd` (frame loop, input routing), `core/sim.gd` (tick) |
| Time, daylight, night/day 968–1142 | `systems/time_of_day.gd`, `world/terrain_events.gd` (clearing) |
| Monsters, spawn, flow field, heal/dig/wreck 1143–1770 | `entities/monsters.gd`, `monster_ai.gd`, `pathing.gd` |
| Player status effects 1771–1816 | `entities/player_state.gd`, `systems/survival.gd` |
| Projectiles 1817–1906 | `entities/projectiles.gd` |
| Turrets and traps 1907–2477 | `entities/towers.gd`, `traps.gd` |
| Persistence and leveling 2478–2688 | `save/`, `systems/progression.gd` |
| Input and building 2689–2972 | `main.gd` (input), `core/commands.gd`, `systems/building.gd` |
| Audio 2973–3158 | `audio/audio.gd`, `music.gd` |
| Movement, interact, harvest, eat, loot, inventory helpers 3159–3748 | `entities/player_state.gd`, `systems/*.gd`, `inventory.gd`, `loot.gd` |
| Storage and utilities 3749–4377 | `systems/utilities/*.gd`, `inventory.gd` |
| World data and grid helpers 4378–4530 | `world/grid.gd`, `world_gen.gd` |
| UI panels, menus, save/load 4531–5876 | `ui/*.gd`, `save/save_game.gd` |
| Drawing 5877–6293 | `render/world_renderer.gd` |
| Sprite baking 6294–6760 | `render/sprites.gd` |
| Self-tests and dev tools 6761–8935 | `dev/*.gd` |

## 4. Core types (sketches)

These are interfaces to aim for, not final code.

```gdscript
# core/sim.gd — owns all game state; no UI access
class_name Sim extends RefCounted
var grid: Grid
var players: Array[PlayerState]
var monsters: Monsters
var towers: Towers
var rng: Rng
var events: Events
var time: TimeOfDay
func tick(dt: float) -> void                  # fixed step
func apply(player_id: int, cmd: Command) -> void
func serialize() -> Dictionary
static func deserialize(d: Dictionary) -> Sim

# core/commands.gd — what a player can ask for
class_name Command extends RefCounted
enum Kind { MOVE, AIM, ATTACK, INTERACT, BUILD, REMOVE, CRAFT, EQUIP, EAT, DRINK,
            USE_ABILITY, TRANSFER, SLEEP, SELECT_PERK, ATTUNE, RESPEC, SET_TARGETING, ... }
var kind: Kind
var args: Dictionary

# core/events.gd — what happened (signals the view listens to)
signal message(text: String)
signal damaged(who, amount: float)
signal killed(monster)
signal built(cell: Vector2i, structure: StringName)
signal phase_changed(boss, phase: int)
signal sfx(name: StringName, volume: float)
signal state_dirty(what: StringName)           # panels refresh; replaces direct UI calls

# systems/inventory.gd — same counts today, slots later
class_name Inventory extends RefCounted
func count(id: StringName) -> int
func add(id: StringName, n: int = 1) -> int    # returns how many fit
func take(id: StringName, n: int = 1) -> bool
func can_afford(cost: Dictionary) -> bool
func spend(cost: Dictionary) -> bool
func refund(cost: Dictionary) -> void
func to_dict() -> Dictionary
func from_dict(d: Dictionary) -> void

# world/grid.gd — terrain arrays behind an API; size is a parameter, not a constant
class_name Grid extends RefCounted
var size: Vector2i
func terrain_at(c: Vector2i) -> int
func set_terrain(c: Vector2i, t: int) -> void
func in_bounds(c: Vector2i) -> bool
func index(c: Vector2i) -> int
func chunk_of(c: Vector2i) -> Vector2i
```

### Player state

Everything per-player moves into `PlayerState`: position, knockback, facing, health, energy,
hydration, lives, level, XP, stat and perk allocation, equipment, active meals and buffs,
abilities and cooldowns, inventory, punch/attack state, status effects (burn, slow, freeze,
snow counters), invulnerability timer, attunement. World-level state stays in `Sim`: time,
day, bosses defeated, terrain, monsters, towers, utilities, storage.

`Sim.players` is an array; `Sim.lp` (the local player) is an accessor for single-player code
paths. Monsters pick the **nearest player** as their target; the path field becomes a
**multi-source** search from all players.

## 5. Fixed timestep and determinism

- `main.gd` accumulates `delta` and calls `sim.tick(1.0/60.0)` while the accumulator allows,
  capped (for example at 5 ticks per frame) to avoid a spiral of death.
- **Fast-forward** (2×/3×) means running 2 or 3 ticks per frame, which is why it is limited to
  raids: tick cost must stay inside the budget.
- Hit-stop and screen-shake are **view effects**, not simulation: they pause or offset
  presentation, not the tick.
- All randomness goes through `Rng`; tick order is fixed; floating-point use stays inside one
  engine build, which is sufficient for host-authoritative co-op (clients are not required to
  predict exactly).

## 6. Data definitions

- **Now:** each definition set is a GDScript file with a `const` dictionary and a small typed
  accessor, for example `CrocDefs.get(type) -> Dictionary`. Zero risk, fast, easy to test.
- **Later (mods, S11):** a loader that merges JSON files over the built-in dictionaries. Nothing
  else changes because all code reads definitions through the accessors.
- Difficulty is a definition set (`difficulty_defs.gd`): one dictionary per difficulty with
  every multiplier and limit; code never branches on the difficulty name.

## 7. Saves

- **Location:** `user://saves/slot_N/` for 5 slots, each with `auto_1..3.save`, `manual.save`
  and a small `header.json` so the slot list loads without opening a full save.
- **Header:** name, difficulty, seed, bosses defeated, in-game day, playtime, player count,
  save version, game version, timestamp, a completed flag.
- **Body:** `{ version, header, world: {...}, players: [...], systems: {...} }`, written to a
  temporary file and renamed (so a crash can't leave a half-written save), with a checksum.
- **Versioning:** `migrations.gd` is a list of `vN -> vN+1` functions. The first release has
  no migration from today's saves (they are discarded, DECISIONS W10); every later release
  must migrate.
- **Profile:** `user://profile.json` holds Hall of Fame entries, credits-seen flag and settings,
  independent of slots.

## 7b. Terrain events and ruins

Bosses and the night-clearing mechanic change tiles through one **terrain-event system**:
an event records `(cells, from, to, ttl)`, applies reversibly, saves with the game and
reverts on its own or at dawn. Ruins are a terrain state (`RUIN` with the structure it
replaced) so a rebuild at reduced cost is a normal build command.

## 8. Large worlds (160×160)

Measured on the 50×50 map: path-field rebuild 5.3 ms, world tick 1.1 ms, night/day swap 7 ms,
structure scan 0.12 ms per call. All of these grow about 10× at 160×160, so:

- **Chunks:** 16×16 tiles (a 10×10 grid of chunks). Growth, regrowth, weather and fluid
  updates run a few chunks per tick, not the whole map.
- **Bounded pathing:** the local flow field covers a radius around each player (about 40
  tiles); long marches use a **coarse chunk-level route** (a small graph) that feeds the local
  field.
- **Spatial hash** (2-tile cells) for monsters and projectiles: crowd separation, targeting and
  area damage query neighbours instead of scanning all (needed for 60+ minions).
- **Cached structure lists** instead of scanning every tile per query.
- **Night clearing** touches only chunks near the base.
- **Rendering** already draws only on-screen cells; add chunk-level dirty flags for any cached
  layers.

## 9. Testing and CI

- **Runner:** `dev/runner.gd` discovers test groups (`dev/selftest/*.gd`), runs them against a
  headless `Sim`, prints a summary and **exits non-zero on failure**. Groups map to systems:
  world, monsters, towers, player, inventory, building, utilities, saves, progression, audio
  helpers, rendering helpers.
- **Headless harness:** builds a `Sim` from a seed and a scenario (base layout, towers, player
  loadout) with no scene tree, used by `--soak`, `--defense`, `--balance` and, later,
  `--bossfight`.
- **CI** (GitHub Actions): pinned Godot 4.6, runs the runner, then the tools with small fixed
  seeds, then compares to `ci/baselines.json`.
- **Gates** (also in ROADMAP): selftest 0 failures; no crocs in solid terrain; stalled crocs ≤
  baseline; `--defense` and `--bossfight` inside recorded bands; frame-cost budgets (world
  redraw, croc update, path rebuild) inside recorded limits; every asset in the manifest.
- **Budgets** are recorded numbers, re-baselined deliberately in a PR that says why.

## 10. Migration strategy (how Phase 0 changes code safely)

The rule: **no behaviour change in a refactor PR.** Each step moves code, the whole test suite
passes before and after, and the tool outputs (soak, defense, balance) match their baselines.

- **Strangler pattern.** Extract a module, leave a **thin forwarding method** in `Main.gd`
  (a shim) so existing call sites and tests keep working, then migrate callers and delete the
  shim. Shims are listed in the PR description.
- **Lowest coupling first:** audio, sprite baking, data tables, then save/load, then world gen,
  utilities, monsters, turrets, UI.
- **Do the cross-cutting changes in a fixed order:** (1) RNG service, (2) events replacing UI
  calls inside game logic, (3) grid wrapper, (4) inventory interface, (5) PlayerState, (6)
  fixed tick and command queue. Each is mechanical but touches hundreds of sites, so each
  gets its own PR and its own tests.
- **Mechanical edits are scripted** (search-and-replace with a review of the diff) rather than
  hand-edited, and verified by the unchanged selftest plus a grep that no old names remain.
- **Keep the build runnable at every commit** so any step can be reviewed or reverted alone.

## 11. Phase 0 task breakdown

**Progress:** P0-01 (CI skeleton) and P0-02 (baselines) are done. CI runs `ci/run_checks.sh`:
selftest, the balance table (exact), soak (bands) and defense (bands); performance gates for
draw and path costs arrive with P0-17.

Size: S about a day or less, M a few days, L about a week or more, in focused work. Each task
is one PR (large ones several). **Acceptance** is what must be true to merge.

| ID | Task | Size | Acceptance |
|---|---|---|---|
| P0-01 | **CI skeleton.** GitHub Action with a pinned Godot download and cache; `--selftest` returns a non-zero exit code on any failure; a README badge. | S | A PR with a deliberately failing test turns CI red; a clean PR is green. |
| P0-02 | **Baselines.** Record `--soak`, `--defense`, `--balance`, draw/update costs into `ci/baselines.json`; a compare script with bands. | S–M | CI fails if a number leaves its band; passes on `main`. |
| P0-03 | **Data tables out of code.** Move croc, tower, structure, recipe, weapon, tool, drink and balance constants to `scripts/data/`. | M | No behaviour change: selftest and baselines identical. |
| P0-04 | **Audio extraction.** `Audio` and `Music` classes with the current synthesis; events drive playback. | S | Existing audio tests pass; startup and quit are clean. |
| P0-05 | **Sprite baking extraction.** `Sprites` class; `render/` gets textures from it. | S–M | Screenshots (`--shot`) pixel-identical before and after. |
| P0-06 | **Rng service.** Named streams seeded from the world seed; replace the ~51 random call sites. | M | Two runs from the same seed produce identical `--soak` output; a test asserts it. |
| P0-07 | **Events replace UI calls in logic.** The ~54/67/21/24/17 calls to message, panel refresh, status, redraw and sfx from game logic become events; UI subscribes. | L | A `Sim` runs with no UI nodes; selftest unchanged; no `Control` access from `scripts/core`, `entities`, `systems`. |
| P0-08 | **Grid wrapper.** `Grid` class owns terrain arrays and helpers; size is a parameter. | M | Selftest identical; a test builds a 160×160 `Grid` and exercises it. |
| P0-09 | **Inventory interface.** `Inventory` with count, add, take, can_afford, spend, refund; all ~390 uses of `_resources` and `_inv(` go through it; storage boxes too. | M–L | No behaviour change; a grep finds no direct `_resources[...]` writes outside `Inventory`. |
| P0-10 | **PlayerState and players list.** Per-player globals move to `PlayerState`; `Sim.lp` accessor; croc targeting picks the nearest player; multi-source path field. | L | Single-player behaviour identical; a test with two players checks targeting and pathing. |
| P0-11 | **Fixed tick and command queue.** `Sim.tick(1/60)`, accumulator in `main.gd`, commands for every player action, input layer translates keys and clicks to commands. | L | Selftest and tools pass at a fixed tick; a test replays a command list and gets the same state; fast-forward test (3 ticks per frame). |
| P0-12 | **Save v2 and profile.** Slots, headers, rolling autosaves, atomic writes, checksum, migrations list, profile file. | L | Round-trip tests for save/load at night, dawn and with towers; corrupt-file test; slot list from headers only. |
| P0-13 | **Split self-tests.** Move the ~1,800 test lines into `dev/selftest/` groups with a runner and a headless harness. | M | Same assertions pass; CI runs the runner; runtime not worse than today. |
| P0-14 | **Split the remaining systems:** world generation, utilities, monsters and pathing, towers and traps, projectiles, UI panels, renderer, input. Several PRs, one per area. | L total | Each PR: no behaviour change; `Main.gd` shrinks toward glue (under about 3,000 lines at the end). |
| P0-15 | **Time constants as data** (day, night, dusk warning, autosave interval). | S | `--balance` output unchanged. |
| P0-16 | **Asset manifest and CI check** (`assets/MANIFEST.csv`, ASSETS.md rules). | S | CI fails on an unlisted asset or a disallowed licence. |
| P0-17 | **Performance gates in CI.** Draw time, croc update, path rebuild with a 60-croc scenario; thresholds recorded. | M | CI fails if a budget is exceeded; documented procedure to re-baseline. |
| P0-18 | **Repo guide.** A `CLAUDE.md`/`CONTRIBUTING` file with dev commands, conventions, folder map, how to run tests and tools. | S | A new contributor (or session) can run everything from it. |

### Recommended order

1. **P0-01, P0-02** (CI and baselines): from here every change is checked.
2. **P0-03, P0-04, P0-05** (low-risk extractions) and **P0-15, P0-16**.
3. **P0-06** (RNG), then **P0-07** (events), then **P0-08** (grid), **P0-09** (inventory).
4. **P0-10** (players), then **P0-11** (fixed tick and commands).
5. **P0-13** (tests split) alongside, then **P0-12** (save v2), then **P0-14** (remaining splits).
6. **P0-17, P0-18** to close.

**Exit criteria for Phase 0** (as in ROADMAP): CI green; `soak`/`defense`/`balance` numbers
unchanged within tolerance; save v2 round-trips; `Main.gd` is glue.

## 12. Conventions

- GDScript with `class_name` for each module, typed variables and signatures, `StringName` ids
  for items, towers and structures.
- Signals and events named in the past tense (`killed`, `built`), commands in the imperative.
- No `get_node` or UI references from `scripts/core`, `entities`, `systems`, `world`, `save`.
- Every system exposes a small public API; internals prefixed with an underscore.
- Every new system lands with tests in its `dev/selftest/` group.
- Numbers that affect balance live in `data/`, not inline.
- Commit messages explain why; PRs describe testing and anything not tested.

## 13. Technical defaults (confirmed by the owner unless marked)

| Question | Decision |
|---|---|
| Fixed tick rate | **60 Hz (confirmed)** |
| Language for hot loops | **stay in GDScript (confirmed)**: packed arrays, profile first; revisit (GDExtension or C#) only if budgets fail |
| Save body encoding | **confirmed:** Godot `var_to_bytes` with a version and checksum (compact, native types); JSON only for headers and profile so they are inspectable |
| Chunk size | 16×16 (default, tune in 2a) |
| Spatial hash cell size | 2 tiles (default, tune in 2a) |
| Test framework | **in-repo runner (confirmed)**, no third-party addon |
| Phase 0 order | **as listed in section 11 (confirmed)** |

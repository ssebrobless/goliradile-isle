# Goliradile Isle — Design Review: Findings & Decisions

Addressed to you, Will. This is the executive artifact: the structural decisions, the cheap bugs, the tuning, the UI direction, and how it all re-sequences the refactor roadmap. Every claim below is anchored to `Main.gd` line refs you can verify, and the design calls are backed by research on the games that already solved these problems. I am opinionated throughout — but each major call is framed as a real fork, because several of them are about how you want the game to *feel*, and that's yours to decide.

> **Status — updated 2026-06-21:** Will has now answered all 8 taste questions and set the game's direction, including a new central-objective ("Mother Tree") pivot that wasn't in the original forks. The resolutions are recorded in the **Decisions log — resolved direction** at the end of this document. The analysis below is preserved exactly as originally written; read the Decisions log for what actually got chosen.

---

## TL;DR — the few decisions that matter most

1. **The single highest-leverage realization: three mechanics are actually one wound.** The night-clears-world wipe (`_begin_night` snapshots every NATURAL tile and overwrites it with GRASS, `Main.gd:921-944`), the direct-to-player greedy chase (`to = _player_pos - m["pos"]`, no pathfinder anywhere — zero AStar/Nav/BFS hits in 7,426 lines, `Main.gd:1156-1158`), and the open-arena kiting all exist **because there is no pathfinder**. The wipe exists to keep greedy AI from jamming on terrain; throwaway 5-HP walls (`Main.gd:469-476`) and the digger/wrecker special-cases exist to paper over greedy AI's inability to handle fortifications. Nearly every "building feels pointless / combat isn't exciting / my stuff gets chewed / mined stone vanishes / map clutters up" complaint traces back to this triad. **Fix the pathfinding and most of the feedback list collapses at once.** This is the keystone.

2. **Pick the night's fantasy before you rebalance anything else.** Open-arena action-kiting vs. tower-defense "hold the line" satisfy *different* fantasies, and the game is currently stuck between them satisfying neither. **My recommendation: commit to "hold the line" with a goal-rooted flow-field pather** — it's cheaper at runtime than today's per-wrecker 2500-cell scan and makes building meaningful by construction. But this is the one call only you can make (see Open Taste Questions #1).

3. **Durability should be a designed pillar, not four incoherent accidents.** Today: walls vanish-and-delete-materials, turrets break-in-place-and-repair, BULB/GLAPPLE_LAMP are *accidental invincible walls* (absent from both `MONSTER_WALK` and `BREAK_HP`, confirmed at `Main.gd:466,469-476`), water is permanent. Extend the existing turret/trap repair pattern to all structures + dawn heal. **Low effort, highest value-to-effort in the whole review.**

4. **There is no information layer at all — `draw_string` appears literally zero times** (verified) and no def dictionary carries a description field. Enemies have no HP bars (turrets already do, `Main.gd:5333-5337` — copy that idiom), weapons/tools never state their stats, ammo hides in the inventory. A computed-from-defs surfacing pass closes ~80% of the legibility complaints for a few hours of work.

5. **The UI is one shared container arbitrated by 7 inconsistently-cross-cleared flags**, so opening a furnace while crafting silently does nothing. Collapse to a single `_active_panel` enum (or better, co-visible panels per Terraria) and the entire "menus compete / can't open building from crafting" bug class dies at the root.

The rest of this document expands each, with options and ripple effects.

---

## The structural decisions

### 1. Pathfinding & the night loop — the keystone

**Root cause.** There is no pathfinder. Every chasing croc moves on the raw normalized vector `_player_pos - m["pos"]` (`Main.gd:1156-1158`); `_move_collide` does axis-separated sliding only (`Main.gd:2631-2639`); when a croc makes <50% intended progress and its break-cooldown is ready it probes one cell ahead and `_damage_structure`s whatever `BREAK_HP` tile is there (`Main.gd:1269-1275`). Because greedy seek gets hopelessly stuck on natural terrain, the night must clear the world to an open arena (`_begin_night`, `Main.gd:921-944`). The wrecker (`_update_wrecker`, `Main.gd:1322`) and digger (`_update_digger`) are bespoke special-cases that exist only to bypass greedy AI's inability to deal with walls.

**Complaints it explains:** "crocs bulldoze through buildings instead of routing around"; "everything I build gets hit because they path straight to me"; "building feels pointless"; "open arena is obvious and easy to train around — not exciting"; "the whole-map vanishes-at-night pop feels unmotivated"; "mined stone stays gone while new stone teleports in"; "routing is really basic."

**The decision (fork):** Does the night stay an **open-arena action-kiting game** (keep cheap greedy AI, lean into dodging + anti-kite enemy design) or pivot to a **true tower-defense "hold the line" loop** built on real pathfinding (persistent world, walls as navigable obstacles)? This single fork determines whether the night-clear, the throwaway walls, and the digger/wrecker survive or are deleted.

**Options:**

- **A — Stopgap: local unstuck + anti-kite, keep greedy AI.** Add a perpendicular ±90° unstuck step / stuck-counter in `_move_monster_toward` so crocs slide around isolated walls before chewing (`Main.gd:1270`); give ranged crocs lead-targeting (aim at `player_pos + velocity*lead`); bump fast-yellow weight on later nights. *Ripple:* ~70% of the "walking into a wall forever" improvement for ~5% of the work, ships now. Does NOT solve concave traps, does NOT make building meaningful. Pure band-aid.
- **B — Flow-field/BFS pather, retune as one coordinated change.** One Dijkstra/BFS *from the goal outward* over `MONSTER_WALK` each frame (or every N), treating `BREAK_HP` structures as **high-cost-but-passable** (cost ≈ break HP, not infinite). Crocs read the flow vector at their cell. In the *same* change: raise wall HP, reduce/remove the night clear (leave stone as cover), revisit digger/wrecker. *Ripple:* the real structural fix and **cheaper at runtime** than today's per-wrecker `_struct_cells` scan (`Main.gd:1347-1365`). But it's a balance grenade — intelligent routing + real walls makes the arena-clear and 5-HP walls obsolete crutches, so every croc role and turret needs a rebalance pass. Largest blast radius; makes funneling/killbox a real strategy.
- **C — Pivot to objective-defense night.** Add a core/beacon the player must stay near and crocs also damage; some fraction of the horde targets high-value structures (generalize the wrecker's `_nearest_structure_cell` into a role-weighted target picker), built on the pather. *Ripple:* directly kills kiting and makes building purposeful — the genre's actual loop. Biggest design commitment: new UI, fail states, croc retargeting, full rebalance.

**Research-grounded recommendation.** The evidence is one-sided that the open-arena/greedy-chase night is the **degenerate failure case**. *They Are Billions* uses weighted shortest-path (Dijkstra with per-tile cost), so the swarm routes *around* walls and chews the thinnest gap — this single trick is what turns walls from speed-bumps into funnels (redblobgames.com/pathfinding/tower-defense; They Are Billions community pathfinding analysis). Maze-TD guides put it bluntly: "Bad maze design usually looks fine until the first fast enemy exposes every wasted corner" — i.e. a flat open arena with direct pathing is the degenerate end-state (towerward.com). Flow-field is *strictly superior* to per-enemy A\* for this shape (many enemies, one goal): one search from the goal, O(1) per-enemy lookup, recompute only on map change; peer-reviewed comparison found flow-field reached the target faster than A\* in every TD scenario (gameaipro.com ch.23; ijmra.in/v5i9/20.php).

**My call:** Ship **A immediately** (perpendicular unstuck + lead-targeting on ranged crocs) as a visible win, but commit to **B** as the real direction, executed as a single coordinated change that also raises wall HP and stops fully clearing the map (leave stone as cover). This is the keystone for at least three clusters. **Make the explicit A-vs-C taste call (kiting-action vs objective-defense) before the rebalance** — they satisfy different fantasies. If you don't want a full combat rebalance, the middle path (Open Taste Q#1) is heterogeneous greedy AI: keep cheap chase but add a *structure-targeting aggro split* + a predictive flanker, which re-justifies walls without writing A\* (gamedesignskills.com enemy design; Brotato's small-map + ranged-cone anti-kite).

**Size:** Option A is incremental (hours). Option B/C is a destructive redesign — safe because the game isn't live, and it's already the Tier2 AStarGrid2D item, just promoted to load-bearing.

---

### 2. Durability & the single source of truth for tile behavior

**Root cause.** Durability is encoded implicitly across three independent dicts — `WALKABLE` (~450), `MONSTER_WALK` (`Main.gd:466`), `BREAK_HP` (`Main.gd:469-476`) — plus per-type special cases in `_damage_structure` (`Main.gd:1384-1411`). At 0 HP a structure reverts to GRASS and all dict state is erased — the wood/stone is gone forever (`Main.gd:1408`). Partial damage is also permanent: nothing restores `_struct_hp`, not even at dawn (`_begin_day`, `Main.gd:947-968`). Only turrets (break-in-place + `_turret_repair`, `Main.gd:1672`) and the peel_launcher get the forgiving treatment. **Confirmed bug:** BULB and GLAPPLE_LAMP are in *neither* `MONSTER_WALK` *nor* `BREAK_HP` (verified at `Main.gd:466,469-476`), so crocs can neither pass nor break them — accidental invincible walls. Four incoherent durability rules ship side by side.

**Complaints it explains:** "low incentive to commit to building — it's lost permanently"; "build the bare minimum"; "lots of unbreakable blocks, feels weird"; "things break instantly with no repair path."

**The decision (fork):** Is durability a **designed pillar** (walls wear, get repaired, choices matter) or an **accident to flatten/remove**? And: keep the three-dict + special-case encoding, or unify into one per-terrain descriptor (the Tier2 `.tres` direction)?

**Options:**

- **A — Extend the turret/trap repair pattern to all structures.** Generic in-place material-cost repair mirroring `_turret_repair`, plus a ~5-line dawn auto-heal in `_begin_day` (iterate `_struct_hp` and erase entries = back to full). Stop reverting to GRASS+deleting cost on 0 HP — convert to a rebuildable "wreck" tile. *Ripple:* highest value-to-effort in the cluster; retires the turrets-repairable/everything-else-disposable inconsistency. Dawn auto-heal removes the tension of "a wall actually broke"; material-cost repair preserves it but needs UI.
- **B — Close the invincible-wall gap + signpost permanence.** Add BULB/GLAPPLE_LAMP to `MONSTER_WALK` (light tiles = walk-over decorations); give water/cliffs a distinct "impassable" read; delete or wire the dead `TRAP_MAX_HP['trap']:6` constant (`Main.gd:327` — spike traps never enter `_traps`, so it's never read). *Ripple:* trivial dictionary fix that removes a real exploit in minutes.
- **C — Unify into one tile-data descriptor (`.tres` GameDb).** Replace scattered membership + special cases with one per-terrain descriptor (`player_walk / monster_walk / break_hp / on_break`); "unbreakable" becomes an explicit, lintable property. *Ripple:* removes a whole bug class; broad refactor touching movement/combat/build/save; worth it only as part of the Tier2 data-def migration.

**Research-grounded recommendation.** Every successful base-defense game makes durability a *designed pillar*: *Kingdom Two Crowns* has tiered walls (barricade→wood→stone→iron) with daytime auto-repair and a cheap "stump" remnant so rebuilding is cheaper than fresh — *this rewards having built at all* (kingdomthegame.fandom.com/wiki/Wall). *Core Keeper* makes wall *material* a real choice (enemies dig natural tiles but not crafted ones; moats work because monsters can't swim) (core-keeper.fandom.com/wiki/Walls). The throwaway 5-HP wall is the anti-pattern: too cheap and weak to be a "choice," so it reads as an accident.

**My call:** Do **A's dawn heal + generic repair** AND **B** (the lamp fix + dead-constant cleanup) **now** — both low-effort, and B fixes genuine bugs. Pair with raising wall HP (coordinated with the pathfinding decision so walls become real obstacles, not free). Defer **C** into the Tier2 `.tres` terrain migration as the structural guarantee against the next accidental invincible block.

**Size:** A+B are incremental (a few hours). C is the Tier2 migration.

---

### 3. World model — no spatial budget, no biomes, no conservation invariant

**Root cause.** The world is four flat `PackedArrays` mutated in place with no cap, no target density, no clustering, no decay. `_regrow_world` (`Main.gd:1082-1102`) sprinkles ~19 fresh naturals (incl. one HIVE, **verified unconditional append at `Main.gd:1089`**) onto random GRASS every dawn with NO cap and NO `_is_outdoors` check — it can spawn obstacles inside the player's base (only the single `_cell` is excluded, `Main.gd:1095`). Since the night snapshot/restore is net-zero, regrow is pure additive drift contradicting the header's "restored exactly" claim. Initial gen and regrow roll each cell independently (only STONE uses `FastNoiseLite`, `Main.gd:3792-3806`) → salt-and-pepper single-tile blockers, never forests. Restore is asymmetric: `_begin_day` upgrades STUMP/SAPLING back to full TREE with fresh fruit (`Main.gd:953-958`) so chopping is undone, while mined stone (STONE→GRASS) is never snapshotted and is silently lost while `REGROW_STONE` sprinkles new stone elsewhere.

**Complaints it explains:** late-game lag (unbounded accumulation + immediate-mode full-grid repaint); "resources pop up in the middle of my base"; "map is an obstacle course, no biomes/forests"; "day-gathering doesn't stick"; "way too many beehives."

**The decision (fork):** Keep the nightly-wipe + regrow-faucet world (cap/guard it) or move to a **persistent world with biome regions** (gated on the pathfinding decision — the wipe only exists to feed greedy AI)? And separately: keep immediate-mode `_draw` or migrate terrain to TileMapLayer for free culling/batching?

**Options:**

- **A — Cap + guard + cull (low-effort patches).** Add `NATURAL_CAP`/`HIVE_CAP` so regrow skips once density is hit; reject regrow cells where `_is_outdoors(c)` is false (the helper the build path already trusts, `Main.gd:2473`); restrict `_draw`'s cell loop to the Camera2D visible rect. *Ripple:* bounds lag, stops base-intrusion, removes the runaway — all small, mostly reusing existing helpers. Leaves the world as capped uniform noise.
- **B — Noise-clustered placement + neighbor-biased regrow.** Drive ALL resource families off `FastNoiseLite` fields (a forest field, a rock field); bias regrow toward cells adjacent to same-type tiles. *Ripple:* big feel-per-line win answering "forests/rock chunks"; reuses the noise already imported. Still clumped noise, not true regions.
- **C — Persistent world + biome regions (fold into pathfinding redesign).** If AStarGrid2D lands, delete the snapshot/wipe: chopped trees stay stumps and regrow in place, mined stone stays mined, `_regrow_world` becomes a slow in-place top-up toward per-region target density. Bake a low-frequency biome/Voronoi map driving gen and regrow; guarantee navigable lanes. *Ripple:* dissolves lag, teleport, base-intrusion, "doesn't stick," and boring-arena complaints at once, and gives the world identity (matches the procedural-art KEEP). Largest effort.

**Research-grounded recommendation.** The winning procgen pipeline for a 50×50 grid is layered: **low-frequency noise or jittered Voronoi for *where biomes are*** + **local clustering (cellular automata 4-5 rule, or Poisson-disk for scatter) for *what fills them*** (redblobgames.com/maps/terrain-from-noise; Don't Starve's Voronoi-rooms place nodes blue-noise-spaced within a room). Critically on a small grid, **connectivity is a separate post-pass**: flood-fill to label regions, carve corridors to guarantee navigable lanes — random gen reliably strands regions (roguebasin Cellular Automata). And the conservation invariant that stops unbounded accretion is *Don't Starve Together's regrowth model*: a resource only spawns if **fewer than N of the same type exist in a radius**, and never near base/structures/player (dontstarve.fandom.com/wiki/Regrowth). Base-spawn suppression is a standard "spawn-inhibitor radius" pattern (Abiotic Factor's workbench).

**My call:** Ship **A immediately** (cap regrow incl. `HIVE_CAP`, add the `_is_outdoors` guard, cull the renderer). Ship **B** as the interim biome-feel win on top of the cap. Schedule **C** as the proper world-model rewrite tied to the pathfinding/TileMapLayer roadmap; it makes the persistence and biome complaints evaporate as side effects. Keep trees/bushes solid (intended) but guarantee navigable lanes.

**Size:** A is a handful of lines each. B is medium. C rides the pathfinding redesign.

---

### 4. The information / legibility layer (it does not exist)

**Root cause.** The def dictionaries (`STRUCTURES`, `TURRET_DEFS`, `CROC_DEFS`, `WEAPON_DEFS`, `TOOL_DEFS`, `CRAFT_RECIPES`) are the single source of truth for behavior but carry **no description/stat-line field**. Explanatory prose exists only as code comments (e.g. `Main.gd:225`) or in util panels that appear *after* you build the machine (barrel/juicer footers ~4663/4679) — always after the resource commitment. **`draw_string` appears 0 times in the whole file (verified)**, so nothing in the world layer is a number: crocs have hp/max_hp but no HP bar, while turrets DO draw one in the same `_draw` pass (`Main.gd:5333-5337`). Weapon stats and tool bonuses are fully modeled but never surfaced. The only teaching surface is a static CONTROLS list plus a 2.5s single-slot `_msg` banner.

**Complaints it explains:** "no info on enemy health"; "no info on weapon damage / combat in general"; "no easy ammo view"; "what is the point of the tools?"; "buildings don't have clear value ahead of time"; "drinking/filling cups is opaque"; croc roles are invisible (encoded only as colors).

**The decision (fork):** Bolt per-item description strings + a few HUD readouts onto the existing ad-hoc panels, or build a real information layer (self-describing GameDb defs + reusable tooltip/codex + contextual hint engine)?

**Options:**

- **A — Cheap surfacing pass (computed, not hardcoded).** Croc HP bar in `_draw` by copying the turret idiom (gate to damaged-only); compute weapon/tool effective stat lines from the defs and show in craft panel + `_lbl_stats`; bottom-right ammo readout via a weapon→ammo lookup; a `desc` field per structure/recipe; seed an Empty Cup + a one-time low-hydration hint. *Ripple:* resolves nearly every literal complaint for a few hours; computing from defs avoids drift on retune.
- **B — Contextual action-prompt + tooltip layer.** When adjacent to an interactable, draw what the next click will do given inventory/time ("Click: fill cup", "need a Glass Jar", "pool dangerous at night"); hover tooltips; surface the tech ladder (gray-out by reachability, "NEW" markers, horde-free days 1-2). *Ripple:* kills the overloaded feedback-less water-click; generalizes to every adjacency.
- **C — Self-describing GameDb + codex + hint engine (Tier2).** `.tres` with `display_name`/`description`/derived-stat methods; one reusable inspect panel; an event-driven hint queue with persisted "seen" flags (riding the Tier1 versioned save). *Ripple:* eliminates the bug class for good; heavy; needs a "hide hints" toggle.

**Research-grounded recommendation.** A controlled IEEE GEM 2015 study found **"number-in-game" ammo** (a numeric counter in the world near the weapon, Dead Space/Halo-style) decisively best: ~35% fewer wasted shots, ~26% faster reloads, 70% favorite — beating HUD bars/icons because it minimizes eye travel (yorku.ca/mack/ieee_gem2015). For enemy HP, the favored pattern is **conditional bars — show only on damage / nearest target, never at full HP** (Kingdoms of Amalur), with a separate always-on boss bar. For mechanic discovery, "show don't tell": a visibly interactable water tile + a cup whose icon implies it wants filling + an on-proximity prompt beats any tutorial popup, and a mechanic used only *once* per run probably shouldn't be taught at all — reconsider it (gamedeveloper.com Organically Teaching). Terraria's Guide NPC is the model self-describing tooltip; Vintage Story's handbook is the cautionary tale that a static reference dump still fails onboarding.

**My call:** Ship **A now** — single highest-value batch in the whole feedback set; computing from defs means nothing desyncs. Layer **B** next ("clear value" needs the dependency graph + the fixed water-click). Fold **C** into the Tier2 GameDb migration with a producer/consumer + has-description selftest invariant.

**Size:** A is incremental (hours). C is the Tier2 migration.

---

## Quick-win bug fixes

These need **no design decision** — just do them.

| Bug | Root cause | Fix |
|---|---|---|
| **Adhesive turret's green slow-field draws all day & re-engages stale** | `t["field"]` is stored on the *persistent* turret dict (`Main.gd:1885`) and nothing resets it; `_draw` renders it with no night gate (`Main.gd:5316-5321`); `_adhesive_factor` still honors it (`Main.gd:1908-1915`). Every other field/aura lives on the monster dict and dies when `_monsters` clears — adhesive is the unique offender. | Add **`_reset_night_state()`** as the single end-of-night choke point: clear monsters/projectiles/clouds/status AND iterate turrets/traps resetting per-night fields (`field=Vector2.INF, cd, powered, heal_t`) to `_new_turret` defaults; call from `_begin_day` and selftests. Gate the field `_draw` on `_is_night` as insurance. |
| **Player frozen at dawn / when placing blocks nearby** | Collision is resolve-only with no un-stick path (`_move_collide`, `Main.gd:2631-2639`). `_begin_day` restores naturals checking only player-*built* cells (no player-position guard); `_apply_build_at` guards only `c==_cell` while the body (`PLAYER_RADIUS` 10.88px) overlaps neighbor cells. The `i != player_idx` guard at `Main.gd:992` is the missing precedent. | Add the player-body overlap guard (cells under `_player_pos ± PLAYER_RADIUS`) to **both** `_begin_day` restoration and `_apply_build_at` placement; add an un-stick fallback in `_move_collide` (if `_box_blocked` at frame start, slide toward open space). |
| **Worm/bee loot orbs never collected, become permanent litter** | `_collect_ground_items` (`Main.gd:3039-3043`) gates worm/bee pickup behind owning a `glass_jar` and `keep.append()`s them otherwise; `g["t"]` is never used as a TTL. A jarless critter orb is permanent (and reads as uncollected ore/honey because of its gold/pink color). | Add a `LOOT_LIFETIME` TTL so orbs despawn (with a fade), plus a throttled "Need a glass jar to catch the worm/bee." message when standing on a refused critter. |
| **BULB / GLAPPLE_LAMP are invincible walls** | Absent from both `MONSTER_WALK` and `BREAK_HP` (verified `Main.gd:466,469-476`). | Add both to `MONSTER_WALK` (light tiles = walk-over decorations). |
| **Dead `TRAP_MAX_HP['trap']:6`** | Spike traps are pure terrain in `_trap_update`, never enter `_traps` (`Main.gd:327`), so the wear HP is never read. | Delete the entry (or wire spike-trap wear). Latent trap for the next engineer. |
| **Mined stone silently lost; new stone teleports in** | Mining sets STONE→GRASS (`~2911`) so it's not snapshotted, while `REGROW_STONE` sprinkles new stone elsewhere. | At minimum reduce/remove `REGROW_STONE`. Full fix (depleted-stone marker / persistent world) lives in the world-model theme. |
| **Regrow spawns resources inside the player's base** | `_regrow_world` (`Main.gd:1090-1097`) places on any GRASS excluding only `_cell`, never calling `_is_outdoors`. | Add `if not _is_outdoors(c): continue` to the placement loop. |

---

## Balance & legibility tuning

Smaller items that need a *direction*, not a structural fork.

- **Bees / hives value + over-spawn.** Honey is produced (enclosure ~3316, wild hive `Main.gd:3500`) but read only by selftests; **beeswax is never read by any code path**. Hives seed at worldgen AND +1 unconditionally every dawn (`Main.gd:1089`) with no cap and no removal. *Direction:* the cap and the sink are the **same faucet-with-no-drain story — ship them together.** Add `HIVE_CAP` (count HIVE tiles, append only if under cap); add honey to `_try_eat` as a high-energy snack; add one beeswax craft recipe (candle/binder). Later, a proper "bee economy" pass: honey→healing salve / energy buff, beeswax→wax-sealed walls with more HP, hives deplete-on-harvest + sting (risk/reward) — *Core Keeper's underpowered turrets are the real-world cautionary tale of an orphaned output.* Add a `--selftest` invariant later: every `INV_ORDER` item has ≥1 producer AND ≥1 consumer.

- **Workbench tether.** `_apply_build_at` spends + places atomically, gated by `if s["bench"] and not _near_workbench()` (verified `Main.gd:2458`), and `_near_workbench` checks the 8 cells around the *player's* tile, not the target — so with a camera-follow at fixed zoom the placement zone collapses to a small disc around the bench. 16/26 buildables carry `bench:true`, so you can't put turrets on a far perimeter. *Direction:* **Now** — `_near_workbench_cell(c)` checking the *target* cell at radius ~2-3, unblocking the playtester. **Real fix** (your stated wish) — separate craft from place: fabricate bench-gated **kits** to inventory, deploy anywhere with no bench check; demolish refunds the kit. This touches the save format → do it when Tier1 save-hardening lands. *Update the menu lock text + HUD bench indicator in lockstep or the UI will lie about why a structure is locked.* (Valheim/Terraria both gate *fabrication* at the station but let *placement* happen anywhere.)

- **Day length / pacing.** `DAY_LENGTH=120s`; `_daylight()` force-disables building when `_time<0.20 or ≥0.80`, so buildable daylight is only ~72s, and day 1 starts at `_time=0.30` → 60s. Within that the player funds *two* survival economies (metabolism + base) from the same scarce daytime swings, forcing ~70-90% gather-grind. *Direction:* **Now** — widen daylight to ~75%, raise base harvest yield to 2-3, make days 1-2 horde-free onboarding. **Durable** — progression-scaled gathering (auto-harvester/lumber-mill trickle) so the grind shrinks over a run. *Avoid a global pause* — it fights the tower-defense identity. Stardew's lesson: keep micro-tension, kill the macro-deadline (pause time in menus, unlimited days). Dome Keeper's dig-defend rhythm — scale prep time with how much you've built — is the strongest model and dovetails with the night-loop redesign.

- **Tool purpose.** Tools add +1/+2 gather and ×0.6/×0.4 energy (`TOOL_DEFS`, `Main.gd:226-229`) — a silent invisible multiplier. *Direction:* surface the computed effect string in the craft panel + `_lbl_stats` (compute from the def, never hardcode, so it can't drift). Optionally spawn the extra loot as a distinct floaty pickup so the value is *felt* (fits the juice identity).

- **Combat readout.** Croc HP bar (copy the turret idiom `Main.gd:5333-5337`, gate to damaged-only); float-up damage numbers (red/fast for damage, green/gentle for heal, gray-flutter for blocked-by-wall, aggregate multi-hits); ammo as a bottom-right / world-anchored number when a ranged weapon is equipped.

- **Cup discoverability.** Hydration is a hidden multi-step chain (craft cup → click pool → Q) with the player starting with zero cups (`_default_inventory` zeroes everything). *Direction:* seed one Empty Cup, fire a one-time thirst hint when hydration first crosses ~30, trigger the PARCHED warning *before* hydration hits 0, document the coconut fallback. Then the contextual adjacency prompt (Option B above) generalizes this to every hidden interaction.

---

## UI/UX overhaul direction

**The disease.** One right-hand container (`_right_vbox`), arbitrated by `_refresh_context_panel` (`Main.gd:4201-4223`) — a fixed priority if/elif over **seven mutually-exclusive flags**. Exclusion is enforced only by scattered, *inconsistent* cross-clearing: keyboard toggles clear siblings, click openers mostly don't — so opening a furnace while crafting sets `_open_util` but the elif short-circuits on `_craft_open` and the furnace UI is **silently invisible**. Every refresh tears down all children and rebuilds from scratch, firing from ~50 call sites incl. per-frame proximity checks, so scroll/focus is lost. Panels are pure text with no item icons; long copy is hand-split for a fixed 280px width with no autowrap, so it overflows.

**The coherent direction (sequenced):**

1. **State model — collapse 7 flags to one `_active_panel` enum** (+ target cell). `_refresh_context_panel` becomes a single `match`; every opener sets it in one place. This kills the craft-blocks-furnace dead-click AND the entire "forgot to clear a sibling" bug class. **Same pass:** give each panel a retained node with `refresh()` that updates child widgets in place (preserves scroll/focus, enables tween juice); gate per-frame paths to edge-changes only; set `autowrap_mode` on `_label`, split the crammed `_lbl_stats`, fix wide button rows (fixes overflow outright).

2. **Per-item baked icons + reusable item row.** Extend the procedural-bake step (`Main.gd:696-705`) to make ~50 16×16 item icons; add `_item_row(icon, name, count, buttons)` used in inventory/craft/build; replace the solid ColorRect with real sprites. This ties the UI to the procedural-art identity (an explicit KEEP) and is the highest-value *visual* upgrade.

3. **Reconsider single-panel vs co-visible.** The research strongly favors **co-visible panels over a single shared rectangle**: Terraria embeds crafting *inside* the always-open inventory and a station *adds* its recipes contextually rather than replacing — inventory and crafting are never competing for the same space (gameuidatabase.com; Terraria 1.4.5 crafting). Valheim's station-gated full-screen takeover is the *less-liked* pattern that spawned a UI-mod ecosystem. So: each panel its own Control in a named slot (left HUD persistent, right-top inventory, right-bottom transient station, bottom build bar), so a machine opens *without* closing inventory/crafting. Pair with a **programmatic Theme** (the Tier2 item) for consistent fonts/colors/styleboxes/badges, and an **icon grid with corner quantity badges + category tints** for the inventory. This is the Tier3 UI-to-scenes work — do it last, on top of the enum + retained panels.

4. **One reusable root-level tooltip frame** (per UX best practice: rendered on top, hidden when no data, never carrying irreversible-action info) driven by the GameDb description fields — this is where the legibility layer (Decision 4) lives permanently.

**Idiomatic Godot:** items as `.tres` Resources not nodes; slot scene = PanelContainer + TextureRect + corner Label; one GridContainer-extending slot script serves hotbar and inventory; data↔UI decoupled via signals; save only IDs + quantities. A radial tool/weapon wheel is well-supported (the maintained Radial Menu Control asset 3469) if you want one.

---

## How this reshapes the refactor roadmap

The existing roadmap is sound as *cleanup*, but several "Tier2/Tier3" items are now **load-bearing for specific gameplay fixes** and must be re-sequenced up. The core re-sequencing principle: **gameplay/UX root-causes outrank pure cleanup.**

**Promoted to load-bearing (do earlier than their tier suggested):**

- **AStarGrid2D / flow-field pathfinding (was Tier2)** is the **keystone**, not a perf nicety. It's the single fix that dissolves the night-loop, building-pointlessness, world-clutter, resource-teleport, and boring-arena clusters simultaneously. Everything about durability/walls/digger/wrecker tuning is downstream of it. **Sequence it as the first big structural piece** — after the cheap stopgaps (Decision 1 Option A) ship as a visible win.
- **Data-driven `.tres` Resources + GameDb (was Tier2)** is now load-bearing for the **information layer (Decision 4)** *and* the **unified tile descriptor (Decision 2C)** *and* the **producer/consumer invariant (bees)**. The flow-field walkability mask, the regrowth ledger, the spawn-inhibitor radius, and the durability model all want to read from one per-terrain descriptor. Promote terrain + turrets first.
- **TileMapLayer for terrain (was Tier3)** is load-bearing for the **late-game lag** complaint, not just architectural tidiness. `_draw` is an immediate-mode full-grid repaint of all 2500 cells + per-fruit overlays + 102 grid-lines every frame at night (`Main.gd:5136-5172`) — a known Godot perf trap. Migrate to TileMapLayer with **event-driven `set_cell`** (only changed cells), driven by the same camera-cull insight. Implement the nightly flatten as a *diff over a persisted day-layer*, not a regenerate-from-noise wipe.

**Re-sequenced UI work:**

- The **Node-based AppState FSM (Tier2)** applies directly to the UI: the `_active_panel` enum *is* that FSM at the panel layer. Do the enum + retained `refresh()` first (kills dead-clicks + rebuild waste in one pass over the ~50 call sites — touch them once).
- **UI-panels-to-scenes + programmatic Theme (Tier3)** come *after* the enum lands, because co-visible panels and theming need a clean state model and retained identity to theme against.

**Stays where it is, but with a clear consumer now:**

- **Tier1 save hardening (version + migration + atomic + backup)** is the prerequisite for two design fixes you'll want: **structure kits** (carrying placeable kits in inventory changes the save format) and the **persisted "seen-hint" flags** for the onboarding engine. So Tier1 save work isn't just hygiene — sequence the kit/hint features right after it.
- **Tier1 InputMap actions, Tween juice, Camera2D smoothing/limits, audio skeleton** — keep as-is; the Camera2D rect is also what the renderer cull (Decision 3A) reads, so do it before the cull.
- **CPUParticles2D (Tier2)** pairs naturally with the staged wither/regrow animation if you want to soften the night-transition pop, and with damage-number/death juice.

**Explicit ordering I'd run:**

1. **Quick-win bugs** (`_reset_night_state`, un-stick + body guards, loot TTL, lamp/dead-constant, regrow `_is_outdoors` + caps). Days, not weeks. Fixes real exploits and freezes.
2. **Cheap surfacing pass** (Decision 4A) + **durability repair/heal** (Decision 2A/B) + **pacing/tether/bee** tuning. The visible-quality batch.
3. **UI state-model refactor** (`_active_panel` enum + retained panels + autowrap). One coordinated pass over the call sites.
4. **Tier1 save hardening** → then **structure kits**.
5. **Make the night-fantasy call (Open Q#1)**, then **flow-field pathfinding + coordinated rebalance** (Decision 1B/C). The keystone.
6. **Riding the pathfinding redesign:** persistent world + biomes (3C), TileMapLayer + event-driven render, delete the wipe.
7. **Tier2 GameDb migration** (4C, 2C) — the permanent home for descriptions + the unified tile descriptor + the producer/consumer selftest.
8. **Tier3 UI-to-scenes + Theme + icon grid.**

---

## Open taste questions for you

These are the forks only you can answer — they're about how the game should *feel*. Each has my recommendation and the real options.

1. **Night fantasy: action-kiting or hold-the-line?** *(The biggest call; gates the whole rebalance.)*
   - **A) Open-arena action.** Keep cheap greedy AI, lean into dodging. Requires anti-kite enemy design (predictive/leading crocs, a faster flanker, ranged-cone units, structure-targeting aggro split) or kiting stays dominant. Walls stay light speed-bumps; durability stays minor.
   - **B) Hold-the-line tower-defense.** Flow-field pather, persistent world, walls as real navigable obstacles, durability as a pillar. The genre's actual loop; biggest rebalance.
   - **My rec:** **B**, executed as one coordinated change — but if a full combat rebalance is undesirable, take the **middle path** (heterogeneous greedy AI: structure-targeting split + a predictive flanker), which re-justifies building without writing A\*.

2. **Durability: tension or convenience?** Material-cost repair (you *feel* a wall break, must invest to fix) vs. free dawn auto-heal (overnight survival just restores everything). *My rec:* both — dawn heal for partial damage as a baseline reward, material-cost rebuild for fully-destroyed "wreck" tiles, so the tension lives at the destruction threshold.

3. **World permanence: does the day's gathering "stick"?** Persistent world (chopped trees stay stumps, mined stone stays mined, slow in-place regrow) vs. nightly reset-and-refill. *My rec:* persistent — but it's only clean *with* pathfinding (it's free as a rider on Decision 1B; not applicable standalone while the wipe exists).

4. **Pacing rhythm: deadline or breathing room?** Keep every day a continuous gather-deadline (just retuned) vs. an explicit prep↔siege oscillation with a visible "next wave in N" meter and optional player-triggered nights (Dome Keeper / wave-survival model). *My rec:* add a **dusk warning beat** + scale prep time with how much you've built, but avoid a hard global pause.

5. **Bee economy: snack or combat system?** Honey/beeswax as shallow sinks (honey = snack, beeswax = one recipe) vs. a real payoff (honey→healing salve/energy buff, beeswax→wax-sealed high-HP walls, hives deplete + sting). *My rec:* ship the shallow sinks + cap *now* (they're the same fix), escalate to the combat payoff when you next touch survival/defense balance.

6. **Workbench: leash or untether?** Target-cell bench check at a wider radius (still proximity-gated, encourages bench-spam) vs. fully separate craft-from-place via inventory kits (your stated wish; needs save migration). *My rec:* target-cell check **now** to unblock, kits **after** Tier1 save-hardening.

7. **UI shape: single-panel-done-right or co-visible?** `_active_panel` enum (provably consistent, still one panel at a time) vs. true multi-panel slots (inventory + station visible together, Terraria-style). *My rec:* enum first regardless; then co-visible once you confirm 280px stacked panels can host inventory + context — the research says co-visible is the better end-state.

8. **Audio:** you've said it's low-priority and you want lowest-friction-to-extend. *My rec:* a thin data-driven `play_sfx(id)` bus wired to the same event points as the juice (croc death, wall hit, build, dawn/dusk) so adding sounds later is a content edit, not a code edit. Nothing more until the above lands.

---

## Decisions log — resolved direction (2026-06-21)

Will answered all 8 taste questions over follow-up discussion. **This section is the source of truth where it conflicts with the open questions above.**

### Locked identity

**Production-driven base defense.** The deep crafting/farming/resource economy exists to fuel and upgrade an automated turret defense. During the siege the player is the **engineer** — building, repairing, re-arming turrets, plugging gaps — *not* the primary source of damage. The DPS center of gravity shifts from the player's body to the turret network, and the horde scales past solo-killable (~night 3–4), so holding the line is mandatory rather than a playstyle choice. (*They Are Billions / Dome Keeper* territory.)

### The central-objective pivot — supersedes the A/B/C fork in Decision 1

The chosen shape is **Option B's mechanics in service of an Option C loop**: flow-field pathfinding + persistent world + walls-as-real-obstacles, organized around a **central structure the player defends** (working name **"Mother Tree"**; a totem / heart / hub works too — thematically gorilla-vs-crocs).

- **Lose condition = the objective is destroyed, NOT player death.** Personal health/stats still matter (enemies attack the player too; being downed is a setback), but they no longer dictate when the run ends. This decoupling is what makes hold-the-line coherent.
- **Split aggro:** some enemies path to the objective, some to the player — *designed and telegraphed*, not the current random bulldozing. This is the resolution to the "random crocs wreck my base while I'm busy fighting" frustration (#2).
- **The hub doubles as the upgrade / tech-tree center:** one place to see the upgrade tree and understand what to build/farm next. It also anchors turret placement — you build your defenses around it.
- **OPEN PROBLEM (flagged by Will):** the *incentive system and gameplay loop* around the hub is not yet concrete — why/what you upgrade there, what the progression pressure is, how advancement and pacing work. **This is the first thing to design before implementation.**

### Per-question resolutions

1. **Night fantasy → B (hold-the-line), realized as the central-objective loop above.** Flow-field pathfinding committed.
2. **Durability → persistent damage (no painless dawn reset); destroyed structures leave a cheap-to-rebuild *wreck* instead of vanishing-and-deleting-materials; repair is a siege job.** Counterplay comes from routing + reinforcing the weak point. Folds into the objective-defense + aggro-split model.
3. **Sustainability → renewable extraction machines + combat reclaim (corpses / spent ammo) + ammo-tech diversification + capped *in-place* biological regrowth (never in base).** Scarcity becomes a prompt to build the next extraction tier, not a dead-end. (Endorsed.)
4. **Pacing → retune (wider daylight, higher yields, horde-free days 1–2) + a dusk "night in N" countdown warning.** NOT the player-triggered / prep-scaling version.
5. **Bees → demoted to a production *input* for advanced turret tech** (e.g. beeswax sealant/insulation), less prominent than now. Plus hive cap + the producer/consumer selftest invariant.
6. **Workbench/kits → Terraria/Valheim model (fabricate at station, place anywhere), but gated behind the UX redesign** — placement becomes part of a unified build *mode*, not a new modal layer.
7. **UI → ground-up restructure, treated as a major feature redesign requiring a fully concrete implementation spec before any code.** Target: co-visible workspace (inventory + crafting together; stations *add* recipes rather than open separate menus), icons not text, hover-inspect, build/placement as a dedicated overlay mode. The `_active_panel` enum is step zero.
8. **Audio → thin data-driven `play_sfx(id)` hook at existing juice event points. Minimal attention.**

### Remaining design work before implementation

- **Production-economy graph** (#1/#3/#5): the concrete resource → production → turret dependency graph, the extraction/reclaim sustainability loops, and how the tech ladder branches.
- **Central-objective loop** (the open problem above): the incentive/progression system around the Mother Tree, the win/advance conditions, and pacing.
- **Combat & durability concretization** (#1/#2): flow-field details, aggro-split rules, the turret-as-DPS rebalance, and the wreck/repair model.
- **UX architecture spec** (#6/#7): the full co-visible workspace + build-mode design, made completely concrete (mockups + every interaction) before any code.
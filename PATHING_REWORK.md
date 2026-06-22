# Goliradile Isle — Croc Pathing Rework (AStarGrid2D)

**Status:** front-loaded design spec, awaiting taste/scope sign-off, then hand off to the technical implementer.
**Why this exists:** the flow-field navigator is the keystone bug. A long-window probe proved **only ~33% of crocs ever reach the tree (131/400), and the other 67% wedge permanently** — 17× more sim time moved `reached` by zero. Two prior "verifications" passed on metrics that were narrower than "crocs actually arrive" (zero-radius selftest; a `stuck_whole_run` counter that only catches freeze-at-spawn). This rework replaces local-steering navigation with **committed, planned paths**, and — critically — ships a **success metric that can't lie** (`reached → ~all`, measured solo AND crowded).

**Scope decision (owner):** *Scoped* structural change. Replace the navigator for normal tree/player-aggro crocs with Godot's `AStarGrid2D`. The rest of the god-file stays single-file (the earlier "fix now, restructure later" decision holds everywhere else). This is the one subsystem where a real must-fix bug justifies the Godot-native rebuild.

---

## The core insight (read before coding)

AStarGrid2D plans on grid **points**; a croc is a **body** (`MONSTER_RADIUS = CELL_SIZE*0.34 = 10.88px`, diameter ≈ 68% of a cell) moving by **per-axis** collision (`_move_collide`/`_box_blocked`). A* by itself does NOT fix the radius/corner deadlock that broke the flow field. The fix comes from three things together:
1. **Commit to a path.** Plan once, follow waypoints center-to-center. No per-frame gradient re-decision → no oscillation/livelock.
2. **No corner-cutting diagonals.** `DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES` — a diagonal step is only allowed when *both* orthogonal neighbors are open, so a path segment never clips an obstacle corner. Every cardinal segment runs down a corridor centerline (full body clearance); every diagonal segment runs through a 2-wide opening.
3. **Radius backstop.** If (1)+(2) still trap a body in tight 1-cell gaps (the probe will tell us), inflate obstacles by the agent radius in the solidity map (rule in §6). Specified as a contingency with a concrete trigger, not a guess.

**Acceptance is behavioral, not structural** — see §7. Do not declare done on "selftest green."

---

## 1. What to KEEP (do not touch)

These work and are out of scope. Verify they still function after the swap; do not rewrite them.
- **Sapper navigation** — `_field_sapper` + `_recompute_flow_field(..., ignore_break=true)` + `_update_digger` (`Main.gd:2053`). Sappers tunnel through walls on their own ignore-break field; that subsystem stays on the flow field. (You are removing the flow field for *normal* crocs only; the sapper field remains.)
- **Pink wrecker** — `_update_wrecker` (`Main.gd:2092`) uses raw Euclidean nearest-structure geometry, no field. Untouched.
- **`_move_monster_toward`** (`Main.gd:1998`), **`_move_collide`** (`Main.gd:3736`), **`_box_blocked`** (`Main.gd:3747`) — the radius collision + per-axis slide + wall-break probe + unstick. KEEP. You change only the *direction source* feeding `_move_monster_toward`, not the mover. (Keep the unstick probe as a movement-layer safety.)
- **Wall-break probe** inside `_move_monster_toward` (`Main.gd:2008-2016`) — crocs chew a breakable tile when blocked. KEEP, unchanged.
- **`_monster_separation`** (`Main.gd:1778`), knockback (`Main.gd:1860`), slow/stun (`Main.gd:1853`), `_adhesive_factor`. KEEP; they blend onto the steering direction exactly as today.
- **Grid utils + TILE_DEF accessors** (`_world_to_cell`, `_cell_center_world`, `_in_bounds`, `_cell_index`, `_tile_impassable`, `_tile_break_hp`, `_tile_armor`, `_terrain_at`). KEEP and reuse.

## 2. What to RETIRE (normal-croc flow field)

Remove or stop calling, for **tree/player aggro only**:
- `_field_tree`, `_field_player` storage + their recompute (`_recompute_tree_field` tree half `Main.gd:1660`, `_recompute_player_field` `Main.gd:1668`) and the player-field ticking in `_tick_flow_fields` (`Main.gd:1645`).
- `_flow_dir_from_cell`/`_flow_dir_from_pos` (`Main.gd:1740/1771`) as the chase-direction source at `Main.gd:1867-1876`.
- `_field_player_timer`/`_field_player_cell`/`FLOW_PLAYER_INTERVAL` machinery.
- Keep `_recompute_flow_field` (`Main.gd:1690`) and `_flow_step_cost` (`Main.gd:1674`) **only** for the sapper field. Keep `_field_tree_dirty`/`_invalidate_flow_fields` for the sapper rebuild.

## 3. The navigator (Mode A — decided)

Add one `AStarGrid2D` instance `_nav` for normal crocs.

**Setup** (once, after world gen; rebuild region only if grid size changes):
```
_nav = AStarGrid2D.new()
_nav.region = Rect2i(0, 0, GRID_CELLS, GRID_CELLS)
_nav.cell_size = Vector2(CELL_SIZE, CELL_SIZE)
_nav.offset = Vector2(CELL_SIZE, CELL_SIZE) * 0.5      # point -> world CELL CENTER
_nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES   # no corner cuts
_nav.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
_nav.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
_nav.jumping_enabled = false                          # jumping ignores weights
_nav.update()                                         # required before queries
# then set per-cell solidity + weights (below)
```

**Solidity + weight per cell** (decided — mirrors `_flow_step_cost` semantics so wall behavior is preserved):
- **Impassable** tile (`_tile_impassable(t)` true: WATER/TREE/STONE/BUSH/COCONUT/BAMBOO/HIVE/IRON_VEIN) → `set_point_solid(c, true)`.
- **Breakable** tile (`break_hp > 0`: walls/doors/structures) → `set_point_solid(c, false)` and `set_point_weight_scale(c, 1.0 + float(break_hp + armor*8) * FP_NAV_WALL_WEIGHT)` ⟐. So crocs route *around* walls when a reasonable detour exists, but path *through* the cheapest wall when sealed in — exactly today's behavior. They physically chew it via the kept wall-break probe when movement blocks.
- **Walkable** (cost-1) tile → `set_point_solid(c, false)`, `set_point_weight_scale(c, 1.0)`.

**Keep the grid in sync** at the single choke point `_set_terrain` (`Main.gd:5678`): on every tile change, update that cell's solid flag + weight, and bump a `_nav_epoch` counter (cheap O(1)) so crocs know to replan. When a wall breaks → WRECK (walkable) the cell flips non-solid immediately here — no lazy gap delay.

## 4. Per-croc path state + follow (Mode A — decided)

Add to the croc dict (additive; default safely on load): `"path"` (PackedVector2Array of world waypoints), `"path_i"` (int), `"replan_t"` (float), `"plan_epoch"` (int), `"plan_goal"` (Vector2i).

**Goal cell per croc:** `target == "tree"` → `_nearest_tree_cell_to(pos)`; else → `_world_to_cell(_player_pos)`.

**Plan:** `_nav.get_point_path(_world_to_cell(pos), goal_cell, true)` — `allow_partial_path = true` so a sealed/unreachable goal still yields a path to the nearest reachable cell (the wall face), where the croc chews. Store as `path`, reset `path_i = 0`, `plan_epoch = _nav_epoch`, `plan_goal = goal_cell`, stagger `replan_t`.

**Follow (replaces the `_flow_dir_from_pos` call at `Main.gd:1872-1876`):**
```
advance path_i while pos is within CELL_SIZE*0.4 of path[path_i]
chase_dir = (path[path_i] - pos).normalized()   # vector to current waypoint
# then the EXISTING blend, unchanged:
sep = _monster_separation(pos); if sep != 0 and not dig: chase_dir = (chase_dir + sep*0.35).normalized()
_move_monster_toward(m, chase_dir, delta, speed)
```

**Replan when ANY:** path empty / path_i past end and not at goal; `plan_epoch != _nav_epoch` (terrain changed); croc is player-aggro and player moved ≥ `FP_NAV_REPLAN_CELLS` (=2 ⟐) cells from `plan_goal`; `replan_t` elapsed (base `FP_NAV_REPLAN_SECS` = 0.4 ⟐, **offset per croc by index** so replans spread across frames, not all on one tick); blocked (net progress < half the intended step) for ≥ `FP_NAV_BLOCKED_FRAMES` (=8 ⟐) consecutive frames while NOT mid wall-chew (`brk_cd <= 0`).

**Performance:** 64×64 grid, ~36 crocs, staggered replans every ~0.4s ≈ ~90 queries/s, each microseconds. Well within budget. Do not replan every croc every frame.

## 5. Migration order (single stream, gate at each step)

1. Stand up `_nav` + solidity/weight build + `_set_terrain` sync, alongside the existing flow field (no behavior change yet). Selftest green.
2. Switch normal-croc direction source from `_flow_dir_from_pos` to the waypoint follower (§4). Keep sapper/wrecker on their paths.
3. Retire the now-dead `_field_tree`/`_field_player` recompute/tick/consumption (§2). Keep the sapper field.
4. Rebuild the probe + selftests (§7) and tune to pass the behavioral bar.

## 6. Radius backstop (contingency — implement only if §7 probe shows residual traps)

If the rebuilt solo probe still leaves a meaningful fraction wedged in tight gaps, make solidity **radius-aware**: a cell is solid-for-pathing if a body of `MONSTER_RADIUS` centered anywhere needed to traverse it would overlap a hard-impassable tile. Concretely, mark cell `c` solid if any impassable tile lies within `ceil(MONSTER_RADIUS/CELL_SIZE)` of `c` in a way that pinches the corridor below body width. (Since `MONSTER_RADIUS < CELL_SIZE/2`, a full 1-cell-wide gap stays passable; this only closes sub-body-width diagonal pinches.) Flag whether this was needed in the handoff report.

## 7. Acceptance — the metric that can't lie (Mode A — decided, load-bearing)

The whole point of this round. Rebuild the probe and gate on **arrival**, not absence-of-freeze.

**Solo probe** (`_pathing_probe_result`, `Main.gd:10002`): drive each croc with the NEW planner+follower (not `_flow_dir_from_pos`). Crocs start ≥18 cells from the tree. Run enough steps that any non-trapped croc arrives (≈1500). Report `reached`, plus a real classification of non-reachers: `walled_off` (goal genuinely unreachable from spawn — acceptable) vs `wedged` (reachable but stopped — a FAILURE). **Gate: `reached + walled_off ≥ 98%`; `wedged` ≈ 0.** Print the numbers (`PATHING_PROBE ...`).

**Crowded probe (NEW):** spawn many crocs at once into `_monsters` with `_monster_separation` active and a **moving player** goal; simulate a night-like burst; assert the same arrival bar. This catches crowd-jam the solo probe structurally cannot (the old probe ran one croc with `_monsters = []`). Add as a selftest.

**Update the three inline pathing asserts** (`Main.gd:10100/10126/10464`): "walkability agree" → now compares `_nav` solidity vs `_box_blocked` at `MONSTER_RADIUS`; "corner progress" → keep (radius body clears a corner); "detour through gap" → assert the `_nav` *path* goes through the gap. Keep the sapper integration test (`Main.gd:11993`) green — sappers are unchanged.

**Definition of done:** normal crocs plan and follow committed paths; the solo probe shows `reached ≥ 98%` of reachable crocs with `wedged ≈ 0`; the crowded probe meets the same bar; all five pathing-related selftests green; sapper + wrecker behavior unchanged; a real night plays with crocs visibly converging on the tree from across the map and breaking through sealed walls. All new tunables (`FP_NAV_*`) live in the one delimited block.

## Global invariants (unchanged)
Never reorder the `Terrain` enum (append only). Saves additive — new croc-dict keys default safely on old saves (`d.get`). Animated entities stay inside the redraw gate. All new tunables in the one delimited const block. If a decided thing can't be built as specified, STOP and flag it — don't hack around it.

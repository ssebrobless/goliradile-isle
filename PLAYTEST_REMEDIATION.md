# Goliradile Isle — Playtest Remediation Plan (Round 1)

**Status:** front-loaded design package, awaiting taste sign-off, then hand off to the technical implementer.
**Source:** a real playtest (build of `Main.gd` @ 12,388 lines) produced 12 numbered findings. Three read-only root-cause investigations located every one with `Main.gd:LINE` evidence; the fixes below are decided (with first-pass values) so the implementer makes **zero taste calls**.

**Architecture decision (finding #9):** *Keep the single file. Fix now, restructure later.* No `.tres`/GameDb/node-split in this round. Confirmed: the pathing bug is NOT a structure problem — `AStarGrid2D` would not have fixed it (see Cluster A). Structure is revisited only once gameplay is playtest-stable.

---

## Work modes (same as the build package)

- **Mode A — implement fully:** correctness fixes and decided mechanics. Build completely.
- **First-pass tunables (flagged ⟐):** numbers and copy that are *decided here* but expected to be felt-and-tuned in a later micro-pass. Wire them as named consts in the existing tunable block; do **not** "improve" them. These are NOT open taste calls for the implementer — the value in this doc is the value to ship.

**Global guardrails (unchanged from the build package):**
- Keep `--selftest` green at every step. A red harness is a blocker.
- Never reorder/insert into the `Terrain` enum (append only — saves store raw ints).
- Saves stay additive (`d.get(key, default)`); any new persisted field defaults safely on old saves.
- Keep animated entities inside the `queue_redraw` gate.
- All new tunables go in the one delimited tunable-const block.

---

## Cluster A — Croc pathing (finding #1) — THE KEYSTONE, highest priority

**Symptom (reproduced):** measured across 20 worlds / 384 crocs, **0 reached the Mother Tree; 51% were stuck the whole run.** Matches the playtest exactly.

**Root cause — it is NOT pathfinding.** The flow field is correct: it fills the whole map (no caps), the greedy fallback fires 0% of the time, and all natural obstacles (TREE/BUSH/STONE/COCONUT/BAMBOO/HIVE) are correctly `monster_walk:false`+impassable in `TILE_DEF` (`Main.gd:654-675`), so the field routes around them. The bug is a **agent-radius vs point-pather mismatch in collision/movement**:
- The field plans on cell centers and emits a **pure cardinal** direction (4-way), `_flow_dir_from_cell` (`Main.gd:1710-1727`; offset-array order, strict-less tie-break at `1724`).
- The collider `_box_blocked` (`Main.gd:3685`) blocks on the croc's **full radius box**; `MONSTER_RADIUS = CELL_SIZE*0.34 = 10.88` (diameter ≈ 68% of a 32px cell, spans up to 4 cells at a corner).
- `_move_collide` (`Main.gd:3674`) slides **per-axis**. When the field says "+x" but the +x box clips a diagonally-adjacent solid, x is blocked AND y is zero → **0 displacement, forever**. `_move_monster_toward` (`Main.gd:1957-1974`) has only a wall-*chew* probe gated on `break_hp > 0`; natural obstacles have `break_hp = 0`, so crocs never sidestep — they stop dead at `Main.gd:1966`.

**Why the old selftest passed (the blind spot):** the detour test (`Main.gd:10296`) checks only the field's *returned direction* at one cell; the walkability-agreement invariant (`Main.gd:9962`) runs the collider with a **zero-size box** (`hs=0.0`). At radius 0 pather and collider agree perfectly; at the real radius they disagree at every corner. The tests validated only the degenerate case.

### Decided fix (Mode A — measured: stuck-whole-run 194→89, reached-tree 0→35)

1. **8-directional gradient** — `_flow_dir_from_cell` (`Main.gd:1719`): add the 4 diagonals to the offset list. Allow a diagonal `(±1,±1)` **only if both** orthogonal cells `(±1,0)` and `(0,±1)` are monster-walkable (no corner-cutting between two solids). Keep a straight-beats-diagonal tie bias so open runs stay clean. This gives the per-axis slide a tangential component to escape corners.
2. **Perpendicular unstick** — `_move_monster_toward` (at `Main.gd:1966`): if the post-move displacement `< motion.length() * 0.5` and there is no breakable tile to chew, retry `_move_collide` along `(dir ± perpendicular)` and keep whichever advances. Frees crocs already wedged.
3. **Strengthen the tests so this can't regress:**
   - Re-run the walkability-agreement check (`Main.gd:9962`) with `hs = MONSTER_RADIUS`, not `0.0`.
   - Add an invariant: a radius-sized croc placed at an obstacle **corner** must make net positive progress toward the goal over N frames.

⟐ **Optional, do the structural fix regardless:** `MONSTER_RADIUS` could shrink to `≤ CELL_SIZE*0.25` to reduce trap frequency — but #1/#2 above are the correct fix; only consider the radius tweak if corner-stalls persist after.

**Acceptance:** new pathing simulation shows a substantial share of crocs reaching the Mother Tree across multiple seeds (not 0); the radius-aware tests pass; existing selftests stay green.

---

## Cluster B — Ground-item lifecycle: worms & bees (findings #10, #11)

**Symptom:** "purple orbs" from broken rocks and "honey orbs" on hives hang around permanently.

**Root cause:** They are uncollected **worm** and **bee** loot critters, and there is **no global ground-item despawn**. `_collect_ground_items` (`Main.gd:4144-4167`) special-cases worm/bee to require a held `glass_jar` (`4152-4157`); without one they are re-appended to `keep` every frame forever. The `t` field (`4140/4149`) is used only for the bob animation, never for despawn. The codebase already has TTL idioms elsewhere (banana peels `PEEL_GROUND_LIFE`, poison `POISON_TIME`) — ground loot just never got one. Spawn faucets vastly exceed recipe demand (worm → only worm-habitat/aquarium; honey → only `FP_SAP_CONVERSION["honey"]=2.0` at `Main.gd:52`; beeswax → only `reinforced_wall`).

### Decided fix (Mode A + ⟐ tunables)

1. **Add a global ground-item TTL.** New const `GROUND_ITEM_TTL = 90.0` ⟐. In `_collect_ground_items`, when an item's `g["t"]` exceeds the TTL, **drop it** instead of `keep.append`. Applies to all ground loot (worms, bees, and stray glapples at `Main.gd:1781`, which also never despawn).
   - **Guardrail:** the existing selftest at `Main.gd:11436-11443` asserts a jarless worm still exists after one `_collect_ground_items(0.05)` tick. With TTL=90 that still passes (0.05 ≪ 90) — do not break it.
2. **Cut the worm faucet** — rock-break drop at `Main.gd:4014-4022`: spawn chance `0.5 → 0.06` ⟐, and **remove the 1–2 doubling** (`4020`) so a rock yields at most one worm, rarely.
3. **Cut the bee faucet:** `HIVE_BEE_CHANCE` (`Main.gd:306`) `0.5 → 0.15` ⟐; hive-harvest bee drop (`Main.gd:4806`) `0.4 → 0.15` ⟐.

**Acceptance:** after several in-game days, ground loot does not accumulate unbounded; worms/bees appear at a trickle consistent with their recipe use; no selftest regressions.

---

## Cluster C — World density (finding #4)

**Symptom:** map feels cluttered; "tune almost all occurrences down."

**Root cause:** world-gen seeds and daily regrowth are both high; hives are the worst (over-seeded AND +1 every dawn).

### Decided fix — first-pass values (all ⟐)

**World-gen** `_generate_world` (`Main.gd:5532-5544`):

| Knob | Loc | Current | → Decided |
|---|---|---|---|
| STONE threshold `n >` | 5533 | 0.45 | **0.50** (raise = less stone) |
| TREE `randf <` | 5535 | 0.10 | **0.06** |
| BUSH `randf <` | 5537 | 0.04 | **0.02** |
| COCONUT `randf <` | 5539 | 0.025 | **0.012** |
| BAMBOO `randf <` | 5541 | 0.03 | **0.015** |
| HIVE `randf <` | 5543 | 0.012 | **0.004** |

**Daily regrowth** `_regrow_world` (`Main.gd:1751-1758`):

| Knob | Loc | Current | → Decided |
|---|---|---|---|
| `REGROW_TREES` | 372 | 6 | **3** |
| `REGROW_BUSHES` | 374 | 4 | **2** |
| COCONUT `range(2)` | 1756 | 2 | **1** |
| BAMBOO `range(2)` | 1757 | 2 | **1** |
| HIVE append | 1758 | 1 | **0** (remove the daily hive) |
| `REGROW_STONE` | 373 | 0 | **leave 0** (intentional — auto-miner replaces stone) |

**Acceptance:** a fresh world reads as open, not carpeted; resources still present and findable; no impact on reachability (the pathing field already routes around whatever spawns).

---

## Cluster D — UI overflow at high resolution (finding #2)

**Symptom:** maximized, the right panel's text clips past the edge ("…1 stone, 1 charcoal", "Banana x26").

**Root cause:** panels are a fixed `PANEL_W = 280.0` (`Main.gd:116`), built by `_make_panel` (`Main.gd:6173`), with horizontal scroll explicitly disabled (`Main.gd:6216`). The row controls — build buttons (`_build_build_panel`, `Main.gd:8077-8086`), craft buttons (`_build_craft_panel`, `Main.gd:7785-7788`), inventory labels (`_label`, `Main.gd:6309`) — never set `autowrap`, `clip_text`, or a bounded width, so each renders at full natural single-line width and is visually cut by the panel edge. `canvas_items` stretch + `aspect=keep` magnifies the overflow when maximized.

### Decided fix (Mode A)

- **Inventory labels** `_label` (`Main.gd:6309`): set `autowrap_mode = AUTOWRAP_WORD_SMART`.
- **Build & craft buttons** (`Main.gd:8082-8085`, `7785-7788`): set `size_flags_horizontal = SIZE_EXPAND_FILL` with a bounded `custom_minimum_size.x`, and enable wrapping (`autowrap_mode`) so the full cost string stays readable. (Prefer wrap over ellipsis here — cost text must not be truncated.)
- Bumping `PANEL_W` alone is not the fix (only delays the clip); bound the row width.

**Acceptance:** at maximized/high-res and at base 1280×720, no build/craft/inventory row text is clipped by the panel edge.

---

## Cluster E — Onboarding & legibility (findings #3, #5, #6, #7, #12; #8 is the meta)

**Shared root cause:** the rules exist in code but are **never surfaced.** Both fix surfaces already exist — the one-shot `_onboard(id, text, secs)` beat system (`Main.gd:3826`, registered in `ONBOARD_BEATS` `Main.gd:847`, persisted in `_onboard_seen`) and the `_tooltip_stat_line` / `_board_hover_target` / `_set_msg` surfaces. **No new infrastructure** — only new beat strings, trigger calls, and per-item surface fixes.

Copy below is **decided functional copy** (clear and correct; voice/flavor polish is a later micro-pass, not the implementer's call).

### #5 — Mother Tree interaction
- **State:** TECH/Sap hub opens *only* by clicking the tree while adjacent (`_click_interact`, `Main.gd:3737-3740`); no keybind, no prompt. `welcome` beat (`Main.gd:7185`) never mentions it.
- **Fix:** (a) amend the `welcome` string (`Main.gd:7185`) to include: *"Stand by the Mother Tree and click it to open its hub — deposit Sap there to grow it and unlock tech."* (b) Special-case `Terrain.MOTHER_TREE` in the hover block (`Main.gd:8364-8375`) to draw an "Open Tree hub" label so the tile is distinguishable from a bush.

### #6 — Tier-lock feedback
- **State:** rejections state the required tier number but never the cause/remedy — `_apply_build_at` (`Main.gd:3305-3307`), `_configure_turret` (`2350-2351`), `_craft` (`3892-3893`); menu suffix `*Tree T%d*` (`8078-8079`, `7625`).
- **Fix:** at the three rejection sites, replace the bare `_set_msg` with a one-shot `_onboard("tier_locked", …)`: *"Locked — needs Mother Tree tier N. Feed the Tree Sap at its hub to grow it and unlock this."* Make the always-visible menu suffix self-explanatory (e.g. "grow Tree→T2").

### #7 — Auto-miner
- **State:** must be placed on `Terrain.IRON_VEIN` (enforced `Main.gd:3272-3276` ghost, `3310-3314` apply); power not required but doubles output (`POWER_SPEED_MULT`, `Main.gd:4543`). The bad-placement branch is a **silent `return`** (`3310-3314`) — uniquely among placement failures. Taught nowhere.
- **Fix:** (a) add `_set_msg("Auto-Miner must be placed on an iron vein.")` to the silent branch (`Main.gd:3310-3314`). (b) add `_onboard("first_vein", "Iron veins mine themselves — place an Auto-Miner on one. Power it (Tree aura) to double output.")` fired when the player first nears a vein (mirror `first_den_seen`, `Main.gd:5277`). (c) fix the desc (`Main.gd:732`) to "Place ON an iron vein. Powered = 2× output."

### #3 — Grass collection
- **State:** grass comes from clicking the plain `Terrain.GRASS` floor tile (`_click_interact`, `Main.gd:3768-3774`); visually identical to the floor; `_board_hover_target` (`Main.gd:1313-1328`) returns `["",""]` for it. `welcome` says only "wood and stone."
- **Fix:** add a grass case to `_board_hover_target` (`Main.gd:1313-1328`) returning a gatherable so the existing tooltip shows *"Click bare grass to pull fibers (for string)."* Add grass to the `welcome` beat line (`Main.gd:7185`).

### #12 — Tool upgrades
- **State:** better tools raise **yield** (`+_tool_bonus`, applied at `Main.gd:3993/4007/4016`) and lower **energy** (`_tool_energy_mult`, `4026`) — *not* speed. `TOOL_DEFS` (`Main.gd:392-396`): stone `+1 / 0.6×`, metal `+2 / 0.4×`. `_tooltip_stat_line` (`Main.gd:7689-7746`) has **no tool branch** → hovering a tool shows nothing. `ITEM_DESC` (`Main.gd:247-248`) says "Mines faster/fastest" — **wrong** (no speed effect).
- **Fix:** add a tool case to `_tooltip_stat_line` (`Main.gd:7689`) reading `TOOL_DEFS` directly: *"+N gather · uses M% energy."* Correct the misleading `ITEM_DESC` strings (`Main.gd:247-248`) to describe yield + stamina, not speed.

### #7-onboarding summary (what's currently taught vs. not)
Existing beats: `welcome`, `first_hunger`, `first_thirst`, `day2_dusk`, `first_turret`, `first_night`, `casings`, `tier_up`, `first_den_seen`. **Add:** `tier_locked`, `first_vein`, grass + tree-interaction (folded into `welcome`), and a tool-effect surface (tooltip, above). All new ids appended to `ONBOARD_BEATS` (`Main.gd:847`); none reorder existing ids.

**Acceptance:** a first-time player is told, at the natural moment, how to grow the Mother Tree, why a build is tier-locked and how to unlock it, what the auto-miner needs, where grass comes from, and what a better tool actually does — all via the existing beat/tooltip systems.

---

## Build order (single stream, selftest green at each step)

1. **Cluster A (pathing)** — keystone; verify with the new radius-aware sim/tests before anything else.
2. **Cluster B (ground-item TTL + spawn cuts)** — keep the worm-stays selftest passing.
3. **Cluster C (density consts)** — pure tunable edits.
4. **Cluster D (panel row wrapping)** — UI only.
5. **Cluster E (onboarding + tooltips + rejection messages)** — last; touches the most surfaces, lowest risk.

Each cluster: make the edits, run `--selftest`, report green + a one-line summary before the next.

## Definition of done
All five clusters landed; `--selftest` green (with the strengthened radius-aware pathing checks); a fresh playthrough shows crocs reaching the tree, no permanent ground clutter, an open-feeling map, no clipped panel text, and the five legibility beats firing at the right moments. All new numbers live in the one tunable block for the next feel pass.
